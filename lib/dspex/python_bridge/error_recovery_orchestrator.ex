defmodule DSPex.PythonBridge.ErrorRecoveryOrchestrator do
  @moduledoc """
  Orchestrates complex error recovery scenarios across the pool system.

  This module coordinates sophisticated error recovery strategies that may involve
  multiple steps, async execution, and integration with various recovery mechanisms
  like circuit breakers, retry logic, and failover adapters.

  ## Features

  - Async recovery execution to avoid blocking operations
  - Context-aware recovery strategy selection
  - Integration with existing ErrorHandler and WorkerRecovery
  - Comprehensive metrics and telemetry
  - Configurable recovery strategies per error type
  - Fallback adapter coordination

  ## Recovery Strategies

  - `:retry_with_backoff` - Use RetryLogic with exponential backoff
  - `:failover` - Switch to fallback adapter
  - `:circuit_break` - Trigger circuit breaker protection
  - `:abandon` - Fail immediately without recovery attempt
  - `:custom` - Use custom recovery function

  ## Usage

      # Handle error with automatic recovery
      ErrorRecoveryOrchestrator.handle_error(error, context)
      
      # Check recovery status
      ErrorRecoveryOrchestrator.get_recovery_status(recovery_id)
      
      # Get recovery metrics
      ErrorRecoveryOrchestrator.get_metrics()
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker, RetryLogic}
  alias DSPex.Adapters.Factory

  defstruct [
    :recovery_strategies,
    :active_recoveries,
    :metrics,
    :config
  ]

  @type recovery_action :: :retry_with_backoff | :failover | :circuit_break | :abandon | :custom

  @type recovery_strategy :: %{
          type: recovery_action(),
          max_attempts: pos_integer(),
          backoff: atom(),
          circuit_breaker: atom() | nil,
          fallback_adapter: module() | nil,
          max_recovery_time: pos_integer(),
          custom_function: function() | nil
        }

  @type recovery_state :: %{
          id: String.t(),
          error: map(),
          strategy: recovery_strategy(),
          started_at: integer(),
          from: GenServer.from() | nil,
          task_ref: reference() | nil
        }

  ## Public API

  @doc """
  Starts the error recovery orchestrator.

  ## Options

  - `:name` - Process name (default: __MODULE__)
  - `:strategies` - Custom recovery strategy configuration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Handles an error with appropriate recovery strategy.

  This function analyzes the error and context to determine the best recovery
  approach, then executes the recovery asynchronously while providing immediate
  feedback to the caller.

  ## Parameters

  - `error` - The error to recover from
  - `context` - Additional context about the error situation

  ## Returns

  - `{:ok, {:recovered, result}}` - Recovery succeeded immediately
  - `{:ok, {:failover, result}}` - Failover succeeded
  - `{:ok, {:recovery_started, recovery_id}}` - Async recovery initiated
  - `{:error, reason}` - Recovery not possible
  """
  @spec handle_error(term(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:adapter) => module(),
          optional(:user_facing) => boolean(),
          optional(:original_operation) => function(),
          optional(:args) => list() | map(),
          optional(atom()) => term()
        }) :: {:ok, term()} | {:error, term()}
  def handle_error(error, context) do
    GenServer.call(__MODULE__, {:handle_error, error, context}, 30_000)
  end

  @doc """
  Gets the status of an active recovery operation.

  ## Parameters

  - `recovery_id` - ID returned from handle_error

  ## Returns

  - `{:ok, status}` - Recovery status information
  - `{:error, :not_found}` - Recovery ID not found
  """
  @spec get_recovery_status(String.t()) ::
          {:ok,
           %{
             id: String.t(),
             error_category: atom(),
             strategy: atom(),
             started_at: integer(),
             duration: integer(),
             status: :in_progress
           }}
          | {:error, :not_found}
  def get_recovery_status(recovery_id) do
    GenServer.call(__MODULE__, {:get_recovery_status, recovery_id})
  end

  @doc """
  Gets current recovery metrics and statistics.

  ## Returns

  Map with recovery metrics including success rates, timing, and active recoveries.
  """
  @spec get_metrics() :: %{
          recoveries_initiated: non_neg_integer(),
          recoveries_succeeded: non_neg_integer(),
          recoveries_failed: non_neg_integer(),
          recoveries_cancelled: non_neg_integer(),
          avg_recovery_time: non_neg_integer(),
          total_recovery_time: non_neg_integer(),
          active_recoveries: non_neg_integer(),
          success_rate: float()
        }
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Cancels an active recovery operation.

  ## Parameters

  - `recovery_id` - ID of recovery to cancel

  ## Returns

  `:ok` or `{:error, :not_found}`
  """
  @spec cancel_recovery(String.t()) :: :ok | {:error, :not_found}
  def cancel_recovery(recovery_id) do
    GenServer.call(__MODULE__, {:cancel_recovery, recovery_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      recovery_strategies: load_recovery_strategies(opts),
      active_recoveries: %{},
      metrics: %{
        recoveries_initiated: 0,
        recoveries_succeeded: 0,
        recoveries_failed: 0,
        recoveries_cancelled: 0,
        avg_recovery_time: 0,
        total_recovery_time: 0
      },
      config: %{
        max_concurrent_recoveries: Keyword.get(opts, :max_concurrent, 10),
        default_timeout: Keyword.get(opts, :default_timeout, 30_000)
      }
    }

    Logger.info(
      "ErrorRecoveryOrchestrator started with #{map_size(state.recovery_strategies)} strategies"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:handle_error, error, context}, from, state) do
    if map_size(state.active_recoveries) >= state.config.max_concurrent_recoveries do
      Logger.warning("Recovery orchestrator at capacity, rejecting new recovery request")
      {:reply, {:error, :recovery_capacity_exceeded}, state}
    else
      wrapped_error = PoolErrorHandler.wrap_pool_error(error, context)
      recovery_id = generate_recovery_id()

      # Determine recovery strategy
      strategy = determine_recovery_strategy(wrapped_error, state)

      case strategy.type do
        :abandon ->
          Logger.info(
            "Error recovery abandoned based on strategy: #{inspect(wrapped_error.error_category)}"
          )

          {:reply, {:error, :recovery_abandoned}, state}

        :circuit_break ->
          # Immediate circuit breaker action
          if strategy.circuit_breaker do
            CircuitBreaker.record_failure(strategy.circuit_breaker, error)
          end

          {:reply, {:error, :circuit_break_triggered}, state}

        _ ->
          # Start async recovery
          recovery_state = %{
            id: recovery_id,
            error: wrapped_error,
            strategy: strategy,
            started_at: System.monotonic_time(:millisecond),
            from: from,
            task_ref: nil
          }

          # Start recovery task
          task =
            Task.async(fn ->
              execute_recovery(recovery_state)
            end)

          updated_recovery = %{recovery_state | task_ref: task.ref}

          new_state = %{
            state
            | active_recoveries: Map.put(state.active_recoveries, recovery_id, updated_recovery),
              metrics: Map.update!(state.metrics, :recoveries_initiated, &(&1 + 1))
          }

          Logger.info(
            "Started recovery #{recovery_id} for #{wrapped_error.error_category} with strategy #{strategy.type}"
          )

          # Don't reply yet - will reply when recovery completes
          {:noreply, new_state}
      end
    end
  end

  @impl true
  def handle_call({:get_recovery_status, recovery_id}, _from, state) do
    case Map.get(state.active_recoveries, recovery_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      recovery ->
        status = %{
          id: recovery.id,
          error_category: recovery.error.error_category,
          strategy: recovery.strategy.type,
          started_at: recovery.started_at,
          duration: System.monotonic_time(:millisecond) - recovery.started_at,
          status: :in_progress
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    enhanced_metrics =
      Map.merge(state.metrics, %{
        active_recoveries: map_size(state.active_recoveries),
        success_rate: calculate_success_rate(state.metrics)
      })

    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:cancel_recovery, recovery_id}, _from, state) do
    case Map.get(state.active_recoveries, recovery_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      recovery ->
        # Cancel the task
        if recovery.task_ref do
          _result = Task.shutdown(recovery.task_ref, :brutal_kill)
          :ok
        end

        # Reply to original caller if waiting
        if recovery.from do
          GenServer.reply(recovery.from, {:error, :recovery_cancelled})
        end

        Logger.info("Recovery #{recovery_id} cancelled")

        new_state = %{
          state
          | active_recoveries: Map.delete(state.active_recoveries, recovery_id),
            metrics: Map.update!(state.metrics, :recoveries_cancelled, &(&1 + 1))
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find recovery by task ref and handle completion
    case find_recovery_by_ref(state.active_recoveries, ref) do
      {recovery_id, recovery} ->
        handle_recovery_completion(recovery_id, recovery, {:error, {:task_failed, reason}}, state)

      nil ->
        Logger.warning("Received DOWN message for unknown task ref: #{inspect(ref)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completion message
    case find_recovery_by_ref(state.active_recoveries, ref) do
      {recovery_id, recovery} ->
        handle_recovery_completion(recovery_id, recovery, result, state)

      nil ->
        {:noreply, state}
    end
  end

  ## Private Functions

  @spec load_recovery_strategies(keyword()) :: %{
          communication_error: term(),
          connection_error: term(),
          health_check_error: term(),
          initialization_error: term(),
          python_error: term(),
          resource_error: term(),
          session_error: term(),
          system_error: term(),
          timeout_error: term()
        }
  defp load_recovery_strategies(opts) do
    custom_strategies = Keyword.get(opts, :strategies, %{})

    default_strategies = %{
      connection_error: %{
        critical: %{type: :circuit_break, circuit_breaker: :pool_connections},
        major: %{type: :retry_with_backoff, max_attempts: 5, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      timeout_error: %{
        critical: %{type: :abandon},
        major: %{type: :retry_with_backoff, max_attempts: 2, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      resource_error: %{
        critical: %{type: :circuit_break, circuit_breaker: :pool_resources},
        major: %{type: :failover, fallback_adapter: DSPex.Adapters.Mock},
        minor: %{type: :retry_with_backoff, max_attempts: 2, backoff: :linear}
      },
      python_error: %{
        critical: %{type: :failover, fallback_adapter: DSPex.Adapters.Mock},
        major: %{type: :failover, fallback_adapter: DSPex.Adapters.Mock},
        minor: %{type: :retry_with_backoff, max_attempts: 2, backoff: :linear}
      },
      initialization_error: %{
        critical: %{type: :circuit_break, circuit_breaker: :worker_initialization},
        major: %{type: :retry_with_backoff, max_attempts: 3, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 2, backoff: :linear}
      },
      communication_error: %{
        critical: %{type: :circuit_break, circuit_breaker: :communication_failures},
        major: %{type: :retry_with_backoff, max_attempts: 3, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      health_check_error: %{
        critical: %{type: :abandon},
        major: %{type: :retry_with_backoff, max_attempts: 2, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      session_error: %{
        critical: %{type: :abandon},
        major: %{type: :retry_with_backoff, max_attempts: 2, backoff: :linear},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      system_error: %{
        critical: %{type: :abandon},
        major: %{type: :abandon},
        minor: %{type: :abandon}
      }
    }

    Map.merge(default_strategies, custom_strategies)
  end

  @spec determine_recovery_strategy(map(), %__MODULE__{}) :: recovery_strategy()
  defp determine_recovery_strategy(wrapped_error, state) do
    category = wrapped_error.error_category
    severity = wrapped_error.severity

    # Get base strategy from configuration
    base_strategy =
      get_in(state.recovery_strategies, [category, severity]) ||
        get_in(state.recovery_strategies, [category, :major]) ||
        %{type: :abandon}

    # Enhance with context-specific adjustments
    enhance_strategy(base_strategy, wrapped_error)
  end

  @spec enhance_strategy(map(), map()) :: recovery_strategy()
  defp enhance_strategy(base_strategy, wrapped_error) do
    Map.merge(
      %{
        type: :abandon,
        max_attempts: 3,
        backoff: :exponential,
        circuit_breaker: nil,
        fallback_adapter: nil,
        max_recovery_time: 30_000,
        custom_function: nil
      },
      base_strategy
    )
    |> Map.merge(%{
      circuit_breaker: get_circuit_breaker_name(wrapped_error),
      fallback_adapter: get_fallback_adapter(wrapped_error),
      max_recovery_time: calculate_max_recovery_time(wrapped_error)
    })
  end

  @spec execute_recovery(recovery_state()) :: {:ok, term()} | {:error, term()}
  defp execute_recovery(recovery_state) do
    strategy = recovery_state.strategy
    error = recovery_state.error

    Logger.info("Executing recovery #{recovery_state.id} with strategy #{strategy.type}")

    try do
      result =
        case strategy.type do
          :retry_with_backoff ->
            execute_retry_recovery(error, strategy)

          :failover ->
            execute_failover_recovery(error, strategy)

          :circuit_break ->
            {:error, :circuit_opened}

          :custom ->
            execute_custom_recovery(error, strategy)

          _ ->
            {:error, :unknown_strategy}
        end

      case result do
        {:ok, _} = success ->
          Logger.info("Recovery #{recovery_state.id} succeeded")
          success

        {:error, reason} ->
          Logger.error("Recovery #{recovery_state.id} failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      kind, error ->
        Logger.error("Recovery #{recovery_state.id} crashed: #{kind} - #{inspect(error)}")
        {:error, {:recovery_crashed, {kind, error}}}
    end
  end

  @spec execute_retry_recovery(PoolErrorHandler.t(), recovery_strategy()) ::
          {:ok, term()} | {:error, :no_original_operation | PoolErrorHandler.t()}
  defp execute_retry_recovery(error, strategy) do
    context = error.context

    # Recreate the original operation if possible
    case Map.get(context, :original_operation) do
      nil ->
        {:error, :no_original_operation}

      operation_fun ->
        RetryLogic.with_retry(
          operation_fun,
          max_attempts: strategy.max_attempts,
          backoff: strategy.backoff,
          circuit: strategy.circuit_breaker
        )
    end
  end

  @spec execute_failover_recovery(PoolErrorHandler.t(), recovery_strategy()) ::
          {:ok, {:failover, term()}}
          | {:error, {:failover_failed, DSPex.Adapters.ErrorHandler.adapter_error()}}
  defp execute_failover_recovery(error, strategy) do
    adapter = strategy.fallback_adapter
    context = error.context
    operation = Map.get(context, :operation)
    args = Map.get(context, :args, [])

    Logger.info("Attempting failover to #{adapter}")

    case Factory.execute_with_adapter(adapter, operation, args, test_layer: :layer_1) do
      {:ok, result} ->
        Logger.info("Failover to #{adapter} succeeded")
        {:ok, {:failover, result}}

      {:error, reason} ->
        Logger.error("Failover to #{adapter} failed: #{inspect(reason)}")
        {:error, {:failover_failed, reason}}
    end
  end

  @spec execute_custom_recovery(PoolErrorHandler.t(), recovery_strategy()) ::
          {:ok, term()} | {:error, term()}
  defp execute_custom_recovery(error, strategy) do
    case strategy.custom_function do
      nil ->
        {:error, :no_custom_function}

      fun when is_function(fun, 1) ->
        fun.(error)

      _ ->
        {:error, :invalid_custom_function}
    end
  end

  @spec handle_recovery_completion(String.t(), recovery_state(), term(), %__MODULE__{}) ::
          {:noreply, %__MODULE__{}}
  defp handle_recovery_completion(recovery_id, recovery, result, state) do
    duration = System.monotonic_time(:millisecond) - recovery.started_at

    # Reply to original caller if waiting
    if recovery.from do
      GenServer.reply(recovery.from, result)
    end

    # Update metrics
    {_metric_key, new_metrics} =
      case result do
        {:ok, _} ->
          {:recoveries_succeeded, update_success_metrics(state.metrics, duration)}

        _ ->
          {:recoveries_failed, Map.update!(state.metrics, :recoveries_failed, &(&1 + 1))}
      end

    # Emit telemetry
    emit_telemetry(:recovery_complete, %{duration: duration}, %{
      recovery_id: recovery_id,
      error_category: recovery.error.error_category,
      strategy: recovery.strategy.type,
      result: elem(result, 0)
    })

    new_state = %{
      state
      | active_recoveries: Map.delete(state.active_recoveries, recovery_id),
        metrics: new_metrics
    }

    {:noreply, new_state}
  end

  @spec find_recovery_by_ref(map(), reference()) :: {String.t(), recovery_state()} | nil
  defp find_recovery_by_ref(recoveries, ref) do
    Enum.find(recoveries, fn {_id, recovery} -> recovery.task_ref == ref end)
  end

  @spec generate_recovery_id() :: String.t()
  defp generate_recovery_id do
    "recovery_#{System.unique_integer([:positive])}_#{System.os_time(:nanosecond)}"
  end

  @spec get_circuit_breaker_name(PoolErrorHandler.t()) ::
          :pool_connections | :pool_resources | :worker_initialization | nil
  defp get_circuit_breaker_name(error) do
    case error.error_category do
      :connection_error -> :pool_connections
      :resource_error -> :pool_resources
      :initialization_error -> :worker_initialization
      _ -> nil
    end
  end

  @spec get_fallback_adapter(PoolErrorHandler.t()) ::
          DSPex.Adapters.Mock | DSPex.Adapters.PythonPort
  defp get_fallback_adapter(error) do
    case Map.get(error.context, :adapter) do
      DSPex.PythonBridge.SessionPoolV2 -> DSPex.Adapters.PythonPort
      DSPex.Adapters.PythonPort -> DSPex.Adapters.Mock
      _ -> DSPex.Adapters.Mock
    end
  end

  @spec calculate_max_recovery_time(PoolErrorHandler.t()) ::
          2500 | 5000 | 10000 | 15000 | 30000 | 60000
  defp calculate_max_recovery_time(error) do
    base_time =
      case error.severity do
        :critical -> 5_000
        :major -> 30_000
        :minor -> 60_000
        _ -> 10_000
      end

    # Adjust based on context
    context = error.context
    if Map.get(context, :user_facing), do: div(base_time, 2), else: base_time
  end

  @spec update_success_metrics(map(), integer()) :: %{
          :avg_recovery_time => integer(),
          :total_recovery_time => integer(),
          optional(atom()) => term()
        }
  defp update_success_metrics(metrics, duration) do
    current_total = Map.get(metrics, :total_recovery_time, 0)
    current_count = Map.get(metrics, :recoveries_succeeded, 0)

    new_total = current_total + duration
    new_count = current_count + 1
    new_avg = div(new_total, new_count)

    metrics
    |> Map.update!(:recoveries_succeeded, &(&1 + 1))
    |> Map.put(:total_recovery_time, new_total)
    |> Map.put(:avg_recovery_time, new_avg)
  end

  @spec calculate_success_rate(map()) :: float()
  defp calculate_success_rate(metrics) do
    total = metrics.recoveries_succeeded + metrics.recoveries_failed

    if total > 0 do
      metrics.recoveries_succeeded / total
    else
      0.0
    end
  end

  @spec emit_telemetry(:recovery_complete, %{duration: integer()}, %{
          recovery_id: binary(),
          error_category: atom(),
          strategy: atom(),
          result: atom()
        }) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    try do
      :telemetry.execute(
        [:dspex, :recovery, event],
        measurements,
        metadata
      )
    rescue
      _ ->
        # Telemetry not available, log instead
        Logger.debug("Recovery #{event}: #{inspect(measurements)} - #{inspect(metadata)}")
    end

    :ok
  end
end

# V2 Pool Technical Design Series: Document 4 - Error Handling and Recovery Strategy

## Overview

This document details the comprehensive error handling and recovery system for Phase 3. It builds upon the existing `ErrorHandler` infrastructure to create a robust, multi-layered error management system with retry logic, circuit breakers, and graceful degradation.

## Error Classification and Hierarchy

### Error Categories

```elixir
@type error_category :: 
  :initialization_error |    # Worker startup failures
  :connection_error |        # Port/process connection issues
  :communication_error |     # Protocol/encoding errors
  :timeout_error |          # Operation timeouts
  :resource_error |         # Resource exhaustion
  :health_check_error |     # Health monitoring failures
  :session_error |          # Session management issues
  :python_error |           # Python-side exceptions
  :system_error             # System-level failures

@type error_severity :: :critical | :major | :minor | :warning

@type recovery_strategy :: :immediate_retry | :backoff_retry | :circuit_break | :failover | :abandon
```

### Error Decision Matrix

| Error Category | Severity | Recovery Strategy | Max Retries | Backoff |
|----------------|----------|-------------------|-------------|---------|
| initialization_error | critical | circuit_break | 3 | exponential |
| connection_error | major | backoff_retry | 5 | exponential |
| communication_error | major | immediate_retry | 3 | linear |
| timeout_error | major | backoff_retry | 2 | exponential |
| resource_error | critical | circuit_break | 1 | none |
| health_check_error | minor | backoff_retry | 3 | linear |
| session_error | minor | immediate_retry | 2 | none |
| python_error | major | failover | 1 | none |
| system_error | critical | abandon | 0 | none |

## Enhanced Error Handler

**File:** `lib/dspex/python_bridge/pool_error_handler.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.PoolErrorHandler do
  @moduledoc """
  Comprehensive error handling for pool operations with recovery strategies.
  """
  
  alias DSPex.Adapters.ErrorHandler
  require Logger
  
  @type error_context :: %{
    error_category: atom(),
    severity: atom(),
    worker_id: String.t() | nil,
    session_id: String.t() | nil,
    operation: atom(),
    attempt: non_neg_integer(),
    metadata: map()
  }
  
  @retry_delays %{
    immediate_retry: [0, 100, 200],
    backoff_retry: [1_000, 2_000, 4_000, 8_000, 16_000],
    exponential: [1_000, 3_000, 9_000, 27_000]
  }
  
  @doc "Wraps pool-specific errors with context and recovery information"
  def wrap_pool_error(error, context) do
    category = categorize_error(error)
    severity = determine_severity(category, context)
    strategy = determine_recovery_strategy(category, severity, context)
    
    enhanced_context = Map.merge(context, %{
      error_category: category,
      severity: severity,
      recovery_strategy: strategy,
      timestamp: System.os_time(:millisecond)
    })
    
    wrapped = ErrorHandler.wrap_error(error, enhanced_context)
    
    # Add pool-specific fields
    Map.merge(wrapped, %{
      __struct__: __MODULE__,
      pool_error: true,
      recovery_strategy: strategy
    })
  end
  
  @doc "Determines if an error should trigger a retry"
  def should_retry?(wrapped_error, attempt \\ 1) do
    case wrapped_error.recovery_strategy do
      :immediate_retry -> attempt <= 3
      :backoff_retry -> attempt <= 5
      :circuit_break -> false  # Let circuit breaker handle
      :failover -> attempt == 1
      :abandon -> false
      _ -> ErrorHandler.should_retry?(wrapped_error)
    end
  end
  
  @doc "Calculates retry delay based on strategy and attempt"
  def get_retry_delay(wrapped_error, attempt) do
    strategy = wrapped_error.recovery_strategy
    delays = Map.get(@retry_delays, strategy, [1_000])
    
    # Get delay for attempt, or last delay if beyond array
    Enum.at(delays, attempt - 1, List.last(delays))
  end
  
  defp categorize_error(error) do
    case error do
      {:port_exited, _} -> :connection_error
      {:connect_failed, _} -> :connection_error
      {:checkout_failed, _} -> :resource_error
      {:timeout, _} -> :timeout_error
      {:encode_error, _} -> :communication_error
      {:decode_error, _} -> :communication_error
      {:health_check_failed, _} -> :health_check_error
      {:python_exception, _} -> :python_error
      {:init_failed, _} -> :initialization_error
      {:session_not_found, _} -> :session_error
      _ -> :system_error
    end
  end
  
  defp determine_severity(category, context) do
    base_severity = case category do
      :initialization_error -> :critical
      :resource_error -> :critical
      :system_error -> :critical
      :connection_error -> :major
      :communication_error -> :major
      :timeout_error -> :major
      :python_error -> :major
      :health_check_error -> :minor
      :session_error -> :minor
      _ -> :warning
    end
    
    # Adjust based on context
    cond do
      context[:attempt] > 3 -> upgrade_severity(base_severity)
      context[:affecting_all_workers] -> :critical
      true -> base_severity
    end
  end
  
  defp upgrade_severity(:minor), do: :major
  defp upgrade_severity(:major), do: :critical
  defp upgrade_severity(severity), do: severity
  
  defp determine_recovery_strategy(category, severity, context) do
    case {category, severity} do
      {_, :critical} when context[:attempt] > 2 -> :abandon
      {:resource_error, :critical} -> :circuit_break
      {:initialization_error, _} -> :circuit_break
      {:connection_error, _} -> :backoff_retry
      {:timeout_error, _} -> :backoff_retry
      {:communication_error, :major} -> :immediate_retry
      {:health_check_error, _} -> :backoff_retry
      {:session_error, _} -> :immediate_retry
      {:python_error, _} -> :failover
      _ -> :abandon
    end
  end
  
  @doc "Formats error for logging with full context"
  def format_for_logging(wrapped_error) do
    """
    Pool Error: #{wrapped_error.message}
    Category: #{wrapped_error.error_category}
    Severity: #{wrapped_error.severity}
    Recovery: #{wrapped_error.recovery_strategy}
    Worker: #{wrapped_error.context[:worker_id] || "N/A"}
    Session: #{wrapped_error.context[:session_id] || "N/A"}
    Attempt: #{wrapped_error.context[:attempt] || 1}
    Context: #{inspect(wrapped_error.context, pretty: true)}
    """
  end
end
```

## Circuit Breaker Implementation

**File:** `lib/dspex/python_bridge/circuit_breaker.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for pool operations to prevent cascading failures.
  """
  
  use GenServer
  require Logger
  
  @type state :: :closed | :open | :half_open
  @type circuit :: %{
    name: atom(),
    state: state(),
    failure_count: non_neg_integer(),
    success_count: non_neg_integer(),
    last_failure: integer() | nil,
    last_state_change: integer(),
    config: map()
  }
  
  @default_config %{
    failure_threshold: 5,      # Failures to open circuit
    success_threshold: 3,      # Successes to close from half-open
    timeout: 60_000,          # Time before half-open attempt
    half_open_requests: 3     # Max requests in half-open state
  }
  
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def init(opts) do
    circuits = %{}
    {:ok, circuits}
  end
  
  @doc "Executes a function through the circuit breaker"
  def with_circuit(circuit_name, fun, opts \\ []) do
    GenServer.call(__MODULE__, {:execute, circuit_name, fun, opts})
  end
  
  @doc "Records a success for a circuit"
  def record_success(circuit_name) do
    GenServer.cast(__MODULE__, {:record_success, circuit_name})
  end
  
  @doc "Records a failure for a circuit"
  def record_failure(circuit_name, error) do
    GenServer.cast(__MODULE__, {:record_failure, circuit_name, error})
  end
  
  @doc "Gets the current state of a circuit"
  def get_state(circuit_name) do
    GenServer.call(__MODULE__, {:get_state, circuit_name})
  end
  
  @doc "Manually resets a circuit"
  def reset(circuit_name) do
    GenServer.call(__MODULE__, {:reset, circuit_name})
  end
  
  # Server callbacks
  
  def handle_call({:execute, circuit_name, fun, opts}, _from, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, opts)
    
    case circuit.state do
      :closed ->
        # Circuit is closed, execute normally
        execute_and_track(circuit, fun, circuits)
        
      :open ->
        # Circuit is open, check if we should transition to half-open
        if should_attempt_reset?(circuit) do
          new_circuit = %{circuit | state: :half_open, success_count: 0}
          execute_and_track(new_circuit, fun, circuits)
        else
          error = {:circuit_open, circuit_name}
          {:reply, {:error, PoolErrorHandler.wrap_pool_error(error, %{
            circuit: circuit_name,
            time_until_retry: time_until_retry(circuit)
          })}, circuits}
        end
        
      :half_open ->
        # Circuit is half-open, limited requests allowed
        if circuit.success_count < circuit.config.half_open_requests do
          execute_and_track(circuit, fun, circuits)
        else
          # Wait for results of in-flight requests
          {:reply, {:error, {:circuit_half_open_limit, circuit_name}}, circuits}
        end
    end
  end
  
  def handle_call({:get_state, circuit_name}, _from, circuits) do
    circuit = Map.get(circuits, circuit_name)
    state = if circuit, do: circuit.state, else: :not_found
    {:reply, state, circuits}
  end
  
  def handle_call({:reset, circuit_name}, _from, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, [])
    new_circuit = %{circuit | 
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure: nil,
      last_state_change: System.monotonic_time(:millisecond)
    }
    
    {:reply, :ok, Map.put(circuits, circuit_name, new_circuit)}
  end
  
  def handle_cast({:record_success, circuit_name}, circuits) do
    circuit = Map.get(circuits, circuit_name)
    
    if circuit do
      new_circuit = handle_success(circuit)
      {:noreply, Map.put(circuits, circuit_name, new_circuit)}
    else
      {:noreply, circuits}
    end
  end
  
  def handle_cast({:record_failure, circuit_name, error}, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, [])
    new_circuit = handle_failure(circuit, error)
    {:noreply, Map.put(circuits, circuit_name, new_circuit)}
  end
  
  # Private functions
  
  defp get_or_create_circuit(circuits, name, opts) do
    Map.get(circuits, name, %{
      name: name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure: nil,
      last_state_change: System.monotonic_time(:millisecond),
      config: Keyword.get(opts, :config, @default_config)
    })
  end
  
  defp execute_and_track(circuit, fun, circuits) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      duration = System.monotonic_time(:millisecond) - start_time
      
      emit_telemetry(circuit.name, :success, duration)
      
      new_circuit = handle_success(circuit)
      {:reply, result, Map.put(circuits, circuit.name, new_circuit)}
    catch
      kind, error ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        emit_telemetry(circuit.name, :failure, duration)
        
        new_circuit = handle_failure(circuit, {kind, error})
        wrapped_error = PoolErrorHandler.wrap_pool_error(
          {:circuit_execution_failed, {kind, error}},
          %{circuit: circuit.name, duration: duration}
        )
        
        {:reply, {:error, wrapped_error}, Map.put(circuits, circuit.name, new_circuit)}
    end
  end
  
  defp handle_success(circuit) do
    case circuit.state do
      :closed ->
        # Reset failure count on success
        %{circuit | failure_count: 0}
        
      :half_open ->
        # Count successes in half-open state
        new_count = circuit.success_count + 1
        
        if new_count >= circuit.config.success_threshold do
          # Enough successes, close the circuit
          Logger.info("Circuit #{circuit.name} closed after successful recovery")
          %{circuit | 
            state: :closed,
            failure_count: 0,
            success_count: 0,
            last_state_change: System.monotonic_time(:millisecond)
          }
        else
          %{circuit | success_count: new_count}
        end
        
      :open ->
        # Shouldn't happen, but handle gracefully
        circuit
    end
  end
  
  defp handle_failure(circuit, error) do
    new_failure_count = circuit.failure_count + 1
    now = System.monotonic_time(:millisecond)
    
    new_circuit = %{circuit | 
      failure_count: new_failure_count,
      last_failure: now
    }
    
    case circuit.state do
      :closed when new_failure_count >= circuit.config.failure_threshold ->
        # Open the circuit
        Logger.error("Circuit #{circuit.name} opened after #{new_failure_count} failures")
        %{new_circuit | 
          state: :open,
          last_state_change: now
        }
        
      :half_open ->
        # Single failure in half-open returns to open
        Logger.warn("Circuit #{circuit.name} reopened after failure in half-open state")
        %{new_circuit | 
          state: :open,
          success_count: 0,
          last_state_change: now
        }
        
      _ ->
        new_circuit
    end
  end
  
  defp should_attempt_reset?(circuit) do
    time_since_failure = System.monotonic_time(:millisecond) - (circuit.last_failure || 0)
    time_since_failure >= circuit.config.timeout
  end
  
  defp time_until_retry(circuit) do
    time_since_failure = System.monotonic_time(:millisecond) - (circuit.last_failure || 0)
    max(0, circuit.config.timeout - time_since_failure)
  end
  
  defp emit_telemetry(circuit_name, result, duration) do
    :telemetry.execute(
      [:dspex, :circuit_breaker, result],
      %{duration: duration},
      %{circuit: circuit_name}
    )
  end
end
```

## Retry Logic Implementation

**File:** `lib/dspex/python_bridge/retry_logic.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.RetryLogic do
  @moduledoc """
  Implements sophisticated retry logic with various backoff strategies.
  """
  
  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker}
  require Logger
  
  @type backoff_strategy :: :linear | :exponential | :fibonacci | :decorrelated_jitter
  
  @doc """
  Executes a function with retry logic based on error handling rules.
  """
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    backoff = Keyword.get(opts, :backoff, :exponential)
    base_delay = Keyword.get(opts, :base_delay, 1_000)
    max_delay = Keyword.get(opts, :max_delay, 30_000)
    circuit = Keyword.get(opts, :circuit, nil)
    
    do_retry(fun, 1, max_attempts, backoff, base_delay, max_delay, circuit, nil)
  end
  
  defp do_retry(fun, attempt, max_attempts, backoff, base_delay, max_delay, circuit, last_error) do
    # Execute through circuit breaker if configured
    result = if circuit do
      CircuitBreaker.with_circuit(circuit, fun)
    else
      try do
        fun.()
      catch
        kind, error -> {:error, {kind, error}}
      end
    end
    
    case result do
      {:ok, _} = success ->
        if attempt > 1 do
          Logger.info("Retry succeeded on attempt #{attempt}")
        end
        success
        
      {:error, error} ->
        wrapped_error = wrap_error(error, attempt)
        
        if attempt < max_attempts and should_retry?(wrapped_error) do
          delay = calculate_delay(attempt, backoff, base_delay, max_delay)
          
          Logger.warn("Retry attempt #{attempt} failed, retrying in #{delay}ms: #{wrapped_error.message}")
          
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_attempts, backoff, base_delay, max_delay, circuit, wrapped_error)
        else
          Logger.error("All retry attempts exhausted (#{attempt}/#{max_attempts})")
          {:error, wrapped_error}
        end
    end
  end
  
  defp wrap_error(error, attempt) do
    case error do
      %PoolErrorHandler{} = wrapped ->
        # Already wrapped, update attempt
        %{wrapped | context: Map.put(wrapped.context, :attempt, attempt)}
        
      _ ->
        # Wrap the error
        PoolErrorHandler.wrap_pool_error(error, %{attempt: attempt})
    end
  end
  
  defp should_retry?(wrapped_error) do
    PoolErrorHandler.should_retry?(wrapped_error, wrapped_error.context[:attempt] || 1)
  end
  
  defp calculate_delay(attempt, strategy, base_delay, max_delay) do
    delay = case strategy do
      :linear ->
        attempt * base_delay
        
      :exponential ->
        :math.pow(2, attempt - 1) * base_delay
        
      :fibonacci ->
        fib(attempt) * base_delay
        
      :decorrelated_jitter ->
        # AWS-style decorrelated jitter
        last_delay = Process.get(:last_retry_delay, base_delay)
        new_delay = :rand.uniform() * min(max_delay, last_delay * 3)
        Process.put(:last_retry_delay, new_delay)
        round(new_delay)
        
      custom when is_function(custom, 1) ->
        custom.(attempt)
        
      _ ->
        base_delay
    end
    
    min(round(delay), max_delay)
  end
  
  defp fib(1), do: 1
  defp fib(2), do: 1
  defp fib(n), do: fib(n-1) + fib(n-2)
end
```

## Error Recovery Orchestrator

**File:** `lib/dspex/python_bridge/error_recovery_orchestrator.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.ErrorRecoveryOrchestrator do
  @moduledoc """
  Orchestrates complex error recovery scenarios across the pool system.
  """
  
  use GenServer
  require Logger
  
  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker, RetryLogic}
  
  defstruct [
    :recovery_strategies,
    :active_recoveries,
    :metrics
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    state = %__MODULE__{
      recovery_strategies: load_recovery_strategies(),
      active_recoveries: %{},
      metrics: %{
        recoveries_initiated: 0,
        recoveries_succeeded: 0,
        recoveries_failed: 0
      }
    }
    
    {:ok, state}
  end
  
  @doc "Handles an error with appropriate recovery strategy"
  def handle_error(error, context) do
    GenServer.call(__MODULE__, {:handle_error, error, context})
  end
  
  def handle_call({:handle_error, error, context}, from, state) do
    wrapped_error = PoolErrorHandler.wrap_pool_error(error, context)
    recovery_id = generate_recovery_id()
    
    # Determine recovery strategy
    strategy = determine_recovery_strategy(wrapped_error, state)
    
    # Start recovery process
    recovery_state = %{
      id: recovery_id,
      error: wrapped_error,
      strategy: strategy,
      started_at: System.monotonic_time(:millisecond),
      from: from
    }
    
    # Execute recovery asynchronously
    Task.start_link(fn ->
      result = execute_recovery(recovery_state, state)
      GenServer.cast(__MODULE__, {:recovery_complete, recovery_id, result})
    end)
    
    new_state = %{state |
      active_recoveries: Map.put(state.active_recoveries, recovery_id, recovery_state),
      metrics: Map.update!(state.metrics, :recoveries_initiated, &(&1 + 1))
    }
    
    {:noreply, new_state}
  end
  
  def handle_cast({:recovery_complete, recovery_id, result}, state) do
    case Map.pop(state.active_recoveries, recovery_id) do
      {nil, _} ->
        {:noreply, state}
        
      {recovery_state, remaining} ->
        # Reply to original caller
        GenServer.reply(recovery_state.from, result)
        
        # Update metrics
        metric_key = case result do
          {:ok, _} -> :recoveries_succeeded
          _ -> :recoveries_failed
        end
        
        new_state = %{state |
          active_recoveries: remaining,
          metrics: Map.update!(state.metrics, metric_key, &(&1 + 1))
        }
        
        {:noreply, new_state}
    end
  end
  
  defp determine_recovery_strategy(wrapped_error, state) do
    category = wrapped_error.error_category
    severity = wrapped_error.severity
    
    # Get base strategy from configuration
    base_strategy = get_in(state.recovery_strategies, [category, severity])
    
    # Enhance with context-specific adjustments
    enhance_strategy(base_strategy, wrapped_error)
  end
  
  defp enhance_strategy(base_strategy, wrapped_error) do
    Map.merge(base_strategy, %{
      circuit_breaker: should_use_circuit_breaker?(wrapped_error),
      fallback_adapter: get_fallback_adapter(wrapped_error),
      max_recovery_time: calculate_max_recovery_time(wrapped_error)
    })
  end
  
  defp execute_recovery(recovery_state, _state) do
    strategy = recovery_state.strategy
    error = recovery_state.error
    
    Logger.info("Initiating recovery #{recovery_state.id} for #{error.error_category}")
    
    try do
      result = case strategy.type do
        :retry_with_backoff ->
          RetryLogic.with_retry(
            fn -> attempt_recovery(error) end,
            max_attempts: strategy.max_attempts,
            backoff: strategy.backoff,
            circuit: strategy.circuit_breaker
          )
          
        :failover ->
          attempt_failover(error, strategy.fallback_adapter)
          
        :circuit_break ->
          {:error, :circuit_opened}
          
        :abandon ->
          {:error, :recovery_abandoned}
          
        _ ->
          {:error, :unknown_strategy}
      end
      
      handle_recovery_result(result, recovery_state)
    catch
      kind, error ->
        Logger.error("Recovery #{recovery_state.id} crashed: #{kind} - #{inspect(error)}")
        {:error, {:recovery_crashed, {kind, error}}}
    end
  end
  
  defp attempt_recovery(error) do
    # Implement specific recovery logic based on error type
    case error.error_category do
      :connection_error ->
        # Try to re-establish connection
        reconnect_worker(error.context[:worker_id])
        
      :timeout_error ->
        # Retry with increased timeout
        retry_with_timeout(error.context)
        
      :resource_error ->
        # Try to free resources and retry
        free_resources_and_retry(error.context)
        
      _ ->
        {:error, :no_recovery_available}
    end
  end
  
  defp attempt_failover(error, fallback_adapter) do
    Logger.info("Attempting failover to #{fallback_adapter}")
    
    # Execute original operation with fallback adapter
    context = error.context
    operation = context[:operation]
    args = context[:args]
    
    case DSPex.Adapters.Factory.execute_with_adapter(
      fallback_adapter,
      operation,
      args,
      test_layer: :layer_1  # Use mock layer for failover
    ) do
      {:ok, result} ->
        Logger.info("Failover succeeded")
        {:ok, {:failover, result}}
        
      {:error, reason} ->
        Logger.error("Failover failed: #{inspect(reason)}")
        {:error, {:failover_failed, reason}}
    end
  end
  
  defp handle_recovery_result(result, recovery_state) do
    duration = System.monotonic_time(:millisecond) - recovery_state.started_at
    
    :telemetry.execute(
      [:dspex, :recovery, :complete],
      %{duration: duration},
      %{
        recovery_id: recovery_state.id,
        error_category: recovery_state.error.error_category,
        strategy: recovery_state.strategy.type,
        result: elem(result, 0)
      }
    )
    
    result
  end
  
  defp generate_recovery_id do
    "recovery_#{System.unique_integer([:positive])}_#{System.os_time(:nanosecond)}"
  end
  
  defp load_recovery_strategies do
    # Load from configuration or defaults
    %{
      connection_error: %{
        critical: %{type: :circuit_break, max_attempts: 3, backoff: :exponential},
        major: %{type: :retry_with_backoff, max_attempts: 5, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      timeout_error: %{
        critical: %{type: :abandon},
        major: %{type: :retry_with_backoff, max_attempts: 2, backoff: :exponential},
        minor: %{type: :retry_with_backoff, max_attempts: 3, backoff: :linear}
      },
      resource_error: %{
        critical: %{type: :circuit_break},
        major: %{type: :failover},
        minor: %{type: :retry_with_backoff, max_attempts: 2}
      }
    }
  end
  
  defp should_use_circuit_breaker?(error) do
    error.severity == :critical or error.context[:affecting_all_workers]
  end
  
  defp get_fallback_adapter(error) do
    case error.context[:adapter] do
      DSPex.Adapters.PythonPort -> DSPex.Adapters.Mock
      DSPex.Adapters.PythonPoolV2 -> DSPex.Adapters.PythonPort
      _ -> DSPex.Adapters.Mock
    end
  end
  
  defp calculate_max_recovery_time(error) do
    base_time = case error.severity do
      :critical -> 5_000
      :major -> 30_000
      :minor -> 60_000
      _ -> 10_000
    end
    
    # Adjust based on context
    if error.context[:user_facing], do: base_time / 2, else: base_time
  end
  
  # Placeholder recovery functions
  defp reconnect_worker(_worker_id), do: {:ok, :reconnected}
  defp retry_with_timeout(_context), do: {:ok, :retried}
  defp free_resources_and_retry(_context), do: {:ok, :resources_freed}
end
```

## Integration with Pool Operations

Update the SessionPoolV2 to use comprehensive error handling:

**File:** `lib/dspex/python_bridge/session_pool_v2.ex` (updates)

```elixir
defmodule DSPex.PythonBridge.SessionPoolV2 do
  # ... existing code ...
  
  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker, RetryLogic, ErrorRecoveryOrchestrator}
  
  def execute_in_session(session_id, command, args, opts \\ []) do
    context = %{
      session_id: session_id,
      command: command,
      args: args,
      operation: :execute_command,
      adapter: __MODULE__
    }
    
    # Wrap entire operation in error handling
    RetryLogic.with_retry(
      fn ->
        do_execute_with_error_handling(session_id, command, args, opts, context)
      end,
      max_attempts: Keyword.get(opts, :max_retries, 3),
      circuit: :pool_operations,
      base_delay: 1_000
    )
  end
  
  defp do_execute_with_error_handling(session_id, command, args, opts, context) do
    pool_name = Keyword.get(opts, :pool_name, @default_pool)
    timeout = Keyword.get(opts, :timeout, 60_000)
    
    try do
      NimblePool.checkout!(
        pool_name,
        {:session, session_id},
        fn from, worker ->
          execute_with_worker_error_handling(worker, command, args, timeout, context)
        end,
        pool_timeout: timeout + 5_000
      )
    catch
      :exit, {:timeout, _} ->
        handle_pool_error({:timeout, :checkout_timeout}, context)
        
      :exit, {:noproc, _} ->
        handle_pool_error({:resource_error, :pool_not_available}, context)
        
      :exit, reason ->
        handle_pool_error({:system_error, reason}, context)
        
      kind, error ->
        handle_pool_error({:unexpected_error, {kind, error}}, context)
    end
  end
  
  defp execute_with_worker_error_handling(worker, command, args, timeout, context) do
    enhanced_context = Map.merge(context, %{
      worker_id: worker.worker_id,
      worker_state: worker.state_machine.state
    })
    
    try do
      result = execute_command_with_timeout(worker, command, args, timeout)
      
      case result do
        {:ok, response} ->
          {{:ok, response}, :ok}
          
        {:error, reason} ->
          wrapped = PoolErrorHandler.wrap_pool_error(
            {:command_error, reason},
            enhanced_context
          )
          {{:error, wrapped}, {:error, reason}}
      end
    catch
      :exit, {:timeout, _} ->
        error = handle_command_timeout(worker, command, enhanced_context)
        {{:error, error}, :close}
        
      kind, error ->
        wrapped = handle_command_error(kind, error, enhanced_context)
        {{:error, wrapped}, {:error, :command_failed}}
    end
  end
  
  defp handle_pool_error(error, context) do
    wrapped = PoolErrorHandler.wrap_pool_error(error, context)
    
    # Attempt recovery through orchestrator
    case ErrorRecoveryOrchestrator.handle_error(wrapped, context) do
      {:ok, {:recovered, result}} ->
        {:ok, result}
        
      {:ok, {:failover, result}} ->
        Logger.warn("Operation succeeded through failover")
        {:ok, result}
        
      {:error, recovery_error} ->
        {:error, wrapped}
    end
  end
  
  defp handle_command_timeout(worker, command, context) do
    Logger.error("Command timeout for worker #{worker.worker_id}: #{command}")
    
    # Record in circuit breaker
    CircuitBreaker.record_failure(:worker_commands, :timeout)
    
    PoolErrorHandler.wrap_pool_error(
      {:timeout, :command_timeout},
      Map.merge(context, %{
        worker_health: worker.state_machine.health,
        command_duration: :timeout
      })
    )
  end
  
  defp handle_command_error(kind, error, context) do
    Logger.error("Command error: #{kind} - #{inspect(error)}")
    
    PoolErrorHandler.wrap_pool_error(
      {:command_error, {kind, error}},
      context
    )
  end
end
```

## Error Reporting and Monitoring

**File:** `lib/dspex/python_bridge/error_reporter.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.ErrorReporter do
  @moduledoc """
  Centralizes error reporting and monitoring for pool operations.
  """
  
  use GenServer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Subscribe to error events
    :telemetry.attach_many(
      "pool-error-reporter",
      [
        [:dspex, :pool, :error],
        [:dspex, :circuit_breaker, :opened],
        [:dspex, :recovery, :complete]
      ],
      &handle_event/4,
      nil
    )
    
    {:ok, %{}}
  end
  
  def handle_event([:dspex, :pool, :error], measurements, metadata, _config) do
    error_category = metadata[:error_category]
    severity = metadata[:severity]
    
    Logger.error("""
    Pool Error Detected:
    Category: #{error_category}
    Severity: #{severity}
    Worker: #{metadata[:worker_id]}
    Duration: #{measurements[:duration]}ms
    Context: #{inspect(metadata[:context])}
    """)
    
    # Send to monitoring system
    send_to_monitoring(error_category, severity, metadata)
  end
  
  def handle_event([:dspex, :circuit_breaker, :opened], _measurements, metadata, _config) do
    Logger.error("Circuit breaker opened: #{metadata[:circuit]}")
    
    # Alert operations team
    send_alert(:circuit_opened, metadata)
  end
  
  def handle_event([:dspex, :recovery, :complete], measurements, metadata, _config) do
    result = metadata[:result]
    duration = measurements[:duration]
    
    Logger.info("Recovery completed: #{result} in #{duration}ms")
  end
  
  defp send_to_monitoring(category, severity, metadata) do
    # Integration with monitoring system (e.g., DataDog, New Relic)
    :ok
  end
  
  defp send_alert(alert_type, metadata) do
    # Integration with alerting system (e.g., PagerDuty, Slack)
    :ok
  end
end
```

## Testing Error Scenarios

```elixir
defmodule DSPex.PythonBridge.ErrorHandlingTest do
  use ExUnit.Case
  
  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker, RetryLogic}
  
  describe "error classification" do
    test "categorizes errors correctly" do
      error1 = {:port_exited, 1}
      wrapped1 = PoolErrorHandler.wrap_pool_error(error1, %{})
      assert wrapped1.error_category == :connection_error
      
      error2 = {:timeout, :operation}
      wrapped2 = PoolErrorHandler.wrap_pool_error(error2, %{})
      assert wrapped2.error_category == :timeout_error
    end
  end
  
  describe "circuit breaker" do
    test "opens after threshold failures" do
      circuit_name = :test_circuit_#{System.unique_integer()}
      
      # Cause failures
      for _ <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error)
      end
      
      assert CircuitBreaker.get_state(circuit_name) == :open
    end
    
    test "transitions to half-open after timeout" do
      # Test implementation
    end
  end
  
  describe "retry logic" do
    test "retries with exponential backoff" do
      attempt_count = :counters.new(1, [])
      
      RetryLogic.with_retry(
        fn ->
          :counters.add(attempt_count, 1, 1)
          if :counters.get(attempt_count, 1) < 3 do
            {:error, :retriable_error}
          else
            {:ok, :success}
          end
        end,
        max_attempts: 5,
        backoff: :exponential,
        base_delay: 10
      )
      
      assert :counters.get(attempt_count, 1) == 3
    end
  end
end
```

## Next Steps

Proceed to Document 5: "Test Infrastructure Overhaul" for comprehensive testing strategy.
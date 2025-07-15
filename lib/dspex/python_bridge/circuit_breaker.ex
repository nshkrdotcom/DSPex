defmodule DSPex.PythonBridge.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for pool operations to prevent cascading failures.

  Implements the circuit breaker pattern with three states:
  - `:closed` - Normal operation, requests pass through
  - `:open` - Circuit is open, requests fail fast
  - `:half_open` - Testing if service has recovered, limited requests allowed

  ## State Transitions

  - `closed -> open`: When failure threshold is exceeded
  - `open -> half_open`: After timeout period expires
  - `half_open -> closed`: When success threshold is met
  - `half_open -> open`: On any failure in half-open state

  ## Configuration

  - `failure_threshold`: Number of failures before opening (default: 5)
  - `success_threshold`: Successes needed to close from half-open (default: 3)
  - `timeout`: Time before attempting half-open (default: 60 seconds)
  - `half_open_requests`: Max concurrent requests in half-open (default: 3)

  ## Usage

      # Execute operation through circuit breaker
      CircuitBreaker.with_circuit(:my_operation, fn ->
        # Your operation here
        {:ok, result}
      end)
      
      # Manual state management
      CircuitBreaker.record_success(:my_operation)
      CircuitBreaker.record_failure(:my_operation, error)
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.PoolErrorHandler

  @type state :: :closed | :open | :half_open
  @type circuit :: %{
          name: atom(),
          state: state(),
          failure_count: non_neg_integer(),
          success_count: non_neg_integer(),
          last_failure: integer() | nil,
          last_state_change: integer(),
          half_open_count: non_neg_integer(),
          config: map()
        }

  @default_config %{
    # Failures to open circuit
    failure_threshold: 5,
    # Successes to close from half-open
    success_threshold: 3,
    # Time before half-open attempt (60 seconds)
    timeout: 60_000,
    # Max requests in half-open state
    half_open_requests: 3
  }

  ## Public API

  @doc """
  Starts the circuit breaker GenServer.

  ## Options

  - `:name` - Process name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a function through the circuit breaker.

  ## Parameters

  - `circuit_name` - Unique name for this circuit
  - `fun` - Function to execute (should return {:ok, result} or {:error, reason})
  - `opts` - Configuration options for this circuit

  ## Returns

  Result of the function or circuit breaker error.

  ## Examples

      CircuitBreaker.with_circuit(:database, fn ->
        Database.query("SELECT * FROM users")
      end)
      
      CircuitBreaker.with_circuit(:api_call, fn ->
        HTTPClient.get("https://api.example.com/data")
      end, config: %{failure_threshold: 3})
  """
  @spec with_circuit(atom(), function(), keyword()) :: {:ok, term()} | {:error, term()}
  def with_circuit(circuit_name, fun, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:execute, circuit_name, fun, opts})
  end

  @doc """
  Records a success for a circuit.

  This is useful when you want to manually track successes outside
  of the `with_circuit/3` function.
  """
  @spec record_success(atom(), keyword()) :: :ok
  def record_success(circuit_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.cast(server, {:record_success, circuit_name})
  end

  @doc """
  Records a failure for a circuit.

  This is useful when you want to manually track failures outside
  of the `with_circuit/3` function.
  """
  @spec record_failure(atom(), term(), keyword()) :: :ok
  def record_failure(circuit_name, error, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.cast(server, {:record_failure, circuit_name, error})
  end

  @doc """
  Gets the current state of a circuit.

  ## Returns

  `:closed`, `:open`, `:half_open`, or `:not_found` if circuit doesn't exist.
  """
  @spec get_state(atom(), keyword()) :: state() | :not_found
  def get_state(circuit_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:get_state, circuit_name})
  end

  @doc """
  Gets detailed circuit information.

  ## Returns

  Map with circuit statistics and configuration, or `:not_found`.
  """
  @spec get_circuit_info(atom(), keyword()) :: map() | :not_found
  def get_circuit_info(circuit_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:get_circuit_info, circuit_name})
  end

  @doc """
  Manually resets a circuit to closed state.

  This clears all failure counts and resets the circuit.
  Useful for manual recovery procedures.
  """
  @spec reset(atom(), keyword()) :: :ok
  def reset(circuit_name, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:reset, circuit_name})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    circuits = %{}
    Logger.info("CircuitBreaker started")
    {:ok, circuits}
  end

  @impl true
  def handle_call({:execute, circuit_name, fun, opts}, _from, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, opts)

    case circuit.state do
      :closed ->
        # Circuit is closed, execute normally
        execute_and_track(circuit, fun, circuits)

      :open ->
        # Circuit is open, check if we should transition to half-open
        if should_attempt_reset?(circuit) do
          Logger.info("Circuit #{circuit_name} transitioning to half-open for testing")

          new_circuit = %{
            circuit
            | state: :half_open,
              success_count: 0,
              half_open_count: 0,
              last_state_change: System.monotonic_time(:millisecond)
          }

          execute_and_track(new_circuit, fun, circuits)
        else
          error = {:circuit_open, circuit_name}
          time_remaining = time_until_retry(circuit)

          Logger.debug(
            "Circuit #{circuit_name} is open, rejecting request (#{time_remaining}ms until retry)"
          )

          wrapped_error =
            PoolErrorHandler.wrap_pool_error(error, %{
              circuit: circuit_name,
              time_until_retry: time_remaining,
              failure_count: circuit.failure_count
            })

          {:reply, {:error, wrapped_error}, circuits}
        end

      :half_open ->
        # Circuit is half-open, limited requests allowed
        if circuit.half_open_count < circuit.config.half_open_requests do
          Logger.debug(
            "Circuit #{circuit_name} allowing half-open request (#{circuit.half_open_count + 1}/#{circuit.config.half_open_requests})"
          )

          new_circuit = %{circuit | half_open_count: circuit.half_open_count + 1}
          execute_and_track(new_circuit, fun, circuits)
        else
          # Too many concurrent half-open requests
          error = {:circuit_half_open_limit, circuit_name}

          wrapped_error =
            PoolErrorHandler.wrap_pool_error(error, %{
              circuit: circuit_name,
              concurrent_requests: circuit.half_open_count
            })

          Logger.debug("Circuit #{circuit_name} rejecting request - half-open limit reached")
          {:reply, {:error, wrapped_error}, circuits}
        end
    end
  end

  @impl true
  def handle_call({:get_state, circuit_name}, _from, circuits) do
    circuit = Map.get(circuits, circuit_name)
    state = if circuit, do: circuit.state, else: :not_found
    {:reply, state, circuits}
  end

  @impl true
  def handle_call({:get_circuit_info, circuit_name}, _from, circuits) do
    case Map.get(circuits, circuit_name) do
      nil ->
        {:reply, :not_found, circuits}

      circuit ->
        info = %{
          name: circuit.name,
          state: circuit.state,
          failure_count: circuit.failure_count,
          success_count: circuit.success_count,
          half_open_count: circuit.half_open_count,
          last_failure: circuit.last_failure,
          last_state_change: circuit.last_state_change,
          time_until_retry: if(circuit.state == :open, do: time_until_retry(circuit), else: nil),
          config: circuit.config
        }

        {:reply, info, circuits}
    end
  end

  @impl true
  def handle_call({:reset, circuit_name}, _from, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, [])

    new_circuit = %{
      circuit
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        half_open_count: 0,
        last_failure: nil,
        last_state_change: System.monotonic_time(:millisecond)
    }

    Logger.info("Circuit #{circuit_name} manually reset to closed state")
    emit_telemetry(circuit_name, :reset, 0)

    {:reply, :ok, Map.put(circuits, circuit_name, new_circuit)}
  end

  @impl true
  def handle_cast({:record_success, circuit_name}, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, [])
    new_circuit = handle_success(circuit)
    {:noreply, Map.put(circuits, circuit_name, new_circuit)}
  end

  @impl true
  def handle_cast({:record_failure, circuit_name, error}, circuits) do
    circuit = get_or_create_circuit(circuits, circuit_name, [])
    new_circuit = handle_failure(circuit, error)
    {:noreply, Map.put(circuits, circuit_name, new_circuit)}
  end

  ## Private Functions

  @spec get_or_create_circuit(map(), atom(), keyword()) :: circuit()
  defp get_or_create_circuit(circuits, name, opts) do
    Map.get(circuits, name, %{
      name: name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      half_open_count: 0,
      last_failure: nil,
      last_state_change: System.monotonic_time(:millisecond),
      config: Map.merge(@default_config, Keyword.get(opts, :config, %{}))
    })
  end

  @spec execute_and_track(circuit(), function(), map()) :: {:reply, term(), map()}
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

        wrapped_error =
          PoolErrorHandler.wrap_pool_error(
            {:circuit_execution_failed, {kind, error}},
            %{
              circuit: circuit.name,
              duration: duration,
              kind: kind
            }
          )

        {:reply, {:error, wrapped_error}, Map.put(circuits, circuit.name, new_circuit)}
    end
  end

  @spec handle_success(circuit()) :: circuit()
  defp handle_success(circuit) do
    case circuit.state do
      :closed ->
        # Reset failure count on success in closed state
        %{circuit | failure_count: 0}

      :half_open ->
        # Count successes in half-open state
        new_count = circuit.success_count + 1

        if new_count >= circuit.config.success_threshold do
          # Enough successes, close the circuit
          Logger.info(
            "Circuit #{circuit.name} closed after successful recovery (#{new_count} successes)"
          )

          emit_telemetry(circuit.name, :closed, 0)

          %{
            circuit
            | state: :closed,
              failure_count: 0,
              success_count: 0,
              half_open_count: 0,
              last_state_change: System.monotonic_time(:millisecond)
          }
        else
          Logger.debug(
            "Circuit #{circuit.name} half-open success #{new_count}/#{circuit.config.success_threshold}"
          )

          %{circuit | success_count: new_count}
        end

      :open ->
        # Shouldn't happen, but handle gracefully
        Logger.warning(
          "Circuit #{circuit.name} received success while open - this should not happen"
        )

        circuit
    end
  end

  @spec handle_failure(circuit(), term()) :: %{
          name: atom(),
          state: state(),
          failure_count: pos_integer(),
          success_count: non_neg_integer(),
          last_failure: integer(),
          last_state_change: integer(),
          half_open_count: non_neg_integer(),
          config: map()
        }
  defp handle_failure(circuit, error) do
    new_failure_count = circuit.failure_count + 1
    now = System.monotonic_time(:millisecond)

    Logger.debug(
      "Circuit #{circuit.name} failure #{new_failure_count} recorded: #{inspect(error)}"
    )

    new_circuit = %{circuit | failure_count: new_failure_count, last_failure: now}

    case circuit.state do
      :closed when new_failure_count >= circuit.config.failure_threshold ->
        # Open the circuit
        Logger.error(
          "Circuit #{circuit.name} opened after #{new_failure_count} failures (threshold: #{circuit.config.failure_threshold})"
        )

        emit_telemetry(circuit.name, :opened, 0)

        %{new_circuit | state: :open, last_state_change: now}

      :half_open ->
        # Single failure in half-open returns to open
        Logger.warning("Circuit #{circuit.name} reopened after failure in half-open state")
        emit_telemetry(circuit.name, :reopened, 0)

        %{
          new_circuit
          | state: :open,
            success_count: 0,
            half_open_count: 0,
            last_state_change: now
        }

      _ ->
        new_circuit
    end
  end

  @spec should_attempt_reset?(circuit()) :: boolean()
  defp should_attempt_reset?(circuit) do
    case circuit.last_failure do
      nil ->
        true

      last_failure ->
        time_since_failure = System.monotonic_time(:millisecond) - last_failure
        time_since_failure >= circuit.config.timeout
    end
  end

  @spec time_until_retry(circuit()) :: non_neg_integer() | float()
  defp time_until_retry(circuit) do
    case circuit.last_failure do
      nil ->
        0

      last_failure ->
        time_since_failure = System.monotonic_time(:millisecond) - last_failure
        max(0, circuit.config.timeout - time_since_failure)
    end
  end

  @spec emit_telemetry(atom(), atom(), non_neg_integer()) :: :ok
  defp emit_telemetry(circuit_name, event, duration) do
    try do
      :telemetry.execute(
        [:dspex, :circuit_breaker, event],
        %{duration: duration},
        %{circuit: circuit_name}
      )
    rescue
      _ ->
        # Telemetry not available, log instead
        Logger.debug("Circuit #{circuit_name} event: #{event} (#{duration}ms)")
    end

    :ok
  end
end

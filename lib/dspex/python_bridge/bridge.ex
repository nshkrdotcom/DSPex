defmodule DSPex.PythonBridge.Bridge do
  @moduledoc """
  GenServer managing Python DSPy process communication.

  This module provides the core communication bridge between Elixir and Python
  DSPy processes using a Port-based subprocess with JSON message passing.

  ## Features

  - **Process Lifecycle Management**: Automatic Python subprocess startup and monitoring
  - **Request/Response Correlation**: Unique request IDs for reliable message correlation
  - **Timeout Handling**: Configurable timeouts with proper cleanup
  - **Error Recovery**: Automatic retry and restart capabilities
  - **Concurrent Requests**: Support for multiple simultaneous operations
  - **Health Monitoring**: Built-in health checks and status monitoring

  ## Architecture

  The bridge uses Erlang Ports to manage Python subprocesses with:
  - 4-byte length-prefixed packet framing
  - JSON message encoding for cross-language compatibility
  - Request correlation using unique sequential IDs
  - Timeout management for long-running operations

  ## Usage

      # Start the bridge
      {:ok, _pid} = DSPex.PythonBridge.Bridge.start_link()

      # Make a call
      {:ok, result} = DSPex.PythonBridge.Bridge.call(:ping, %{})

      # Create a DSPy program
      {:ok, program_info} = DSPex.PythonBridge.Bridge.call(:create_program, %{
        id: "qa_program",
        signature: %{
          inputs: [%{name: "question", type: "str"}],
          outputs: [%{name: "answer", type: "str"}]
        }
      })

  ## Configuration

      config :dspex, :python_bridge,
        python_executable: "python3",
        default_timeout: 30_000,
        max_retries: 3,
        restart_strategy: :permanent
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.{Protocol, EnvironmentCheck}

  @type command :: atom() | String.t()
  @type args :: map()
  @type result :: any()
  @type timeout_ms :: non_neg_integer()

  @default_timeout 30_000
  @default_config %{
    python_executable: "python3",
    default_timeout: @default_timeout,
    max_retries: 3,
    restart_strategy: :permanent
  }

  defstruct [
    :port,
    :python_path,
    :script_path,
    :environment_info,
    requests: %{},
    request_id: 0,
    config: @default_config,
    status: :starting,
    start_time: nil,
    stats: %{
      requests_sent: 0,
      responses_received: 0,
      errors: 0,
      restarts: 0,
      correlation_errors: 0
    }
  ]

  ## Public API

  @doc """
  Starts the Python bridge GenServer.

  Validates the Python environment and starts the subprocess if everything
  is properly configured.

  ## Options

  - `:name` - The name to register the GenServer (default: `__MODULE__`)
  - `:python_executable` - Python executable to use
  - `:timeout` - Default timeout for operations
  - `:max_retries` - Maximum number of restart retries

  ## Examples

      {:ok, pid} = DSPex.PythonBridge.Bridge.start_link()
      {:ok, pid} = DSPex.PythonBridge.Bridge.start_link(name: MyBridge)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Makes a synchronous call to the Python bridge.

  Sends a command with arguments to the Python process and waits for
  a response. Returns the result or an error.

  ## Parameters

  - `command` - The command to execute (atom or string)
  - `args` - Arguments map to pass to the command
  - `timeout` - Timeout in milliseconds (optional)

  ## Examples

      {:ok, result} = DSPex.PythonBridge.Bridge.call(:ping, %{})
      {:ok, stats} = DSPex.PythonBridge.Bridge.call(:get_stats, %{}, 5000)
      {:error, reason} = DSPex.PythonBridge.Bridge.call(:unknown_command, %{})
  """
  @spec call(command(), args(), timeout_ms()) :: {:ok, result()} | {:error, any()}
  def call(command, args, timeout \\ @default_timeout) do
    try do
      GenServer.call(__MODULE__, {:call, command, args}, timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Python bridge call timed out: #{inspect(command)}")
        {:error, :timeout}

      :exit, {:noproc, _} ->
        Logger.error("Python bridge process not running")
        {:error, :bridge_not_running}

      error ->
        Logger.error("Unexpected error in bridge call: #{inspect(error)}")
        {:error, :unexpected_error}
    end
  end

  @doc """
  Makes an asynchronous call to the Python bridge.

  Sends a command without waiting for a response. Useful for fire-and-forget
  operations or when handling responses separately.

  ## Examples

      :ok = DSPex.PythonBridge.Bridge.cast(:cleanup, %{})
  """
  @spec cast(command(), args()) :: :ok
  def cast(command, args) do
    GenServer.cast(__MODULE__, {:cast, command, args})
  end

  @doc """
  Gets the current status of the Python bridge.

  Returns information about the bridge state, statistics, and health.

  ## Examples

      %{status: :running, stats: %{...}, uptime: 12345} = 
        DSPex.PythonBridge.Bridge.get_status()
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Stops the Python bridge gracefully.

  Terminates the Python subprocess and cleans up resources.

  ## Examples

      :ok = DSPex.PythonBridge.Bridge.stop()
  """
  @spec stop() :: :ok
  def stop do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Restarts the Python bridge.

  Stops the current process and starts a new one. Useful for recovery
  from errors or configuration changes.
  """
  @spec restart() :: :ok | {:error, any()}
  def restart do
    GenServer.call(__MODULE__, :restart)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    config = build_config(opts)

    case EnvironmentCheck.validate_environment() do
      {:ok, environment_info} ->
        case start_python_process(environment_info, config) do
          {:ok, port} ->
            state = %__MODULE__{
              port: port,
              python_path: environment_info.python_path,
              script_path: environment_info.script_path,
              environment_info: environment_info,
              config: config,
              status: :running,
              start_time: DateTime.utc_now()
            }

            Logger.info("Python bridge started successfully")

            # Send an initial ping to establish the connection and prevent early exit
            request_id = 1
            request = Protocol.encode_request(request_id, :ping, %{})
            request_bytes = :erlang.iolist_to_binary(request)
            send(port, {self(), {:command, request_bytes}})

            updated_state = %{state | request_id: request_id}
            {:ok, updated_state}

          {:error, reason} ->
            Logger.error("Failed to start Python process: #{reason}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("Python environment validation failed: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:call, command, args}, from, state) do
    case state.status do
      :running ->
        request_id = state.request_id + 1
        request = Protocol.encode_request(request_id, command, args)

        # Send to Python (port handles length prefix automatically)
        request_bytes = :erlang.iolist_to_binary(request)
        send(state.port, {self(), {:command, request_bytes}})

        # Store request for correlation
        new_requests = Map.put(state.requests, request_id, from)
        new_stats = update_in(state.stats, [:requests_sent], &(&1 + 1))

        new_state = %{state | requests: new_requests, request_id: request_id, stats: new_stats}

        {:noreply, new_state}

      status ->
        Logger.warning("Bridge call rejected, bridge status: #{status}")
        {:reply, {:error, {:bridge_not_ready, status}}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      uptime: calculate_uptime(state.start_time),
      pending_requests: map_size(state.requests),
      stats: state.stats,
      environment: state.environment_info,
      python_path: state.python_path,
      script_path: state.script_path
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_call(:restart, _from, state) do
    Logger.info("Restarting Python bridge")

    # Close current port
    if state.port do
      Port.close(state.port)
    end

    # Fail all pending requests
    fail_pending_requests(state.requests, "Bridge restarting")

    # Start new process
    case start_python_process(state.environment_info, state.config) do
      {:ok, new_port} ->
        new_state = %{
          state
          | port: new_port,
            requests: %{},
            request_id: 0,
            status: :running,
            start_time: DateTime.utc_now()
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | status: :failed}}
    end
  end

  @impl true
  def handle_cast({:cast, command, args}, state) do
    if state.status == :running do
      request_id = state.request_id + 1
      request = Protocol.encode_request(request_id, command, args)

      # Send to Python (no response tracking for casts, port handles length prefix)
      request_bytes = :erlang.iolist_to_binary(request)
      send(state.port, {self(), {:command, request_bytes}})

      new_stats = update_in(state.stats, [:requests_sent], &(&1 + 1))
      new_state = %{state | request_id: request_id, stats: new_stats}

      {:noreply, new_state}
    else
      Logger.warning("Bridge cast rejected, bridge status: #{state.status}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Protocol.decode_response(data) do
      {:ok, id, result} ->
        handle_successful_response(state, id, result)

      {:error, id, error} ->
        handle_error_response(state, id, error)

      {:error, :decode_error} ->
        Logger.error("JSON decode failed - potential Python bridge protocol issue")
        handle_decode_error(state, :json_parse_failed)

      {:error, :malformed_response} ->
        Logger.error("Malformed response from Python bridge - response structure invalid")
        handle_decode_error(state, :malformed_structure)

      {:error, :binary_data} ->
        Logger.error("Received binary/Erlang term data instead of JSON - protocol mismatch")
        handle_decode_error(state, :protocol_mismatch)
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited with status: #{status}")

    # Fail all pending requests
    fail_pending_requests(state.requests, "Python process died")

    new_state = %{state | status: :failed, requests: %{}, port: nil}

    {:stop, :python_process_died, new_state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("Python port exited with reason: #{inspect(reason)}")

    fail_pending_requests(state.requests, "Port exited")

    new_state = %{state | status: :failed, requests: %{}, port: nil}

    {:stop, reason, new_state}
  end

  # Handle normal port cleanup messages that aren't errors
  @impl true
  def handle_info({:EXIT, _port, :normal}, state) do
    # Normal port cleanup after close - not an error
    Logger.debug("Port closed normally")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _port, :shutdown}, state) do
    # Expected shutdown signal - not an error
    Logger.debug("Port shutdown cleanly")
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _port, {:shutdown, _reason}}, state) do
    # Expected shutdown with reason - not an error
    Logger.debug("Port shutdown with reason")
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Unexpected message received: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Python bridge terminating: #{inspect(reason)}")

    if state.port do
      # Send graceful shutdown command and wait for acknowledgment
      case send_graceful_shutdown(state.port) do
        :ok ->
          Logger.debug("Python bridge acknowledged shutdown")

        {:error, reason} ->
          Logger.debug("Python bridge shutdown acknowledgment failed: #{inspect(reason)}")
      end

      Port.close(state.port)
    end

    # Fail any remaining requests
    fail_pending_requests(state.requests, "Bridge terminating")

    :ok
  end

  ## Private Functions

  defp build_config(opts) do
    app_config = Application.get_env(:dspex, :python_bridge, %{})

    @default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end

  defp start_python_process(environment_info, _config) do
    # Configure port with packet mode for length-prefixed messages
    port_opts = [
      {:args, [environment_info.script_path]},
      :binary,
      :exit_status,
      # 4-byte big-endian length prefix
      {:packet, 4}
    ]

    Logger.debug("Starting Python process with simplified options: #{inspect(port_opts)}")
    Logger.debug("Python executable: #{environment_info.python_path}")
    Logger.debug("Script path: #{environment_info.script_path}")

    try do
      port = Port.open({:spawn_executable, environment_info.python_path}, port_opts)
      {:ok, port}
    rescue
      error ->
        Logger.error("Failed to open Python port: #{inspect(error)}")
        {:error, "Failed to start Python process: #{inspect(error)}"}
    end
  end

  defp handle_successful_response(state, request_id, result) do
    case Map.pop(state.requests, request_id) do
      {nil, requests} ->
        # Enhanced correlation validation and logging
        pending_ids = Map.keys(state.requests)

        Logger.warning(
          "Received response for unknown request #{request_id}. Pending requests: #{inspect(pending_ids)}"
        )

        # Check if this might be a delayed response
        if request_id < state.request_id - 10 do
          Logger.warning(
            "Response #{request_id} appears to be significantly delayed (current: #{state.request_id})"
          )
        end

        new_stats = update_in(state.stats, [:correlation_errors], &((&1 || 0) + 1))
        {:noreply, %{state | requests: requests, stats: new_stats}}

      {from, requests} ->
        GenServer.reply(from, {:ok, result})
        new_stats = update_in(state.stats, [:responses_received], &(&1 + 1))
        {:noreply, %{state | requests: requests, stats: new_stats}}
    end
  end

  defp handle_error_response(state, request_id, error) do
    case Map.pop(state.requests, request_id) do
      {nil, requests} ->
        # Enhanced correlation validation for error responses
        pending_ids = Map.keys(state.requests)

        Logger.warning(
          "Received error for unknown request #{request_id}. Error: #{inspect(error)}. Pending: #{inspect(pending_ids)}"
        )

        # Track correlation errors separately from execution errors
        new_stats = update_in(state.stats, [:correlation_errors], &((&1 || 0) + 1))
        {:noreply, %{state | requests: requests, stats: new_stats}}

      {from, requests} ->
        GenServer.reply(from, {:error, error})

        new_stats =
          state.stats
          |> update_in([:responses_received], &(&1 + 1))
          |> update_in([:errors], &(&1 + 1))

        {:noreply, %{state | requests: requests, stats: new_stats}}
    end
  end

  defp handle_decode_error(state, error_type) do
    # Increment error stats
    new_stats = update_in(state.stats, [:errors], &(&1 + 1))

    # Determine if this is a recoverable error or if we should restart
    case {error_type, map_size(state.requests)} do
      {:protocol_mismatch, _} ->
        # Protocol mismatch might indicate Python bridge is in wrong state
        Logger.error("Protocol mismatch detected - Python bridge may need restart")
        consider_bridge_restart(state, "Protocol mismatch")

      {:json_parse_failed, pending_count} when pending_count > 5 ->
        # Many pending requests with parse failures indicate serious issues
        Logger.error(
          "JSON parse failures with #{pending_count} pending requests - restarting bridge"
        )

        consider_bridge_restart(state, "Multiple JSON parse failures")

      _ ->
        # Single decode error - log and continue
        Logger.warning("Decode error #{error_type} - continuing operation")
        {:noreply, %{state | stats: new_stats}}
    end
  end

  defp consider_bridge_restart(state, reason) do
    # Fail pending requests with clear reason
    fail_pending_requests(state.requests, "Bridge restart: #{reason}")

    # Mark bridge as failed and suggest restart
    new_stats = update_in(state.stats, [:restarts], &(&1 + 1))
    new_state = %{state | status: :failed, requests: %{}, stats: new_stats}

    Logger.warning("Bridge marked for restart due to: #{reason}")
    {:noreply, new_state}
  end

  defp fail_pending_requests(requests, reason) do
    Enum.each(requests, fn {_id, from} ->
      GenServer.reply(from, {:error, reason})
    end)
  end

  defp calculate_uptime(start_time) when is_nil(start_time), do: 0

  defp calculate_uptime(start_time) do
    DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
  end

  defp send_graceful_shutdown(port) do
    # Send cleanup command (which exists) with unique ID
    cleanup_request = Protocol.encode_request(999_999, :cleanup, %{})
    send(port, {self(), {:command, cleanup_request}})

    # Wait for acknowledgment with reasonable timeout
    receive do
      {^port, {:data, response}} ->
        case Protocol.decode_response(response) do
          {:ok, 999_999, _result} ->
            # Successful cleanup response
            :ok

          {:error, 999_999, _error} ->
            # Error response is still acknowledgment
            :ok

          _ ->
            {:error, :invalid_response}
        end

      {^port, {:exit_status, _}} ->
        # Python process exited, which is fine
        :ok
    after
      2000 -> {:error, :timeout}
    end
  end
end

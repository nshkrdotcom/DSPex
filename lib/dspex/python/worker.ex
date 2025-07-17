defmodule DSPex.Python.Worker do
  @moduledoc """
  GenServer that manages a single Python process via Port.

  Each worker:
  - Owns one Python process
  - Handles request/response communication
  - Manages health checks
  - Reports metrics
  """

  use GenServer, restart: :permanent
  require Logger

  alias DSPex.PythonBridge.Protocol

  @health_check_interval 30_000
  @init_timeout 10_000

  defstruct [
    :id,
    :port,
    :python_pid,
    :fingerprint,
    :start_time,
    :busy,
    :pending_requests,
    :health_status,
    :last_health_check,
    :stats
  ]

  # Client API

  @doc """
  Starts a Python worker process.
  """
  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: DSPex.Python.Registry.via_tuple(worker_id))
  end

  @doc """
  Executes a command on the worker.
  """
  def execute(worker_id, command, args, timeout \\ 30_000) do
    GenServer.call(
      DSPex.Python.Registry.via_tuple(worker_id),
      {:execute, command, args},
      timeout
    )
  end

  @doc """
  Checks if a worker is busy.
  """
  def busy?(worker_id) do
    GenServer.call(DSPex.Python.Registry.via_tuple(worker_id), :busy?)
  end

  @doc """
  Gets worker statistics.
  """
  def get_stats(worker_id) do
    GenServer.call(DSPex.Python.Registry.via_tuple(worker_id), :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :id)
    fingerprint = generate_fingerprint(worker_id)

    # Start Python process with fingerprint
    case start_python_port(fingerprint) do
      {:ok, port, python_pid} ->
        # Send initial ping to verify connection
        state = %__MODULE__{
          id: worker_id,
          port: port,
          python_pid: python_pid,
          fingerprint: fingerprint,
          start_time: System.system_time(:second),
          busy: false,
          pending_requests: %{},
          health_status: :initializing,
          stats: %{requests: 0, errors: 0, total_time: 0}
        }

        # Register worker with process tracking
        DSPex.Python.ProcessRegistry.register_worker(
          worker_id,
          self(),
          python_pid,
          fingerprint
        )

        # Send initialization ping
        {:ok, state, {:continue, :initialize}}

      {:error, reason} ->
        {:stop, {:failed_to_start_port, reason}}
    end
  end

  @impl true
  def handle_continue(:initialize, state) do
    # Send initialization ping
    request_id = System.unique_integer([:positive])

    request =
      Protocol.encode_request(request_id, "ping", %{
        "worker_id" => state.id,
        "initialization" => true
      })

    case Port.command(state.port, request) do
      true ->
        # Wait for ping response
        receive do
          {port, {:data, data}} when port == state.port ->
            case Protocol.decode_response(data) do
              {:ok, ^request_id, response} when is_map(response) ->
                # Accept any successful response that includes status ok
                if Map.get(response, "status") == "ok" do
                  Logger.info("Worker #{state.id} initialized successfully")

                  # Schedule health checks
                  Process.send_after(self(), :health_check, @health_check_interval)

                  {:noreply, %{state | health_status: :healthy}}
                else
                  Logger.error("Failed to initialize worker: #{inspect(response)}")
                  {:stop, {:initialization_failed, response}, state}
                end

              error ->
                Logger.error("Failed to initialize worker: #{inspect(error)}")
                {:stop, {:initialization_failed, error}, state}
            end
        after
          @init_timeout ->
            {:stop, :initialization_timeout, state}
        end

      false ->
        {:stop, :port_command_failed, state}
    end
  end

  @impl true
  def handle_call({:execute, _command, _args}, _from, %{busy: true} = state) do
    # Worker is busy, reject the request
    {:reply, {:error, :worker_busy}, state}
  end

  def handle_call({:execute, command, args}, from, state) do
    request_id = System.unique_integer([:positive])

    Logger.debug(
      "Worker #{state.id} executing command: #{command} with request_id: #{request_id}"
    )

    # Encode and send request
    request = Protocol.encode_request(request_id, command, args)

    case Port.command(state.port, request) do
      true ->
        # Track pending request
        pending = Map.put(state.pending_requests, request_id, {from, System.monotonic_time()})

        Logger.debug(
          "Worker #{state.id} sent request #{request_id}, pending count: #{map_size(pending)}"
        )

        {:noreply, %{state | busy: true, pending_requests: pending}}

      false ->
        {:reply, {:error, :port_command_failed}, state}
    end
  end

  def handle_call(:busy?, _from, state) do
    {:reply, state.busy, state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("Worker #{state.id} received data from port")

    case Protocol.decode_response(data) do
      {:ok, request_id, result} ->
        Logger.debug(
          "Worker #{state.id} decoded response for request #{request_id}: #{inspect(result)}"
        )

        handle_response(request_id, {:ok, result}, state)

      {:error, request_id, error} ->
        Logger.debug(
          "Worker #{state.id} decoded error for request #{request_id}: #{inspect(error)}"
        )

        handle_response(request_id, {:error, error}, state)

      other ->
        Logger.error("Worker #{state.id} - Invalid response from Python: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("Python port exited: #{inspect(reason)}")
    {:stop, {:port_exited, reason}, state}
  end

  def handle_info(:health_check, state) do
    # Send health check ping
    request_id = System.unique_integer([:positive])
    request = Protocol.encode_request(request_id, "ping", %{"health_check" => true})

    case Port.command(state.port, request) do
      true ->
        # Store health check request
        pending =
          Map.put(state.pending_requests, request_id, {:health_check, System.monotonic_time()})

        Process.send_after(self(), :health_check, @health_check_interval)
        {:noreply, %{state | pending_requests: pending}}

      false ->
        # Port is dead
        {:stop, :health_check_failed, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Worker #{state.id} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Worker #{state.id} terminating: #{inspect(reason)}")

    # Unregister from process tracking
    DSPex.Python.ProcessRegistry.unregister_worker(state.id)

    # Close the port gracefully
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  end

  # Private Functions

  defp start_python_port(_fingerprint) do
    python_path = System.find_executable("python3") || System.find_executable("python")
    script_path = Path.join(:code.priv_dir(:dspex), "python/dspy_bridge.py")

    # Use same port options as working V2 pool worker
    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4},
      {:args, [script_path, "--mode", "pool-worker"]}
    ]

    try do
      port = Port.open({:spawn_executable, python_path}, port_opts)
      
      # Extract Python process PID
      python_pid = case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end
      
      {:ok, port, python_pid}
    rescue
      e -> {:error, e}
    end
  end

  defp generate_fingerprint(worker_id) do
    timestamp = System.system_time(:nanosecond)
    random = :rand.uniform(1_000_000)
    "dspex_worker_#{worker_id}_#{timestamp}_#{random}"
  end

  defp handle_response(request_id, result, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _pending} ->
        # Unknown request ID
        Logger.warning("Received response for unknown request: #{request_id}")
        {:noreply, state}

      {{:health_check, start_time}, pending} ->
        # Health check response
        _duration = System.monotonic_time() - start_time

        health_status =
          case result do
            {:ok, _} -> :healthy
            {:error, _} -> :unhealthy
          end

        {:noreply,
         %{
           state
           | pending_requests: pending,
             health_status: health_status,
             last_health_check: System.monotonic_time()
         }}

      {{from, start_time}, pending} ->
        # Regular request response
        duration = System.monotonic_time() - start_time

        # Update stats
        stats = update_stats(state.stats, result, duration)

        # Reply to caller
        GenServer.reply(from, result)

        {:noreply, %{state | busy: false, pending_requests: pending, stats: stats}}
    end
  end

  defp update_stats(stats, result, duration) do
    stats
    |> Map.update!(:requests, &(&1 + 1))
    |> Map.update!(:errors, fn errors ->
      case result do
        {:ok, _} -> errors
        {:error, _} -> errors + 1
      end
    end)
    |> Map.update!(:total_time, &(&1 + duration))
  end
end

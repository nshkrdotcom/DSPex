defmodule DSPex.Python.Pool do
  @moduledoc """
  Pool manager for Python workers with concurrent initialization.

  Features:
  - Concurrent worker startup (all workers start in parallel)
  - Simple queue-based request distribution
  - Non-blocking async execution
  - Automatic request queueing when workers are busy
  """

  use GenServer
  require Logger

  @default_size System.schedulers_online() * 2
  @startup_timeout 10_000
  @queue_timeout 5_000

  defstruct [
    :size,
    :workers,
    :available,
    :busy,
    :request_queue,
    :stats,
    :initialized,
    :python_pids  # Track Python PIDs for cleanup
  ]

  # Client API

  @doc """
  Starts the pool manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc """
  Executes a command on any available worker.
  """
  def execute(command, args, opts \\ []) do
    pool = opts[:pool] || __MODULE__
    timeout = opts[:timeout] || 60_000

    GenServer.call(pool, {:execute, command, args, opts}, timeout)
  end

  @doc """
  Executes a command in session context with enhanced args.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    # Enhance args with session data like V2 pool does
    enhanced_args = enhance_args_with_session_data(args, session_id, command)

    case execute(command, enhanced_args, opts) do
      {:ok, response} when command == "create_program" ->
        # Store program data in SessionStore after creation
        case store_program_data_after_creation(session_id, args, response) do
          {:error, reason} ->
            Logger.warning("Program created but failed to store metadata: #{inspect(reason)}")

          :ok ->
            :ok
        end

        {:ok, response}

      result ->
        result
    end
  end

  @doc """
  Gets pool statistics.
  """
  def get_stats(pool \\ __MODULE__) do
    GenServer.call(pool, :get_stats)
  end

  @doc """
  Lists all worker IDs in the pool.
  """
  def list_workers(pool \\ __MODULE__) do
    GenServer.call(pool, :list_workers)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    size = opts[:size] || @default_size

    state = %__MODULE__{
      size: size,
      workers: [],
      available: :queue.new(),
      busy: %{},
      request_queue: :queue.new(),
      stats: %{
        requests: 0,
        queued: 0,
        errors: 0,
        queue_timeouts: 0
      },
      initialized: false,
      python_pids: MapSet.new()  # Track Python PIDs
    }

    # Start concurrent worker initialization
    {:ok, state, {:continue, :initialize_workers}}
  end

  @impl true
  def handle_continue(:initialize_workers, state) do
    Logger.info("🚀 Starting concurrent initialization of #{state.size} workers...")
    start_time = System.monotonic_time(:millisecond)

    # Start all workers concurrently
    workers = start_workers_concurrently(state.size)

    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.info("✅ Initialized #{length(workers)}/#{state.size} workers in #{elapsed}ms")

    if length(workers) == 0 do
      {:stop, :no_workers_started, state}
    else
      # Initialize available queue with all workers
      available =
        Enum.reduce(workers, :queue.new(), fn worker_id, q ->
          :queue.in(worker_id, q)
        end)

      {:noreply, %{state | workers: workers, available: available, initialized: true}}
    end
  end

  @impl true
  def handle_call({:execute, command, args, opts}, from, state) do
    if not state.initialized do
      {:reply, {:error, :pool_not_initialized}, state}
    else
      case checkout_worker(state) do
        {:ok, worker_id, new_state} ->
          # Execute asynchronously
          pool_pid = self()

          Task.start(fn ->
            result = execute_on_worker(worker_id, command, args, opts)
            GenServer.cast(pool_pid, {:worker_complete, worker_id, from, result})
          end)

          # Update stats
          stats = Map.update!(state.stats, :requests, &(&1 + 1))
          {:noreply, %{new_state | stats: stats}}

        {:error, :no_workers} ->
          # Queue the request
          request = {from, command, args, opts, System.monotonic_time()}
          new_queue = :queue.in(request, state.request_queue)

          # Update stats
          stats =
            state.stats
            |> Map.update!(:requests, &(&1 + 1))
            |> Map.update!(:queued, &(&1 + 1))

          # Set queue timeout
          Process.send_after(self(), {:queue_timeout, from}, @queue_timeout)

          {:noreply, %{state | request_queue: new_queue, stats: stats}}
      end
    end
  end

  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        workers: length(state.workers),
        available: :queue.len(state.available),
        busy: map_size(state.busy),
        queued: :queue.len(state.request_queue)
      })

    {:reply, stats, state}
  end

  def handle_call(:list_workers, _from, state) do
    {:reply, state.workers, state}
  end

  @impl true
  def handle_cast({:worker_complete, worker_id, from, result}, state) do
    # Reply to original caller
    GenServer.reply(from, result)

    # Update error stats if needed
    stats =
      case result do
        {:error, _} -> Map.update!(state.stats, :errors, &(&1 + 1))
        _ -> state.stats
      end

    # Check for queued requests
    case :queue.out(state.request_queue) do
      {{:value, {queued_from, command, args, opts, _queued_at}}, new_queue} ->
        # Give worker to queued request
        pool_pid = self()

        Task.start(fn ->
          result = execute_on_worker(worker_id, command, args, opts)
          GenServer.cast(pool_pid, {:worker_complete, worker_id, queued_from, result})
        end)

        {:noreply, %{state | request_queue: new_queue, stats: stats}}

      {:empty, _} ->
        # Return worker to available pool
        new_available = :queue.in(worker_id, state.available)
        new_busy = Map.delete(state.busy, worker_id)

        {:noreply, %{state | available: new_available, busy: new_busy, stats: stats}}
    end
  end

  @impl true
  def handle_info({:queue_timeout, from}, state) do
    # Remove request from queue if still there
    new_queue =
      :queue.filter(
        fn
          {^from, _, _, _, _} -> false
          _ -> true
        end,
        state.request_queue
      )

    # Reply with timeout error if request was still queued
    if :queue.len(new_queue) < :queue.len(state.request_queue) do
      GenServer.reply(from, {:error, :queue_timeout})

      stats = Map.update!(state.stats, :queue_timeouts, &(&1 + 1))
      {:noreply, %{state | request_queue: new_queue, stats: stats}}
    else
      # Request already processed
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Worker died, remove from pool
    case Enum.find(state.workers, fn worker_id ->
           case DSPex.Python.Registry.get_worker_pid(worker_id) do
             {:ok, ^pid} -> true
             _ -> false
           end
         end) do
      nil ->
        {:noreply, state}

      worker_id ->
        Logger.error("Worker #{worker_id} died: #{inspect(reason)}")

        # Remove from all queues
        new_workers = List.delete(state.workers, worker_id)
        new_available = :queue.filter(&(&1 != worker_id), state.available)
        new_busy = Map.delete(state.busy, worker_id)

        # Try to start replacement worker
        Task.start(fn ->
          case DSPex.Python.WorkerSupervisor.start_worker(worker_id) do
            {:ok, _} ->
              GenServer.cast(self(), {:worker_restarted, worker_id})

            _ ->
              :ok
          end
        end)

        {:noreply, %{state | workers: new_workers, available: new_available, busy: new_busy}}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Pool received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("🛑 Pool shutting down: #{inspect(reason)}")
    
    # Kill only OUR Python processes, not all processes on the system
    killed_count = kill_pool_worker_processes(state)
    
    Logger.warning("✅ Pool shutdown completed - killed #{killed_count} worker processes")
    :ok
  end

  # Private Functions

  defp kill_pool_worker_processes(state) do
    Logger.warning("🔥 Killing Python processes for pool workers...")
    
    # Get all workers from this pool
    worker_ids = state.workers || []
    
    killed_count = Enum.reduce(worker_ids, 0, fn worker_id, acc ->
      # Get Python PID from ProcessRegistry
      case DSPex.Python.ProcessRegistry.get_worker_info(worker_id) do
        {:ok, %{python_pid: python_pid}} when is_integer(python_pid) ->
          case kill_python_process(python_pid, worker_id) do
            :ok -> 
              Logger.warning("✅ Killed Python process #{python_pid} for worker #{worker_id}")
              acc + 1
            :error -> 
              Logger.warning("⚠️ Failed to kill Python process #{python_pid} for worker #{worker_id}")
              acc
          end
        _ ->
          Logger.warning("⚠️ No Python PID found for worker #{worker_id}")
          acc
      end
    end)
    
    # Also try to get Python PIDs from the tracked set if available
    tracked_pids = MapSet.to_list(state.python_pids || MapSet.new())
    
    additional_killed = Enum.reduce(tracked_pids, 0, fn python_pid, acc ->
      case kill_python_process(python_pid, "tracked") do
        :ok -> 
          Logger.warning("✅ Killed tracked Python process #{python_pid}")
          acc + 1
        :error -> 
          acc
      end
    end)
    
    killed_count + additional_killed
  end
  
  defp kill_python_process(python_pid, _worker_id) when is_integer(python_pid) do
    try do
      # Use SIGKILL for immediate termination
      case System.cmd("kill", ["-KILL", "#{python_pid}"], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok
        {_error, _} ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp start_workers_concurrently(count) do
    1..count
    |> Task.async_stream(
      fn i ->
        worker_id = "python_worker_#{i}_#{:erlang.unique_integer([:positive])}"

        case DSPex.Python.WorkerSupervisor.start_worker(worker_id) do
          {:ok, _pid} ->
            Logger.info("✅ Worker #{i}/#{count} ready: #{worker_id}")
            worker_id

          {:error, reason} ->
            Logger.error("❌ Worker #{i}/#{count} failed: #{inspect(reason)}")
            nil
        end
      end,
      timeout: @startup_timeout,
      max_concurrency: count,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, worker_id} ->
        worker_id

      {:exit, reason} ->
        Logger.error("Worker startup task failed: #{inspect(reason)}")
        nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp checkout_worker(state) do
    case :queue.out(state.available) do
      {{:value, worker_id}, new_available} ->
        new_busy = Map.put(state.busy, worker_id, true)
        {:ok, worker_id, %{state | available: new_available, busy: new_busy}}

      {:empty, _} ->
        {:error, :no_workers}
    end
  end

  defp execute_on_worker(worker_id, command, args, opts) do
    timeout = opts[:timeout] || 30_000

    try do
      DSPex.Python.Worker.execute(worker_id, command, args, timeout)
    catch
      :exit, {:timeout, _} ->
        {:error, :worker_timeout}

      :exit, reason ->
        {:error, {:worker_exit, reason}}
    end
  end

  # Enhanced args with session data (from V2 pool)
  defp enhance_args_with_session_data(args, session_id, command) do
    base_args =
      if session_id,
        do: Map.put(args, :session_id, session_id),
        else: Map.put(args, :session_id, "anonymous")

    # For execute_program commands, fetch program data from SessionStore
    if command == "execute_program" do
      program_id = Map.get(args, :program_id)

      case DSPex.PythonBridge.SessionStore.get_program(session_id, program_id) do
        {:ok, program_data} ->
          Map.put(base_args, :program_data, program_data)

        {:error, _reason} ->
          # Program not found in session store - let Python handle the error
          base_args
      end
    else
      base_args
    end
  end

  # Store program data after creation (from V2 pool)
  defp store_program_data_after_creation(session_id, _create_args, create_response) do
    if session_id != nil and session_id != "anonymous" do
      program_id = Map.get(create_response, "program_id")

      if program_id do
        # Extract complete serializable program data from Python response
        program_data = %{
          program_id: program_id,
          signature_def:
            Map.get(create_response, "signature_def", Map.get(create_response, "signature", %{})),
          signature_class: Map.get(create_response, "signature_class"),
          field_mapping: Map.get(create_response, "field_mapping", %{}),
          fallback_used: Map.get(create_response, "fallback_used", false),
          created_at: System.system_time(:second),
          execution_count: 0,
          last_executed: nil,
          program_type: Map.get(create_response, "program_type", "predict"),
          signature: Map.get(create_response, "signature", %{})
        }

        store_program_in_session(session_id, program_id, program_data)
      end
    end
  end

  # Store program in SessionStore
  defp store_program_in_session(session_id, program_id, program_data) do
    if session_id != nil and session_id != "anonymous" do
      case DSPex.PythonBridge.SessionStore.get_session(session_id) do
        {:ok, _session} ->
          # Update existing session
          DSPex.PythonBridge.SessionStore.store_program(session_id, program_id, program_data)

        {:error, :not_found} ->
          # Create new session with program
          case DSPex.PythonBridge.SessionStore.create_session(session_id) do
            {:ok, _session} ->
              DSPex.PythonBridge.SessionStore.store_program(session_id, program_id, program_data)

            error ->
              error
          end

        error ->
          error
      end
    else
      :ok
    end
  end
end

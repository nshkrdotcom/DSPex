defmodule DSPex.PythonBridge.SessionPoolV2 do
  @moduledoc """
  Minimal session pool manager for Python bridge workers.

  This version implements a streamlined, stateless pooling approach focused on
  the "Golden Path" architecture. It provides essential pooling functionality
  without complex enterprise features.

  Key features:
  - Session affinity to maintain Python process state
  - Direct port communication between clients and Python processes
  - Simple error handling with structured error responses
  - ETS-based session tracking for observability only
  - Focus on PoolWorkerV2 (not Enhanced variants)
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.{
    PoolWorkerV2,
    Protocol,
    SessionStore
  }

  # Configuration defaults - reduced for resource efficiency
  @default_pool_size 4
  @default_overflow 2
  # 75s to allow for worker initialization (5-6s) + operation buffer
  @default_checkout_timeout 75_000
  # 60s timeout for real AI operations
  @default_operation_timeout 60_000
  @health_check_interval 30_000
  @session_cleanup_interval 300_000

  # ETS table for session tracking (monitoring only)
  @session_table :dspex_pool_sessions

  # State structure
  defstruct [
    :pool_name,
    :pool_pid,
    :pool_size,
    :overflow,
    :health_check_ref,
    :cleanup_ref,
    :started_at,
    :worker_module
  ]

  ## Public API - Client Functions

  @doc """
  Executes a command within a session context.

  This function runs in the CLIENT process, not the pool manager.
  It provides direct port communication with simple error handling.

  ## Parameters
  - session_id: String identifier for session tracking (observability only)
  - command: Atom representing the command to execute
  - args: Map of arguments to pass to the Python process
  - opts: Keyword list of options (pool_name, timeout, etc.)

  ## Returns
  - {:ok, result} on success
  - {:error, {category, type, message, context}} on error
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Track session for monitoring and affinity
    track_session(session_id)

    try do
      # Use any available worker - session data is centralized in SessionStore
      result =
        NimblePool.checkout!(
          pool_name,
          :any_worker,
          fn _from, worker ->
            # All session data is in SessionStore, any worker can handle any session
            execute_with_worker(worker, command, args, operation_timeout, session_id)
          end,
          pool_timeout
        )

      # Handle program creation storage (Task 2.1)
      case result do
        {:ok, response} when command == :create_program ->
          case store_program_data_after_creation(session_id, args, response) do
            {:error, reason} ->
              Logger.warning(
                "Program created successfully but failed to store metadata: #{inspect(reason)}"
              )

            _ ->
              :ok
          end

          update_session_activity(session_id)

        {:ok, _} ->
          update_session_activity(session_id)

        _ ->
          :ok
      end

      result
    catch
      :exit, {:timeout, _} ->
        {:error,
         {:timeout_error, :checkout_timeout, "No workers available",
          %{pool_name: pool_name, session_id: session_id}}}

      :exit, {:noproc, _} ->
        {:error,
         {:resource_error, :pool_not_available, "Pool not started", %{pool_name: pool_name}}}

      :exit, reason ->
        {:error,
         {:system_error, :pool_exit, "Pool process exited",
          %{reason: reason, session_id: session_id}}}

      kind, error ->
        {:error,
         {:system_error, :unexpected_error, "Unexpected error during checkout",
          %{kind: kind, error: error, session_id: session_id}}}
    end
  end

  @doc """
  Executes a command without session binding.

  This function runs in the CLIENT process for anonymous operations.
  Provides the same functionality as execute_in_session/4 but without session tracking.

  ## Parameters
  - command: Atom representing the command to execute
  - args: Map of arguments to pass to the Python process
  - opts: Keyword list of options (pool_name, timeout, etc.)

  ## Returns
  - {:ok, result} on success
  - {:error, {category, type, message, context}} on error
  """
  def execute_anonymous(command, args, opts \\ []) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    try do
      result =
        NimblePool.checkout!(
          pool_name,
          :anonymous,
          fn _from, worker ->
            execute_with_worker(worker, command, args, operation_timeout, "anonymous")
          end,
          pool_timeout
        )

      # Handle global program storage for anonymous operations
      case result do
        {:ok, response} when command == :create_program ->
          program_id = Map.get(response, "program_id")
          log_debug("🔄 Storing anonymous program globally: #{program_id}")

          case store_anonymous_program_globally(args, response) do
            {:error, reason} ->
              log_debug(
                "Anonymous program created successfully but failed to store globally: #{inspect(reason)}"
              )

            :ok ->
              log_debug("✅ Anonymous program stored globally: #{program_id}")
          end

        _ ->
          :ok
      end

      result
    catch
      :exit, {:timeout, _} ->
        {:error,
         {:timeout_error, :checkout_timeout, "No workers available", %{pool_name: pool_name}}}

      :exit, {:noproc, _} ->
        {:error,
         {:resource_error, :pool_not_available, "Pool not started", %{pool_name: pool_name}}}

      :exit, reason ->
        {:error, {:system_error, :pool_exit, "Pool process exited", %{reason: reason}}}

      kind, error ->
        {:error,
         {:system_error, :unexpected_error, "Unexpected error during checkout",
          %{kind: kind, error: error}}}
    end
  end

  ## Private Worker Communication Functions

  @spec execute_with_worker(map(), atom(), map(), pos_integer(), String.t() | nil) ::
          {{:ok, term()} | {:error, term()}, atom()}
  defp execute_with_worker(worker, command, args, timeout, session_id) do
    # Generate request ID and encode
    request_id = System.unique_integer([:positive, :monotonic])

    # Enhance args with session data for stateless workers
    enhanced_args = enhance_args_with_session_data(args, session_id, command)

    # Conditional logging for cross-worker execution
    if command == :execute_program do
      program_id = Map.get(args, :program_id)
      has_program_data = Map.has_key?(enhanced_args, :program_data)
      log_worker_execution(worker.worker_id, program_id, has_program_data, session_id)
    end

    try do
      request_payload = Protocol.encode_request(request_id, command, enhanced_args)

      # Send command to port
      port = worker.port
      Port.command(port, request_payload)

      # Wait for response with simple error handling
      receive do
        {^port, {:data, data}} ->
          log_debug(
            "Raw response from Python worker #{worker.worker_id}: #{inspect(data, limit: 500)}"
          )

          case Protocol.decode_response(data) do
            {:ok, ^request_id, response} when is_map(response) ->
              log_debug(
                "Success response from worker #{worker.worker_id}: #{inspect(response, limit: 500)}"
              )

              {{:ok, response}, :ok}

            {:ok, other_id, _} ->
              error =
                {:communication_error, :response_mismatch,
                 "Expected ID #{request_id}, got #{other_id}",
                 %{expected_id: request_id, actual_id: other_id, worker_id: worker.worker_id}}

              Logger.error("Response mismatch from worker #{worker.worker_id}: #{inspect(error)}")
              # Response mismatch is recoverable - keep worker but track failure
              {{:error, error}, :error}

            {:error, _id, reason} ->
              error =
                {:communication_error, :python_error, reason,
                 %{worker_id: worker.worker_id, session_id: session_id}}

              # Log differently based on test mode
              if get_test_mode() do
                log_test_error(worker.worker_id, reason)
              else
                Logger.error("Python error from worker #{worker.worker_id}: #{inspect(error)}")
              end

              {{:error, error}, :ok}

            {:error, reason} ->
              error =
                {:communication_error, :decode_error,
                 "Failed to decode response: #{inspect(reason)}",
                 %{decode_reason: reason, worker_id: worker.worker_id}}

              Logger.error("Decode error from worker #{worker.worker_id}: #{inspect(error)}")
              # Decode errors might be recoverable - keep worker
              {{:error, error}, :error}
          end

        {^port, {:exit_status, status}} ->
          error =
            {:communication_error, :port_exited, "Python process exited with status #{status}",
             %{exit_status: status, worker_id: worker.worker_id}}

          {{:error, error}, :close}
      after
        timeout ->
          Logger.error(
            "TIMEOUT: No response from Python worker #{worker.worker_id} for command #{command} after #{timeout}ms"
          )

          error =
            {:timeout_error, :command_timeout, "Command timed out after #{timeout}ms",
             %{timeout_ms: timeout, worker_id: worker.worker_id, command: command}}

          # Single timeout is recoverable - keep worker
          {{:error, error}, :error}
      end
    catch
      :exit, {:timeout, _} ->
        error =
          {:timeout_error, :command_timeout, "Command timed out after #{timeout}ms",
           %{timeout_ms: timeout, worker_id: worker.worker_id, command: command}}

        # Exit timeout is recoverable - keep worker
        {{:error, error}, :error}

      :error, {:badarg, _} ->
        error =
          {:communication_error, :port_send_failed, "Port.command/2 failed - port may be closed",
           %{worker_id: worker.worker_id}}

        # Port send failure is likely fatal - remove worker
        {{:error, error}, :close}

      kind, error ->
        error_tuple =
          {:system_error, :command_error, "Unexpected error during command execution",
           %{error_kind: kind, error: error, worker_id: worker.worker_id}}

        # System errors are likely fatal - remove worker
        {{:error, error_tuple}, :close}
    end
  end

  ## Enhanced Logging Functions

  defp get_test_mode do
    :persistent_term.get({:dspex, :test_mode}, false)
  end

  defp get_error_handling_config do
    Application.get_env(:dspex, :error_handling, [])
  end

  defp should_log_verbose_worker_details? do
    config = get_error_handling_config()
    debug_mode = Keyword.get(config, :debug_mode, false)
    clean_output = Keyword.get(config, :clean_output, true)

    # Show verbose details only in debug mode, suppress when clean_output is enabled
    debug_mode and not clean_output
  end

  defp log_debug(message) do
    if should_log_verbose_worker_details?() do
      Logger.info(message)
    end
  end

  defp log_worker_execution(worker_id, program_id, has_data, session_id) do
    if should_log_verbose_worker_details?() do
      Logger.info(
        "🔍 Execute program on worker #{worker_id}: program_id=#{program_id}, has_program_data=#{has_data}, session_id=#{session_id}"
      )

      if has_data do
        Logger.info("✅ Program data included for cross-worker execution")
      else
        Logger.warning("❌ NO program data found for program #{program_id} on worker #{worker_id}")
      end
    end
  end

  defp log_test_error(worker_id, reason) do
    config = get_error_handling_config()
    clean_output = Keyword.get(config, :clean_output, true)

    if clean_output do
      # Clean test output - minimal logging
      cond do
        String.contains?(reason, "Program not found") ->
          Logger.info("🧪 Expected test error: Invalid program ID handled by worker #{worker_id}")

        String.contains?(reason, "Unknown command") ->
          Logger.info("🧪 Expected test error: Unknown command handled by worker #{worker_id}")

        String.contains?(reason, "Missing") ->
          Logger.info(
            "🧪 Expected test error: Missing required inputs handled by worker #{worker_id}"
          )

        true ->
          Logger.info(
            "🧪 Test error handled by worker #{worker_id}: #{String.slice(reason, 0, 100)}"
          )
      end
    else
      # Verbose test output - show full details
      cond do
        String.contains?(reason, "Program not found") ->
          Logger.info("🧪 Expected test error: Invalid program ID handled by worker #{worker_id}")
          Logger.info("   Full error: #{reason}")

        String.contains?(reason, "Unknown command") ->
          Logger.info("🧪 Expected test error: Unknown command handled by worker #{worker_id}")
          Logger.info("   Full error: #{reason}")

        String.contains?(reason, "Missing") ->
          Logger.info(
            "🧪 Expected test error: Missing required inputs handled by worker #{worker_id}"
          )

          Logger.info("   Full error: #{reason}")

        true ->
          Logger.error("Python error from worker #{worker_id}: #{inspect(reason)}")
      end
    end
  end

  ## Session Management Functions

  @doc """
  Tracks a session in ETS for monitoring.
  """
  def track_session(session_id) do
    _result = ensure_session_table()

    session_info = %{
      session_id: session_id,
      started_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond),
      operations: 0
    }

    _result = :ets.insert(@session_table, {session_id, session_info})
    :ok
  end

  @doc """
  Updates session activity timestamp.
  """
  def update_session_activity(session_id) do
    _result = ensure_session_table()

    case :ets.lookup(@session_table, session_id) do
      [{^session_id, info}] ->
        updated_info = %{
          info
          | last_activity: System.monotonic_time(:millisecond),
            operations: info.operations + 1
        }

        _result = :ets.insert(@session_table, {session_id, updated_info})
        :ok

      [] ->
        # If session doesn't exist, create it with 1 operation
        session_info = %{
          session_id: session_id,
          started_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond),
          operations: 1
        }

        _result = :ets.insert(@session_table, {session_id, session_info})
        :ok
    end
  end

  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    # Clean up monitoring data
    _result = ensure_session_table()
    _result = :ets.delete(@session_table, session_id)

    # Clean up centralized session data
    SessionStore.delete_session(session_id)
    :ok
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    _result = ensure_session_table()

    :ets.tab2list(@session_table)
    |> Enum.map(fn {_id, info} -> info end)
  end

  ## Pool Management API (GenServer)

  @doc """
  Starts the session pool manager.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current pool status.
  """
  def get_pool_status(pool_name \\ __MODULE__) do
    GenServer.call(pool_name, :get_status)
  end

  @doc """
  Gets the actual pool name for a given GenServer name.
  """
  def get_pool_name_for(genserver_name \\ __MODULE__) do
    GenServer.call(genserver_name, :get_pool_name)
  end

  @doc """
  Performs a health check on the pool.
  """
  def health_check(pool_name \\ __MODULE__) do
    GenServer.call(pool_name, :health_check)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize session tracking table (monitoring only)
    _result = ensure_session_table()

    # In minimal pooling, we only use PoolWorkerV2 (not Enhanced)
    worker_module = Keyword.get(opts, :worker_module, PoolWorkerV2)

    # Parse configuration
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)

    # Get name from opts or generate unique pool name
    genserver_name = Keyword.get(opts, :name, __MODULE__)
    pool_name = :"#{genserver_name}_pool"

    # Start NimblePool with lazy initialization to control worker creation
    pool_config = [
      worker: {worker_module, []},
      pool_size: pool_size,
      max_overflow: overflow,
      # Use lazy initialization so we can control concurrent worker creation
      lazy: true,
      name: pool_name
    ]

    case NimblePool.start_link(pool_config) do
      {:ok, pool_pid} ->
        # Schedule periodic tasks
        health_check_ref = schedule_health_check()
        cleanup_ref = schedule_cleanup()

        state = %__MODULE__{
          pool_name: pool_name,
          pool_pid: pool_pid,
          pool_size: pool_size,
          overflow: overflow,
          health_check_ref: health_check_ref,
          cleanup_ref: cleanup_ref,
          started_at: System.monotonic_time(:millisecond),
          worker_module: worker_module
        }

        Logger.info(
          "Minimal session pool V2 started with #{pool_size} workers, #{overflow} overflow"
        )

        # Force concurrent worker initialization
        spawn(fn -> pre_warm_workers(pool_name, pool_size) end)

        {:ok, state}

      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    sessions = get_session_info()

    # Session affinity is maintained through NimblePool
    affinity_stats = %{active_sessions: length(sessions)}

    status = %{
      pool_size: state.pool_size,
      max_overflow: state.overflow,
      active_sessions: length(sessions),
      sessions: sessions,
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at,
      session_affinity: affinity_stats
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_pool_name, _from, state) do
    {:reply, state.pool_name, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # For now, just return a simple status
    # In production, you'd check each worker's health
    {:reply, {:ok, :healthy}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    # In production, iterate through workers and check their health

    # Reschedule
    health_check_ref = schedule_health_check()
    {:noreply, %{state | health_check_ref: health_check_ref}}
  end

  @impl true
  def handle_info(:cleanup_stale_sessions, state) do
    # Clean up stale sessions from ETS
    now = System.monotonic_time(:millisecond)
    # 1 hour
    stale_timeout = 3600_000

    _result = ensure_session_table()

    # Find and remove stale sessions
    stale_sessions =
      :ets.select(@session_table, [
        {
          {:"$1", %{last_activity: :"$2"}},
          [{:<, :"$2", now - stale_timeout}],
          [:"$1"]
        }
      ])

    Enum.each(stale_sessions, fn session_id ->
      Logger.warning("Cleaning up stale session: #{session_id}")
      _result = :ets.delete(@session_table, session_id)
    end)

    # Reschedule
    cleanup_ref = schedule_cleanup()
    {:noreply, %{state | cleanup_ref: cleanup_ref}}
  end

  @impl true
  def handle_info({:replace_worker, worker_id, metadata}, state) do
    Logger.info("Received request to replace worker #{worker_id}: #{inspect(metadata)}")

    # NimblePool handles worker creation automatically when workers are removed
    # We just need to track metrics here

    # TODO: Add telemetry when available
    # :telemetry.execute(
    #   [:dspex, :pool, :worker, :replaced],
    #   %{count: 1},
    #   %{
    #     worker_id: worker_id,
    #     reason: Map.get(metadata, :reason, :unknown),
    #     pool_name: state.pool_name
    #   }
    # )

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel timers
    _result1 = Process.cancel_timer(state.health_check_ref)
    _result2 = Process.cancel_timer(state.cleanup_ref)

    # Stop the pool with longer timeout and confirmation (Phase 2A fix)
    if state.pool_pid do
      try do
        # Increased timeout
        NimblePool.stop(state.pool_name, :shutdown, 15_000)
      catch
        # Ignore shutdown errors in tests
        _, _ -> :ok
      end
    end

    :ok
  end

  ## Private Functions

  defp get_default_pool_name do
    :"#{__MODULE__}_pool"
  end

  defp normalize_opts(opts) when is_map(opts) do
    Enum.to_list(opts)
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(_), do: []

  defp ensure_session_table do
    case :ets.whereis(@session_table) do
      :undefined ->
        :ets.new(@session_table, [:set, :public, :named_table])

      _tid ->
        :ok
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_sessions, @session_cleanup_interval)
  end

  ## Session Management Functions (using centralized SessionStore)

  # Enhances command arguments with session data for stateless workers.
  # For stateless workers, this function fetches necessary session data
  # from the SessionStore and includes it in the command arguments.
  defp enhance_args_with_session_data(args, session_id, command) do
    base_args =
      if session_id,
        do: Map.put(args, :session_id, session_id),
        else: Map.put(args, :session_id, "anonymous")

    # For execute_program commands, fetch program data
    if command == :execute_program do
      program_id = Map.get(args, :program_id)

      if program_id do
        cond do
          # Named session: check SessionStore
          session_id != nil and session_id != "anonymous" ->
            case SessionStore.get_session(session_id) do
              {:ok, session} ->
                program_data = Map.get(session.programs, program_id)

                if program_data do
                  Map.put(base_args, :program_data, program_data)
                else
                  Logger.debug("Program #{program_id} not found in session #{session_id}")
                  base_args
                end

              {:error, reason} ->
                Logger.debug("Session #{session_id} not found: #{inspect(reason)}")
                base_args
            end

          # Anonymous session: check global program storage
          session_id == "anonymous" ->
            case SessionStore.get_global_program(program_id) do
              {:ok, program_data} ->
                log_debug("✅ Found global program #{program_id} for anonymous execution")
                Map.put(base_args, :program_data, program_data)

              {:error, :not_found} ->
                log_debug("❌ Global program #{program_id} not found for anonymous execution")
                base_args
            end

          true ->
            base_args
        end
      else
        base_args
      end
    else
      base_args
    end
  end

  # Stores program data in the SessionStore after successful creation.
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

  # Stores program data in the SessionStore.
  defp store_program_in_session(session_id, program_id, program_data) do
    if session_id != nil and session_id != "anonymous" do
      case SessionStore.get_session(session_id) do
        {:ok, _session} ->
          # Update existing session
          SessionStore.update_session(session_id, fn session ->
            %{session | programs: Map.put(session.programs, program_id, program_data)}
          end)

        {:error, :not_found} ->
          # Create new session
          {:ok, _session} = SessionStore.create_session(session_id)

          SessionStore.update_session(session_id, fn session ->
            %{session | programs: Map.put(session.programs, program_id, program_data)}
          end)
      end
    end
  end

  # Stores anonymous program data in global storage.
  defp store_anonymous_program_globally(_create_args, create_response) do
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

      SessionStore.store_global_program(program_id, program_data)
    else
      {:error, :no_program_id}
    end
  end

  ## Worker Pre-warming for Concurrent Initialization

  # Force concurrent worker initialization by exercising all workers in parallel.
  # This overcomes NimblePool's sequential worker creation by forcing checkout/checkin.
  defp pre_warm_workers(pool_name, pool_size) do
    Logger.info("Pre-warming #{pool_size} workers concurrently...")
    start_time = System.monotonic_time(:millisecond)

    # Create parallel tasks to checkout and warm up each worker
    warmup_tasks =
      for i <- 1..pool_size do
        Task.async(fn ->
          try do
            case execute_anonymous(:ping, %{warmup: true, slot: i},
                   pool_name: pool_name,
                   pool_timeout: 15_000,
                   timeout: 10_000
                 ) do
              {:ok, response} ->
                worker_id = Map.get(response, "worker_id", "unknown")
                Logger.info("Worker #{i} (#{worker_id}) warmed up successfully")
                {:ok, i, worker_id}

              {:error, reason} ->
                Logger.warning("Worker #{i} warmup failed: #{inspect(reason)}")
                {:error, i, reason}
            end
          rescue
            error ->
              Logger.warning("Worker #{i} warmup exception: #{inspect(error)}")
              {:error, i, error}
          end
        end)
      end

    # Wait for all workers to complete warmup
    results = Task.await_many(warmup_tasks, 30_000)

    # Report results
    successful = Enum.count(results, fn {status, _, _} -> status == :ok end)
    total_time = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "Pre-warming complete: #{successful}/#{pool_size} workers ready in #{total_time}ms"
    )

    if successful == pool_size do
      Logger.info("✅ All workers initialized concurrently - pool ready for requests")
    else
      Logger.warning("⚠️  #{pool_size - successful} workers failed to initialize")
    end

    results
  end

  ## Supervisor Integration

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end
end

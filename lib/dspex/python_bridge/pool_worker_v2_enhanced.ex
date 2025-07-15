defmodule DSPex.PythonBridge.PoolWorkerV2Enhanced do
  @moduledoc """
  Enhanced worker implementation with state machine and health monitoring.

  This version adds:
  - Formal state machine for worker lifecycle management
  - Health monitoring with recovery strategies  
  - Session affinity tracking
  - Comprehensive error handling and recovery
  - Worker metrics and telemetry

  The worker follows a strict state machine that ensures proper lifecycle management
  and provides visibility into worker health and performance.
  """

  @behaviour NimblePool

  alias DSPex.PythonBridge.{WorkerStateMachine, Protocol}
  require Logger

  # Worker record with state machine
  defstruct [
    :port,
    :python_path,
    :script_path,
    :worker_id,
    :current_session,
    :state_machine,
    :health_check_failures,
    :last_health_check,
    :stats,
    :started_at
  ]

  # 30 seconds
  @health_check_interval 30_000
  @max_health_failures 3
  @init_timeout 5_000
  @health_check_timeout 5_000

  ## NimblePool Callbacks

  @impl NimblePool
  def init_worker(pool_state) do
    worker_id = generate_worker_id()
    state_machine = WorkerStateMachine.new(worker_id)

    Logger.debug("Initializing enhanced pool worker: #{worker_id}")

    case start_python_process(worker_id) do
      {:ok, port, python_path, script_path} ->
        worker = %__MODULE__{
          port: port,
          python_path: python_path,
          script_path: script_path,
          worker_id: worker_id,
          current_session: nil,
          state_machine: state_machine,
          health_check_failures: 0,
          last_health_check: System.monotonic_time(:millisecond),
          stats: init_stats(),
          started_at: System.monotonic_time(:millisecond)
        }

        case perform_initialization(worker) do
          {:ok, initialized_worker} ->
            # Record successful worker creation
            try do
              alias DSPex.PythonBridge.WorkerMetrics
              WorkerMetrics.record_lifecycle(worker_id, :created)
            rescue
              _ -> :ok
            end

            {:ok, transition_to_ready(initialized_worker), pool_state}

          {:error, reason} ->
            Logger.error("Worker #{worker_id} initialization failed: #{inspect(reason)}")
            Port.close(port)
            raise "Worker initialization failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        Logger.error("Failed to start Python process for worker #{worker_id}: #{inspect(reason)}")
        raise "Failed to start Python process: #{inspect(reason)}"
    end
  end

  @impl NimblePool
  def handle_checkout(checkout_type, from, worker, pool_state) do
    case WorkerStateMachine.can_accept_work?(worker.state_machine) do
      true ->
        perform_checkout(checkout_type, from, worker, pool_state)

      false ->
        Logger.debug(
          "Worker #{worker.worker_id} not ready for checkout, state: #{worker.state_machine.state}, health: #{worker.state_machine.health}"
        )

        {:remove, {:worker_not_ready, worker.state_machine.state}, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkin(checkin_type, _from, worker, pool_state) do
    Logger.debug("Worker #{worker.worker_id} checkin with type: #{inspect(checkin_type)}")

    # Check if health check is needed
    worker = maybe_perform_health_check(worker)

    case checkin_type do
      :ok ->
        handle_successful_checkin(worker, pool_state)

      {:error, reason} ->
        handle_error_checkin(worker, reason, pool_state)

      :close ->
        handle_close_checkin(worker, pool_state)

      _ ->
        # Unknown checkin type, treat as error
        handle_error_checkin(worker, {:unknown_checkin_type, checkin_type}, pool_state)
    end
  end

  @impl NimblePool
  def handle_info(message, worker) do
    case message do
      {port, {:exit_status, status}} when port == worker.port ->
        Logger.error("Worker #{worker.worker_id} port exited with status: #{status}")
        {:remove, {:port_exited, status}}

      :perform_health_check ->
        # Async health check trigger
        updated_worker = perform_health_check(worker)
        {:ok, updated_worker}

      _ ->
        Logger.debug("Worker #{worker.worker_id} ignoring message: #{inspect(message)}")
        {:ok, worker}
    end
  end

  @impl NimblePool
  def terminate_worker(reason, worker, pool_state) do
    Logger.info("Terminating enhanced worker #{worker.worker_id}, reason: #{inspect(reason)}")

    # Transition to terminating state
    {:ok, state_machine} =
      WorkerStateMachine.transition(
        worker.state_machine,
        :terminating,
        :terminate,
        %{reason: reason}
      )

    worker = %{worker | state_machine: state_machine}

    # Graceful shutdown
    try do
      send_shutdown_command(worker)

      receive do
        {port, {:exit_status, _}} when port == worker.port ->
          :ok
      after
        1_000 ->
          # Force close if not exited
          Logger.warning("Worker #{worker.worker_id} did not exit gracefully, forcing close")
          Port.close(worker.port)
      end
    catch
      :error, _ ->
        # Port already closed
        :ok
    end

    # Record final transition
    {:ok, final_state_machine} =
      WorkerStateMachine.transition(
        worker.state_machine,
        :terminated,
        :terminate,
        %{reason: reason}
      )

    Logger.debug(
      "Worker #{worker.worker_id} terminated, final state: #{final_state_machine.state}"
    )

    # Record worker removal
    try do
      alias DSPex.PythonBridge.WorkerMetrics
      WorkerMetrics.record_lifecycle(worker.worker_id, :removed, %{reason: reason})
    rescue
      _ -> :ok
    end

    {:ok, pool_state}
  end

  ## Checkout Handlers

  defp perform_checkout({:session, session_id}, {pid, _ref}, worker, pool_state) do
    case safe_port_connect(worker.port, pid, worker.worker_id) do
      :ok ->
        {:ok, new_state_machine} =
          WorkerStateMachine.transition(
            worker.state_machine,
            :busy,
            :checkout,
            %{session_id: session_id, client_pid: pid}
          )

        updated_worker = %{
          worker
          | current_session: session_id,
            state_machine: new_state_machine,
            stats: update_checkout_stats(worker.stats)
        }

        Logger.debug("Worker #{worker.worker_id} checked out for session #{session_id}")
        {:ok, updated_worker, updated_worker, pool_state}

      {:error, reason} ->
        Logger.error("Worker #{worker.worker_id} checkout failed: #{inspect(reason)}")
        {:remove, {:checkout_failed, reason}, pool_state}
    end
  end

  defp perform_checkout(:anonymous, {pid, _ref}, worker, pool_state) do
    case safe_port_connect(worker.port, pid, worker.worker_id) do
      :ok ->
        {:ok, new_state_machine} =
          WorkerStateMachine.transition(
            worker.state_machine,
            :busy,
            :checkout,
            %{checkout_type: :anonymous, client_pid: pid}
          )

        updated_worker = %{
          worker
          | state_machine: new_state_machine,
            stats: update_checkout_stats(worker.stats)
        }

        Logger.debug("Worker #{worker.worker_id} checked out for anonymous operation")
        {:ok, updated_worker, updated_worker, pool_state}

      {:error, reason} ->
        Logger.error("Worker #{worker.worker_id} anonymous checkout failed: #{inspect(reason)}")
        {:remove, {:checkout_failed, reason}, pool_state}
    end
  end

  defp perform_checkout(checkout_type, from, worker, pool_state) do
    Logger.error(
      "Worker #{worker.worker_id} invalid checkout type: #{inspect(checkout_type)} from #{inspect(from)}"
    )

    {:remove, {:invalid_checkout_type, checkout_type}, pool_state}
  end

  ## Checkin Handlers

  defp handle_successful_checkin(worker, pool_state) do
    {:ok, new_state_machine} =
      WorkerStateMachine.transition(
        worker.state_machine,
        :ready,
        :checkin_success
      )

    updated_worker = %{
      worker
      | current_session: nil,
        state_machine: new_state_machine,
        # Reset on success
        health_check_failures: 0,
        stats: update_successful_checkin_stats(worker.stats)
    }

    Logger.debug("Worker #{worker.worker_id} successful checkin, back to ready state")
    {:ok, updated_worker, pool_state}
  end

  defp handle_error_checkin(worker, reason, pool_state) do
    failures = worker.health_check_failures + 1

    Logger.warning(
      "Worker #{worker.worker_id} error checkin: #{inspect(reason)}, failures: #{failures}"
    )

    if failures >= @max_health_failures do
      # Too many failures, remove worker
      Logger.error(
        "Worker #{worker.worker_id} exceeded max failures (#{@max_health_failures}), removing"
      )

      {:remove, {:max_failures_exceeded, reason}, pool_state}
    else
      # Degrade worker but keep it
      {:ok, new_state_machine} =
        WorkerStateMachine.transition(
          worker.state_machine,
          :degraded,
          :checkin_error,
          %{error: reason, failure_count: failures}
        )

      updated_worker = %{
        worker
        | current_session: nil,
          state_machine: WorkerStateMachine.update_health(new_state_machine, :unhealthy),
          health_check_failures: failures,
          stats: update_error_checkin_stats(worker.stats)
      }

      Logger.debug("Worker #{worker.worker_id} degraded due to error, failures: #{failures}")
      {:ok, updated_worker, pool_state}
    end
  end

  defp handle_close_checkin(worker, pool_state) do
    Logger.debug("Worker #{worker.worker_id} close checkin, removing worker")
    {:remove, :closed_by_client, pool_state}
  end

  ## Initialization

  defp start_python_process(worker_id) do
    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
      {:ok, env_info} ->
        python_path = env_info.python_path
        script_path = env_info.script_path

        # Start Python process in pool-worker mode
        debug_mode = Application.get_env(:dspex, :pool_debug_mode, false)

        base_opts = [
          :binary,
          :exit_status,
          {:packet, 4},
          {:args, [script_path, "--mode", "pool-worker", "--worker-id", worker_id]}
        ]

        port_opts =
          if debug_mode do
            Logger.warning("Pool debug mode enabled for worker #{worker_id}")
            [:stderr_to_stdout | base_opts]
          else
            base_opts
          end

        Logger.debug("Starting Python process for enhanced worker #{worker_id}")
        port = Port.open({:spawn_executable, python_path}, port_opts)

        {:ok, port, python_path, script_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_initialization(worker) do
    request_id = 0

    request =
      Protocol.encode_request(request_id, :ping, %{
        initialization: true,
        worker_id: worker.worker_id,
        enhanced: true
      })

    Logger.debug("Sending init ping for enhanced worker #{worker.worker_id}")

    try do
      Port.command(worker.port, request)
      wait_for_init_response(worker, request_id)
    catch
      :error, reason ->
        Logger.error("Failed to send init ping: #{inspect(reason)}")
        {:error, {:send_failed, reason}}
    end
  end

  defp wait_for_init_response(worker, request_id) do
    receive do
      {port, {:data, data}} when port == worker.port ->
        case Protocol.decode_response(data) do
          {:ok, ^request_id, response} ->
            case response do
              %{"status" => "ok"} ->
                Logger.debug("Enhanced worker #{worker.worker_id} init successful")
                {:ok, worker}

              response_map when is_map(response_map) ->
                Logger.debug(
                  "Enhanced worker #{worker.worker_id} init successful with response: #{inspect(response_map)}"
                )

                {:ok, worker}

              _ ->
                Logger.error("Unexpected init response structure: #{inspect(response)}")
                {:error, :malformed_init_response}
            end

          {:ok, other_id, _response} ->
            Logger.error("Init response ID mismatch: expected #{request_id}, got #{other_id}")
            {:error, :response_id_mismatch}

          {:error, _id, error_msg} ->
            Logger.error("Init ping returned error: #{error_msg}")
            {:error, {:init_failed, error_msg}}

          {:error, reason} ->
            Logger.error("Failed to decode init response: #{inspect(reason)}")
            {:error, {:decode_error, reason}}
        end

      {port, {:exit_status, status}} when port == worker.port ->
        Logger.error(
          "Enhanced worker #{worker.worker_id} port exited during init with status #{status}"
        )

        {:error, {:port_exited, status}}

      other ->
        Logger.debug("Ignoring message during init: #{inspect(other)}")
        wait_for_init_response(worker, request_id)
    after
      @init_timeout ->
        Logger.error("Enhanced worker #{worker.worker_id} init timeout after #{@init_timeout}ms")
        {:error, :init_timeout}
    end
  end

  defp send_shutdown_command(worker) do
    request_id = System.unique_integer([:positive])

    request =
      Protocol.encode_request(request_id, :shutdown, %{
        worker_id: worker.worker_id,
        enhanced: true
      })

    Port.command(worker.port, request)
  end

  ## Health Monitoring

  defp maybe_perform_health_check(worker) do
    now = System.monotonic_time(:millisecond)

    if now - worker.last_health_check >= @health_check_interval do
      perform_health_check(worker)
    else
      worker
    end
  end

  defp perform_health_check(worker) do
    case execute_health_check(worker) do
      {:ok, _response} ->
        handle_health_check_success(worker)

      {:error, reason} ->
        handle_health_check_failure(worker, reason)
    end
  end

  defp execute_health_check(worker) do
    request_id = System.unique_integer([:positive])

    request =
      Protocol.encode_request(request_id, :ping, %{
        health_check: true,
        worker_id: worker.worker_id
      })

    try do
      Port.command(worker.port, request)

      receive do
        {port, {:data, response}} when port == worker.port ->
          case Protocol.decode_response(response) do
            {:ok, ^request_id, result} ->
              {:ok, result}

            {:error, reason} ->
              {:error, reason}
          end

        {port, {:exit_status, status}} when port == worker.port ->
          {:error, {:port_exited, status}}
      after
        @health_check_timeout ->
          {:error, :health_check_timeout}
      end
    catch
      :error, reason ->
        {:error, {:health_check_failed, reason}}
    end
  end

  defp handle_health_check_success(worker) do
    Logger.debug("Worker #{worker.worker_id} health check successful")

    new_state_machine =
      if worker.state_machine.state == :degraded do
        case WorkerStateMachine.transition(worker.state_machine, :ready, :health_restored) do
          {:ok, sm} ->
            Logger.info("Worker #{worker.worker_id} recovered from degraded state")
            sm

          _ ->
            worker.state_machine
        end
      else
        WorkerStateMachine.update_health(worker.state_machine, :healthy)
      end

    # Record successful health check metrics
    try do
      alias DSPex.PythonBridge.WorkerMetrics
      WorkerMetrics.record_health_check(worker.worker_id, :success, 0)
    rescue
      _ -> :ok
    end

    %{
      worker
      | state_machine: new_state_machine,
        health_check_failures: 0,
        last_health_check: System.monotonic_time(:millisecond)
    }
  end

  defp handle_health_check_failure(worker, reason) do
    failures = worker.health_check_failures + 1

    Logger.warning(
      "Worker #{worker.worker_id} health check failed: #{inspect(reason)}, failures: #{failures}"
    )

    new_state_machine =
      if failures >= @max_health_failures do
        case WorkerStateMachine.transition(
               worker.state_machine,
               :terminating,
               :health_check_failed
             ) do
          {:ok, sm} ->
            Logger.error(
              "Worker #{worker.worker_id} marked for termination due to health failures"
            )

            sm

          _ ->
            worker.state_machine
        end
      else
        worker.state_machine
        |> WorkerStateMachine.update_health(:unhealthy)
      end

    # Record failed health check metrics
    try do
      alias DSPex.PythonBridge.WorkerMetrics

      WorkerMetrics.record_health_check(worker.worker_id, :failure, 0, %{
        reason: reason,
        failure_count: failures
      })
    rescue
      _ -> :ok
    end

    %{
      worker
      | state_machine: new_state_machine,
        health_check_failures: failures,
        last_health_check: System.monotonic_time(:millisecond)
    }
  end

  ## Session and Worker Management

  defp transition_to_ready(worker) do
    {:ok, state_machine} =
      WorkerStateMachine.transition(
        worker.state_machine,
        :ready,
        :init_complete
      )

    %{worker | state_machine: WorkerStateMachine.update_health(state_machine, :healthy)}
  end

  defp generate_worker_id do
    "enhanced_worker_#{:erlang.unique_integer([:positive])}_#{System.os_time(:nanosecond)}"
  end

  ## Stats Management

  defp init_stats do
    %{
      checkouts: 0,
      successful_checkins: 0,
      error_checkins: 0,
      health_checks: 0,
      health_failures: 0,
      state_transitions: 0,
      uptime_ms: 0,
      last_activity: System.monotonic_time(:millisecond)
    }
  end

  defp update_checkout_stats(stats) do
    %{stats | checkouts: stats.checkouts + 1, last_activity: System.monotonic_time(:millisecond)}
  end

  defp update_successful_checkin_stats(stats) do
    %{
      stats
      | successful_checkins: stats.successful_checkins + 1,
        last_activity: System.monotonic_time(:millisecond)
    }
  end

  defp update_error_checkin_stats(stats) do
    %{
      stats
      | error_checkins: stats.error_checkins + 1,
        last_activity: System.monotonic_time(:millisecond)
    }
  end

  ## Port Management (reused from PoolWorkerV2)

  defp validate_port(port) when is_port(port) do
    case Port.info(port) do
      nil ->
        {:error, :port_closed}

      _port_info ->
        {:ok, port}
    end
  end

  defp validate_port(_), do: {:error, :not_a_port}

  defp safe_port_connect(port, target_pid, worker_id) do
    Logger.debug("[#{worker_id}] Attempting safe port connection to #{inspect(target_pid)}")

    with :ok <- validate_pid(target_pid),
         {:ok, _port} <- validate_port(port),
         :ok <- attempt_port_connect(port, target_pid, worker_id) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("[#{worker_id}] Safe port connect failed: #{inspect(reason)}")
        error
    end
  end

  defp validate_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      :ok
    else
      {:error, :process_not_alive}
    end
  end

  defp validate_pid(_), do: {:error, :not_a_pid}

  defp attempt_port_connect(port, target_pid, worker_id) do
    try do
      Port.connect(port, target_pid)
      Logger.debug("[#{worker_id}] Successfully connected port to #{inspect(target_pid)}")
      :ok
    rescue
      ArgumentError ->
        {:error, :port_closed_during_connect}
    catch
      :error, :badarg ->
        {:error, :badarg}

      :error, reason ->
        {:error, {:connect_failed, reason}}
    end
  end

  @doc """
  Gets comprehensive worker information including state machine status.
  """
  def get_worker_info(worker) do
    uptime = System.monotonic_time(:millisecond) - worker.started_at

    %{
      worker_id: worker.worker_id,
      current_session: worker.current_session,
      state: worker.state_machine.state,
      health: worker.state_machine.health,
      health_check_failures: worker.health_check_failures,
      last_health_check: worker.last_health_check,
      stats: Map.put(worker.stats, :uptime_ms, uptime),
      transition_history: worker.state_machine.transition_history,
      metadata: worker.state_machine.metadata
    }
  end
end

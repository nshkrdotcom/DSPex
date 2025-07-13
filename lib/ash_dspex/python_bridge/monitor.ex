defmodule AshDSPex.PythonBridge.Monitor do
  @moduledoc """
  Health monitoring and metrics collection for the Python bridge.

  This module continuously monitors the health of the Python bridge process,
  collecting metrics, detecting failures, and triggering recovery actions
  when necessary.

  ## Features

  - **Periodic Health Checks**: Regular ping operations to verify bridge availability
  - **Failure Detection**: Tracks consecutive failures and response times
  - **Automatic Recovery**: Triggers bridge restarts when health degradation is detected
  - **Metrics Collection**: Gathers performance and reliability statistics
  - **Alerting**: Logs warnings and errors for monitoring systems
  - **Configurable Thresholds**: Adjustable health check intervals and failure limits

  ## Health Check Process

  1. **Ping Test**: Sends periodic ping commands to verify bridge responsiveness
  2. **Response Time**: Measures and tracks request/response latency
  3. **Failure Counting**: Tracks consecutive health check failures
  4. **Recovery Actions**: Restarts bridge when failure threshold is exceeded
  5. **Statistics**: Maintains running averages and failure rates

  ## Configuration

      config :ash_dspex, :python_bridge_monitor,
        health_check_interval: 30_000,  # 30 seconds
        failure_threshold: 3,
        response_timeout: 5_000,
        restart_delay: 1_000

  ## Usage

      # Start the monitor
      {:ok, _pid} = AshDSPex.PythonBridge.Monitor.start_link()

      # Get health status
      status = AshDSPex.PythonBridge.Monitor.get_health_status()

      # Force a health check
      :ok = AshDSPex.PythonBridge.Monitor.force_health_check()
  """

  use GenServer
  require Logger

  @type health_status :: :healthy | :degraded | :unhealthy | :unknown
  @type health_metrics :: %{
          status: health_status(),
          last_check: DateTime.t() | nil,
          consecutive_failures: non_neg_integer(),
          total_checks: non_neg_integer(),
          total_failures: non_neg_integer(),
          success_rate: float(),
          average_response_time: float(),
          last_error: String.t() | nil
        }

  @default_config %{
    # 30 seconds
    health_check_interval: 30_000,
    failure_threshold: 3,
    response_timeout: 5_000,
    restart_delay: 1_000,
    max_restart_attempts: 5,
    # 1 minute
    restart_cooldown: 60_000
  }

  defstruct config: @default_config,
            bridge_name: AshDSPex.PythonBridge.Bridge,
            health_status: :unknown,
            last_check: nil,
            consecutive_failures: 0,
            total_checks: 0,
            total_failures: 0,
            response_times: [],
            last_error: nil,
            restart_attempts: 0,
            last_restart: nil,
            timer_ref: nil

  ## Public API

  @doc """
  Starts the health monitor GenServer.

  ## Options

  - `:name` - The name to register the GenServer (default: `__MODULE__`)
  - `:health_check_interval` - Interval between health checks in milliseconds
  - `:failure_threshold` - Number of consecutive failures before restart
  - `:response_timeout` - Timeout for health check requests

  ## Examples

      {:ok, pid} = AshDSPex.PythonBridge.Monitor.start_link()
      {:ok, pid} = AshDSPex.PythonBridge.Monitor.start_link(name: MyMonitor)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current health status and metrics.

  Returns comprehensive health information including status, failure counts,
  response times, and other monitoring metrics.

  ## Examples

      %{
        status: :healthy,
        last_check: ~U[2024-01-01 12:00:00Z],
        consecutive_failures: 0,
        success_rate: 98.5,
        average_response_time: 245.3
      } = AshDSPex.PythonBridge.Monitor.get_health_status()
  """
  @spec get_health_status() :: health_metrics()
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Forces an immediate health check.

  Triggers a health check outside of the normal scheduled interval.
  Useful for testing or immediate status verification.

  ## Examples

      :ok = AshDSPex.PythonBridge.Monitor.force_health_check()
  """
  @spec force_health_check() :: :ok
  def force_health_check do
    GenServer.cast(__MODULE__, :force_health_check)
  end

  @doc """
  Resets the health monitor statistics.

  Clears all accumulated metrics and failure counts. Useful for
  testing or after manual interventions.

  ## Examples

      :ok = AshDSPex.PythonBridge.Monitor.reset_stats()
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.cast(__MODULE__, :reset_stats)
  end

  @doc """
  Stops the health monitor.

  ## Examples

      :ok = AshDSPex.PythonBridge.Monitor.stop()
  """
  @spec stop() :: :ok
  def stop do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Stops a named health monitor.

  ## Examples

      :ok = AshDSPex.PythonBridge.Monitor.stop(:my_monitor)
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)
    bridge_name = Keyword.get(opts, :bridge_name, AshDSPex.PythonBridge.Bridge)

    # Schedule first health check
    timer_ref = schedule_health_check(config.health_check_interval)

    state = %__MODULE__{
      config: config,
      bridge_name: bridge_name,
      timer_ref: timer_ref
    }

    Logger.info("Python bridge monitor started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    metrics = build_health_metrics(state)
    {:reply, metrics, state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    new_state = perform_health_check(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset_stats, state) do
    new_state = %{
      state
      | health_status: :unknown,
        last_check: nil,
        consecutive_failures: 0,
        total_checks: 0,
        total_failures: 0,
        response_times: [],
        last_error: nil,
        restart_attempts: 0,
        last_restart: nil
    }

    Logger.info("Health monitor statistics reset")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)

    # Schedule next health check
    timer_ref = schedule_health_check(state.config.health_check_interval)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:perform_restart, state) do
    Logger.info("Performing Python bridge restart")

    case GenServer.call(state.bridge_name, :restart) do
      :ok ->
        Logger.info("Python bridge restart successful")
        # Reset failure count after successful restart
        new_state = %{state | consecutive_failures: 0, health_status: :unknown}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Python bridge restart failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("Unexpected message in monitor: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Python bridge monitor terminating: #{inspect(reason)}")

    _ =
      if state.timer_ref do
        Process.cancel_timer(state.timer_ref)
      end

    :ok
  end

  ## Private Functions

  defp build_config(opts) do
    app_config = Application.get_env(:ash_dspex, :python_bridge_monitor, %{})

    @default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp perform_health_check(state) do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        GenServer.call(state.bridge_name, {:call, :ping, %{}}, state.config.response_timeout)
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, {:noproc, _} -> {:error, :bridge_not_running}
        error -> {:error, error}
      end

    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    case result do
      {:ok, %{"status" => "ok"}} ->
        handle_successful_health_check(state, response_time)

      {:ok, response} ->
        error_msg = "Unexpected health check response: #{inspect(response)}"
        handle_failed_health_check(state, error_msg, response_time)

      {:error, reason} ->
        error_msg = "Health check failed: #{inspect(reason)}"
        handle_failed_health_check(state, error_msg, response_time)
    end
  end

  defp handle_successful_health_check(state, response_time) do
    new_response_times = update_response_times(state.response_times, response_time)

    new_state = %{
      state
      | health_status: :healthy,
        last_check: DateTime.utc_now(),
        consecutive_failures: 0,
        total_checks: state.total_checks + 1,
        response_times: new_response_times,
        last_error: nil
    }

    if state.consecutive_failures > 0 do
      Logger.info("Python bridge health recovered after #{state.consecutive_failures} failures")
    end

    new_state
  end

  defp handle_failed_health_check(state, error_msg, response_time) do
    new_consecutive_failures = state.consecutive_failures + 1
    new_response_times = update_response_times(state.response_times, response_time)

    new_state = %{
      state
      | health_status:
          determine_health_status(new_consecutive_failures, state.config.failure_threshold),
        last_check: DateTime.utc_now(),
        consecutive_failures: new_consecutive_failures,
        total_checks: state.total_checks + 1,
        total_failures: state.total_failures + 1,
        response_times: new_response_times,
        last_error: error_msg
    }

    Logger.warning("Health check failed (#{new_consecutive_failures}): #{error_msg}")

    # Check if we should trigger a restart
    if should_restart_bridge?(new_state) do
      trigger_bridge_restart(new_state)
    else
      new_state
    end
  end

  defp determine_health_status(consecutive_failures, failure_threshold) do
    cond do
      consecutive_failures == 0 -> :healthy
      consecutive_failures < failure_threshold -> :degraded
      true -> :unhealthy
    end
  end

  defp should_restart_bridge?(state) do
    state.consecutive_failures >= state.config.failure_threshold and
      not restart_on_cooldown?(state) and
      state.restart_attempts < state.config.max_restart_attempts
  end

  defp restart_on_cooldown?(state) do
    case state.last_restart do
      nil ->
        false

      last_restart ->
        cooldown_elapsed = DateTime.diff(DateTime.utc_now(), last_restart, :millisecond)
        cooldown_elapsed < state.config.restart_cooldown
    end
  end

  defp trigger_bridge_restart(state) do
    Logger.error(
      "Triggering Python bridge restart due to #{state.consecutive_failures} consecutive failures"
    )

    # Delay restart slightly to avoid immediate restart loops
    Process.send_after(self(), :perform_restart, state.config.restart_delay)

    %{state | restart_attempts: state.restart_attempts + 1, last_restart: DateTime.utc_now()}
  end

  defp update_response_times(response_times, new_time) do
    # Keep last 100 response times for averaging
    updated_times = [new_time | response_times]
    Enum.take(updated_times, 100)
  end

  defp build_health_metrics(state) do
    success_rate = calculate_success_rate(state.total_checks, state.total_failures)
    average_response_time = calculate_average_response_time(state.response_times)

    %{
      status: state.health_status,
      last_check: state.last_check,
      consecutive_failures: state.consecutive_failures,
      total_checks: state.total_checks,
      total_failures: state.total_failures,
      success_rate: success_rate,
      average_response_time: average_response_time,
      last_error: state.last_error,
      restart_attempts: state.restart_attempts,
      last_restart: state.last_restart,
      config: state.config
    }
  end

  defp calculate_success_rate(0, _), do: 100.0

  defp calculate_success_rate(total_checks, total_failures) do
    successful_checks = total_checks - total_failures
    successful_checks / total_checks * 100.0
  end

  defp calculate_average_response_time([]), do: 0.0

  defp calculate_average_response_time(response_times) do
    Enum.sum(response_times) / length(response_times)
  end

  ## Handle restart trigger - implemented above in handle_info clauses
end

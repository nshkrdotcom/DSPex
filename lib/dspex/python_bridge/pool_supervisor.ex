defmodule DSPex.PythonBridge.PoolSupervisor do
  @moduledoc """
  Supervisor for the Python bridge pool system.

  This supervisor manages the complete pool infrastructure including:
  - Session pool manager
  - NimblePool of Python workers
  - Health monitoring
  - Metrics collection

  ## Configuration

  Configure the pool in your application config:

      config :dspex, DSPex.PythonBridge.PoolSupervisor,
        enabled: true,
        pool_size: System.schedulers_online() * 2,
        overflow: 2,
        health_check_interval: 30_000

  ## Architecture

  ```
  PoolSupervisor
  ├── SessionPool (GenServer)
  │   └── NimblePool
  │       ├── PoolWorker 1
  │       ├── PoolWorker 2
  │       └── PoolWorker N
  └── PoolMonitor (GenServer)
  ```
  """

  use Supervisor
  require Logger

  @default_config %{
    enabled: true,
    pool_size: System.schedulers_online() * 2,
    overflow: 2,
    checkout_timeout: 5_000,
    operation_timeout: 30_000,
    health_check_interval: 30_000,
    session_cleanup_interval: 300_000
  }

  @doc """
  Starts the pool supervisor.

  ## Options

  - `:name` - The name to register the supervisor (default: `__MODULE__`)
  - `:enabled` - Whether to start the pool (default: true)
  - `:pool_size` - Number of worker processes
  - `:overflow` - Maximum additional workers when pool is full
  - `:checkout_timeout` - Maximum time to wait for available worker
  - `:operation_timeout` - Maximum time for operations
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current configuration of the pool.
  """
  def get_config do
    config = Application.get_env(:dspex, __MODULE__, %{})
    Map.merge(@default_config, Map.new(config))
  end

  @doc """
  Checks if the pool is enabled.
  """
  def enabled? do
    get_config().enabled
  end

  @doc """
  Gracefully shuts down the pool system.
  """
  def shutdown(timeout \\ 10_000) do
    Supervisor.stop(__MODULE__, :normal, timeout)
  end

  ## Supervisor Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    if config.enabled do
      Logger.info("Starting Python bridge pool supervisor")

      children = [
        # Session pool manager with NimblePool
        {DSPex.PythonBridge.SessionPool,
         [
           pool_size: config.pool_size,
           overflow: config.overflow,
           checkout_timeout: config.checkout_timeout,
           operation_timeout: config.operation_timeout
         ]},

        # Pool health monitor
        {DSPex.PythonBridge.PoolMonitor,
         [
           health_check_interval: config.health_check_interval,
           session_cleanup_interval: config.session_cleanup_interval
         ]}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    else
      Logger.info("Python bridge pool disabled")
      Supervisor.init([], strategy: :one_for_one)
    end
  end

  defp build_config(opts) do
    app_config = Application.get_env(:dspex, __MODULE__, %{})

    @default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end
end

defmodule DSPex.PythonBridge.PoolMonitor do
  @moduledoc """
  Health monitor for the Python bridge pool.

  Monitors pool health, collects metrics, and performs maintenance tasks.
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.SessionPool

  defstruct [
    :health_check_interval,
    :session_cleanup_interval,
    :health_check_ref,
    :cleanup_ref,
    :metrics,
    :started_at
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current health status of the pool.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @doc """
  Gets current pool metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    health_check_interval = Keyword.get(opts, :health_check_interval, 30_000)
    session_cleanup_interval = Keyword.get(opts, :session_cleanup_interval, 300_000)

    # Schedule periodic tasks
    health_check_ref = schedule_health_check(health_check_interval)
    cleanup_ref = schedule_cleanup(session_cleanup_interval)

    state = %__MODULE__{
      health_check_interval: health_check_interval,
      session_cleanup_interval: session_cleanup_interval,
      health_check_ref: health_check_ref,
      cleanup_ref: cleanup_ref,
      metrics: init_metrics(),
      started_at: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_status = perform_health_check(state)
    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics =
      Map.merge(state.metrics, %{
        uptime_ms: System.monotonic_time(:millisecond) - state.started_at
      })

    {:reply, metrics, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health check
    health_status = perform_health_check(state)

    # Update metrics
    metrics = update_health_metrics(state.metrics, health_status)

    # Log if unhealthy
    if health_status.status != :healthy do
      Logger.warning("Pool health check failed: #{inspect(health_status)}")
    end

    # Reschedule
    health_check_ref = schedule_health_check(state.health_check_interval)

    {:noreply, %{state | health_check_ref: health_check_ref, metrics: metrics}}
  end

  @impl true
  def handle_info(:cleanup_sessions, state) do
    # Trigger session cleanup in pool
    Task.start(fn ->
      try do
        SessionPool.cleanup_stale_sessions()
      catch
        :exit, reason ->
          Logger.error("Session cleanup failed: #{inspect(reason)}")
      end
    end)

    # Reschedule
    cleanup_ref = schedule_cleanup(state.session_cleanup_interval)

    {:noreply, %{state | cleanup_ref: cleanup_ref}}
  end

  ## Private Functions

  defp init_metrics do
    %{
      health_checks_performed: 0,
      health_check_failures: 0,
      last_health_check: nil,
      pool_restarts: 0
    }
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_sessions, interval)
  end

  defp perform_health_check(_state) do
    try do
      # Get pool status
      pool_status = SessionPool.get_pool_status()

      # Perform test operation
      test_result = SessionPool.execute_anonymous(:ping, %{health_check: true}, timeout: 5000)

      %{
        status: determine_health_status(pool_status, test_result),
        pool_status: pool_status,
        test_result: test_result,
        timestamp: DateTime.utc_now()
      }
    catch
      :exit, reason ->
        %{
          status: :unhealthy,
          error: reason,
          timestamp: DateTime.utc_now()
        }
    end
  end

  defp determine_health_status(pool_status, test_result) do
    cond do
      match?({:ok, _}, test_result) and pool_status.active_sessions < pool_status.pool_size * 2 ->
        :healthy

      match?({:ok, _}, test_result) ->
        :degraded

      true ->
        :unhealthy
    end
  end

  defp update_health_metrics(metrics, health_status) do
    metrics
    |> Map.update(:health_checks_performed, 1, &(&1 + 1))
    |> Map.update(:health_check_failures, 0, fn failures ->
      if health_status.status == :unhealthy, do: failures + 1, else: failures
    end)
    |> Map.put(:last_health_check, health_status)
  end
end

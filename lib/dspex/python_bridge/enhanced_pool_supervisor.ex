defmodule DSPex.PythonBridge.EnhancedPoolSupervisor do
  @moduledoc """
  Enhanced supervisor that can manage both V2 and V3 Python pools.

  This supervisor allows running both pools simultaneously during migration,
  with configuration to control which pools are active.

  ## Configuration

      config :dspex, :pool_config,
        v2_enabled: true,
        v3_enabled: false,  # Enable when ready
        pool_version: :v2,  # :v2, :v3, or :gradual
        v3_percentage: 10   # For gradual rollout
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = get_pool_config()

    children = build_children(config)

    Logger.info("Starting enhanced pool supervisor with config: #{inspect(config)}")

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_children(config) do
    children = []

    # Always start SessionStore (used by both versions)
    children = [{DSPex.PythonBridge.SessionStore, []} | children]

    # V3 pool components (start first if enabled)
    children =
      if config.v3_enabled do
        Logger.info("V3 pool enabled - starting components")

        [
          # Pool goes FIRST so it shuts down LAST (reverse order)
          %{
            id: DSPex.Python.Pool,
            start: {DSPex.Python.Pool, :start_link, [[
              name: DSPex.Python.Pool,
              size: config.pool_size || 8
            ]]},
            restart: :permanent,
            shutdown: 15_000,  # Give pool 15 seconds to clean up Python processes
            type: :worker
          },
          DSPex.Python.Registry,
          DSPex.Python.ProcessRegistry,
          DSPex.Python.WorkerSupervisor
          | children
        ]
      else
        children
      end

    # V2 pool components
    children =
      if config.v2_enabled do
        Logger.info("V2 pool enabled - starting components")

        [
          {DSPex.PythonBridge.SessionPoolV2,
           [
             pool_size: config.pool_size || 8,
             overflow: config.overflow || 4,
             checkout_timeout: 5_000,
             operation_timeout: 30_000
           ]},
          {DSPex.PythonBridge.PoolMonitor,
           [
             health_check_interval: 30_000,
             session_cleanup_interval: 300_000
           ]}
          | children
        ]
      else
        children
      end

    Enum.reverse(children)
  end

  defp get_pool_config do
    default = %{
      v2_enabled: true,
      v3_enabled: false,
      pool_version: :v2,
      v3_percentage: 0,
      pool_size: 8,
      overflow: 4
    }

    config = Application.get_env(:dspex, :pool_config, %{})
    Map.merge(default, config)
  end

  @doc """
  Switches pool configuration at runtime.
  """
  def update_pool_config(updates) do
    current = get_pool_config()
    new_config = Map.merge(current, updates)

    Application.put_env(:dspex, :pool_config, new_config)

    # Log the change
    Logger.info("Pool config updated: #{inspect(new_config)}")

    # Note: This doesn't restart pools, just updates routing
    :ok
  end

  @doc """
  Gets current pool status for both V2 and V3.
  """
  def get_pool_status do
    v2_status =
      try do
        DSPex.PythonBridge.SessionPoolV2.get_pool_status()
      rescue
        _ -> %{error: "V2 pool not running"}
      end

    v3_status =
      try do
        DSPex.Python.Pool.get_stats()
      rescue
        _ -> %{error: "V3 pool not running"}
      end

    %{
      v2: v2_status,
      v3: v3_status,
      config: get_pool_config()
    }
  end
end

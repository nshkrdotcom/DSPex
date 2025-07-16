defmodule DSPex.PoolAdapter do
  @moduledoc """
  Migration adapter that routes requests to V2 or V3 pool based on configuration.

  This allows gradual migration without changing client code:
  1. Start with all traffic to V2
  2. Gradually increase V3 traffic percentage
  3. Monitor metrics and rollback if needed
  4. Eventually remove V2 and this adapter

  Configuration:
      config :dspex, :pool_version, :v2  # or :v3
      config :dspex, :pool_v3_percentage, 10  # 10% to V3
  """

  require Logger

  @doc """
  Routes execute_in_session to appropriate pool version.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    case select_pool_version() do
      :v2 ->
        DSPex.PythonBridge.SessionPoolV2.execute_in_session(
          session_id,
          command,
          args,
          opts
        )

      :v3 ->
        DSPex.Python.SessionAdapter.execute_in_session(
          session_id,
          command,
          args,
          opts
        )
    end
  end

  @doc """
  Routes execute_anonymous to appropriate pool version.
  """
  def execute_anonymous(command, args, opts \\ []) do
    case select_pool_version() do
      :v2 ->
        DSPex.PythonBridge.SessionPoolV2.execute_anonymous(command, args, opts)

      :v3 ->
        DSPex.Python.SessionAdapter.execute_anonymous(command, args, opts)
    end
  end

  @doc """
  Gets statistics from both pools for comparison.
  """
  def get_stats do
    v2_stats =
      try do
        DSPex.PythonBridge.SessionPoolV2.get_pool_status()
      rescue
        _ -> %{error: "V2 pool not available"}
      end

    v3_stats =
      try do
        DSPex.Python.Pool.get_stats()
      rescue
        _ -> %{error: "V3 pool not available"}
      end

    %{
      v2: v2_stats,
      v3: v3_stats,
      routing: %{
        version: pool_version(),
        v3_percentage: v3_percentage()
      }
    }
  end

  @doc """
  Forces a specific pool version for testing.
  """
  def with_pool_version(version, fun) when version in [:v2, :v3] do
    current = Application.get_env(:dspex, :pool_version)

    try do
      Application.put_env(:dspex, :pool_version, version)
      fun.()
    after
      Application.put_env(:dspex, :pool_version, current)
    end
  end

  # Private Functions

  defp select_pool_version do
    case pool_version() do
      :v2 ->
        :v2

      :v3 ->
        :v3

      :gradual ->
        # Gradual rollout based on percentage
        if :rand.uniform(100) <= v3_percentage() do
          log_routing_decision(:v3)
          :v3
        else
          log_routing_decision(:v2)
          :v2
        end
    end
  end

  defp pool_version do
    Application.get_env(:dspex, :pool_version, :v2)
  end

  defp v3_percentage do
    Application.get_env(:dspex, :pool_v3_percentage, 0)
  end

  defp log_routing_decision(version) do
    # Only log a sample to avoid spam
    if :rand.uniform(100) == 1 do
      Logger.debug("PoolAdapter routed request to #{version}")
    end

    # Emit telemetry for monitoring
    :telemetry.execute(
      [:dspex, :pool_adapter, :route],
      %{count: 1},
      %{version: version}
    )
  end
end

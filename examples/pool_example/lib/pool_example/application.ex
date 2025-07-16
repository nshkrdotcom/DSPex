defmodule PoolExample.Application do
  @moduledoc """
  Application module for the PoolExample app.
  
  Starts the necessary supervisors and services for pool operations.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting PoolExample Application...")

    # Check if pool is already started by DSPex
    children = case Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
      nil ->
        Logger.info("SessionPoolV2 not found, starting it...")
        [
          # Start the SessionPoolV2 supervisor
          {DSPex.PythonBridge.SessionPoolV2,
           [
             name: DSPex.PythonBridge.SessionPoolV2,
             pool_size: Application.get_env(:pool_example, :pool_size, 4),
             overflow: Application.get_env(:pool_example, :overflow, 2)
           ]}
        ]
      pid ->
        Logger.info("SessionPoolV2 already running at #{inspect(pid)}, skipping start")
        []
    end

    opts = [strategy: :one_for_one, name: PoolExample.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("✅ PoolExample Application started successfully")
        {:ok, pid}
      error ->
        Logger.error("Failed to start PoolExample Application: #{inspect(error)}")
        error
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping PoolExample Application...")
    :ok
  end
end
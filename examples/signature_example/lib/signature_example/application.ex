defmodule SignatureExample.Application do
  @moduledoc """
  Application module for the DSPex Dynamic Signature Example.
  
  This sets up the application supervision tree and initializes DSPex
  with the Python bridge for dynamic signature capabilities.
  """
  
  use Application
  
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("🚀 Starting DSPex Dynamic Signature Example Application")
    
    # Ensure DSPex application is started
    case Application.ensure_started(:dspex) do
      :ok -> 
        Logger.info("✅ DSPex application started")
      {:error, {:already_started, :dspex}} ->
        Logger.info("✅ DSPex application already running")
      {:error, reason} ->
        Logger.warning("⚠️  DSPex application issue: #{inspect(reason)}")
    end
    
    children = [
      # Just start an empty supervisor for the example app
    ]

    opts = [strategy: :one_for_one, name: SignatureExample.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("✅ Dynamic Signature Example Application started successfully")
        {:ok, pid}
        
      error ->
        Logger.error("❌ Failed to start Dynamic Signature Example Application: #{inspect(error)}")
        error
    end
  end
  
  @impl true
  def stop(_state) do
    Logger.info("🛑 Stopping DSPex Dynamic Signature Example Application")
    :ok
  end
end
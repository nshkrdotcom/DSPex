defmodule DSPex.Application do
  @moduledoc """
  Application supervision tree for DSPex.

  This module sets up the supervision tree for DSPex, including:
  - Signature module registry for the native Elixir DSPy signature system
  - Python bridge supervision tree for DSPy integration
  - Background processes and infrastructure for reliable operation
  """

  use Application

  @doc """
  Starts the DSPex application.

  Sets up the supervision tree with signature registry and Python bridge
  infrastructure for DSPy integration.
  """
  @impl true
  def start(_type, _args) do
    children = [
      # Registry for signature module lookup
      {Registry, keys: :unique, name: DSPex.SignatureRegistry},

      # Conditional Python bridge supervisor
      DSPex.PythonBridge.ConditionalSupervisor
    ]

    opts = [strategy: :one_for_one, name: DSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Application stop callback - called when Application.stop/1 is invoked.
  
  The supervision tree handles all cleanup automatically through proper
  shutdown timeouts and GenServer terminate/2 callbacks.
  """
  @impl true
  def stop(_state) do
    require Logger
    Logger.info("🛑 DSPex application stopping (automatic cleanup via supervision tree)")
    
    # Debug: Check what children exist in the supervision tree
    case Process.whereis(DSPex.Supervisor) do
      nil -> 
        Logger.info("🔍 DSPex.Supervisor not found")
      supervisor_pid ->
        children = Supervisor.which_children(supervisor_pid)
        Logger.info("🔍 DSPex.Supervisor children: #{inspect(children)}")
        
        # Check the ConditionalSupervisor children
        case Process.whereis(DSPex.PythonBridge.ConditionalSupervisor) do
          nil ->
            Logger.info("🔍 ConditionalSupervisor not found")
          cond_sup_pid ->
            cond_children = Supervisor.which_children(cond_sup_pid)
            Logger.info("🔍 ConditionalSupervisor children: #{inspect(cond_children)}")
            
            # Check EnhancedPoolSupervisor if it exists
            case Process.whereis(DSPex.PythonBridge.EnhancedPoolSupervisor) do
              nil ->
                Logger.info("🔍 EnhancedPoolSupervisor not found")
              enhanced_pid ->
                enhanced_children = Supervisor.which_children(enhanced_pid)
                Logger.info("🔍 EnhancedPoolSupervisor children: #{inspect(enhanced_children)}")
            end
        end
    end
    
    :ok
  end
end

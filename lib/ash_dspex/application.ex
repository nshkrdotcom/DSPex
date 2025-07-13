defmodule AshDSPex.Application do
  @moduledoc """
  Application supervision tree for AshDSPex.

  This module sets up the supervision tree for AshDSPex, including:
  - Signature module registry for the native Elixir DSPy signature system
  - Python bridge supervision tree for DSPy integration
  - Background processes and infrastructure for reliable operation
  """

  use Application

  @doc """
  Starts the AshDSPex application.

  Sets up the supervision tree with signature registry and Python bridge
  infrastructure for DSPy integration.
  """
  @impl true
  def start(_type, _args) do
    children = [
      # Registry for signature module lookup
      {Registry, keys: :unique, name: AshDSPex.SignatureRegistry},

      # Conditional Python bridge supervisor
      AshDSPex.PythonBridge.ConditionalSupervisor
    ]

    opts = [strategy: :one_for_one, name: AshDSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule ElixirML.Application do
  @moduledoc """
  ElixirML Application supervisor.

  Starts and supervises all ElixirML foundation components including the
  Process Orchestrator and its child processes.
  """

  use Application

  def start(_type, _args) do
    children = [
      # Start the Process Orchestrator which supervises all other components
      ElixirML.Process.Orchestrator
    ]

    opts = [strategy: :one_for_one, name: ElixirML.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    :ok
  end
end

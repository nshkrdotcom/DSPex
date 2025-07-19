defmodule DSPex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking Python processes
      {Registry, keys: :unique, name: DSPex.ProcessRegistry},

      # Python pool manager (Snakepit pools)
      DSPex.Python.PoolManager,

      # Native module registry
      DSPex.Native.Registry,

      # Python module registry
      DSPex.Python.Registry,

      # Router with its registries
      DSPex.Router
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]

    result = Supervisor.start_link(children, opts)

    # Log startup
    :telemetry.execute([:dspex, :application, :start], %{}, %{})

    result
  end

  @impl true
  def stop(_state) do
    # Cleanup Python processes gracefully
    DSPex.Python.PoolManager.shutdown()
    :ok
  end
end

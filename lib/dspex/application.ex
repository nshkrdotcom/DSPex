defmodule DSPex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking Python processes
      {Registry, keys: :unique, name: DSPex.ProcessRegistry},

      # Native module registry
      DSPex.Native.Registry
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
    # Snakepit manages its own lifecycle
    :ok
  end
end

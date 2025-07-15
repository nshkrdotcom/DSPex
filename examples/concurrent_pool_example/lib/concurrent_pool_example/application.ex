defmodule ConcurrentPoolExample.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # The concurrent pool example doesn't need to start its own processes
      # DSPex application will be started automatically as a dependency
      # and will handle starting the pool supervisor based on configuration
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConcurrentPoolExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

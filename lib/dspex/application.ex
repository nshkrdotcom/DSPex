defmodule DSPex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for tracking Python processes
      {Registry, keys: :unique, name: DSPex.ProcessRegistry},

      # Native module registry
      DSPex.Native.Registry,
      
      # Tool registry for bidirectional bridge
      DSPex.Bridge.Tools.Registry,
      
      # Telemetry infrastructure
      DSPex.Telemetry.Handler,
      DSPex.Telemetry.Metrics,
      DSPex.Telemetry.Reporter,
      DSPex.Telemetry.Alerts,
      DSPex.Telemetry.OpenTelemetry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]

    result = Supervisor.start_link(children, opts)

    # Attach telemetry handlers
    DSPex.Telemetry.Metrics.attach()
    DSPex.Telemetry.Reporter.attach()
    DSPex.Telemetry.Alerts.attach()

    # Log startup with timing
    start_time = System.monotonic_time(:millisecond)
    :telemetry.execute(
      [:dspex, :application, :start], 
      %{
        system_time: System.system_time(),
        start_time: start_time
      }, 
      %{
        version: Application.spec(:dspex, :vsn) |> to_string()
      }
    )

    result
  end

  @impl true
  def stop(_state) do
    # Snakepit manages its own lifecycle
    :ok
  end
end

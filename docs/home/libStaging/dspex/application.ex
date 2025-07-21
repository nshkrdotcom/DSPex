defmodule Dspex.Application do
  @moduledoc """
  Application module for DSPEx (Declarative Self-improving Programs in Elixir).

  This module implements the OTP Application behavior and is responsible for starting
  the supervision tree for DSPEx services. It manages the lifecycle of core services
  including configuration management, telemetry setup, and HTTP client pools.

  ## Supervised Services

  - `DSPEx.Services.ConfigManager` - Configuration management service
  - `DSPEx.Services.TelemetrySetup` - Telemetry and metrics setup
  - `Finch` - HTTP client pool for external API calls

  The supervision strategy is `:one_for_one`, meaning if any child process crashes,
  only that process will be restarted.
  """

  use Application

  @impl Application
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      # DSPEx's independent configuration system
      DSPEx.Config.Store,

      # DSPEx-specific services (Foundation starts automatically)
      {DSPEx.Services.ConfigManager, []},
      {DSPEx.Services.TelemetrySetup, []},

      # HTTP client pool for external API calls
      {Finch, name: DSPEx.Finch},

      # ElixirML Process Orchestrator
      ElixirML.Process.Orchestrator
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dspex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

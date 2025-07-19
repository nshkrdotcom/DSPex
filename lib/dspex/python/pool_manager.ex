defmodule DSPex.Python.PoolManager do
  @moduledoc """
  Manages Python process pools via Snakepit.

  Since Snakepit manages its own pool internally, this module
  configures and supervises the Snakepit application.
  """

  use Supervisor

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting DSPex Python Pool Manager")

    # Snakepit is configured through application config
    # We just need to ensure it's started
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Check pool status.
  """
  @spec status() :: %{status: :running | :not_available | :error, stats: map()} | %{status: :not_available | :error}
  def status do
    case Snakepit.get_stats() do
      stats when is_map(stats) ->
        %{status: :running, stats: stats}

      _ ->
        %{status: :not_available}
    end
  catch
    _, _ -> %{status: :error}
  end

  @doc """
  Gracefully shutdown.
  """
  @spec shutdown() :: :ok
  def shutdown do
    Logger.info("DSPex shutdown requested - Snakepit manages its own lifecycle")
    :ok
  end
end

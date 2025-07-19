defmodule DSPEx.Services.ConfigManager do
  @moduledoc """
  Configuration manager for DSPEx that integrates with Foundation's config system.
  Sets up DSPEx-specific configuration and provides convenient access methods.
  """

  use GenServer
  require Logger

  @doc """
  Starts the configuration manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the configuration manager.
  """
  @impl GenServer
  @spec init(term()) :: {:ok, map()}
  def init(_opts) do
    # Wait for Foundation to be ready
    :ok = wait_for_foundation()

    # Set up DSPEx configuration schema
    setup_dspex_config()

    # Initialize circuit breakers for each provider
    setup_circuit_breakers()

    # Register with Foundation's service registry using a valid service name
    # Use :config_server as it's in the allowed list
    :ok = Foundation.ServiceRegistry.register(:production, :config_server, self())

    # Configuration is now managed by DSPEx.Config.Store - no fallback needed
    {:ok, %{config_system: :independent}}
  end

  @doc """
  Get DSPEx configuration value
  """
  @spec get(list(atom()) | atom()) :: {:ok, term()} | {:error, atom()}
  def get(path) when is_list(path) do
    # Use DSPEx's independent configuration system
    DSPEx.Config.get([:dspex | path])
  end

  def get(key) when is_atom(key) do
    DSPEx.Config.get([:dspex, key])
  end

  @doc """
  Update DSPEx configuration value
  """
  @spec update(list(atom()) | atom(), term()) :: :ok | {:error, term()}
  def update(path, value) when is_list(path) do
    DSPEx.Config.update([:dspex | path], value)
  end

  def update(key, value) when is_atom(key) do
    DSPEx.Config.update([:dspex, key], value)
  end

  @doc """
  Get configuration with default value
  """
  @spec get_with_default(list(atom()) | atom(), term()) :: term()
  def get_with_default(path, default) when is_list(path) do
    DSPEx.Config.get_with_default([:dspex | path], default)
  end

  def get_with_default(key, default) when is_atom(key) do
    DSPEx.Config.get_with_default([:dspex, key], default)
  end

  # Private functions

  @spec wait_for_foundation() :: :ok
  defp wait_for_foundation do
    case Foundation.available?() do
      true ->
        :ok

      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end

  @spec setup_dspex_config() :: :ok
  defp setup_dspex_config do
    # Configuration is now managed by DSPEx.Config.Store (initialized during application startup)
    Logger.debug("DSPEx configuration managed by independent config system")
    :ok
  end

  @spec setup_circuit_breakers() :: :ok
  defp setup_circuit_breakers do
    # Initialize circuit breakers for each provider (now available in Foundation v0.1.2)
    providers = [:gemini, :openai]

    Enum.each(providers, fn provider ->
      circuit_breaker_name = :"dspex_client_#{provider}"

      # Get circuit breaker config from DSPEx's independent config system
      circuit_config =
        case DSPEx.Config.get([:dspex, :providers, provider, :circuit_breaker]) do
          {:ok, config} ->
            config

          {:error, :not_found} ->
            # Default circuit breaker config
            %{
              failure_threshold: 5,
              recovery_time: 30_000
            }
        end

      # Initialize circuit breaker with Foundation's infrastructure service
      case Foundation.Infrastructure.initialize_circuit_breaker(
             circuit_breaker_name,
             circuit_config
           ) do
        :ok ->
          Logger.debug("Initialized circuit breaker for #{provider}")

        {:error, reason} ->
          Logger.warning(
            "Failed to initialize circuit breaker for #{provider}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end

  # Required GenServer callbacks for complete implementation
  @impl GenServer
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state), do: :ok
end

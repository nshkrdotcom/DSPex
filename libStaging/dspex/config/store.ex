defmodule DSPEx.Config.Store do
  @moduledoc """
  ETS-based configuration storage for DSPEx.

  This GenServer manages DSPEx's configuration state using an ETS table for fast access.
  It's completely independent of Foundation's configuration system and provides
  reliable configuration storage with proper supervision.

  ## Features

  - Fast ETS-based configuration storage
  - Concurrent read access
  - Atomic updates via GenServer
  - Default configuration initialization
  - Configuration reset capabilities
  """

  use GenServer
  require Logger

  @table_name :dspex_config
  @server __MODULE__

  # Default configuration matching current DSPEx setup from ConfigManager
  @default_config %{
    dspex: %{
      # Client configuration
      client: %{
        timeout: 30_000,
        retry_attempts: 3,
        backoff_factor: 2
      },

      # Evaluation configuration
      evaluation: %{
        batch_size: 10,
        parallel_limit: 5
      },

      # Teleprompter configuration
      teleprompter: %{
        bootstrap_examples: 5,
        validation_threshold: 0.8
      },

      # Logging configuration
      logging: %{
        level: :info,
        correlation_enabled: true
      },

      # Provider configurations (migrated from ConfigManager)
      providers: %{
        gemini: %{
          api_key: {:system, "GEMINI_API_KEY"},
          base_url: "https://generativelanguage.googleapis.com/v1beta/models",
          default_model: "gemini-2.5-flash-preview-05-20",
          timeout: 30_000,
          rate_limit: %{
            requests_per_minute: 60,
            tokens_per_minute: 100_000
          },
          circuit_breaker: %{
            failure_threshold: 5,
            recovery_time: 30_000
          }
        },
        openai: %{
          api_key: {:system, "OPENAI_API_KEY"},
          base_url: "https://api.openai.com/v1",
          default_model: "gpt-4",
          timeout: 30_000,
          rate_limit: %{
            requests_per_minute: 50,
            tokens_per_minute: 150_000
          },
          circuit_breaker: %{
            failure_threshold: 3,
            recovery_time: 15_000
          }
        }
      },

      # Prediction configuration
      prediction: %{
        default_provider: :gemini,
        default_temperature: 0.7,
        default_max_tokens: 150,
        cache_enabled: true,
        cache_ttl: 3600
      },

      # Teleprompters configuration (BEACON, etc.)
      teleprompters: %{
        beacon: %{
          default_instruction_model: :openai,
          default_evaluation_model: :gemini,
          max_concurrent_operations: 20,
          default_timeout: 60_000,
          optimization: %{
            max_trials: 100,
            convergence_patience: 5,
            improvement_threshold: 0.01
          },
          bayesian_optimization: %{
            acquisition_function: :expected_improvement,
            surrogate_model: :gaussian_process,
            exploration_exploitation_tradeoff: 0.1
          }
        }
      },

      # Telemetry configuration
      telemetry: %{
        enabled: true,
        detailed_logging: false,
        performance_tracking: true
      }
    }
  }

  ## Client API

  @doc """
  Start the configuration store.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @doc """
  Get configuration value by path.
  """
  @spec get(list(atom())) :: {:ok, term()} | {:error, :not_found}
  def get(path) when is_list(path) do
    case :ets.lookup(@table_name, :config) do
      [{:config, config}] ->
        case get_nested_value(config, path) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Update configuration value at path.
  """
  @spec update(list(atom()), term()) :: :ok | {:error, term()}
  def update(path, value) when is_list(path) do
    GenServer.call(@server, {:update, path, value})
  end

  @doc """
  Reset configuration to defaults.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(@server, :reset)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    # Create ETS table for configuration storage
    table =
      :ets.new(@table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])

    # Initialize with default configuration merged with Mix config
    merged_config = merge_with_mix_config(@default_config)
    :ets.insert(table, {:config, merged_config})

    Logger.debug("DSPEx.Config.Store initialized with ETS table: #{inspect(table)}")

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:update, path, value}, _from, %{table: table} = state) do
    case :ets.lookup(table, :config) do
      [{:config, config}] ->
        case update_nested_value(config, path, value) do
          {:ok, new_config} ->
            :ets.insert(table, {:config, new_config})
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      [] ->
        {:reply, {:error, :config_not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:reset, _from, %{table: table} = state) do
    merged_config = merge_with_mix_config(@default_config)
    :ets.insert(table, {:config, merged_config})
    Logger.debug("DSPEx configuration reset to defaults")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, _state) do
    # ETS table will be automatically cleaned up
    :ok
  end

  ## Private Functions

  # Merge default config with Mix configuration (config/test.exs, config/dev.exs, etc.)
  @spec merge_with_mix_config(map()) :: map()
  defp merge_with_mix_config(base_config) do
    mix_providers = Application.get_env(:dspex, :providers, %{})
    mix_prediction = Application.get_env(:dspex, :prediction, %{})
    mix_teleprompters = Application.get_env(:dspex, :teleprompters, %{})
    mix_telemetry = Application.get_env(:dspex, :telemetry, %{})

    base_config
    |> put_in([:dspex, :providers], Map.merge(base_config.dspex.providers, mix_providers))
    |> put_in([:dspex, :prediction], Map.merge(base_config.dspex.prediction, mix_prediction))
    |> put_in(
      [:dspex, :teleprompters],
      Map.merge(base_config.dspex.teleprompters, mix_teleprompters)
    )
    |> put_in([:dspex, :telemetry], Map.merge(base_config.dspex.telemetry, mix_telemetry))
  end

  # Get nested value from configuration map
  @spec get_nested_value(map() | term(), list(atom())) :: {:ok, term()} | :error
  defp get_nested_value(config, []) do
    {:ok, config}
  end

  defp get_nested_value(config, [key | rest]) when is_map(config) do
    case Map.get(config, key) do
      nil -> :error
      value -> get_nested_value(value, rest)
    end
  end

  defp get_nested_value(_, _), do: :error

  # Update nested value in configuration map
  @spec update_nested_value(map(), list(atom()), term()) :: {:ok, map()} | {:error, term()}
  defp update_nested_value(_config, [], value) do
    {:ok, value}
  end

  defp update_nested_value(config, [key], value) when is_map(config) do
    {:ok, Map.put(config, key, value)}
  end

  defp update_nested_value(config, [key | rest], value) when is_map(config) do
    case Map.get(config, key) do
      nil ->
        {:error, :path_not_found}

      nested_value ->
        case update_nested_value(nested_value, rest, value) do
          {:ok, new_nested} -> {:ok, Map.put(config, key, new_nested)}
          error -> error
        end
    end
  end

  defp update_nested_value(_, _, _), do: {:error, :invalid_path}
end

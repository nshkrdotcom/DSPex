defmodule DSPEx.Config do
  @moduledoc """
  DSPEx's independent configuration system.

  Manages DSPEx-specific configuration without relying on Foundation.Config.
  This module provides a clean API for getting and updating configuration values
  while maintaining compatibility with existing DSPEx components.

  ## Usage

      # Get a configuration value
      {:ok, timeout} = DSPEx.Config.get([:dspex, :client, :timeout])

      # Update a configuration value
      :ok = DSPEx.Config.update([:dspex, :client, :timeout], 45_000)

      # Reset configuration to defaults
      :ok = DSPEx.Config.reset()

  ## Configuration Paths

  Supports all DSPEx-specific configuration paths:
  - `[:dspex, :client, :timeout]` - HTTP client timeout
  - `[:dspex, :client, :retry_attempts]` - Number of retry attempts
  - `[:dspex, :evaluation, :batch_size]` - Evaluation batch size
  - `[:dspex, :logging, :level]` - Logging level
  - And many more...

  """

  alias DSPEx.Config.{Store, Validator}

  @type config_path :: [atom()]
  @type config_value :: term()

  @doc """
  Get configuration value by path.

  Returns `{:ok, value}` if the configuration exists, `{:error, :not_found}` otherwise.

  ## Examples

      iex> DSPEx.Config.get([:dspex, :client, :timeout])
      {:ok, 30000}

      iex> DSPEx.Config.get([:dspex, :nonexistent])
      {:error, :not_found}
  """
  @spec get(config_path()) :: {:ok, config_value()} | {:error, :not_found}
  def get(path) when is_list(path) do
    Store.get(path)
  end

  @doc """
  Update configuration value at the given path.

  The path and value are validated before being stored. Returns `:ok` on success,
  `{:error, reason}` on validation failure.

  ## Examples

      iex> DSPEx.Config.update([:dspex, :client, :timeout], 45000)
      :ok

      iex> DSPEx.Config.update([:invalid, :path], "value")
      {:error, :invalid_path}
  """
  @spec update(config_path(), config_value()) :: :ok | {:error, term()}
  def update(path, value) when is_list(path) do
    with :ok <- Validator.validate_path(path),
         :ok <- Validator.validate_value(path, value) do
      Store.update(path, value)
    end
  end

  @doc """
  Reset configuration to default values.

  This will restore all configuration values to their defaults as defined
  in `DSPEx.Config.Store`.

  ## Examples

      iex> DSPEx.Config.reset()
      :ok
  """
  @spec reset() :: :ok
  def reset do
    Store.reset()
  end

  @doc """
  Get configuration value with a default fallback.

  Returns the configuration value if it exists, otherwise returns the provided default.

  ## Examples

      iex> DSPEx.Config.get_with_default([:dspex, :client, :timeout], 60000)
      30000

      iex> DSPEx.Config.get_with_default([:nonexistent, :path], "default")
      "default"
  """
  @spec get_with_default(config_path(), config_value()) :: config_value()
  def get_with_default(path, default) when is_list(path) do
    case get(path) do
      {:ok, value} -> value
      {:error, :not_found} -> default
    end
  end
end

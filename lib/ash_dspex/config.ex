defmodule AshDSPex.Config do
  @moduledoc """
  Configuration management for AshDSPex.

  This module provides centralized configuration management for all AshDSPex
  components, including the signature system and Python bridge integration.

  ## Configuration Structure

  Configuration is organized into logical sections:

  - `:signature_system` - Native Elixir signature compilation and validation
  - `:python_bridge` - Python DSPy process communication settings  
  - `:python_bridge_monitor` - Health monitoring and failure detection
  - `:python_bridge_supervisor` - Supervision tree configuration

  ## Example Configuration

      config :ash_dspex, :signature_system,
        validation_enabled: true,
        compile_time_checks: true,
        json_schema_provider: :openai

      config :ash_dspex, :python_bridge,
        python_executable: "python3",
        default_timeout: 30_000,
        max_retries: 3,
        required_packages: ["dspy-ai"],
        min_python_version: "3.8.0"

      config :ash_dspex, :python_bridge_monitor,
        health_check_interval: 30_000,
        failure_threshold: 3,
        response_timeout: 5_000,
        restart_delay: 1_000

      config :ash_dspex, :python_bridge_supervisor,
        max_restarts: 5,
        max_seconds: 60,
        bridge_restart: :permanent,
        monitor_restart: :permanent

  ## Usage

      # Get specific configuration section
      config = AshDSPex.Config.get(:python_bridge)

      # Get specific setting with default
      timeout = AshDSPex.Config.get(:python_bridge, :default_timeout, 30_000)

      # Validate current configuration
      case AshDSPex.Config.validate() do
        :ok -> Logger.info("Configuration is valid")
        {:error, issues} -> Logger.error("Configuration issues: \#{inspect(issues)}")
      end

  ## Environment Variables

  Some settings can be overridden with environment variables:

  - `ASH_DSPEX_PYTHON_EXECUTABLE` - Python executable path
  - `ASH_DSPEX_BRIDGE_TIMEOUT` - Default bridge timeout in milliseconds
  - `ASH_DSPEX_LOG_LEVEL` - Logging level for bridge components
  """

  require Logger

  @type config_section :: atom()
  @type config_key :: atom()
  @type config_value :: any()
  @type validation_result :: :ok | {:error, [String.t()]}

  @default_configs %{
    signature_system: %{
      validation_enabled: true,
      compile_time_checks: true,
      json_schema_provider: :openai,
      type_validation_strict: false,
      cache_compiled_signatures: true
    },
    python_bridge: %{
      python_executable: "python3",
      default_timeout: 30_000,
      max_retries: 3,
      restart_strategy: :permanent,
      required_packages: ["dspy-ai"],
      min_python_version: "3.8.0",
      script_path: "python/dspy_bridge.py"
    },
    python_bridge_monitor: %{
      health_check_interval: 30_000,
      failure_threshold: 3,
      response_timeout: 5_000,
      restart_delay: 1_000,
      max_restart_attempts: 5,
      restart_cooldown: 60_000
    },
    python_bridge_supervisor: %{
      max_restarts: 5,
      max_seconds: 60,
      bridge_restart: :permanent,
      monitor_restart: :permanent
    }
  }

  @env_var_mappings %{
    "ASH_DSPEX_PYTHON_EXECUTABLE" => [:python_bridge, :python_executable],
    "ASH_DSPEX_BRIDGE_TIMEOUT" => [:python_bridge, :default_timeout],
    "ASH_DSPEX_LOG_LEVEL" => [:system, :log_level],
    "ASH_DSPEX_HEALTH_CHECK_INTERVAL" => [:python_bridge_monitor, :health_check_interval],
    "ASH_DSPEX_FAILURE_THRESHOLD" => [:python_bridge_monitor, :failure_threshold]
  }

  ## Public API

  @doc """
  Gets configuration for a specific section.

  Returns the merged configuration including defaults, application config,
  and environment variable overrides.

  ## Examples

      iex> AshDSPex.Config.get(:python_bridge)
      %{
        python_executable: "python3",
        default_timeout: 30_000,
        max_retries: 3,
        # ... other settings
      }

      iex> AshDSPex.Config.get(:nonexistent_section)
      %{}
  """
  @spec get(config_section()) :: map()
  def get(section) when is_atom(section) do
    section
    |> build_config()
    |> apply_environment_overrides()
  end

  @doc """
  Gets a specific configuration value with optional default.

  ## Examples

      iex> AshDSPex.Config.get(:python_bridge, :default_timeout)
      30_000

      iex> AshDSPex.Config.get(:python_bridge, :nonexistent_key, "default_value")
      "default_value"
  """
  @spec get(config_section(), config_key(), config_value()) :: config_value()
  def get(section, key, default \\ nil) do
    section
    |> get()
    |> Map.get(key, default)
  end

  @doc """
  Validates the current configuration.

  Checks all configuration sections for common issues like:
  - Invalid timeout values
  - Missing required settings
  - Incompatible option combinations
  - Environment variable parsing errors

  ## Examples

      iex> AshDSPex.Config.validate()
      :ok

      iex> AshDSPex.Config.validate()
      {:error, ["Invalid timeout value: -1000", "Python executable not found"]}
  """
  @spec validate() :: validation_result()
  def validate do
    issues = []

    issues = validate_signature_system(issues)
    issues = validate_python_bridge(issues)
    issues = validate_monitor_config(issues)
    issues = validate_supervisor_config(issues)
    issues = validate_environment_variables(issues)

    case issues do
      [] -> :ok
      problems -> {:error, Enum.reverse(problems)}
    end
  end

  @doc """
  Gets all configuration sections as a single map.

  Useful for debugging or comprehensive configuration inspection.

  ## Examples

      iex> AshDSPex.Config.get_all()
      %{
        signature_system: %{...},
        python_bridge: %{...},
        python_bridge_monitor: %{...},
        python_bridge_supervisor: %{...}
      }
  """
  @spec get_all() :: map()
  def get_all do
    @default_configs
    |> Map.keys()
    |> Enum.into(%{}, fn section ->
      {section, get(section)}
    end)
  end

  @doc """
  Resets configuration cache and reloads from application environment.

  Useful during testing or when application configuration changes at runtime.

  ## Examples

      iex> AshDSPex.Config.reload()
      :ok
  """
  @spec reload() :: :ok
  def reload do
    # Clear any internal caches if we add them in the future
    Logger.debug("AshDSPex configuration reloaded")
    :ok
  end

  @doc """
  Gets the default configuration for a section.

  Returns the built-in defaults without any application or environment
  variable overrides.

  ## Examples

      iex> AshDSPex.Config.get_defaults(:python_bridge)
      %{python_executable: "python3", default_timeout: 30_000, ...}
  """
  @spec get_defaults(config_section()) :: map()
  def get_defaults(section) when is_atom(section) do
    Map.get(@default_configs, section, %{})
  end

  ## Private Implementation

  defp build_config(section) do
    defaults = get_defaults(section)
    app_config = Application.get_env(:ash_dspex, section, %{})

    Map.merge(defaults, Map.new(app_config))
  end

  defp apply_environment_overrides(config) do
    Enum.reduce(@env_var_mappings, config, fn {env_var, [_section, key]}, acc ->
      case System.get_env(env_var) do
        nil ->
          acc

        value ->
          parsed_value = parse_env_value(key, value)

          if Map.has_key?(acc, key) do
            Map.put(acc, key, parsed_value)
          else
            acc
          end
      end
    end)
  end

  defp parse_env_value(key, value)
       when key in [
              :default_timeout,
              :health_check_interval,
              :response_timeout,
              :restart_delay,
              :restart_cooldown,
              :max_seconds
            ] do
    case Integer.parse(value) do
      {int_val, ""} when int_val > 0 ->
        int_val

      _ ->
        Logger.warning("Invalid integer value for #{key}: #{value}")
        value
    end
  end

  defp parse_env_value(key, value)
       when key in [:max_retries, :failure_threshold, :max_restart_attempts, :max_restarts] do
    case Integer.parse(value) do
      {int_val, ""} when int_val >= 0 ->
        int_val

      _ ->
        Logger.warning("Invalid non-negative integer value for #{key}: #{value}")
        value
    end
  end

  defp parse_env_value(key, value)
       when key in [
              :validation_enabled,
              :compile_time_checks,
              :type_validation_strict,
              :cache_compiled_signatures
            ] do
    case String.downcase(value) do
      val when val in ["true", "1", "yes", "on"] ->
        true

      val when val in ["false", "0", "no", "off"] ->
        false

      _ ->
        Logger.warning("Invalid boolean value for #{key}: #{value}")
        value
    end
  end

  defp parse_env_value(_key, value), do: value

  ## Validation Functions

  defp validate_signature_system(issues) do
    config = get(:signature_system)

    issues = validate_boolean_setting(config, :validation_enabled, "validation_enabled", issues)
    issues = validate_boolean_setting(config, :compile_time_checks, "compile_time_checks", issues)

    case Map.get(config, :json_schema_provider) do
      provider when provider in [:openai, :anthropic, :generic] -> issues
      invalid -> ["Invalid json_schema_provider: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_python_bridge(issues) do
    config = get(:python_bridge)

    issues = validate_timeout(config, :default_timeout, issues)
    issues = validate_positive_integer(config, :max_retries, issues)

    case Map.get(config, :restart_strategy) do
      strategy when strategy in [:permanent, :temporary, :transient] -> issues
      invalid -> ["Invalid restart_strategy: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_monitor_config(issues) do
    config = get(:python_bridge_monitor)

    issues = validate_timeout(config, :health_check_interval, issues)
    issues = validate_timeout(config, :response_timeout, issues)
    issues = validate_timeout(config, :restart_delay, issues)
    issues = validate_timeout(config, :restart_cooldown, issues)
    issues = validate_positive_integer(config, :failure_threshold, issues)
    issues = validate_positive_integer(config, :max_restart_attempts, issues)

    # Validate that response_timeout < health_check_interval
    response_timeout = Map.get(config, :response_timeout, 0)
    health_interval = Map.get(config, :health_check_interval, 0)

    if response_timeout >= health_interval do
      [
        "response_timeout (#{response_timeout}) should be less than health_check_interval (#{health_interval})"
        | issues
      ]
    else
      issues
    end
  end

  defp validate_supervisor_config(issues) do
    config = get(:python_bridge_supervisor)

    issues = validate_positive_integer(config, :max_restarts, issues)
    issues = validate_positive_integer(config, :max_seconds, issues)

    issues =
      case Map.get(config, :bridge_restart) do
        strategy when strategy in [:permanent, :temporary, :transient] -> issues
        invalid -> ["Invalid bridge_restart strategy: #{inspect(invalid)}" | issues]
      end

    case Map.get(config, :monitor_restart) do
      strategy when strategy in [:permanent, :temporary, :transient] -> issues
      invalid -> ["Invalid monitor_restart strategy: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_environment_variables(issues) do
    Enum.reduce(@env_var_mappings, issues, fn {env_var, [_section, key]}, acc ->
      case System.get_env(env_var) do
        nil ->
          acc

        value ->
          case parse_env_value(key, value) do
            ^value when is_binary(value) ->
              # Parsing failed, already logged warning
              ["Invalid environment variable #{env_var}: #{value}" | acc]

            _parsed_value ->
              # Parsing succeeded
              acc
          end
      end
    end)
  end

  defp validate_timeout(config, key, issues) do
    case Map.get(config, key) do
      timeout when is_integer(timeout) and timeout > 0 -> issues
      invalid -> ["Invalid timeout value for #{key}: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_positive_integer(config, key, issues) do
    case Map.get(config, key) do
      value when is_integer(value) and value > 0 -> issues
      invalid -> ["Invalid positive integer value for #{key}: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_boolean_setting(config, key, name, issues) do
    case Map.get(config, key) do
      value when is_boolean(value) -> issues
      invalid -> ["Invalid boolean value for #{name}: #{inspect(invalid)}" | issues]
    end
  end
end

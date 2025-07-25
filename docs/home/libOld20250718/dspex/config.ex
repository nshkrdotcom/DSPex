defmodule DSPex.Config do
  @moduledoc """
  Configuration management for DSPex.

  This module provides centralized configuration management for all DSPex
  components, including the signature system and Python bridge integration.

  ## Configuration Structure

  Configuration is organized into logical sections:

  - `:signature_system` - Native Elixir signature compilation and validation
  - `:python_bridge` - Python DSPy process communication settings
  - `:python_bridge_monitor` - Health monitoring and failure detection
  - `:python_bridge_supervisor` - Supervision tree configuration

  ## Example Configuration

      config :dspex, :signature_system,
        validation_enabled: true,
        compile_time_checks: true,
        json_schema_provider: :openai

      config :dspex, :python_bridge,
        python_executable: "python3",
        default_timeout: 30_000,
        max_retries: 3,
        required_packages: ["dspy-ai"],
        min_python_version: "3.8.0"

      config :dspex, :python_bridge_monitor,
        health_check_interval: 30_000,
        failure_threshold: 3,
        response_timeout: 5_000,
        restart_delay: 1_000

      config :dspex, :python_bridge_supervisor,
        max_restarts: 5,
        max_seconds: 60,
        bridge_restart: :permanent,
        monitor_restart: :permanent

  ## Usage

      # Get specific configuration section
      config = DSPex.Config.get(:python_bridge)

      # Get specific setting with default
      timeout = DSPex.Config.get(:python_bridge, :default_timeout, 30_000)

      # Validate current configuration
      case DSPex.Config.validate() do
        :ok -> Logger.info("Configuration is valid")
        {:error, issues} -> Logger.error("Configuration issues: \#{inspect(issues)}")
      end

  ## Environment Variables

  Some settings can be overridden with environment variables:

  - `DSPEX_PYTHON_EXECUTABLE` - Python executable path
  - `DSPEX_BRIDGE_TIMEOUT` - Default bridge timeout in milliseconds
  - `DSPEX_LOG_LEVEL` - Logging level for bridge components
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
    },
    minimal_python_pool: %{
      pool_size: System.schedulers_online(),
      overflow: 2,
      checkout_timeout: 5_000,
      operation_timeout: 30_000,
      python_executable: "python3",
      script_path: "priv/python/dspy_bridge.py",
      health_check_enabled: true,
      session_tracking_enabled: true
    }
  }

  @env_var_mappings %{
    "DSPEX_PYTHON_EXECUTABLE" => [:python_bridge, :python_executable],
    "DSPEX_BRIDGE_TIMEOUT" => [:python_bridge, :default_timeout],
    "DSPEX_LOG_LEVEL" => [:system, :log_level],
    "DSPEX_HEALTH_CHECK_INTERVAL" => [:python_bridge_monitor, :health_check_interval],
    "DSPEX_FAILURE_THRESHOLD" => [:python_bridge_monitor, :failure_threshold],
    "DSPEX_POOL_SIZE" => [:minimal_python_pool, :pool_size],
    "DSPEX_POOL_OVERFLOW" => [:minimal_python_pool, :overflow],
    "DSPEX_CHECKOUT_TIMEOUT" => [:minimal_python_pool, :checkout_timeout],
    "DSPEX_OPERATION_TIMEOUT" => [:minimal_python_pool, :operation_timeout]
  }

  ## Public API

  @doc """
  Gets configuration for a specific section.

  Returns the merged configuration including defaults, application config,
  and environment variable overrides.

  ## Examples

      iex> DSPex.Config.get(:python_bridge)
      %{
        python_executable: "python3",
        default_timeout: 30_000,
        max_retries: 3,
        # ... other settings
      }

      iex> DSPex.Config.get(:nonexistent_section)
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

      iex> DSPex.Config.get(:python_bridge, :default_timeout)
      30_000

      iex> DSPex.Config.get(:python_bridge, :nonexistent_key, "default_value")
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

      iex> DSPex.Config.validate()
      :ok

      iex> DSPex.Config.validate()
      {:error, ["Invalid timeout value: -1000", "Python executable not found"]}
  """
  @spec validate() :: validation_result()
  def validate do
    issues = []

    issues = validate_signature_system(issues)
    issues = validate_python_bridge(issues)
    issues = validate_monitor_config(issues)
    issues = validate_supervisor_config(issues)
    issues = validate_minimal_python_pool(issues)
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

      iex> DSPex.Config.get_all()
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

      iex> DSPex.Config.reload()
      :ok
  """
  @spec reload() :: :ok
  def reload do
    # Clear any internal caches if we add them in the future
    Logger.debug("DSPex configuration reloaded")
    :ok
  end

  @doc """
  Gets the default configuration for a section.

  Returns the built-in defaults without any application or environment
  variable overrides.

  ## Examples

      iex> DSPex.Config.get_defaults(:python_bridge)
      %{python_executable: "python3", default_timeout: 30_000, ...}
  """
  @spec get_defaults(config_section()) :: map()
  def get_defaults(section) when is_atom(section) do
    Map.get(@default_configs, section, %{})
  end

  ## Private Implementation

  defp build_config(section) do
    defaults = get_defaults(section)
    app_config = Application.get_env(:dspex, section, %{})

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
              :max_seconds,
              :checkout_timeout,
              :operation_timeout
            ] do
    case Integer.parse(value) do
      {int_val, ""} ->
        # Accept any valid integer for now, validation happens separately
        int_val

      _ ->
        Logger.warning("Invalid integer value for #{key}: #{value}")
        # Return appropriate default based on key
        get_default_for_key(key)
    end
  end

  defp parse_env_value(key, value)
       when key in [
              :max_retries,
              :failure_threshold,
              :max_restart_attempts,
              :max_restarts,
              :pool_size,
              :overflow
            ] do
    case Integer.parse(value) do
      {int_val, ""} when int_val >= 0 ->
        int_val

      _ ->
        Logger.warning("Invalid non-negative integer value for #{key}: #{value}")
        # Return appropriate default based on key
        get_default_for_key(key)
    end
  end

  defp parse_env_value(key, value)
       when key in [
              :validation_enabled,
              :compile_time_checks,
              :type_validation_strict,
              :cache_compiled_signatures,
              :health_check_enabled,
              :session_tracking_enabled
            ] do
    case String.downcase(value) do
      val when val in ["true", "1", "yes", "on"] ->
        true

      val when val in ["false", "0", "no", "off"] ->
        false

      _ ->
        Logger.warning("Invalid boolean value for #{key}: #{value}")
        # Return appropriate default based on key
        get_default_for_key(key)
    end
  end

  defp parse_env_value(_key, value), do: value

  defp get_default_for_key(key) do
    # Search through all default config sections to find the key
    default_value =
      Enum.find_value(@default_configs, fn {_section, section_config} ->
        Map.get(section_config, key)
      end)

    # Return the found default or a sensible fallback
    case default_value do
      nil ->
        cond do
          # Timeout/interval keys should default to a positive integer
          key in [
            :default_timeout,
            :health_check_interval,
            :response_timeout,
            :restart_delay,
            :restart_cooldown,
            :max_seconds
          ] ->
            30_000

          # Count/threshold keys should default to a reasonable positive integer
          key in [:max_retries, :failure_threshold, :max_restart_attempts, :max_restarts] ->
            3

          # Boolean keys should default to true
          key in [
            :validation_enabled,
            :compile_time_checks,
            :type_validation_strict,
            :cache_compiled_signatures
          ] ->
            true

          # Unknown key, return nil
          true ->
            nil
        end

      value ->
        value
    end
  end

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

  defp validate_minimal_python_pool(issues) do
    config = get(:minimal_python_pool)

    issues = validate_positive_integer(config, :pool_size, issues)
    issues = validate_non_negative_integer(config, :overflow, issues)
    issues = validate_timeout(config, :checkout_timeout, issues)
    issues = validate_timeout(config, :operation_timeout, issues)

    issues =
      validate_boolean_setting(config, :health_check_enabled, "health_check_enabled", issues)

    issues =
      validate_boolean_setting(
        config,
        :session_tracking_enabled,
        "session_tracking_enabled",
        issues
      )

    # Validate that checkout_timeout < operation_timeout
    checkout_timeout = Map.get(config, :checkout_timeout, 0)
    operation_timeout = Map.get(config, :operation_timeout, 0)

    if checkout_timeout >= operation_timeout do
      [
        "checkout_timeout (#{checkout_timeout}) should be less than operation_timeout (#{operation_timeout})"
        | issues
      ]
    else
      issues
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

  defp validate_non_negative_integer(config, key, issues) do
    case Map.get(config, key) do
      value when is_integer(value) and value >= 0 -> issues
      invalid -> ["Invalid non-negative integer value for #{key}: #{inspect(invalid)}" | issues]
    end
  end

  defp validate_boolean_setting(config, key, name, issues) do
    case Map.get(config, key) do
      value when is_boolean(value) -> issues
      invalid -> ["Invalid boolean value for #{name}: #{inspect(invalid)}" | issues]
    end
  end
end

defmodule DSPEx.Config.Validator do
  @moduledoc """
  Validation rules for DSPEx configuration.

  Enhanced with Sinter schema-based validation for improved type safety,
  detailed error reporting, and maintainable validation logic.

  This module provides validation for all supported DSPEx configuration
  paths and their corresponding value types using declarative schemas
  instead of manual validation functions.

  ## Supported Configuration Paths

  - Client configuration: `[:dspex, :client, :timeout]`, etc.
  - Evaluation configuration: `[:dspex, :evaluation, :batch_size]`, etc.
  - Provider configuration: `[:dspex, :providers, :gemini, ...]`, etc.
  - And many more...

  ## Enhanced Features

  - Schema-based validation with Sinter integration
  - Field-level error reporting with detailed messages
  - JSON schema export for documentation
  - Automatic constraint validation
  - Improved maintainability through declarative schemas
  """

  alias DSPEx.Config.SinterSchemas

  # Valid configuration paths - comprehensive list based on ConfigManager analysis
  @valid_paths [
    # Client configuration
    [:dspex, :client, :timeout],
    [:dspex, :client, :retry_attempts],
    [:dspex, :client, :backoff_factor],

    # Evaluation configuration
    [:dspex, :evaluation, :batch_size],
    [:dspex, :evaluation, :parallel_limit],

    # Teleprompter configuration
    [:dspex, :teleprompter, :bootstrap_examples],
    [:dspex, :teleprompter, :validation_threshold],

    # Logging configuration
    [:dspex, :logging, :level],
    [:dspex, :logging, :correlation_enabled],

    # Provider configurations - Gemini
    [:dspex, :providers, :gemini, :api_key],
    [:dspex, :providers, :gemini, :base_url],
    [:dspex, :providers, :gemini, :default_model],
    [:dspex, :providers, :gemini, :timeout],
    [:dspex, :providers, :gemini, :rate_limit, :requests_per_minute],
    [:dspex, :providers, :gemini, :rate_limit, :tokens_per_minute],
    [:dspex, :providers, :gemini, :circuit_breaker, :failure_threshold],
    [:dspex, :providers, :gemini, :circuit_breaker, :recovery_time],

    # Provider configurations - OpenAI
    [:dspex, :providers, :openai, :api_key],
    [:dspex, :providers, :openai, :base_url],
    [:dspex, :providers, :openai, :default_model],
    [:dspex, :providers, :openai, :timeout],
    [:dspex, :providers, :openai, :rate_limit, :requests_per_minute],
    [:dspex, :providers, :openai, :rate_limit, :tokens_per_minute],
    [:dspex, :providers, :openai, :circuit_breaker, :failure_threshold],
    [:dspex, :providers, :openai, :circuit_breaker, :recovery_time],

    # Prediction configuration
    [:dspex, :prediction, :default_provider],
    [:dspex, :prediction, :default_temperature],
    [:dspex, :prediction, :default_max_tokens],
    [:dspex, :prediction, :cache_enabled],
    [:dspex, :prediction, :cache_ttl],

    # BEACON teleprompter configuration
    [:dspex, :teleprompters, :beacon, :default_instruction_model],
    [:dspex, :teleprompters, :beacon, :default_evaluation_model],
    [:dspex, :teleprompters, :beacon, :max_concurrent_operations],
    [:dspex, :teleprompters, :beacon, :default_timeout],
    [:dspex, :teleprompters, :beacon, :optimization, :max_trials],
    [:dspex, :teleprompters, :beacon, :optimization, :convergence_patience],
    [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
    [:dspex, :teleprompters, :beacon, :bayesian_optimization, :exploration_exploitation_tradeoff],

    # Telemetry configuration
    [:dspex, :telemetry, :enabled],
    [:dspex, :telemetry, :detailed_logging],
    [:dspex, :telemetry, :performance_tracking]
  ]

  # Valid log levels
  @valid_log_levels [
    :emergency,
    :alert,
    :critical,
    :error,
    :warning,
    :warn,
    :notice,
    :info,
    :debug
  ]

  # Valid providers
  @valid_providers [:gemini, :openai]

  # Valid acquisition functions for Bayesian optimization
  @valid_acquisition_functions [
    :expected_improvement,
    :probability_of_improvement,
    :upper_confidence_bound
  ]

  # Valid surrogate models
  @valid_surrogate_models [:gaussian_process, :random_forest, :extra_trees]

  @doc """
  Validate that a configuration path is supported.

  Returns `:ok` if the path is valid, `{:error, :invalid_path}` otherwise.

  ## Examples

      iex> DSPEx.Config.Validator.validate_path([:dspex, :client, :timeout])
      :ok

      iex> DSPEx.Config.Validator.validate_path([:invalid, :path])
      {:error, :invalid_path}
  """
  @spec validate_path(list(atom())) :: :ok | {:error, :invalid_path}
  def validate_path(path) when is_list(path) do
    if path in @valid_paths or path_prefix_valid?(path) do
      :ok
    else
      {:error, :invalid_path}
    end
  end

  def validate_path(_), do: {:error, :invalid_path}

  @doc """
  Validate that a configuration value is appropriate for the given path.

  Enhanced with schema-based validation for better error reporting and
  automatic constraint validation.

  Returns `:ok` if the value is valid, `{:error, reason}` otherwise.

  ## Examples

      iex> DSPEx.Config.Validator.validate_value([:dspex, :client, :timeout], 30000)
      :ok

      iex> DSPEx.Config.Validator.validate_value([:dspex, :client, :timeout], "invalid")
      {:error, :invalid_timeout}
  """
  @spec validate_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_value(path, value) do
    case SinterSchemas.validate_config_value(path, value) do
      :ok -> :ok
      {:error, {:unknown_path, path}} -> {:error, {:unknown_path, path}}
      {:error, {error_atom, _message}} when is_atom(error_atom) -> {:error, error_atom}
    end
  end

  @doc """
  Enhanced validation with detailed error reporting.

  Returns comprehensive validation information including field-level errors
  and suggested corrections for improved developer experience.

  ## Examples

      iex> DSPEx.Config.Validator.validate_value_detailed([:dspex, :client, :timeout], "invalid")
      {:error, %{
        message: "expected integer, got string",
        path: [:dspex, :client, :timeout],
        field: :timeout,
        provided: "invalid",
        error_code: :invalid_timeout,
        suggestion: "Use a positive integer value in milliseconds, e.g., 30000"
      }}
  """
  @spec validate_value_detailed(list(atom()), term()) ::
          :ok | {:error, map()}
  def validate_value_detailed(path, value) do
    case SinterSchemas.validate_config_value(path, value) do
      :ok ->
        :ok

      {:error, {:unknown_path, path}} ->
        {:error, {:unknown_path, path}}

      {:error, {error_atom, message}} when is_atom(error_atom) ->
        {:error,
         %{
           field: List.last(path),
           provided: value,
           error_code: error_atom,
           message: message,
           path: path,
           suggestion: generate_suggestion(path, value, error_atom)
         }}
    end
  end

  @doc """
  Export JSON schema for configuration documentation.

  ## Examples

      iex> {:ok, schema} = DSPEx.Config.Validator.export_schema(:client)
      iex> schema["type"]
      "object"
  """
  @spec export_schema(atom()) :: {:ok, map()} | {:error, term()}
  def export_schema(domain) do
    SinterSchemas.export_json_schema(domain)
  end

  @doc """
  List all available configuration domains.
  """
  @spec list_domains() :: [atom()]
  def list_domains do
    SinterSchemas.list_domains()
  end

  @doc """
  Legacy validation function - kept for compatibility.

  This function provides the original manual validation logic as fallback
  for any edge cases not covered by schema validation.
  """
  @spec validate_value_legacy(list(atom()), term()) :: :ok | {:error, term()}
  def validate_value_legacy(path, value)

  # Timeout validations (must be positive integer)
  def validate_value_legacy([:dspex, :client, :timeout], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :client, :timeout], _), do: {:error, :invalid_timeout}

  def validate_value_legacy([:dspex, :providers, _, :timeout], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :timeout], _), do: {:error, :invalid_timeout}

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_timeout], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_timeout], _),
    do: {:error, :invalid_timeout}

  # Retry attempts (must be non-negative integer)
  def validate_value_legacy([:dspex, :client, :retry_attempts], value)
      when is_integer(value) and value >= 0,
      do: :ok

  def validate_value_legacy([:dspex, :client, :retry_attempts], _),
    do: {:error, :invalid_retry_attempts}

  # Backoff factor (must be positive number)
  def validate_value_legacy([:dspex, :client, :backoff_factor], value)
      when is_number(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :client, :backoff_factor], _),
    do: {:error, :invalid_backoff_factor}

  # Batch size and parallel limits (must be positive integer)
  def validate_value_legacy([:dspex, :evaluation, :batch_size], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :evaluation, :batch_size], _),
    do: {:error, :invalid_batch_size}

  def validate_value_legacy([:dspex, :evaluation, :parallel_limit], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :evaluation, :parallel_limit], _),
    do: {:error, :invalid_parallel_limit}

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :max_concurrent_operations], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :max_concurrent_operations], _),
    do: {:error, :invalid_concurrent_operations}

  # Bootstrap examples (must be positive integer)
  def validate_value_legacy([:dspex, :teleprompter, :bootstrap_examples], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompter, :bootstrap_examples], _),
    do: {:error, :invalid_bootstrap_examples}

  # Validation threshold (must be float between 0 and 1)
  def validate_value_legacy([:dspex, :teleprompter, :validation_threshold], value)
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompter, :validation_threshold], _),
    do: {:error, :invalid_validation_threshold}

  # Temperature (must be float between 0 and 2)
  def validate_value_legacy([:dspex, :prediction, :default_temperature], value)
      when is_float(value) and value >= 0.0 and value <= 2.0,
      do: :ok

  def validate_value_legacy([:dspex, :prediction, :default_temperature], _),
    do: {:error, :invalid_temperature}

  # Max tokens (must be positive integer)
  def validate_value_legacy([:dspex, :prediction, :default_max_tokens], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :prediction, :default_max_tokens], _),
    do: {:error, :invalid_max_tokens}

  # TTL values (must be positive integer)
  def validate_value_legacy([:dspex, :prediction, :cache_ttl], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :prediction, :cache_ttl], _),
    do: {:error, :invalid_cache_ttl}

  def validate_value_legacy([:dspex, :providers, _, :circuit_breaker, :recovery_time], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :circuit_breaker, :recovery_time], _),
    do: {:error, :invalid_recovery_time}

  # Logging level validation
  def validate_value_legacy([:dspex, :logging, :level], value) when value in @valid_log_levels,
    do: :ok

  def validate_value_legacy([:dspex, :logging, :level], _), do: {:error, :invalid_log_level}

  # Boolean validations
  def validate_value_legacy([:dspex, :logging, :correlation_enabled], value)
      when is_boolean(value),
      do: :ok

  def validate_value_legacy([:dspex, :logging, :correlation_enabled], _),
    do: {:error, :invalid_boolean}

  def validate_value_legacy([:dspex, :prediction, :cache_enabled], value) when is_boolean(value),
    do: :ok

  def validate_value_legacy([:dspex, :prediction, :cache_enabled], _),
    do: {:error, :invalid_boolean}

  def validate_value_legacy([:dspex, :telemetry, :enabled], value) when is_boolean(value), do: :ok
  def validate_value_legacy([:dspex, :telemetry, :enabled], _), do: {:error, :invalid_boolean}

  def validate_value_legacy([:dspex, :telemetry, :detailed_logging], value)
      when is_boolean(value),
      do: :ok

  def validate_value_legacy([:dspex, :telemetry, :detailed_logging], _),
    do: {:error, :invalid_boolean}

  def validate_value_legacy([:dspex, :telemetry, :performance_tracking], value)
      when is_boolean(value),
      do: :ok

  def validate_value_legacy([:dspex, :telemetry, :performance_tracking], _),
    do: {:error, :invalid_boolean}

  # Provider validation
  def validate_value_legacy([:dspex, :prediction, :default_provider], value)
      when value in @valid_providers,
      do: :ok

  def validate_value_legacy([:dspex, :prediction, :default_provider], _),
    do: {:error, :invalid_provider}

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_instruction_model], value)
      when value in @valid_providers,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_instruction_model], _),
    do: {:error, :invalid_provider}

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_evaluation_model], value)
      when value in @valid_providers,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :default_evaluation_model], _),
    do: {:error, :invalid_provider}

  # String validations (API keys, URLs, models)
  def validate_value_legacy([:dspex, :providers, _, :api_key], {:system, env_var})
      when is_binary(env_var),
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :api_key], value) when is_binary(value),
    do: :ok

  def validate_value_legacy([:dspex, :providers, _, :api_key], _), do: {:error, :invalid_api_key}

  def validate_value_legacy([:dspex, :providers, _, :base_url], value) when is_binary(value),
    do: :ok

  def validate_value_legacy([:dspex, :providers, _, :base_url], _),
    do: {:error, :invalid_base_url}

  def validate_value_legacy([:dspex, :providers, _, :default_model], value) when is_binary(value),
    do: :ok

  def validate_value_legacy([:dspex, :providers, _, :default_model], _),
    do: {:error, :invalid_model}

  # Rate limit validations (must be positive integers)
  def validate_value_legacy([:dspex, :providers, _, :rate_limit, :requests_per_minute], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :rate_limit, :requests_per_minute], _),
    do: {:error, :invalid_rate_limit}

  def validate_value_legacy([:dspex, :providers, _, :rate_limit, :tokens_per_minute], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :rate_limit, :tokens_per_minute], _),
    do: {:error, :invalid_rate_limit}

  # Circuit breaker validations
  def validate_value_legacy([:dspex, :providers, _, :circuit_breaker, :failure_threshold], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :providers, _, :circuit_breaker, :failure_threshold], _),
    do: {:error, :invalid_failure_threshold}

  # BEACON optimization validations
  def validate_value_legacy([:dspex, :teleprompters, :beacon, :optimization, :max_trials], value)
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy([:dspex, :teleprompters, :beacon, :optimization, :max_trials], _),
    do: {:error, :invalid_max_trials}

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :optimization, :convergence_patience],
        value
      )
      when is_integer(value) and value > 0,
      do: :ok

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :optimization, :convergence_patience],
        _
      ),
      do: {:error, :invalid_convergence_patience}

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
        value
      )
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :optimization, :improvement_threshold],
        _
      ),
      do: {:error, :invalid_improvement_threshold}

  # Bayesian optimization validations
  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
        value
      )
      when value in @valid_acquisition_functions,
      do: :ok

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
        _
      ),
      do: {:error, :invalid_acquisition_function}

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
        value
      )
      when value in @valid_surrogate_models,
      do: :ok

  def validate_value_legacy(
        [:dspex, :teleprompters, :beacon, :bayesian_optimization, :surrogate_model],
        _
      ),
      do: {:error, :invalid_surrogate_model}

  def validate_value_legacy(
        [
          :dspex,
          :teleprompters,
          :beacon,
          :bayesian_optimization,
          :exploration_exploitation_tradeoff
        ],
        value
      )
      when is_float(value) and value >= 0.0 and value <= 1.0,
      do: :ok

  def validate_value_legacy(
        [
          :dspex,
          :teleprompters,
          :beacon,
          :bayesian_optimization,
          :exploration_exploitation_tradeoff
        ],
        _
      ),
      do: {:error, :invalid_tradeoff}

  # Default case - unknown path
  def validate_value_legacy(path, _value) do
    {:error, {:unknown_path, path}}
  end

  ## Private Functions

  # Check if a path has a valid prefix (for nested configurations)
  @spec path_prefix_valid?(list(atom())) :: boolean()
  defp path_prefix_valid?(path) do
    # Allow any path that starts with [:dspex] for extensibility
    # This enables adding new configuration paths without updating the validator
    case path do
      [:dspex | _] -> true
      _ -> false
    end
  end

  # Generate helpful suggestions for validation errors
  @spec generate_suggestion(list(atom()), term(), atom()) :: String.t()
  defp generate_suggestion(path, _value, _error_code) do
    field = List.last(path)
    get_field_suggestion(field)
  end

  defp get_field_suggestion(field) when field in [:timeout, :retry_attempts, :backoff_factor] do
    get_numeric_field_suggestion(field)
  end

  defp get_field_suggestion(field) when field in [:batch_size, :parallel_limit] do
    suggest_positive_integer()
  end

  defp get_field_suggestion(field) when field in [:default_temperature, :default_max_tokens] do
    get_model_field_suggestion(field)
  end

  defp get_field_suggestion(field) when field in [:level, :default_provider, :api_key] do
    get_config_field_suggestion(field)
  end

  defp get_field_suggestion(field)
       when field in [
              :enabled,
              :correlation_enabled,
              :cache_enabled,
              :detailed_logging,
              :performance_tracking
            ] do
    suggest_boolean()
  end

  defp get_field_suggestion(_field) do
    suggest_generic()
  end

  defp get_numeric_field_suggestion(:timeout), do: suggest_timeout()
  defp get_numeric_field_suggestion(:retry_attempts), do: suggest_retry_attempts()
  defp get_numeric_field_suggestion(:backoff_factor), do: suggest_backoff_factor()

  defp get_model_field_suggestion(:default_temperature), do: suggest_temperature()
  defp get_model_field_suggestion(:default_max_tokens), do: suggest_max_tokens()

  defp get_config_field_suggestion(:level), do: suggest_log_level()
  defp get_config_field_suggestion(:default_provider), do: suggest_provider()
  defp get_config_field_suggestion(:api_key), do: suggest_api_key()

  defp suggest_timeout, do: "Use a positive integer value in milliseconds, e.g., 30000"
  defp suggest_retry_attempts, do: "Use a non-negative integer, e.g., 3"
  defp suggest_backoff_factor, do: "Use a positive number, e.g., 2.0"
  defp suggest_positive_integer, do: "Use a positive integer, e.g., 10"
  defp suggest_temperature, do: "Use a float between 0.0 and 2.0, e.g., 0.7"
  defp suggest_max_tokens, do: "Use a positive integer, e.g., 1000"
  defp suggest_log_level, do: "Use a valid log level: :debug, :info, :warning, :error, :critical"
  defp suggest_provider, do: "Use a valid provider: :gemini or :openai"
  defp suggest_api_key, do: "Use a string API key or {:system, \"ENV_VAR\"} tuple"
  defp suggest_boolean, do: "Use a boolean value: true or false"
  defp suggest_generic, do: "Check the value type and constraints for this configuration field"
end

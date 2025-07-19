defmodule DSPEx.Config.ElixirMLSchemas do
  @moduledoc """
  ElixirML schema definitions for DSPEx configuration validation.

  This module provides schema-based validation for DSPEx configuration
  with enhanced error reporting and path-based validation mapping using ElixirML.

  Key improvements over SinterSchemas:
  - ML-native types for better semantic validation
  - Enhanced constraint handling with ElixirML Runtime
  - Provider-specific optimizations for LLM configurations
  - Better integration with the ElixirML variable system
  """

  alias ElixirML.Runtime

  @doc """
  Maps configuration paths to their corresponding validation schema and field path.
  """
  @spec path_to_schema(list(atom())) :: {:ok, map(), list(atom())} | {:error, :unknown_path}
  def path_to_schema(path)

  # Client configuration mappings
  def path_to_schema([:dspex, :client, field])
      when field in [:timeout, :retry_attempts, :backoff_factor] do
    {:ok, client_configuration_schema(), [field]}
  end

  # Evaluation configuration mappings
  def path_to_schema([:dspex, :evaluation, field]) when field in [:batch_size, :parallel_limit] do
    {:ok, evaluation_configuration_schema(), [field]}
  end

  # Teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompter, field])
      when field in [:bootstrap_examples, :validation_threshold] do
    {:ok, teleprompter_configuration_schema(), [field]}
  end

  # Logging configuration mappings
  def path_to_schema([:dspex, :logging, field]) when field in [:level, :correlation_enabled] do
    {:ok, logging_configuration_schema(), [field]}
  end

  # Provider configuration mappings (with wildcard support)
  def path_to_schema([:dspex, :providers, _provider, field])
      when field in [:api_key, :base_url, :default_model, :timeout] do
    {:ok, provider_configuration_schema(), [field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :rate_limit, field])
      when field in [:requests_per_minute, :tokens_per_minute] do
    {:ok, rate_limit_schema(), [field]}
  end

  def path_to_schema([:dspex, :providers, _provider, :circuit_breaker, field])
      when field in [:failure_threshold, :recovery_time] do
    {:ok, circuit_breaker_schema(), [field]}
  end

  # Prediction configuration mappings
  def path_to_schema([:dspex, :prediction, field])
      when field in [
             :default_provider,
             :default_temperature,
             :default_max_tokens,
             :cache_enabled,
             :cache_ttl
           ] do
    {:ok, prediction_configuration_schema(), [field]}
  end

  # BEACON teleprompter configuration mappings
  def path_to_schema([:dspex, :teleprompters, :beacon, field])
      when field in [
             :default_instruction_model,
             :default_evaluation_model,
             :max_concurrent_operations,
             :default_timeout
           ] do
    {:ok, beacon_configuration_schema(), [field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :optimization, field])
      when field in [:max_trials, :convergence_patience, :improvement_threshold] do
    {:ok, optimization_schema(), [field]}
  end

  def path_to_schema([:dspex, :teleprompters, :beacon, :bayesian_optimization, field])
      when field in [:acquisition_function, :surrogate_model, :exploration_exploitation_tradeoff] do
    {:ok, bayesian_optimization_schema(), [field]}
  end

  # Telemetry configuration mappings
  def path_to_schema([:dspex, :telemetry, field])
      when field in [:enabled, :detailed_logging, :performance_tracking] do
    {:ok, telemetry_configuration_schema(), [field]}
  end

  # Unknown path
  def path_to_schema(_path), do: {:error, :unknown_path}

  @doc """
  Validates a configuration value using ElixirML schema-based validation.
  """
  @spec validate_config_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_config_value(path, value) do
    case path_to_schema(path) do
      {:ok, schema, field_path} ->
        validate_field_with_elixir_ml(schema, field_path, value)

      {:error, :unknown_path} ->
        {:error, {:unknown_path, path}}
    end
  end

  @doc """
  Lists all available configuration domains.
  """
  @spec list_domains() :: [atom()]
  def list_domains do
    [:client, :provider, :prediction, :evaluation, :teleprompter, :beacon, :logging, :telemetry]
  end

  @doc """
  Exports JSON schema for documentation using ElixirML.
  """
  @spec export_json_schema(atom()) :: {:ok, map()} | {:error, term()}
  def export_json_schema(domain) do
    case get_domain_schema(domain) do
      nil -> {:error, {:unknown_domain, domain}}
      schema -> {:ok, Runtime.to_json_schema(schema, provider: :generic)}
    end
  end

  ## Schema Definitions using ElixirML

  @doc """
  Client configuration schema using ElixirML.
  """
  @spec client_configuration_schema() :: map()
  def client_configuration_schema do
    fields = [
      {:timeout, :integer, required: true, gteq: 1, lteq: 300_000},
      {:retry_attempts, :integer, required: true, gteq: 0, lteq: 10},
      {:backoff_factor, :float, required: true, gteq: 1.0, lteq: 10.0}
    ]

    Runtime.create_schema(fields,
      title: "Client Configuration Schema",
      description: "DSPEx client configuration with timeout and retry settings"
    )
  end

  @doc """
  Provider configuration schema using ElixirML.
  """
  @spec provider_configuration_schema() :: map()
  def provider_configuration_schema do
    fields = [
      # API key can be string or {:system, env_var} tuple
      {:api_key, :api_key, required: true},
      {:base_url, :string, required: true, min_length: 1},
      {:default_model, :string, required: true, min_length: 1},
      {:timeout, :integer, required: true, gteq: 1, lteq: 300_000}
    ]

    Runtime.create_schema(fields,
      title: "Provider Configuration Schema",
      description: "LLM provider configuration with authentication and limits"
    )
  end

  @doc """
  Prediction configuration schema using ElixirML with ML-native types.
  """
  @spec prediction_configuration_schema() :: map()
  def prediction_configuration_schema do
    fields = [
      {:default_provider, :atom, required: true, choices: [:openai, :anthropic, :gemini]},
      # Use float with temperature-like constraints for ML-native validation
      {:default_temperature, :float, required: true, gteq: 0.0, lteq: 2.0},
      {:default_max_tokens, :integer, required: true, gteq: 1, lteq: 32_000},
      {:cache_enabled, :boolean, required: true},
      {:cache_ttl, :integer, required: true, gteq: 0, lteq: 86_400}
    ]

    Runtime.create_schema(fields,
      title: "Prediction Configuration Schema",
      description: "ML prediction configuration with provider and model settings"
    )
  end

  @doc """
  Evaluation configuration schema using ElixirML.
  """
  @spec evaluation_configuration_schema() :: map()
  def evaluation_configuration_schema do
    fields = [
      {:batch_size, :integer, required: true, gteq: 1, lteq: 1000},
      {:parallel_limit, :integer, required: true, gteq: 1, lteq: 100}
    ]

    Runtime.create_schema(fields,
      title: "Evaluation Configuration Schema",
      description: "Evaluation pipeline configuration for batch processing"
    )
  end

  @doc """
  Teleprompter configuration schema using ElixirML.
  """
  @spec teleprompter_configuration_schema() :: map()
  def teleprompter_configuration_schema do
    fields = [
      {:bootstrap_examples, :integer, required: true, gteq: 1, lteq: 100},
      # Use float with probability-like constraints for validation threshold
      {:validation_threshold, :float, required: true, gteq: 0.0, lteq: 1.0}
    ]

    Runtime.create_schema(fields,
      title: "Teleprompter Configuration Schema",
      description: "Teleprompter optimization configuration"
    )
  end

  @doc """
  BEACON configuration schema using ElixirML.
  """
  @spec beacon_configuration_schema() :: map()
  def beacon_configuration_schema do
    fields = [
      {:default_instruction_model, :string, required: true, min_length: 1},
      {:default_evaluation_model, :string, required: true, min_length: 1},
      {:max_concurrent_operations, :integer, required: true, gteq: 1, lteq: 50},
      {:default_timeout, :integer, required: true, gteq: 1000, lteq: 600_000}
    ]

    Runtime.create_schema(fields,
      title: "BEACON Configuration Schema",
      description: "BEACON teleprompter configuration with optimization settings"
    )
  end

  @doc """
  Logging configuration schema using ElixirML.
  """
  @spec logging_configuration_schema() :: map()
  def logging_configuration_schema do
    fields = [
      {:level, :atom,
       required: true,
       choices: [
         :debug,
         :info,
         :warn,
         :error,
         :warning,
         :critical,
         :emergency,
         :alert,
         :notice
       ]},
      {:correlation_enabled, :boolean, required: true}
    ]

    Runtime.create_schema(fields,
      title: "Logging Configuration Schema",
      description: "Logging configuration with level and correlation settings"
    )
  end

  @doc """
  Telemetry configuration schema using ElixirML.
  """
  @spec telemetry_configuration_schema() :: map()
  def telemetry_configuration_schema do
    fields = [
      {:enabled, :boolean, required: true},
      {:detailed_logging, :boolean, required: true},
      {:performance_tracking, :boolean, required: true}
    ]

    Runtime.create_schema(fields,
      title: "Telemetry Configuration Schema",
      description: "Telemetry and monitoring configuration"
    )
  end

  @doc """
  Rate limit nested schema.
  """
  @spec rate_limit_schema() :: map()
  def rate_limit_schema do
    fields = [
      {:requests_per_minute, :integer, required: true, gteq: 1, lteq: 10_000},
      {:tokens_per_minute, :integer, required: true, gteq: 1, lteq: 1_000_000}
    ]

    Runtime.create_schema(fields,
      title: "Rate Limit Schema",
      description: "API rate limiting configuration"
    )
  end

  @doc """
  Circuit breaker nested schema.
  """
  @spec circuit_breaker_schema() :: map()
  def circuit_breaker_schema do
    fields = [
      {:failure_threshold, :integer, required: true, gteq: 1, lteq: 100},
      {:recovery_time, :integer, required: true, gteq: 1000, lteq: 600_000}
    ]

    Runtime.create_schema(fields,
      title: "Circuit Breaker Schema",
      description: "Circuit breaker configuration for fault tolerance"
    )
  end

  @doc """
  Optimization nested schema.
  """
  @spec optimization_schema() :: map()
  def optimization_schema do
    fields = [
      {:max_trials, :integer, required: true, gteq: 1, lteq: 1000},
      {:convergence_patience, :integer, required: true, gteq: 1, lteq: 100},
      # Use float with probability-like constraints for improvement threshold
      {:improvement_threshold, :float, required: true, gteq: 0.0, lteq: 1.0}
    ]

    Runtime.create_schema(fields,
      title: "Optimization Schema",
      description: "Optimization algorithm configuration"
    )
  end

  @doc """
  Bayesian optimization nested schema.
  """
  @spec bayesian_optimization_schema() :: map()
  def bayesian_optimization_schema do
    fields = [
      {:acquisition_function, :atom,
       required: true,
       choices: [
         :expected_improvement,
         :probability_of_improvement,
         :upper_confidence_bound
       ]},
      {:surrogate_model, :atom,
       required: true, choices: [:gaussian_process, :random_forest, :extra_trees]},
      # Use float with probability-like constraints for exploration/exploitation tradeoff
      {:exploration_exploitation_tradeoff, :float, required: true, gteq: 0.0, lteq: 1.0}
    ]

    Runtime.create_schema(fields,
      title: "Bayesian Optimization Schema",
      description: "Bayesian optimization configuration for hyperparameter tuning"
    )
  end

  ## Private helper functions

  defp get_domain_schema(:client), do: client_configuration_schema()
  defp get_domain_schema(:provider), do: provider_configuration_schema()
  defp get_domain_schema(:prediction), do: prediction_configuration_schema()
  defp get_domain_schema(:evaluation), do: evaluation_configuration_schema()
  defp get_domain_schema(:teleprompter), do: teleprompter_configuration_schema()
  defp get_domain_schema(:beacon), do: beacon_configuration_schema()
  defp get_domain_schema(:logging), do: logging_configuration_schema()
  defp get_domain_schema(:telemetry), do: telemetry_configuration_schema()
  defp get_domain_schema(_), do: nil

  # ElixirML-based field validation
  @spec validate_field_with_elixir_ml(map(), list(atom()), term()) :: :ok | {:error, term()}
  defp validate_field_with_elixir_ml(schema, field_path, value) do
    # Reject nil values explicitly (even for optional fields)
    if is_nil(value) do
      field_name = List.last(field_path)
      error_atom = field_to_error_atom(field_name)
      {:error, {error_atom, "Value cannot be nil"}}
    else
      validate_field_value_with_elixir_ml(schema, field_path, value)
    end
  rescue
    error ->
      field_name = List.last(field_path)
      error_atom = field_to_error_atom(field_name)
      {:error, {error_atom, "Validation failed: #{inspect(error)}"}}
  end

  # Extract the validation logic to reduce nesting
  defp validate_field_value_with_elixir_ml(schema, field_path, value) do
    field_name = List.last(field_path)

    case extract_field_type_from_schema(schema, field_name) do
      {:ok, field_def} ->
        # Create a single-field schema for validation
        single_field_schema = create_single_field_schema(field_name, field_def)
        field_data = %{field_name => value}

        case Runtime.validate(single_field_schema, field_data) do
          {:ok, _validated} ->
            :ok
            # Note: Runtime.validate always returns {:ok, map()} according to Dialyzer
            # Keeping this for future compatibility if the library changes
        end

      {:error, :field_not_found} ->
        error_atom = field_to_error_atom(field_name)
        {:error, {error_atom, "Field not found in schema"}}
    end
  end

  # Create a single-field schema for validation
  defp create_single_field_schema(field_name, field_def) do
    # Create a schema with just this one field
    # field_def is a map with type and constraints keys
    field_type = field_def.type
    constraints = Map.to_list(field_def.constraints)

    fields = [{field_name, field_type, constraints}]

    Runtime.create_schema(fields,
      title: "Single Field Validation",
      description: "Validation schema for individual field"
    )
  end

  # Extract field type and constraints from schema for validation
  @spec extract_field_type_from_schema(map(), atom()) ::
          {:ok, map()} | {:error, :field_not_found}
  defp extract_field_type_from_schema(schema, field_name) do
    case Map.get(schema.fields, field_name) do
      nil ->
        {:error, :field_not_found}

      field_def ->
        # Return the full field definition
        {:ok, field_def}
    end
  end

  # Note: format_elixir_ml_error functions removed as they were unused
  # due to Runtime.validate always returning {:ok, map()}

  # Map field names to legacy error atoms (maintaining compatibility)
  @spec field_to_error_atom(atom()) :: atom()
  defp field_to_error_atom(:timeout), do: :invalid_timeout
  defp field_to_error_atom(:retry_attempts), do: :invalid_retry_attempts
  defp field_to_error_atom(:backoff_factor), do: :invalid_backoff_factor
  defp field_to_error_atom(:api_key), do: :invalid_api_key
  defp field_to_error_atom(:base_url), do: :invalid_base_url
  defp field_to_error_atom(:default_model), do: :invalid_model
  defp field_to_error_atom(:default_provider), do: :invalid_provider
  defp field_to_error_atom(:default_temperature), do: :invalid_temperature
  defp field_to_error_atom(:default_max_tokens), do: :invalid_max_tokens
  defp field_to_error_atom(:cache_enabled), do: :invalid_boolean
  defp field_to_error_atom(:cache_ttl), do: :invalid_cache_ttl
  defp field_to_error_atom(:batch_size), do: :invalid_batch_size
  defp field_to_error_atom(:parallel_limit), do: :invalid_parallel_limit
  defp field_to_error_atom(:bootstrap_examples), do: :invalid_bootstrap_examples
  defp field_to_error_atom(:validation_threshold), do: :invalid_validation_threshold
  defp field_to_error_atom(:level), do: :invalid_log_level
  defp field_to_error_atom(:correlation_enabled), do: :invalid_boolean
  defp field_to_error_atom(:enabled), do: :invalid_boolean
  defp field_to_error_atom(:detailed_logging), do: :invalid_detailed_logging
  defp field_to_error_atom(:performance_tracking), do: :invalid_performance_tracking
  defp field_to_error_atom(:requests_per_minute), do: :invalid_rate_limit
  defp field_to_error_atom(:tokens_per_minute), do: :invalid_token_limit
  defp field_to_error_atom(:failure_threshold), do: :invalid_failure_threshold
  defp field_to_error_atom(:recovery_time), do: :invalid_recovery_time
  defp field_to_error_atom(field), do: :"invalid_#{field}"
end

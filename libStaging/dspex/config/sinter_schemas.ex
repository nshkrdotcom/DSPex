defmodule DSPEx.Config.SinterSchemas do
  @moduledoc """
  Sinter schema definitions for DSPEx configuration validation.

  This module provides schema-based validation for DSPEx configuration
  with enhanced error reporting and path-based validation mapping using Sinter.

  Key improvements over Elixact:
  - No dynamic module compilation
  - Better performance through data structures
  - Enhanced error context for configuration issues
  """

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
  Validates a configuration value using Sinter schema-based validation.
  """
  @spec validate_config_value(list(atom()), term()) :: :ok | {:error, term()}
  def validate_config_value(path, value) do
    case path_to_schema(path) do
      {:ok, schema, field_path} ->
        validate_field_with_sinter(schema, field_path, value)

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
  Exports JSON schema for documentation using Sinter.
  """
  @spec export_json_schema(atom()) :: {:ok, map()} | {:error, term()}
  def export_json_schema(domain) do
    case get_domain_schema(domain) do
      nil -> {:error, {:unknown_domain, domain}}
      schema -> {:ok, Sinter.JsonSchema.generate(schema)}
    end
  end

  ## Schema Definitions

  @doc """
  Client configuration schema using Sinter.
  """
  @spec client_configuration_schema() :: map()
  def client_configuration_schema do
    Sinter.Schema.define(
      [
        {:timeout, :integer, [required: true, gteq: 1, lteq: 300_000]},
        {:retry_attempts, :integer, [required: true, gteq: 0, lteq: 10]},
        {:backoff_factor, :float, [required: true, gteq: 1.0, lteq: 10.0]}
      ],
      title: "Client Configuration Schema"
    )
  end

  @doc """
  Provider configuration schema using Sinter.
  """
  @spec provider_configuration_schema() :: map()
  def provider_configuration_schema do
    Sinter.Schema.define(
      [
        {:api_key, {:union, [:string, {:tuple, [:atom, :string]}]}, [required: true]},
        {:base_url, :string, [required: true, format: ~r/^https?:\/\/.+/]},
        {:default_model, :string, [required: true, min_length: 1]},
        {:timeout, :integer, [required: true, gteq: 1, lteq: 300_000]},
        {:rate_limit, :map, [required: true]},
        {:circuit_breaker, :map, [required: true]}
      ],
      title: "Provider Configuration Schema"
    )
  end

  @doc """
  Prediction configuration schema using Sinter.
  """
  @spec prediction_configuration_schema() :: map()
  def prediction_configuration_schema do
    Sinter.Schema.define(
      [
        {:default_provider, :atom, [required: true, choices: [:openai, :anthropic, :gemini]]},
        {:default_temperature, :float, [required: true, gteq: 0.0, lteq: 2.0]},
        {:default_max_tokens, :integer, [required: true, gteq: 1, lteq: 32_000]},
        {:cache_enabled, :boolean, [required: true]},
        {:cache_ttl, :integer, [required: true, gteq: 0, lteq: 86_400]}
      ],
      title: "Prediction Configuration Schema"
    )
  end

  @doc """
  Evaluation configuration schema using Sinter.
  """
  @spec evaluation_configuration_schema() :: map()
  def evaluation_configuration_schema do
    Sinter.Schema.define(
      [
        {:batch_size, :integer, [required: true, gteq: 1, lteq: 1000]},
        {:parallel_limit, :integer, [required: true, gteq: 1, lteq: 100]}
      ],
      title: "Evaluation Configuration Schema"
    )
  end

  @doc """
  Teleprompter configuration schema using Sinter.
  """
  @spec teleprompter_configuration_schema() :: map()
  def teleprompter_configuration_schema do
    Sinter.Schema.define(
      [
        {:bootstrap_examples, :integer, [required: true, gteq: 1, lteq: 100]},
        {:validation_threshold, :float, [required: true, gteq: 0.0, lteq: 1.0]}
      ],
      title: "Teleprompter Configuration Schema"
    )
  end

  @doc """
  BEACON configuration schema using Sinter.
  """
  @spec beacon_configuration_schema() :: map()
  def beacon_configuration_schema do
    Sinter.Schema.define(
      [
        {:default_instruction_model, :string, [required: true, min_length: 1]},
        {:default_evaluation_model, :string, [required: true, min_length: 1]},
        {:max_concurrent_operations, :integer, [required: true, gteq: 1, lteq: 50]},
        {:default_timeout, :integer, [required: true, gteq: 1000, lteq: 600_000]},
        {:optimization, :map, [required: true]},
        {:bayesian_optimization, :map, [required: true]}
      ],
      title: "BEACON Configuration Schema"
    )
  end

  @doc """
  Logging configuration schema using Sinter.
  """
  @spec logging_configuration_schema() :: map()
  def logging_configuration_schema do
    Sinter.Schema.define(
      [
        {:level, :atom,
         [
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
           ]
         ]},
        {:correlation_enabled, :boolean, [required: true]}
      ],
      title: "Logging Configuration Schema"
    )
  end

  @doc """
  Telemetry configuration schema using Sinter.
  """
  @spec telemetry_configuration_schema() :: map()
  def telemetry_configuration_schema do
    Sinter.Schema.define(
      [
        {:enabled, :boolean, [required: true]},
        {:detailed_logging, :boolean, [required: true]},
        {:performance_tracking, :boolean, [required: true]}
      ],
      title: "Telemetry Configuration Schema"
    )
  end

  @doc """
  Rate limit nested schema.
  """
  @spec rate_limit_schema() :: map()
  def rate_limit_schema do
    Sinter.Schema.define(
      [
        {:requests_per_minute, :integer, [required: true, gteq: 1, lteq: 10_000]},
        {:tokens_per_minute, :integer, [required: true, gteq: 1, lteq: 1_000_000]}
      ],
      title: "Rate Limit Schema"
    )
  end

  @doc """
  Circuit breaker nested schema.
  """
  @spec circuit_breaker_schema() :: map()
  def circuit_breaker_schema do
    Sinter.Schema.define(
      [
        {:failure_threshold, :integer, [required: true, gteq: 1, lteq: 100]},
        {:recovery_time, :integer, [required: true, gteq: 1000, lteq: 600_000]}
      ],
      title: "Circuit Breaker Schema"
    )
  end

  @doc """
  Optimization nested schema.
  """
  @spec optimization_schema() :: map()
  def optimization_schema do
    Sinter.Schema.define(
      [
        {:max_trials, :integer, [required: true, gteq: 1, lteq: 1000]},
        {:convergence_patience, :integer, [required: true, gteq: 1, lteq: 100]},
        {:improvement_threshold, :float, [required: true, gteq: 0.0, lteq: 1.0]}
      ],
      title: "Optimization Schema"
    )
  end

  @doc """
  Bayesian optimization nested schema.
  """
  @spec bayesian_optimization_schema() :: map()
  def bayesian_optimization_schema do
    Sinter.Schema.define(
      [
        {:acquisition_function, {:union, [:string, :atom]},
         [
           required: true,
           choices: [
             "ei",
             "ucb",
             "pi",
             :expected_improvement,
             :probability_of_improvement,
             :upper_confidence_bound
           ]
         ]},
        {:surrogate_model, {:union, [:string, :atom]},
         [
           required: true,
           choices: ["gp", "rf", "et", :gaussian_process, :random_forest, :extra_trees]
         ]},
        {:exploration_exploitation_tradeoff, :float, [required: true, gteq: 0.0, lteq: 1.0]}
      ],
      title: "Bayesian Optimization Schema"
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

  # Sinter-based field validation
  @spec validate_field_with_sinter(map(), list(atom()), term()) :: :ok | {:error, term()}
  defp validate_field_with_sinter(schema, field_path, value) do
    # Reject nil values explicitly (even for optional fields)
    if is_nil(value) do
      field_name = List.last(field_path)
      error_atom = field_to_error_atom(field_name)
      {:error, {error_atom, "Value cannot be nil"}}
    else
      validate_field_value_with_sinter(schema, field_path, value)
    end
  rescue
    error ->
      field_name = List.last(field_path)
      error_atom = field_to_error_atom(field_name)
      {:error, {error_atom, "Validation failed: #{inspect(error)}"}}
  end

  # Extract the validation logic to reduce nesting
  defp validate_field_value_with_sinter(schema, field_path, value) do
    field_name = List.last(field_path)

    case extract_field_type_from_schema(schema, field_name) do
      {:ok, field_type, constraints} ->
        # Use Sinter's validate_type function for single field validation
        case Sinter.validate_type(field_type, value, constraints) do
          {:ok, _validated} -> :ok
          {:error, errors} -> {:error, format_sinter_error(errors, field_path)}
        end

      {:error, :field_not_found} ->
        error_atom = field_to_error_atom(field_name)
        {:error, {error_atom, "Field not found in schema"}}
    end
  end

  # Extract field type and constraints from schema for validation
  @spec extract_field_type_from_schema(map(), atom()) ::
          {:ok, term(), keyword()} | {:error, :field_not_found}
  defp extract_field_type_from_schema(schema, field_name) do
    case Map.get(schema.fields, field_name) do
      nil ->
        {:error, :field_not_found}

      field_def ->
        # Pass the field constraints directly
        {:ok, field_def.type, field_def.constraints}
    end
  end

  # Format Sinter errors to match legacy error format
  @spec format_sinter_error([map()] | map(), list(atom())) :: term()
  defp format_sinter_error([error | _], field_path), do: format_sinter_error(error, field_path)

  defp format_sinter_error(%Sinter.Error{path: path, message: message}, field_path) do
    # Use the provided field_path if Sinter path is empty or unclear
    field =
      case path do
        [field_atom] when is_atom(field_atom) ->
          field_atom

        [field_atom | _] when is_atom(field_atom) ->
          field_atom

        _ ->
          # Fall back to using the field_path we passed in
          List.last(field_path)
      end

    error_atom = field_to_error_atom(field)
    {error_atom, message}
  end

  defp format_sinter_error(%{field: field, message: message}, _field_path) do
    error_atom = field_to_error_atom(field)
    {error_atom, message}
  end

  defp format_sinter_error(_error, field_path) do
    field_name = List.last(field_path)
    error_atom = field_to_error_atom(field_name)
    {error_atom, "Configuration validation failed"}
  end

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

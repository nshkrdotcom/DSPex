defmodule DSPEx.Signature.SchemaIntegration do
  @moduledoc """
  Integration layer between DSPEx Signatures and ElixirML Schema Engine.

  This module provides seamless integration between DSPEx signature definitions
  and the ElixirML Schema Engine, enabling ML-specific type validation,
  automatic variable extraction, and comprehensive validation pipelines.

  ## Features

  - **ML-Native Validation**: Integrates ElixirML's ML-specific types (embedding, probability, etc.)
  - **Automatic Variable Extraction**: Generates variables from signature field types
  - **Schema Generation**: Creates ElixirML schemas from signature field definitions
  - **Validation Pipeline**: Provides comprehensive field validation with detailed errors

  ## Usage

  This module is used internally by DSPEx.Signature when using the schema DSL:

      defmodule QASignature do
        use DSPEx.Signature, :schema_dsl

        input :question, :string
        input :context, :embedding, dimensions: 1536
        output :answer, :string
        output :confidence, :confidence_score
      end

      # Automatic schema validation
      {:ok, validated} = QASignature.validate_inputs_with_schema(%{
        question: "What is 2+2?",
        context: [0.1, 0.2, 0.3] # ... 1536 dimensions
      })
  """

  alias ElixirML.Variable

  @doc """
  Creates an ElixirML schema from signature field definitions.

  ## Parameters
  - `signature_module` - The signature module
  - `enhanced_fields` - List of enhanced field definitions

  ## Returns
  - Schema module atom for validation
  """
  @spec create_schema(module(), [map()]) :: module()
  def create_schema(signature_module, enhanced_fields) do
    # Generate unique schema module name
    schema_module_name = :"#{signature_module}.GeneratedSchema"

    # Create schema fields from enhanced field definitions
    schema_fields =
      Enum.map(enhanced_fields, fn field ->
        {field.name, map_to_schema_type(field.type), build_schema_options(field)}
      end)

    # Generate schema module at compile time
    schema_ast =
      quote do
        defmodule unquote(schema_module_name) do
          use ElixirML.Schema

          defschema ValidatedSignature do
            (unquote_splicing(
               Enum.map(schema_fields, fn {name, type, opts} ->
                 quote do
                   field(unquote(name), unquote(type), unquote(opts))
                 end
               end)
             ))
          end
        end
      end

    # Store the schema definition for runtime access
    Process.put({:signature_schema, signature_module}, {schema_module_name, schema_ast})

    schema_module_name
  end

  @doc """
  Validates field values using the generated ElixirML schema.

  ## Parameters
  - `signature_module` - The signature module
  - `data` - Map of field values to validate
  - `field_type` - Either `:input` or `:output` to validate specific field subset

  ## Returns
  - `{:ok, validated_data}` if validation passes
  - `{:error, validation_errors}` if validation fails
  """
  @spec validate_fields(module(), map(), :input | :output) :: {:ok, map()} | {:error, term()}
  def validate_fields(signature_module, data, field_type) do
    try do
      # Get enhanced field definitions
      enhanced_fields = signature_module.__enhanced_fields__()

      # Filter fields by type
      relevant_fields =
        case field_type do
          :input ->
            input_names = signature_module.input_fields()
            Enum.filter(enhanced_fields, fn field -> field.name in input_names end)

          :output ->
            output_names = signature_module.output_fields()
            Enum.filter(enhanced_fields, fn field -> field.name in output_names end)
        end

      # Extract field names and validate presence
      field_names = Enum.map(relevant_fields, & &1.name)
      field_data = Map.take(data, field_names)

      # Validate each field individually using ElixirML types
      validated_fields =
        Enum.reduce_while(relevant_fields, {:ok, %{}}, fn field, {:ok, acc} ->
          case validate_single_field(field, Map.get(field_data, field.name)) do
            {:ok, validated_value} ->
              {:cont, {:ok, Map.put(acc, field.name, validated_value)}}

            {:error, reason} ->
              {:halt, {:error, {field.name, reason}}}
          end
        end)

      validated_fields
    rescue
      error -> {:error, {:validation_failed, error}}
    end
  end

  @doc """
  Extracts optimization variables from signature field definitions.

  ## Parameters
  - `signature_module` - The signature module

  ## Returns
  - Variable space containing extractable variables
  """
  @spec extract_variables(module()) :: Variable.Space.t()
  def extract_variables(signature_module) do
    try do
      enhanced_fields = signature_module.__enhanced_fields__()

      # Start with empty variable space
      variable_space = Variable.Space.new()

      # Extract variables from field types and constraints
      Enum.reduce(enhanced_fields, variable_space, fn field, space ->
        field_variables = extract_variables_from_field(field)

        Enum.reduce(field_variables, space, fn variable, acc_space ->
          Variable.Space.add_variable(acc_space, variable)
        end)
      end)
    rescue
      _error -> Variable.Space.new()
    end
  end

  # Private implementation

  @spec validate_single_field(map(), term()) :: {:ok, term()} | {:error, term()}
  defp validate_single_field(field, value) do
    # Handle required field validation
    if field.required and (value == nil or value == "") do
      {:error, :required_field_missing}
    else
      # Skip validation if field is not required and value is nil/empty
      if not field.required and (value == nil or value == "") do
        {:ok, value}
      else
        # Use ElixirML Schema types for validation
        case field.type do
          :embedding -> validate_embedding(value, field.constraints)
          :probability -> validate_probability(value)
          :confidence_score -> validate_confidence_score(value)
          :token_list -> validate_token_list(value)
          :tensor -> validate_tensor(value)
          :model_response -> validate_model_response(value)
          :reasoning_chain -> validate_reasoning_chain(value)
          _ -> validate_basic_type(value, field.type)
        end
      end
    end
  end

  @spec validate_embedding(term(), map()) :: {:ok, term()} | {:error, term()}
  defp validate_embedding(value, constraints) when is_list(value) do
    cond do
      not Enum.all?(value, &is_number/1) ->
        {:error, :invalid_embedding_values}

      Map.has_key?(constraints, :dimensions) and length(value) != constraints.dimensions ->
        {:error,
         {:invalid_embedding_dimensions, expected: constraints.dimensions, got: length(value)}}

      true ->
        {:ok, value}
    end
  end

  defp validate_embedding(_, _), do: {:error, :invalid_embedding_format}

  @spec validate_probability(term()) :: {:ok, term()} | {:error, term()}
  defp validate_probability(value) when is_number(value) and value >= 0.0 and value <= 1.0 do
    {:ok, value}
  end

  defp validate_probability(_), do: {:error, :invalid_probability}

  @spec validate_confidence_score(term()) :: {:ok, term()} | {:error, term()}
  defp validate_confidence_score(value) when is_number(value) and value >= 0.0 do
    {:ok, value}
  end

  defp validate_confidence_score(_), do: {:error, :invalid_confidence_score}

  @spec validate_token_list(term()) :: {:ok, term()} | {:error, term()}
  defp validate_token_list(value) when is_list(value) do
    if Enum.all?(value, fn item -> is_binary(item) or is_integer(item) end) do
      {:ok, value}
    else
      {:error, :invalid_token_list}
    end
  end

  defp validate_token_list(_), do: {:error, :invalid_token_list_format}

  @spec validate_tensor(term()) :: {:ok, term()} | {:error, term()}
  defp validate_tensor(value) when is_list(value) do
    # Simplified validation - could be enhanced
    {:ok, value}
  end

  defp validate_tensor(_), do: {:error, :invalid_tensor}

  @spec validate_model_response(term()) :: {:ok, term()} | {:error, term()}
  defp validate_model_response(value) when is_map(value) do
    {:ok, value}
  end

  defp validate_model_response(_), do: {:error, :invalid_model_response}

  @spec validate_reasoning_chain(term()) :: {:ok, term()} | {:error, term()}
  defp validate_reasoning_chain(value) when is_list(value) do
    {:ok, value}
  end

  defp validate_reasoning_chain(_), do: {:error, :invalid_reasoning_chain}

  @spec validate_basic_type(term(), atom()) :: {:ok, term()} | {:error, term()}
  defp validate_basic_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_basic_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_basic_type(value, :float) when is_float(value), do: {:ok, value}
  defp validate_basic_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_basic_type(value, :any), do: {:ok, value}
  defp validate_basic_type(_, type), do: {:error, {:invalid_type, type}}

  @spec map_to_schema_type(atom()) :: atom()
  defp map_to_schema_type(:embedding), do: :embedding
  defp map_to_schema_type(:probability), do: :probability
  defp map_to_schema_type(:confidence_score), do: :confidence_score
  defp map_to_schema_type(:token_list), do: :token_list
  defp map_to_schema_type(:tensor), do: :tensor
  defp map_to_schema_type(:model_response), do: :model_response
  defp map_to_schema_type(:reasoning_chain), do: :reasoning_chain
  # Pass through basic types
  defp map_to_schema_type(type), do: type

  @spec build_schema_options(map()) :: keyword()
  defp build_schema_options(field) do
    options = []
    options = if field.required, do: Keyword.put(options, :required, true), else: options
    options = if field.default, do: Keyword.put(options, :default, field.default), else: options

    # Add constraints as schema options
    Enum.reduce(field.constraints, options, fn {key, value}, acc ->
      Keyword.put(acc, key, value)
    end)
  end

  @spec extract_variables_from_field(map()) :: [Variable.t()]
  defp extract_variables_from_field(field) do
    variables = []

    # Extract variables based on field type
    type_variables =
      case field.type do
        :probability ->
          [
            Variable.float(:"#{field.name}_threshold",
              range: {0.0, 1.0},
              default: 0.5,
              description: "Threshold for #{field.name} probability"
            )
          ]

        :confidence_score ->
          [
            Variable.float(:"#{field.name}_min_confidence",
              range: {0.0, 1.0},
              default: 0.8,
              description: "Minimum confidence for #{field.name}"
            )
          ]

        :embedding ->
          dims = Map.get(field.constraints, :dimensions, 1536)

          [
            Variable.integer(:"#{field.name}_dimensions",
              range: {128, 4096},
              default: dims,
              description: "Embedding dimensions for #{field.name}"
            )
          ]

        _ ->
          []
      end

    # Extract variables from constraints
    constraint_variables =
      Enum.flat_map(field.constraints, fn {constraint, value} ->
        case constraint do
          :max_length when is_integer(value) ->
            [
              Variable.integer(:"#{field.name}_max_length",
                range: {div(value, 2), value * 2},
                default: value,
                description: "Maximum length for #{field.name}"
              )
            ]

          :max_tokens when is_integer(value) ->
            [
              Variable.integer(:"#{field.name}_max_tokens",
                range: {div(value, 2), value * 2},
                default: value,
                description: "Maximum tokens for #{field.name}"
              )
            ]

          _ ->
            []
        end
      end)

    variables ++ type_variables ++ constraint_variables
  end
end

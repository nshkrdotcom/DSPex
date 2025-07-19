defmodule DSPEx.Sinter do
  @moduledoc """
  Enhanced Sinter integration for DSPEx - Phase 1 Sinter Migration

  This module provides native Sinter functionality,
  enabling bidirectional conversion between DSPEx signatures and Sinter schemas.

  Key features:
  - No dynamic module compilation overhead
  - Purpose-built DSPEx integration
  - Enhanced error handling with LLM context
  - Provider-specific JSON Schema optimizations
  """

  alias DSPEx.Signature.Sinter, as: SignatureSinter

  @doc """
  Converts a Sinter schema definition to a DSPEx signature.

  This enables importing schemas from other systems into DSPEx.
  """
  @spec schema_to_signature(map()) :: module()
  def schema_to_signature(schema_definition) do
    # Extract fields and metadata from Sinter schema format
    fields = Map.get(schema_definition, :fields, %{})
    meta = Map.get(schema_definition, :__meta__, %{})

    # Determine input vs output fields (simple heuristic for now)
    # In a real implementation, this would be more sophisticated
    field_names = Map.keys(fields)
    {input_fields, output_fields} = split_fields_by_convention(field_names)

    # Create signature string
    signature_string = build_signature_string(input_fields, output_fields, fields)

    # Create a dynamic signature module
    create_dynamic_signature_module(signature_string, fields, meta)
  end

  @doc """
  Generates JSON Schema from DSPEx signature via Sinter.

  Leverages Sinter's superior JSON Schema generation capabilities with provider optimizations.
  """
  @spec generate_json_schema(module(), keyword()) :: map()
  def generate_json_schema(signature_module, opts \\ []) do
    # Use the Sinter signature integration which supports provider optimizations
    SignatureSinter.generate_json_schema(signature_module, opts)
  rescue
    _error ->
      # Fallback to basic JSON schema (outputs only)
      generate_basic_json_schema_outputs_only(signature_module)
  end

  @doc """
  Maps DSPEx constraints to Sinter constraint format.
  """
  @spec map_constraints_to_sinter(map()) :: keyword()
  def map_constraints_to_sinter(dspex_constraints) do
    Enum.reduce(dspex_constraints, [], fn {key, value}, acc ->
      case map_single_constraint(key, value) do
        {:ok, sinter_key, sinter_value} ->
          Keyword.put(acc, sinter_key, sinter_value)

        {:skip} ->
          acc
      end
    end)
  end

  @doc """
  Converts Sinter errors to DSPEx-compatible format.
  """
  @spec convert_errors_to_dspex([map()] | map()) :: [map()]
  def convert_errors_to_dspex(sinter_errors) when is_list(sinter_errors) do
    Enum.map(sinter_errors, &convert_single_error_to_dspex/1)
  end

  def convert_errors_to_dspex(sinter_error) do
    [convert_single_error_to_dspex(sinter_error)]
  end

  @doc """
  Creates a dynamic Sinter schema from DSPEx signature definition.

  This doesn't create runtime modules but uses Sinter's data structures.
  """
  @spec create_dynamic_schema(map(), String.t()) :: map()
  def create_dynamic_schema(signature_definition, schema_name) do
    input_fields = Map.get(signature_definition, :input_fields, [])
    output_fields = Map.get(signature_definition, :output_fields, [])
    field_types = Map.get(signature_definition, :field_types, %{})
    constraints = Map.get(signature_definition, :constraints, %{})

    all_fields = input_fields ++ output_fields

    # Build field definitions for Sinter
    sinter_fields =
      build_sinter_field_definitions(all_fields, field_types, constraints, input_fields)

    # Create Sinter schema (data structure, not module)
    Sinter.Schema.define(sinter_fields,
      title: schema_name,
      description: "Dynamic schema for #{schema_name}"
    )
  end

  @doc """
  Extracts schema information from a Sinter schema for DSPEx metadata.
  """
  @spec extract_schema_info(map()) :: map()
  def extract_schema_info(sinter_schema) do
    # Use Sinter's introspection capabilities
    json_schema = Sinter.JsonSchema.generate(sinter_schema)

    # Extract field information
    properties = Map.get(json_schema, "properties", %{})
    required = Map.get(json_schema, "required", [])

    fields = extract_fields_from_properties(properties)
    constraints = extract_constraints_from_properties(properties)
    descriptions = extract_descriptions_from_properties(properties)

    %{
      fields: fields,
      constraints: constraints,
      descriptions: descriptions,
      required: required
    }
  end

  # Private helper functions

  defp split_fields_by_convention(field_names) do
    # Simple heuristic: fields ending with common input words vs output words
    input_indicators = ["query", "question", "input", "request", "search", "term"]
    _output_indicators = ["answer", "response", "result", "output", "summary", "reply"]

    {inputs, outputs} =
      Enum.split_with(field_names, fn field ->
        field_str = Atom.to_string(field)
        Enum.any?(input_indicators, &String.contains?(field_str, &1))
      end)

    # If no clear split, assume first field is input, rest are outputs
    case {inputs, outputs} do
      {[], []} -> {[], []}
      {[], all} -> {[hd(all)], tl(all)}
      {inputs, []} -> {inputs, []}
      split -> split
    end
  end

  defp build_signature_string(input_fields, output_fields, _fields) do
    input_str = Enum.map_join(input_fields, ", ", &Atom.to_string/1)
    output_str = Enum.map_join(output_fields, ", ", &Atom.to_string/1)

    "#{input_str} -> #{output_str}"
  end

  defp create_dynamic_signature_module(signature_string, fields, meta) do
    # Generate unique module name
    module_name = :"DynamicSignature.#{System.unique_integer([:positive])}"
    title = Map.get(meta, :title, "Dynamic Signature")

    # Convert fields to enhanced fields format
    enhanced_fields =
      Enum.map(fields, fn {name, field_info} ->
        %{
          name: name,
          type: Map.get(field_info, :type, :string),
          description: Map.get(field_info, :description, ""),
          constraints: Map.get(field_info, :constraints, %{})
        }
      end)

    # Create module definition using DSPEx.Signature
    module_def =
      quote do
        defmodule unquote(module_name) do
          @moduledoc unquote(title)

          def __enhanced_fields__, do: unquote(Macro.escape(enhanced_fields))

          use DSPEx.Signature, unquote(signature_string)
        end
      end

    # Compile and return the module
    {_result, _binding} = Code.eval_quoted(module_def)
    module_name
  end

  defp build_sinter_field_definitions(all_fields, field_types, constraints, input_fields) do
    Enum.map(all_fields, fn field_name ->
      field_type = Map.get(field_types, field_name, :string)
      field_constraints = Map.get(constraints, field_name, %{})

      # Convert constraints to Sinter format
      sinter_constraints = map_constraints_to_sinter(field_constraints)

      # Add required/optional based on whether it's an input field
      sinter_constraints =
        if field_name in input_fields do
          Keyword.put(sinter_constraints, :required, true)
        else
          Keyword.put(sinter_constraints, :optional, true)
        end

      {field_name, field_type, sinter_constraints}
    end)
  end

  defp map_single_constraint(:min_length, value), do: {:ok, :min_length, value}
  defp map_single_constraint(:max_length, value), do: {:ok, :max_length, value}
  defp map_single_constraint(:min_items, value), do: {:ok, :min_items, value}
  defp map_single_constraint(:max_items, value), do: {:ok, :max_items, value}
  defp map_single_constraint(:gteq, value), do: {:ok, :gteq, value}
  defp map_single_constraint(:lteq, value), do: {:ok, :lteq, value}
  defp map_single_constraint(:gt, value), do: {:ok, :gt, value}
  defp map_single_constraint(:lt, value), do: {:ok, :lt, value}
  defp map_single_constraint(:format, value), do: {:ok, :format, value}
  defp map_single_constraint(:choices, value), do: {:ok, :choices, value}
  defp map_single_constraint(:required, value), do: {:ok, :required, value}
  defp map_single_constraint(:optional, value), do: {:ok, :optional, value}
  defp map_single_constraint(:default, value), do: {:ok, :default, value}
  defp map_single_constraint(_key, _value), do: {:skip}

  defp convert_single_error_to_dspex(%Sinter.Error{} = error) do
    %{
      path: error.path,
      code: error.code,
      message: error.message,
      context: error.context || %{},
      type: :sinter_validation_error
    }
  end

  defp convert_single_error_to_dspex(%{} = error) do
    # Already in map format, ensure consistent structure
    %{
      path: Map.get(error, :path),
      code: Map.get(error, :code),
      message: Map.get(error, :message, "Validation failed"),
      context: Map.get(error, :context, %{}),
      type: :sinter_validation_error
    }
  end

  defp convert_single_error_to_dspex(error) do
    %{
      path: [],
      code: :unknown,
      message: "Validation error: #{inspect(error)}",
      context: %{},
      type: :unknown_error
    }
  end

  defp generate_basic_json_schema_outputs_only(signature_module) do
    try do
      output_fields = signature_module.output_fields()

      properties =
        Enum.into(output_fields, %{}, fn field ->
          {Atom.to_string(field),
           %{
             "type" => "string",
             "description" => "Output field: #{field}"
           }}
        end)

      %{
        "type" => "object",
        "properties" => properties,
        "required" => Enum.map(output_fields, &Atom.to_string/1),
        "title" => "#{signature_module} Output Schema",
        "description" => "Basic JSON schema for #{signature_module} outputs"
      }
    rescue
      _ ->
        %{
          "type" => "object",
          "properties" => %{},
          "error" => "Failed to generate schema for #{signature_module}"
        }
    end
  end

  defp extract_fields_from_properties(properties) do
    Enum.into(properties, %{}, fn {field_name, field_schema} ->
      field_atom = String.to_atom(field_name)

      field_type =
        case Map.get(field_schema, "type") do
          "string" -> :string
          "integer" -> :integer
          "number" -> :float
          "boolean" -> :boolean
          "array" -> :array
          "object" -> :map
          _ -> :string
        end

      {field_atom, field_type}
    end)
  end

  defp extract_constraints_from_properties(properties) do
    Enum.into(properties, %{}, fn {field_name, field_schema} ->
      field_atom = String.to_atom(field_name)

      constraints =
        %{}
        |> maybe_add_constraint(:min_length, Map.get(field_schema, "minLength"))
        |> maybe_add_constraint(:max_length, Map.get(field_schema, "maxLength"))
        |> maybe_add_constraint(:gteq, Map.get(field_schema, "minimum"))
        |> maybe_add_constraint(:lteq, Map.get(field_schema, "maximum"))
        |> maybe_add_constraint(:min_items, Map.get(field_schema, "minItems"))
        |> maybe_add_constraint(:max_items, Map.get(field_schema, "maxItems"))

      {field_atom, constraints}
    end)
  end

  defp extract_descriptions_from_properties(properties) do
    Enum.into(properties, %{}, fn {field_name, field_schema} ->
      field_atom = String.to_atom(field_name)
      description = Map.get(field_schema, "description", "")
      {field_atom, description}
    end)
  end

  defp maybe_add_constraint(constraints, _key, nil), do: constraints
  defp maybe_add_constraint(constraints, key, value), do: Map.put(constraints, key, value)
end

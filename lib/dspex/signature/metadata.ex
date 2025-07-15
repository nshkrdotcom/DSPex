defmodule DSPex.Signature.Metadata do
  @moduledoc """
  Enhanced signature metadata support for dynamic signature generation.

  This module provides functionality to convert native Elixir DSPex signatures
  into rich metadata format that can be consumed by the Python bridge for
  dynamic signature class generation.

  ## Features

  - Convert compile-time signature definitions to runtime metadata
  - Support for field descriptions and type information
  - JSON-compatible format for Python bridge communication
  - Validation of metadata structure
  - Support for complex types and ML-specific types

  ## Usage

      defmodule MySignature do
        use DSPex.Signature
        
        signature question: :string -> answer: :string
      end

      # Generate enhanced metadata
      metadata = DSPex.Signature.Metadata.to_enhanced_metadata(MySignature)
      
      # Result:
      %{
        name: "MySignature",
        description: "A dynamically generated DSPy signature.",
        inputs: [
          %{name: "question", type: "string", description: "Input field: question"}
        ],
        outputs: [
          %{name: "answer", type: "string", description: "Output field: answer"}
        ]
      }
  """

  @type field_metadata :: %{
          name: String.t(),
          type: String.t(),
          description: String.t(),
          constraints: map()
        }

  @type enhanced_metadata :: %{
          name: String.t(),
          description: String.t(),
          inputs: [field_metadata()],
          outputs: [field_metadata()]
        }

  @doc """
  Converts a signature module to enhanced metadata format.

  Takes a module that uses DSPex.Signature and converts its compiled
  signature metadata into the rich format expected by the Python bridge.

  ## Parameters

  - `signature_module` - Module that implements DSPex.Signature behavior
  - `opts` - Optional configuration (description, type mappings, etc.)

  ## Examples

      metadata = DSPex.Signature.Metadata.to_enhanced_metadata(MySignature)
      
      # With custom description
      metadata = DSPex.Signature.Metadata.to_enhanced_metadata(
        MySignature, 
        description: "Custom signature for question answering"
      )

  ## Options

  - `:description` - Custom description for the signature
  - `:type_mapping` - Custom type mappings for special types
  - `:include_constraints` - Include type constraints in output (default: true)
  """
  @spec to_enhanced_metadata(module(), keyword()) :: enhanced_metadata()
  def to_enhanced_metadata(signature_module, opts \\ []) do
    signature_data = signature_module.__signature__()

    name = get_signature_name(signature_module, opts)
    description = get_signature_description(signature_module, opts)

    inputs = convert_fields_to_metadata(signature_data.inputs, :input, opts)
    outputs = convert_fields_to_metadata(signature_data.outputs, :output, opts)

    %{
      name: name,
      description: description,
      inputs: inputs,
      outputs: outputs
    }
  end

  @doc """
  Converts a direct signature definition to enhanced metadata.

  Takes a signature definition map (like those from examples) and ensures
  it has all required fields for enhanced metadata format.

  ## Examples

      signature_def = %{
        name: "CustomSignature",
        inputs: [%{name: "text", type: "string"}],
        outputs: [%{name: "result", type: "string"}]
      }
      
      metadata = DSPex.Signature.Metadata.normalize_signature_definition(signature_def)
  """
  @spec normalize_signature_definition(map()) :: enhanced_metadata()
  def normalize_signature_definition(signature_def) when is_map(signature_def) do
    name = Map.get(signature_def, :name) || Map.get(signature_def, "name") || "DynamicSignature"

    description =
      Map.get(signature_def, :description) || Map.get(signature_def, "description") ||
        "A dynamically generated DSPy signature."

    inputs =
      normalize_field_list(
        Map.get(signature_def, :inputs) || Map.get(signature_def, "inputs") || []
      )

    outputs =
      normalize_field_list(
        Map.get(signature_def, :outputs) || Map.get(signature_def, "outputs") || []
      )

    %{
      name: name,
      description: description,
      inputs: inputs,
      outputs: outputs
    }
  end

  @doc """
  Validates enhanced metadata structure.

  Ensures the metadata has all required fields and valid structure
  for Python bridge consumption. Uses the enhanced validator for
  comprehensive validation.

  ## Examples

      case DSPex.Signature.Metadata.validate_metadata(metadata) do
        :ok -> 
          # Metadata is valid
        {:error, errors} -> 
          # Handle validation errors
      end
  """
  @spec validate_metadata(enhanced_metadata()) :: :ok | {:error, term()}
  def validate_metadata(metadata) when is_map(metadata) do
    DSPex.Signature.EnhancedValidator.validate_enhanced_metadata(metadata)
  end

  def validate_metadata(_), do: {:error, "Metadata must be a map"}

  @doc """
  Converts Python bridge metadata back to DSPex signature format.

  Useful for round-trip conversions and testing.

  ## Examples

      dspex_format = DSPex.Signature.Metadata.from_enhanced_metadata(enhanced_metadata)
  """
  @spec from_enhanced_metadata(enhanced_metadata()) :: map()
  def from_enhanced_metadata(metadata) do
    inputs = convert_metadata_to_fields(metadata.inputs)
    outputs = convert_metadata_to_fields(metadata.outputs)

    %{
      inputs: inputs,
      outputs: outputs,
      module: String.to_atom("Elixir.#{metadata.name}")
    }
  end

  ## Private Functions

  defp get_signature_name(signature_module, opts) do
    case Keyword.get(opts, :name) do
      nil ->
        # Extract module name without Elixir prefix
        signature_module
        |> Module.split()
        |> List.last()

      custom_name ->
        to_string(custom_name)
    end
  end

  defp get_signature_description(signature_module, opts) do
    case Keyword.get(opts, :description) do
      nil ->
        # Try to get description from compiled signature metadata first
        try do
          signature_data = signature_module.__signature__()

          case Map.get(signature_data, :description) do
            desc when is_binary(desc) and desc != "" -> desc
            _ -> get_module_doc_description(signature_module)
          end
        rescue
          _ -> get_module_doc_description(signature_module)
        end

      custom_description ->
        to_string(custom_description)
    end
  end

  defp get_module_doc_description(signature_module) do
    # Try to get description from module docstring
    case Code.fetch_docs(signature_module) do
      {:docs_v1, _, _, _, %{"en" => module_doc}, _, _} when is_binary(module_doc) ->
        # Extract first line of module doc
        module_doc
        |> String.split("\n")
        |> List.first()
        |> String.trim()

      _ ->
        "A dynamically generated DSPy signature."
    end
  end

  defp convert_fields_to_metadata(fields, field_type, opts) do
    include_constraints = Keyword.get(opts, :include_constraints, true)
    type_mapping = Keyword.get(opts, :type_mapping, %{})

    Enum.map(fields, fn {field_name, field_type_def, constraints} ->
      %{
        name: to_string(field_name),
        type: convert_type_to_string(field_type_def, type_mapping),
        description: generate_field_description(field_name, field_type, field_type_def),
        constraints: if(include_constraints, do: normalize_constraints(constraints), else: %{})
      }
    end)
  end

  defp normalize_field_list(fields) when is_list(fields) do
    Enum.map(fields, &normalize_field_definition/1)
  end

  defp normalize_field_list(_), do: []

  defp normalize_field_definition(field) when is_map(field) do
    name = Map.get(field, :name) || Map.get(field, "name")
    type = Map.get(field, :type) || Map.get(field, "type") || "string"

    description =
      Map.get(field, :description) || Map.get(field, "description") ||
        "Field: #{name}"

    %{
      name: to_string(name),
      type: to_string(type),
      description: to_string(description)
    }
  end

  defp normalize_field_definition(_),
    do: %{name: "unknown", type: "string", description: "Unknown field"}

  defp convert_type_to_string(type, type_mapping) when is_atom(type) do
    case Map.get(type_mapping, type) do
      nil -> convert_basic_type(type)
      custom_type -> to_string(custom_type)
    end
  end

  defp convert_type_to_string({:list, inner_type}, type_mapping) do
    "list<#{convert_type_to_string(inner_type, type_mapping)}>"
  end

  defp convert_type_to_string({:dict, key_type, value_type}, type_mapping) do
    "dict<#{convert_type_to_string(key_type, type_mapping)},#{convert_type_to_string(value_type, type_mapping)}>"
  end

  defp convert_type_to_string({:union, types}, type_mapping) do
    type_strings = Enum.map(types, &convert_type_to_string(&1, type_mapping))
    "union<#{Enum.join(type_strings, "|")}>"
  end

  defp convert_type_to_string(type, _type_mapping) do
    to_string(type)
  end

  defp convert_basic_type(:string), do: "string"
  defp convert_basic_type(:integer), do: "integer"
  defp convert_basic_type(:float), do: "float"
  defp convert_basic_type(:boolean), do: "boolean"
  # Atoms become strings in Python
  defp convert_basic_type(:atom), do: "string"
  defp convert_basic_type(:map), do: "dict"
  defp convert_basic_type(:any), do: "any"

  # ML-specific types
  defp convert_basic_type(:embedding), do: "embedding"
  defp convert_basic_type(:probability), do: "float"
  defp convert_basic_type(:confidence_score), do: "float"
  defp convert_basic_type(:reasoning_chain), do: "list<string>"

  defp convert_basic_type(other), do: to_string(other)

  defp generate_field_description(field_name, :input, _field_type) do
    "Input field: #{field_name}"
  end

  defp generate_field_description(field_name, :output, _field_type) do
    "Output field: #{field_name}"
  end

  defp normalize_constraints(constraints) when is_list(constraints) do
    Enum.into(constraints, %{})
  end

  defp normalize_constraints(constraints) when is_map(constraints) do
    constraints
  end

  defp normalize_constraints(_), do: %{}

  defp convert_metadata_to_fields(field_metadata) do
    Enum.map(field_metadata, fn field ->
      field_name = String.to_atom(field.name)
      field_type = convert_string_to_type(field.type)
      constraints = Map.get(field, :constraints, [])

      {field_name, field_type, constraints}
    end)
  end

  defp convert_string_to_type("string"), do: :string
  defp convert_string_to_type("integer"), do: :integer
  defp convert_string_to_type("float"), do: :float
  defp convert_string_to_type("boolean"), do: :boolean
  defp convert_string_to_type("dict"), do: :map
  defp convert_string_to_type("any"), do: :any
  defp convert_string_to_type("embedding"), do: :embedding

  defp convert_string_to_type(type_string) when is_binary(type_string) do
    # Handle complex types
    cond do
      String.starts_with?(type_string, "list<") ->
        inner_type = extract_inner_type(type_string, "list<", ">")
        {:list, convert_string_to_type(inner_type)}

      String.starts_with?(type_string, "dict<") ->
        types = extract_dict_types(type_string)
        {:dict, convert_string_to_type(types.key), convert_string_to_type(types.value)}

      String.starts_with?(type_string, "union<") ->
        union_types = extract_union_types(type_string)
        {:union, Enum.map(union_types, &convert_string_to_type/1)}

      true ->
        String.to_atom(type_string)
    end
  end

  defp extract_inner_type(type_string, prefix, suffix) do
    type_string
    |> String.trim_leading(prefix)
    |> String.trim_trailing(suffix)
  end

  defp extract_dict_types(type_string) do
    inner = extract_inner_type(type_string, "dict<", ">")
    # Handle both ", " and "," as separators
    parts =
      case String.split(inner, ", ", parts: 2) do
        [key_type, value_type] -> [key_type, value_type]
        [single_part] -> String.split(single_part, ",", parts: 2)
      end

    case parts do
      [key_type, value_type] ->
        %{key: String.trim(key_type), value: String.trim(value_type)}

      _ ->
        # Fallback for malformed dict types
        %{key: "string", value: "any"}
    end
  end

  defp extract_union_types(type_string) do
    inner = extract_inner_type(type_string, "union<", ">")
    String.split(inner, "|")
  end
end

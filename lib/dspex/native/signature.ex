defmodule DSPex.Native.Signature do
  @moduledoc """
  Native Elixir implementation of DSPy signature parsing and validation.

  Signatures define the input/output schema for ML operations. This module
  provides high-performance parsing without requiring Python.

  ## Signature Syntax

      "input_field: type 'description' -> output_field: type 'description'"

  ## Examples

      # Simple
      "question -> answer"
      
      # With types
      "question: str, context: list[str] -> answer: str, confidence: float"
      
      # With descriptions
      "question: str 'The user query' -> answer: str 'Generated response'"
  """

  defstruct [:name, :docstring, :inputs, :outputs, :metadata]

  @type field_type ::
          :string
          | :str
          | :integer
          | :int
          | :float
          | :boolean
          | :bool
          | {:list, field_type()}
          | {:dict, field_type()}
          | {:optional, field_type()}

  @type field :: %{
          name: atom(),
          type: field_type(),
          description: String.t() | nil,
          constraints: map()
        }

  @type t :: %__MODULE__{
          name: String.t() | nil,
          docstring: String.t() | nil,
          inputs: [field()],
          outputs: [field()],
          metadata: map()
        }

  @doc """
  Parse a signature specification into a structured format.
  """
  @spec parse(String.t() | map()) :: {:ok, t()} | {:error, term()}
  def parse(spec) when is_binary(spec) do
    with {:ok, tokens} <- tokenize(spec),
         {:ok, ast} <- build_ast(tokens),
         {:ok, signature} <- transform_ast(ast) do
      {:ok, signature}
    end
  end

  def parse(spec) when is_map(spec) do
    # Support map-based definitions
    signature = %__MODULE__{
      name: spec[:name],
      docstring: spec[:docstring],
      inputs: parse_fields(spec[:inputs] || []),
      outputs: parse_fields(spec[:outputs] || []),
      metadata: spec[:metadata] || %{}
    }

    {:ok, signature}
  end

  def parse(_), do: {:error, "Invalid signature specification"}

  @doc """
  Compile a signature for repeated use with validation and serialization.
  """
  @spec compile(String.t()) :: {:ok, map()} | {:error, term()}
  def compile(spec) do
    with {:ok, signature} <- parse(spec) do
      compiled = %{
        signature: signature,
        validator: build_validator(signature),
        serializer: build_serializer(signature),
        compiled_at: DateTime.utc_now()
      }

      {:ok, compiled}
    end
  end

  # Tokenizer

  defp tokenize(spec) do
    # Remove extra whitespace
    spec = String.trim(spec)

    # Split on arrow
    case String.split(spec, "->", parts: 2) do
      [inputs, outputs] ->
        {:ok,
         %{
           inputs: tokenize_fields(String.trim(inputs)),
           outputs: tokenize_fields(String.trim(outputs))
         }}

      _ ->
        {:error, "Missing '->' separator in signature"}
    end
  end

  defp tokenize_fields(fields_str) do
    fields_str
    |> String.split(",")
    |> Enum.map(&parse_field/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_field(field_str) do
    field_str = String.trim(field_str)

    # Match: name: type 'description'
    case Regex.run(~r/^(\w+)(?:\s*:\s*([^']+?))?(?:\s*'([^']*)')?$/, field_str) do
      [_, name] ->
        %{name: String.to_atom(name), type: :string, description: nil}

      [_, name, type] ->
        %{
          name: String.to_atom(name),
          type: parse_type(String.trim(type)),
          description: nil
        }

      [_, name, type, desc] ->
        %{
          name: String.to_atom(name),
          type: parse_type(String.trim(type)),
          description: desc
        }

      _ ->
        nil
    end
  end

  defp parse_type(""), do: :string
  defp parse_type("str"), do: :string
  defp parse_type("string"), do: :string
  defp parse_type("int"), do: :integer
  defp parse_type("integer"), do: :integer
  defp parse_type("float"), do: :float
  defp parse_type("bool"), do: :boolean
  defp parse_type("boolean"), do: :boolean

  defp parse_type("list[" <> rest) do
    case String.trim_trailing(rest, "]") do
      inner_type -> {:list, parse_type(inner_type)}
    end
  end

  defp parse_type("dict[" <> rest) do
    case String.trim_trailing(rest, "]") do
      inner_type -> {:dict, parse_type(inner_type)}
    end
  end

  defp parse_type("optional[" <> rest) do
    case String.trim_trailing(rest, "]") do
      inner_type -> {:optional, parse_type(inner_type)}
    end
  end

  defp parse_type(_), do: :string

  # AST builder

  defp build_ast(tokens) do
    ast = %{
      inputs: tokens.inputs,
      outputs: tokens.outputs
    }

    {:ok, ast}
  end

  # AST transformer

  defp transform_ast(ast) do
    signature = %__MODULE__{
      inputs: ast.inputs,
      outputs: ast.outputs,
      metadata: %{
        parsed_at: DateTime.utc_now()
      }
    }

    {:ok, signature}
  end

  # Validator builder

  defp build_validator(signature) do
    fn data ->
      errors = []

      # Check required inputs
      errors = errors ++ validate_fields(data, signature.inputs, "input")

      {:ok, errors}
    end
  end

  defp validate_fields(data, fields, field_type) do
    Enum.flat_map(fields, fn field ->
      case validate_field(data, field) do
        :ok -> []
        {:error, msg} -> ["#{field_type} field '#{field.name}': #{msg}"]
      end
    end)
  end

  defp validate_field(data, field) do
    value = data[field.name] || data[to_string(field.name)]

    cond do
      is_nil(value) and not optional?(field.type) ->
        {:error, "is required"}

      not is_nil(value) and not valid_type?(value, field.type) ->
        {:error, "invalid type, expected #{inspect(field.type)}"}

      true ->
        :ok
    end
  end

  defp optional?({:optional, _}), do: true
  defp optional?(_), do: false

  defp valid_type?(value, :string) when is_binary(value), do: true
  defp valid_type?(value, :integer) when is_integer(value), do: true
  defp valid_type?(value, :float) when is_float(value) or is_integer(value), do: true
  defp valid_type?(value, :boolean) when is_boolean(value), do: true

  defp valid_type?(value, {:list, inner_type}) when is_list(value) do
    Enum.all?(value, &valid_type?(&1, inner_type))
  end

  defp valid_type?(value, {:dict, _}) when is_map(value), do: true
  defp valid_type?(value, {:optional, inner_type}), do: valid_type?(value, inner_type)
  defp valid_type?(_, _), do: false

  # Serializer builder

  defp build_serializer(signature) do
    fn data ->
      serialized = %{
        inputs: serialize_fields(data, signature.inputs),
        signature_hash: signature_hash(signature)
      }

      {:ok, serialized}
    end
  end

  defp serialize_fields(data, fields) do
    Map.new(fields, fn field ->
      value = data[field.name] || data[to_string(field.name)]
      {field.name, serialize_value(value, field.type)}
    end)
  end

  defp serialize_value(nil, {:optional, _}), do: nil
  defp serialize_value(value, {:optional, type}), do: serialize_value(value, type)

  defp serialize_value(value, {:list, type}) when is_list(value) do
    Enum.map(value, &serialize_value(&1, type))
  end

  defp serialize_value(value, _), do: value

  defp signature_hash(signature) do
    :crypto.hash(:sha256, inspect(signature))
    |> Base.encode16()
    |> String.slice(0..7)
  end

  # Helper for parsing fields from maps

  defp parse_fields(fields) when is_list(fields) do
    Enum.map(fields, &parse_field_map/1)
  end

  defp parse_field_map(field) when is_map(field) do
    %{
      name: field[:name] || field["name"],
      type: field[:type] || field["type"] || :string,
      description: field[:description] || field["description"],
      constraints: field[:constraints] || field["constraints"] || %{}
    }
  end
end

defmodule DSPex.Native.Validator do
  @moduledoc """
  Native validation of data against DSPy signatures.

  Provides fast validation without Python overhead.
  """

  alias DSPex.Native.Signature

  @doc """
  Validate data against a signature.

  Returns :ok if valid, or {:error, errors} with a list of validation errors.

  ## Examples

      iex> {:ok, sig} = DSPex.signature("name: str, age: int -> greeting: str")
      iex> DSPex.Native.Validator.validate(%{name: "Alice", age: 30}, sig)
      :ok
      
      iex> DSPex.Native.Validator.validate(%{name: "Alice"}, sig)
      {:error, ["input field 'age': is required"]}
  """
  @spec validate(map(), Signature.t()) :: :ok | {:error, list(String.t())}
  def validate(data, %Signature{} = signature) do
    errors = validate_fields(data, signature.inputs, "input")

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Validate output data against a signature.
  """
  @spec validate_output(map(), Signature.t()) :: :ok | {:error, list(String.t())}
  def validate_output(data, %Signature{} = signature) do
    errors = validate_fields(data, signature.outputs, "output")

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Private functions

  defp validate_fields(data, fields, field_type) do
    Enum.flat_map(fields, fn field ->
      case validate_field(data, field) do
        :ok -> []
        {:error, msg} -> ["#{field_type} field '#{field.name}': #{msg}"]
      end
    end)
  end

  defp validate_field(data, field) do
    value = get_field_value(data, field.name)

    cond do
      is_nil(value) and not optional?(field.type) ->
        {:error, "is required"}

      not is_nil(value) and not valid_type?(value, field.type) ->
        {:error, "invalid type, expected #{format_type(field.type)}, got #{inspect(value)}"}

      true ->
        :ok
    end
  end

  defp get_field_value(data, field_name) when is_map(data) do
    # Try both atom and string keys
    data[field_name] || data[to_string(field_name)]
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

  defp valid_type?(value, {:dict, _inner_type}) when is_map(value), do: true

  defp valid_type?(value, {:optional, inner_type}) do
    valid_type?(value, inner_type)
  end

  defp valid_type?(_value, _type), do: false

  defp format_type(:string), do: "string"
  defp format_type(:integer), do: "integer"
  defp format_type(:float), do: "float"
  defp format_type(:boolean), do: "boolean"
  defp format_type({:list, inner}), do: "list[#{format_type(inner)}]"
  defp format_type({:dict, inner}), do: "dict[str, #{format_type(inner)}]"
  defp format_type({:optional, inner}), do: "optional[#{format_type(inner)}]"
  defp format_type(type), do: inspect(type)
end

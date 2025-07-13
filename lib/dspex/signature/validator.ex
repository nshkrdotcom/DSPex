defmodule DSPex.Signature.Validator do
  @moduledoc """
  Runtime validation for signature inputs and outputs.

  This module provides comprehensive validation functionality for data against
  signature field definitions. It supports type checking, constraint validation,
  and data coercion where appropriate.

  ## Features

  - Type validation for all supported types (basic, ML-specific, composite)
  - Nested validation for composite types (lists, dicts, unions)
  - Descriptive error messages with field-level details
  - Optional data coercion for compatible types
  - Support for missing field detection
  - Constraint validation (future extensibility)

  ## Validation Process

  1. Check for missing required fields
  2. Validate each field's type
  3. Apply any constraints (currently minimal, extensible)
  4. Return validated/coerced data or detailed errors

  ## Usage

      fields = [{:question, :string, []}, {:context, {:list, :string}, []}]
      data = %{question: "What is 2+2?", context: ["math", "arithmetic"]}
      
      {:ok, validated} = Validator.validate_fields(data, fields)
      # => {:ok, %{question: "What is 2+2?", context: ["math", "arithmetic"]}}

      # Error case
      bad_data = %{question: 123}  # wrong type
      {:error, reason} = Validator.validate_fields(bad_data, fields)
      # => {:error, "Field question: Expected :string, got: 123 (integer)"}
  """

  @doc """
  Validates data against a list of field definitions.

  Each field definition is a tuple of `{field_name, type, constraints}`.
  Returns `{:ok, validated_data}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> fields = [{:name, :string, []}, {:age, :integer, []}]
      iex> data = %{name: "Alice", age: 30}
      iex> DSPex.Signature.Validator.validate_fields(data, fields)
      {:ok, %{name: "Alice", age: 30}}

      iex> fields = [{:name, :string, []}, {:age, :integer, []}]
      iex> bad_data = %{name: "Alice"}  # missing age
      iex> DSPex.Signature.Validator.validate_fields(bad_data, fields)
      {:error, "Missing required field: age"}
  """
  @spec validate_fields(map(), [{atom(), any(), list()}]) :: {:ok, map()} | {:error, String.t()}
  def validate_fields(data, fields) when is_map(data) and is_list(fields) do
    case validate_all_fields(data, fields, %{}) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, _reason} = error -> error
    end
  end

  def validate_fields(data, _fields) when not is_map(data) do
    {:error, "Data must be a map, got: #{inspect(data)}"}
  end

  @doc """
  Validates a single value against a type definition.

  Returns `{:ok, validated_value}` on success or `{:error, reason}` on failure.
  May perform type coercion where appropriate.

  ## Examples

      iex> DSPex.Signature.Validator.validate_type("hello", :string)
      {:ok, "hello"}

      iex> DSPex.Signature.Validator.validate_type(42, :string)
      {:error, "Expected :string, got: 42 (integer)"}

      iex> DSPex.Signature.Validator.validate_type([1, 2, 3], {:list, :integer})
      {:ok, [1, 2, 3]}
  """
  @spec validate_type(any(), any()) :: {:ok, any()} | {:error, String.t()}
  def validate_type(value, :string) when is_binary(value), do: {:ok, value}
  def validate_type(value, :integer) when is_integer(value), do: {:ok, value}
  def validate_type(value, :float) when is_float(value), do: {:ok, value}
  def validate_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  def validate_type(value, :atom) when is_atom(value), do: {:ok, value}
  def validate_type(value, :any), do: {:ok, value}
  def validate_type(value, :map) when is_map(value), do: {:ok, value}

  # ML-specific types
  def validate_type(value, :embedding) when is_list(value) do
    if Enum.all?(value, &is_number/1) do
      {:ok, value}
    else
      {:error, "Embedding must be a list of numbers, got: #{inspect(value)}"}
    end
  end

  def validate_type(value, :probability) when is_number(value) do
    if value >= 0.0 and value <= 1.0 do
      {:ok, value}
    else
      {:error, "Probability must be between 0.0 and 1.0, got: #{value}"}
    end
  end

  def validate_type(value, :confidence_score) when is_number(value) do
    if value >= 0.0 and value <= 1.0 do
      {:ok, value}
    else
      {:error, "Confidence score must be between 0.0 and 1.0, got: #{value}"}
    end
  end

  def validate_type(value, :reasoning_chain) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      {:ok, value}
    else
      {:error, "Reasoning chain must be a list of strings, got: #{inspect(value)}"}
    end
  end

  # Composite types
  def validate_type(value, {:list, inner_type}) when is_list(value) do
    validate_list_items(value, inner_type, [])
  end

  def validate_type(value, {:dict, key_type, value_type}) when is_map(value) do
    validate_dict_entries(Map.to_list(value), key_type, value_type, %{})
  end

  def validate_type(value, {:union, types}) when is_list(types) do
    validate_union_type(value, types)
  end

  # Handle numeric coercion for convenience
  def validate_type(value, :float) when is_integer(value), do: {:ok, value / 1}

  def validate_type(value, :integer) when is_float(value) and trunc(value) == value,
    do: {:ok, trunc(value)}

  # Catch-all for type mismatches
  def validate_type(value, expected_type) do
    actual_type = get_value_type(value)
    {:error, "Expected #{inspect(expected_type)}, got: #{inspect(value)} (#{actual_type})"}
  end

  # Private helper functions

  defp validate_all_fields(_data, [], acc), do: {:ok, acc}

  defp validate_all_fields(data, [{field_name, type, constraints} | rest], acc) do
    case Map.get(data, field_name) do
      nil ->
        {:error, "Missing required field: #{field_name}"}

      value ->
        case validate_field_value(value, type, constraints) do
          {:ok, validated_value} ->
            validate_all_fields(data, rest, Map.put(acc, field_name, validated_value))

          {:error, reason} ->
            {:error, "Field #{field_name}: #{reason}"}
        end
    end
  end

  defp validate_field_value(value, type, _constraints) do
    # Currently constraints are not implemented, but the structure is here for future extension
    validate_type(value, type)
  end

  defp validate_list_items([], _inner_type, acc), do: {:ok, Enum.reverse(acc)}

  defp validate_list_items([item | rest], inner_type, acc) do
    case validate_type(item, inner_type) do
      {:ok, validated_item} ->
        validate_list_items(rest, inner_type, [validated_item | acc])

      {:error, reason} ->
        {:error, "List item validation failed: #{reason}"}
    end
  end

  defp validate_dict_entries([], _key_type, _value_type, acc), do: {:ok, acc}

  defp validate_dict_entries([{key, value} | rest], key_type, value_type, acc) do
    with {:ok, validated_key} <- validate_type(key, key_type),
         {:ok, validated_value} <- validate_type(value, value_type) do
      validate_dict_entries(
        rest,
        key_type,
        value_type,
        Map.put(acc, validated_key, validated_value)
      )
    else
      {:error, reason} -> {:error, "Dict entry validation failed: #{reason}"}
    end
  end

  defp validate_union_type(value, []),
    do: {:error, "Value #{inspect(value)} does not match any union type"}

  defp validate_union_type(value, [type | rest_types]) do
    case validate_type(value, type) do
      {:ok, validated_value} -> {:ok, validated_value}
      {:error, _} -> validate_union_type(value, rest_types)
    end
  end

  defp get_value_type(value) when is_binary(value), do: "string"
  defp get_value_type(value) when is_integer(value), do: "integer"
  defp get_value_type(value) when is_float(value), do: "float"
  defp get_value_type(value) when is_boolean(value), do: "boolean"
  defp get_value_type(value) when is_atom(value), do: "atom"
  defp get_value_type(value) when is_list(value), do: "list"
  defp get_value_type(value) when is_map(value), do: "map"
  defp get_value_type(_value), do: "unknown"

  @doc """
  Validates field presence without type checking.

  Useful for checking if all required fields are present before detailed validation.

  ## Examples

      iex> fields = [{:name, :string, []}, {:age, :integer, []}]
      iex> data = %{name: "Alice", age: 30}
      iex> DSPex.Signature.Validator.check_required_fields(data, fields)
      :ok

      iex> fields = [{:name, :string, []}, {:age, :integer, []}]
      iex> incomplete_data = %{name: "Alice"}
      iex> DSPex.Signature.Validator.check_required_fields(incomplete_data, fields)
      {:error, ["Missing required field: age"]}
  """
  @spec check_required_fields(map(), [{atom(), any(), list()}]) :: :ok | {:error, [String.t()]}
  def check_required_fields(data, fields) when is_map(data) do
    missing_fields =
      fields
      |> Enum.map(fn {field_name, _type, _constraints} -> field_name end)
      |> Enum.reject(&Map.has_key?(data, &1))

    case missing_fields do
      [] -> :ok
      missing -> {:error, Enum.map(missing, &"Missing required field: #{&1}")}
    end
  end

  @doc """
  Performs partial validation, allowing missing fields.

  Useful for incremental data building or optional field scenarios.

  ## Examples

      iex> fields = [{:name, :string, []}, {:age, :integer, []}]
      iex> partial_data = %{name: "Alice"}
      iex> DSPex.Signature.Validator.validate_partial(partial_data, fields)
      {:ok, %{name: "Alice"}}
  """
  @spec validate_partial(map(), [{atom(), any(), list()}]) :: {:ok, map()} | {:error, String.t()}
  def validate_partial(data, fields) when is_map(data) do
    present_fields =
      Enum.filter(fields, fn {field_name, _type, _constraints} ->
        Map.has_key?(data, field_name)
      end)

    validate_fields(data, present_fields)
  end
end

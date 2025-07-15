defmodule DSPex.Signature.EnhancedValidator do
  @moduledoc """
  Enhanced validation for signature metadata and field definitions.

  This module provides comprehensive validation for both legacy signature
  formats and new enhanced metadata formats used by the Python bridge.

  ## Features

  - Validation of enhanced metadata structure
  - Field type validation
  - Cross-field validation
  - Python bridge compatibility checks
  - Legacy format validation

  ## Usage

      case DSPex.Signature.EnhancedValidator.validate_enhanced_metadata(metadata) do
        :ok -> 
          # Metadata is valid
        {:error, errors} -> 
          # Handle validation errors
      end
  """

  @type validation_error :: {atom(), String.t()}
  @type validation_result :: :ok | {:error, [validation_error()]}

  @doc """
  Validates enhanced metadata structure for Python bridge compatibility.

  Performs comprehensive validation including:
  - Required field presence
  - Field type validation
  - Name sanitization checks
  - Python bridge compatibility

  ## Examples

      metadata = %{
        name: "MySignature",
        description: "A test signature",
        inputs: [%{name: "text", type: "string", description: "Input text"}],
        outputs: [%{name: "result", type: "string", description: "Output result"}]
      }

      case DSPex.Signature.EnhancedValidator.validate_enhanced_metadata(metadata) do
        :ok -> 
          IO.puts("Metadata is valid")
        {:error, errors} -> 
          IO.inspect(errors, label: "Validation errors")
      end
  """
  @spec validate_enhanced_metadata(map()) :: validation_result()
  def validate_enhanced_metadata(metadata) when is_map(metadata) do
    errors = []

    errors = validate_required_metadata_fields(metadata, errors)
    errors = validate_metadata_name(metadata, errors)
    errors = validate_metadata_description(metadata, errors)
    errors = validate_field_lists(metadata, errors)
    errors = validate_python_compatibility(metadata, errors)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_enhanced_metadata(_), do: {:error, [structure: "Metadata must be a map"]}

  @doc """
  Validates a list of field definitions.

  Checks each field for required properties and validates types.
  """
  @spec validate_field_definitions([map()], atom()) :: validation_result()
  def validate_field_definitions(fields, field_type) when is_list(fields) do
    errors =
      fields
      |> Enum.with_index()
      |> Enum.reduce([], fn {field, index}, errors ->
        validate_single_field(field, field_type, index, errors)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_field_definitions(_, field_type) do
    {:error, [{field_type, "Field list must be a list"}]}
  end

  ## Private Functions

  defp validate_required_metadata_fields(metadata, errors) do
    required_fields = [:name, :description, :inputs, :outputs]

    Enum.reduce(required_fields, errors, fn field, acc ->
      if Map.has_key?(metadata, field) do
        acc
      else
        [{:missing_field, "Required field missing: #{field}"} | acc]
      end
    end)
  end

  defp validate_metadata_name(metadata, errors) do
    case Map.get(metadata, :name) do
      name when is_binary(name) and name != "" ->
        if valid_python_identifier?(name) do
          errors
        else
          [{:invalid_name, "Name '#{name}' is not a valid Python identifier"} | errors]
        end

      _ ->
        [{:invalid_name, "Name must be a non-empty string"} | errors]
    end
  end

  defp validate_metadata_description(metadata, errors) do
    case Map.get(metadata, :description) do
      desc when is_binary(desc) ->
        errors

      _ ->
        [{:invalid_description, "Description must be a string"} | errors]
    end
  end

  defp validate_field_lists(metadata, errors) do
    errors = validate_field_list(Map.get(metadata, :inputs, []), :inputs, errors)
    validate_field_list(Map.get(metadata, :outputs, []), :outputs, errors)
  end

  defp validate_field_list(fields, list_type, errors) when is_list(fields) do
    if length(fields) > 0 do
      fields
      |> Enum.with_index()
      |> Enum.reduce(errors, fn {field, index}, acc ->
        validate_single_field(field, list_type, index, acc)
      end)
    else
      [{list_type, "Must have at least one field in #{list_type}"} | errors]
    end
  end

  defp validate_field_list(_, list_type, errors) do
    [{list_type, "#{list_type} must be a list"} | errors]
  end

  defp validate_single_field(field, field_type, index, errors) when is_map(field) do
    error_context = "#{field_type}[#{index}]"

    errors = validate_field_name(field, error_context, errors)
    errors = validate_field_type(field, error_context, errors)
    validate_field_description(field, error_context, errors)
  end

  defp validate_single_field(_, field_type, index, errors) do
    [{field_type, "Field at index #{index} must be a map"} | errors]
  end

  defp validate_field_name(field, context, errors) do
    case Map.get(field, :name) do
      name when is_binary(name) and name != "" ->
        if valid_python_identifier?(name) do
          errors
        else
          [
            {:invalid_field_name,
             "#{context}: Field name '#{name}' is not a valid Python identifier"}
            | errors
          ]
        end

      _ ->
        [{:invalid_field_name, "#{context}: Field name must be a non-empty string"} | errors]
    end
  end

  defp validate_field_type(field, context, errors) do
    case Map.get(field, :type) do
      type when is_binary(type) and type != "" ->
        if valid_field_type?(type) do
          errors
        else
          [{:invalid_field_type, "#{context}: Unknown field type '#{type}'"} | errors]
        end

      _ ->
        [{:invalid_field_type, "#{context}: Field type must be a non-empty string"} | errors]
    end
  end

  defp validate_field_description(field, context, errors) do
    case Map.get(field, :description) do
      desc when is_binary(desc) ->
        errors

      nil ->
        # Description is optional, but warn if missing
        errors

      _ ->
        [{:invalid_field_description, "#{context}: Field description must be a string"} | errors]
    end
  end

  defp validate_python_compatibility(metadata, errors) do
    # Check for any Python-specific compatibility issues
    errors = validate_field_name_conflicts(metadata, errors)
    validate_reserved_names(metadata, errors)
  end

  defp validate_field_name_conflicts(metadata, errors) do
    all_field_names =
      (Map.get(metadata, :inputs, []) ++ Map.get(metadata, :outputs, []))
      # Only process map entries
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&is_binary/1)

    duplicate_names =
      all_field_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    case duplicate_names do
      [] ->
        errors

      names ->
        duplicate_list = Enum.join(names, ", ")
        [{:field_name_conflict, "Duplicate field names: #{duplicate_list}"} | errors]
    end
  end

  defp validate_reserved_names(metadata, errors) do
    reserved_python_names = ~w[
      class def if elif else for while try except finally with as import from
      return yield lambda global nonlocal pass break continue del and or not in is
      True False None __init__ __call__ __str__ __repr__ self completions
    ]

    all_field_names =
      (Map.get(metadata, :inputs, []) ++ Map.get(metadata, :outputs, []))
      # Only process map entries
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&is_binary/1)

    reserved_conflicts =
      all_field_names
      |> Enum.filter(&(&1 in reserved_python_names))

    case reserved_conflicts do
      [] ->
        errors

      names ->
        conflict_list = Enum.join(names, ", ")

        [
          {:reserved_name_conflict,
           "Field names conflict with Python reserved words: #{conflict_list}"}
          | errors
        ]
    end
  end

  defp valid_python_identifier?(name) when is_binary(name) do
    # Python identifier rules: start with letter or underscore, followed by letters, digits, or underscores
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) && String.length(name) > 0
  end

  defp valid_field_type?(type) when is_binary(type) do
    basic_types = ~w[string integer float boolean dict list any]
    ml_types = ~w[embedding probability confidence_score reasoning_chain]

    # Also allow complex types like list<string>, dict<string,float>, etc.
    type in basic_types ||
      type in ml_types ||
      String.match?(type, ~r/^list<.+>$/) ||
      String.match?(type, ~r/^dict<.+,.+>$/) ||
      String.match?(type, ~r/^union<.+>$/)
  end
end

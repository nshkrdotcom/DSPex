defmodule ElixirML.Schema.ValidationError do
  @moduledoc """
  Structured validation error for ElixirML schemas.
  Provides detailed error information for debugging and optimization.
  """

  defexception [:message, :schema, :data, :field, :path, :context]

  @type t :: %__MODULE__{
          message: String.t(),
          schema: module() | nil,
          data: term(),
          field: atom() | nil,
          path: [atom()] | nil,
          context: map()
        }

  def exception(opts) when is_list(opts) do
    %__MODULE__{
      message: Keyword.get(opts, :message, "Validation failed"),
      schema: Keyword.get(opts, :schema),
      data: Keyword.get(opts, :data),
      field: Keyword.get(opts, :field),
      path: Keyword.get(opts, :path, []),
      context: Keyword.get(opts, :context, %{})
    }
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message, context: %{}}
  end

  @doc """
  Create a field-specific validation error.
  """
  def field_error(field, message, opts \\ []) do
    %__MODULE__{
      message: "Field #{field}: #{message}",
      field: field,
      data: Keyword.get(opts, :data),
      schema: Keyword.get(opts, :schema),
      path: [field | Keyword.get(opts, :path, [])],
      context: Keyword.get(opts, :context, %{})
    }
  end

  @doc """
  Create a type validation error.
  """
  def type_error(field, expected_type, actual_value, opts \\ []) do
    %__MODULE__{
      message: "Field #{field}: expected #{expected_type}, got #{inspect(actual_value)}",
      field: field,
      data: actual_value,
      schema: Keyword.get(opts, :schema),
      path: [field | Keyword.get(opts, :path, [])],
      context:
        Map.merge(
          Keyword.get(opts, :context, %{}),
          %{expected_type: expected_type, actual_type: type_of(actual_value)}
        )
    }
  end

  @doc """
  Create a constraint validation error.
  """
  def constraint_error(field, constraint, value, opts \\ []) do
    %__MODULE__{
      message: "Field #{field}: constraint #{constraint} failed for value #{inspect(value)}",
      field: field,
      data: value,
      schema: Keyword.get(opts, :schema),
      path: [field | Keyword.get(opts, :path, [])],
      context:
        Map.merge(
          Keyword.get(opts, :context, %{}),
          %{constraint: constraint, value: value}
        )
    }
  end

  @doc """
  Create a nested validation error.
  """
  def nested_error(path, inner_error, opts \\ []) do
    %__MODULE__{
      message: "At #{path_to_string(path)}: #{inner_error.message}",
      field: List.last(path),
      data: inner_error.data,
      schema: Keyword.get(opts, :schema, inner_error.schema),
      path: path,
      context:
        Map.merge(
          Keyword.get(opts, :context, %{}),
          %{inner_error: inner_error}
        )
    }
  end

  @doc """
  Add context to an existing error.
  """
  def add_context(%__MODULE__{} = error, key, value) do
    %{error | context: Map.put(error.context, key, value)}
  end

  def add_context(%__MODULE__{} = error, context) when is_map(context) do
    %{error | context: Map.merge(error.context, context)}
  end

  @doc """
  Convert error to a user-friendly string.
  """
  def to_friendly_string(%__MODULE__{} = error) do
    base_message =
      if error.path && !Enum.empty?(error.path) do
        "At #{path_to_string(error.path)}: #{error.message}"
      else
        error.message
      end

    context_info =
      case error.context do
        context when map_size(context) > 0 ->
          context_str =
            Enum.map_join(context, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)

          " (#{context_str})"

        _ ->
          ""
      end

    base_message <> context_info
  end

  defimpl String.Chars do
    alias ElixirML.Schema.ValidationError

    def to_string(error) do
      ValidationError.to_friendly_string(error)
    end
  end

  # Private helpers

  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(_), do: :unknown

  defp path_to_string(path) do
    path
    |> Enum.reverse()
    |> Enum.map_join(".", &to_string/1)
  end
end

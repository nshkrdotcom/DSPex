defmodule DSPex.Adapters.TypeConverter do
  @moduledoc """
  Type conversion system for adapter data transformation.

  Handles bidirectional type conversion between Elixir types and DSPy types,
  ensuring data integrity and proper format transformation across adapter
  boundaries. Supports complex nested structures and custom type mappings.
  """

  require Logger

  @type conversion_opts :: [
          strict: boolean(),
          atom_keys: boolean(),
          custom_types: map()
        ]

  # DSPy to Elixir type mappings
  @dspy_to_elixir %{
    "str" => :string,
    "int" => :integer,
    "float" => :float,
    "bool" => :boolean,
    "list" => :list,
    "dict" => :map,
    "None" => nil,
    "NoneType" => nil
  }

  # Elixir to DSPy type mappings
  @elixir_to_dspy %{
    string: "str",
    integer: "int",
    float: "float",
    boolean: "bool",
    list: "list",
    map: "dict",
    atom: "str",
    nil: "None"
  }

  @doc """
  Converts DSPy types to Elixir types.

  Handles simple types, nested structures, and complex type annotations
  like List[str] or Dict[str, int].

  ## Examples

      iex> TypeConverter.dspy_to_elixir("str")
      :string
      
      iex> TypeConverter.dspy_to_elixir("List[int]")
      {:list, :integer}
      
      iex> TypeConverter.dspy_to_elixir("Dict[str, float]")
      {:map, :string, :float}
  """
  @spec dspy_to_elixir(String.t()) :: atom() | tuple()
  def dspy_to_elixir(dspy_type) when is_binary(dspy_type) do
    case parse_dspy_type(dspy_type) do
      {:ok, elixir_type} -> elixir_type
      {:error, _reason} -> :any
    end
  end

  @doc """
  Converts Elixir types to DSPy types.

  ## Examples

      iex> TypeConverter.elixir_to_dspy(:string)
      "str"
      
      iex> TypeConverter.elixir_to_dspy({:list, :integer})
      "List[int]"
  """
  @spec elixir_to_dspy(atom() | tuple()) :: String.t()
  def elixir_to_dspy(elixir_type) when is_atom(elixir_type) do
    Map.get(@elixir_to_dspy, elixir_type, "Any")
  end

  def elixir_to_dspy({:list, inner_type}) do
    "List[#{elixir_to_dspy(inner_type)}]"
  end

  def elixir_to_dspy({:map, key_type, value_type}) do
    "Dict[#{elixir_to_dspy(key_type)}, #{elixir_to_dspy(value_type)}]"
  end

  def elixir_to_dspy(_), do: "Any"

  @doc """
  Converts DSPy data to Elixir format.

  Transforms Python-style data structures to idiomatic Elixir formats,
  handling type coercion and structure transformation.

  ## Options

  - `:atom_keys` - Convert string keys to atoms (default: false)
  - `:strict` - Fail on unknown types (default: false)

  ## Examples

      iex> TypeConverter.from_dspy(%{"name" => "test", "count" => 42})
      %{"name" => "test", "count" => 42}
      
      iex> TypeConverter.from_dspy(%{"name" => "test"}, atom_keys: true)
      %{name: "test"}
  """
  @spec from_dspy(any(), conversion_opts()) :: any()
  def from_dspy(data, opts \\ [])

  def from_dspy(nil, _opts), do: nil
  def from_dspy(data, _opts) when is_binary(data), do: data
  def from_dspy(data, _opts) when is_number(data), do: data
  def from_dspy(data, _opts) when is_boolean(data), do: data

  def from_dspy(data, opts) when is_list(data) do
    Enum.map(data, &from_dspy(&1, opts))
  end

  def from_dspy(data, opts) when is_map(data) do
    atom_keys = Keyword.get(opts, :atom_keys, false)

    data
    |> Enum.map(fn {k, v} ->
      key = if atom_keys and is_binary(k), do: String.to_atom(k), else: k
      {key, from_dspy(v, opts)}
    end)
    |> Map.new()
  end

  def from_dspy(data, opts) do
    if Keyword.get(opts, :strict, false) do
      raise ArgumentError, "Unknown DSPy data type: #{inspect(data)}"
    else
      data
    end
  end

  @doc """
  Converts Elixir data to DSPy format.

  Transforms Elixir data structures to Python-compatible formats,
  handling atoms, tuples, and other Elixir-specific types.

  ## Examples

      iex> TypeConverter.to_dspy(%{name: "test", active: true})
      %{"name" => "test", "active" => true}
      
      iex> TypeConverter.to_dspy({:ok, "result"})
      ["ok", "result"]
  """
  @spec to_dspy(any(), conversion_opts()) :: any()
  def to_dspy(data, opts \\ [])

  def to_dspy(nil, _opts), do: nil
  def to_dspy(data, _opts) when is_binary(data), do: data
  def to_dspy(data, _opts) when is_number(data), do: data
  def to_dspy(data, _opts) when is_boolean(data), do: data
  def to_dspy(atom, _opts) when is_atom(atom), do: to_string(atom)

  def to_dspy(data, opts) when is_list(data) do
    Enum.map(data, &to_dspy(&1, opts))
  end

  def to_dspy(data, opts) when is_tuple(data) do
    data
    |> Tuple.to_list()
    |> Enum.map(&to_dspy(&1, opts))
  end

  def to_dspy(%Date{} = date, _opts), do: Date.to_iso8601(date)
  def to_dspy(%DateTime{} = datetime, _opts), do: DateTime.to_iso8601(datetime)

  def to_dspy(%{__struct__: _} = struct, opts) do
    struct
    |> Map.from_struct()
    |> to_dspy(opts)
  end

  def to_dspy(data, opts) when is_map(data) do
    data
    |> Enum.map(fn {k, v} ->
      key = if is_atom(k), do: to_string(k), else: k
      {key, to_dspy(v, opts)}
    end)
    |> Map.new()
  end

  def to_dspy(data, opts) do
    if Keyword.get(opts, :strict, false) do
      raise ArgumentError, "Cannot convert to DSPy format: #{inspect(data)}"
    else
      inspect(data)
    end
  end

  @doc """
  Converts a signature definition between formats.

  Transforms signature definitions between Elixir and DSPy wire formats,
  handling field type conversions and metadata.

  ## Examples

      iex> TypeConverter.convert_signature(%{
      ...>   inputs: [%{name: :question, type: :string}],
      ...>   outputs: [%{name: :answer, type: :string}]
      ...> })
      %{
        "inputs" => [%{"name" => "question", "type" => "str", "description" => ""}],
        "outputs" => [%{"name" => "answer", "type" => "str", "description" => ""}]
      }
  """
  @spec convert_signature(map()) :: %{String.t() => list()}
  def convert_signature(signature) when is_map(signature) do
    %{
      "inputs" => convert_fields(Map.get(signature, :inputs, [])),
      "outputs" => convert_fields(Map.get(signature, :outputs, []))
    }
  end

  @doc """
  Validates data against expected types.

  Checks if data matches the expected type specification, useful for
  runtime validation at adapter boundaries.

  ## Examples

      iex> TypeConverter.validate_type("hello", :string)
      :ok
      
      iex> TypeConverter.validate_type(42, :string)
      {:error, "Expected string, got integer"}
  """
  @spec validate_type(any(), atom() | tuple()) :: :ok | {:error, String.t()}
  def validate_type(data, expected_type)

  def validate_type(data, :string) when is_binary(data), do: :ok
  def validate_type(data, :integer) when is_integer(data), do: :ok
  def validate_type(data, :float) when is_float(data), do: :ok
  def validate_type(data, :boolean) when is_boolean(data), do: :ok
  def validate_type(nil, nil), do: :ok
  def validate_type(_data, :any), do: :ok

  def validate_type(data, {:list, inner_type}) when is_list(data) do
    case Enum.find(data, fn item -> validate_type(item, inner_type) != :ok end) do
      nil -> :ok
      _item -> {:error, "List contains invalid item type"}
    end
  end

  def validate_type(data, {:map, _key_type, _value_type}) when is_map(data) do
    # Simplified validation for maps
    :ok
  end

  def validate_type(data, expected_type) do
    actual_type = type_of(data)
    {:error, "Expected #{expected_type}, got #{actual_type}"}
  end

  @doc """
  Coerces data to the specified type if possible.

  Attempts to convert data to match the expected type, useful for
  handling flexible input formats.

  ## Examples

      iex> TypeConverter.coerce("42", :integer)
      {:ok, 42}
      
      iex> TypeConverter.coerce("true", :boolean)
      {:ok, true}
      
      iex> TypeConverter.coerce("not_a_number", :integer)
      {:error, "Cannot coerce string to integer"}
  """
  @spec coerce(any(), atom()) :: {:ok, any()} | {:error, String.t()}
  def coerce(data, :string) when not is_binary(data) do
    {:ok, to_string(data)}
  end

  def coerce(data, :integer) when is_binary(data) do
    case Integer.parse(data) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Cannot coerce string to integer"}
    end
  end

  def coerce(data, :float) when is_binary(data) do
    case Float.parse(data) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "Cannot coerce string to float"}
    end
  end

  def coerce(data, :float) when is_integer(data) do
    {:ok, data * 1.0}
  end

  def coerce("true", :boolean), do: {:ok, true}
  def coerce("false", :boolean), do: {:ok, false}
  def coerce("1", :boolean), do: {:ok, true}
  def coerce("0", :boolean), do: {:ok, false}
  def coerce(1, :boolean), do: {:ok, true}
  def coerce(0, :boolean), do: {:ok, false}

  def coerce(data, :atom) when is_binary(data) do
    {:ok, String.to_atom(data)}
  end

  def coerce(data, target_type) do
    case validate_type(data, target_type) do
      :ok -> {:ok, data}
      error -> error
    end
  end

  # Private Functions

  defp parse_dspy_type(type_string) do
    cond do
      Map.has_key?(@dspy_to_elixir, type_string) ->
        {:ok, @dspy_to_elixir[type_string]}

      String.starts_with?(type_string, "List[") ->
        parse_list_type(type_string)

      String.starts_with?(type_string, "Dict[") ->
        parse_dict_type(type_string)

      String.starts_with?(type_string, "Optional[") ->
        parse_optional_type(type_string)

      true ->
        {:error, "Unknown DSPy type: #{type_string}"}
    end
  end

  defp parse_list_type(type_string) do
    case Regex.run(~r/^List\[(.+)\]$/, type_string) do
      [_, inner] ->
        case parse_dspy_type(inner) do
          {:ok, inner_type} -> {:ok, {:list, inner_type}}
          error -> error
        end

      _ ->
        {:error, "Invalid List type format"}
    end
  end

  defp parse_dict_type(type_string) do
    case Regex.run(~r/^Dict\[(.+),\s*(.+)\]$/, type_string) do
      [_, key_type, value_type] ->
        with {:ok, k_type} <- parse_dspy_type(String.trim(key_type)),
             {:ok, v_type} <- parse_dspy_type(String.trim(value_type)) do
          {:ok, {:map, k_type, v_type}}
        end

      _ ->
        {:error, "Invalid Dict type format"}
    end
  end

  defp parse_optional_type(type_string) do
    case Regex.run(~r/^Optional\[(.+)\]$/, type_string) do
      [_, inner] ->
        case parse_dspy_type(inner) do
          {:ok, inner_type} -> {:ok, {:optional, inner_type}}
          error -> error
        end

      _ ->
        {:error, "Invalid Optional type format"}
    end
  end

  defp convert_fields(fields) when is_list(fields) do
    Enum.map(fields, &convert_field/1)
  end

  defp convert_field(%{name: name, type: type} = field) do
    %{
      "name" => to_string(name),
      "type" => elixir_to_dspy(type),
      "description" => Map.get(field, :description, "")
    }
  end

  defp type_of(data) when is_binary(data), do: :string
  defp type_of(data) when is_integer(data), do: :integer
  defp type_of(data) when is_float(data), do: :float
  defp type_of(data) when is_boolean(data), do: :boolean
  defp type_of(data) when is_atom(data), do: :atom
  defp type_of(data) when is_list(data), do: :list
  defp type_of(data) when is_map(data), do: :map
  defp type_of(data) when is_tuple(data), do: :tuple
  defp type_of(nil), do: nil
  defp type_of(_), do: :unknown
end

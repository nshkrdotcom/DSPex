defmodule DSPEx.Example do
  @moduledoc """
  Represents an example data structure for DSPEx programs.

  An Example holds input/output data and provides methods for manipulation,
  conversion, and validation. This is equivalent to Python DSPy's Example class
  but designed for Elixir's functional paradigm.

  ## Key Features

  - Immutable data structure with functional operations
  - Input/output field designation for validation
  - Protocol implementations for seamless Elixir integration
  - Type-safe operations with comprehensive specs

  ## Example Usage

      # Create example with data
      example = DSPEx.Example.new(%{question: "What is 2+2?", answer: "4"})

      # Access data
      DSPEx.Example.get(example, :question)  # "What is 2+2?"

      # Update data (returns new instance)
      updated = DSPEx.Example.put(example, :confidence, 0.95)

      # Designate input fields for validation
      with_inputs = DSPEx.Example.with_inputs(example, [:question])

      # Convert to different formats
      DSPEx.Example.to_dict(example)  # %{question: "What is 2+2?", answer: "4"}

  ## Data Structure

  The Example struct contains:
  - `data`: Map containing the actual key-value pairs
  - `input_keys`: MapSet of keys that are considered inputs (for validation)

  Both fields are enforced to ensure structural integrity. See `@type t` for the
  complete type specification.
  """

  @enforce_keys [:data, :input_keys]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          data: map(),
          input_keys: MapSet.t(atom())
        }

  @doc """
  Creates a new Example from data.

  ## Parameters
  - `data` - Initial data as a map or keyword list (optional, defaults to empty map)

  ## Returns
  - A new `DSPEx.Example` struct with the given data and no designated input keys

  ## Examples

      iex> DSPEx.Example.new()
      %DSPEx.Example{data: %{}, input_keys: #MapSet<[]>}

      iex> DSPEx.Example.new(%{question: "What is 2+2?"})
      %DSPEx.Example{data: %{question: "What is 2+2?"}, input_keys: #MapSet<[]>}

      iex> DSPEx.Example.new([question: "Hi", answer: "Hello"])
      %DSPEx.Example{data: %{question: "Hi", answer: "Hello"}, input_keys: #MapSet<[]>}

  """
  @spec new(map() | keyword()) :: t()
  def new(data \\ %{})

  def new(data) when is_map(data) do
    %__MODULE__{
      data: data,
      input_keys: MapSet.new()
    }
  end

  def new(data) when is_list(data) do
    new(Enum.into(data, %{}))
  end

  @doc """
  Creates a new Example with specified input keys.

  Input keys are used for validation and separation of concerns.
  This is useful for distinguishing between input fields and output fields
  in DSPEx programs.

  ## Parameters
  - `data` - Initial data as a map or keyword list
  - `input_keys` - List of atoms representing keys that should be considered inputs

  ## Returns
  - A new `DSPEx.Example` struct with the given data and designated input keys

  ## Examples

      iex> DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      %DSPEx.Example{
        data: %{question: "Hi", answer: "Hello"},
        input_keys: #MapSet<[:question]>
      }

  """
  @spec new(map() | keyword(), [atom()]) :: t()
  def new(data, input_keys) when is_list(input_keys) do
    data
    |> new()
    |> Map.put(:input_keys, MapSet.new(input_keys))
  end

  @doc """
  Gets a value from the example data.

  ## Parameters
  - `example` - The Example struct to query
  - `key` - The atom key to retrieve
  - `default` - Default value if key is not found (optional, defaults to nil)

  ## Returns
  - The value associated with the key, or the default value

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> DSPEx.Example.get(example, :question)
      "What is 2+2?"

      iex> DSPEx.Example.get(example, :missing)
      nil

      iex> DSPEx.Example.get(example, :missing, "default")
      "default"

  """
  @spec get(t(), atom(), any()) :: any()
  def get(%__MODULE__{data: data}, key, default \\ nil) do
    Map.get(data, key, default)
  end

  @doc """
  Puts a value into the example data, returning a new example.

  This operation is immutable - it returns a new Example instance
  with the updated data while leaving the original unchanged.

  ## Parameters
  - `example` - The Example struct to update
  - `key` - The atom key to set
  - `value` - The value to associate with the key

  ## Returns
  - A new Example struct with the updated data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> updated = DSPEx.Example.put(example, :answer, "4")
      iex> updated.data
      %{question: "What is 2+2?", answer: "4"}

  """
  @spec put(t(), atom(), any()) :: t()
  def put(%__MODULE__{} = example, key, value) do
    %{example | data: Map.put(example.data, key, value)}
  end

  @doc """
  Updates multiple values in the example data.

  This operation merges the new data with the existing data,
  returning a new Example instance.

  ## Parameters
  - `example` - The Example struct to update
  - `new_data` - A map containing the new key-value pairs to merge

  ## Returns
  - A new Example struct with the merged data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "What is 2+2?"})
      iex> updated = DSPEx.Example.merge(example, %{answer: "4", confidence: 0.9})
      iex> updated.data
      %{question: "What is 2+2?", answer: "4", confidence: 0.9}

  """
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{} = example, new_data) when is_map(new_data) do
    %{example | data: Map.merge(example.data, new_data)}
  end

  @doc """
  Deletes a key from the example data.

  Returns a new Example instance with the specified key removed.

  ## Parameters
  - `example` - The Example struct to update
  - `key` - The atom key to remove

  ## Returns
  - A new Example struct with the key removed from data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello", temp: "remove"})
      iex> cleaned = DSPEx.Example.delete(example, :temp)
      iex> cleaned.data
      %{question: "Hi", answer: "Hello"}

  """
  @spec delete(t(), atom()) :: t()
  def delete(%__MODULE__{} = example, key) do
    %{example | data: Map.delete(example.data, key)}
  end

  @doc """
  Designates which keys are considered inputs (does not filter data).

  This function sets which fields should be considered as inputs for
  validation and separation purposes. The data itself remains unchanged.

  ## Parameters
  - `example` - The Example struct to update
  - `keys` - List of atom keys to designate as inputs

  ## Returns
  - A new Example struct with the specified input key designation

  ## Examples

      iex> example = DSPEx.Example.new(%{q: "Hi", a: "Hello", extra: "data"})
      iex> with_inputs = DSPEx.Example.with_inputs(example, [:q])
      iex> with_inputs.data
      %{q: "Hi", a: "Hello", extra: "data"}
      iex> MapSet.to_list(with_inputs.input_keys)
      [:q]

  """
  @spec with_inputs(t(), [atom()]) :: t()
  def with_inputs(%__MODULE__{} = example, keys) when is_list(keys) do
    %{example | input_keys: MapSet.new(keys)}
  end

  @doc """
  Filters example data to only include outputs (non-input keys).

  Creates a new Example containing only the output fields (keys that
  are not designated as inputs). The resulting example has no input keys.

  ## Parameters
  - `example` - The Example struct to filter

  ## Returns
  - A new Example struct containing only output data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> outputs = DSPEx.Example.with_outputs(example)
      iex> outputs.data
      %{answer: "Hello"}

  """
  @spec with_outputs(t()) :: t()
  def with_outputs(%__MODULE__{data: data, input_keys: input_keys} = example) do
    output_keys =
      data
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(input_keys)
      |> MapSet.to_list()

    filtered_data = Map.take(data, output_keys)
    %{example | data: filtered_data, input_keys: MapSet.new()}
  end

  @doc """
  Returns the input data only.

  Extracts only the data for keys that have been designated as inputs.

  ## Parameters
  - `example` - The Example struct to query

  ## Returns
  - A map containing only the input key-value pairs

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.inputs(example)
      %{question: "Hi"}

  """
  @spec inputs(t()) :: map()
  def inputs(%__MODULE__{data: data, input_keys: input_keys}) do
    input_keys
    |> MapSet.to_list()
    |> case do
      [] -> %{}
      keys -> Map.take(data, keys)
    end
  end

  @doc """
  Returns the output data only.

  Extracts only the data for keys that have NOT been designated as inputs.

  ## Parameters
  - `example` - The Example struct to query

  ## Returns
  - A map containing only the output key-value pairs

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.outputs(example)
      %{answer: "Hello"}

  """
  @spec outputs(t()) :: map()
  def outputs(%__MODULE__{data: data, input_keys: input_keys}) do
    output_keys =
      data
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(input_keys)
      |> MapSet.to_list()

    Map.take(data, output_keys)
  end

  @doc """
  Returns the output data only (alias for outputs/1 for DSPy compatibility).

  This function provides compatibility with the Python DSPy library
  which uses the term "labels" for output data.

  ## Parameters
  - `example` - The Example struct to query

  ## Returns
  - A map containing only the output key-value pairs

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"}, [:question])
      iex> DSPEx.Example.labels(example)
      %{answer: "Hello"}

  """
  @spec labels(t()) :: map()
  def labels(%__MODULE__{} = example), do: outputs(example)

  @doc """
  Converts example to a plain map (equivalent to Python's toDict()).

  Extracts the raw data map from the Example struct for interoperability
  with other systems or when plain map operations are needed.

  ## Parameters
  - `example` - The Example struct to convert

  ## Returns
  - The raw data map from the Example struct

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.to_dict(example)
      %{question: "Hi", answer: "Hello"}

  """
  @spec to_dict(t()) :: map()
  def to_dict(%__MODULE__{data: data}), do: data

  @doc """
  Converts example to a keyword list.

  Useful for interoperability with functions that expect keyword lists.

  ## Parameters
  - `example` - The Example struct to convert

  ## Returns
  - A keyword list representation of the example data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.to_list(example) |> Enum.sort()
      [answer: "Hello", question: "Hi"]

  """
  @spec to_list(t()) :: keyword()
  def to_list(%__MODULE__{data: data}), do: Map.to_list(data)

  @doc """
  Returns all keys in the example.

  ## Parameters
  - `example` - The Example struct to query

  ## Returns
  - A list of all keys (atoms) in the example data

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi", answer: "Hello"})
      iex> DSPEx.Example.keys(example) |> Enum.sort()
      [:answer, :question]

  """
  @spec keys(t()) :: [atom()]
  def keys(%__MODULE__{data: data}), do: Map.keys(data)

  @doc """
  Returns all values in the example.

  ## Parameters
  - `example` - The Example struct to query

  ## Returns
  - A list of all values in the example data

  ## Examples

      iex> example = DSPEx.Example.new(%{a: 1, b: 2})
      iex> DSPEx.Example.values(example) |> Enum.sort()
      [1, 2]

  """
  @spec values(t()) :: [any()]
  def values(%__MODULE__{data: data}), do: Map.values(data)

  @doc """
  Checks if the example is empty.

  ## Parameters
  - `example` - The Example struct to check

  ## Returns
  - `true` if the example contains no data, `false` otherwise

  ## Examples

      iex> DSPEx.Example.empty?(%DSPEx.Example{data: %{}, input_keys: MapSet.new()})
      true

      iex> DSPEx.Example.empty?(DSPEx.Example.new(%{a: 1}))
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{data: data}), do: map_size(data) == 0

  @doc """
  Returns the size (number of key-value pairs) of the example.

  ## Parameters
  - `example` - The Example struct to measure

  ## Returns
  - A non-negative integer representing the number of key-value pairs

  ## Examples

      iex> example = DSPEx.Example.new(%{a: 1, b: 2, c: 3})
      iex> DSPEx.Example.size(example)
      3

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{data: data}), do: map_size(data)

  @doc """
  Checks if a key exists in the example.

  ## Parameters
  - `example` - The Example struct to check
  - `key` - The atom key to look for

  ## Returns
  - `true` if the key exists in the data, `false` otherwise

  ## Examples

      iex> example = DSPEx.Example.new(%{question: "Hi"})
      iex> DSPEx.Example.has_key?(example, :question)
      true

      iex> DSPEx.Example.has_key?(example, :answer)
      false

  """
  @spec has_key?(t(), atom()) :: boolean()
  def has_key?(%__MODULE__{data: data}, key), do: Map.has_key?(data, key)

  # Protocol implementations for better Elixir integration

  defimpl Enumerable do
    @moduledoc false

    @spec count(DSPEx.Example.t()) :: {:ok, non_neg_integer()}
    def count(%DSPEx.Example{data: data}), do: {:ok, map_size(data)}

    @spec member?(DSPEx.Example.t(), {atom(), any()}) :: {:ok, boolean()}
    def member?(%DSPEx.Example{data: data}, {key, value}) do
      {:ok, Map.get(data, key) == value}
    end

    @spec member?(DSPEx.Example.t(), any()) :: {:ok, boolean()}
    def member?(%DSPEx.Example{}, _), do: {:ok, false}

    @spec slice(DSPEx.Example.t()) :: {:error, module()}
    def slice(%DSPEx.Example{}), do: {:error, __MODULE__}

    @spec reduce(DSPEx.Example.t(), Enumerable.acc(), Enumerable.reducer()) :: Enumerable.result()
    def reduce(%DSPEx.Example{data: data}, acc, fun) do
      Enumerable.reduce(data, acc, fun)
    end
  end

  defimpl Collectable do
    @moduledoc false

    @spec into(DSPEx.Example.t()) ::
            {DSPEx.Example.t(),
             (DSPEx.Example.t(), Collectable.command() -> DSPEx.Example.t() | any())}
    def into(%DSPEx.Example{} = original) do
      collector_fun = fn
        example_acc, {:cont, {key, value}} ->
          DSPEx.Example.put(example_acc, key, value)

        example_acc, :done ->
          example_acc

        _example_acc, :halt ->
          :ok
      end

      {original, collector_fun}
    end
  end

  defimpl Inspect do
    @moduledoc false
    import Inspect.Algebra

    @spec inspect(DSPEx.Example.t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
    def inspect(%DSPEx.Example{data: data, input_keys: input_keys}, opts) do
      input_keys_list = MapSet.to_list(input_keys)

      concat([
        "#DSPEx.Example<",
        to_doc(data, opts),
        if input_keys_list != [] do
          concat([", inputs: ", to_doc(input_keys_list, opts)])
        else
          empty()
        end,
        ">"
      ])
    end
  end
end

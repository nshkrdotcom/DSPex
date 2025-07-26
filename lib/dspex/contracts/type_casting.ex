defmodule DSPex.Contracts.TypeCasting do
  @moduledoc """
  Type casting module for converting Python results to Elixir types.
  
  This module handles the conversion of values returned from Python
  to their appropriate Elixir representations according to contract
  specifications.
  
  ## Type Conversions
  
  - Python strings → Elixir binaries
  - Python integers → Elixir integers
  - Python floats → Elixir floats
  - Python booleans → Elixir booleans
  - Python dicts → Elixir maps
  - Python lists → Elixir lists
  - Python objects → Elixir structs (when specified)
  - Python references → Preserved as references
  """

  @doc """
  Casts a result value to the specified type.
  
  ## Examples
  
      iex> TypeCasting.cast_result("hello", :string)
      {:ok, "hello"}
      
      iex> TypeCasting.cast_result(42, :float)
      {:ok, 42.0}
      
      iex> TypeCasting.cast_result([1, 2, 3], {:list, :float})
      {:ok, [1.0, 2.0, 3.0]}
      
      iex> TypeCasting.cast_result(%{"name" => "test"}, {:struct, MyStruct})
      {:ok, %MyStruct{name: "test"}}
  """
  @spec cast_result(any(), atom() | tuple()) :: {:ok, any()} | {:error, term()}
  
  # Primitive types
  def cast_result(value, :string) when is_binary(value), do: {:ok, value}
  def cast_result(value, :string) do
    {:error, {:cannot_cast, value, :string}}
  end

  def cast_result(value, :integer) when is_integer(value), do: {:ok, value}
  def cast_result(value, :integer) do
    {:error, {:cannot_cast, value, :integer}}
  end

  def cast_result(value, :float) when is_float(value), do: {:ok, value}
  def cast_result(value, :float) when is_integer(value), do: {:ok, value * 1.0}
  def cast_result(value, :float) do
    {:error, {:cannot_cast, value, :float}}
  end

  def cast_result(value, :boolean) when is_boolean(value), do: {:ok, value}
  def cast_result(value, :boolean) do
    {:error, {:cannot_cast, value, :boolean}}
  end

  def cast_result(value, :atom) when is_atom(value), do: {:ok, value}
  def cast_result(value, :atom) when is_binary(value) do
    {:ok, String.to_atom(value)}
  end
  def cast_result(value, :atom) do
    {:error, {:cannot_cast, value, :atom}}
  end

  # Complex types
  def cast_result(value, :list) when is_list(value), do: {:ok, value}
  def cast_result(value, :list) do
    {:error, {:cannot_cast, value, :list}}
  end

  def cast_result(value, {:list, element_type}) when is_list(value) do
    cast_list_elements(value, element_type)
  end
  def cast_result(value, {:list, _element_type}) do
    {:error, {:cannot_cast, value, :list}}
  end

  def cast_result(value, :map) when is_map(value), do: {:ok, value}
  def cast_result(value, :map) do
    {:error, {:cannot_cast, value, :map}}
  end

  def cast_result(value, :tuple) when is_tuple(value), do: {:ok, value}
  def cast_result(value, :tuple) when is_list(value) do
    {:ok, List.to_tuple(value)}
  end
  def cast_result(value, :tuple) do
    {:error, {:cannot_cast, value, :tuple}}
  end

  def cast_result(value, {:struct, module}) when is_map(value) do
    cast_to_struct(value, module)
  end
  def cast_result(value, {:struct, module}) do
    {:error, {:cannot_cast, value, {:struct, module}}}
  end

  def cast_result(value, :reference) when is_reference(value), do: {:ok, value}
  def cast_result(%{__python_ref__: _} = value, :reference), do: {:ok, value}
  def cast_result(value, :reference) do
    {:error, {:cannot_cast, value, :reference}}
  end

  def cast_result(value, :any), do: {:ok, value}

  def cast_result(value, type) do
    {:error, {:unknown_type, type, value}}
  end

  # Helper functions
  defp cast_list_elements(list, element_type) do
    results =
      list
      |> Enum.map(&cast_result(&1, element_type))
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        values = Enum.map(results, fn {:ok, value} -> value end)
        {:ok, values}
      
      error ->
        error
    end
  end

  defp cast_to_struct(value, module) do
    # Convert string keys to atoms if needed
    atomized_map = 
      value
      |> Enum.map(fn
        {key, val} when is_binary(key) -> {String.to_atom(key), val}
        {key, val} -> {key, val}
      end)
      |> Enum.into(%{})
    
    # Check if the module implements from_python_result/1
    if function_exported?(module, :from_python_result, 1) do
      case module.from_python_result(atomized_map) do
        {:ok, struct} -> {:ok, struct}
        {:error, _} = error -> error
        result when is_struct(result, module) -> {:ok, result}
        _ -> {:error, {:invalid_struct_conversion, module}}
      end
    else
      # Fallback to struct/2
      try do
        struct_instance = struct(module, atomized_map)
        {:ok, struct_instance}
      rescue
        error ->
          {:error, {:struct_creation_failed, module, error}}
      end
    end
  end
end
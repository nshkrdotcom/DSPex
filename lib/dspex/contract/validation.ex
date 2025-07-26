defmodule DSPex.Contract.Validation do
  @moduledoc """
  Validation module for DSPex contract system.
  
  Provides functions to validate parameters against contract specifications
  and ensure type safety when calling Python methods.
  
  ## Supported Type Specifications
  
  ### Primitive Types
  - `:string` - Binary string
  - `:integer` - Integer
  - `:float` - Float (accepts integers)
  - `:boolean` - Boolean
  - `:atom` - Atom
  
  ### Complex Types
  - `:list` - Generic list
  - `{:list, type}` - Typed list
  - `:map` - Generic map
  - `:tuple` - Generic tuple
  - `{:struct, module}` - Elixir struct
  - `:reference` - Python object reference
  
  ### Parameter Specifications
  - `{:required, type}` - Required parameter
  - `{:optional, type, default}` - Optional parameter with default
  - `:variable_keyword` - Accept any keyword arguments
  """

  @doc """
  Validates parameters against contract specifications.
  
  ## Examples
  
      iex> spec = [name: {:required, :string}, count: {:optional, :integer, 10}]
      iex> DSPex.Contract.Validation.validate_params(%{name: "test"}, spec)
      :ok
      
      iex> DSPex.Contract.Validation.validate_params(%{}, spec)
      {:error, {:missing_required_param, :name}}
  """
  @spec validate_params(map(), keyword() | :variable_keyword) :: :ok | {:error, term()}
  def validate_params(_params, :variable_keyword), do: :ok
  
  def validate_params(params, spec) when is_map(params) and is_list(spec) do
    start_time = System.monotonic_time()
    metadata = %{
      param_count: map_size(params),
      spec_count: length(spec)
    }
    
    :telemetry.execute(
      [:dspex, :contract, :validate, :start],
      %{system_time: System.system_time()},
      metadata
    )
    
    params = Map.new(params, fn {k, v} -> {to_atom(k), v} end)
    
    result = with :ok <- validate_required_params(params, spec),
                  :ok <- validate_param_types(params, spec) do
      :ok
    end
    
    duration = System.monotonic_time() - start_time
    
    case result do
      :ok ->
        :telemetry.execute(
          [:dspex, :contract, :validate, :stop],
          %{duration: duration, system_time: System.system_time()},
          Map.put(metadata, :success, true)
        )
        
      {:error, reason} = error ->
        :telemetry.execute(
          [:dspex, :contract, :validate, :exception],
          %{duration: duration, system_time: System.system_time()},
          Map.merge(metadata, %{success: false, error: reason})
        )
        error
    end
    
    result
  end
  
  def validate_params(_params, _spec) do
    {:error, :invalid_params_format}
  end

  # Validate that all required parameters are present
  defp validate_required_params(params, spec) do
    spec
    |> Enum.reduce(:ok, fn
      {key, {:required, _type}}, :ok ->
        if Map.has_key?(params, key) do
          :ok
        else
          {:error, {:missing_required_param, key}}
        end
      
      _other, acc ->
        acc
    end)
  end

  # Validate parameter types
  defp validate_param_types(params, spec) do
    params
    |> Enum.reduce(:ok, fn
      {key, value}, :ok ->
        case find_param_spec(key, spec) do
          {:required, type} ->
            validate_type(value, type, key)
          
          {:optional, type, _default} ->
            validate_type(value, type, key)
          
          nil ->
            # Parameter not in spec - only error if spec doesn't allow variable keywords
            if allows_variable_keywords?(spec) do
              :ok
            else
              {:error, {:unknown_parameter, key}}
            end
        end
      
      _other, error ->
        error
    end)
  end

  defp find_param_spec(key, spec) do
    Keyword.get(spec, key)
  end

  defp allows_variable_keywords?(spec) do
    :variable_keyword in Keyword.values(spec)
  end

  # Type validation functions
  defp validate_type(value, :string, _key) when is_binary(value), do: :ok
  defp validate_type(value, :string, key) do
    {:error, {:invalid_type, key, :string, type_of(value)}}
  end

  defp validate_type(value, :integer, _key) when is_integer(value), do: :ok
  defp validate_type(value, :integer, key) do
    {:error, {:invalid_type, key, :integer, type_of(value)}}
  end

  defp validate_type(value, :float, _key) when is_float(value), do: :ok
  defp validate_type(value, :float, _key) when is_integer(value), do: :ok
  defp validate_type(value, :float, key) do
    {:error, {:invalid_type, key, :float, type_of(value)}}
  end

  defp validate_type(value, :boolean, _key) when is_boolean(value), do: :ok
  defp validate_type(value, :boolean, key) do
    {:error, {:invalid_type, key, :boolean, type_of(value)}}
  end

  defp validate_type(value, :atom, _key) when is_atom(value), do: :ok
  defp validate_type(value, :atom, key) do
    {:error, {:invalid_type, key, :atom, type_of(value)}}
  end

  defp validate_type(value, :list, _key) when is_list(value), do: :ok
  defp validate_type(value, :list, key) do
    {:error, {:invalid_type, key, :list, type_of(value)}}
  end

  defp validate_type(value, {:list, element_type}, key) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce(:ok, fn
      {elem, _index}, :ok ->
        validate_type(elem, element_type, key)
      
      _other, error ->
        error
    end)
  end
  defp validate_type(value, {:list, _element_type}, key) do
    {:error, {:invalid_type, key, :list, type_of(value)}}
  end

  defp validate_type(value, :map, _key) when is_map(value), do: :ok
  defp validate_type(value, :map, key) do
    {:error, {:invalid_type, key, :map, type_of(value)}}
  end

  defp validate_type(value, :tuple, _key) when is_tuple(value), do: :ok
  defp validate_type(value, :tuple, key) do
    {:error, {:invalid_type, key, :tuple, type_of(value)}}
  end

  defp validate_type(%module{}, {:struct, module}, _key), do: :ok
  defp validate_type(%{__struct__: _}, {:struct, module}, key) do
    {:error, {:invalid_struct_type, key, module}}
  end
  defp validate_type(_value, {:struct, module}, key) do
    {:error, {:invalid_type, key, {:struct, module}, :not_a_struct}}
  end

  defp validate_type(value, :reference, _key) when is_reference(value), do: :ok
  defp validate_type(%{__python_ref__: _}, :reference, _key), do: :ok
  defp validate_type(value, :reference, key) do
    {:error, {:invalid_type, key, :reference, type_of(value)}}
  end

  defp validate_type(_value, :any, _key), do: :ok

  # Utility functions
  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key) when is_binary(key), do: String.to_atom(key)

  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value) do
    if Map.has_key?(value, :__struct__), do: :struct, else: :map
  end
  defp type_of(value) when is_tuple(value), do: :tuple
  defp type_of(value) when is_reference(value), do: :reference
  defp type_of(_value), do: :unknown

  @doc """
  Casts a result from Python to the specified Elixir type.
  
  This function is used to convert Python results to proper Elixir types
  according to the contract specification.
  
  ## Examples
  
      iex> DSPex.Contract.Validation.cast_result("hello", :string)
      {:ok, "hello"}
      
      iex> DSPex.Contract.Validation.cast_result(42, :float)
      {:ok, 42.0}
      
      iex> DSPex.Contract.Validation.cast_result(%{"answer" => "test"}, {:struct, MyStruct})
      {:ok, %MyStruct{answer: "test"}}
  """
  @spec cast_result(any(), atom() | tuple()) :: {:ok, any()} | {:error, term()}
  def cast_result(value, type) do
    start_time = System.monotonic_time()
    metadata = %{
      input_type: type_of(value),
      target_type: type
    }
    
    :telemetry.execute(
      [:dspex, :types, :cast, :start],
      %{system_time: System.system_time()},
      metadata
    )
    
    result = DSPex.Contracts.TypeCasting.cast_result(value, type)
    
    duration = System.monotonic_time() - start_time
    
    case result do
      {:ok, _} ->
        :telemetry.execute(
          [:dspex, :types, :cast, :stop],
          %{duration: duration, system_time: System.system_time()},
          Map.put(metadata, :success, true)
        )
        
      {:error, reason} ->
        :telemetry.execute(
          [:dspex, :types, :cast, :exception],
          %{duration: duration, system_time: System.system_time()},
          Map.merge(metadata, %{success: false, error: reason})
        )
    end
    
    result
  end
end
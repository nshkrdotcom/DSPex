defmodule DSPex.Contracts.Wrapper do
  @moduledoc """
  Macro for generating wrapper functions with contract validation.
  
  This module provides macros to generate type-safe wrapper functions
  that validate inputs and cast outputs according to contract specifications.
  
  ## Usage
  
      defmodule MyWrapper do
        use DSPex.Contracts.Wrapper
        
        defwrapper :predict, 
          contract: MyContract,
          method: :predict,
          validate_input: true,
          cast_output: true
      end
  
  The generated wrapper will:
  1. Validate input parameters against the contract
  2. Call the underlying Python method
  3. Cast the result to the specified return type
  """

  @doc """
  Generates a wrapper function with contract validation.
  
  ## Options
  
  - `:contract` - The contract module to use for validation
  - `:method` - The method name in the contract
  - `:validate_input` - Whether to validate input parameters (default: true)
  - `:cast_output` - Whether to cast the output to the contract's return type (default: true)
  """
  defmacro defwrapper(name, opts) do
    contract = Keyword.fetch!(opts, :contract)
    method = Keyword.get(opts, :method, name)
    validate_input = Keyword.get(opts, :validate_input, true)
    cast_output = Keyword.get(opts, :cast_output, true)
    
    quote do
      def unquote(name)(ref, params \\ %{}) do
        contract_module = unquote(contract)
        method_name = unquote(method)
        
        with {:ok, method_spec} <- get_method_spec(contract_module, method_name),
             {:ok, validated_params} <- maybe_validate_params(
               params, 
               method_spec.params, 
               unquote(validate_input)
             ),
             {:ok, result} <- call_python_method(
               ref, 
               method_spec.python_name, 
               validated_params
             ),
             {:ok, typed_result} <- maybe_cast_result(
               result, 
               method_spec.returns, 
               unquote(cast_output)
             ) do
          {:ok, typed_result}
        end
      end
      
      defp get_method_spec(contract_module, method_name) do
        case contract_module.get_method_spec(method_name) do
          {:ok, spec} -> {:ok, spec}
          {:error, :method_not_found} -> 
            {:error, {:unknown_method, method_name, contract_module}}
          error -> error
        end
      end
      
      defp maybe_validate_params(params, spec, true) do
        DSPex.Contract.Validation.validate_params(params, spec)
        |> case do
          :ok -> {:ok, params}
          error -> error
        end
      end
      defp maybe_validate_params(params, _spec, false), do: {:ok, params}
      
      defp call_python_method(ref, python_name, params) do
        DSPex.Bridge.call_method(ref, to_string(python_name), params)
      end
      
      defp maybe_cast_result(result, type, true) do
        DSPex.Contracts.TypeCasting.cast_result(result, type)
      end
      defp maybe_cast_result(result, _type, false), do: {:ok, result}
    end
  end

  @doc """
  Use macro that imports the necessary functions and macros.
  """
  defmacro __using__(opts) do
    contract = Keyword.get(opts, :contract)
    
    quote do
      import DSPex.Contracts.Wrapper
      
      if unquote(contract) do
        @contract unquote(contract)
      end
      
      @doc """
      Generates a validated wrapper function for a contract method.
      
      The wrapper will validate inputs and cast outputs according to
      the contract specification.
      """
      defmacro generate_wrapper(name, opts \\ []) do
        contract_module = Keyword.get(opts, :contract) || @contract
        
        unless contract_module do
          raise ArgumentError, "Contract must be specified either in use options or in generate_wrapper"
        end
        
        DSPex.Contracts.Wrapper.defwrapper(name, Keyword.put(opts, :contract, contract_module))
      end
    end
  end
end
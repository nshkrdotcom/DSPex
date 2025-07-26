defmodule DSPex.Bridge.ContractBased do
  @moduledoc """
  Macro for generating typed wrapper functions from contracts.
  
  This module reads method definitions from a contract module and generates
  properly typed wrapper functions that validate parameters and delegate
  to the underlying bridge implementation.
  """
  
  @doc """
  Use a contract to generate typed wrapper functions.
  
  ## Examples
  
      defmodule DSPex.Predict do
        use DSPex.Bridge.ContractBased
        use_contract DSPex.Contracts.Predict
      end
  """
  defmacro use_contract(contract_module) do
    contract_mod = Macro.expand(contract_module, __CALLER__)
    methods = contract_mod.__methods__()
    python_class = contract_mod.python_class()
    
    quote do
      @contract_module unquote(contract_module)
      @python_class unquote(python_class)
      
      # Generate functions for each method in the contract
      unquote(for {method_name, method_spec} <- methods do
        case method_name do
          :create ->
            # Special handling for constructor methods
            quote do
              def create(params \\ %{}, opts \\ []) do
              validated_result = DSPex.Contract.Validation.validate_params(
                params, 
                unquote(Macro.escape(method_spec.params))
              )
              
              case validated_result do
                :ok ->
                  # Use the normalized params from validation
                  normalized_params = normalize_params(params)
                  DSPex.Bridge.create_instance(@python_class, normalized_params, opts)
                  
                {:error, reason} ->
                  {:error, reason}
              end
            end
            end
            
          name ->
            # Regular method calls
            quote do
              def unquote(name)(instance_ref, params \\ %{}, opts \\ []) do
              validated_result = DSPex.Contract.Validation.validate_params(
                params, 
                unquote(Macro.escape(method_spec.params))
              )
              
              case validated_result do
                :ok ->
                  # Use the normalized params from validation
                  normalized_params = normalize_params(params)
                  
                  result = DSPex.Bridge.call_method(
                    instance_ref,
                    unquote(to_string(method_spec.python_name)),
                    normalized_params,
                    opts
                  )
                  
                  # Transform result using the type casting system
                  case result do
                    {:ok, raw_result} ->
                      DSPex.Contracts.TypeCasting.cast_result(
                        raw_result, 
                        unquote(Macro.escape(method_spec.returns))
                      )
                    error -> 
                      error
                  end
                  
                {:error, reason} ->
                  {:error, reason}
              end
            end
            end
        end
      end)
      
      # Helper to generate wrapper methods based on contract methods
      @doc false
      def __contract_module__, do: @contract_module
      
      @doc false
      def __python_class__, do: @python_class
      
      # Normalize params to map format
      defp normalize_params(params) when is_map(params), do: params
      defp normalize_params(params) when is_list(params), do: Map.new(params)
    end
  end
  
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge.ContractBased, only: [use_contract: 1]
    end
  end
end
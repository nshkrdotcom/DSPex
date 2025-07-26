defmodule DSPex.Contracts do
  @moduledoc """
  Base module for contract-driven DSPy integration.
  
  Provides the foundation for strongly-typed contracts that replace
  stringly-typed method calls with compile-time validated operations.
  """
  
  defmacro __using__(_opts) do
    quote do
      import DSPex.Contracts
      Module.register_attribute(__MODULE__, :methods, accumulate: true)
      Module.register_attribute(__MODULE__, :python_class, [])
      Module.register_attribute(__MODULE__, :contract_version, [])
      
      @before_compile DSPex.Contracts
    end
  end
  
  defmacro __before_compile__(env) do
    methods = Module.get_attribute(env.module, :methods)
    python_class = Module.get_attribute(env.module, :python_class)
    
    quote do
      def __contract_metadata__ do
        %{
          python_class: unquote(python_class),
          methods: unquote(Macro.escape(methods)),
          contract_version: @contract_version
        }
      end
      
      def validate_method(method_name) do
        methods = unquote(Macro.escape(methods))
        Enum.any?(methods, fn {name, _} -> name == method_name end)
      end
      
      def get_method_spec(method_name) do
        methods = unquote(Macro.escape(methods))
        Enum.find_value(methods, fn 
          {^method_name, spec} -> {:ok, spec}
          _ -> nil
        end) || {:error, :method_not_found}
      end
    end
  end
  
  @doc """
  Define a method contract for a DSPy component.
  
  ## Examples
  
      defmethod :create, :__init__,
        params: [
          signature: {:required, :string}
        ],
        returns: :reference
  """
  defmacro defmethod(name, python_name, opts) do
    quote bind_quoted: [name: name, python_name: python_name, opts: opts] do
      method_spec = %{
        name: name,
        python_name: python_name,
        params: Keyword.get(opts, :params, []),
        returns: Keyword.get(opts, :returns, :any),
        description: Keyword.get(opts, :description)
      }
      
      @methods {name, method_spec}
      
      # Generate the typed method
      def unquote(name)(ref, params \\ %{}) do
        method_spec = unquote(Macro.escape(method_spec))
        
        with {:ok, validated_params} <- DSPex.Contracts.Validation.validate_params(
               params, 
               method_spec.params
             ),
             {:ok, result} <- DSPex.Bridge.call_method(
               ref, 
               to_string(method_spec.python_name), 
               validated_params
             ),
             {:ok, typed_result} <- DSPex.Contracts.TypeCasting.cast_result(
               result, 
               method_spec.returns
             ) do
          {:ok, typed_result}
        end
      end
    end
  end
  
  @doc """
  Define the Python class this contract maps to.
  """
  defmacro python_class(class_name) do
    quote do
      @python_class unquote(class_name)
    end
  end
  
  @doc """
  Define the contract version for compatibility tracking.
  """
  defmacro contract_version(version) do
    quote do
      @contract_version unquote(version)
    end
  end
end
defmodule DSPex.Contract do
  @moduledoc """
  Defines the contract behaviour for Python class wrappers.
  
  Contracts provide explicit, version-controlled specifications for Python APIs,
  enabling compile-time validation and type safety without requiring Python
  at build time.
  
  ## Creating a Contract
  
      defmodule DSPex.Contracts.Predict do
        use DSPex.Contract
        
        @python_class "dspy.Predict"
        @contract_version "1.0.0"
        
        defmethod :create, :__init__,
          params: [
            signature: {:required, :string}
          ],
          returns: :reference
          
        defmethod :predict, :__call__,
          params: [
            question: {:required, :string}
          ],
          returns: {:struct, DSPex.Types.Prediction}
      end
  """
  
  @doc """
  Returns the Python class this contract represents.
  """
  @callback python_class() :: String.t()
  
  @doc """
  Returns the contract version for compatibility tracking.
  """
  @callback contract_version() :: String.t()
  
  @doc """
  Returns all method definitions as a keyword list.
  """
  @callback __methods__() :: [{atom(), map()}]
  
  @doc """
  Validates arguments for the create/initialization method.
  """
  @callback validate_create_args(args :: map()) :: :ok | {:error, term()}
  
  @doc """
  Validates arguments for a specific method.
  """
  @callback validate_method_args(method :: atom(), args :: map()) :: :ok | {:error, term()}
  
  defmacro __using__(_opts) do
    quote do
      @behaviour DSPex.Contract
      
      # Accumulate method definitions
      Module.register_attribute(__MODULE__, :methods, accumulate: true)
      
      # Import the defmethod macro
      import DSPex.Contract
      
      # Default implementations
      @impl DSPex.Contract
      def contract_version, do: @contract_version || "1.0.0"
      
      @impl DSPex.Contract
      def python_class, do: @python_class
      
      @impl DSPex.Contract
      def validate_create_args(args) do
        case get_method_spec(:create) do
          nil -> :ok
          spec -> DSPex.Contract.Validation.validate_params(args, spec.params)
        end
      end
      
      @impl DSPex.Contract
      def validate_method_args(method, args) do
        case get_method_spec(method) do
          nil -> {:error, {:unknown_method, method}}
          spec -> DSPex.Contract.Validation.validate_params(args, spec.params)
        end
      end
      
      defp get_method_spec(method) do
        __methods__()
        |> Keyword.get(method)
      end
      
      @before_compile DSPex.Contract
    end
  end
  
  @doc """
  Define a method in the contract.
  
  ## Parameters
  
  - `elixir_name` - The name of the Elixir function to generate
  - `python_name` - The corresponding Python method name
  - `opts` - Method specification:
    - `:params` - Parameter specifications
    - `:returns` - Return type specification
    
  ## Parameter Specifications
  
  - `{:required, type}` - Required parameter
  - `{:optional, type, default}` - Optional parameter with default
  - `:variable_keyword` - Accept any keyword arguments
  
  ## Type Specifications
  
  - `:string` - Binary string
  - `:integer` - Integer
  - `:float` - Float
  - `:boolean` - Boolean
  - `:map` - Generic map
  - `:list` - Generic list
  - `{:list, type}` - Typed list
  - `{:struct, module}` - Elixir struct
  - `:reference` - Python object reference
  """
  defmacro defmethod(elixir_name, python_name, opts) do
    quote do
      @methods {unquote(elixir_name), %{
        python_name: unquote(python_name),
        params: unquote(opts[:params]),
        returns: unquote(opts[:returns])
      }}
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      @impl DSPex.Contract
      def __methods__ do
        # Return methods as a keyword list of {name, spec}
        @methods
        |> Enum.reverse()  # Reverse to maintain definition order
      end
    end
  end
end
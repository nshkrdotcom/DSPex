defmodule DSPex.Bridge.SimpleWrapper do
  @moduledoc """
  Simple macro for wrapping Python classes with minimal boilerplate.
  
  This is the foundation for all other wrapper behaviors. It generates
  basic `create` and `call` functions for interacting with Python objects.
  
  ## Usage
  
      defmodule MyPredictor do
        use DSPex.Bridge.SimpleWrapper
        
        wrap_dspy "dspy.Predict"
      end
      
  This generates:
  - `create/0` and `create/1` for creating instances
  - `call/2` and `call/3` for calling methods
  - Common helper methods like `__call__/2` and `forward/2`
  """
  
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge.SimpleWrapper
      
      # Store the Python class path
      Module.register_attribute(__MODULE__, :python_class, persist: true)
      
      # Initialize behaviors list
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :simple_wrapper
    end
  end
  
  @doc """
  Generate wrapper functions for a Python class.
  
  ## Parameters
  
  - `python_class` - The fully qualified Python class name (e.g., "dspy.Predict")
  
  ## Generated Functions
  
  - `create(args \\\\ %{})` - Creates a new instance
  - `call(ref, method, args \\\\ %{})` - Calls a method on an instance
  - `__call__(ref, args)` - Convenience for calling `__call__`
  - `forward(ref, args)` - Convenience for calling `forward`
  - `__python_class__()` - Returns the wrapped Python class name
  """
  defmacro wrap_dspy(python_class) do
    quote do
      @python_class unquote(python_class)
      
      @doc """
      Create a new instance of #{unquote(python_class)}.
      
      ## Parameters
      
      - `args` - Initialization arguments as a map
      
      ## Returns
      
      - `{:ok, ref}` - Reference to the created Python object
      - `{:error, reason}` - If creation fails
      """
      def create(args \\ %{}) do
        # The orchestrator will enhance this with behaviors
        DSPex.Bridge.WrapperOrchestrator.handle_create(
          __MODULE__,
          @python_class,
          args,
          @dspex_behaviors
        )
      end
      
      @doc """
      Call a method on the Python instance.
      
      ## Parameters
      
      - `ref` - Reference to the Python object
      - `method` - Method name as a string
      - `args` - Method arguments as a map
      
      ## Returns
      
      - `{:ok, result}` - The method result
      - `{:error, reason}` - If the call fails
      """
      def call(ref, method, args \\ %{}) when is_binary(method) do
        # The orchestrator will enhance this with behaviors
        DSPex.Bridge.WrapperOrchestrator.handle_call(
          __MODULE__,
          ref,
          method,
          args,
          @dspex_behaviors
        )
      end
      
      @doc """
      Call the __call__ method (common in Python).
      """
      def __call__(ref, args), do: call(ref, "__call__", args)
      
      @doc """
      Call the forward method (common in DSPy).
      """
      def forward(ref, args), do: call(ref, "forward", args)
      
      @doc """
      Get the wrapped Python class name.
      """
      def __python_class__, do: @python_class
      
      @doc false
      def __dspex_behaviors__, do: @dspex_behaviors
    end
  end
end
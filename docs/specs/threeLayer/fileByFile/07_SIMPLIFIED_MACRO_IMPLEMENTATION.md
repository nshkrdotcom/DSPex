# Simplified Macro Implementation Guide

## From God Macro to Simple Helpers

This guide shows how to implement the simplified, composable macro system that replaces the monolithic `defdsyp`.

## Core Philosophy

1. **Do One Thing Well**: Each macro has a single, clear purpose
2. **Compose, Don't Configure**: Build complex behavior by combining simple pieces
3. **Explicit Over Implicit**: Show what's generated, hide nothing
4. **Standard Elixir**: Use patterns Elixir developers already know

## Implementation Order

### Step 1: Define Core Behaviors

Start with the behavior contracts that define extension points:

```elixir
# lib/dspex/bridge/behaviours/bidirectional.ex
defmodule DSPex.Bridge.Behaviours.Bidirectional do
  @moduledoc """
  Behavior for modules that support Python → Elixir callbacks.
  """
  
  @doc """
  Returns list of tools available to Python.
  Each tool is a {name, function} tuple.
  """
  @callback elixir_tools() :: [{String.t(), function()}]
  
  @doc """
  Called when Python invokes an Elixir tool.
  Useful for logging, monitoring, or preprocessing.
  """
  @callback on_python_callback(tool_name :: String.t(), args :: map(), session_context :: map()) :: 
    :ok | {:error, term()}
    
  @optional_callbacks [on_python_callback: 3]
end

# lib/dspex/bridge/behaviours/observable.ex
defmodule DSPex.Bridge.Behaviours.Observable do
  @moduledoc """
  Behavior for modules that emit custom telemetry.
  """
  
  @doc """
  Returns metadata to include with telemetry events.
  """
  @callback telemetry_metadata(operation :: atom(), args :: map()) :: map()
  
  @doc """
  Called before operation execution.
  """
  @callback before_execute(operation :: atom(), args :: map()) :: :ok | {:error, term()}
  
  @doc """
  Called after operation execution.
  """
  @callback after_execute(operation :: atom(), args :: map(), result :: term()) :: :ok
  
  @optional_callbacks [before_execute: 2, after_execute: 3]
end

# lib/dspex/bridge/behaviours/result_transform.ex
defmodule DSPex.Bridge.Behaviours.ResultTransform do
  @moduledoc """
  Behavior for transforming Python results to Elixir types.
  """
  
  @doc """
  Transform raw Python result into domain type.
  """
  @callback transform_result(python_result :: map()) :: term()
  
  @doc """
  Transform Elixir input for Python consumption.
  """
  @callback transform_input(elixir_input :: map()) :: map()
  
  @optional_callbacks [transform_input: 1]
end
```

### Step 2: Implement SimpleWrapper

The most basic macro - just generates wrapper functions:

```elixir
# lib/dspex/bridge/simple_wrapper.ex
defmodule DSPex.Bridge.SimpleWrapper do
  @moduledoc """
  Simple macro for wrapping Python classes.
  Generates basic create/call functions.
  """
  
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge.SimpleWrapper
      
      # Store the Python class path
      Module.register_attribute(__MODULE__, :python_class, persist: true)
    end
  end
  
  @doc """
  Generate wrapper functions for a Python class.
  
  ## Example
  
      use DSPex.Bridge.SimpleWrapper
      wrap_dspy "dspy.Predict"
  
  Generates:
  - create/0, create/1 - Create new instance
  - call/2, call/3 - Call methods on instance
  - Helper functions for common methods
  """
  defmacro wrap_dspy(python_class) do
    quote do
      @python_class unquote(python_class)
      
      @doc """
      Create a new instance of #{unquote(python_class)}.
      """
      def create(args \\ %{}) do
        DSPex.Bridge.create_instance(@python_class, args)
      end
      
      @doc """
      Call a method on the instance.
      """
      def call(ref, method, args \\ %{}) when is_binary(method) do
        DSPex.Bridge.call_method(ref, method, args)
      end
      
      # Common convenience methods
      def __call__(ref, args), do: call(ref, "__call__", args)
      def forward(ref, args), do: call(ref, "forward", args)
      
      # Module metadata
      def __python_class__, do: @python_class
    end
  end
end
```

### Step 3: Add Bidirectional Support

Enable Python → Elixir callbacks:

```elixir
# lib/dspex/bridge/bidirectional.ex
defmodule DSPex.Bridge.Bidirectional do
  @moduledoc """
  Adds bidirectional communication to wrapped modules.
  """
  
  alias DSPex.Bridge.Behaviours
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Behaviours.Bidirectional
      
      # Default implementation
      @impl Behaviours.Bidirectional
      def on_python_callback(_tool_name, _args, _session_context), do: :ok
      
      defoverridable [on_python_callback: 3]
      
      # Override create to register tools
      def create(args \\ %{}) do
        case super(args) do
          {:ok, ref} = success ->
            # Register tools with the session
            DSPex.Bridge.register_tools(ref, elixir_tools())
            success
            
          error ->
            error
        end
      end
      
      defoverridable [create: 0, create: 1]
    end
  end
end
```

### Step 4: Add Observable Features

Automatic telemetry for all operations:

```elixir
# lib/dspex/bridge/observable.ex
defmodule DSPex.Bridge.Observable do
  @moduledoc """
  Adds comprehensive telemetry to wrapped modules.
  """
  
  alias DSPex.Bridge.Behaviours
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Behaviours.Observable
      
      # Default implementations
      @impl Behaviours.Observable
      def telemetry_metadata(_operation, _args), do: %{}
      
      @impl Behaviours.Observable
      def before_execute(_operation, _args), do: :ok
      
      @impl Behaviours.Observable  
      def after_execute(_operation, _args, _result), do: :ok
      
      defoverridable [telemetry_metadata: 2, before_execute: 2, after_execute: 3]
      
      # Wrap create with telemetry
      def create(args \\ %{}) do
        metadata = telemetry_metadata(:create, args)
        
        :telemetry.span(
          [:dspex, :wrapper, :create],
          metadata,
          fn ->
            before_execute(:create, args)
            result = super(args)
            after_execute(:create, args, result)
            {result, metadata}
          end
        )
      end
      
      # Wrap call with telemetry
      def call(ref, method, args \\ %{}) do
        metadata = telemetry_metadata(:call, Map.put(args, :method, method))
        
        :telemetry.span(
          [:dspex, :wrapper, :call],
          metadata,
          fn ->
            before_execute(:call, args)
            result = super(ref, method, args)
            after_execute(:call, args, result)
            {result, metadata}
          end
        )
      end
      
      defoverridable [create: 0, create: 1, call: 2, call: 3]
    end
  end
end
```

### Step 5: Schema Discovery

Compile-time validation and type generation:

```elixir
# lib/dspex/bridge/schema_aware.ex
defmodule DSPex.Bridge.SchemaAware do
  @moduledoc """
  Discovers Python class schema at compile time and generates typed functions.
  """
  
  defmacro discover_schema(python_class, opts \\ []) do
    # This runs at compile time
    schema = fetch_schema_at_compile_time(python_class, opts)
    
    # Generate functions for each method
    method_defs = for {method_name, spec} <- schema.methods do
      generate_method_def(python_class, method_name, spec)
    end
    
    quote do
      # Store schema for runtime access
      @schema unquote(Macro.escape(schema))
      def __schema__, do: @schema
      
      # Generated typed methods
      unquote_splicing(method_defs)
    end
  end
  
  defp fetch_schema_at_compile_time(python_class, opts) do
    # Start temporary Python process during compilation
    case DSPex.Bridge.SchemaIntrospector.introspect(python_class, opts) do
      {:ok, schema} -> schema
      {:error, reason} -> 
        raise CompileError, "Failed to introspect #{python_class}: #{inspect(reason)}"
    end
  end
  
  defp generate_method_def(python_class, method_name, spec) do
    # Convert Python method name to Elixir function name
    elixir_name = pythonic_to_elixir(method_name)
    param_specs = generate_param_specs(spec.params)
    
    quote do
      @doc unquote(spec.doc || "Calls #{method_name} on #{python_class}")
      @spec unquote(elixir_name)(reference(), unquote_splicing(param_specs)) :: 
        {:ok, unquote(spec.return_type)} | {:error, term()}
        
      def unquote(elixir_name)(ref, unquote_splicing(generate_params(spec.params))) do
        args = unquote(generate_args_map(spec.params))
        
        case call(ref, unquote(method_name), args) do
          {:ok, result} -> {:ok, unquote(transform_result(spec.return_type, quote do result end))}
          error -> error
        end
      end
    end
  end
  
  # ... helper functions for code generation
end
```

### Step 6: Usage Examples

Show how the pieces compose:

```elixir
# Example 1: Simple wrapper
defmodule MyApp.BasicPredict do
  use DSPex.Bridge.SimpleWrapper
  
  wrap_dspy "dspy.Predict"
end

# Usage:
{:ok, predictor} = MyApp.BasicPredict.create(%{signature: "question -> answer"})
{:ok, result} = MyApp.BasicPredict.__call__(predictor, %{question: "What is AI?"})

# Example 2: With telemetry
defmodule MyApp.ObservablePredict do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.Observable
  
  wrap_dspy "dspy.Predict"
  
  @impl DSPex.Bridge.Observable
  def telemetry_metadata(:call, %{method: "__call__"} = args) do
    %{
      question_length: String.length(args[:question] || ""),
      timestamp: System.system_time(:millisecond)
    }
  end
end

# Example 3: With bidirectional support
defmodule MyApp.EnhancedPredict do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.Bidirectional
  
  wrap_dspy "dspy.Predict"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_answer", &MyApp.Validators.validate_answer/1},
      {"enhance_prompt", &MyApp.Enhancers.enhance_prompt/1}
    ]
  end
end

# Example 4: Full featured with schema
defmodule MyApp.TypedChainOfThought do
  use DSPex.Bridge.SchemaAware
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.Observable
  
  discover_schema "dspy.ChainOfThought"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_reasoning", &validate_reasoning_steps/1},
      {"fetch_context", &fetch_relevant_context/1}
    ]
  end
  
  @impl DSPex.Bridge.Observable
  def telemetry_metadata(:call, args) do
    %{
      has_context: Map.has_key?(args, :context),
      reasoning_type: args[:rationale_type] || "default"
    }
  end
  
  defp validate_reasoning_steps(%{"steps" => steps}) do
    length(steps) >= 3 && Enum.all?(steps, &(String.length(&1) > 20))
  end
  
  defp fetch_relevant_context(%{"question" => question}) do
    # Fetch from database, API, etc.
    %{
      "domain" => "AI",
      "examples" => ["Example 1", "Example 2"]
    }
  end
end
```

### Step 7: Testing the Macros

Comprehensive tests for each macro:

```elixir
# test/dspex/bridge/simple_wrapper_test.exs
defmodule DSPex.Bridge.SimpleWrapperTest do
  use ExUnit.Case
  
  defmodule TestWrapper do
    use DSPex.Bridge.SimpleWrapper
    wrap_dspy "test.Component"
  end
  
  test "generates create function" do
    assert function_exported?(TestWrapper, :create, 0)
    assert function_exported?(TestWrapper, :create, 1)
  end
  
  test "generates call functions" do
    assert function_exported?(TestWrapper, :call, 2)
    assert function_exported?(TestWrapper, :call, 3)
    assert function_exported?(TestWrapper, :__call__, 2)
    assert function_exported?(TestWrapper, :forward, 2)
  end
  
  test "stores Python class" do
    assert TestWrapper.__python_class__() == "test.Component"
  end
end

# test/dspex/bridge/observable_test.exs
defmodule DSPex.Bridge.ObservableTest do
  use ExUnit.Case
  
  defmodule ObservableWrapper do
    use DSPex.Bridge.SimpleWrapper
    use DSPex.Bridge.Observable
    
    wrap_dspy "test.Component"
    
    @impl DSPex.Bridge.Observable
    def telemetry_metadata(:create, _args) do
      %{test: true}
    end
  end
  
  test "emits telemetry on create" do
    {:ok, events} = with_telemetry(fn ->
      ObservableWrapper.create(%{test: "data"})
    end)
    
    assert {:create, measurements, metadata} = find_event(events, [:dspex, :wrapper, :create])
    assert metadata.test == true
    assert measurements.duration > 0
  end
end
```

## Migration Path

### From Old defdsyp

```elixir
# OLD - Everything in one macro
defdsyp MyModule, "dspy.ChainOfThought", %{
  enhanced_mode: true,
  elixir_tools: ["validate", "enhance"],
  result_transform: &transform_result/1,
  telemetry: true
}
```

### To New Composition

```elixir
# NEW - Clear, composable pieces
defmodule MyModule do
  use DSPex.Bridge.SimpleWrapper      # Basic wrapping
  use DSPex.Bridge.Bidirectional      # Tool support
  use DSPex.Bridge.Observable         # Telemetry
  use DSPex.Bridge.ResultTransform    # Transformations
  
  wrap_dspy "dspy.ChainOfThought"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate", &OldModule.validate/1},
      {"enhance", &OldModule.enhance/1}
    ]
  end
  
  @impl DSPex.Bridge.ResultTransform
  def transform_result(result) do
    OldModule.transform_result(result)
  end
end
```

## Benefits Realized

### 1. Understandable
- Each macro is < 100 lines
- Clear what code is generated
- Standard Elixir patterns

### 2. Testable
- Test each behavior separately
- Mock at behavior boundaries
- No macro magic to debug

### 3. Composable
- Use only what you need
- Mix and match features
- Extend with new behaviors

### 4. Maintainable
- Fix bugs in one place
- Add features without breaking others
- Clear separation of concerns

## Summary

The simplified macro system:
1. **Breaks Apart Complexity**: God macro → focused behaviors
2. **Enables Understanding**: See what's generated
3. **Promotes Composition**: Build complex from simple
4. **Follows Elixir Idioms**: Behaviors, protocols, and macros

The result is more powerful yet easier to understand and maintain.
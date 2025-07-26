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
      
      # Instead of using super, inject behavior through module attributes
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :bidirectional
      
      # The wrapper macro will orchestrate all behaviors
      # No fragile super chains!
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
      
      # Register this behavior
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :observable
    end
  end
end
```

### Step 5: Behavior Orchestration (No Super!)

Instead of fragile `super` chains, the wrapper macro orchestrates behaviors:

```elixir
defmodule DSPex.Bridge.WrapperOrchestrator do
  @moduledoc """
  Orchestrates multiple behaviors without relying on super.
  Order-independent and explicit.
  """
  
  def generate_create_function(behaviors) do
    quote do
      def create(args \\ %{}) do
        # Collect all behavior metadata
        behaviors = @dspex_behaviors
        
        # Pre-execution hooks
        if :observable in behaviors do
          metadata = telemetry_metadata(:create, args)
          :telemetry.execute([:dspex, :wrapper, :create, :start], %{}, metadata)
        end
        
        # Core execution
        result = DSPex.Bridge.create_instance(@python_class, args)
        
        # Post-execution hooks
        with {:ok, ref} = result do
          if :bidirectional in behaviors do
            DSPex.Bridge.register_tools(ref, elixir_tools())
          end
        end
        
        # Telemetry completion
        if :observable in behaviors do
          :telemetry.execute([:dspex, :wrapper, :create, :stop], 
            %{duration: 0}, Map.put(metadata, :success, match?({:ok, _}, result)))
        end
        
        result
      end
    end
  end
  
  def generate_call_function(behaviors) do
    # Similar orchestration for call/3
  end
end
```

This approach:
- **No super chains**: Each behavior is independent
- **Order doesn't matter**: Use statements can be in any order
- **Explicit flow**: You can see exactly what happens when
- **Easy to extend**: Add new behaviors without touching existing ones

### Step 6: Contract-Based Wrapper

Use explicit contracts instead of runtime discovery:

```elixir
# lib/dspex/bridge/contract_based.ex
defmodule DSPex.Bridge.ContractBased do
  @moduledoc """
  Uses explicit contract modules to generate typed functions.
  No Python needed at compile time!
  """
  
  defmacro use_contract(contract_module) do
    quote do
      # Import the contract's method definitions
      @contract_module unquote(contract_module)
      @python_class @contract_module.python_class()
      
      # Register as contract-based
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :contract_based
      
      # Generate functions from contract
      for {method_name, method_def} <- @contract_module.__methods__() do
        DSPex.Bridge.ContractBased.generate_method(__MODULE__, method_name, method_def)
      end
    end
  end
  
  def generate_method(module, method_name, method_def) do
    # Generate properly typed function from contract definition
    # This happens at compile time but doesn't need Python!
  end
end
```

### Step 7: Mix Task for Contract Generation

Helper tool for developers (not used at compile time):

```elixir
defmodule Mix.Tasks.Dspex.Gen.Contract do
  use Mix.Task
  
  @shortdoc "Generate a contract template from Python class"
  
  @moduledoc """
  Generates an Elixir contract module from a Python class.
  
  This is a development tool - the generated contract becomes
  the source of truth and is checked into version control.
  
  Usage:
      mix dspex.gen.contract dspy.Predict --out lib/contracts/predict.ex
  """
  
  def run(args) do
    {opts, [python_class], _} = OptionParser.parse(args, 
      strict: [out: :string, force: :boolean])
    
    # Start Python and introspect (only during development!)
    Mix.Task.run("app.start")
    
    case DSPex.SchemaIntrospector.discover(python_class) do
      {:ok, schema} ->
        content = generate_contract(python_class, schema)
        path = opts[:out] || default_path(python_class)
        
        if File.exists?(path) and not opts[:force] do
          Mix.raise("Contract already exists at #{path}. Use --force to overwrite.")
        end
        
        File.write!(path, content)
        Mix.shell().info("Generated contract at #{path}")
        Mix.shell().info("Please review and customize before committing!")
        
      {:error, reason} ->
        Mix.raise("Failed to introspect #{python_class}: #{inspect(reason)}")
    end
  end
  
  defp generate_contract(python_class, schema) do
    # Generate a well-formatted contract module
    """
    defmodule #{contract_module_name(python_class)} do
      use DSPex.Contract
      
      @moduledoc \"\"\"
      Contract for #{python_class}
      
      Generated on: #{Date.utc_today()}
      
      IMPORTANT: Review and customize this contract!
      - Verify method signatures match your usage
      - Add domain-specific validations
      - Document any version constraints
      \"\"\"
      
      @python_class "#{python_class}"
      @contract_version "1.0.0"
      
      #{Enum.map_join(schema.methods, "\n", &format_method/1)}
    end
    """
  end
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

# Example 4: Full featured with explicit contract
defmodule MyApp.TypedChainOfThought do
  use DSPex.Bridge.ContractBased    # Explicit contract
  use DSPex.Bridge.Bidirectional    # Python callbacks
  use DSPex.Bridge.Observable       # Telemetry
  
  use_contract DSPex.Contracts.ChainOfThought
  
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

# test/dspex/bridge/contract_based_test.exs
defmodule DSPex.Bridge.ContractBasedTest do
  use ExUnit.Case
  
  # Assume DSPex.Contracts.TestComponent exists
  defmodule TestContractWrapper do
    use DSPex.Bridge.ContractBased
    use_contract DSPex.Contracts.TestComponent
  end
  
  test "generates functions from the contract" do
    # Assert that functions defined in the contract are generated
    assert function_exported?(TestContractWrapper, :create, 1)
    assert function_exported?(TestContractWrapper, :process, 2)
  end
  
  test "contract enforces compile-time safety" do
    # This would be in a separate test file to check compile errors
    # The contract system prevents undefined method calls at compile time
  end
  
  test "uses contract metadata" do
    assert TestContractWrapper.__contract_module__() == DSPex.Contracts.TestComponent
    assert TestContractWrapper.__python_class__() == "test.Component"
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
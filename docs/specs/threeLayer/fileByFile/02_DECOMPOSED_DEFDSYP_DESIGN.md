# Decomposed defdsyp Design

## The Problem with the God Macro

The original `defdsyp` macro tried to be everything to everyone:
- Wrapper generation
- State management
- Tool registration
- Result transformation
- "Cognitive" features
- Kitchen sink

This led to:
1. **Incomprehensible code**: 500+ lines of macro magic
2. **Rigid abstractions**: Hard to extend or modify
3. **Poor debugging**: Macro errors are cryptic
4. **Hidden complexity**: Users don't know what's generated

## The Solution: Composition over Configuration

Break the macro into focused, composable parts that users can understand and control.

## Component Architecture

### 1. Basic Wrapper Generation

The simplest case - just wrap a Python class:

```elixir
defmodule MyApp.BasicPredictor do
  use DSPex.Bridge.SimpleWrapper
  
  wrap_dspy "dspy.Predict"
  
  # Generates:
  # def create(signature), do: Bridge.create_instance(@python_class, %{signature: signature})
  # def call(ref, inputs), do: Bridge.call_method(ref, "__call__", inputs)
end
```

### 2. Schema-Aware Wrapper

For compile-time validation and better DX:

```elixir
defmodule MyApp.TypedPredictor do
  use DSPex.Bridge.SchemaAware
  
  discover_schema "dspy.Predict"
  
  # At compile time:
  # 1. Queries Python for class schema
  # 2. Generates typed functions
  # 3. Validates at compile time
  
  # Generated functions match Python API exactly:
  # @spec __init__(String.t()) :: {:ok, reference()} | {:error, term()}
  # def __init__(signature) when is_binary(signature)
  #
  # @spec __call__(reference(), keyword()) :: {:ok, map()} | {:error, term()}
  # def __call__(ref, question: question) when is_binary(question)
end
```

### 3. Bidirectional Communication

Add Python → Elixir callbacks:

```elixir
defmodule MyApp.BidirectionalPredictor do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.Bidirectional
  
  wrap_dspy "dspy.Predict"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_answer", &MyApp.Validators.validate_answer/1},
      {"fetch_context", &MyApp.Context.fetch/1},
      {"apply_rules", &MyApp.Rules.apply/1}
    ]
  end
  
  @impl DSPex.Bridge.Bidirectional
  def on_python_callback(tool_name, args, session_context) do
    # Optional: Hook for logging/monitoring Python callbacks
    Logger.info("Python called #{tool_name}")
    :ok
  end
end
```

### 4. Observable Wrapper

Add comprehensive telemetry:

```elixir
defmodule MyApp.ObservablePredictor do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.Observable
  
  wrap_dspy "dspy.Predict"
  
  @impl DSPex.Bridge.Observable
  def telemetry_metadata(operation, args) do
    %{
      model: args[:model] || "default",
      prompt_length: String.length(args[:question] || ""),
      timestamp: DateTime.utc_now()
    }
  end
  
  # Automatically emits telemetry for:
  # - [:dspex, :wrapper, :call, :start]
  # - [:dspex, :wrapper, :call, :stop]
  # - [:dspex, :wrapper, :call, :exception]
end
```

### 5. Result Transformation

Transform Python results to Elixir-friendly formats:

```elixir
defmodule MyApp.TransformingPredictor do
  use DSPex.Bridge.SimpleWrapper
  use DSPex.Bridge.ResultTransform
  
  wrap_dspy "dspy.Predict"
  
  @impl DSPex.Bridge.ResultTransform
  def transform_result(%{"answer" => answer, "reasoning" => reasoning}) do
    %MyApp.Prediction{
      answer: answer,
      reasoning: parse_reasoning(reasoning),
      confidence: calculate_confidence(answer, reasoning)
    }
  end
  
  defp parse_reasoning(reasoning) do
    # Transform Python reasoning format to domain model
  end
end
```

## Composing Components

The power comes from mixing and matching:

```elixir
defmodule MyApp.FullFeaturedPredictor do
  use DSPex.Bridge.SchemaAware      # Typed API
  use DSPex.Bridge.Bidirectional    # Python callbacks
  use DSPex.Bridge.Observable       # Telemetry
  use DSPex.Bridge.ResultTransform  # Result shaping
  
  discover_schema "dspy.ChainOfThought"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_reasoning", &MyApp.Validators.validate_cot/1},
      {"fetch_examples", &MyApp.Examples.fetch/1}
    ]
  end
  
  @impl DSPex.Bridge.Observable
  def telemetry_metadata(operation, args) do
    %{
      operation: operation,
      has_examples: map_size(args[:examples] || %{}) > 0
    }
  end
  
  @impl DSPex.Bridge.ResultTransform
  def transform_result(result) do
    %MyApp.ChainOfThoughtResult{
      reasoning_steps: parse_steps(result["reasoning"]),
      final_answer: result["answer"],
      metadata: extract_metadata(result)
    }
  end
end
```

## Implementation Strategy

### Phase 1: Core Behaviors

Define the behavior contracts:

```elixir
defmodule DSPex.Bridge.Bidirectional do
  @callback elixir_tools() :: [{String.t(), function()}]
  @callback on_python_callback(String.t(), map(), map()) :: :ok | {:error, term()}
  
  defmacro __using__(_) do
    quote do
      @behaviour DSPex.Bridge.Bidirectional
      
      # Default implementation
      def on_python_callback(_tool, _args, _context), do: :ok
      defoverridable [on_python_callback: 3]
    end
  end
end
```

### Phase 2: Simple Wrapper Macro

The minimal macro that just generates basic functions:

```elixir
defmodule DSPex.Bridge.SimpleWrapper do
  defmacro wrap_dspy(python_class) do
    quote do
      @python_class unquote(python_class)
      
      def create(args \\ %{}) do
        DSPex.Bridge.create_instance(@python_class, args)
      end
      
      def call(ref, method, args) do
        DSPex.Bridge.call_method(ref, method, args)
      end
      
      # Common convenience methods
      def __call__(ref, args), do: call(ref, "__call__", args)
      def forward(ref, args), do: call(ref, "forward", args)
    end
  end
end
```

### Phase 3: Schema Discovery

Build compile-time schema introspection:

```elixir
defmodule DSPex.Bridge.SchemaAware do
  defmacro discover_schema(python_class) do
    # At compile time, start a Python process and introspect
    schema = DSPex.Bridge.SchemaIntrospector.get_schema(python_class)
    
    # Generate functions based on schema
    for {method_name, method_spec} <- schema.methods do
      generate_method(method_name, method_spec)
    end
  end
  
  defp generate_method(name, spec) do
    # Generate typed function with proper spec
  end
end
```

## Migration Path

### From Old defdsyp

```elixir
# Old
defdsyp MyModule, "dspy.Predict", %{
  enhanced_mode: true,
  elixir_tools: ["validate", "transform"],
  result_transform: &transform/1
}
```

### To New Composition

```elixir
# New
defmodule MyModule do
  use DSPex.Bridge.SchemaAware
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.ResultTransform
  
  discover_schema "dspy.Predict"
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate", &OldModule.validate/1},
      {"transform", &OldModule.transform/1}
    ]
  end
  
  @impl DSPex.Bridge.ResultTransform
  def transform_result(result), do: OldModule.transform(result)
end
```

## Benefits

### 1. Understandable Code
- Each component has a single responsibility
- No hidden magic - you see what's generated
- Standard Elixir patterns (behaviors, macros)

### 2. Flexible Composition
- Use only what you need
- Easy to extend with new behaviors
- Mix and match components

### 3. Better Testing
- Test each component in isolation
- Mock behaviors easily
- Clear boundaries

### 4. Improved Debugging
- Smaller macros = better error messages
- Can inspect generated code
- Standard Elixir tools work

### 5. Gradual Migration
- Old defdsyp can coexist
- Migrate module by module
- No big bang required

## Anti-Patterns to Avoid

### 1. Kitchen Sink Behaviors
```elixir
# BAD: One behavior trying to do everything
use DSPex.Bridge.EverythingBehavior
```

### 2. Implicit Magic
```elixir
# BAD: Hidden side effects
use DSPex.Bridge.AutoMagic  # What does this even do?
```

### 3. Compile-Time Coupling
```elixir
# BAD: Too much compile-time dependency
discover_schema "dspy.Predict", 
  validate_at_compile_time: true,
  fail_on_schema_change: true  # Brittle!
```

## Summary

By decomposing the god macro into focused, composable behaviors:
1. **Clarity**: Each piece has a clear purpose
2. **Flexibility**: Compose only what you need
3. **Maintainability**: Smaller, testable units
4. **Migration**: Gradual path from old to new

The result is the same power with less magic, more control, and better understanding.
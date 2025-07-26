# Architectural Principles

## Core Philosophy

This document outlines the fundamental principles guiding the DSPex/Snakepit/SnakepitGrpcBridge architecture. Understanding these principles is essential for making consistent architectural decisions.

## Key Principles

### 1. Elixir is the Source of Truth

All state management (sessions, variables, tool registries) lives in Elixir and is managed by OTP processes. This provides:
- **Fault Tolerance**: OTP supervision trees handle failures gracefully
- **Consistency**: Single source of truth prevents synchronization issues
- **Performance**: ETS tables provide microsecond access times

```elixir
# Good: State managed in Elixir
SessionStore.set_variable(session_id, "temperature", 0.7)

# Bad: State duplicated in Python
# python_bridge.store_variable("temperature", 0.7)
```

### 2. Python Workers are Stateless Ephemeral Cogs

Python processes exist solely for computation. They:
- Hold no state between requests
- Can be killed and restarted without data loss
- Scale horizontally without coordination

```python
# Good: Python worker receives state, computes, returns
def execute_prediction(session_context, inputs):
    temperature = session_context.get_variable("temperature")
    return predict(inputs, temperature=temperature)

# Bad: Python worker maintains state
# class Worker:
#     def __init__(self):
#         self.temperature = 0.7  # NO!
```

### 3. Observability as a Foundation

Every significant action emits telemetry. This isn't "cognitive" magic - it's practical engineering:
- **Performance Monitoring**: Track latency of every operation
- **Error Tracking**: Understand failure patterns
- **Usage Analytics**: See which features are actually used

```elixir
# Every bridge call includes telemetry
def execute(command, args) do
  start_time = System.monotonic_time(:microsecond)
  result = do_work(command, args)
  duration = System.monotonic_time(:microsecond) - start_time
  
  :telemetry.execute([:bridge, :execution], %{duration: duration}, %{
    command: command,
    success: match?({:ok, _}, result)
  })
  
  result
end
```

### 4. Explicit Contracts over Implicit Magic

Clear, explicit code is preferred over clever abstractions:

```elixir
# Good: Explicit module with clear functions
defmodule MyApp.Predictor do
  def create(signature), do: Bridge.create_instance("dspy.Predict", %{signature: signature})
  def execute(ref, question), do: Bridge.call_method(ref, "__call__", %{question: question})
end

# Bad: Magic macro hiding complexity
# defdsyp MyApp.Predictor, "dspy.Predict", enhanced: true, magic: :maximum
```

### 5. Bidirectional Communication is a First-Class Citizen

The killer feature: Python can call back to Elixir for:
- **Business Logic**: Keep domain rules in Elixir
- **Validation**: Leverage Elixir's pattern matching
- **Data Access**: Use Elixir's concurrent data structures

```python
# Python calling Elixir for validation
def enhanced_predict(session_context, inputs):
    # Get prediction from ML model
    prediction = model.predict(inputs)
    
    # Validate using Elixir business logic
    is_valid = session_context.call_elixir_tool("validate_prediction", {
        "prediction": prediction,
        "context": inputs
    })
    
    if not is_valid:
        prediction = session_context.call_elixir_tool("apply_business_rules", {
            "raw_prediction": prediction
        })
    
    return prediction
```

## Why This Architecture?

### The Problem with Traditional Approaches

1. **Unidirectional RPC**: Most Elixir-Python bridges are one-way streets. Elixir calls Python, period.
2. **State Synchronization Hell**: When both sides maintain state, keeping them in sync is a nightmare
3. **Monolithic Python Services**: Python services grow into unmaintainable beasts

### Our Solution

1. **Bidirectional by Design**: Python workers can call back to Elixir naturally
2. **Single Source of Truth**: All state in Elixir, Python is stateless
3. **Modular and Observable**: Small, focused modules with comprehensive telemetry

## Anti-Patterns to Avoid

### 1. State in Python Workers
```python
# NEVER DO THIS
class StatefulWorker:
    def __init__(self):
        self.cache = {}  # State will be lost on restart!
```

### 2. Bypassing the Bridge
```elixir
# NEVER DO THIS
# Direct Python execution bypassing our infrastructure
System.cmd("python", ["script.py", args])
```

### 3. Over-Abstraction
```elixir
# AVOID THIS
defmacro super_magic_dspy(name, path, opts) do
  # 500 lines of macro magic that nobody understands
end
```

### 4. Ignoring Telemetry
```elixir
# BAD: No observability
def execute(cmd, args), do: Worker.run(cmd, args)

# GOOD: Observable
def execute(cmd, args) do
  :telemetry.span([:bridge, :execution], %{cmd: cmd}, fn ->
    {Worker.run(cmd, args), %{}}
  end)
end
```

## Future Evolution

These principles enable future enhancements without architectural changes:

1. **Performance Optimization**: Use telemetry data to route requests to fastest workers
2. **Intelligent Caching**: Cache results based on usage patterns
3. **Failure Recovery**: Learn from error patterns to improve reliability

But these are *concrete engineering improvements*, not vague "AI magic".

## Summary

This architecture succeeds by:
1. Keeping state management simple (all in Elixir)
2. Making Python workers disposable (stateless computation only)
3. Measuring everything (comprehensive telemetry)
4. Being explicit (clear contracts over magic)
5. Enabling bidirectional communication (the killer feature)

Follow these principles, and the system will remain maintainable, scalable, and evolvable.
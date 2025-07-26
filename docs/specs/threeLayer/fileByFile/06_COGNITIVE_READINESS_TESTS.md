# Cognitive Readiness Test Specifications

## Reframing "Cognitive" as Observable Capabilities

Instead of vague "cognitive" features, we define concrete, testable capabilities that demonstrate the system is ready for advanced use cases.

## Test Categories

### 1. Contract System Validation Tests

**Purpose**: Verify the contract-based macro system provides compile-time safety.

```elixir
defmodule SnakepitGrpcBridge.Tests.ContractValidation do
  use ExUnit.Case
  
  test "contract prevents calling undefined methods at compile time" do
    # This should fail to compile
    assert_raise CompileError, fn ->
      defmodule InvalidWrapper do
        use DSPex.Bridge.ContractBased
        use_contract DSPex.Contracts.Predict
        
        # Try to call non-existent method
        def invalid_call(ref) do
          non_existent_method(ref, "arg")  # Contract doesn't define this!
        end
      end
    end
  end
  
  test "contract enforces parameter types" do
    # Define a strict contract
    defmodule StrictContract do
      use DSPex.Contract
      
      defmethod :process, :process,
        params: [count: {:required, :integer}],
        returns: :ok
    end
    
    defmodule StrictWrapper do
      use DSPex.Bridge.ContractBased
      use_contract StrictContract
    end
    
    # This should fail at runtime with clear error
    {:error, {:invalid_type, :integer, "not a number"}} = 
      StrictWrapper.process(ref, count: "not a number")
  end
  
  test "from_python_result transformation is applied" do
    defmodule TransformContract do
      use DSPex.Contract
      
      defmethod :get_data, :get_data,
        params: [],
        returns: {:struct, MyApp.Data}
    end
    
    # Verify the transformation happens automatically
    {:ok, result} = TransformWrapper.get_data(ref)
    assert %MyApp.Data{} = result
    assert result.__struct__ == MyApp.Data
  end
  
  test "contract version checking works" do
    # Contracts can validate compatibility
    assert DSPex.Contracts.Predict.validate_compatibility("2.1.3")
    refute DSPex.Contracts.Predict.validate_compatibility("1.0.0")
  end
end
```

### 2. Performance Baseline Tests

**Purpose**: Establish that the system performs well enough for interactive use.

```elixir
defmodule SnakepitGrpcBridge.Tests.PerformanceBaseline do
  use ExUnit.Case
  
  @tag :performance
  test "simple prediction completes within 100ms" do
    predictor = DSPex.Predict.new("question -> answer")
    
    {time, {:ok, _result}} = :timer.tc(fn ->
      DSPex.Predict.call(predictor, %{question: "What is 2+2?"})
    end)
    
    assert time < 100_000  # microseconds
  end
  
  @tag :performance
  test "handles 100 concurrent requests" do
    predictor = DSPex.Predict.new("question -> answer")
    
    tasks = for i <- 1..100 do
      Task.async(fn ->
        DSPex.Predict.call(predictor, %{question: "Question #{i}"})
      end)
    end
    
    results = Task.await_many(tasks, 30_000)
    assert Enum.all?(results, &match?({:ok, _}, &1))
  end
  
  @tag :performance
  test "memory usage remains stable" do
    initial_memory = :erlang.memory(:total)
    
    for _ <- 1..1000 do
      predictor = DSPex.Predict.new("question -> answer")
      DSPex.Predict.call(predictor, %{question: "test"})
    end
    
    :erlang.garbage_collect()
    final_memory = :erlang.memory(:total)
    
    # Memory should not grow more than 10MB
    assert (final_memory - initial_memory) < 10_000_000
  end
end
```

### 2. Observability Tests

**Purpose**: Verify that all operations emit proper telemetry.

```elixir
defmodule SnakepitGrpcBridge.Tests.Observability do
  use ExUnit.Case
  
  test "emits telemetry for all operations" do
    {:ok, _pid} = TelemetryCollector.start_link()
    
    # Execute various operations
    predictor = DSPex.Predict.new("question -> answer")
    DSPex.Predict.call(predictor, %{question: "test"})
    
    # Check telemetry was emitted
    events = TelemetryCollector.get_events()
    
    assert_telemetry_emitted(events, [:bridge, :create_instance, :start])
    assert_telemetry_emitted(events, [:bridge, :create_instance, :stop])
    assert_telemetry_emitted(events, [:bridge, :call_method, :start])
    assert_telemetry_emitted(events, [:bridge, :call_method, :stop])
  end
  
  test "telemetry includes useful metadata" do
    {:ok, events} = capture_telemetry(fn ->
      predictor = DSPex.Predict.new("question -> answer")
      DSPex.Predict.call(predictor, %{question: "What is AI?"})
    end)
    
    call_event = find_event(events, [:bridge, :call_method, :stop])
    
    assert call_event.metadata.python_class == "dspy.Predict"
    assert call_event.metadata.method == "__call__"
    assert call_event.measurements.duration > 0
    assert call_event.metadata.success == true
  end
  
  test "error telemetry includes exception details" do
    {:ok, events} = capture_telemetry(fn ->
      predictor = DSPex.Predict.new("invalid signature")
      DSPex.Predict.call(predictor, %{})  # Missing required input
    end)
    
    error_event = find_event(events, [:bridge, :call_method, :exception])
    
    assert error_event.metadata.kind == :error
    assert error_event.metadata.reason =~ "missing required"
  end
end
```

### 3. Bidirectional Communication Tests

**Purpose**: Verify Python can successfully call back to Elixir.

```elixir
defmodule SnakepitGrpcBridge.Tests.Bidirectional do
  use ExUnit.Case
  
  test "Python can call Elixir tools" do
    # Register Elixir tool
    DSPex.Tools.register("uppercase", fn %{"text" => text} ->
      String.upcase(text)
    end)
    
    # Create Python component that uses the tool
    enhancer = DSPex.Custom.new("""
    def enhance(session_context, text):
        # Call Elixir tool from Python
        return session_context.call_elixir_tool("uppercase", {"text": text})
    """)
    
    {:ok, result} = DSPex.Custom.call(enhancer, %{text: "hello"})
    assert result == "HELLO"
  end
  
  test "complex bidirectional workflow" do
    # Register multiple tools
    DSPex.Tools.register("validate_email", &MyApp.Validators.email?/1)
    DSPex.Tools.register("normalize_email", &MyApp.Normalizers.email/1)
    DSPex.Tools.register("check_domain", &MyApp.DomainChecker.valid?/1)
    
    # Python component that orchestrates Elixir tools
    # SECURITY NOTE: DSPex.Custom.new is ONLY available in test environment
    # This prevents arbitrary code execution in production
    email_processor = DSPex.Custom.new("""
    def process_email(session_context, email):
        # Step 1: Validate format
        if not session_context.call_elixir_tool("validate_email", {"email": email}):
            return {"status": "invalid", "email": email}
            
        # Step 2: Normalize
        normalized = session_context.call_elixir_tool("normalize_email", {"email": email})
        
        # Step 3: Check domain
        domain_valid = session_context.call_elixir_tool("check_domain", {"email": normalized})
        
        return {
            "status": "valid" if domain_valid else "invalid_domain",
            "original": email,
            "normalized": normalized
        }
    """)
    
    {:ok, result} = DSPex.Custom.call(email_processor, %{email: "TEST@EXAMPLE.COM"})
    
    assert result["status"] == "valid"
    assert result["normalized"] == "test@example.com"
  end
end
```

### Security Note: DSPex.Custom

The `DSPex.Custom.new("""...""")` helper shown in tests is a powerful but dangerous feature that allows arbitrary Python code execution. This feature:

1. **MUST be restricted to test environment only**
   ```elixir
   defmodule DSPex.Custom do
     def new(python_code) do
       unless Mix.env() == :test do
         raise "DSPex.Custom is only available in test environment for security"
       end
       # Implementation...
     end
   end
   ```

2. **Should never be exposed in production**
3. **Is intended only for testing complex scenarios**
4. **Could be replaced with pre-defined test components if security is a concern**

### 4. State Management Tests

**Purpose**: Verify session state works correctly across calls.

```elixir
defmodule SnakepitGrpcBridge.Tests.StateManagement do
  use ExUnit.Case
  
  test "session variables persist across calls" do
    session = DSPex.Session.new()
    
    # Set variables
    DSPex.Session.set_variable(session, "user_name", "Alice")
    DSPex.Session.set_variable(session, "preferences", %{theme: "dark"})
    
    # Use in multiple calls
    greeter = DSPex.Custom.new("""
    def greet(session_context):
        name = session_context.get_variable("user_name")
        prefs = session_context.get_variable("preferences")
        return f"Hello {name}, using {prefs['theme']} theme"
    """)
    
    {:ok, result1} = DSPex.Custom.call(greeter, %{}, session: session)
    assert result1 == "Hello Alice, using dark theme"
    
    # Variables persist
    {:ok, result2} = DSPex.Custom.call(greeter, %{}, session: session)
    assert result2 == "Hello Alice, using dark theme"
  end
  
  test "instance references persist in session" do
    session = DSPex.Session.new()
    
    # Create predictor in session
    predictor = DSPex.Predict.new("question -> answer", session: session)
    
    # Use same predictor multiple times
    {:ok, result1} = DSPex.Predict.call(predictor, %{question: "What is 1+1?"})
    {:ok, result2} = DSPex.Predict.call(predictor, %{question: "What is 2+2?"})
    
    # Should use same underlying Python instance
    assert result1.answer != result2.answer
  end
end
```

### 5. Error Recovery Tests

**Purpose**: Verify the system handles failures gracefully.

```elixir
defmodule SnakepitGrpcBridge.Tests.ErrorRecovery do
  use ExUnit.Case
  
  test "recovers from Python worker crash" do
    predictor = DSPex.Predict.new("question -> answer")
    
    # Kill Python worker
    SnakepitGrpcBridge.Tests.Helpers.kill_python_workers()
    
    # Should still work (new worker spawned)
    {:ok, result} = DSPex.Predict.call(predictor, %{question: "test"})
    assert result.answer
  end
  
  test "handles malformed Python responses" do
    # Create component that returns invalid data
    bad_component = DSPex.Custom.new("""
    def execute(session_context, inputs):
        return {"this": {"is": {"too": {"deeply": {"nested": None}}}}}
    """)
    
    {:error, reason} = DSPex.Custom.call(bad_component, %{})
    assert reason =~ "serialization"
  end
  
  test "circuit breaker prevents cascade failures" do
    # Create component that always fails
    failing_component = DSPex.Custom.new("""
    def execute(session_context, inputs):
        raise Exception("Always fails")
    """)
    
    # First few calls fail normally
    for _ <- 1..5 do
      {:error, _} = DSPex.Custom.call(failing_component, %{})
    end
    
    # Circuit breaker opens
    {:error, :circuit_breaker_open} = DSPex.Custom.call(failing_component, %{})
  end
end
```

### 6. Performance Optimization Tests

**Purpose**: Verify performance features work correctly.

```elixir
defmodule SnakepitGrpcBridge.Tests.PerformanceOptimization do
  use ExUnit.Case
  
  test "routes to fastest worker" do
    # Create workers with different response times
    SnakepitGrpcBridge.Tests.Helpers.create_slow_worker(1, delay: 100)
    SnakepitGrpcBridge.Tests.Helpers.create_fast_worker(2, delay: 10)
    
    # Make several calls to establish performance baseline
    for _ <- 1..10 do
      DSPex.Predict.call(predictor, %{question: "test"})
    end
    
    # Check routing statistics
    stats = SnakepitGrpcBridge.Telemetry.get_routing_stats()
    
    # Fast worker should get more requests
    assert stats.worker_2.request_count > stats.worker_1.request_count
  end
  
  test "caches schema lookups" do
    # First schema lookup
    {time1, _} = :timer.tc(fn ->
      DSPex.SchemaCache.get_schema("dspy.Predict")
    end)
    
    # Second lookup should be cached
    {time2, _} = :timer.tc(fn ->
      DSPex.SchemaCache.get_schema("dspy.Predict")
    end)
    
    # Cached lookup should be 100x faster
    assert time2 < time1 / 100
  end
end
```

### 7. Integration Tests

**Purpose**: Verify the system works end-to-end with real DSPy components.

```elixir
defmodule SnakepitGrpcBridge.Tests.Integration do
  use ExUnit.Case
  
  @tag :integration
  test "ChainOfThought with validators" do
    # Register validator
    DSPex.Tools.register("validate_reasoning", fn %{"steps" => steps} ->
      length(steps) >= 3 && Enum.all?(steps, &String.length(&1) > 10)
    end)
    
    # Create ChainOfThought that uses validator
    cot = DSPex.ChainOfThought.new(
      "question -> reasoning, answer",
      validators: ["validate_reasoning"]
    )
    
    {:ok, result} = DSPex.ChainOfThought.call(cot, %{
      question: "Why does ice float on water?"
    })
    
    assert length(result.reasoning_steps) >= 3
    assert result.answer =~ "density"
  end
  
  @tag :integration
  test "ReAct agent with external tools" do
    # Register tools
    DSPex.Tools.register("search", fn %{"query" => query} ->
      # Mock search results
      case query do
        "population France 2024" -> "67.5 million"
        _ -> "No results found"
      end
    end)
    
    DSPex.Tools.register("calculate", fn %{"expression" => expr} ->
      # Simple calculator
      Code.eval_string(expr) |> elem(0) |> to_string()
    end)
    
    agent = DSPex.ReAct.new(
      signature: "question -> answer",
      tools: ["search", "calculate"]
    )
    
    {:ok, result} = DSPex.ReAct.call(agent, %{
      question: "What is the population of France in 2024?"
    })
    
    assert result.answer =~ "67.5 million"
    assert length(result.tool_calls) > 0
    assert Enum.any?(result.tool_calls, &(&1.tool == "search"))
  end
end
```

## Test Execution Strategy

### Continuous Integration

```yaml
# .github/workflows/cognitive-readiness.yml
name: Cognitive Readiness Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
      - run: mix test --only unit
      
  performance-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
      - run: mix test --only performance
      
  integration-tests:
    runs-on: ubuntu-latest
    services:
      python:
        image: python:3.10
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
      - run: mix test --only integration
```

### Performance Benchmarks

```elixir
# benchmarks/bridge_bench.exs
Benchee.run(%{
  "simple_prediction" => fn ->
    DSPex.Predict.call(predictor, %{question: "What is AI?"})
  end,
  
  "bidirectional_call" => fn ->
    DSPex.Custom.call(bidirectional_component, %{text: "test"})
  end,
  
  "parallel_requests" => fn ->
    tasks = for _ <- 1..10 do
      Task.async(fn -> DSPex.Predict.call(predictor, %{question: "test"}) end)
    end
    Task.await_many(tasks)
  end
})
```

## Success Criteria

### Performance
- P50 latency < 50ms
- P99 latency < 200ms
- Throughput > 1000 req/s

### Reliability
- Error rate < 0.1%
- Recovery time < 5s
- No memory leaks

### Observability
- 100% operation coverage
- Meaningful error messages
- Actionable metrics

## Summary

These tests prove the system is "cognitive ready" by demonstrating:
1. **Performance**: Fast enough for interactive use
2. **Observability**: Complete visibility into operations
3. **Bidirectional**: Seamless Python ↔ Elixir communication
4. **Reliability**: Graceful error handling and recovery
5. **Scalability**: Handles concurrent load efficiently

No vague promises - just concrete, measurable capabilities.
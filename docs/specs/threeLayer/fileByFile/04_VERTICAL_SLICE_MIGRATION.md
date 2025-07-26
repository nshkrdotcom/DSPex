# Vertical Slice Migration Plan

## Why Vertical Slices?

The "big bang" migration approach is doomed to fail:
- Too many moving parts
- No incremental validation
- All-or-nothing risk
- Impossible to debug

Instead, we migrate one complete feature at a time, validating each slice works end-to-end before moving on.

## Slice Selection Criteria

Good vertical slices:
1. **Self-contained**: Minimal dependencies on other features
2. **Testable**: Clear success criteria
3. **Valuable**: Provides immediate benefit when migrated
4. **Representative**: Exercises key architectural patterns

## Migration Slices

### Slice 1: Basic Predict (Weeks 1-2)

**Goal**: Migrate the simplest DSPy operation to prove the architecture.

**Scope**:
- DSPex.Predict module
- Simple session management
- Basic telemetry
- No bidirectional features

**Files to Migrate**:
```
DSPex:
- lib/dspex/predict.ex → Uses new bridge

SnakepitGrpcBridge:
- lib/snakepit_grpc_bridge/dspy/predict.ex (new)
- lib/snakepit_grpc_bridge/session/manager.ex (new)
- lib/snakepit_grpc_bridge/telemetry/reporter.ex (new)
```

**Success Criteria**:
```elixir
# This must work identically before and after migration
predictor = DSPex.Predict.new("question -> answer")
{:ok, result} = DSPex.Predict.call(predictor, %{question: "What is 2+2?"})
assert result.answer == "4"
```

**Implementation Steps**:
1. Create minimal SnakepitGrpcBridge.Session.Manager
2. Implement SnakepitGrpcBridge.DSPy.Predict wrapper
3. Add basic telemetry
4. Update DSPex.Predict to use new bridge
5. Run existing tests - they must pass
6. Add telemetry assertions

### Slice 2: Session Variables (Week 3)

**Goal**: Prove session state management works correctly.

**Scope**:
- Variable storage and retrieval
- Session persistence
- Cross-request state

**Files to Migrate**:
```
SnakepitGrpcBridge:
- lib/snakepit_grpc_bridge/session/variable_store.ex (new)
- lib/snakepit_grpc_bridge/session/persistence.ex (new)

Python:
- Update session_context.py to use gRPC for variables
```

**Success Criteria**:
```elixir
# Variables persist across calls
session = DSPex.Session.new()
DSPex.Session.set_variable(session, "temperature", 0.7)
DSPex.Session.set_variable(session, "max_tokens", 100)

# Use in prediction
predictor = DSPex.Predict.new("question -> answer", session: session)
{:ok, result} = DSPex.Predict.call(predictor, %{question: "What is AI?"})

# Verify variables were accessible in Python
assert DSPex.Session.get_variable(session, "temperature") == 0.7
```

### Slice 3: Bidirectional Tool Bridge (Week 4)

**Goal**: Enable Python → Elixir callbacks.

**Scope**:
- Tool registry
- Bidirectional communication
- ChainOfThought with validation

**Files to Migrate**:
```
SnakepitGrpcBridge:
- lib/snakepit_grpc_bridge/tools/registry.ex (new)
- lib/snakepit_grpc_bridge/tools/executor.ex (new)
- lib/snakepit_grpc_bridge/grpc/tool_service.ex (new)

DSPex:
- lib/dspex/chain_of_thought.ex → Uses bidirectional features
```

**Success Criteria**:
```elixir
# Define Elixir validation tool
defmodule MyApp.Validators do
  def validate_reasoning(reasoning) do
    String.contains?(reasoning, "because")
  end
end

# Register with bridge
DSPex.Tools.register("validate_reasoning", &MyApp.Validators.validate_reasoning/1)

# Use in ChainOfThought
cot = DSPex.ChainOfThought.new("question -> reasoning, answer")
{:ok, result} = DSPex.ChainOfThought.call(cot, %{question: "Why is the sky blue?"})

# Verify Python called our validator
assert result.reasoning =~ "because"
```

### Slice 4: Performance Monitoring (Week 5)

**Goal**: Add comprehensive observability.

**Scope**:
- Detailed telemetry
- Performance routing
- Error tracking

**Files to Migrate**:
```
SnakepitGrpcBridge:
- lib/snakepit_grpc_bridge/telemetry/performance_tracker.ex (new)
- lib/snakepit_grpc_bridge/routing/performance_router.ex (new)
- lib/snakepit_grpc_bridge/telemetry/error_reporter.ex (new)
```

**Success Criteria**:
```elixir
# Telemetry events are emitted
{:ok, events} = Telemetry.TestHelper.capture(fn ->
  DSPex.Predict.call(predictor, %{question: "test"})
end)

assert Enum.any?(events, &match?({[:bridge, :execution, :start], _, _}, &1))
assert Enum.any?(events, &match?({[:bridge, :execution, :stop], _, _}, &1))

# Performance routing works
# After several calls, fastest worker is preferred
stats = SnakepitGrpcBridge.Telemetry.get_worker_stats()
assert stats.worker_1.avg_latency < stats.worker_2.avg_latency
```

### Slice 5: Complex Components (Week 6)

**Goal**: Migrate more complex DSPy components.

**Scope**:
- ReAct agent
- ProgramOfThought
- Complex tool interactions

**Files to Migrate**:
```
DSPex:
- lib/dspex/react.ex
- lib/dspex/program_of_thought.ex
```

**Success Criteria**:
```elixir
# ReAct agent works with tools
agent = DSPex.ReAct.new(
  signature: "question -> answer",
  tools: ["search", "calculate", "validate"]
)

{:ok, result} = DSPex.ReAct.call(agent, %{
  question: "What is the population of France in 2024?"
})

# Verify tool calls happened
assert length(result.tool_calls) > 0
assert result.answer =~ "million"
```

### Slice 6: Production Readiness (Week 7-8)

**Goal**: Production-grade features.

**Scope**:
- Connection pooling
- Circuit breakers
- Health checks
- Graceful shutdown

**Files to Migrate**:
```
SnakepitGrpcBridge:
- lib/snakepit_grpc_bridge/pool/manager.ex
- lib/snakepit_grpc_bridge/health/checker.ex
- lib/snakepit_grpc_bridge/circuit_breaker.ex
```

**Success Criteria**:
- Load tests pass
- Failover works correctly
- Memory usage is stable
- Graceful shutdown preserves state

## Migration Execution

### For Each Slice

1. **Write Integration Tests First**
   ```elixir
   defmodule SliceXIntegrationTest do
     use ExUnit.Case
     
     describe "slice X behavior" do
       test "works exactly like before migration" do
         # Test current behavior
       end
     end
   end
   ```

2. **Implement in SnakepitGrpcBridge**
   - Start with minimal implementation
   - Add telemetry from the start
   - Test in isolation

3. **Update DSPex to Use New Bridge**
   - Keep old code paths during migration
   - Use feature flags if needed
   - Maintain backwards compatibility

4. **Validate with Integration Tests**
   - All existing tests must pass
   - Performance should not degrade
   - Telemetry should show improvements

5. **Deploy to Staging**
   - Monitor for issues
   - Compare metrics before/after
   - Run soak tests

6. **Graduate to Production**
   - Gradual rollout
   - Monitor closely
   - Have rollback plan

### Rollback Strategy

Each slice must be independently rollback-able:

```elixir
defmodule DSPex.Predict do
  # Feature flag for migration
  if Application.get_env(:dspex, :use_new_bridge, false) do
    defdelegate new(signature), to: DSPex.Bridge.Predict
    defdelegate call(predictor, inputs), to: DSPex.Bridge.Predict
  else
    # Old implementation
    def new(signature), do: Legacy.Predict.new(signature)
    def call(predictor, inputs), do: Legacy.Predict.call(predictor, inputs)
  end
end
```

## Success Metrics

### Per-Slice Metrics

1. **Functional**: All tests pass
2. **Performance**: No regression (< 5% increase in latency)
3. **Reliability**: Error rate unchanged or improved
4. **Observability**: New telemetry events captured

### Overall Migration Metrics

1. **Code Quality**: Reduced complexity scores
2. **Maintainability**: Smaller, focused modules
3. **Performance**: 20% improvement from better routing
4. **Developer Experience**: Positive feedback on new APIs

## Risk Mitigation

### Technical Risks

1. **gRPC Performance**: Benchmark early and often
2. **State Corruption**: Comprehensive testing of session management
3. **Python Compatibility**: Test with all Python versions

### Process Risks

1. **Scope Creep**: Stick to slice boundaries
2. **Big Bang Temptation**: Resist urge to migrate everything at once
3. **Testing Shortcuts**: Maintain high test coverage throughout

## Timeline Summary

- **Weeks 1-2**: Basic Predict (Foundation)
- **Week 3**: Session Variables (State Management)
- **Week 4**: Bidirectional Bridge (Key Innovation)
- **Week 5**: Performance Monitoring (Observability)
- **Week 6**: Complex Components (Full Features)
- **Weeks 7-8**: Production Readiness (Hardening)

Total: 8 weeks for complete migration with validation at each step.

## Conclusion

Vertical slice migration:
1. **Reduces Risk**: Each slice is independently valuable
2. **Provides Validation**: Know it works before moving on
3. **Maintains Momentum**: Regular wins keep team motivated
4. **Enables Learning**: Each slice informs the next

This approach turns a risky "big bang" into a series of controlled, validated improvements.
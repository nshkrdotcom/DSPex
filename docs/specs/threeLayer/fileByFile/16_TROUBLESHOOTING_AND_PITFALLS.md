# Troubleshooting Guide and Common Pitfalls

## Overview

This document captures common issues encountered during the DSPex migration and their solutions. Learn from these patterns to avoid similar problems.

## Common AI Conversation Pitfalls

### Pitfall 1: AI Adds Unnecessary Complexity

**Symptom**: 
```elixir
# You asked for a simple validator
# AI gives you:
defmodule Validator do
  use GenServer
  use Supervisor
  use Phoenix.PubSub
  
  def start_link(_), do: Supervisor.start_link(__MODULE__, :ok)
  
  def init(:ok) do
    children = [
      {DynamicSupervisor, name: ValidatorSupervisor},
      {Registry, keys: :unique, name: ValidatorRegistry},
      {Phoenix.PubSub, name: ValidatorPubSub}
    ]
    # ... 200 more lines
  end
```

**Solution**:
Be explicit about simplicity in your constraints:
```text
CONSTRAINTS:
- This should be a simple pure function module, NOT a GenServer
- No processes, supervisors, or state needed
- Just validate and return true/false
- Keep it under 50 lines total
```

### Pitfall 2: AI Ignores Existing Patterns

**Symptom**:
AI creates new patterns instead of following established ones in your codebase.

**Solution**:
Always provide concrete examples:
```text
EXAMPLE:
Follow this exact pattern from our existing validators:
```elixir
defmodule MyApp.Validators.Email do
  def validate(%{"email" => email}) when is_binary(email) do
    email =~ ~r/^[\w\.\-]+@[\w\.\-]+\.\w+$/
  end
  
  def validate(_), do: false
end
```
Your validator should follow the same structure.
```

### Pitfall 3: AI Forgets Module Dependencies

**Symptom**:
```elixir
# AI generates this
defmodule NewModule do
  def process(data) do
    # Uses SomeHelper.transform without importing/aliasing
    result = SomeHelper.transform(data)
    # Calls function that doesn't exist
    finalize_result(result)
  end
end
```

**Solution**:
Specify dependencies upfront:
```text
TASK:
Create NewModule that uses these existing modules:
- SomeHelper (alias and use transform/1)
- ResultFormatter (import format_output/1)

The module should have proper aliases/imports at the top.
```

## Architecture-Specific Pitfalls

### Pitfall 4: Mixing Layers

**Symptom**:
Putting bridge logic in DSPex (user API) layer or user API in SnakepitGrpcBridge.

**Solution**:
Be clear about which layer:
```text
CONTEXT:
This module belongs in SnakepitGrpcBridge (NOT DSPex).
It handles gRPC communication and should not contain user-facing API.

DSPex layer: User-facing API only
SnakepitGrpcBridge layer: gRPC and bridge logic
Snakepit layer: Pure OTP infrastructure
```

### Pitfall 5: Contract Compile-Time Dependencies

**Symptom**:
```elixir
defmodule DSPex.Contracts.Predict do
  # This requires Python at compile time!
  @methods SchemaDiscovery.discover!("dspy.Predict")
  
  for method <- @methods do
    defmethod unquote(method.name), unquote(method.params)
  end
end
```

**Solution**:
Contracts must be explicit:
```text
CONSTRAINTS:
- Define contracts manually, do NOT use runtime discovery
- No Python dependencies at compile time
- Use the mix task for discovery during development only
- Contracts are checked into version control
```

### Pitfall 6: Super Chain Problems

**Symptom**:
```elixir
defmodule MyWrapper do
  use DSPex.Bridge.Observable
  use DSPex.Bridge.Bidirectional  # Order matters! Breaks super()
  
  def create(args) do
    # Which super() is called?
    super(args)
  end
end
```

**Solution**:
Never use super in composed behaviors:
```text
IMPORTANT: Our architecture does NOT use super() chains.
Instead, behaviors register themselves via module attributes:

@dspex_behaviors [:observable, :bidirectional]

The wrapper orchestrator handles all behaviors explicitly.
```

## Testing Pitfalls

### Pitfall 7: Tests Depend on External Services

**Symptom**:
```elixir
test "validates with real Python" do
  # This fails in CI without Python
  result = DSPex.Predict.call(predictor, %{question: "test"})
end
```

**Solution**:
Mock at the bridge layer:
```elixir
test "validates with mocked bridge" do
  Mock.expect(DSPex.Bridge, :call_method, fn _, _, _ ->
    {:ok, %{"answer" => "mocked"}}
  end)
  
  result = DSPex.Predict.call(predictor, %{question: "test"})
  assert result.answer == "mocked"
end
```

### Pitfall 8: Flaky Async Tests

**Symptom**:
```elixir
test "concurrent operations" do
  for i <- 1..100 do
    Task.async(fn -> operation(i) end)
  end
  
  # Sometimes passes, sometimes fails
  assert something()
end
```

**Solution**:
Properly await async operations:
```elixir
test "concurrent operations" do
  tasks = for i <- 1..100 do
    Task.async(fn -> operation(i) end)
  end
  
  results = Task.await_many(tasks, 5000)
  assert length(results) == 100
  assert Enum.all?(results, &match?({:ok, _}, &1))
end
```

## Performance Pitfalls

### Pitfall 9: N+1 Bridge Calls

**Symptom**:
```elixir
def process_items(items) do
  Enum.map(items, fn item ->
    # Each calls Python separately!
    {:ok, result} = DSPex.Predict.call(predictor, item)
    result
  end)
end
```

**Solution**:
Batch operations:
```elixir
def process_items(items) do
  # Single call with all items
  {:ok, results} = DSPex.Predict.batch_call(predictor, items)
  results
end
```

### Pitfall 10: Unbounded Session Growth

**Symptom**:
Sessions accumulate variables forever, causing memory issues.

**Solution**:
Implement limits and expiry:
```elixir
defmodule Session.VariableStore do
  @max_variables 1000
  @max_variable_size 1_048_576  # 1MB
  
  def set(store, key, value) do
    with :ok <- validate_size(value),
         :ok <- validate_count(store) do
      do_set(store, key, value)
    end
  end
end
```

## Debugging Techniques

### Technique 1: Telemetry Inspection

When things don't work as expected:
```elixir
# Add temporary telemetry handler
:telemetry.attach("debug", 
  [:dspex, :bridge, :call_method, :stop],
  fn _, measurements, metadata, _ ->
    IO.inspect({measurements, metadata}, label: "TELEMETRY")
  end,
  nil
)

# Run your code
# Remove handler
:telemetry.detach("debug")
```

### Technique 2: Bridge Call Tracing

```elixir
# Wrap bridge calls with logging
defmodule DebugBridge do
  def call_method(ref, method, args) do
    IO.inspect({ref, method, args}, label: "BRIDGE CALL")
    result = DSPex.Bridge.call_method(ref, method, args)
    IO.inspect(result, label: "BRIDGE RESULT")
    result
  end
end
```

### Technique 3: Python Side Debugging

```python
# Add to session context
class DebugSession(Session):
    def call_elixir_tool(self, name, args):
        print(f"TOOL CALL: {name} with {args}")
        result = super().call_elixir_tool(name, args)
        print(f"TOOL RESULT: {result}")
        return result
```

## Recovery Procedures

### When Build is Broken

```bash
# 1. Stash current work
git stash

# 2. Reset to last known good state
git reset --hard HEAD~1

# 3. Clean build artifacts
rm -rf _build deps
mix deps.get
mix compile

# 4. Gradually reapply changes
git stash pop
```

### When Tests Won't Pass

```bash
# 1. Run single test with debugging
MIX_DEBUG=1 mix test test/file.exs:42 --trace

# 2. Check for test pollution
mix test --seed 0  # Deterministic order

# 3. Run in isolation
mix test test/specific_test.exs --only focus:true
```

### When Python Won't Connect

```bash
# 1. Check Python bridge is running
ps aux | grep bridge_server

# 2. Verify gRPC port is open
netstat -an | grep 50051

# 3. Test basic connectivity
grpcurl -plaintext localhost:50051 list

# 4. Check logs
tail -f log/bridge.log
```

## Prevention Strategies

### Strategy 1: Incremental Implementation

Never try to implement everything at once:
```text
BAD:  "Implement the complete bidirectional bridge system"
GOOD: "First, create the tool registry module"
      "Next, add the executor"
      "Then, wire up gRPC"
      etc.
```

### Strategy 2: Test First

Write a failing test before asking AI to implement:
```elixir
test "the behavior I want" do
  # This will fail until implemented
  result = NewModule.new_function("input")
  assert result == "expected output"
end
```

### Strategy 3: Version Control Discipline

```bash
# Before each AI conversation
git checkout -b ai-attempt-$(date +%s)

# After success
git checkout main
git merge --squash ai-attempt-*
git commit -m "feat: Description of what worked"

# After failure  
git checkout main
git branch -D ai-attempt-*
```

## Common Error Messages and Solutions

### Error: "undefined function super/1"
**Cause**: Using super in our composed behaviors
**Solution**: Don't use super; use module attributes instead

### Error: "dspy module not found"
**Cause**: Trying to discover schema at compile time
**Solution**: Use explicit contracts, not runtime discovery

### Error: "argument error: :erlang.binary_to_term"
**Cause**: Serialization mismatch between Python and Elixir
**Solution**: Use consistent serialization (JSON or ETF)

### Error: "process #PID<...> is not alive"
**Cause**: Race condition in async operations
**Solution**: Add proper process monitoring and await

### Error: "{:timeout, {GenServer, :call, [...]}}"
**Cause**: Bridge operation taking too long
**Solution**: Increase timeout or optimize operation

## Best Practices Learned

1. **Always provide examples** - AI follows patterns better than descriptions
2. **Constrain explicitly** - Say what NOT to do as well as what to do
3. **Test boundaries** - Most bugs hide at integration points
4. **Commit working code immediately** - Don't let it drift
5. **Keep conversations focused** - One topic per conversation
6. **Document decisions** - Future you will thank present you

## Summary

The key to avoiding pitfalls:
1. **Be Explicit**: Over-communicate requirements
2. **Show Examples**: Code speaks louder than words
3. **Test Early**: Catch issues before they compound
4. **Stay Focused**: One problem at a time
5. **Use Version Control**: Always have an escape route

Remember: AI is a powerful tool, but you're the architect. Guide it carefully and verify everything.
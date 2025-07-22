# Implementation Plan: Stage 2 Compliance for Unified gRPC Bridge

## Status (Updated: 2025-01-22)

✅ **COMPLETED** - All high and medium priority fixes have been successfully implemented:
- ✅ Service name updated from `SnakepitBridge` to `BridgeService` 
- ✅ All references updated across Elixir and Python codebases
- ✅ Type system deduplicated - LocalState now uses centralized type system
- ✅ BridgedState refactored to use SessionStore API directly
- ✅ GetSession and Heartbeat RPC handlers implemented
- ✅ Type serialization double-encoding issue fixed
- ✅ Deprecation warnings in tests resolved
- ✅ All tests passing (DSPex: 116 tests, Snakepit: 182 tests)

Remaining low-priority items for future consideration:
- ⏳ Create unified integration test runner
- ⏳ Implement property-based tests  
- ⏳ Create benchmark suite

## Executive Summary

This document provides a comprehensive plan to bring the DSPex unified gRPC bridge implementation into 100% compliance with the Stage 0, Stage 1, and Stage 2 specifications. The plan addresses architectural refactoring, missing implementations, and test suite completion.

## Current State Analysis

### Implemented Components
- **Stage 0**: Protocol foundation with gRPC infrastructure (see `snakepit/priv/protos/snakepit_bridge.proto`)
- **Stage 1**: Core variable system with SessionStore (see `snakepit/lib/snakepit/bridge/session_store.ex`)
- **Stage 2**: DSPex.Context and dual backend architecture (see `lib/dspex/context.ex`)

### Key Deviations from Specification
1. Service naming inconsistency in protobuf definitions
2. Duplicated type system logic in state backends
3. Missing property-based tests and benchmarks
4. Incomplete integration test consolidation

## Phase 1: Stage 0 Protocol Foundation Fixes

### Fix 1: Correct Service Name in Protobuf

**Current State:**
- File: `snakepit/priv/protos/snakepit_bridge.proto` (line 6)
- Service is named `SnakepitBridge`

**Required Change:**
```protobuf
// Change from:
service SnakepitBridge {

// To:
service BridgeService {
```

**Implementation Steps:**
1. Update the proto file at `snakepit/priv/protos/snakepit_bridge.proto:6`
2. Regenerate Elixir bindings:
   ```bash
   cd snakepit
   mix grpc.gen
   ```
3. Regenerate Python bindings:
   ```bash
   cd snakepit/priv/python
   ./generate_grpc.sh
   ```
4. Update all references in:
   - `snakepit/lib/snakepit/grpc/client.ex` (lines 663-782)
   - `snakepit/priv/python/snakepit_bridge/grpc_server.py` (lines 878-1096)

### Fix 2: Implement Missing RPCs

**Current State:**
- Missing `GetSession` and `Heartbeat` RPCs in the protocol

**Required Changes:**

1. Add to `snakepit/priv/protos/snakepit_bridge.proto` (after line 95):
```protobuf
// Session management
rpc GetSession(GetSessionRequest) returns (GetSessionResponse);
rpc Heartbeat(HeartbeatRequest) returns (HeartbeatResponse);

// Add message definitions (after line 351):
message GetSessionRequest {
  string session_id = 1;
}

message GetSessionResponse {
  string session_id = 1;
  map<string, string> metadata = 2;
  google.protobuf.Timestamp created_at = 3;
  int32 variable_count = 4;
  int32 tool_count = 5;
}

message HeartbeatRequest {
  string session_id = 1;
  google.protobuf.Timestamp client_time = 2;
}

message HeartbeatResponse {
  google.protobuf.Timestamp server_time = 1;
  bool session_valid = 2;
}
```

2. Implement handlers in `snakepit/lib/snakepit/grpc/handlers/session_handlers.ex` (new file):
```elixir
defmodule Snakepit.GRPC.Handlers.SessionHandlers do
  alias Snakepit.Bridge.SessionStore
  
  def handle_get_session(request, _stream) do
    case SessionStore.get_session(request.session_id) do
      {:ok, session} ->
        # Implementation here
      {:error, :not_found} ->
        raise GRPC.RPCError, status: :not_found
    end
  end
  
  def handle_heartbeat(request, _stream) do
    # Implementation here
  end
end
```

3. Add Python handlers in `snakepit/priv/python/snakepit_bridge/grpc_server.py` (after line 991):
```python
async def GetSession(self, request, context):
    # Implementation here
    pass

async def Heartbeat(self, request, context):
    # Implementation here
    pass
```

### Fix 3: Consolidate Integration Tests

**Current State:**
- Elixir tests in `test/snakepit/grpc_stage0_test.exs`
- Python tests in `snakepit/priv/python/tests/`
- Missing unified runner

**Required Action:**
Create `scripts/run_integration_tests.sh`:
```bash
#!/bin/bash
# File: scripts/run_integration_tests.sh

echo "Running DSPex gRPC Bridge Integration Tests"
echo "=========================================="

# Ensure Python dependencies are installed
echo "Installing Python dependencies..."
cd snakepit/priv/python
pip install -r requirements.txt
cd ../../..

# Compile protocol buffers
echo "Compiling protocol buffers..."
cd snakepit
mix grpc.gen
cd priv/python
./generate_grpc.sh
cd ../../..

# Run Elixir tests
echo "Running Elixir integration tests..."
cd snakepit
mix test --only integration

# Run Python tests
echo "Running Python integration tests..."
cd priv/python
python -m pytest tests/test_integration.py

# Run performance tests if requested
if [ "$1" == "--perf" ]; then
  echo "Running performance tests..."
  cd ../..
  mix test --only performance
fi
```

## Phase 2: Stage 1 Type System Fixes

### Fix 1: Correct Type Serialization

**Current State:**
- Files: `snakepit/lib/snakepit/bridge/variables/types/*.ex`
- Double JSON encoding in serialize/deserialize functions

**Example Fix for String Type:**
File: `snakepit/lib/snakepit/bridge/variables/types/string.ex` (lines 197-208)

```elixir
# Current implementation (line 197-200):
@impl true
def serialize(value) do
  {:ok, Jason.encode!(value)}  # This double-encodes!
end

# Should be:
@impl true
def serialize(value) do
  {:ok, value}  # Return raw string, JSON encoding happens at protocol layer
end

# Current implementation (line 203-208):
@impl true
def deserialize(json) do
  case Jason.decode(json) do
    {:ok, value} when is_binary(value) -> {:ok, value}
    _ -> {:error, "invalid string format"}
  end
end

# Should be:
@impl true
def deserialize(value) when is_binary(value) do
  {:ok, value}
end
def deserialize(_) do
  {:error, "invalid string format"}
end
```

**Apply Similar Fixes To:**
- `snakepit/lib/snakepit/bridge/variables/types/boolean.ex`
- `snakepit/lib/snakepit/bridge/variables/types/integer.ex`
- `snakepit/lib/snakepit/bridge/variables/types/float.ex`

## Phase 3: Stage 2 Architectural Refactoring

### Fix 1: Remove Duplicated Type System from LocalState

**Current State:**
- File: `lib/dspex/bridge/state/local.ex` (lines 385-562)
- Contains inline type modules duplicating Stage 1 type system

**Required Changes:**

1. Remove lines 385-562 (all inline `Types` modules)

2. Add alias at top of module (after line 10):
```elixir
alias Snakepit.Bridge.Variables.Types
```

3. Update `register_variable/5` function (line 42-73):
```elixir
@impl true
def register_variable(state, name, type, initial_value, opts) do
  with {:ok, type_module} <- Types.get_type_module(type),
       {:ok, validated_value} <- type_module.validate(initial_value),
       constraints = Keyword.get(opts, :constraints, %{}),
       :ok <- type_module.validate_constraints(validated_value, constraints) do
    # Rest of implementation remains the same
  end
end
```

4. Update `set_variable/4` function (line 113-144):
```elixir
# Replace the validation logic to use centralized Types
with {:ok, type_module} <- Types.get_type_module(variable.type),
     {:ok, validated_value} <- type_module.validate(new_value),
     :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
  # Rest of implementation
end
```

### Fix 2: Refactor BridgedState to Use SessionStore API

**Current State:**
- File: `lib/dspex/bridge/state/bridged.ex`
- Directly manipulates session data instead of using SessionStore API

**Required Changes:**

1. Update imports (add after line 8):
```elixir
alias Snakepit.Bridge.SessionStore
alias Snakepit.Bridge.Variables.Variable
```

2. Refactor `register_variable/5` (lines 51-89):
```elixir
@impl true
def register_variable(state, name, type, initial_value, opts) do
  case SessionStore.register_variable(
    state.session_id,
    name,
    type,
    initial_value,
    opts
  ) do
    {:ok, var_id} ->
      {:ok, {var_id, state}}
    error ->
      error
  end
end
```

3. Refactor `get_variable/2` (lines 91-101):
```elixir
@impl true
def get_variable(state, identifier) do
  case SessionStore.get_variable(state.session_id, identifier) do
    {:ok, %Variable{value: value}} ->
      {:ok, value}
    error ->
      error
  end
end
```

4. Refactor `set_variable/4` (lines 103-112):
```elixir
@impl true
def set_variable(state, identifier, new_value, metadata) do
  case SessionStore.update_variable(
    state.session_id,
    identifier,
    new_value,
    metadata
  ) do
    :ok -> {:ok, state}
    error -> error
  end
end
```

5. Continue this pattern for:
   - `list_variables/1` (lines 114-123)
   - `get_variables/2` (lines 125-142)
   - `update_variables/3` (lines 144-166)
   - `delete_variable/2` (lines 168-175)

6. Refactor `import_state/2` (lines 223-261) to use:
```elixir
defp import_variables(session_id, variables) do
  case SessionStore.import_variables(session_id, variables) do
    {:ok, _count} -> :ok
    error -> error
  end
end
```

## Phase 4: Test Suite Completion

### Fix 1: Implement Property-Based Tests

**Create:** `test/dspex/property_test.exs`

```elixir
defmodule DSPex.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  alias DSPex.{Context, Variables}
  
  property "variables maintain value and constraints across backend switches" do
    check all name <- atom(:alphanumeric),
              type <- member_of([:float, :integer, :string, :boolean]),
              value <- value_generator(type),
              max_runs: 100 do
      
      {:ok, ctx} = Context.start_link()
      
      # Register in local backend
      assert {:ok, _} = Variables.defvariable(ctx, name, type, value)
      local_value = Variables.get(ctx, name)
      
      # Force backend switch
      :ok = Context.ensure_bridged(ctx)
      
      # Value should be preserved
      bridged_value = Variables.get(ctx, name)
      assert local_value == bridged_value
      
      Context.stop(ctx)
    end
  end
  
  defp value_generator(:float), do: float()
  defp value_generator(:integer), do: integer()
  defp value_generator(:string), do: string(:alphanumeric)
  defp value_generator(:boolean), do: boolean()
end
```

### Fix 2: Implement Benchmark Suite

**Create:** `bench/stage2_benchmarks.exs`

```elixir
defmodule Stage2Benchmarks do
  use Benchfella
  
  alias DSPex.{Context, Variables}
  
  setup_all do
    {:ok, local_ctx} = Context.start_link()
    {:ok, bridged_ctx} = Context.start_link()
    Context.ensure_bridged(bridged_ctx)
    
    # Register test variables
    Variables.defvariable(local_ctx, :test_var, :float, 1.0)
    Variables.defvariable(bridged_ctx, :test_var, :float, 1.0)
    
    {:ok, local: local_ctx, bridged: bridged_ctx}
  end
  
  bench "LocalState get" do
    ctx = bench_context[:local]
    Variables.get(ctx, :test_var)
  end
  
  bench "BridgedState get" do
    ctx = bench_context[:bridged]
    Variables.get(ctx, :test_var)
  end
  
  bench "LocalState set" do
    ctx = bench_context[:local]
    Variables.set(ctx, :test_var, :rand.uniform())
  end
  
  bench "BridgedState set" do
    ctx = bench_context[:bridged]
    Variables.set(ctx, :test_var, :rand.uniform())
  end
  
  bench "Backend switch overhead" do
    {:ok, ctx} = Context.start_link()
    Variables.defvariable(ctx, :temp, :float, 0.5)
    Context.ensure_bridged(ctx)
    Context.stop(ctx)
  end
end
```

### Fix 3: Reorganize Python Tests

**Current Location:** `priv/python/dspex/python/test_stage2_integration.py`
**Move To:** `test/python/test_stage2_integration.py`

```bash
mkdir -p test/python
mv priv/python/dspex/python/test_stage2_integration.py test/python/
```

## Implementation Priority

1. **High Priority (Breaking Changes)**:
   - Fix 1.1: Service name correction (requires regenerating all bindings)
   - Fix 3.1: Remove duplicated type system from LocalState
   - Fix 3.2: Refactor BridgedState to use SessionStore API

2. **Medium Priority (Functionality)**:
   - Fix 1.2: Implement missing RPCs
   - Fix 2.1: Correct type serialization

3. **Low Priority (Testing/Organization)**:
   - Fix 1.3: Consolidate integration tests
   - Fix 4.1: Property-based tests
   - Fix 4.2: Benchmarks
   - Fix 4.3: Python test reorganization

## Validation Checklist

After implementing all fixes, validate:

- [ ] All protobuf files compile without errors
- [ ] Generated bindings match new service name
- [ ] LocalState uses centralized type system
- [ ] BridgedState delegates to SessionStore API
- [ ] Integration tests run from single script
- [ ] Property tests pass with 100+ iterations
- [ ] Benchmarks show expected performance characteristics
- [ ] No duplicated logic between layers

## References

- Stage 0 Specification: `docs/specs/unified_grpc_bridge/40_revised_stage0_protocol_foundation.md`
- Stage 1 Specification: `docs/specs/unified_grpc_bridge/41_revised_stage1_core_variables.md`
- Stage 2 Specification: `docs/specs/unified_grpc_bridge/42_revised_stage2_tool_dspy_module_integration.md`
- Implementation Prompts: `docs/specs/unified_grpc_bridge/prompts/`

This plan ensures 100% compliance with the specifications while maintaining the existing functionality and improving the architectural clarity of the implementation.
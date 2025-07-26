# Slice 2: Session Variables Implementation Guide

## Overview

This guide covers implementing Slice 2: Session Variables and State Management. This slice builds on Slice 1's basic session manager to add variable storage, persistence, and cross-request state management.

## Slice 2 Goals

- Implement variable storage in sessions
- Enable Python to get/set Elixir-side variables
- Add session persistence mechanisms
- Maintain state across multiple requests
- Full backward compatibility

## Prerequisites

- [ ] Slice 1 completed and merged
- [ ] Basic session manager exists
- [ ] Python bridge can pass session_id
- [ ] Understanding of `04_VERTICAL_SLICE_MIGRATION.md` Slice 2 requirements

## Architecture Overview

```
Elixir Side:                     Python Side:
Session.Manager                  session_context.py
    ↓                                  ↓
Variable.Store     <--gRPC-->   get/set_variable()
    ↓
Persistence.Backend
```

## Conversation Flow

### Conversation 1: Extend Session Structure

**Objective**: Add variable storage to session

**Source Documents**:
- `04_VERTICAL_SLICE_MIGRATION.md` - Slice 2 requirements
- `05_PYTHON_BRIDGE_REFACTORING.md` - Session management patterns

**Prompt**:
```text
CONTEXT:
I'm implementing Slice 2: Session Variables from our migration plan (04_VERTICAL_SLICE_MIGRATION.md).
Currently we have a basic Session.Manager from Slice 1 that just tracks session IDs.

From the Slice 2 specification:
--- PASTE lines 60-68 from 04_VERTICAL_SLICE_MIGRATION.md ---

TASK:
Extend the existing SnakepitGrpcBridge.Session.Manager to support variables.

Current basic implementation has:
- get_or_create/1 that returns %Session{id: id, created_at: timestamp}

Add:
1. A variables map to the Session struct
2. set_variable/3 function (session_id, key, value)
3. get_variable/2 function (session_id, key)
4. get_all_variables/1 function
5. Update the session state in GenServer

CONSTRAINTS:
- Variables should be stored in session state
- Support any serializable Elixir term as value
- Return {:ok, value} or {:error, :not_found}
- Make operations atomic to avoid race conditions
- Don't add persistence yet (that's next)

EXAMPLE:
Usage should look like:
```elixir
{:ok, _} = Session.Manager.set_variable("session-123", "user_name", "Alice")
{:ok, "Alice"} = Session.Manager.get_variable("session-123", "user_name")
{:error, :not_found} = Session.Manager.get_variable("session-123", "unknown")
```
```

**Expected Output**: Extended session manager with variable support

### Conversation 2: Create Variable Store Module

**Objective**: Separate variable management logic

**Source Documents**:
- Good separation of concerns principles
- `05_PYTHON_BRIDGE_REFACTORING.md` - Clean architecture

**Prompt**:
```text
CONTEXT:
To keep our session manager focused, we should extract variable management into its own module.
This follows the separation of concerns from our architecture docs.

TASK:
Create SnakepitGrpcBridge.Session.VariableStore module that:

1. Manages variables for a single session (not a GenServer)
2. Provides a clean API for variable operations
3. Handles serialization concerns
4. Tracks metadata about variables

The module should have these functions:
- new/0 - Creates empty variable store
- set/3 - Set variable with key and value
- get/2 - Get variable by key
- delete/2 - Remove variable
- to_map/1 - Get all variables as map
- merge/2 - Merge another store into this one

CONSTRAINTS:
- This is a pure functional module, not a process
- Track when each variable was set/updated
- Include size limits (e.g., max 1MB per variable)
- Provide clear error messages
- Make it easy to add persistence later

EXAMPLE:
```elixir
store = VariableStore.new()
{:ok, store} = VariableStore.set(store, "key", "value")
{:ok, "value"} = VariableStore.get(store, "key")
%{"key" => "value"} = VariableStore.to_map(store)
```
```

**Expected Output**: Functional variable store module

### Conversation 3: Integrate Variable Store with Session

**Objective**: Update Session Manager to use Variable Store

**Prompt**:
```text
CONTEXT:
Now we need to integrate the VariableStore with our Session.Manager.
This refactoring will make the code cleaner and more maintainable.

TASK:
Refactor SnakepitGrpcBridge.Session.Manager to use VariableStore:

1. Update Session struct to include variable_store field
2. Update get_or_create to initialize with empty store
3. Reimplement set_variable/3 to use VariableStore
4. Reimplement get_variable/2 to use VariableStore
5. Add delete_variable/2 function
6. Handle all error cases properly

Current functions that need updating:
[PASTE current Session.Manager implementation]

CONSTRAINTS:
- Maintain the same public API
- All existing tests must pass
- Use GenServer.call for all operations (not cast)
- Add proper error handling
- Include logging for debugging

EXAMPLE:
The internal state should now look like:
```elixir
%{
  sessions: %{
    "session-123" => %Session{
      id: "session-123",
      created_at: ~U[...],
      variable_store: %VariableStore{...}
    }
  }
}
```
```

**Expected Output**: Refactored session manager using variable store

### Conversation 4: Add Python-Side Interface

**Objective**: Enable Python to interact with variables

**Source Documents**:
- `05_PYTHON_BRIDGE_REFACTORING.md` - Session context design

**Prompt**:
```text
CONTEXT:
Now we need to add Python-side support for session variables.
From our Python bridge refactoring plan (05_PYTHON_BRIDGE_REFACTORING.md), session context design:

--- PASTE lines 149-178 from 05_PYTHON_BRIDGE_REFACTORING.md ---

TASK:
Create or update the Python session context to support variables.

Implement these methods in the Session class:
1. get_variable(self, name: str) -> Any
2. set_variable(self, name: str, value: Any) -> None
3. delete_variable(self, name: str) -> None
4. has_variable(self, name: str) -> bool

These should make gRPC calls to the Elixir side.

CONSTRAINTS:
- Handle serialization of Python types to Elixir
- Provide clear error messages
- Support common Python types (str, int, float, list, dict)
- Make it feel Pythonic
- Include type hints

EXAMPLE:
```python
# In a DSPy component
def process(session_context, inputs):
    # Get configuration from Elixir
    temperature = session_context.get_variable("temperature")
    if temperature is None:
        temperature = 0.7
    
    # Store result for later
    session_context.set_variable("last_result", result)
```
```

**Expected Output**: Python session context with variable support

### Conversation 5: Create gRPC Service for Variables

**Objective**: Add gRPC endpoints for variable operations

**Prompt**:
```text
CONTEXT:
We need gRPC service definitions for session variable operations.
This enables Python to communicate with Elixir for variable management.

TASK:
Update the gRPC protocol buffer definitions to include:

1. GetVariableRequest/Response messages
2. SetVariableRequest/Response messages  
3. DeleteVariableRequest/Response messages
4. ListVariablesRequest/Response messages

Then implement the Elixir gRPC service handlers.

Proto definitions should look like:
```proto
message GetVariableRequest {
  string session_id = 1;
  string name = 2;
}

message GetVariableResponse {
  bool found = 1;
  bytes value = 2;  // Serialized value
}
```

CONSTRAINTS:
- Use bytes for values to handle any serialization
- Include proper error status codes
- Session ID required for all operations
- Consider batch operations for efficiency
- Follow existing proto patterns in project

EXAMPLE:
The service implementation should delegate to Session.Manager:
```elixir
def get_variable(request, _stream) do
  case Session.Manager.get_variable(request.session_id, request.name) do
    {:ok, value} ->
      GetVariableResponse.new(found: true, value: serialize(value))
    {:error, :not_found} ->
      GetVariableResponse.new(found: false)
  end
end
```
```

**Expected Output**: gRPC service for variables

### Conversation 6: Add Persistence Layer

**Objective**: Make sessions survive restarts

**Source Documents**:
- Architecture principles about explicit over implicit

**Prompt**:
```text
CONTEXT:
Sessions need to survive Elixir process restarts for production use.
We'll add a simple persistence layer that can be extended later.

TASK:
Create SnakepitGrpcBridge.Session.Persistence behaviour and ETS implementation:

1. Define behaviour with callbacks:
   - save_session/1
   - load_session/1 
   - delete_session/1
   - list_sessions/0

2. Create ETSPersistence implementation:
   - Use named ETS table
   - Handle table creation on init
   - Survive process restarts
   - Include TTL support

3. Update Session.Manager to:
   - Accept persistence module in start_link
   - Auto-persist on variable changes
   - Load sessions on startup
   - Clean up expired sessions

CONSTRAINTS:
- Make persistence pluggable via behaviour
- Default to no persistence for tests
- Don't block on persistence operations
- Log persistence failures but don't crash
- Include session expiry (24 hour default)

EXAMPLE:
```elixir
# Starting with persistence
{:ok, _} = Session.Manager.start_link(
  persistence: SnakepitGrpcBridge.Session.ETSPersistence
)

# Sessions survive restart
Session.Manager.set_variable("session-123", "data", "value")
# ... restart ...
{:ok, "value"} = Session.Manager.get_variable("session-123", "data")
```
```

**Expected Output**: Persistence behaviour and ETS implementation

### Conversation 7: Write Comprehensive Tests

**Objective**: Verify session variables work correctly

**Source Documents**:
- `06_COGNITIVE_READINESS_TESTS.md` - State management tests

**Prompt**:
```text
CONTEXT:
We need comprehensive tests for session variable functionality.
Reference the state management tests from 06_COGNITIVE_READINESS_TESTS.md:

--- PASTE lines 253-304 from 06_COGNITIVE_READINESS_TESTS.md ---

TASK:
Create test/snakepit_grpc_bridge/session/variable_test.exs with:

1. Variable Store unit tests:
   - Set/get/delete operations
   - Size limit enforcement
   - Serialization edge cases
   - Concurrent updates

2. Session Manager integration tests:
   - Variables persist in session
   - Multiple sessions isolated
   - Session expiry cleans variables
   - Persistence works correctly

3. Python integration tests:
   - Python can set/get variables
   - Complex types serialize correctly
   - Error handling works
   - Session context feels natural

CONSTRAINTS:
- Test both success and failure paths
- Include property-based tests for variable names/values
- Test concurrent access patterns
- Verify memory usage stays bounded
- Mock external dependencies

EXAMPLE:
```elixir
test "variables persist across Python calls" do
  session_id = "test-session"
  
  # Python sets variable
  PythonBridge.execute(session_id, "set_var", %{name: "config", value: %{temp: 0.7}})
  
  # Later Python call can read it
  {:ok, result} = PythonBridge.execute(session_id, "get_var", %{name: "config"})
  assert result == %{temp: 0.7}
end
```
```

**Expected Output**: Comprehensive test suite

### Conversation 8: Add Telemetry for Variables

**Objective**: Add observability to variable operations

**Source Documents**:
- `08_TELEMETRY_AND_OBSERVABILITY.md` - Session telemetry events

**Prompt**:
```text
CONTEXT:
We need telemetry for session variable operations as specified in our observability plan.
From 08_TELEMETRY_AND_OBSERVABILITY.md, session events:

--- PASTE lines 52-71 from 08_TELEMETRY_AND_OBSERVABILITY.md ---

TASK:
Add telemetry events to all variable operations:

1. Update VariableStore to emit:
   - [:dspex, :session, :variable, :set]
   - [:dspex, :session, :variable, :get]
   - [:dspex, :session, :variable, :delete]

2. Include measurements:
   - Size of variable value
   - Operation duration
   - Total variables in session

3. Include metadata:
   - session_id
   - variable_name
   - variable_type
   - found/not_found for gets

4. Add summary telemetry:
   - Session size growth
   - Most accessed variables
   - Variable type distribution

CONSTRAINTS:
- Don't emit sensitive values in telemetry
- Keep event names consistent with existing patterns
- Measure serialization time separately
- Include rate limiting metadata

EXAMPLE:
```elixir
:telemetry.execute(
  [:dspex, :session, :variable, :set],
  %{size: byte_size(value), duration: duration_us},
  %{
    session_id: session_id,
    var_name: name,
    var_type: type_of(value)
  }
)
```
```

**Expected Output**: Telemetry instrumentation

## Verification Checklist

After completing all conversations:

- [ ] Session variables work end-to-end
- [ ] Python can set/get variables naturally
- [ ] Variables persist across requests
- [ ] Sessions survive process restarts  
- [ ] Telemetry provides visibility
- [ ] Tests cover all scenarios
- [ ] Performance is acceptable
- [ ] Memory usage is bounded

## Integration Tests

Run these manual tests to verify everything works:

### Test 1: Basic Variable Flow
```elixir
# Elixir side
{:ok, _} = Session.Manager.set_variable("test-1", "name", "Alice")
{:ok, "Alice"} = Session.Manager.get_variable("test-1", "name")
```

### Test 2: Python Integration
```python
# Python side
session = bridge.get_session("test-2")
session.set_variable("config", {"temperature": 0.8})
config = session.get_variable("config")
assert config["temperature"] == 0.8
```

### Test 3: Persistence
```bash
# Set variable
iex> Session.Manager.set_variable("test-3", "data", "important")

# Restart the application
iex> System.stop()
iex> Application.start(:snakepit_grpc_bridge)

# Verify variable persisted
iex> Session.Manager.get_variable("test-3", "data")
{:ok, "important"}
```

## Common Issues and Solutions

### Issue: Variable Size Too Large
**Solution**: Implement size limits in VariableStore with clear errors

### Issue: Serialization Failures
**Solution**: Add fallback serialization for unknown types

### Issue: Memory Growth
**Solution**: Implement session expiry and variable count limits

### Issue: Race Conditions
**Solution**: Use GenServer.call (not cast) for all mutations

## Performance Considerations

1. **Lazy Loading**: Don't load all session variables on access
2. **Batch Operations**: Support setting multiple variables at once
3. **Compression**: Consider compressing large values
4. **Indexing**: If using database, index session_id
5. **Caching**: Cache frequently accessed variables

## Next Steps

After Slice 2 is complete:

1. Monitor telemetry for usage patterns
2. Optimize based on real usage
3. Consider Redis/database for persistence
4. Move to Slice 3: Bidirectional Bridge

## Summary

Slice 2 adds stateful session management:
- ✅ Variables stored per session
- ✅ Python transparent access
- ✅ Persistence across restarts
- ✅ Full observability
- ✅ Production-ready patterns

This enables DSPy components to maintain state across calls, a critical feature for complex AI workflows.
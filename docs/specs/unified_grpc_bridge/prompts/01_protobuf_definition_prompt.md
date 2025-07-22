# Prompt: Create Unified Protocol Buffer Definitions

## Objective
Create the complete protobuf definitions for the unified gRPC bridge that supports both tools and variables with streaming capabilities.

## Context
You need to create a `.proto` file that defines all messages and services for the unified bridge. This protocol will be the foundation for all client-server communication.

## Requirements

### Service Definition
Create a `BridgeService` with the following RPC methods:
1. `ExecuteTool` - Execute a tool (existing functionality)
2. `RegisterVariable` - Register a new variable
3. `GetVariable` - Get a variable's current value
4. `SetVariable` - Update a variable's value
5. `ListVariables` - List all variables in a session
6. `WatchVariables` - Stream variable updates (server streaming)
7. `GetSession` - Get session information
8. `Heartbeat` - Keep-alive mechanism

### Message Definitions

#### Core Messages
- `Variable` - Complete variable representation
- `VariableType` - Enum for all supported types
- `VariableValue` - Wrapper using protobuf Any
- `VariableConstraints` - Type-specific constraints
- `VariableMetadata` - Additional variable information

#### Request/Response Messages
- Define request and response messages for each RPC method
- Include session_id in all requests
- Support batch operations where appropriate

#### Streaming Messages
- `WatchVariablesRequest` - Subscribe to variables
- `VariableUpdate` - Streamed update message

### Type System
Support these types with proper serialization:
- float, integer, string, boolean (basic types)
- choice (enumeration with allowed values)
- module (DSPy module selection)
- embedding (vector representation)
- tensor (multi-dimensional arrays)

## Implementation Steps

1. **Create the proto file**:
   ```bash
   # Location: snakepit/priv/protos/bridge_service.proto
   ```

2. **Define the service**:
   ```protobuf
   service BridgeService {
     // Tool execution (existing)
     rpc ExecuteTool(ExecuteToolRequest) returns (ExecuteToolResponse);
     
     // Variable management (new)
     rpc RegisterVariable(RegisterVariableRequest) returns (RegisterVariableResponse);
     rpc GetVariable(GetVariableRequest) returns (GetVariableResponse);
     rpc SetVariable(SetVariableRequest) returns (SetVariableResponse);
     rpc ListVariables(ListVariablesRequest) returns (ListVariablesResponse);
     
     // Streaming (new)
     rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
     
     // Session management
     rpc GetSession(GetSessionRequest) returns (GetSessionResponse);
     rpc Heartbeat(HeartbeatRequest) returns (HeartbeatResponse);
   }
   ```

3. **Define core messages with proper Any usage**:
   ```protobuf
   import "google/protobuf/any.proto";
   import "google/protobuf/timestamp.proto";
   
   message Variable {
     string id = 1;
     string name = 2;
     VariableType type = 3;
     google.protobuf.Any value = 4;  // JSON-encoded for custom types
     VariableConstraints constraints = 5;
     VariableMetadata metadata = 6;
     int32 version = 7;
   }
   ```

4. **Implement type safety**:
   - Use oneof for constraint types
   - Define clear serialization rules
   - Include validation hints

5. **Add streaming support**:
   ```protobuf
   message VariableUpdate {
     string variable_id = 1;
     Variable variable = 2;
     google.protobuf.Any old_value = 3;
     string update_source = 4;
     map<string, string> update_metadata = 5;
     google.protobuf.Timestamp timestamp = 6;
     string update_type = 7; // "value_change", "constraint_change", "deleted"
   }
   ```

## Validation Checklist
- [ ] All existing tool functionality is preserved
- [ ] Variable CRUD operations are complete
- [ ] Streaming is properly defined
- [ ] Type system is comprehensive
- [ ] Session management is included
- [ ] Backward compatibility is maintained
- [ ] Comments document JSON encoding for Any fields

## Example Usage Pattern
After implementation, the protocol should support:
```python
# Python server
async def watch_variables(request, context):
    for update in variable_changes:
        yield VariableUpdate(...)

# Elixir client  
stream = Stub.watch_variables(channel, request)
Enum.each(stream, fn update -> 
  handle_update(update)
end)
```

## Files to Create/Modify
1. Create: `snakepit/priv/protos/bridge_service.proto`
2. Update: `snakepit/mix.exs` (if needed for protobuf compilation)
3. Create: `snakepit/priv/protos/README.md` (document the protocol)

## Next Steps
After creating the protobuf definitions:
1. Compile them for both Python and Elixir
2. Proceed to implement the Python server (next prompt)
3. Update the Elixir client to use new protocol
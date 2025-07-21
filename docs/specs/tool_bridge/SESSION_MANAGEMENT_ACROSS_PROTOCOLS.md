# Session Management Across Bridge Protocols

## Overview

This document details how session management works across all three bridge protocols (JSON, MessagePack, gRPC) and its implications for the Python tool bridge.

## Core Session Architecture

### 1. Centralized Session Store

```elixir
# Snakepit.Bridge.SessionStore
# Central ETS-based session storage used by all protocols

defmodule Snakepit.Bridge.SessionStore do
  @table_name :snakepit_sessions
  @default_ttl :timer.minutes(30)
  
  # Session structure
  # {session_id, data, last_accessed, ttl}
  
  def create(session_id, initial_data \\ %{}) do
    :ets.insert(@table_name, {
      session_id,
      initial_data,
      System.monotonic_time(:second),
      @default_ttl
    })
  end
  
  def update(session_id, updater) when is_function(updater, 1) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, data, _, ttl}] ->
        new_data = updater.(data)
        :ets.insert(@table_name, {
          session_id,
          new_data,
          System.monotonic_time(:second),
          ttl
        })
        {:ok, new_data}
      [] ->
        {:error, :not_found}
    end
  end
end
```

### 2. Session Flow Across Protocols

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Client    │────▶│ Protocol     │────▶│   Python    │
│             │     │ Adapter      │     │   Bridge    │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                     │
       │                    ▼                     │
       │            ┌──────────────┐              │
       └───────────▶│Session Store │◀─────────────┘
                    └──────────────┘
```

## Protocol-Specific Implementations

### 1. JSON/MessagePack Sessions

```elixir
# Session handling in stdin/stdout protocols
defmodule Snakepit.Worker do
  def handle_call({:execute_in_session, session_id, command, args}, from, state) do
    # Merge session data with request
    with {:ok, session_data} <- SessionStore.get(session_id) do
      enhanced_args = Map.merge(args, %{
        "__session_id__" => session_id,
        "__session_data__" => session_data
      })
      
      request = %{
        "id" => request_id,
        "command" => command,
        "args" => enhanced_args,
        "session_id" => session_id  # For Python-side tracking
      }
      
      # Send via stdin
      send_request(request, state)
    end
  end
end
```

Python side handling:
```python
class SessionAwareCommandHandler(BaseCommandHandler):
    def __init__(self):
        super().__init__()
        self.sessions = {}  # Local session cache
        
    def handle_command(self, command, args):
        session_id = args.get("__session_id__")
        
        if session_id:
            # Restore session context
            session_data = args.pop("__session_data__", {})
            self.sessions[session_id] = session_data
            
        # Execute command with session context
        result = self._execute_with_session(command, args, session_id)
        
        # Update session if needed
        if session_id and hasattr(result, "__session_update__"):
            self.sessions[session_id].update(result.__session_update__)
            
        return result
```

### 2. gRPC Sessions

```protobuf
// Session support in gRPC protocol
message SessionRequest {
  string session_id = 1;
  string command = 2;
  map<string, bytes> args = 3;
  int32 timeout_ms = 4;
  map<string, string> metadata = 5;  // Session metadata
}

message SessionResponse {
  string session_id = 1;
  bool success = 2;
  map<string, bytes> result = 3;
  string error = 4;
  map<string, string> session_updates = 5;  // Updates to session
}
```

```python
# gRPC session handling
class GRPCSessionHandler:
    def __init__(self):
        self.sessions = {}
        self.session_lock = threading.Lock()
        
    def ExecuteInSession(self, request, context):
        session_id = request.session_id
        
        # Thread-safe session access
        with self.session_lock:
            session = self.sessions.setdefault(session_id, {})
            
        # Execute with session context
        result = self.execute_with_session(
            request.command,
            self._unpack_args(request.args),
            session
        )
        
        # Prepare response with session updates
        response = SessionResponse(
            session_id=session_id,
            success=True,
            result=self._pack_result(result)
        )
        
        # Include session updates
        if hasattr(result, "__session_update__"):
            response.session_updates.update(result.__session_update__)
            
        return response
```

## Tool Bridge Session Integration

### 1. Session-Aware Tool Registry

```elixir
defmodule DSPex.SessionAwareToolRegistry do
  @moduledoc """
  Extends tool registry with session context
  """
  
  def register_for_session(session_id, function, opts \\ []) do
    tool_id = generate_session_tool_id(session_id)
    
    # Store with session context
    registration = %{
      mfa: Function.capture(function),
      session_id: session_id,
      expires_at: calculate_expiry(opts),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    :ets.insert(@registry_table, {tool_id, registration})
    {:ok, tool_id}
  end
  
  def lookup_with_session(tool_id) do
    case :ets.lookup(@registry_table, tool_id) do
      [{^tool_id, %{session_id: sid} = reg}] ->
        # Verify session is still valid
        case SessionStore.get(sid) do
          {:ok, session_data} ->
            {:ok, reg, session_data}
          _ ->
            {:error, :session_expired}
        end
      [] ->
        {:error, :not_found}
    end
  end
end
```

### 2. Session-Aware RPC Tools

```python
class SessionAwareRPCProxyTool:
    """Tool proxy that maintains session context"""
    
    def __init__(self, tool_id, session_id, protocol_handler):
        self.tool_id = tool_id
        self.session_id = session_id
        self.protocol_handler = protocol_handler
        
    def __call__(self, *args, **kwargs):
        # Include session context in RPC call
        rpc_request = {
            "type": "rpc_call",
            "rpc_id": generate_rpc_id(),
            "tool_id": self.tool_id,
            "session_id": self.session_id,  # Session context
            "args": args,
            "kwargs": kwargs
        }
        
        return self.protocol_handler.execute_rpc(rpc_request)
```

### 3. Stateful Tool Example

```elixir
defmodule MyApp.StatefulTools do
  @doc """
  Example of a stateful tool that accumulates context
  """
  def create_conversation_tool(session_id) do
    # Register a tool that maintains conversation history
    DSPex.SessionAwareToolRegistry.register_for_session(
      session_id,
      fn message ->
        # Get current conversation from session
        {:ok, session} = SessionStore.get(session_id)
        history = Map.get(session, :conversation_history, [])
        
        # Add new message
        new_history = history ++ [%{role: "user", content: message}]
        
        # Generate response based on history
        response = generate_contextual_response(new_history)
        
        # Update session with new history
        SessionStore.update(session_id, fn data ->
          Map.put(data, :conversation_history, 
            new_history ++ [%{role: "assistant", content: response}]
          )
        end)
        
        response
      end,
      metadata: %{type: "conversation", stateful: true}
    )
  end
end
```

## Session Lifecycle Management

### 1. Session Creation Patterns

```elixir
# Pattern 1: Explicit session creation
{:ok, session_id} = Snakepit.create_session()
{:ok, result} = Snakepit.execute_in_session(session_id, "command", args)

# Pattern 2: Auto-session with first call
session_id = "user_#{user_id}_#{timestamp}"
{:ok, result} = Snakepit.execute_in_session(session_id, "command", args)

# Pattern 3: Session with initial data
SessionStore.create(session_id, %{
  user_id: user_id,
  model_config: %{temperature: 0.7},
  tool_permissions: [:search, :calculate]
})
```

### 2. Session Cleanup

```elixir
defmodule Snakepit.SessionCleaner do
  use GenServer
  
  @cleanup_interval :timer.minutes(5)
  
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end
  
  def handle_info(:cleanup, state) do
    expired_sessions = SessionStore.get_expired()
    
    Enum.each(expired_sessions, fn {session_id, _data} ->
      # Clean up Python-side resources
      notify_python_cleanup(session_id)
      
      # Clean up session tools
      ToolRegistry.cleanup_session_tools(session_id)
      
      # Remove from store
      SessionStore.delete(session_id)
    end)
    
    schedule_cleanup()
    {:noreply, state}
  end
end
```

## Cross-Protocol Session Migration

### Migrating Sessions Between Protocols

```elixir
defmodule Snakepit.SessionMigration do
  @doc """
  Migrate a session from one protocol to another
  """
  def migrate_session(session_id, from_protocol, to_protocol) do
    with {:ok, session_data} <- SessionStore.get(session_id),
         {:ok, tools} <- migrate_tools(session_id, from_protocol, to_protocol) do
      
      # Update session metadata
      SessionStore.update(session_id, fn data ->
        Map.merge(data, %{
          protocol: to_protocol,
          migrated_at: DateTime.utc_now(),
          migrated_tools: tools
        })
      end)
      
      {:ok, session_id}
    end
  end
  
  defp migrate_tools(session_id, :json, :grpc) do
    # Re-register tools for new protocol
    # This may involve updating tool proxies
  end
end
```

## Performance Considerations

### 1. Session Storage Optimization

| Storage Type | Pros | Cons | Use Case |
|--------------|------|------|----------|
| ETS (default) | Fast, in-memory | Not distributed | Single-node |
| Redis | Distributed, persistent | Network overhead | Multi-node |
| Mnesia | Distributed, Erlang-native | Complex setup | Erlang clusters |

### 2. Session Data Best Practices

```elixir
# DO: Store minimal session data
session_data = %{
  user_id: user_id,
  model_id: model_id,
  tool_ids: [tool1, tool2]
}

# DON'T: Store large objects in session
session_data = %{
  full_conversation: [...],  # Store in separate cache
  model_weights: {...},      # Keep in Python process
  large_dataset: [...]       # Use references instead
}
```

## Testing Session Functionality

### 1. Unit Tests

```elixir
describe "session-aware tool execution" do
  test "tool maintains session context" do
    session_id = "test_session_#{System.unique_integer()}"
    
    # Create session with initial data
    SessionStore.create(session_id, %{counter: 0})
    
    # Register stateful tool
    {:ok, tool_id} = ToolRegistry.register_for_session(
      session_id,
      fn _args ->
        {:ok, data} = SessionStore.get(session_id)
        new_count = data.counter + 1
        SessionStore.update(session_id, &Map.put(&1, :counter, new_count))
        new_count
      end
    )
    
    # Execute tool multiple times
    assert execute_tool(tool_id) == 1
    assert execute_tool(tool_id) == 2
    assert execute_tool(tool_id) == 3
  end
end
```

### 2. Integration Tests

```python
# Test session persistence across protocols
async def test_session_across_protocols():
    session_id = "test_cross_protocol"
    
    # Create session via JSON protocol
    json_worker = await start_json_worker()
    await json_worker.execute_in_session(
        session_id, 
        "store_value", 
        {"key": "test", "value": "data"}
    )
    
    # Access same session via gRPC
    grpc_worker = await start_grpc_worker()
    result = await grpc_worker.execute_in_session(
        session_id,
        "get_value",
        {"key": "test"}
    )
    
    assert result["value"] == "data"
```

## Security Considerations

1. **Session Hijacking**: Use cryptographically secure session IDs
2. **Data Isolation**: Ensure sessions cannot access each other's data
3. **Tool Permissions**: Validate tool access per session
4. **Expiration**: Enforce strict TTLs for sensitive operations
5. **Audit Trail**: Log all session-based tool executions
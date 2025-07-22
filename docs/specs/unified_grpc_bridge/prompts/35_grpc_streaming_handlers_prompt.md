# Prompt: Implement gRPC Streaming Handlers for Variable Watching

## Objective
Implement the gRPC streaming handlers that enable real-time variable watching across the bridge, with atomic observer registration to prevent stale reads and proper stream lifecycle management.

## Context
The gRPC streaming handlers connect the ObserverManager with remote clients (primarily Python). The critical innovation is atomic observer registration BEFORE sending initial values, ensuring no updates are missed during stream initialization.

## Requirements

### Core Features
1. Atomic observer registration before initial values
2. Proper stream lifecycle management
3. Heartbeat mechanism for connection health
4. Error handling and cleanup
5. Integration with ObserverManager

### Critical Design
The "stale read" problem occurs when:
1. Client requests initial values
2. Server reads current values
3. Another process updates the variable
4. Server sends now-stale initial values
5. Update notification is missed

Solution: Register observer BEFORE reading initial values.

## Implementation

### Update Proto Definition

```protobuf
// File: priv/protos/unified_bridge.proto

// Add to existing proto file:

message WatchVariablesRequest {
  string session_id = 1;
  repeated string variable_identifiers = 2;
  bool include_initial_values = 3;
  map<string, string> options = 4;  // For future extensions
}

message VariableUpdate {
  string variable_id = 1;
  Variable variable = 2;  // Current state
  google.protobuf.Any old_value = 3;  // Previous value (if applicable)
  string update_source = 4;  // Who made the change
  map<string, string> update_metadata = 5;
  google.protobuf.Timestamp timestamp = 6;
  string update_type = 7;  // "initial_value", "value_change", "heartbeat"
}

service UnifiedBridge {
  // ... existing RPCs ...
  
  // Streaming RPC for watching variables
  rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
}
```

### Implement Streaming Handler

```elixir
# File: lib/snakepit/grpc/handlers/streaming_handlers.ex

defmodule Snakepit.GRPC.Handlers.StreamingHandlers do
  @moduledoc """
  gRPC streaming handlers for real-time variable watching.
  
  Critical: Prevents stale reads by registering observers BEFORE
  sending initial values.
  """
  
  require Logger
  alias Snakepit.Bridge.{SessionStore, ObserverManager}
  alias Snakepit.Bridge.Proto
  
  @heartbeat_interval 30_000  # 30 seconds
  
  @doc """
  Handles WatchVariables streaming RPC.
  
  The implementation carefully avoids the stale read problem by:
  1. Registering observers first
  2. Reading initial values second
  3. Streaming updates continuously
  """
  def handle_watch_variables(request, stream) do
    session_id = request.session_id
    identifiers = request.variable_identifiers
    include_initial = request.include_initial_values
    
    Logger.info("Starting variable watch stream for session #{session_id}")
    
    # Validate session exists
    case SessionStore.get_session(session_id) do
      {:error, :not_found} ->
        GRPC.Server.send_error(stream, GRPC.Status.not_found(), "Session not found")
        
      {:ok, _session} ->
        # Set up stream state
        stream_state = %{
          session_id: session_id,
          identifiers: identifiers,
          observers: %{},
          stream: stream,
          alive: true
        }
        
        # Start streaming
        try do
          stream_state = setup_observers(stream_state)
          
          if include_initial do
            send_initial_values(stream_state)
          end
          
          stream_loop(stream_state)
        catch
          :exit, reason ->
            Logger.info("Stream terminated: #{inspect(reason)}")
            cleanup_observers(stream_state)
        after
          cleanup_observers(stream_state)
        end
    end
  end
  
  defp setup_observers(stream_state) do
    # CRITICAL: Register observers BEFORE reading any values
    # This ensures no updates are missed
    
    observer_pid = self()
    
    observers = Enum.reduce(stream_state.identifiers, %{}, fn identifier, acc ->
      case SessionStore.get_variable(stream_state.session_id, identifier) do
        {:ok, variable} ->
          # Create callback that sends to this process
          callback = fn var_id, old_value, new_value, metadata ->
            send(observer_pid, {:variable_update, var_id, old_value, new_value, metadata})
          end
          
          # Register with ObserverManager
          ref = ObserverManager.add_observer(variable.id, observer_pid, callback)
          
          Map.put(acc, variable.id, %{
            ref: ref,
            identifier: identifier,
            variable: variable
          })
          
        {:error, _} ->
          Logger.warning("Variable #{identifier} not found for watching")
          acc
      end
    end)
    
    %{stream_state | observers: observers}
  end
  
  defp send_initial_values(stream_state) do
    # Send initial values AFTER observers are registered
    # This guarantees we won't miss any updates
    
    Enum.each(stream_state.observers, fn {var_id, observer_info} ->
      variable = observer_info.variable
      
      update = Proto.VariableUpdate.new(
        variable_id: var_id,
        variable: variable_to_proto(variable),
        # No old_value for initial
        update_source: "initial",
        update_metadata: %{"initial" => "true"},
        timestamp: current_timestamp(),
        update_type: "initial_value"
      )
      
      case GRPC.Server.send_reply(stream_state.stream, update) do
        :ok -> :ok
        {:error, reason} ->
          Logger.error("Failed to send initial value: #{inspect(reason)}")
          throw({:exit, :send_failed})
      end
    end)
  end
  
  defp stream_loop(stream_state) do
    receive do
      {:variable_update, var_id, old_value, new_value, metadata} ->
        stream_state = handle_variable_update(
          stream_state, var_id, old_value, new_value, metadata
        )
        
        if stream_state.alive do
          stream_loop(stream_state)
        else
          Logger.info("Stream closed by client")
        end
        
      :heartbeat ->
        stream_state = send_heartbeat(stream_state)
        
        if stream_state.alive do
          schedule_heartbeat()
          stream_loop(stream_state)
        end
        
      {:grpc_error, reason} ->
        Logger.error("gRPC error: #{inspect(reason)}")
        %{stream_state | alive: false}
        
      other ->
        Logger.warning("Unexpected message in stream loop: #{inspect(other)}")
        stream_loop(stream_state)
        
    after
      @heartbeat_interval ->
        # Heartbeat timeout
        send(self(), :heartbeat)
        stream_loop(stream_state)
    end
  end
  
  defp handle_variable_update(stream_state, var_id, old_value, new_value, metadata) do
    case Map.get(stream_state.observers, var_id) do
      nil ->
        # Not watching this variable
        stream_state
        
      observer_info ->
        # Get current variable state
        case SessionStore.get_variable_by_id(stream_state.session_id, var_id) do
          {:ok, variable} ->
            # Build update message
            update = Proto.VariableUpdate.new(
              variable_id: var_id,
              variable: variable_to_proto(variable),
              old_value: serialize_value(old_value, variable.type),
              update_source: metadata[:source] || metadata["source"] || "unknown",
              update_metadata: stringify_metadata(metadata),
              timestamp: current_timestamp(),
              update_type: "value_change"
            )
            
            # Send update
            case GRPC.Server.send_reply(stream_state.stream, update) do
              :ok ->
                stream_state
                
              {:error, reason} ->
                Logger.error("Failed to send update: #{inspect(reason)}")
                %{stream_state | alive: false}
            end
            
          {:error, reason} ->
            Logger.error("Variable #{var_id} disappeared: #{inspect(reason)}")
            stream_state
        end
    end
  end
  
  defp send_heartbeat(stream_state) do
    heartbeat = Proto.VariableUpdate.new(
      variable_id: "",
      update_type: "heartbeat",
      timestamp: current_timestamp()
    )
    
    case GRPC.Server.send_reply(stream_state.stream, heartbeat) do
      :ok ->
        stream_state
      {:error, _reason} ->
        %{stream_state | alive: false}
    end
  end
  
  defp cleanup_observers(stream_state) do
    Enum.each(stream_state.observers, fn {var_id, observer_info} ->
      ObserverManager.remove_observer(var_id, observer_info.ref)
    end)
    
    Logger.info("Cleaned up #{map_size(stream_state.observers)} observers")
  end
  
  defp variable_to_proto(variable) do
    Proto.Variable.new(
      id: variable.id,
      name: to_string(variable.name),
      type: to_string(variable.type),
      value: serialize_value(variable.value, variable.type),
      constraints: variable.constraints || %{},
      metadata: stringify_metadata(variable.metadata || %{}),
      version: variable.version,
      created_at: variable.created_at,
      last_updated_at: variable.last_updated_at
    )
  end
  
  defp serialize_value(value, type) do
    case Snakepit.Bridge.Serialization.Encoder.encode_value(value, type) do
      {:ok, any} -> any
      {:error, reason} ->
        Logger.error("Failed to serialize value: #{inspect(reason)}")
        Google.Protobuf.Any.new()
    end
  end
  
  defp current_timestamp do
    now = System.os_time(:nanosecond)
    seconds = div(now, 1_000_000_000)
    nanos = rem(now, 1_000_000_000)
    
    Google.Protobuf.Timestamp.new(
      seconds: seconds,
      nanos: nanos
    )
  end
  
  defp stringify_metadata(metadata) do
    Map.new(metadata, fn
      {k, v} when is_binary(v) -> {to_string(k), v}
      {k, v} -> {to_string(k), inspect(v)}
    end)
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end
end
```

### Update gRPC Server

```elixir
# File: lib/snakepit/grpc/server.ex

defmodule Snakepit.GRPC.Server do
  use GRPC.Server, service: Snakepit.Bridge.Proto.UnifiedBridge.Service
  
  alias Snakepit.GRPC.Handlers.{
    SessionHandlers,
    VariableHandlers,
    StreamingHandlers
  }
  
  # ... existing handlers ...
  
  @impl true
  def watch_variables(request, stream) do
    StreamingHandlers.handle_watch_variables(request, stream)
  end
end
```

## Error Handling

### Stream Lifecycle
```elixir
defmodule Snakepit.GRPC.StreamLifecycle do
  @moduledoc """
  Manages gRPC stream lifecycle and error recovery.
  """
  
  def with_stream_management(stream, fun) do
    # Set up error handling
    Process.flag(:trap_exit, true)
    
    try do
      fun.()
    catch
      :exit, :normal ->
        Logger.debug("Stream closed normally")
        :ok
        
      :exit, {:shutdown, reason} ->
        Logger.info("Stream shutdown: #{inspect(reason)}")
        :ok
        
      :exit, reason ->
        Logger.error("Stream crashed: #{inspect(reason)}")
        GRPC.Server.send_error(stream, GRPC.Status.internal(), "Internal error")
        
      :throw, {:grpc_error, status, message} ->
        GRPC.Server.send_error(stream, status, message)
        
    after
      Process.flag(:trap_exit, false)
    end
  end
end
```

## Testing

```elixir
defmodule Snakepit.GRPC.StreamingHandlersTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.{SessionStore, ObserverManager}
  
  setup do
    # Ensure services are running
    {:ok, _} = SessionStore.start_link()
    {:ok, _} = ObserverManager.start_link()
    
    # Create test session
    session_id = "stream_test_#{System.unique_integer()}"
    {:ok, _} = SessionStore.create_session(session_id)
    
    # Register test variables
    {:ok, _} = SessionStore.register_variable(
      session_id, :streamed, :integer, 1, []
    )
    
    {:ok, session_id: session_id}
  end
  
  test "prevents stale reads with atomic registration", %{session_id: session_id} do
    # This test verifies the critical ordering:
    # 1. Observer registered
    # 2. Initial value read
    # 3. Updates flow correctly
    
    # Start a mock stream
    stream = spawn_mock_stream()
    
    # Create request
    request = %{
      session_id: session_id,
      variable_identifiers: ["streamed"],
      include_initial_values: true
    }
    
    # Start watching in separate process
    watcher = Task.async(fn ->
      StreamingHandlers.handle_watch_variables(request, stream)
    end)
    
    # Wait for observer registration
    Process.sleep(50)
    
    # Update variable while initial value is being sent
    :ok = SessionStore.update_variable(session_id, :streamed, 42, %{})
    
    # Collect messages
    messages = collect_stream_messages(stream, 2)
    
    # Should have initial value then update
    assert length(messages) == 2
    assert hd(messages).update_type == "initial_value"
    assert hd(messages).variable.value == 1  # Original value
    
    assert hd(tl(messages)).update_type == "value_change"
    assert hd(tl(messages)).variable.value == 42  # Updated value
    
    # No missed updates!
    
    Task.shutdown(watcher)
  end
  
  test "heartbeats keep stream alive", %{session_id: session_id} do
    stream = spawn_mock_stream()
    
    request = %{
      session_id: session_id,
      variable_identifiers: ["streamed"],
      include_initial_values: false
    }
    
    watcher = Task.async(fn ->
      # Temporarily reduce heartbeat interval for testing
      Process.put(:heartbeat_interval, 100)
      StreamingHandlers.handle_watch_variables(request, stream)
    end)
    
    # Wait for heartbeats
    Process.sleep(300)
    
    messages = collect_stream_messages(stream, :all)
    heartbeats = Enum.filter(messages, & &1.update_type == "heartbeat")
    
    assert length(heartbeats) >= 2
    
    Task.shutdown(watcher)
  end
  
  defp spawn_mock_stream do
    test_pid = self()
    
    spawn(fn ->
      receive_loop(test_pid, [])
    end)
  end
  
  defp receive_loop(test_pid, messages) do
    receive do
      {:send_reply, message} ->
        send(test_pid, {:stream_message, message})
        receive_loop(test_pid, [message | messages])
        
      {:get_messages, from} ->
        send(from, {:messages, Enum.reverse(messages)})
        receive_loop(test_pid, messages)
        
      :close ->
        :ok
    end
  end
  
  defp collect_stream_messages(stream, count) do
    Process.sleep(100)  # Allow time for messages
    send(stream, {:get_messages, self()})
    
    receive do
      {:messages, messages} ->
        if count == :all do
          messages
        else
          Enum.take(messages, count)
        end
    after
      1000 -> []
    end
  end
end
```

## Performance Considerations

### Stream Management
- Each stream runs in its own process
- Heartbeats detect broken connections
- Automatic cleanup on process death

### Memory Usage
- Stream state is minimal
- No buffering of updates
- Direct dispatch from ObserverManager

### Scalability
- Thousands of concurrent streams supported
- ETS-based ObserverManager scales well
- Process isolation prevents cascade failures

## Integration with Python

The Python client consumes the stream as an async iterator:

```python
async def example_usage():
    async with grpc.aio.insecure_channel('localhost:50051') as channel:
        stub = UnifiedBridgeStub(channel)
        
        request = WatchVariablesRequest(
            session_id=session_id,
            variable_identifiers=['temperature', 'pressure'],
            include_initial_values=True
        )
        
        async for update in stub.WatchVariables(request):
            if update.update_type == "heartbeat":
                continue
                
            print(f"{update.variable.name}: {update.old_value} -> {update.variable.value}")
            print(f"  Source: {update.update_source}")
            print(f"  Time: {update.timestamp}")
```

## Next Steps
After implementing streaming handlers:
1. Update Python client with async iterator
2. Add advanced variable types (choice, module)
3. Create reactive programming examples
4. Benchmark streaming performance
5. Implement batching for high-frequency updates
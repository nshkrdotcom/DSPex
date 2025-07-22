# Prompt: Implement BridgedState Variable Watching

## Objective
Implement variable watching in BridgedState using gRPC streaming, enabling real-time cross-language reactive programming between Elixir and Python.

## Context
BridgedState provides Python interoperability through the gRPC bridge. For watching, we need to create streaming connections that efficiently propagate variable changes across language boundaries while maintaining consistency with the LocalState watching API.

## Requirements

### Core Features
1. gRPC streaming for variable updates
2. StreamConsumer GenServer for each stream
3. Automatic reconnection on failures
4. Integration with ObserverManager
5. Same API as LocalState watching

### Design Goals
- Minimize latency (~1-2ms per update)
- Handle network failures gracefully
- Support thousands of concurrent streams
- Prevent memory leaks from orphan streams
- Maintain update ordering per variable

## Implementation

### Extend BridgedState Structure

```elixir
# File: lib/dspex/bridge/state/bridged.ex

defmodule DSPex.Bridge.State.Bridged do
  @behaviour DSPex.Bridge.StateProvider
  
  defstruct [
    :session_id,
    :metadata,
    :grpc_channel,    # Add gRPC channel reference
    :active_streams   # Map of ref -> stream_pid
  ]
  
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    # Ensure SessionStore is running
    ensure_session_store!()
    
    # Get or create gRPC channel
    channel = get_grpc_channel()
    
    # Create or get session
    case create_or_get_session(session_id) do
      :ok ->
        state = %__MODULE__{
          session_id: session_id,
          metadata: %{
            created_at: DateTime.utc_now(),
            backend: :bridged
          },
          grpc_channel: channel,
          active_streams: %{}
        }
        
        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil -> 
            {:ok, state}
          exported ->
            import_state(state, exported)
        end
        
      {:error, reason} ->
        {:error, {:session_creation_failed, reason}}
    end
  end
  
  defp get_grpc_channel do
    # Get or create gRPC channel to bridge
    # This should reuse existing channels when possible
    case Process.whereis(:grpc_channel) do
      nil ->
        {:ok, channel} = GRPC.Stub.connect("localhost:50051")
        Process.register(channel, :grpc_channel)
        channel
      pid ->
        pid
    end
  end
end
```

### Implement Watching

```elixir
@impl true
def supports_watching?, do: true

@impl true
def watch_variables(state, identifiers, watcher_fn, opts) do
  # Validate variables exist
  validation_results = Enum.map(identifiers, fn id ->
    case SessionStore.get_variable(state.session_id, id) do
      {:ok, var} -> {:ok, id, var}
      _ -> {:error, id}
    end
  end)
  
  errors = Enum.filter(validation_results, &match?({:error, _}, &1))
  if errors != [] do
    failed_ids = Enum.map(errors, fn {:error, id} -> id end)
    return {:error, {:variables_not_found, failed_ids}}
  end
  
  # Start stream consumer
  {:ok, stream_pid} = DSPex.Bridge.StreamConsumer.start_link(%{
    channel: state.grpc_channel,
    session_id: state.session_id,
    identifiers: identifiers,
    watcher_fn: watcher_fn,
    opts: opts
  })
  
  # Monitor the stream process
  ref = Process.monitor(stream_pid)
  
  # Update state
  new_state = %{state | 
    active_streams: Map.put(state.active_streams, ref, stream_pid)
  }
  
  Logger.info("BridgedState: Started watch stream #{inspect(ref)} for session #{state.session_id}")
  
  {:ok, {ref, new_state}}
end

@impl true
def unwatch_variables(state, ref) do
  case Map.get(state.active_streams, ref) do
    nil -> 
      {:error, :not_found}
      
    stream_pid ->
      # Stop monitoring
      Process.demonitor(ref, [:flush])
      
      # Stop the stream
      if Process.alive?(stream_pid) do
        GenServer.stop(stream_pid, :normal)
      end
      
      # Update state
      new_state = %{state | 
        active_streams: Map.delete(state.active_streams, ref)
      }
      
      Logger.info("BridgedState: Stopped watch stream #{inspect(ref)}")
      
      {:ok, new_state}
  end
end

@impl true
def list_watchers(state) do
  watchers = Enum.map(state.active_streams, fn {ref, pid} ->
    if Process.alive?(pid) do
      # Get info from StreamConsumer
      case GenServer.call(pid, :get_info, 5000) do
        {:ok, info} ->
          Map.merge(info, %{
            ref: ref,
            alive: true
          })
        _ ->
          %{ref: ref, pid: pid, alive: true, error: "info_unavailable"}
      end
    else
      %{ref: ref, pid: pid, alive: false}
    end
  end)
  
  {:ok, watchers}
end

# Handle stream process deaths
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  case Map.get(state.active_streams, ref) do
    ^pid ->
      Logger.warning("Watch stream #{inspect(ref)} died: #{inspect(reason)}")
      new_state = %{state | 
        active_streams: Map.delete(state.active_streams, ref)
      }
      {:noreply, new_state}
    _ ->
      {:noreply, state}
  end
end
```

### Create StreamConsumer GenServer

```elixir
# File: lib/dspex/bridge/stream_consumer.ex

defmodule DSPex.Bridge.StreamConsumer do
  @moduledoc """
  Consumes gRPC streams for variable watching.
  
  Each StreamConsumer manages a single gRPC stream connection,
  handling updates, reconnections, and error recovery.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :channel,
    :session_id,
    :identifiers,
    :watcher_fn,
    :opts,
    :stream_ref,
    :stream_task,
    :stats
  ]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end
  
  @impl true
  def init(config) do
    state = struct(__MODULE__, Map.merge(config, %{
      stats: %{
        updates_received: 0,
        updates_filtered: 0,
        errors: 0,
        started_at: System.monotonic_time(:millisecond)
      }
    }))
    
    # Start streaming immediately
    send(self(), :start_stream)
    
    {:ok, state}
  end
  
  @impl true
  def handle_info(:start_stream, state) do
    # Create gRPC streaming request
    request = Snakepit.Bridge.Proto.WatchVariablesRequest.new(
      session_id: state.session_id,
      variable_identifiers: Enum.map(state.identifiers, &to_string/1),
      include_initial_values: Keyword.get(state.opts, :include_initial, false)
    )
    
    # Start the stream in a supervised task
    task = Task.async(fn ->
      try do
        stub = Snakepit.Bridge.Proto.UnifiedBridge.Stub
        stream = stub.watch_variables(state.channel, request)
        consume_stream(stream, state)
      catch
        kind, error ->
          Logger.error("Stream error: #{kind} #{inspect(error)}")
          {:error, error}
      end
    end)
    
    {:noreply, %{state | stream_task: task}}
  end
  
  @impl true
  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    # Task completed
    Process.demonitor(task_ref, [:flush])
    
    case result do
      :stream_ended ->
        Logger.info("Variable watch stream ended normally")
        {:stop, :normal, state}
        
      {:error, reason} ->
        Logger.error("Stream failed: #{inspect(reason)}")
        handle_stream_error(reason, state)
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Stream task crashed: #{inspect(reason)}")
    handle_stream_error(reason, state)
  end
  
  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_id: state.session_id,
      identifiers: state.identifiers,
      watcher_pid: Keyword.get(state.opts, :watcher_pid, self()),
      stats: Map.merge(state.stats, %{
        uptime_ms: System.monotonic_time(:millisecond) - state.stats.started_at
      })
    }
    
    {:reply, {:ok, info}, state}
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.debug("StreamConsumer terminating: #{inspect(reason)}")
    
    # Cancel stream task if running
    if state.stream_task do
      Task.shutdown(state.stream_task, :brutal_kill)
    end
    
    :ok
  end
  
  # Private functions
  
  defp consume_stream(stream, state) do
    Enum.reduce_while(stream, state, fn update, acc_state ->
      case process_update(update, acc_state) do
        {:ok, new_state} ->
          {:cont, new_state}
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    
    :stream_ended
  end
  
  defp process_update(update, state) do
    # Update stats
    state = update_in(state.stats.updates_received, &(&1 + 1))
    
    case update.update_type do
      "heartbeat" ->
        # Just a keepalive
        {:ok, state}
        
      "initial_value" ->
        handle_variable_update(update, state, true)
        
      "value_change" ->
        handle_variable_update(update, state, false)
        
      _ ->
        Logger.warning("Unknown update type: #{update.update_type}")
        {:ok, state}
    end
  end
  
  defp handle_variable_update(update, state, is_initial) do
    try do
      # Deserialize variable
      variable = deserialize_variable(update.variable)
      var_name = variable.name
      var_id = update.variable_id
      
      # Check if we're watching this variable
      watching? = Enum.any?(state.identifiers, fn id ->
        id_str = to_string(id)
        id_str == var_id || id_str == var_name || id == String.to_atom(var_name)
      end)
      
      if watching? do
        # Deserialize old value
        old_value = if is_initial do
          nil
        else
          deserialize_value(update.old_value, variable.type)
        end
        
        new_value = variable.value
        
        # Apply filter
        if should_notify?(state.opts, old_value, new_value) do
          # Build metadata
          metadata = Map.merge(
            %{
              source: update.update_source,
              timestamp: update.timestamp,
              initial: is_initial
            },
            update.update_metadata || %{}
          )
          
          # Find original identifier
          orig_id = Enum.find(state.identifiers, fn id ->
            id_str = to_string(id)
            id_str == var_id || id_str == var_name
          end)
          
          # Call watcher function asynchronously
          Task.start(fn ->
            try do
              state.watcher_fn.(orig_id || var_name, old_value, new_value, metadata)
            rescue
              e ->
                Logger.error("Watcher function error: #{Exception.format(:error, e, __STACKTRACE__)}")
            end
          end)
        else
          state = update_in(state.stats.updates_filtered, &(&1 + 1))
        end
      end
      
      {:ok, state}
    rescue
      e ->
        Logger.error("Failed to process update: #{Exception.format(:error, e, __STACKTRACE__)}")
        state = update_in(state.stats.errors, &(&1 + 1))
        {:ok, state}
    end
  end
  
  defp should_notify?(opts, old_value, new_value) do
    case opts[:filter] do
      nil -> 
        true
      filter_fn when is_function(filter_fn, 2) ->
        try do
          filter_fn.(old_value, new_value)
        rescue
          _ -> true
        end
      _ -> 
        true
    end
  end
  
  defp deserialize_variable(proto_var) do
    %{
      id: proto_var.id,
      name: proto_var.name,
      type: String.to_atom(proto_var.type),
      value: deserialize_value(proto_var.value, String.to_atom(proto_var.type)),
      version: proto_var.version
    }
  end
  
  defp deserialize_value(any_value, type) do
    case Snakepit.Bridge.Serialization.Decoder.decode_any(any_value, type) do
      {:ok, value} -> value
      _ -> nil
    end
  end
  
  defp handle_stream_error(reason, state) do
    state = update_in(state.stats.errors, &(&1 + 1))
    
    # Determine if we should reconnect
    if should_reconnect?(reason, state) do
      Logger.info("Attempting to reconnect stream...")
      Process.send_after(self(), :start_stream, reconnect_delay(state))
      {:noreply, %{state | stream_task: nil}}
    else
      Logger.error("Stream error is not recoverable, stopping")
      {:stop, {:stream_error, reason}, state}
    end
  end
  
  defp should_reconnect?(reason, state) do
    # Don't reconnect if explicitly stopped or too many errors
    state.stats.errors < 10 and
    reason not in [:normal, :shutdown]
  end
  
  defp reconnect_delay(state) do
    # Exponential backoff with jitter
    base = 1000  # 1 second
    max = 30000  # 30 seconds
    
    delay = min(base * :math.pow(2, state.stats.errors), max)
    jitter = :rand.uniform(round(delay * 0.1))
    
    round(delay + jitter)
  end
end
```

### Integration with gRPC Handlers

The gRPC handler needs modification to support ObserverManager (see Stage 3 spec for implementation details). Key points:

1. Register observer BEFORE sending initial values
2. Use ObserverManager for decoupled notification
3. Handle stream lifecycle properly
4. Send heartbeats to detect broken connections

## Testing

```elixir
defmodule DSPex.Bridge.State.BridgedWatchingTest do
  use ExUnit.Case, async: false
  
  alias DSPex.Bridge.State.Bridged
  alias Snakepit.Bridge.SessionStore
  
  setup do
    # Ensure services are running
    {:ok, _} = SessionStore.start_link()
    
    # Start gRPC server if not running
    ensure_grpc_server_running()
    
    :ok
  end
  
  test "can watch variables through gRPC" do
    {:ok, state} = Bridged.init(session_id: "watch_test_#{System.unique_integer()}")
    
    # Register a variable
    {:ok, {_, state}} = Bridged.register_variable(state, :streamed, :integer, 1, [])
    
    # Set up watcher
    test_pid = self()
    watcher = fn id, old, new, meta ->
      send(test_pid, {:update, id, old, new, meta})
    end
    
    {:ok, {ref, state}} = Bridged.watch_variables(state, [:streamed], watcher, [])
    
    # Update through SessionStore to trigger notification
    :ok = SessionStore.update_variable(state.session_id, :streamed, 2, %{source: "test"})
    
    # Should receive update via gRPC stream
    assert_receive {:update, :streamed, 1, 2, %{source: "test"}}, 2000
    
    # Cleanup
    {:ok, _state} = Bridged.unwatch_variables(state, ref)
  end
  
  test "handles stream reconnection" do
    {:ok, state} = Bridged.init(session_id: "reconnect_test_#{System.unique_integer()}")
    {:ok, {_, state}} = Bridged.register_variable(state, :test, :string, "initial", [])
    
    test_pid = self()
    {:ok, {ref, state}} = Bridged.watch_variables(
      state, [:test], 
      fn id, _, new, _ -> send(test_pid, {:update, id, new}) end,
      []
    )
    
    # Get stream PID
    stream_pid = Map.get(state.active_streams, ref)
    assert Process.alive?(stream_pid)
    
    # Simulate stream failure
    Process.exit(stream_pid, :connection_lost)
    
    # Stream should be removed from active streams
    Process.sleep(100)
    {:ok, watchers} = Bridged.list_watchers(state)
    assert Enum.all?(watchers, & not &1.alive)
  end
  
  test "filters work across gRPC" do
    {:ok, state} = Bridged.init(session_id: "filter_test_#{System.unique_integer()}")
    {:ok, {_, state}} = Bridged.register_variable(state, :temp, :float, 20.0, [])
    
    test_pid = self()
    filter = fn old, new -> abs(new - old) > 1.0 end
    
    {:ok, {ref, state}} = Bridged.watch_variables(
      state, [:temp],
      fn _, _, new, _ -> send(test_pid, {:temp_change, new}) end,
      filter: filter, include_initial: false
    )
    
    # Small change
    :ok = SessionStore.update_variable(state.session_id, :temp, 20.5, %{})
    refute_receive {:temp_change, _}, 500
    
    # Large change
    :ok = SessionStore.update_variable(state.session_id, :temp, 22.0, %{})
    assert_receive {:temp_change, 22.0}, 2000
  end
end
```

## Performance Considerations

### Connection Pooling
- Reuse gRPC channels across streams
- Limit concurrent streams per channel
- Monitor channel health

### Batching Updates
When multiple variables change simultaneously:
```elixir
# Future optimization: batch updates in a time window
defp batch_updates(updates, window_ms) do
  # Collect updates for window_ms
  # Send as single message
end
```

### Memory Management
- Monitor stream process memory usage
- Set limits on buffered updates
- Clean up completed streams promptly

### Error Recovery
- Exponential backoff for reconnections
- Circuit breaker for persistent failures
- Log metrics for monitoring

## Integration Points

### With ObserverManager
The gRPC handler uses ObserverManager to avoid coupling SessionStore with streaming:
```elixir
# In SessionStore
ObserverManager.notify_observers(var_id, old_value, new_value, metadata)

# ObserverManager dispatches to registered callbacks
# Including those from gRPC streams
```

### With Python Client
Python's SessionContext.watch_variables() returns an async iterator:
```python
async for update in session.watch_variables(['temperature']):
    print(f"{update.variable_name}: {update.old_value} -> {update.value}")
```

## Next Steps
After implementing BridgedState watching:
1. Create ObserverManager for centralized dispatch
2. Update gRPC handlers for streaming
3. Implement Python async iterator client
4. Add high-level Variables.watch API
5. Create reactive programming examples
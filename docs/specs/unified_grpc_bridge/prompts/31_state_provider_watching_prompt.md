# Prompt: Extend StateProvider for Variable Watching

## Objective
Extend the StateProvider behaviour to support variable watching, enabling reactive programming patterns across all backend implementations.

## Context
The StateProvider behaviour defines the contract for state backends. By adding watching capabilities at this level, we ensure all backends can support reactive patterns while allowing backend-specific optimizations.

## Requirements

### New Callbacks
1. `watch_variables/4` - Register a watcher for variable changes
2. `unwatch_variables/2` - Stop watching variables
3. `list_watchers/1` - Get active watchers (for debugging)

### Design Principles
- Watching should be optional (backends can return {:error, :not_supported})
- Callbacks should be invoked asynchronously
- Process cleanup must be automatic
- Support for filtering and options

## Implementation

### Update StateProvider Behaviour

```elixir
# File: lib/dspex/bridge/state_provider.ex

defmodule DSPex.Bridge.StateProvider do
  # ... existing code ...

  @doc """
  Watch variables for changes.
  
  The watcher_fn will be called with (identifier, old_value, new_value, metadata)
  whenever a watched variable changes.
  
  ## Options
    * `:watcher_pid` - Process to monitor for cleanup (default: self())
    * `:include_initial` - Send current values immediately (default: false)
    * `:filter` - Function (old, new) -> boolean to filter updates
    * `:debounce_ms` - Minimum milliseconds between updates
    
  ## Returns
    * `{:ok, {reference(), state}}` - Success with watch reference
    * `{:error, :not_supported}` - Backend doesn't support watching
    * `{:error, reason}` - Other error
  """
  @callback watch_variables(
    state,
    identifiers :: [identifier()],
    watcher_fn :: (identifier(), any(), any(), map() -> any()),
    opts :: keyword()
  ) :: {:ok, {reference(), state}} | error()
  
  @doc """
  Stop watching variables.
  
  ## Returns
    * `{:ok, state}` - Successfully stopped watching
    * `{:error, :not_found}` - Reference not found
    * `{:error, reason}` - Other error
  """
  @callback unwatch_variables(state, reference()) :: {:ok, state} | error()
  
  @doc """
  List all active watchers.
  
  Returns a list of watcher information for debugging.
  Each entry contains at least:
    * `:ref` - The watch reference
    * `:identifiers` - Variables being watched
    * `:watcher_pid` - Process receiving updates
    * `:alive` - Whether the process is still alive
  """
  @callback list_watchers(state) :: {:ok, [map()]} | error()
  
  @doc """
  Check if this provider supports watching.
  
  Default implementation returns false.
  """
  @callback supports_watching?() :: boolean()
  
  # Default implementations
  
  @doc false
  def __using__(_opts) do
    quote do
      @behaviour DSPex.Bridge.StateProvider
      
      # Default implementations for watching
      def watch_variables(_state, _identifiers, _watcher_fn, _opts) do
        {:error, :not_supported}
      end
      
      def unwatch_variables(_state, _ref) do
        {:error, :not_supported}
      end
      
      def list_watchers(_state) do
        {:ok, []}
      end
      
      def supports_watching?, do: false
      
      defoverridable [
        watch_variables: 4,
        unwatch_variables: 2,
        list_watchers: 1,
        supports_watching?: 0
      ]
    end
  end
end
```

## Watcher Function Contract

The watcher function receives four arguments:
1. `identifier` - The variable name or ID (as originally requested)
2. `old_value` - Previous value (nil for initial values)
3. `new_value` - Current value
4. `metadata` - Map with update metadata:
   - `:source` - Who made the change
   - `:timestamp` - When the change occurred
   - `:initial` - Whether this is an initial value
   - Additional backend-specific metadata

Example watcher function:
```elixir
fn identifier, old_value, new_value, metadata ->
  IO.puts("#{identifier} changed from #{inspect(old_value)} to #{inspect(new_value)}")
  
  if metadata[:source] == "optimization" do
    Logger.info("Optimization updated #{identifier}")
  end
end
```

## Backend Implementation Guidelines

### Process Monitoring
Backends MUST monitor the watcher process and clean up when it dies:
```elixir
ref = Process.monitor(watcher_pid)
# Store ref -> watcher mapping
# Handle {:DOWN, ref, :process, pid, reason} messages
```

### Notification Ordering
- If `include_initial: true`, send current values BEFORE any updates
- Preserve update order within a single variable
- No ordering guarantees across different variables

### Error Handling
- Watcher functions may crash - isolate with Task.start or try/catch
- Network errors in streaming should be logged but not crash
- Invalid references should return {:error, :not_found}

### Performance Considerations
- Batch notifications when possible
- Apply filters before invoking callbacks
- Use async notification (don't block on watcher function)
- Consider debouncing for high-frequency updates

## Testing Requirements

### Basic Functionality
```elixir
test "can watch and receive updates" do
  {:ok, state} = Provider.init([])
  {:ok, {_, state}} = Provider.register_variable(state, :test, :integer, 1, [])
  
  test_pid = self()
  watcher = fn id, old, new, _meta ->
    send(test_pid, {:update, id, old, new})
  end
  
  {:ok, {ref, state}} = Provider.watch_variables(state, [:test], watcher, [])
  {:ok, state} = Provider.set_variable(state, :test, 2, %{})
  
  assert_receive {:update, :test, 1, 2}
  
  {:ok, state} = Provider.unwatch_variables(state, ref)
end
```

### Process Cleanup
```elixir
test "cleans up when watcher process dies" do
  {:ok, state} = Provider.init([])
  
  watcher_pid = spawn(fn ->
    receive do: (:stop -> :ok)
  end)
  
  {:ok, {ref, state}} = Provider.watch_variables(
    state, [:test], fn _, _, _, _ -> :ok end,
    watcher_pid: watcher_pid
  )
  
  {:ok, watchers} = Provider.list_watchers(state)
  assert length(watchers) == 1
  
  Process.exit(watcher_pid, :kill)
  Process.sleep(10)
  
  {:ok, watchers} = Provider.list_watchers(state)
  assert Enum.all?(watchers, & not &1.alive)
end
```

### Filtering
```elixir
test "applies filter function" do
  filter = fn old, new -> abs(new - old) > 0.5 end
  
  {:ok, {ref, state}} = Provider.watch_variables(
    state, [:value], watcher,
    filter: filter
  )
  
  # Small change - no notification
  {:ok, state} = Provider.set_variable(state, :value, 0.3, %{})
  refute_receive {:update, _, _, _}
  
  # Large change - notification
  {:ok, state} = Provider.set_variable(state, :value, 1.0, %{})
  assert_receive {:update, :value, 0.3, 1.0}
end
```

## Migration Guide

For existing StateProvider implementations:
1. Add `use DSPex.Bridge.StateProvider` to get defaults
2. Override `supports_watching?` to return true if implementing
3. Implement the three watching callbacks
4. Add process monitoring for cleanup
5. Test with the StateProviderTest shared tests

## Next Steps
After extending StateProvider:
1. Implement watching in LocalState (process-based)
2. Implement watching in BridgedState (gRPC-based)
3. Create ObserverManager for centralized dispatch
4. Add high-level Variables.watch API
5. Test cross-backend compatibility
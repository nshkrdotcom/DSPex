# Prompt: Create ObserverManager for Decoupled Notifications

## Objective
Implement ObserverManager to decouple the SessionStore from stream management complexity, enabling efficient notification dispatch to thousands of concurrent watchers without impacting core variable operations.

## Context
The ObserverManager acts as a notification hub between variable updates and watchers. By separating this concern from SessionStore, we achieve:
- Better separation of concerns
- Scalable observer management
- Isolated failure handling
- Performance optimization opportunities

## Requirements

### Core Features
1. Centralized observer registration
2. Efficient notification dispatch
3. Process monitoring and cleanup
4. Atomic operations for race condition prevention
5. Performance metrics and monitoring

### Design Goals
- Support thousands of observers per variable
- Sub-millisecond notification dispatch
- Zero memory leaks from dead observers
- Graceful degradation under load
- Clear debugging and introspection

## Implementation

### Create ObserverManager Module

```elixir
# File: lib/snakepit/bridge/observer_manager.ex

defmodule Snakepit.Bridge.ObserverManager do
  @moduledoc """
  Manages variable observers for the bridge system.
  
  The ObserverManager decouples the SessionStore from notification
  complexity, providing a scalable way to manage thousands of
  concurrent observers.
  
  ## Architecture
  
  - Uses ETS for fast concurrent reads
  - Single GenServer for write coordination
  - Automatic cleanup of dead observers
  - Batched operations for efficiency
  
  ## Performance
  
  - Observer lookup: O(1) average case
  - Notification dispatch: O(n) where n = observers for variable
  - Cleanup: O(m) where m = observers for dead process
  """
  
  use GenServer
  require Logger
  
  @table_name :observer_manager_table
  @cleanup_interval 30_000  # 30 seconds
  
  defstruct [
    :table,
    :monitors,
    :stats
  ]
  
  ## Client API
  
  @doc """
  Starts the ObserverManager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Adds an observer for a variable.
  
  The callback will be invoked with (var_id, old_value, new_value, metadata)
  when the variable changes.
  
  Returns a unique reference for this observer.
  """
  @spec add_observer(String.t(), pid(), function()) :: reference()
  def add_observer(var_id, observer_pid, callback) do
    ref = make_ref()
    GenServer.call(__MODULE__, {:add_observer, var_id, observer_pid, callback, ref})
    ref
  end
  
  @doc """
  Removes an observer.
  """
  @spec remove_observer(String.t(), reference()) :: :ok
  def remove_observer(var_id, ref) do
    GenServer.cast(__MODULE__, {:remove_observer, var_id, ref})
  end
  
  @doc """
  Notifies all observers of a variable change.
  
  This is called by SessionStore when variables are updated.
  Returns immediately - notifications happen asynchronously.
  """
  @spec notify_observers(String.t(), any(), any(), map()) :: :ok
  def notify_observers(var_id, old_value, new_value, metadata) do
    # Skip if value unchanged
    if old_value == new_value do
      :ok
    else
      # Read observers directly from ETS for performance
      observers = :ets.lookup(@table_name, var_id)
      
      # Dispatch notifications asynchronously
      if observers != [] do
        Task.start(fn ->
          dispatch_notifications(observers, var_id, old_value, new_value, metadata)
        end)
      end
      
      :ok
    end
  end
  
  @doc """
  Gets observer count for a variable.
  """
  @spec observer_count(String.t()) :: non_neg_integer()
  def observer_count(var_id) do
    case :ets.lookup(@table_name, var_id) do
      [] -> 0
      [{^var_id, observers}] -> map_size(observers)
    end
  end
  
  @doc """
  Gets total observer count across all variables.
  """
  @spec total_observers() :: non_neg_integer()
  def total_observers do
    :ets.foldl(fn {_var_id, observers}, acc ->
      acc + map_size(observers)
    end, 0, @table_name)
  end
  
  @doc """
  Gets statistics about the ObserverManager.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    # Create ETS table for fast concurrent reads
    table = :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    state = %__MODULE__{
      table: table,
      monitors: %{},  # monitor_ref -> {var_id, observer_ref}
      stats: %{
        observers_added: 0,
        observers_removed: 0,
        notifications_sent: 0,
        cleanup_runs: 0,
        started_at: System.monotonic_time(:millisecond)
      }
    }
    
    Logger.info("ObserverManager started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:add_observer, var_id, observer_pid, callback, ref}, _from, state) do
    # Create observer entry
    observer = %{
      ref: ref,
      pid: observer_pid,
      callback: callback,
      added_at: System.monotonic_time(:millisecond)
    }
    
    # Update ETS table
    :ets.update_counter(@table_name, var_id, {2, 0}, {var_id, %{}})
    :ets.update_element(@table_name, var_id, {2, fn observers ->
      Map.put(observers, ref, observer)
    end})
    
    # Monitor the observer process
    monitor_ref = Process.monitor(observer_pid)
    
    # Update state
    new_state = %{state |
      monitors: Map.put(state.monitors, monitor_ref, {var_id, ref}),
      stats: Map.update!(state.stats, :observers_added, &(&1 + 1))
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      active_observers: total_observers(),
      monitored_processes: map_size(state.monitors),
      uptime_ms: System.monotonic_time(:millisecond) - state.stats.started_at
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:remove_observer, var_id, ref}, state) do
    # Remove from ETS
    case :ets.lookup(@table_name, var_id) do
      [{^var_id, observers}] ->
        case Map.get(observers, ref) do
          nil ->
            {:noreply, state}
            
          observer ->
            # Remove observer
            new_observers = Map.delete(observers, ref)
            
            if map_size(new_observers) == 0 do
              # No more observers for this variable
              :ets.delete(@table_name, var_id)
            else
              :ets.update_element(@table_name, var_id, {2, new_observers})
            end
            
            # Find and remove monitor
            {monitor_ref, new_monitors} = Enum.find_value(state.monitors, {nil, state.monitors}, 
              fn {mon_ref, {obs_var_id, obs_ref}} ->
                if obs_var_id == var_id and obs_ref == ref do
                  Process.demonitor(mon_ref, [:flush])
                  {mon_ref, Map.delete(state.monitors, mon_ref)}
                else
                  nil
                end
              end
            )
            
            new_state = %{state |
              monitors: new_monitors,
              stats: Map.update!(state.stats, :observers_removed, &(&1 + 1))
            }
            
            {:noreply, new_state}
        end
        
      [] ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}
        
      {var_id, observer_ref} ->
        # Remove observer
        remove_observer_internal(var_id, observer_ref)
        
        # Update state
        new_state = %{state |
          monitors: Map.delete(state.monitors, monitor_ref),
          stats: Map.update!(state.stats, :observers_removed, &(&1 + 1))
        }
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Periodic cleanup of dead observers
    dead_count = cleanup_dead_observers()
    
    if dead_count > 0 do
      Logger.info("ObserverManager cleanup removed #{dead_count} dead observers")
    end
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    new_state = %{state |
      stats: Map.update!(state.stats, :cleanup_runs, &(&1 + 1))
    }
    
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp dispatch_notifications([{var_id, observers}], var_id, old_value, new_value, metadata) do
    # Update stats
    GenServer.cast(__MODULE__, {:update_stats, :notifications_sent, map_size(observers)})
    
    # Notify each observer
    Enum.each(observers, fn {_ref, observer} ->
      if Process.alive?(observer.pid) do
        # Run callback in separate process to prevent blocking
        Task.start(fn ->
          try do
            observer.callback.(var_id, old_value, new_value, metadata)
          rescue
            e ->
              Logger.error("Observer callback error: #{Exception.format(:error, e, __STACKTRACE__)}")
          end
        end)
      end
    end)
  end
  
  defp dispatch_notifications([], _var_id, _old_value, _new_value, _metadata), do: :ok
  
  defp remove_observer_internal(var_id, ref) do
    case :ets.lookup(@table_name, var_id) do
      [{^var_id, observers}] ->
        new_observers = Map.delete(observers, ref)
        
        if map_size(new_observers) == 0 do
          :ets.delete(@table_name, var_id)
        else
          :ets.update_element(@table_name, var_id, {2, new_observers})
        end
        
      [] ->
        :ok
    end
  end
  
  defp cleanup_dead_observers do
    # Find all dead observers
    dead_observers = :ets.foldl(fn {var_id, observers}, acc ->
      dead = Enum.filter(observers, fn {ref, observer} ->
        not Process.alive?(observer.pid)
      end)
      
      if dead != [] do
        [{var_id, dead} | acc]
      else
        acc
      end
    end, [], @table_name)
    
    # Remove dead observers
    removed_count = Enum.reduce(dead_observers, 0, fn {var_id, dead}, count ->
      Enum.each(dead, fn {ref, _observer} ->
        remove_observer_internal(var_id, ref)
      end)
      
      count + length(dead)
    end)
    
    removed_count
  end
  
  @impl true
  def handle_cast({:update_stats, key, increment}, state) do
    new_state = update_in(state.stats[key], &(&1 + increment))
    {:noreply, new_state}
  end
end
```

### Integration with SessionStore

```elixir
# In SessionStore, when updating a variable:

defp notify_variable_change(session_id, var_id, old_value, new_value, metadata) do
  # Add session context to metadata
  enhanced_metadata = Map.merge(metadata, %{
    session_id: session_id,
    timestamp: System.monotonic_time(:millisecond)
  })
  
  # Delegate to ObserverManager
  ObserverManager.notify_observers(var_id, old_value, new_value, enhanced_metadata)
end
```

### Supervisor Configuration

```elixir
# File: lib/snakepit/bridge/supervisor.ex

defmodule Snakepit.Bridge.Supervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      # ObserverManager should start before SessionStore
      {Snakepit.Bridge.ObserverManager, []},
      {Snakepit.Bridge.SessionStore, []},
      # ... other children
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Performance Optimizations

### ETS Table Design
- Public table for direct reads
- Write/read concurrency enabled
- Observer data stored as maps for fast updates

### Notification Dispatch
- Asynchronous dispatch prevents blocking
- Task.start isolates callback failures
- Batch stat updates to reduce contention

### Memory Management
- Periodic cleanup removes dead observers
- Monitor-based cleanup for immediate removal
- Efficient ref-based lookups

## Testing

```elixir
defmodule Snakepit.Bridge.ObserverManagerTest do
  use ExUnit.Case, async: true
  
  alias Snakepit.Bridge.ObserverManager
  
  setup do
    # Ensure ObserverManager is running
    case GenServer.whereis(ObserverManager) do
      nil -> {:ok, _} = ObserverManager.start_link()
      _ -> :ok
    end
    
    :ok
  end
  
  test "can add and notify observers" do
    var_id = "test_var_#{System.unique_integer()}"
    test_pid = self()
    
    callback = fn id, old, new, meta ->
      send(test_pid, {:notification, id, old, new, meta})
    end
    
    # Add observer
    ref = ObserverManager.add_observer(var_id, self(), callback)
    assert is_reference(ref)
    
    # Check observer count
    assert ObserverManager.observer_count(var_id) == 1
    
    # Trigger notification
    ObserverManager.notify_observers(var_id, "old", "new", %{source: "test"})
    
    # Should receive notification
    assert_receive {:notification, ^var_id, "old", "new", %{source: "test"}}, 1000
    
    # Remove observer
    ObserverManager.remove_observer(var_id, ref)
    assert ObserverManager.observer_count(var_id) == 0
  end
  
  test "cleans up observers when process dies" do
    var_id = "cleanup_test_#{System.unique_integer()}"
    
    # Create observer in separate process
    {:ok, observer_pid} = Task.start(fn ->
      receive do: (:block -> :ok)
    end)
    
    ref = ObserverManager.add_observer(var_id, observer_pid, fn _, _, _, _ -> :ok end)
    assert ObserverManager.observer_count(var_id) == 1
    
    # Kill observer process
    Process.exit(observer_pid, :kill)
    Process.sleep(50)
    
    # Observer should be cleaned up
    assert ObserverManager.observer_count(var_id) == 0
  end
  
  test "handles concurrent observers" do
    var_id = "concurrent_test_#{System.unique_integer()}"
    test_pid = self()
    
    # Add multiple observers
    refs = for i <- 1..10 do
      callback = fn id, old, new, _meta ->
        send(test_pid, {:notification, i, id, old, new})
      end
      
      ObserverManager.add_observer(var_id, self(), callback)
    end
    
    assert ObserverManager.observer_count(var_id) == 10
    
    # Notify all
    ObserverManager.notify_observers(var_id, 0, 1, %{})
    
    # Should receive all notifications
    for i <- 1..10 do
      assert_receive {:notification, ^i, ^var_id, 0, 1}, 1000
    end
    
    # Remove all
    Enum.each(refs, &ObserverManager.remove_observer(var_id, &1))
    assert ObserverManager.observer_count(var_id) == 0
  end
  
  test "skips notification when value unchanged" do
    var_id = "skip_test_#{System.unique_integer()}"
    test_pid = self()
    
    ObserverManager.add_observer(var_id, self(), fn _, _, _, _ ->
      send(test_pid, :should_not_receive)
    end)
    
    # Same old and new value
    ObserverManager.notify_observers(var_id, "same", "same", %{})
    
    # Should not receive notification
    refute_receive :should_not_receive, 100
  end
  
  test "provides accurate statistics" do
    initial_stats = ObserverManager.get_stats()
    
    var_id = "stats_test_#{System.unique_integer()}"
    ref = ObserverManager.add_observer(var_id, self(), fn _, _, _, _ -> :ok end)
    
    # Trigger notification
    ObserverManager.notify_observers(var_id, 1, 2, %{})
    Process.sleep(50)
    
    ObserverManager.remove_observer(var_id, ref)
    
    final_stats = ObserverManager.get_stats()
    
    assert final_stats.observers_added > initial_stats.observers_added
    assert final_stats.observers_removed > initial_stats.observers_removed
    assert final_stats.notifications_sent > initial_stats.notifications_sent
  end
end
```

## Monitoring and Debugging

### Telemetry Integration
```elixir
defp emit_telemetry(event, measurements, metadata) do
  :telemetry.execute(
    [:snakepit, :observer_manager, event],
    measurements,
    metadata
  )
end

# In dispatch_notifications:
emit_telemetry(:notification, %{count: map_size(observers)}, %{var_id: var_id})

# In cleanup:
emit_telemetry(:cleanup, %{removed: dead_count}, %{})
```

### Debug Helpers
```elixir
def inspect_variable(var_id) do
  case :ets.lookup(@table_name, var_id) do
    [{^var_id, observers}] ->
      %{
        var_id: var_id,
        observer_count: map_size(observers),
        observers: Enum.map(observers, fn {ref, obs} ->
          %{
            ref: ref,
            pid: obs.pid,
            alive: Process.alive?(obs.pid),
            age_ms: System.monotonic_time(:millisecond) - obs.added_at
          }
        end)
      }
    [] ->
      %{var_id: var_id, observer_count: 0, observers: []}
  end
end
```

## Design Decisions

1. **ETS vs GenServer State**: ETS provides concurrent reads without bottlenecks
2. **Async Notifications**: Prevents slow observers from blocking others
3. **Process Monitoring**: Immediate cleanup of dead observers
4. **Reference-Based**: Allows multiple observers per process
5. **Metadata Propagation**: Context flows through to observers

## Next Steps
After implementing ObserverManager:
1. Update SessionStore to use ObserverManager
2. Modify gRPC handlers to register with ObserverManager
3. Add telemetry and metrics
4. Benchmark with thousands of observers
5. Create observer pooling for efficiency
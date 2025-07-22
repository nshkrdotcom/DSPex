# Prompt: Implement LocalState Variable Watching

## Objective
Implement efficient variable watching in LocalState using Erlang's process messaging system, providing sub-microsecond notification latency for pure Elixir workflows.

## Context
LocalState is the high-performance backend for pure Elixir workflows. By using process messaging for notifications, we achieve near-zero overhead for reactive updates while maintaining the simple Agent-based architecture.

## Requirements

### Core Features
1. Process-based notification system
2. Automatic cleanup on process death
3. Support for filtering and initial values
4. Efficient observer storage and lookup
5. Thread-safe concurrent access

### Performance Goals
- Notification latency: < 1 microsecond
- Support hundreds of watchers per variable
- Minimal memory overhead
- No performance impact on non-watched variables

## Implementation

### Extend LocalState Structure

```elixir
# File: lib/dspex/bridge/state/local.ex

defmodule DSPex.Bridge.State.Local do
  @behaviour DSPex.Bridge.StateProvider
  
  defstruct [:agent_pid, :observer_pid, :session_id]
  
  defmodule Watcher do
    @moduledoc false
    defstruct [:ref, :identifiers, :watcher_fn, :watcher_pid, :opts, :created_at]
  end
  
  # Update init to create observer agent
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    case Agent.start_link(fn -> initial_state(session_id) end) do
      {:ok, agent_pid} ->
        # Also start the observer process
        {:ok, observer_pid} = Agent.start_link(fn -> %{
          watchers: %{},
          variable_watchers: %{}  # var_id -> [ref1, ref2, ...]
        } end)
        
        state = %__MODULE__{
          agent_pid: agent_pid,
          observer_pid: observer_pid,
          session_id: session_id
        }
        
        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil -> {:ok, state}
          exported -> import_state(state, exported)
        end
        
      error ->
        error
    end
  end
end
```

### Implement Watching

```elixir
# Continuing in local.ex

@impl true
def supports_watching?, do: true

@impl true
def watch_variables(state, identifiers, watcher_fn, opts) do
  ref = make_ref()
  watcher_pid = Keyword.get(opts, :watcher_pid, self())
  
  # Resolve identifiers to IDs and validate they exist
  resolution_result = Agent.get(state.agent_pid, fn agent_state ->
    Enum.map(identifiers, fn id ->
      case resolve_identifier(agent_state, id) do
        nil -> {:error, id}
        var_id -> 
          var = get_in(agent_state, [:variables, var_id])
          {:ok, id, var_id, var}
      end
    end)
  end)
  
  # Check for any resolution errors
  errors = Enum.filter(resolution_result, &match?({:error, _}, &1))
  if errors != [] do
    failed_ids = Enum.map(errors, fn {:error, id} -> id end)
    return {:error, {:variables_not_found, failed_ids}}
  end
  
  # Extract successful resolutions
  var_mappings = Enum.map(resolution_result, fn {:ok, orig_id, var_id, var} ->
    {orig_id, var_id, var}
  end)
  
  # Create watcher
  watcher = %Watcher{
    ref: ref,
    identifiers: Enum.map(var_mappings, fn {orig_id, var_id, _} -> {orig_id, var_id} end),
    watcher_fn: watcher_fn,
    watcher_pid: watcher_pid,
    opts: opts,
    created_at: System.monotonic_time(:millisecond)
  }
  
  # Store watcher and update variable_watchers index
  Agent.update(state.observer_pid, fn obs_state ->
    # Add to watchers map
    obs_state = put_in(obs_state, [:watchers, ref], watcher)
    
    # Update variable_watchers index for efficient lookup
    obs_state = Enum.reduce(var_mappings, obs_state, fn {_orig_id, var_id, _var}, acc ->
      update_in(acc, [:variable_watchers, var_id], fn
        nil -> [ref]
        refs -> [ref | refs]
      end)
    end)
    
    obs_state
  end)
  
  # Monitor the watcher process
  monitor_ref = Process.monitor(watcher_pid)
  
  # Store monitor ref in observer state
  Agent.update(state.observer_pid, fn obs_state ->
    put_in(obs_state, [:monitors, monitor_ref], ref)
  end)
  
  Logger.debug("LocalState: Registered watcher #{inspect(ref)} for #{length(identifiers)} variables")
  
  # Send initial values if requested
  if Keyword.get(opts, :include_initial, false) do
    Task.start(fn ->
      send_initial_values(var_mappings, watcher)
    end)
  end
  
  {:ok, {ref, state}}
end

@impl true
def unwatch_variables(state, ref) do
  # Get watcher info before removing
  watcher_info = Agent.get(state.observer_pid, fn obs_state ->
    get_in(obs_state, [:watchers, ref])
  end)
  
  if watcher_info do
    # Remove watcher and clean up indices
    Agent.update(state.observer_pid, fn obs_state ->
      # Remove from watchers
      obs_state = update_in(obs_state, [:watchers], &Map.delete(&1, ref))
      
      # Remove from variable_watchers index
      obs_state = Enum.reduce(watcher_info.identifiers, obs_state, fn {_orig_id, var_id}, acc ->
        update_in(acc, [:variable_watchers, var_id], fn
          nil -> nil
          refs -> Enum.reject(refs, &(&1 == ref))
        end)
      end)
      
      # Remove associated monitor
      {monitor_ref, obs_state} = Enum.find_value(obs_state.monitors, {nil, obs_state}, fn {mon_ref, watch_ref} ->
        if watch_ref == ref do
          Process.demonitor(mon_ref, [:flush])
          {mon_ref, update_in(obs_state, [:monitors], &Map.delete(&1, mon_ref))}
        else
          nil
        end
      end)
      
      obs_state
    end)
    
    Logger.debug("LocalState: Unregistered watcher #{inspect(ref)}")
    {:ok, state}
  else
    {:error, :not_found}
  end
end

@impl true
def list_watchers(state) do
  watchers = Agent.get(state.observer_pid, fn obs_state ->
    Enum.map(obs_state.watchers, fn {ref, watcher} ->
      %{
        ref: ref,
        identifiers: watcher.identifiers,
        watcher_pid: watcher.watcher_pid,
        alive: Process.alive?(watcher.watcher_pid),
        created_at: watcher.created_at,
        opts: watcher.opts
      }
    end)
  end)
  
  {:ok, watchers}
end
```

### Update set_variable for Notifications

```elixir
@impl true
def set_variable(state, identifier, new_value, metadata) do
  # Perform the update and get notification info
  result = Agent.get_and_update(state.agent_pid, fn agent_state ->
    var_id = resolve_identifier(agent_state, identifier)
    
    case var_id && get_in(agent_state, [:variables, var_id]) do
      nil -> 
        {{:error, :not_found}, agent_state}
        
      variable ->
        # Validate new value
        with {:ok, type_module} <- Types.get_type_module(variable.type),
             {:ok, validated_value} <- type_module.validate(new_value),
             :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
          
          old_value = variable.value
          
          # Skip update if value unchanged
          if old_value == validated_value do
            {{:ok, :unchanged}, agent_state}
          else
            updated_variable = %{variable |
              value: validated_value,
              version: variable.version + 1,
              last_updated_at: System.monotonic_time(:millisecond),
              metadata: Map.merge(variable.metadata, metadata)
            }
            
            new_state = put_in(agent_state, [:variables, var_id], updated_variable)
            
            # Return notification info
            {{:ok, {:changed, var_id, variable.name, old_value, validated_value}}, new_state}
          end
        else
          error -> {error, agent_state}
        end
    end
  end)
  
  # Handle notifications outside the agent transaction
  case result do
    {:ok, {:changed, var_id, var_name, old_value, new_value}} ->
      notify_watchers(state, var_id, var_name, old_value, new_value, metadata)
      {:ok, state}
      
    {:ok, :unchanged} ->
      {:ok, state}
      
    error ->
      error
  end
end
```

### Notification System

```elixir
# Private notification helpers

defp notify_watchers(state, var_id, var_name, old_value, new_value, metadata) do
  # Get watchers for this variable
  watchers_to_notify = Agent.get(state.observer_pid, fn obs_state ->
    case get_in(obs_state, [:variable_watchers, var_id]) do
      nil -> []
      refs ->
        # Get watcher info for each ref
        Enum.map(refs, fn ref ->
          get_in(obs_state, [:watchers, ref])
        end)
        |> Enum.reject(&is_nil/1)
    end
  end)
  
  # Send notifications asynchronously
  Enum.each(watchers_to_notify, fn watcher ->
    if Process.alive?(watcher.watcher_pid) do
      # Find the original identifier used for this variable
      {orig_id, _} = Enum.find(watcher.identifiers, fn {_orig, watched_id} ->
        watched_id == var_id
      end)
      
      # Apply filter if present
      if should_notify?(watcher.opts, old_value, new_value) do
        # Notify in a separate process to avoid blocking
        Task.start(fn ->
          try do
            watcher.watcher_fn.(orig_id || var_name, old_value, new_value, metadata)
          rescue
            e ->
              Logger.error("Watcher function error: #{Exception.format(:error, e, __STACKTRACE__)}")
          end
        end)
      end
    end
  end)
end

defp should_notify?(opts, old_value, new_value) do
  case opts[:filter] do
    nil -> 
      true
      
    filter_fn when is_function(filter_fn, 2) ->
      try do
        filter_fn.(old_value, new_value)
      rescue
        _ -> true  # Default to notifying on filter errors
      end
      
    _ -> 
      true
  end
end

defp send_initial_values(var_mappings, watcher) do
  Enum.each(var_mappings, fn {orig_id, _var_id, variable} ->
    if should_notify?(watcher.opts, nil, variable.value) do
      try do
        watcher.watcher_fn.(orig_id, nil, variable.value, %{initial: true})
      rescue
        e ->
          Logger.error("Initial value notification error: #{Exception.format(:error, e, __STACKTRACE__)}")
      end
    end
  end)
end
```

### Handle Process Deaths

```elixir
# Add to GenServer that owns the LocalState (if using one)
# Or create a separate monitor process

def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, state) do
  # Find and remove watchers for dead process
  Agent.update(state.observer_pid, fn obs_state ->
    case get_in(obs_state, [:monitors, monitor_ref]) do
      nil -> 
        obs_state
        
      watcher_ref ->
        # Remove monitor
        obs_state = update_in(obs_state, [:monitors], &Map.delete(&1, monitor_ref))
        
        # Get watcher info
        case get_in(obs_state, [:watchers, watcher_ref]) do
          nil ->
            obs_state
            
          watcher ->
            # Remove from watchers
            obs_state = update_in(obs_state, [:watchers], &Map.delete(&1, watcher_ref))
            
            # Remove from variable_watchers index
            Enum.reduce(watcher.identifiers, obs_state, fn {_orig_id, var_id}, acc ->
              update_in(acc, [:variable_watchers, var_id], fn
                nil -> nil
                refs -> Enum.reject(refs, &(&1 == watcher_ref))
              end)
            end)
        end
    end
  end)
  
  {:noreply, state}
end
```

### Cleanup

```elixir
@impl true
def cleanup(state) do
  # Stop observer agent
  if Process.alive?(state.observer_pid) do
    Agent.stop(state.observer_pid)
  end
  
  # Stop main agent
  if Process.alive?(state.agent_pid) do
    Agent.stop(state.agent_pid)
  end
  
  :ok
end
```

## Performance Optimizations

### Efficient Lookups
The `variable_watchers` index maps variable IDs to watcher references, avoiding full scans:
```elixir
%{
  "var_123" => [ref1, ref2, ref3],
  "var_456" => [ref2, ref4]
}
```

### Async Notifications
All watcher functions are called in separate Tasks to prevent blocking:
- Main process continues immediately
- Slow watchers don't affect others
- Crashes are isolated

### Minimal Allocations
- Reuse existing data structures where possible
- Only create Tasks when actually notifying
- Use pattern matching for efficient access

## Testing

```elixir
defmodule DSPex.Bridge.State.LocalWatchingTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.State.Local
  
  test "notifies on variable changes" do
    {:ok, state} = Local.init([])
    {:ok, {_, state}} = Local.register_variable(state, :watched, :integer, 1, [])
    
    test_pid = self()
    watcher = fn id, old, new, meta ->
      send(test_pid, {:update, id, old, new, meta})
    end
    
    {:ok, {ref, state}} = Local.watch_variables(state, [:watched], watcher, [])
    
    # Update variable
    {:ok, state} = Local.set_variable(state, :watched, 2, %{source: "test"})
    
    # Should receive notification
    assert_receive {:update, :watched, 1, 2, %{source: "test"}}, 100
    
    # Cleanup
    {:ok, _state} = Local.unwatch_variables(state, ref)
  end
  
  test "cleans up on process death" do
    {:ok, state} = Local.init([])
    {:ok, {_, state}} = Local.register_variable(state, :test, :string, "value", [])
    
    # Create watcher in separate process
    {:ok, watcher_pid} = Task.start(fn ->
      receive do: (:block -> :ok)
    end)
    
    {:ok, {ref, state}} = Local.watch_variables(
      state, [:test], fn _, _, _, _ -> :ok end,
      watcher_pid: watcher_pid
    )
    
    # Verify watcher exists
    {:ok, watchers} = Local.list_watchers(state)
    assert length(watchers) == 1
    assert hd(watchers).alive
    
    # Kill watcher process
    Process.exit(watcher_pid, :kill)
    Process.sleep(50)
    
    # Watcher should be cleaned up
    {:ok, watchers} = Local.list_watchers(state)
    assert watchers == []
  end
  
  test "filters updates correctly" do
    {:ok, state} = Local.init([])
    {:ok, {_, state}} = Local.register_variable(state, :temp, :float, 20.0, [])
    
    test_pid = self()
    watcher = fn id, old, new, _ ->
      send(test_pid, {:temp_change, id, old, new})
    end
    
    # Only notify on changes > 1 degree
    filter = fn old, new -> abs(new - old) > 1.0 end
    
    {:ok, {ref, state}} = Local.watch_variables(
      state, [:temp], watcher,
      filter: filter, include_initial: false
    )
    
    # Small change - no notification
    {:ok, state} = Local.set_variable(state, :temp, 20.5, %{})
    refute_receive {:temp_change, _, _, _}, 50
    
    # Large change - notification
    {:ok, _state} = Local.set_variable(state, :temp, 22.0, %{})
    assert_receive {:temp_change, :temp, 20.5, 22.0}, 100
  end
end
```

## Next Steps
After implementing LocalState watching:
1. Implement BridgedState watching with gRPC
2. Create StreamConsumer for gRPC streams
3. Add ObserverManager for SessionStore
4. Update Variables API with watch functions
5. Benchmark notification performance
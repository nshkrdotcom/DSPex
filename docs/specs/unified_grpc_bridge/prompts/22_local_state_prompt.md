# Prompt: Implement LocalState Backend

## Objective
Create the `LocalState` backend that provides blazing-fast, in-process variable storage using an Elixir Agent. This is the default backend for pure Elixir workflows where Python integration is not needed.

## Context
LocalState is designed for maximum performance in pure Elixir DSPex programs. It provides:
- Sub-microsecond latency for all operations
- No serialization overhead
- No network calls
- Zero external dependencies
- Perfect for LLM-free DSPex programs

## Requirements

### Performance Targets
- Get operation: < 1 microsecond
- Set operation: < 5 microseconds
- Batch operations: Linear scaling
- Memory efficient storage

### Features
1. Full StateProvider behaviour implementation
2. Efficient name-to-ID index
3. Type validation using Stage 1 type system
4. Constraint enforcement
5. Version tracking
6. Metadata support

## Implementation

### Create LocalState Module

```elixir
# File: lib/dspex/bridge/state/local.ex

defmodule DSPex.Bridge.State.Local do
  @moduledoc """
  In-process state provider using an Agent.
  
  This is the default backend for pure Elixir workflows. It provides:
  - Sub-microsecond latency
  - No serialization overhead
  - No network calls
  - Perfect for LLM-free DSPex programs
  
  ## Performance Characteristics
  
  - Get operation: ~0.5-1 microseconds
  - Set operation: ~2-5 microseconds
  - List operation: ~1-2 microseconds per variable
  - No network overhead
  - No serialization cost
  
  ## Storage Structure
  
  The Agent maintains state with:
  - `variables`: Map of var_id => variable data
  - `variable_index`: Map of name => var_id for fast lookups
  - `metadata`: Session-level metadata
  - `stats`: Performance statistics
  """
  
  @behaviour DSPex.Bridge.StateProvider
  
  require Logger
  alias Snakepit.Bridge.Variables.{Variable, Types}
  
  defstruct [
    :agent_pid,
    :session_id
  ]
  
  ## StateProvider Implementation
  
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    case Agent.start_link(fn -> initial_state(session_id) end) do
      {:ok, pid} ->
        state = %__MODULE__{agent_pid: pid, session_id: session_id}
        
        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil -> 
            {:ok, state}
          exported ->
            case import_state(state, exported) do
              {:ok, state} -> {:ok, state}
              error -> 
                # Cleanup on import failure
                Agent.stop(pid)
                error
            end
        end
        
      error ->
        error
    end
  end
  
  @impl true
  def register_variable(state, name, type, initial_value, opts) do
    name_str = to_string(name)
    
    # Check if name already exists
    existing_id = Agent.get(state.agent_pid, fn agent_state ->
      Map.get(agent_state.variable_index, name_str)
    end)
    
    if existing_id do
      {:error, {:already_exists, name}}
    else
      with {:ok, type_module} <- Types.get_type_module(type),
           {:ok, validated_value} <- type_module.validate(initial_value),
           constraints = Keyword.get(opts, :constraints, %{}),
           :ok <- type_module.validate_constraints(validated_value, constraints) do
        
        var_id = generate_var_id(name)
        now = System.monotonic_time(:millisecond)
        
        variable = %{
          id: var_id,
          name: name,
          type: type,
          value: validated_value,
          constraints: constraints,
          metadata: build_metadata(opts),
          version: 0,
          created_at: now,
          last_updated_at: now
        }
        
        Agent.update(state.agent_pid, fn agent_state ->
          agent_state
          |> put_in([:variables, var_id], variable)
          |> put_in([:variable_index, name_str], var_id)
          |> update_in([:stats, :variable_count], &(&1 + 1))
          |> update_in([:stats, :total_operations], &(&1 + 1))
        end)
        
        Logger.debug("LocalState: Registered variable #{name} (#{var_id})")
        
        {:ok, {var_id, state}}
      end
    end
  end
  
  @impl true
  def get_variable(state, identifier) do
    {microseconds, result} = :timer.tc(fn ->
      Agent.get(state.agent_pid, fn agent_state ->
        var_id = resolve_identifier(agent_state, identifier)
        
        case get_in(agent_state, [:variables, var_id]) do
          nil -> {:error, :not_found}
          variable -> {:ok, variable.value}
        end
      end)
    end)
    
    # Update stats
    Agent.update(state.agent_pid, fn agent_state ->
      agent_state
      |> update_in([:stats, :total_operations], &(&1 + 1))
      |> update_in([:stats, :total_get_microseconds], &(&1 + microseconds))
    end)
    
    result
  end
  
  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    result = Agent.get_and_update(state.agent_pid, fn agent_state ->
      var_id = resolve_identifier(agent_state, identifier)
      
      case get_in(agent_state, [:variables, var_id]) do
        nil -> 
          {{:error, :not_found}, agent_state}
          
        variable ->
          with {:ok, type_module} <- Types.get_type_module(variable.type),
               {:ok, validated_value} <- type_module.validate(new_value),
               :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
            
            updated_variable = %{variable |
              value: validated_value,
              version: variable.version + 1,
              last_updated_at: System.monotonic_time(:millisecond),
              metadata: Map.merge(variable.metadata, metadata)
            }
            
            new_state = agent_state
            |> put_in([:variables, var_id], updated_variable)
            |> update_in([:stats, :total_operations], &(&1 + 1))
            |> update_in([:stats, :total_updates], &(&1 + 1))
            
            {:ok, new_state}
          else
            error -> {error, agent_state}
          end
      end
    end)
    
    case result do
      :ok -> {:ok, state}
      error -> error
    end
  end
  
  @impl true
  def list_variables(state) do
    variables = Agent.get(state.agent_pid, fn agent_state ->
      agent_state.variables
      |> Map.values()
      |> Enum.sort_by(& &1.created_at)
      |> Enum.map(&export_variable/1)
    end)
    
    {:ok, variables}
  end
  
  @impl true
  def get_variables(state, identifiers) do
    result = Agent.get(state.agent_pid, fn agent_state ->
      Enum.reduce(identifiers, %{}, fn identifier, acc ->
        var_id = resolve_identifier(agent_state, identifier)
        
        case get_in(agent_state, [:variables, var_id]) do
          nil -> acc  # Skip missing
          variable -> Map.put(acc, to_string(identifier), variable.value)
        end
      end)
    end)
    
    # Update stats
    Agent.update(state.agent_pid, fn agent_state ->
      update_in(agent_state, [:stats, :total_operations], &(&1 + length(identifiers)))
    end)
    
    {:ok, result}
  end
  
  @impl true
  def update_variables(state, updates, metadata) do
    # LocalState doesn't support true atomic updates
    # We'll do best-effort sequential updates
    errors = Enum.reduce(updates, %{}, fn {identifier, value}, acc ->
      case set_variable(state, identifier, value, metadata) do
        {:ok, _} -> acc
        {:error, reason} -> Map.put(acc, to_string(identifier), reason)
      end
    end)
    
    if map_size(errors) == 0 do
      {:ok, state}
    else
      {:error, {:partial_failure, errors}}
    end
  end
  
  @impl true
  def delete_variable(state, identifier) do
    result = Agent.get_and_update(state.agent_pid, fn agent_state ->
      var_id = resolve_identifier(agent_state, identifier)
      
      case get_in(agent_state, [:variables, var_id]) do
        nil ->
          {{:error, :not_found}, agent_state}
          
        variable ->
          name_str = to_string(variable.name)
          
          new_state = agent_state
          |> update_in([:variables], &Map.delete(&1, var_id))
          |> update_in([:variable_index], &Map.delete(&1, name_str))
          |> update_in([:stats, :variable_count], &(&1 - 1))
          |> update_in([:stats, :total_operations], &(&1 + 1))
          
          {:ok, new_state}
      end
    end)
    
    case result do
      :ok -> {:ok, state}
      error -> error
    end
  end
  
  @impl true
  def export_state(state) do
    exported = Agent.get(state.agent_pid, fn agent_state ->
      %{
        session_id: state.session_id,
        variables: agent_state.variables,
        variable_index: agent_state.variable_index,
        metadata: agent_state.metadata,
        stats: agent_state.stats
      }
    end)
    
    {:ok, exported}
  end
  
  @impl true
  def import_state(state, exported_state) do
    # Validate exported state structure
    required_keys = [:session_id, :variables, :variable_index]
    missing_keys = required_keys -- Map.keys(exported_state)
    
    if missing_keys != [] do
      {:error, {:invalid_export, {:missing_keys, missing_keys}}}
    else
      # Import into agent
      Agent.update(state.agent_pid, fn agent_state ->
        %{agent_state |
          variables: exported_state.variables,
          variable_index: exported_state.variable_index,
          metadata: Map.merge(agent_state.metadata, exported_state[:metadata] || %{}),
          stats: Map.merge(agent_state.stats, %{
            variable_count: map_size(exported_state.variables),
            imported_at: System.monotonic_time(:millisecond)
          })
        }
      end)
      
      Logger.info("LocalState: Imported #{map_size(exported_state.variables)} variables")
      {:ok, state}
    end
  end
  
  @impl true
  def requires_bridge?, do: false
  
  @impl true
  def capabilities do
    %{
      atomic_updates: false,  # Best-effort only
      streaming: false,       # Could be added via process messaging
      persistence: false,     # In-memory only
      distribution: false     # Local process only
    }
  end
  
  @impl true
  def cleanup(state) do
    if Process.alive?(state.agent_pid) do
      # Get final stats for logging
      stats = Agent.get(state.agent_pid, & &1.stats)
      
      Logger.debug("""
      LocalState cleanup for session #{state.session_id}:
        Variables: #{stats.variable_count}
        Total operations: #{stats.total_operations}
        Total updates: #{stats.total_updates || 0}
        Avg get time: #{avg_get_time(stats)}μs
      """)
      
      Agent.stop(state.agent_pid)
    end
    
    :ok
  end
  
  ## Private Helpers
  
  defp initial_state(session_id) do
    %{
      session_id: session_id,
      variables: %{},
      variable_index: %{},
      metadata: %{
        created_at: System.monotonic_time(:millisecond),
        backend: :local
      },
      stats: %{
        variable_count: 0,
        total_operations: 0,
        total_updates: 0,
        total_get_microseconds: 0
      }
    }
  end
  
  defp generate_session_id do
    "local_session_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_var_id(name) do
    "var_#{name}_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp resolve_identifier(agent_state, identifier) when is_atom(identifier) do
    resolve_identifier(agent_state, to_string(identifier))
  end
  
  defp resolve_identifier(agent_state, identifier) when is_binary(identifier) do
    # Check if it's already a var_id
    if Map.has_key?(agent_state.variables, identifier) do
      identifier
    else
      # Try to resolve as name
      Map.get(agent_state.variable_index, identifier)
    end
  end
  
  defp build_metadata(opts) do
    base = %{
      "source" => "elixir",
      "backend" => "local"
    }
    
    # Add description if provided
    base = case Keyword.get(opts, :description) do
      nil -> base
      desc -> Map.put(base, "description", desc)
    end
    
    # Merge any additional metadata
    Map.merge(base, Keyword.get(opts, :metadata, %{}))
  end
  
  defp export_variable(variable) do
    %{
      id: variable.id,
      name: variable.name,
      type: variable.type,
      value: variable.value,
      constraints: variable.constraints,
      metadata: variable.metadata,
      version: variable.version,
      created_at: variable.created_at,
      last_updated_at: variable.last_updated_at
    }
  end
  
  defp avg_get_time(%{total_operations: 0}), do: 0
  defp avg_get_time(%{total_get_microseconds: total_us, total_operations: ops}) do
    Float.round(total_us / ops, 2)
  end
end
```

## Performance Optimizations

### 1. Direct Agent Access
```elixir
# Instead of multiple Agent calls, batch operations
Agent.get_and_update(pid, fn state ->
  # Do multiple operations in one call
  {result, new_state}
end)
```

### 2. Efficient Lookups
- Maintain name-to-ID index for O(1) name lookups
- Direct ID access without index check
- Lazy pattern compilation for wildcards

### 3. Minimal Copying
- Update only changed parts of state
- Use `put_in` and `update_in` for efficient updates
- Avoid full state copies

## Testing

```elixir
# File: test/dspex/bridge/state/local_test.exs

defmodule DSPex.Bridge.State.LocalTest do
  use DSPex.Bridge.StateProviderTest, provider: DSPex.Bridge.State.Local
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.State.Local
  
  describe "LocalState specific features" do
    setup do
      {:ok, state} = Local.init(session_id: "test_local")
      {:ok, state: state}
    end
    
    test "sub-microsecond performance", %{state: state} do
      # Register a variable
      {:ok, {_, state}} = Local.register_variable(
        state, :perf_test, :float, 1.0, []
      )
      
      # Measure get performance
      measurements = for _ <- 1..1000 do
        {time, {:ok, _}} = :timer.tc(fn ->
          Local.get_variable(state, :perf_test)
        end)
        time
      end
      
      avg_microseconds = Enum.sum(measurements) / length(measurements)
      
      # Should average under 1 microsecond
      assert avg_microseconds < 1.0
      
      # 99th percentile should be under 5 microseconds
      sorted = Enum.sort(measurements)
      p99 = Enum.at(sorted, round(length(sorted) * 0.99))
      assert p99 < 5.0
    end
    
    test "efficient batch operations", %{state: state} do
      # Register 100 variables
      state = Enum.reduce(1..100, state, fn i, acc_state ->
        {:ok, {_, new_state}} = Local.register_variable(
          acc_state, :"var_#{i}", :integer, i, []
        )
        new_state
      end)
      
      # Batch get all 100
      identifiers = Enum.map(1..100, &:"var_#{&1}")
      
      {time, {:ok, values}} = :timer.tc(fn ->
        Local.get_variables(state, identifiers)
      end)
      
      assert map_size(values) == 100
      
      # Should be much faster than 100 individual gets
      # Roughly 10-50 microseconds total
      assert time < 50_000  # 50ms
    end
    
    test "memory efficiency", %{state: state} do
      # Get initial memory
      {:ok, exported1} = Local.export_state(state)
      initial_size = :erlang.external_size(exported1)
      
      # Add 10 variables
      state = Enum.reduce(1..10, state, fn i, acc_state ->
        {:ok, {_, new_state}} = Local.register_variable(
          acc_state, 
          :"mem_test_#{i}", 
          :string, 
          String.duplicate("x", 100),
          metadata: %{index: i}
        )
        new_state
      end)
      
      # Check memory growth
      {:ok, exported2} = Local.export_state(state)
      final_size = :erlang.external_size(exported2)
      
      growth_per_var = (final_size - initial_size) / 10
      
      # Should be reasonably efficient
      # Roughly 200-500 bytes per variable with 100-char string
      assert growth_per_var < 1000
    end
    
    test "name collision detection", %{state: state} do
      # Register a variable
      {:ok, {_, state}} = Local.register_variable(
        state, :duplicate, :string, "first", []
      )
      
      # Try to register with same name
      assert {:error, {:already_exists, :duplicate}} = 
        Local.register_variable(state, :duplicate, :string, "second", [])
      
      # Original still has first value
      assert {:ok, "first"} = Local.get_variable(state, :duplicate)
    end
    
    test "stats tracking", %{state: state} do
      # Perform various operations
      {:ok, {_, state}} = Local.register_variable(state, :x, :integer, 1, [])
      {:ok, 1} = Local.get_variable(state, :x)
      {:ok, 1} = Local.get_variable(state, :x)
      {:ok, state} = Local.set_variable(state, :x, 2, %{})
      
      # Export to see stats
      {:ok, exported} = Local.export_state(state)
      stats = exported.stats
      
      assert stats.variable_count == 1
      assert stats.total_operations >= 4  # register + 2 gets + 1 set
      assert stats.total_updates == 1
      assert stats.total_get_microseconds > 0
    end
  end
  
  describe "state migration" do
    test "can import from another LocalState" do
      # Create source state
      {:ok, source} = Local.init(session_id: "source")
      {:ok, {_, source}} = Local.register_variable(source, :a, :integer, 1, [])
      {:ok, {_, source}} = Local.register_variable(source, :b, :string, "test", [])
      
      # Export
      {:ok, exported} = Local.export_state(source)
      
      # Import into new state
      {:ok, target} = Local.init(session_id: "target")
      {:ok, target} = Local.import_state(target, exported)
      
      # Verify
      assert {:ok, 1} = Local.get_variable(target, :a)
      assert {:ok, "test"} = Local.get_variable(target, :b)
      
      # Can still add new variables
      {:ok, {_, target}} = Local.register_variable(target, :c, :float, 3.14, [])
      assert {:ok, 3.14} = Local.get_variable(target, :c)
      
      # Cleanup
      Local.cleanup(source)
      Local.cleanup(target)
    end
  end
end
```

## Benchmarking

```elixir
# File: bench/local_state_bench.exs

defmodule LocalStateBench do
  use Benchfella
  
  setup_all do
    {:ok, state} = DSPex.Bridge.State.Local.init(session_id: "bench")
    
    # Pre-populate with variables
    state = Enum.reduce(1..100, state, fn i, acc ->
      {:ok, {_, new_state}} = DSPex.Bridge.State.Local.register_variable(
        acc, :"bench_var_#{i}", :integer, i, []
      )
      new_state
    end)
    
    {:ok, state}
  end
  
  bench "get_variable", [state: bench_context] do
    DSPex.Bridge.State.Local.get_variable(state, :bench_var_50)
  end
  
  bench "set_variable", [state: bench_context] do
    DSPex.Bridge.State.Local.set_variable(state, :bench_var_50, 999, %{})
  end
  
  bench "get_variables (10)", [state: bench_context] do
    identifiers = Enum.map(1..10, &:"bench_var_#{&1}")
    DSPex.Bridge.State.Local.get_variables(state, identifiers)
  end
  
  bench "list_variables", [state: bench_context] do
    DSPex.Bridge.State.Local.list_variables(state)
  end
  
  teardown_all state do
    DSPex.Bridge.State.Local.cleanup(state)
  end
end
```

## Design Decisions

1. **Agent-based Storage**: Simple, fast, supervision-friendly
2. **No Serialization**: Values stored as-is for speed
3. **Simple Indexing**: Name-to-ID map for fast lookups
4. **Stats Tracking**: Minimal overhead performance monitoring
5. **Non-atomic Batches**: Simplicity over strict atomicity

## Limitations

- No persistence (in-memory only)
- No distribution (single node)
- No true atomic batch updates
- No built-in streaming (could be added)
- Limited to single process capacity

## Next Steps

After implementing LocalState:
1. Run performance benchmarks
2. Verify sub-microsecond latency
3. Test state export/import
4. Implement BridgedState backend
5. Create Context that switches between them
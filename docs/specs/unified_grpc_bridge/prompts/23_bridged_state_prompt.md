# Prompt: Implement BridgedState Backend

## Objective
Create the `BridgedState` backend that delegates to the SessionStore and gRPC bridge from Stage 1. This backend is automatically activated when Python components are detected, providing full cross-language state synchronization.

## Context
BridgedState connects the high-level DSPex API to the robust infrastructure built in Stage 1. It provides:
- Full Python interoperability
- Cross-process state sharing  
- Millisecond latency (acceptable for LLM operations)
- Seamless migration from LocalState

## Requirements

### Integration Points
1. Use SessionStore for all variable operations
2. Manage gRPC worker lifecycle
3. Support state import from LocalState
4. Maintain session consistency
5. Handle connection failures gracefully

### Performance Targets
- Get operation: < 2ms average
- Set operation: < 5ms average
- Batch operations: Significant improvement over individual calls
- Minimal overhead above SessionStore

## Implementation

### Create BridgedState Module

```elixir
# File: lib/dspex/bridge/state/bridged.ex

defmodule DSPex.Bridge.State.Bridged do
  @moduledoc """
  State provider that delegates to SessionStore and gRPC bridge.
  
  This backend is automatically activated when Python components are detected.
  It provides:
  - Full Python interoperability
  - Cross-process state sharing
  - Millisecond latency (acceptable for LLM operations)
  - Seamless migration from LocalState
  
  ## Architecture
  
  BridgedState acts as an adapter between the StateProvider behaviour
  and the SessionStore + gRPC infrastructure from Stage 1:
  
      DSPex.Context
           ↓
      BridgedState
           ↓
      SessionStore ←→ gRPC ←→ Python
  
  ## Performance Characteristics
  
  - Get operation: ~1-2ms (includes gRPC overhead)
  - Set operation: ~2-5ms (includes validation)
  - Batch operations: Amortized cost per operation
  - Network overhead: ~0.5-1ms per round trip
  """
  
  @behaviour DSPex.Bridge.StateProvider
  
  require Logger
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.Bridge.Variables.Variable
  
  defstruct [
    :session_id,
    :metadata
  ]
  
  ## StateProvider Implementation
  
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    # Ensure SessionStore is running
    ensure_session_store!()
    
    # Create or get session
    case create_or_get_session(session_id) do
      :ok ->
        state = %__MODULE__{
          session_id: session_id,
          metadata: %{
            created_at: DateTime.utc_now(),
            backend: :bridged
          }
        }
        
        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil -> 
            {:ok, state}
          exported ->
            case import_state(state, exported) do
              {:ok, state} -> 
                Logger.info("BridgedState: Imported state for session #{session_id}")
                {:ok, state}
              error -> 
                # Cleanup on import failure
                SessionStore.delete_session(session_id)
                error
            end
        end
        
      {:error, reason} ->
        {:error, {:session_creation_failed, reason}}
    end
  end
  
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
        Logger.debug("BridgedState: Registered variable #{name} (#{var_id})")
        {:ok, {var_id, state}}
        
      {:error, reason} = error ->
        Logger.warning("BridgedState: Failed to register variable #{name}: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def get_variable(state, identifier) do
    case SessionStore.get_variable(state.session_id, identifier) do
      {:ok, %Variable{value: value}} -> 
        {:ok, value}
        
      {:error, :not_found} = error ->
        error
        
      {:error, :session_not_found} ->
        # Session might have expired, try to recreate
        Logger.warning("BridgedState: Session #{state.session_id} not found, attempting recreation")
        case create_or_get_session(state.session_id) do
          :ok -> {:error, :not_found}  # Session recreated but variable is gone
          {:error, _} -> {:error, :session_expired}
        end
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Unexpected error getting variable: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    case SessionStore.update_variable(
      state.session_id,
      identifier,
      new_value,
      metadata
    ) do
      :ok -> 
        {:ok, state}
        
      {:error, :not_found} = error ->
        error
        
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Failed to update variable: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def list_variables(state) do
    case SessionStore.list_variables(state.session_id) do
      {:ok, variables} ->
        # Convert Variable structs to maps for consistency
        exported = Enum.map(variables, &export_variable/1)
        {:ok, exported}
        
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Failed to list variables: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def get_variables(state, identifiers) do
    case SessionStore.get_variables(state.session_id, identifiers) do
      {:ok, %{found: found}} ->
        # Extract just the values
        values = Map.new(found, fn {id, %Variable{value: value}} ->
          {id, value}
        end)
        {:ok, values}
        
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Failed to get variables: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def update_variables(state, updates, metadata) do
    opts = [
      atomic: false,  # TODO: Make configurable
      metadata: metadata
    ]
    
    case SessionStore.update_variables(state.session_id, updates, opts) do
      {:ok, results} ->
        # Check for any failures
        failures = Enum.filter(results, fn {_, result} -> result != :ok end)
        
        if failures == [] do
          {:ok, state}
        else
          errors = Map.new(failures, fn {id, {:error, reason}} -> {id, reason} end)
          {:error, {:partial_failure, errors}}
        end
        
      {:error, {:validation_failed, errors}} ->
        {:error, {:partial_failure, errors}}
        
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Failed to update variables: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def delete_variable(state, identifier) do
    case SessionStore.delete_variable(state.session_id, identifier) do
      :ok ->
        {:ok, state}
        
      {:error, :not_found} = error ->
        error
        
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      {:error, reason} = error ->
        Logger.error("BridgedState: Failed to delete variable: #{inspect(reason)}")
        error
    end
  end
  
  @impl true
  def export_state(state) do
    with {:ok, variables} <- SessionStore.list_variables(state.session_id) do
      # Build the same structure as LocalState exports
      variable_map = variables
      |> Enum.map(fn var -> {var.id, export_variable(var)} end)
      |> Map.new()
      
      variable_index = variables
      |> Enum.map(fn var -> {to_string(var.name), var.id} end)
      |> Map.new()
      
      exported = %{
        session_id: state.session_id,
        variables: variable_map,
        variable_index: variable_index,
        metadata: Map.merge(state.metadata, %{
          exported_at: DateTime.utc_now(),
          backend: :bridged
        })
      }
      
      {:ok, exported}
    else
      {:error, :session_not_found} ->
        {:error, :session_expired}
        
      error ->
        error
    end
  end
  
  @impl true
  def import_state(state, exported_state) do
    Logger.info("BridgedState: Importing #{map_size(exported_state.variables)} variables")
    
    # Import variables one by one
    # Future optimization: Add batch import to SessionStore
    results = Enum.map(exported_state.variables, fn {_var_id, var_data} ->
      import_variable(state, var_data)
    end)
    
    failures = Enum.filter(results, fn
      {:ok, _} -> false
      _ -> true
    end)
    
    if failures == [] do
      Logger.info("BridgedState: Successfully imported all variables")
      {:ok, state}
    else
      Logger.error("BridgedState: Failed to import #{length(failures)} variables")
      {:error, {:import_failed, failures}}
    end
  end
  
  @impl true
  def requires_bridge?, do: true
  
  @impl true
  def capabilities do
    %{
      atomic_updates: false,  # SessionStore doesn't support yet
      streaming: false,       # Will be added in Stage 3
      persistence: true,      # Survives process restarts
      distribution: true      # Works across nodes via gRPC
    }
  end
  
  @impl true
  def cleanup(state) do
    # SessionStore handles session cleanup via TTL
    # We just log for debugging
    Logger.debug("BridgedState: Cleanup called for session #{state.session_id}")
    :ok
  end
  
  ## Private Helpers
  
  defp ensure_session_store! do
    case Process.whereis(SessionStore) do
      nil ->
        # Try to start it
        case SessionStore.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} ->
            raise "Failed to start SessionStore: #{inspect(reason)}"
        end
      
      pid when is_pid(pid) ->
        :ok
    end
  end
  
  defp create_or_get_session(session_id) do
    case SessionStore.create_session(session_id) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      error -> error
    end
  end
  
  defp generate_session_id do
    "bridged_session_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp export_variable(%Variable{} = var) do
    %{
      id: var.id,
      name: var.name,
      type: var.type,
      value: var.value,
      constraints: var.constraints,
      metadata: var.metadata,
      version: var.version,
      created_at: var.created_at,
      last_updated_at: var.last_updated_at
    }
  end
  
  defp export_variable(var) when is_map(var) do
    # Already in map format
    var
  end
  
  defp import_variable(state, var_data) do
    # Add migration metadata
    metadata = var_data.metadata
    |> Map.put("migrated_from", metadata["backend"] || "unknown")
    |> Map.put("migrated_at", DateTime.utc_now() |> DateTime.to_iso8601())
    
    case SessionStore.register_variable(
      state.session_id,
      var_data.name,
      var_data.type,
      var_data.value,
      constraints: var_data.constraints,
      metadata: metadata
    ) do
      {:ok, _var_id} -> {:ok, var_data.name}
      error -> error
    end
  end
end
```

## Error Handling

### Session Management
```elixir
defmodule DSPex.Bridge.State.BridgedErrorHandler do
  @moduledoc """
  Error handling utilities for BridgedState.
  """
  
  @doc """
  Wraps SessionStore calls with proper error handling.
  """
  defmacro with_session(session_id, do: block) do
    quote do
      try do
        unquote(block)
      rescue
        e in [RuntimeError, ArgumentError] ->
          if String.contains?(Exception.message(e), "session") do
            {:error, :session_expired}
          else
            reraise e, __STACKTRACE__
          end
      end
    end
  end
  
  @doc """
  Retries an operation with exponential backoff.
  """
  def retry_with_backoff(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay = Keyword.get(opts, :base_delay, 100)
    
    do_retry(fun, 0, max_retries, base_delay)
  end
  
  defp do_retry(fun, attempt, max_attempts, base_delay) do
    case fun.() do
      {:error, :session_expired} = error when attempt < max_attempts ->
        delay = base_delay * :math.pow(2, attempt)
        Process.sleep(round(delay))
        do_retry(fun, attempt + 1, max_attempts, base_delay)
        
      result ->
        result
    end
  end
end
```

## Testing

```elixir
# File: test/dspex/bridge/state/bridged_test.exs

defmodule DSPex.Bridge.State.BridgedTest do
  use DSPex.Bridge.StateProviderTest, provider: DSPex.Bridge.State.Bridged
  use ExUnit.Case, async: false
  
  alias DSPex.Bridge.State.Bridged
  alias Snakepit.Bridge.SessionStore
  
  setup do
    # Ensure SessionStore is running
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    on_exit(fn ->
      # Cleanup any test sessions
      # SessionStore should handle this via TTL
    end)
    
    :ok
  end
  
  describe "BridgedState specific features" do
    setup do
      {:ok, state} = Bridged.init(session_id: "test_bridged_#{System.unique_integer()}")
      {:ok, state: state}
    end
    
    test "delegates to SessionStore", %{state: state} do
      # Register a variable
      {:ok, {var_id, state}} = Bridged.register_variable(
        state, :bridge_test, :string, "hello", []
      )
      
      # Verify it's in SessionStore
      assert {:ok, var} = SessionStore.get_variable(state.session_id, var_id)
      assert var.value == "hello"
      
      # Update via BridgedState
      {:ok, state} = Bridged.set_variable(state, :bridge_test, "world", %{})
      
      # Verify in SessionStore
      assert {:ok, var} = SessionStore.get_variable(state.session_id, :bridge_test)
      assert var.value == "world"
    end
    
    test "handles session expiration gracefully", %{state: state} do
      # Register a variable
      {:ok, {_, state}} = Bridged.register_variable(
        state, :temp_var, :integer, 42, []
      )
      
      # Manually delete the session to simulate expiration
      SessionStore.delete_session(state.session_id)
      
      # Operations should return session_expired error
      assert {:error, :session_expired} = Bridged.get_variable(state, :temp_var)
      assert {:error, :session_expired} = Bridged.set_variable(state, :temp_var, 100, %{})
      assert {:error, :session_expired} = Bridged.list_variables(state)
    end
    
    test "batch operations use SessionStore batching", %{state: state} do
      # Register multiple variables
      for i <- 1..10 do
        {:ok, {_, state}} = Bridged.register_variable(
          state, :"batch_#{i}", :integer, i, []
        )
      end
      
      # Batch get
      identifiers = Enum.map(1..10, &:"batch_#{&1}")
      {:ok, values} = Bridged.get_variables(state, identifiers)
      
      assert map_size(values) == 10
      assert values["batch_5"] == 5
      
      # Batch update
      updates = Map.new(1..10, fn i -> {:"batch_#{i}", i * 10} end)
      {:ok, state} = Bridged.update_variables(state, updates, %{})
      
      # Verify updates
      {:ok, values} = Bridged.get_variables(state, identifiers)
      assert values["batch_5"] == 50
    end
    
    test "preserves metadata through operations", %{state: state} do
      # Register with metadata
      {:ok, {_, state}} = Bridged.register_variable(
        state, :meta_test, :string, "test",
        metadata: %{custom: "value"},
        description: "Test variable"
      )
      
      # Get via SessionStore to see full variable
      {:ok, var} = SessionStore.get_variable(state.session_id, :meta_test)
      assert var.metadata["custom"] == "value"
      assert var.metadata["description"] == "Test variable"
      
      # Update with new metadata
      {:ok, state} = Bridged.set_variable(
        state, :meta_test, "updated",
        %{updated_by: "test"}
      )
      
      {:ok, var} = SessionStore.get_variable(state.session_id, :meta_test)
      assert var.metadata["updated_by"] == "test"
      assert var.version == 1
    end
  end
  
  describe "state migration from LocalState" do
    test "imports LocalState export correctly" do
      alias DSPex.Bridge.State.Local
      
      # Create and populate LocalState
      {:ok, local} = Local.init(session_id: "local_source")
      {:ok, {_, local}} = Local.register_variable(local, :migrated, :float, 3.14,
        constraints: %{min: 0, max: 10},
        metadata: %{source: "local"}
      )
      {:ok, {_, local}} = Local.register_variable(local, :counter, :integer, 42, [])
      
      # Export from LocalState
      {:ok, exported} = Local.export_state(local)
      
      # Import into BridgedState
      {:ok, bridged} = Bridged.init(
        session_id: "bridged_target",
        existing_state: exported
      )
      
      # Verify all variables migrated
      {:ok, 3.14} = Bridged.get_variable(bridged, :migrated)
      {:ok, 42} = Bridged.get_variable(bridged, :counter)
      
      # Check metadata preserved
      {:ok, var} = SessionStore.get_variable(bridged.session_id, :migrated)
      assert var.constraints == %{min: 0, max: 10}
      assert var.metadata["source"] == "local"
      assert var.metadata["migrated_from"] == "local"
      
      # Cleanup
      Local.cleanup(local)
    end
    
    test "handles import failures gracefully" do
      # Create invalid export
      invalid_export = %{
        # Missing required fields
        variables: %{}
      }
      
      # Should fail to init with invalid export
      assert {:error, _} = Bridged.init(
        session_id: "bad_import",
        existing_state: invalid_export
      )
      
      # Session should not exist
      assert {:error, :session_not_found} = SessionStore.get_session("bad_import")
    end
  end
  
  describe "performance characteristics" do
    setup do
      {:ok, state} = Bridged.init(session_id: "perf_test_#{System.unique_integer()}")
      
      # Pre-populate variables
      state = Enum.reduce(1..50, state, fn i, acc ->
        {:ok, {_, new_state}} = Bridged.register_variable(
          acc, :"perf_var_#{i}", :integer, i, []
        )
        new_state
      end)
      
      {:ok, state: state}
    end
    
    test "operations complete within target latency", %{state: state} do
      # Measure get operation
      {get_time, {:ok, _}} = :timer.tc(fn ->
        Bridged.get_variable(state, :perf_var_25)
      end)
      
      # Should be under 2ms
      assert get_time < 2000
      
      # Measure set operation
      {set_time, {:ok, _}} = :timer.tc(fn ->
        Bridged.set_variable(state, :perf_var_25, 999, %{})
      end)
      
      # Should be under 5ms
      assert set_time < 5000
      
      # Measure batch get
      identifiers = Enum.map(1..20, &:"perf_var_#{&1}")
      {batch_time, {:ok, values}} = :timer.tc(fn ->
        Bridged.get_variables(state, identifiers)
      end)
      
      assert map_size(values) == 20
      
      # Batch should be much more efficient than individual
      # Should be under 10ms for 20 variables
      assert batch_time < 10000
      
      # Average time per variable in batch
      avg_per_var = batch_time / 20
      assert avg_per_var < get_time  # Better than individual gets
    end
  end
end
```

## Integration with Python

The BridgedState backend enables Python code to access the same variables:

```python
# Python code can now access variables from the same session
import grpc
from unified_bridge import SessionContext

# Connect to the same session
channel = grpc.insecure_channel('localhost:50051')
ctx = SessionContext(stub, 'bridged_target')  # Same session ID

# Access migrated variables
temp = ctx.get_variable('migrated')  # Gets 3.14
count = ctx.get_variable('counter')   # Gets 42

# Updates are visible in Elixir
ctx.set_variable('counter', 43)
```

## Performance Monitoring

```elixir
defmodule DSPex.Bridge.State.BridgedMetrics do
  @moduledoc """
  Performance metrics for BridgedState operations.
  """
  
  def instrument(state, operation, fun) do
    start = System.monotonic_time()
    
    try do
      result = fun.()
      duration = System.monotonic_time() - start
      
      :telemetry.execute(
        [:dspex, :bridged_state, operation],
        %{duration: duration},
        %{session_id: state.session_id}
      )
      
      result
    rescue
      e ->
        duration = System.monotonic_time() - start
        
        :telemetry.execute(
          [:dspex, :bridged_state, operation, :error],
          %{duration: duration},
          %{session_id: state.session_id, error: e}
        )
        
        reraise e, __STACKTRACE__
    end
  end
end
```

## Design Decisions

1. **Direct SessionStore Usage**: No caching layer to ensure consistency
2. **Session Management**: Graceful handling of expired sessions
3. **Import Flexibility**: Supports migration from any StateProvider
4. **Metadata Preservation**: Migration tracking for debugging
5. **Error Propagation**: Clear error messages for troubleshooting

## Limitations

- Latency higher than LocalState (network overhead)
- Depends on SessionStore availability
- No offline capability
- Session TTL may expire data

## Next Steps

After implementing BridgedState:
1. Test state migration from LocalState
2. Verify Python interoperability
3. Benchmark performance vs LocalState
4. Implement DSPex.Context with auto-switching
5. Add monitoring and alerting
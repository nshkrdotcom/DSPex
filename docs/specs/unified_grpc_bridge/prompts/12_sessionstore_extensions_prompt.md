# Prompt: Extend SessionStore with Variable Operations

## Objective
Add comprehensive variable management operations to the SessionStore GenServer, building on the Variable module and Session extensions from the previous step.

## Context
The SessionStore is the centralized state manager. We need to add variable operations while maintaining its existing functionality and performance characteristics.

## Requirements

### Core Operations
1. Register new variables with type validation
2. Get variables by ID or name
3. Update variables with constraint checking
4. List variables with filtering
5. Batch operations for efficiency

### Additional Requirements
- Thread-safe concurrent access
- Type validation at boundaries
- Constraint enforcement
- Proper error handling
- Telemetry integration

## Implementation Steps

### 1. Update SessionStore with Variable Operations

```elixir
# File: snakepit/lib/snakepit/bridge/session_store.ex

defmodule Snakepit.Bridge.SessionStore do
  @moduledoc """
  Centralized session storage with ETS backing.
  
  Extended in Stage 1 to support variable management alongside
  existing program/tool functionality.
  """
  
  use GenServer
  require Logger
  
  alias Snakepit.Bridge.Session
  alias Snakepit.Bridge.Variables.{Variable, Types}
  
  # ... existing code ...
  
  ## Variable API
  
  @doc """
  Registers a new variable in a session.
  
  ## Options
    * `:constraints` - Type-specific constraints
    * `:metadata` - Additional metadata
    * `:description` - Human-readable description
  
  ## Examples
  
      iex> SessionStore.register_variable("session_1", :temperature, :float, 0.7,
      ...>   constraints: %{min: 0.0, max: 2.0},
      ...>   description: "LLM generation temperature"
      ...> )
      {:ok, "var_temperature_1234567"}
  """
  @spec register_variable(String.t(), atom() | String.t(), atom(), any(), keyword()) ::
    {:ok, String.t()} | {:error, term()}
  def register_variable(session_id, name, type, initial_value, opts \\ []) do
    GenServer.call(__MODULE__, {:register_variable, session_id, name, type, initial_value, opts})
  end

  @doc """
  Gets a variable by ID or name.
  
  Supports both string and atom identifiers. Names are resolved
  through the session's variable index.
  """
  @spec get_variable(String.t(), String.t() | atom()) :: 
    {:ok, Variable.t()} | {:error, term()}
  def get_variable(session_id, identifier) do
    GenServer.call(__MODULE__, {:get_variable, session_id, identifier})
  end
  
  @doc """
  Gets a variable's current value directly.
  
  Convenience function that returns just the value.
  """
  @spec get_variable_value(String.t(), String.t() | atom(), any()) :: any()
  def get_variable_value(session_id, identifier, default \\ nil) do
    case get_variable(session_id, identifier) do
      {:ok, variable} -> variable.value
      {:error, _} -> default
    end
  end

  @doc """
  Updates a variable's value with validation.
  
  The variable's type constraints are enforced and version
  is automatically incremented.
  """
  @spec update_variable(String.t(), String.t() | atom(), any(), map()) ::
    :ok | {:error, term()}
  def update_variable(session_id, identifier, new_value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_variable, session_id, identifier, new_value, metadata})
  end

  @doc """
  Lists all variables in a session.
  
  Returns variables sorted by creation time (oldest first).
  """
  @spec list_variables(String.t()) :: {:ok, [Variable.t()]} | {:error, term()}
  def list_variables(session_id) do
    GenServer.call(__MODULE__, {:list_variables, session_id})
  end
  
  @doc """
  Lists variables matching a pattern.
  
  Supports wildcards: "temp_*" matches "temp_1", "temp_2", etc.
  """
  @spec list_variables(String.t(), String.t()) :: {:ok, [Variable.t()]} | {:error, term()}
  def list_variables(session_id, pattern) do
    GenServer.call(__MODULE__, {:list_variables, session_id, pattern})
  end
  
  @doc """
  Deletes a variable from the session.
  """
  @spec delete_variable(String.t(), String.t() | atom()) :: :ok | {:error, term()}
  def delete_variable(session_id, identifier) do
    GenServer.call(__MODULE__, {:delete_variable, session_id, identifier})
  end
  
  @doc """
  Checks if a variable exists.
  """
  @spec has_variable?(String.t(), String.t() | atom()) :: boolean()
  def has_variable?(session_id, identifier) do
    case get_variable(session_id, identifier) do
      {:ok, _} -> true
      _ -> false
    end
  end
  
  ## Batch Operations
  
  @doc """
  Gets multiple variables efficiently.
  
  Returns a map of identifier => variable for found variables
  and a list of missing identifiers.
  """
  @spec get_variables(String.t(), [String.t() | atom()]) :: 
    {:ok, %{found: map(), missing: [String.t()]}} | {:error, term()}
  def get_variables(session_id, identifiers) do
    GenServer.call(__MODULE__, {:get_variables, session_id, identifiers})
  end
  
  @doc """
  Updates multiple variables.
  
  ## Options
    * `:atomic` - If true, all updates must succeed or none are applied
    * `:metadata` - Metadata to apply to all updates
  
  Returns a map of identifier => :ok | {:error, reason}
  """
  @spec update_variables(String.t(), map(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def update_variables(session_id, updates, opts \\ []) do
    GenServer.call(__MODULE__, {:update_variables, session_id, updates, opts})
  end
  
  ## GenServer Callbacks
  
  @impl true
  def handle_call({:register_variable, session_id, name, type, initial_value, opts}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id),
         {:ok, type_module} <- Types.get_type_module(type),
         {:ok, validated_value} <- type_module.validate(initial_value),
         constraints = Keyword.get(opts, :constraints, %{}),
         :ok <- type_module.validate_constraints(validated_value, constraints) do
      
      var_id = generate_variable_id(name)
      now = System.monotonic_time(:second)
      
      variable = Variable.new(%{
        id: var_id,
        name: name,
        type: type,
        value: validated_value,
        constraints: constraints,
        metadata: build_variable_metadata(opts),
        version: 0,
        created_at: now,
        last_updated_at: now
      })
      
      updated_session = Session.put_variable(session, var_id, variable)
      new_state = store_session(state, session_id, updated_session)
      
      # Emit telemetry
      :telemetry.execute(
        [:snakepit, :session_store, :variable, :registered],
        %{count: 1},
        %{session_id: session_id, type: type}
      )
      
      Logger.info("Registered variable #{name} (#{var_id}) in session #{session_id}")
      
      {:reply, {:ok, var_id}, new_state}
    else
      {:error, reason} -> 
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_variable, session_id, identifier}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id),
         {:ok, variable} <- Session.get_variable(session, identifier) do
      
      # Touch the session
      updated_session = Session.touch(session)
      new_state = store_session(state, session_id, updated_session)
      
      # Emit telemetry
      :telemetry.execute(
        [:snakepit, :session_store, :variable, :get],
        %{count: 1},
        %{session_id: session_id, cache_hit: false}
      )
      
      {:reply, {:ok, variable}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:update_variable, session_id, identifier, new_value, metadata}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id),
         {:ok, variable} <- Session.get_variable(session, identifier),
         {:ok, type_module} <- Types.get_type_module(variable.type),
         {:ok, validated_value} <- type_module.validate(new_value),
         :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
      
      # Check if optimizing (Stage 4 feature)
      if Variable.optimizing?(variable) do
        {:reply, {:error, :variable_locked_for_optimization}, state}
      else
        updated_variable = Variable.update_value(variable, validated_value, 
          metadata: metadata,
          source: Map.get(metadata, "source", "elixir")
        )
        
        updated_session = Session.put_variable(session, variable.id, updated_variable)
        new_state = store_session(state, session_id, updated_session)
        
        # Emit telemetry
        :telemetry.execute(
          [:snakepit, :session_store, :variable, :updated],
          %{count: 1, version: updated_variable.version},
          %{session_id: session_id, type: variable.type}
        )
        
        Logger.debug("Updated variable #{identifier} in session #{session_id}")
        
        # TODO: In Stage 3, notify observers here
        
        {:reply, :ok, new_state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:list_variables, session_id}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id) do
      variables = Session.list_variables(session)
      {:reply, {:ok, variables}, state}
    else
      error -> {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:list_variables, session_id, pattern}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id) do
      variables = Session.list_variables(session, pattern)
      {:reply, {:ok, variables}, state}
    else
      error -> {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:delete_variable, session_id, identifier}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id),
         {:ok, variable} <- Session.get_variable(session, identifier) do
      
      if Variable.optimizing?(variable) do
        {:reply, {:error, :variable_locked_for_optimization}, state}
      else
        updated_session = Session.delete_variable(session, identifier)
        new_state = store_session(state, session_id, updated_session)
        
        Logger.info("Deleted variable #{identifier} from session #{session_id}")
        
        {:reply, :ok, new_state}
      end
    else
      error -> {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:get_variables, session_id, identifiers}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id) do
      result = Enum.reduce(identifiers, %{found: %{}, missing: []}, fn id, acc ->
        case Session.get_variable(session, id) do
          {:ok, variable} ->
            %{acc | found: Map.put(acc.found, to_string(id), variable)}
          {:error, :not_found} ->
            %{acc | missing: [to_string(id) | acc.missing]}
        end
      end)
      
      # Reverse missing list to maintain order
      result = %{result | missing: Enum.reverse(result.missing)}
      
      # Touch session
      updated_session = Session.touch(session)
      new_state = store_session(state, session_id, updated_session)
      
      {:reply, {:ok, result}, new_state}
    else
      error -> {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:update_variables, session_id, updates, opts}, _from, state) do
    atomic = Keyword.get(opts, :atomic, false)
    metadata = Keyword.get(opts, :metadata, %{})
    
    with {:ok, session} <- get_session_internal(state, session_id) do
      if atomic do
        handle_atomic_updates(session, updates, metadata, state, session_id)
      else
        handle_non_atomic_updates(session, updates, metadata, state, session_id)
      end
    else
      error -> {:reply, error, state}
    end
  end
  
  # Private helpers
  
  defp get_session_internal(state, session_id) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, {_last_accessed, _ttl, session}}] -> {:ok, session}
      [] -> {:error, :session_not_found}
    end
  end

  defp store_session(state, session_id, session) do
    touched_session = Session.touch(session)
    ets_record = {session_id, {touched_session.last_accessed, touched_session.ttl, touched_session}}
    :ets.insert(state.table, ets_record)
    state
  end

  defp generate_variable_id(name) do
    timestamp = System.unique_integer([:positive, :monotonic])
    "var_#{name}_#{timestamp}"
  end
  
  defp build_variable_metadata(opts) do
    base_metadata = %{
      "source" => "elixir",
      "created_by" => "session_store"
    }
    
    # Add description if provided
    base_metadata = if desc = Keyword.get(opts, :description) do
      Map.put(base_metadata, "description", desc)
    else
      base_metadata
    end
    
    # Merge any additional metadata
    Map.merge(base_metadata, Keyword.get(opts, :metadata, %{}))
  end
  
  defp handle_atomic_updates(session, updates, metadata, state, session_id) do
    # First validate all updates
    validation_results = Enum.reduce(updates, %{}, fn {id, value}, acc ->
      case validate_update(session, id, value) do
        :ok -> acc
        {:error, reason} -> Map.put(acc, to_string(id), reason)
      end
    end)
    
    if map_size(validation_results) == 0 do
      # All valid, apply updates
      {updated_session, results} = Enum.reduce(updates, {session, %{}}, fn {id, value}, {sess, res} ->
        case apply_update(sess, id, value, metadata) do
          {:ok, new_sess} ->
            {new_sess, Map.put(res, to_string(id), :ok)}
          {:error, reason} ->
            # Shouldn't happen after validation
            {sess, Map.put(res, to_string(id), {:error, reason})}
        end
      end)
      
      new_state = store_session(state, session_id, updated_session)
      {:reply, {:ok, results}, new_state}
    else
      # Validation failed, return errors
      {:reply, {:error, {:validation_failed, validation_results}}, state}
    end
  end
  
  defp handle_non_atomic_updates(session, updates, metadata, state, session_id) do
    {updated_session, results} = Enum.reduce(updates, {session, %{}}, fn {id, value}, {sess, res} ->
      case apply_update(sess, id, value, metadata) do
        {:ok, new_sess} ->
          {new_sess, Map.put(res, to_string(id), :ok)}
        {:error, reason} ->
          {sess, Map.put(res, to_string(id), {:error, reason})}
      end
    end)
    
    new_state = store_session(state, session_id, updated_session)
    {:reply, {:ok, results}, new_state}
  end
  
  defp validate_update(session, identifier, value) do
    with {:ok, variable} <- Session.get_variable(session, identifier),
         {:ok, type_module} <- Types.get_type_module(variable.type),
         {:ok, validated_value} <- type_module.validate(value),
         :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
      :ok
    end
  end
  
  defp apply_update(session, identifier, value, metadata) do
    with {:ok, variable} <- Session.get_variable(session, identifier),
         {:ok, type_module} <- Types.get_type_module(variable.type),
         {:ok, validated_value} <- type_module.validate(value),
         :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
      
      updated_variable = Variable.update_value(variable, validated_value, metadata: metadata)
      updated_session = Session.put_variable(session, variable.id, updated_variable)
      
      {:ok, updated_session}
    end
  end
  
  # Export/Import for Stage 4 HA
  
  @doc """
  Exports all variables from a session.
  
  Used for session migration in Stage 4.
  """
  @spec export_variables(String.t()) :: {:ok, [map()]} | {:error, term()}
  def export_variables(session_id) do
    with {:ok, variables} <- list_variables(session_id) do
      exported = Enum.map(variables, &Variable.to_map/1)
      {:ok, exported}
    end
  end
  
  @doc """
  Imports variables into a session.
  
  Used for session restoration in Stage 4.
  """
  @spec import_variables(String.t(), [map()]) :: {:ok, integer()} | {:error, term()}
  def import_variables(session_id, variable_maps) do
    GenServer.call(__MODULE__, {:import_variables, session_id, variable_maps})
  end
  
  @impl true
  def handle_call({:import_variables, session_id, variable_maps}, _from, state) do
    with {:ok, session} <- get_session_internal(state, session_id) do
      {updated_session, count} = Enum.reduce(variable_maps, {session, 0}, fn var_map, {sess, cnt} ->
        variable = Variable.new(var_map)
        {Session.put_variable(sess, variable.id, variable), cnt + 1}
      end)
      
      new_state = store_session(state, session_id, updated_session)
      
      Logger.info("Imported #{count} variables into session #{session_id}")
      
      {:reply, {:ok, count}, new_state}
    else
      error -> {:reply, error, state}
    end
  end
end
```

### 2. Add Telemetry Events

```elixir
# File: snakepit/lib/snakepit/telemetry.ex

defmodule Snakepit.Telemetry do
  @moduledoc """
  Telemetry event definitions for Snakepit.
  """
  
  # ... existing events ...
  
  @doc """
  Variable-related telemetry events.
  """
  def variable_events do
    [
      # Variable operations
      [:snakepit, :session_store, :variable, :registered],
      [:snakepit, :session_store, :variable, :get],
      [:snakepit, :session_store, :variable, :updated],
      [:snakepit, :session_store, :variable, :deleted],
      
      # Batch operations
      [:snakepit, :session_store, :variables, :batch_get],
      [:snakepit, :session_store, :variables, :batch_update],
      
      # Validation
      [:snakepit, :session_store, :variable, :validation_failed],
      [:snakepit, :session_store, :variable, :constraint_violation]
    ]
  end
  
  @doc """
  Attaches default handlers for variable events.
  """
  def attach_variable_handlers do
    :telemetry.attach_many(
      "snakepit-variable-logger",
      variable_events(),
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event([:snakepit, :session_store, :variable, :registered], measurements, metadata, _) do
    Logger.info("Variable registered: type=#{metadata.type} session=#{metadata.session_id}")
  end
  
  defp handle_event([:snakepit, :session_store, :variable, :updated], measurements, metadata, _) do
    Logger.debug("Variable updated: type=#{metadata.type} version=#{measurements.version}")
  end
  
  # ... other handlers ...
end
```

### 3. Create Integration Tests

```elixir
# File: test/snakepit/bridge/session_store_variables_test.exs

defmodule Snakepit.Bridge.SessionStoreVariablesTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.SessionStore
  
  setup do
    # Ensure SessionStore is started
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Create test session
    session_id = "test_session_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionStore.create_session(session_id)
    
    on_exit(fn ->
      SessionStore.delete_session(session_id)
    end)
    
    {:ok, session_id: session_id}
  end
  
  describe "register_variable/5" do
    test "registers variable with type validation", %{session_id: session_id} do
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :temperature,
        :float,
        0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "LLM temperature"
      )
      
      assert String.starts_with?(var_id, "var_temperature_")
      
      {:ok, variable} = SessionStore.get_variable(session_id, var_id)
      assert variable.name == :temperature
      assert variable.type == :float
      assert variable.value == 0.7
      assert variable.constraints.min == 0.0
      assert variable.metadata["description"] == "LLM temperature"
    end
    
    test "rejects invalid type", %{session_id: session_id} do
      assert {:error, {:unknown_type, :invalid}} = 
        SessionStore.register_variable(session_id, :bad, :invalid, "value")
    end
    
    test "enforces type validation", %{session_id: session_id} do
      assert {:error, _} = 
        SessionStore.register_variable(session_id, :count, :integer, "not a number")
    end
    
    test "enforces constraints", %{session_id: session_id} do
      assert {:error, _} = 
        SessionStore.register_variable(
          session_id,
          :percentage,
          :float,
          1.5,
          constraints: %{min: 0.0, max: 1.0}
        )
    end
  end
  
  describe "get_variable/2" do
    setup %{session_id: session_id} do
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :test_var,
        :string,
        "hello"
      )
      
      {:ok, var_id: var_id}
    end
    
    test "gets by ID", %{session_id: session_id, var_id: var_id} do
      {:ok, variable} = SessionStore.get_variable(session_id, var_id)
      assert variable.value == "hello"
    end
    
    test "gets by name (string)", %{session_id: session_id} do
      {:ok, variable} = SessionStore.get_variable(session_id, "test_var")
      assert variable.value == "hello"
    end
    
    test "gets by name (atom)", %{session_id: session_id} do
      {:ok, variable} = SessionStore.get_variable(session_id, :test_var)
      assert variable.value == "hello"
    end
    
    test "returns error for non-existent", %{session_id: session_id} do
      assert {:error, :not_found} = SessionStore.get_variable(session_id, :nonexistent)
    end
  end
  
  describe "update_variable/4" do
    setup %{session_id: session_id} do
      {:ok, _} = SessionStore.register_variable(
        session_id,
        :counter,
        :integer,
        0,
        constraints: %{min: 0, max: 100}
      )
      
      :ok
    end
    
    test "updates value and increments version", %{session_id: session_id} do
      assert :ok = SessionStore.update_variable(session_id, :counter, 42)
      
      {:ok, variable} = SessionStore.get_variable(session_id, :counter)
      assert variable.value == 42
      assert variable.version == 1
      
      assert :ok = SessionStore.update_variable(session_id, :counter, 50)
      
      {:ok, variable} = SessionStore.get_variable(session_id, :counter)
      assert variable.value == 50
      assert variable.version == 2
    end
    
    test "enforces constraints on update", %{session_id: session_id} do
      assert {:error, _} = SessionStore.update_variable(session_id, :counter, 150)
      
      # Value should remain unchanged
      {:ok, variable} = SessionStore.get_variable(session_id, :counter)
      assert variable.value == 0
      assert variable.version == 0
    end
    
    test "adds metadata", %{session_id: session_id} do
      assert :ok = SessionStore.update_variable(
        session_id,
        :counter,
        1,
        %{"reason" => "increment", "user" => "test"}
      )
      
      {:ok, variable} = SessionStore.get_variable(session_id, :counter)
      assert variable.metadata["reason"] == "increment"
      assert variable.metadata["user"] == "test"
    end
  end
  
  describe "batch operations" do
    setup %{session_id: session_id} do
      # Register multiple variables
      {:ok, _} = SessionStore.register_variable(session_id, :a, :integer, 1)
      {:ok, _} = SessionStore.register_variable(session_id, :b, :integer, 2)
      {:ok, _} = SessionStore.register_variable(session_id, :c, :integer, 3)
      
      :ok
    end
    
    test "get_variables/2", %{session_id: session_id} do
      {:ok, result} = SessionStore.get_variables(
        session_id,
        [:a, :b, :nonexistent, "c"]
      )
      
      assert map_size(result.found) == 3
      assert result.found["a"].value == 1
      assert result.found["b"].value == 2
      assert result.found["c"].value == 3
      assert result.missing == ["nonexistent"]
    end
    
    test "update_variables/3 non-atomic", %{session_id: session_id} do
      updates = %{
        a: 10,
        b: 20,
        c: 30
      }
      
      {:ok, results} = SessionStore.update_variables(session_id, updates)
      
      assert results["a"] == :ok
      assert results["b"] == :ok
      assert results["c"] == :ok
      
      # Verify updates
      assert SessionStore.get_variable_value(session_id, :a) == 10
      assert SessionStore.get_variable_value(session_id, :b) == 20
      assert SessionStore.get_variable_value(session_id, :c) == 30
    end
    
    test "update_variables/3 atomic with validation failure", %{session_id: session_id} do
      # Add constraint to one variable
      {:ok, _} = SessionStore.register_variable(
        session_id,
        :constrained,
        :integer,
        5,
        constraints: %{max: 10}
      )
      
      updates = %{
        a: 100,
        constrained: 20  # Will fail
      }
      
      {:error, {:validation_failed, errors}} = 
        SessionStore.update_variables(session_id, updates, atomic: true)
      
      assert errors["constrained"] =~ "above maximum"
      
      # No updates should have been applied
      assert SessionStore.get_variable_value(session_id, :a) == 1
      assert SessionStore.get_variable_value(session_id, :constrained) == 5
    end
  end
  
  describe "list_variables/1,2" do
    setup %{session_id: session_id} do
      # Register variables with patterns
      {:ok, _} = SessionStore.register_variable(session_id, :temp_cpu, :float, 45.0)
      {:ok, _} = SessionStore.register_variable(session_id, :temp_gpu, :float, 60.0)
      {:ok, _} = SessionStore.register_variable(session_id, :memory, :integer, 1024)
      
      :ok
    end
    
    test "lists all variables", %{session_id: session_id} do
      {:ok, variables} = SessionStore.list_variables(session_id)
      assert length(variables) == 3
      
      names = Enum.map(variables, & &1.name)
      assert :temp_cpu in names
      assert :temp_gpu in names
      assert :memory in names
    end
    
    test "lists by pattern", %{session_id: session_id} do
      {:ok, temps} = SessionStore.list_variables(session_id, "temp_*")
      assert length(temps) == 2
      assert Enum.all?(temps, fn v -> 
        String.starts_with?(to_string(v.name), "temp_")
      end)
    end
  end
end
```

## Performance Considerations

1. **ETS Access Patterns**:
   - Single read for get operations
   - Single write for updates
   - Pattern compilation cached in Session module

2. **Batch Operations**:
   - Reduce GenServer calls
   - Process all in single transaction
   - Atomic updates use two-phase approach

3. **Type Validation**:
   - Type modules loaded once and cached
   - Validation happens at boundaries
   - Constraints checked efficiently

## Security Considerations

1. **Type Safety**: All values validated before storage
2. **Constraint Enforcement**: Limits enforced consistently  
3. **Session Isolation**: Variables scoped to sessions
4. **Metadata Tracking**: All changes tracked with source

## Files to Create/Modify

1. Modify: `snakepit/lib/snakepit/bridge/session_store.ex`
2. Create/Modify: `snakepit/lib/snakepit/telemetry.ex`
3. Create: `test/snakepit/bridge/session_store_variables_test.exs`

## Next Steps

After implementing SessionStore extensions:
1. Run all tests to verify functionality
2. Check telemetry events are firing correctly
3. Benchmark batch operations
4. Proceed to implement the type system (next prompt)
# Variable Registry Implementation Specification

## Overview

The Variable Registry is a GenServer-based system that manages all variables in DSPex. It serves as the central coordination point for variable state, observers, and optimization history.

## Architecture

### Core Components

```
┌─────────────────────────────────────────────┐
│           Variable Registry GenServer        │
│  ┌─────────────────────────────────────┐    │
│  │        ETS Table: Variables         │    │
│  │  (Fast lookups by ID and name)      │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │        State Management             │    │
│  │  - Observers (PID mappings)         │    │
│  │  - Active optimizers               │    │
│  │  - Dependency graph                │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │        Telemetry & Events           │    │
│  │  - Variable updates                 │    │
│  │  - Observer notifications           │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Implementation Details

### File: `lib/dspex/variables/registry.ex`

```elixir
defmodule DSPex.Variables.Registry do
  use GenServer
  require Logger
  
  @moduledoc """
  Central registry for all DSPex variables.
  
  Manages variable lifecycle, observers, and optimization coordination.
  Uses ETS for fast lookups and maintains consistency across the system.
  """
  
  @table_name :dspex_variables
  @type variable_id :: String.t()
  @type variable_type :: :float | :integer | :choice | :module | :embedding
  
  defstruct [
    :table,
    :observers,      # %{variable_id => MapSet.t(pid)}
    :optimizers,     # %{variable_id => pid}
    :dependencies,   # %{variable_id => MapSet.t(variable_id)}
    :name_index     # %{name => variable_id}
  ]
  
  # Client API
  
  @doc """
  Starts the Variable Registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a new variable with the given specifications.
  
  ## Options
    * `:constraints` - Variable constraints (type-specific)
    * `:metadata` - Additional metadata
    * `:dependencies` - List of variable IDs this depends on
    * `:description` - Human-readable description
  """
  @spec register(atom(), variable_type(), any(), keyword()) :: 
    {:ok, variable_id()} | {:error, term()}
  def register(name, type, initial_value, opts \\ []) do
    GenServer.call(__MODULE__, {:register, name, type, initial_value, opts})
  end
  
  @doc """
  Updates a variable's value with optional metadata.
  
  Notifies all observers and records in optimization history.
  """
  @spec update(variable_id(), any(), map()) :: :ok | {:error, term()}
  def update(variable_id, new_value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update, variable_id, new_value, metadata})
  end
  
  @doc """
  Retrieves a variable by ID or name.
  """
  @spec get(variable_id() | atom()) :: {:ok, Variable.t()} | {:error, :not_found}
  def get(id_or_name) do
    GenServer.call(__MODULE__, {:get, id_or_name})
  end
  
  @doc """
  Lists all variables, optionally filtered by type.
  """
  @spec list(keyword()) :: [Variable.t()]
  def list(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end
  
  @doc """
  Subscribes the calling process to variable updates.
  """
  @spec observe(variable_id(), pid() | nil) :: :ok | {:error, term()}
  def observe(variable_id, observer_pid \\ nil) do
    observer_pid = observer_pid || self()
    GenServer.cast(__MODULE__, {:observe, variable_id, observer_pid})
  end
  
  @doc """
  Unsubscribes from variable updates.
  """
  @spec unobserve(variable_id(), pid() | nil) :: :ok
  def unobserve(variable_id, observer_pid \\ nil) do
    observer_pid = observer_pid || self()
    GenServer.cast(__MODULE__, {:unobserve, variable_id, observer_pid})
  end
  
  @doc """
  Attempts to acquire optimization lock for a variable.
  """
  @spec start_optimization(variable_id(), pid() | nil) :: 
    :ok | {:error, :already_optimizing}
  def start_optimization(variable_id, optimizer_pid \\ nil) do
    optimizer_pid = optimizer_pid || self()
    GenServer.call(__MODULE__, {:start_optimization, variable_id, optimizer_pid})
  end
  
  @doc """
  Releases optimization lock for a variable.
  """
  @spec end_optimization(variable_id(), pid() | nil) :: :ok
  def end_optimization(variable_id, optimizer_pid \\ nil) do
    optimizer_pid = optimizer_pid || self()
    GenServer.cast(__MODULE__, {:end_optimization, variable_id, optimizer_pid})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    state = %__MODULE__{
      table: table,
      observers: %{},
      optimizers: %{},
      dependencies: %{},
      name_index: %{}
    }
    
    # Set up telemetry
    :telemetry.attach(
      "#{__MODULE__}.variable_updates",
      [:dspex, :variables, :update],
      &handle_telemetry/4,
      nil
    )
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, name, type, initial_value, opts}, _from, state) do
    with {:ok, type_module} <- validate_type(type),
         {:ok, validated_value} <- type_module.validate(initial_value),
         :ok <- validate_constraints(validated_value, opts[:constraints], type_module) do
      
      variable_id = generate_variable_id(name)
      
      variable = %DSPex.Variables.Variable{
        id: variable_id,
        name: name,
        type: type,
        value: validated_value,
        constraints: opts[:constraints] || %{},
        dependencies: MapSet.new(opts[:dependencies] || []),
        metadata: Map.merge(
          %{
            created_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            description: opts[:description]
          },
          opts[:metadata] || %{}
        ),
        optimization_history: []
      }
      
      # Store in ETS
      :ets.insert(state.table, {variable_id, variable})
      
      # Update indices
      new_state = %{state |
        name_index: Map.put(state.name_index, name, variable_id),
        dependencies: Map.put(state.dependencies, variable_id, variable.dependencies)
      }
      
      # Emit telemetry
      :telemetry.execute(
        [:dspex, :variables, :registered],
        %{count: 1},
        %{variable_id: variable_id, type: type, name: name}
      )
      
      Logger.info("Registered variable #{name} (#{variable_id}) with type #{type}")
      
      {:reply, {:ok, variable_id}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:update, variable_id, new_value, metadata}, _from, state) do
    case lookup_variable(state, variable_id) do
      {:ok, variable} ->
        with {:ok, type_module} <- validate_type(variable.type),
             {:ok, validated_value} <- type_module.validate(new_value),
             :ok <- validate_constraints(validated_value, variable.constraints, type_module),
             :ok <- check_dependencies(variable_id, state) do
          
          # Update variable
          updated_variable = %{variable |
            value: validated_value,
            metadata: Map.merge(variable.metadata, %{
              updated_at: DateTime.utc_now(),
              last_update_metadata: metadata
            }),
            optimization_history: [
              %{
                timestamp: DateTime.utc_now(),
                value: validated_value,
                metadata: metadata
              } | Enum.take(variable.optimization_history, 99)
            ]
          }
          
          # Store updated variable
          :ets.insert(state.table, {variable_id, updated_variable})
          
          # Notify observers
          notify_observers(variable_id, updated_variable, state)
          
          # Emit telemetry
          :telemetry.execute(
            [:dspex, :variables, :update],
            %{value: validated_value},
            %{variable_id: variable_id, type: variable.type, metadata: metadata}
          )
          
          {:reply, :ok, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
        
      {:error, :not_found} ->
        {:reply, {:error, :variable_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:get, id_or_name}, _from, state) do
    result = lookup_variable(state, id_or_name)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:list, opts}, _from, state) do
    variables = :ets.tab2list(state.table)
    |> Enum.map(fn {_id, var} -> var end)
    |> apply_filters(opts)
    
    {:reply, variables, state}
  end
  
  @impl true
  def handle_call({:start_optimization, variable_id, optimizer_pid}, _from, state) do
    case Map.get(state.optimizers, variable_id) do
      nil ->
        new_state = %{state | 
          optimizers: Map.put(state.optimizers, variable_id, optimizer_pid)
        }
        Process.monitor(optimizer_pid)
        {:reply, :ok, new_state}
        
      existing_pid ->
        {:reply, {:error, {:already_optimizing, existing_pid}}, state}
    end
  end
  
  @impl true
  def handle_cast({:observe, variable_id, observer_pid}, state) do
    case lookup_variable(state, variable_id) do
      {:ok, _variable} ->
        observers = Map.get(state.observers, variable_id, MapSet.new())
        |> MapSet.put(observer_pid)
        
        new_state = %{state | 
          observers: Map.put(state.observers, variable_id, observers)
        }
        
        Process.monitor(observer_pid)
        
        Logger.debug("Process #{inspect(observer_pid)} observing variable #{variable_id}")
        
        {:noreply, new_state}
        
      {:error, :not_found} ->
        Logger.warn("Attempted to observe non-existent variable: #{variable_id}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_cast({:unobserve, variable_id, observer_pid}, state) do
    observers = Map.get(state.observers, variable_id, MapSet.new())
    |> MapSet.delete(observer_pid)
    
    new_observers = if MapSet.size(observers) == 0 do
      Map.delete(state.observers, variable_id)
    else
      Map.put(state.observers, variable_id, observers)
    end
    
    {:noreply, %{state | observers: new_observers}}
  end
  
  @impl true
  def handle_cast({:end_optimization, variable_id, optimizer_pid}, state) do
    case Map.get(state.optimizers, variable_id) do
      ^optimizer_pid ->
        new_state = %{state | 
          optimizers: Map.delete(state.optimizers, variable_id)
        }
        {:noreply, new_state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up observers
    new_observers = Enum.reduce(state.observers, %{}, fn {var_id, observers}, acc ->
      remaining = MapSet.delete(observers, pid)
      if MapSet.size(remaining) > 0 do
        Map.put(acc, var_id, remaining)
      else
        acc
      end
    end)
    
    # Clean up optimizers
    new_optimizers = Enum.reduce(state.optimizers, %{}, fn {var_id, opt_pid}, acc ->
      if opt_pid == pid do
        Logger.info("Optimizer #{inspect(pid)} for variable #{var_id} terminated")
        acc
      else
        Map.put(acc, var_id, opt_pid)
      end
    end)
    
    {:noreply, %{state | observers: new_observers, optimizers: new_optimizers}}
  end
  
  # Private Functions
  
  defp validate_type(type) do
    type_module = Module.concat([DSPex.Variables.Types, Macro.camelize(to_string(type))])
    
    if Code.ensure_loaded?(type_module) do
      {:ok, type_module}
    else
      {:error, {:invalid_type, type}}
    end
  end
  
  defp validate_constraints(value, constraints, type_module) do
    Enum.reduce_while(constraints, :ok, fn {constraint, spec}, _acc ->
      case type_module.validate_constraint(constraint, spec, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp check_dependencies(variable_id, state) do
    deps = Map.get(state.dependencies, variable_id, MapSet.new())
    
    unmet_deps = Enum.filter(deps, fn dep_id ->
      case lookup_variable(state, dep_id) do
        {:ok, _} -> false
        {:error, _} -> true
      end
    end)
    
    if Enum.empty?(unmet_deps) do
      :ok
    else
      {:error, {:unmet_dependencies, unmet_deps}}
    end
  end
  
  defp lookup_variable(state, id) when is_binary(id) do
    case :ets.lookup(state.table, id) do
      [{^id, variable}] -> {:ok, variable}
      [] -> {:error, :not_found}
    end
  end
  
  defp lookup_variable(state, name) when is_atom(name) do
    case Map.get(state.name_index, name) do
      nil -> {:error, :not_found}
      id -> lookup_variable(state, id)
    end
  end
  
  defp generate_variable_id(name) do
    "var_#{name}_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
  
  defp notify_observers(variable_id, variable, state) do
    observers = Map.get(state.observers, variable_id, MapSet.new())
    
    Enum.each(observers, fn pid ->
      send(pid, {:variable_updated, variable_id, variable})
    end)
    
    Logger.debug("Notified #{MapSet.size(observers)} observers of update to #{variable_id}")
  end
  
  defp apply_filters(variables, opts) do
    variables
    |> filter_by_type(opts[:type])
    |> filter_by_metadata(opts[:metadata_filter])
    |> sort_variables(opts[:sort_by])
  end
  
  defp filter_by_type(variables, nil), do: variables
  defp filter_by_type(variables, type) do
    Enum.filter(variables, &(&1.type == type))
  end
  
  defp filter_by_metadata(variables, nil), do: variables
  defp filter_by_metadata(variables, filter_fn) do
    Enum.filter(variables, &filter_fn.(&1.metadata))
  end
  
  defp sort_variables(variables, nil), do: variables
  defp sort_variables(variables, :name) do
    Enum.sort_by(variables, & &1.name)
  end
  defp sort_variables(variables, :updated_at) do
    Enum.sort_by(variables, & &1.metadata.updated_at, {:desc, DateTime})
  end
  
  defp handle_telemetry(_event_name, measurements, metadata, _config) do
    Logger.debug("Variable telemetry: #{inspect(metadata)}, measurements: #{inspect(measurements)}")
  end
end
```

### File: `lib/dspex/variables/variable.ex`

```elixir
defmodule DSPex.Variables.Variable do
  @moduledoc """
  Represents a generalized variable in the DSPex system.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: atom(),
    type: atom(),
    value: any(),
    constraints: map(),
    dependencies: MapSet.t(String.t()),
    metadata: map(),
    optimization_history: list(map())
  }
  
  defstruct [
    :id,
    :name,
    :type,
    :value,
    :constraints,
    :dependencies,
    :metadata,
    :optimization_history
  ]
  
  @doc """
  Converts the variable to a Python-compatible representation.
  """
  def to_python(%__MODULE__{} = variable) do
    %{
      "id" => variable.id,
      "name" => to_string(variable.name),
      "type" => to_string(variable.type),
      "value" => variable.value,
      "constraints" => variable.constraints,
      "metadata" => variable.metadata
    }
  end
  
  @doc """
  Creates a Variable from Python representation.
  """
  def from_python(python_repr) do
    %__MODULE__{
      id: python_repr["id"],
      name: String.to_atom(python_repr["name"]),
      type: String.to_atom(python_repr["type"]),
      value: python_repr["value"],
      constraints: python_repr["constraints"] || %{},
      dependencies: MapSet.new(python_repr["dependencies"] || []),
      metadata: python_repr["metadata"] || %{},
      optimization_history: python_repr["optimization_history"] || []
    }
  end
end
```

## Testing Strategy

### Unit Tests

```elixir
# test/dspex/variables/registry_test.exs
defmodule DSPex.Variables.RegistryTest do
  use ExUnit.Case, async: false
  
  setup do
    {:ok, _pid} = DSPex.Variables.Registry.start_link()
    :ok
  end
  
  describe "register/4" do
    test "registers a float variable with constraints" do
      {:ok, var_id} = Registry.register(:temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "LLM temperature"
      )
      
      assert var_id =~ "var_temperature_"
      
      {:ok, variable} = Registry.get(var_id)
      assert variable.name == :temperature
      assert variable.type == :float
      assert variable.value == 0.7
    end
    
    test "rejects invalid type" do
      assert {:error, {:invalid_type, :unknown}} = 
        Registry.register(:test, :unknown, 42)
    end
    
    test "enforces constraints" do
      {:ok, var_id} = Registry.register(:count, :integer, 5,
        constraints: %{min: 0, max: 10}
      )
      
      assert {:error, _} = Registry.update(var_id, 15)
      assert :ok = Registry.update(var_id, 8)
    end
  end
  
  describe "observe/2" do
    test "notifies observers on update" do
      {:ok, var_id} = Registry.register(:test, :float, 1.0)
      Registry.observe(var_id)
      
      Registry.update(var_id, 2.0)
      
      assert_receive {:variable_updated, ^var_id, variable}
      assert variable.value == 2.0
    end
  end
  
  describe "optimization locking" do
    test "prevents concurrent optimization" do
      {:ok, var_id} = Registry.register(:test, :float, 1.0)
      
      assert :ok = Registry.start_optimization(var_id)
      assert {:error, {:already_optimizing, _}} = 
        Registry.start_optimization(var_id)
    end
  end
end
```

## Integration Points

### 1. With DSPex.Settings

```elixir
# Extension to settings module
defmodule DSPex.Settings do
  def put_variable(name, value) do
    case DSPex.Variables.Registry.get(name) do
      {:ok, variable} ->
        Registry.update(variable.id, value)
        put(name, value)
      {:error, :not_found} ->
        put(name, value)
    end
  end
end
```

### 2. With Telemetry

```elixir
# Telemetry events emitted:
# [:dspex, :variables, :registered]
# [:dspex, :variables, :update]
# [:dspex, :variables, :optimization_started]
# [:dspex, :variables, :optimization_completed]
```

## Performance Considerations

1. **ETS Table**: Public read access for fast concurrent lookups
2. **Observer Pattern**: Async notifications to avoid blocking
3. **History Limit**: Keep only last 100 optimization entries
4. **Process Monitoring**: Automatic cleanup of dead observers/optimizers

## Next Steps

After implementing the Variable Registry:
1. Create the type system (types.ex)
2. Add specific type implementations (float.ex, module.ex, etc.)
3. Integrate with Python bridge
4. Add comprehensive tests
5. Document usage patterns
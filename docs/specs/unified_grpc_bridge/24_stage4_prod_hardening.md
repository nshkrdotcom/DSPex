# Stage 4: Production Hardening & Optimization Hooks

## Overview

Stage 4 is the final and most critical phase, elevating the unified gRPC bridge from a powerful communication channel to a true orchestration platform. This stage introduces the advanced features required for complex, multi-optimizer workflows, production-level security, and deep system observability. We will implement dependency tracking, optimization coordination, versioning for rollback and concurrency control, and a full access control layer.

## Goals

1.  **Implement Variable Dependencies:** Create a dependency graph to manage relationships between variables, preventing cycles and enabling reactive recalculations.
2.  **Coordinate Optimizations:** Introduce locking mechanisms to prevent multiple optimizers from conflicting over the same variable.
3.  **Add History and Versioning:** Track every change to a variable, enabling optimistic locking for concurrent updates and rollback capabilities.
4.  **Enforce Security:** Implement a flexible access control system to manage read/write/optimize permissions on a per-variable basis.
5.  **Ensure Observability:** Instrument the entire system with comprehensive telemetry and performance benchmarks for production monitoring.

## Deliverables

-   `DependencyGraph` module in Elixir for tracking variable relationships.
-   Optimizer coordination logic within `SessionStore` (locking, status tracking).
-   Full versioning and history tracking for all variables.
-   `AccessControl` module and integration for secure variable access.
-   New gRPC endpoints for all advanced features.
-   Updated Python `SessionContext` exposing the new capabilities.
-   Telemetry events for all key operations and a suite of performance benchmarks.
-   Integration tests for failure modes like circular dependencies, optimization conflicts, and access denial.

## Detailed Implementation Plan

### 1. Implement Dependency Management (Elixir)

#### Create `snakepit/lib/snakepit/bridge/variables/dependency_graph.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.DependencyGraph do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{graph: %{}, reverse_graph: %{}}, name: __MODULE__)
  end

  # Public API
  def add_dependency(from_id, to_id), do: GenServer.call(__MODULE__, {:add, from_id, to_id})
  def get_dependents(var_id), do: GenServer.call(__MODULE__, {:get_dependents, var_id})

  # Server Callbacks
  def handle_call({:add, from, to}, _from, state) do
    # 1. Check for cycle before adding
    if would_create_cycle?(state.graph, from, to) do
      {:reply, {:error, :would_create_cycle}, state}
    else
      # 2. Add the edge
      new_graph = Map.update(state.graph, from, MapSet.new([to]), &MapSet.put(&1, to))
      new_reverse = Map.update(state.reverse_graph, to, MapSet.new([from]), &MapSet.put(&1, from))
      new_state = %{state | graph: new_graph, reverse_graph: new_reverse}
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_dependents, var_id}, _from, state) do
    dependents = Map.get(state.reverse_graph, var_id, MapSet.new()) |> MapSet.to_list()
    {:reply, {:ok, dependents}, state}
  end

  # DFS-based cycle detection
  defp would_create_cycle?(graph, from, to) do
    # A cycle is created if 'from' is reachable from 'to' *before* adding the new edge
    path_exists?(graph, to, from)
  end

  defp path_exists?(graph, start_node, end_node) do
    # ... implementation of a graph traversal like DFS or BFS ...
  end
end
```

#### Update `snakepit/lib/snakepit/bridge/session_store.ex`:

-   Add `:dependencies` and `:dependents` maps to the session struct.
-   Call `DependencyGraph` when registering variables with dependency information.
-   When a variable is updated, use the graph to trigger recalculation or notify dependents.

### 2. Implement Optimization Coordination (Elixir)

#### Update `snakepit/lib/snakepit/bridge/variables/variable.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.Variable do
  defstruct [
    # ... existing fields ...
    optimization_status: %{
      optimizing: false,
      optimizer_id: nil,
      optimizer_pid: nil,
      started_at: nil
    }
  ]
end
```

#### Update `snakepit/lib/snakepit/bridge/session_store.ex`:

```elixir
defmodule Snakepit.Bridge.SessionStore do
  # ...

  def start_optimization(session_id, identifier, optimizer_pid, opts \\ []) do
    GenServer.call(__MODULE__, {:start_optimization, session_id, identifier, optimizer_pid, opts})
  end

  def handle_call({:start_optimization, session_id, identifier, optimizer_pid, opts}, _from, state) do
    with {:ok, session} <- get_session(state, session_id),
         {:ok, var_id} <- resolve_variable_id(session, identifier),
         {:ok, variable} <- Map.fetch(session.variables, var_id) do
      
      if variable.optimization_status.optimizing do
        {:reply, {:error, {:already_optimizing, variable.optimization_status}}, state}
      else
        # Acquire lock
        updated_status = %{
          optimizing: true,
          optimizer_id: opts[:optimizer_id] || "opt_#{System.unique_integer()}",
          optimizer_pid: optimizer_pid,
          started_at: DateTime.utc_now()
        }
        updated_var = %{variable | optimization_status: updated_status}
        # ... update state and reply :ok ...
      end
    end
  end
end
```

### 3. Implement History & Versioning (Elixir)

#### Update `snakepit/lib/snakepit/bridge/variables/variable.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.Variable do
  defstruct [
    # ...
    version: 0,
    history: [] # List of previous states, limited in size
  ]
end
```

#### Update `snakepit/lib/snakepit/bridge/session_store.ex`:

```elixir
defmodule Snakepit.Bridge.SessionStore do
  @max_history 50

  # Update handle_call for :update_variable
  def handle_call({:update_variable, session_id, identifier, new_value, metadata}, _from, state) do
    # ... inside the with block, after getting the variable ...
    
    # Optimistic Locking Check
    expected_version = metadata["expected_version"]
    if expected_version && expected_version != variable.version do
      {:reply, {:error, {:version_mismatch, variable.version}}, state}
    else
      # Archive current state to history
      history_entry = %{
        version: variable.version,
        value: variable.value,
        updated_at: variable.last_updated_at,
        metadata: variable.metadata
      }
      
      new_history = [history_entry | variable.history] |> Enum.take(@max_history)
      
      updated_variable = %{variable |
        value: validated_value,
        version: variable.version + 1,
        history: new_history,
        # ...
      }
      
      # ... continue with update logic ...
    end
  end

  # New function for rollback
  def rollback_variable(session_id, identifier, version) do
    GenServer.call(__MODULE__, {:rollback, session_id, identifier, version})
  end

  def handle_call({:rollback, session_id, identifier, version}, _from, state) do
    # ... logic to find version in history and set it as the current value ...
  end
end
```

### 4. Implement gRPC, Python API, and Tests

With the Elixir logic in place, the final step is to expose it.

#### Update `snakepit_bridge.proto`:

Add new RPCs and messages for dependencies, optimization, history, and access control as detailed in the revised API specification.

#### Update Python `SessionContext`:

Implement the corresponding client methods for the new RPCs:
-   `add_dependency`, `get_dependencies`, `get_dependents`
-   `start_optimization`, `stop_optimization`, `get_optimization_status`
-   `get_variable_history`, `rollback_variable`
-   `set_variable_permissions`, `check_variable_access`
-   Update `set_variable` to accept an `expected_version` parameter for optimistic locking.

#### Create Integration Tests:

Write tests for the new failure and control modes.

```elixir
# test/snakepit/grpc_stage4_integration_test.exs

# Test for circular dependency
test "adding a dependency that creates a cycle fails", %{...} do
  :ok = SessionStore.add_dependency(session_id, "var_b", "var_a")
  assert {:error, :would_create_cycle} == SessionStore.add_dependency(session_id, "var_a", "var_b")
end

# Test for optimization lock
test "starting a second optimization on a locked variable fails", %{...} do
  {:ok, _} = SessionStore.start_optimization(session_id, "var_a", self())
  assert {:error, {:already_optimizing, _}} == SessionStore.start_optimization(session_id, "var_a", self())
end

# Test for optimistic locking
test "update fails with incorrect version", %{...} do
  # Python sets variable with expected_version=0
  {:ok, resp} = Client.set_variable(channel, session_id, "var_a", 10, %{"expected_version" => 0})
  assert resp.success
  
  # Python tries to set again with same version, should fail
  {:ok, resp2} = Client.set_variable(channel, session_id, "var_a", 20, %{"expected_version" => 0})
  assert resp2.success == false
  assert resp2.error_message =~ "version_mismatch"
end

# Test for rollback
test "can rollback a variable to a previous version", %{...} do
  :ok = SessionStore.update_variable(session_id, "var_a", 100) # version 1
  :ok = SessionStore.update_variable(session_id, "var_a", 200) # version 2

  :ok = SessionStore.rollback_variable(session_id, "var_a", 1)
  {:ok, var} = SessionStore.get_variable(session_id, "var_a")
  assert var.value == 100
  assert var.version == 3 # Rollback creates a new version
end
```

### 5. Add Telemetry and Benchmarking

#### Instrument Elixir Code:

Add telemetry events for new operations.

```elixir
# In SessionStore, after a successful optimization status change
:telemetry.execute(
  [:snakepit, :bridge, :variable, :optimization, :status_change],
  %{status: new_status},
  %{session_id: session_id, variable_id: var_id, optimizer_id: opt_id}
)

# In AccessControl, after a check
:telemetry.execute(
  [:snakepit, :bridge, :variable, :access_check],
  %{duration_us: duration},
  %{session_id: session_id, permission: permission, result: result}
)
```

#### Create a Benchmark Suite:

Use `Benchee` to create performance tests.

```elixir
# bench/session_store_bench.exs
Benchee.run(
  %{
    "single_write" => fn session_id -> SessionStore.update_variable(session_id, "var_a", :rand.uniform()) end,
    "batch_write_10" => fn session_id -> SessionStore.update_variables(session_id, ten_updates) end,
    "rollback" => fn session_id -> SessionStore.rollback_variable(session_id, "var_b", 5) end
  },
  # ... Benchee config ...
)
```

## Success Criteria

1.  **Dependency Graph Works:** Tests prove that circular dependencies are rejected and dependent lookups are correct.
2.  **Optimizer Coordination Works:** Tests prove that a variable can be "locked" by an optimization process, preventing concurrent modifications.
3.  **Versioning is Robust:** Tests prove that optimistic locking prevents race conditions and that variables can be successfully rolled back to previous states.
4.  **Security is Enforced:** Tests prove that sessions without the correct permissions are denied access for read, write, and optimize operations.
5.  **System is Observable:** Telemetry events are emitted for all new features, and a performance benchmark suite is in place to track regressions.
6.  **All Previous Stage Tests Still Pass:** The new features have not broken any existing functionality.

## Conclusion of Implementation

Upon completion of Stage 4, the unified gRPC bridge will be a feature-complete, secure, and observable platform. It will have moved far beyond a simple communication channel to become a sophisticated state management and orchestration system, fully realizing the architectural vision. The final steps would involve creating higher-level Elixir abstractions (e.g., a `DSPex.Variable` module) to simplify the developer experience, finalizing documentation, and preparing for production deployment.

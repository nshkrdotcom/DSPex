# Stage 4.1: Dependency Graph Implementation

## Context

You are implementing the Dependency Manager for the DSPex BridgedState backend. This component manages variable dependencies, prevents circular dependencies, and enables reactive propagation of changes through the dependency graph.

## Requirements

The Dependency Manager must:

1. **Track Dependencies**: Maintain a directed acyclic graph (DAG) of variable relationships
2. **Prevent Cycles**: Reject dependency additions that would create circular dependencies
3. **Calculate Update Order**: Provide topologically sorted update sequences
4. **Enable Propagation**: Support reactive updates when upstream variables change
5. **Integrate with BridgedState**: Work exclusively within the BridgedState backend

## Implementation Guide

### 1. Create the Dependency Manager Module

Create `lib/dspex/bridge/dependency_manager.ex`:

```elixir
defmodule DSPex.Bridge.DependencyManager do
  @moduledoc """
  Manages variable dependencies with cycle detection and propagation.
  
  This is a BridgedState-only feature that enables reactive variable updates.
  Uses Erlang's :digraph for efficient graph operations.
  """
  
  use GenServer
  require Logger
  
  alias :digraph, as: Graph
  
  defstruct [:graph, :session_id, :propagation_queue]
end
```

### 2. Core API Design

The public API should include:

```elixir
# Add a dependency between variables
def add_dependency(session_id, from_var, to_var, type \\ :data)

# Get topologically sorted update order
def get_update_order(session_id, changed_var)

# Propagate a change through the graph
def propagate_change(session_id, var_id, new_value, metadata)

# Get all dependencies of a variable
def get_dependencies(session_id, var_id)

# Get all dependents of a variable
def get_dependents(session_id, var_id)

# Remove a dependency
def remove_dependency(session_id, from_var, to_var)

# Clear all dependencies for a variable
def clear_dependencies(session_id, var_id)
```

### 3. Graph Operations

Use Erlang's `:digraph` module for efficient graph operations:

```elixir
# Create graph with cycle prevention
Graph.new([:acyclic])

# Add vertices (variables)
Graph.add_vertex(graph, var_id)

# Add edges (dependencies)
# Returns {:error, {:bad_edge, _}} if would create cycle
Graph.add_edge(graph, from_var, to_var, dependency_type)

# Get topological sort
Graph.topsort(graph)  # Returns false if cyclic

# Find paths
Graph.get_path(graph, from, to)

# Get neighbors
Graph.out_neighbours(graph, vertex)  # Dependencies
Graph.in_neighbours(graph, vertex)   # Dependents
```

### 4. Propagation Algorithm

Implement breadth-first propagation:

1. When a variable changes, get its dependents
2. Calculate topological order for all affected variables
3. Update each variable in order
4. Handle errors gracefully (log but don't fail entire propagation)
5. Emit telemetry for each propagation step

### 5. Integration with SessionStore

The DependencyManager should:

1. Be started per session via Registry lookup
2. Integrate with variable updates in SessionStore
3. Support both immediate and queued propagation
4. Handle session cleanup on termination

### 6. Telemetry Events

Emit these telemetry events:

```elixir
# Dependency added
:telemetry.execute(
  [:dspex, :bridge, :dependency, :added],
  %{},
  %{session_id: session_id, from: from_var, to: to_var, type: type}
)

# Cycle detected
:telemetry.execute(
  [:dspex, :bridge, :dependency, :cycle_detected],
  %{},
  %{session_id: session_id, from: from_var, to: to_var}
)

# Propagation started
:telemetry.execute(
  [:dspex, :bridge, :dependency, :propagation_started],
  %{affected_count: length(update_order)},
  %{session_id: session_id, source_var: var_id}
)

# Propagation completed
:telemetry.execute(
  [:dspex, :bridge, :dependency, :propagation_completed],
  %{duration_us: duration, updated_count: count},
  %{session_id: session_id, source_var: var_id}
)
```

### 7. Error Handling

Handle these error cases:

1. **Circular Dependencies**: Return `{:error, :would_create_cycle}`
2. **Missing Variables**: Log warning but continue
3. **Propagation Failures**: Isolate failures, log, continue with rest
4. **Graph Corruption**: Detect and rebuild from SessionStore state

### 8. Testing Requirements

Write tests for:

1. **Cycle Detection**: 
   - Simple cycle (A → B → A)
   - Complex cycle (A → B → C → A)
   - Diamond pattern (A → B,C; B,C → D)

2. **Update Order**:
   - Linear chain propagation
   - Fork/join patterns
   - Multiple roots

3. **Error Recovery**:
   - Propagation with missing variables
   - Concurrent modifications
   - Session cleanup

4. **Performance**:
   - Large graphs (1000+ variables)
   - Deep dependency chains
   - Wide fan-out patterns

### 9. Example Usage

```elixir
# In a DSPex context
{:ok, ctx} = DSPex.Context.start_link()
:ok = DSPex.Context.ensure_bridged(ctx)

# Define variables
{:ok, _} = Variables.defvariable(ctx, :input, :float, 10.0)
{:ok, _} = Variables.defvariable(ctx, :factor, :float, 2.0)
{:ok, _} = Variables.defvariable(ctx, :output, :float, 0.0)

# Add computation dependency
:ok = DependencyManager.add_dependency(session_id, :input, :output, :compute)
:ok = DependencyManager.add_dependency(session_id, :factor, :output, :compute)

# When input changes, output should be recalculated
Variables.set(ctx, :input, 20.0)
# This triggers propagation to :output
```

### 10. Future Considerations

Design with these future enhancements in mind:

1. **Distributed Graphs**: Store in Redis/etcd for multi-node support
2. **Lazy Evaluation**: Mark variables dirty instead of immediate compute
3. **Batch Updates**: Coalesce multiple changes before propagation
4. **Priority Propagation**: Update critical paths first
5. **Versioned Dependencies**: Track dependency changes over time

## Implementation Checklist

- [ ] Create DependencyManager GenServer with Registry
- [ ] Implement :digraph-based DAG with cycle detection
- [ ] Add dependency CRUD operations
- [ ] Implement topological sort for update order
- [ ] Create propagation queue and algorithm
- [ ] Integrate with SessionStore variable updates
- [ ] Add comprehensive telemetry
- [ ] Write unit tests for all edge cases
- [ ] Add integration tests with full Context
- [ ] Document propagation behavior
- [ ] Benchmark with large graphs
- [ ] Handle session cleanup properly

## Success Criteria

1. **Correctness**: No circular dependencies ever created
2. **Performance**: Sub-millisecond operations for graphs < 1000 nodes
3. **Reliability**: Propagation continues despite individual failures
4. **Observability**: Full telemetry coverage of all operations
5. **Integration**: Seamless operation within BridgedState
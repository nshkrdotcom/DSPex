# Elixir Variables API Specification (Revised)

## Overview

This document specifies the Elixir-side API for the Variables feature within the unified gRPC Bridge. All variable operations are integrated into the existing SessionStore and exposed via gRPC to Python clients. This revision includes batch operations, dependency management, optimization coordination, access control, and versioning capabilities.

## Core Modules

### DSPex.Bridge.SessionStore

The enhanced SessionStore now manages variables alongside tools with comprehensive lifecycle management.

#### Variable Registration

```elixir
@doc """
Registers a new variable in the session with type validation and constraints.

## Parameters
  - `session_id` - The session identifier
  - `name` - Variable name (atom or string)
  - `type` - Variable type (:float, :integer, :string, :boolean, :choice, :module, :embedding, :tensor)
  - `initial_value` - Initial value (will be validated against type)
  - `opts` - Options keyword list

## Options
  - `:constraints` - Type-specific constraints (map)
  - `:description` - Human-readable description (string)
  - `:metadata` - Additional metadata (map)
  - `:read_only` - Whether variable can be modified (boolean, default: false)
  - `:dependencies` - List of variable IDs this depends on
  - `:access_rules` - Access control rules (see AccessControl module)

## Returns
  - `{:ok, variable_id}` - Unique variable identifier
  - `{:error, reason}` - On validation failure or session not found

## Examples
    # Simple float variable
    {:ok, var_id} = SessionStore.register_variable(
      session_id, 
      :temperature, 
      :float, 
      0.7
    )
    
    # Variable with dependencies
    {:ok, var_id} = SessionStore.register_variable(
      session_id,
      :effective_temperature,
      :float,
      0.7,
      dependencies: [base_temp_id, style_modifier_id]
    )
    
    # Embedding variable
    {:ok, var_id} = SessionStore.register_variable(
      session_id,
      :context_embedding,
      :embedding,
      List.duplicate(0.0, 768),
      constraints: %{dimensions: 768, normalize: true}
    )
"""
@spec register_variable(String.t(), atom() | String.t(), variable_type(), any(), keyword()) ::
  {:ok, String.t()} | {:error, term()}
def register_variable(session_id, name, type, initial_value, opts \\ [])

@doc """
Registers multiple variables in a single atomic operation.

## Parameters
  - `session_id` - The session identifier
  - `variables` - List of variable specifications

## Variable Spec
    %{
      name: atom(),
      type: atom(),
      initial_value: any(),
      constraints: map(),
      metadata: map()
    }

## Returns
  - `{:ok, variable_ids}` - Map of name => variable_id
  - `{:error, reason}` - If any validation fails (atomic - all or nothing)

## Examples
    {:ok, var_ids} = SessionStore.register_variables(session_id, [
      %{name: :temperature, type: :float, initial_value: 0.7,
        constraints: %{min: 0.0, max: 2.0}},
      %{name: :max_tokens, type: :integer, initial_value: 256,
        constraints: %{min: 1, max: 4096}}
    ])
"""
@spec register_variables(String.t(), [map()]) ::
  {:ok, %{atom() => String.t()}} | {:error, term()}
def register_variables(session_id, variables)
```

#### Variable Updates

```elixir
@doc """
Updates a variable's value with validation and observer notification.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `new_value` - New value (will be validated)
  - `metadata` - Update metadata (map)

## Metadata Fields
  - `:source` - Update source identifier (string)
  - `:reason` - Reason for update (string)
  - `:optimizer_id` - If updated by optimizer (string)
  - `:iteration` - Optimization iteration number
  - `:metrics` - Associated performance metrics
  - Custom fields allowed

## Returns
  - `:ok` - Update successful
  - `{:error, :read_only}` - Variable is read-only
  - `{:error, {:validation_failed, reason}}` - Value validation failed
  - `{:error, :not_found}` - Variable not found
  - `{:error, :access_denied}` - Insufficient permissions

## Side Effects
  - Notifies all registered observers
  - Updates optimization history
  - Triggers dependent variable recalculation
  - Emits telemetry event

## Examples
    # Simple update
    :ok = SessionStore.update_variable(session_id, :temperature, 0.9)
    
    # Update with optimization metadata
    :ok = SessionStore.update_variable(
      session_id,
      :temperature,
      0.9,
      %{
        source: "bayesian_optimizer",
        iteration: 42,
        metrics: %{loss: 0.23, accuracy: 0.87}
      }
    )
"""
@spec update_variable(String.t(), String.t() | atom(), any(), map()) ::
  :ok | {:error, term()}
def update_variable(session_id, identifier, new_value, metadata \\ %{})

@doc """
Updates multiple variables atomically with validation.

## Parameters
  - `session_id` - The session identifier
  - `updates` - Map of identifier => new_value
  - `metadata` - Metadata applied to all updates

## Returns
  - `:ok` - All updates successful
  - `{:error, {:partial_failure, results}}` - Some updates failed
  - `{:error, reason}` - Complete failure

## Examples
    :ok = SessionStore.update_variables(
      session_id,
      %{
        temperature: 0.8,
        max_tokens: 512,
        model: "gpt-4"
      },
      %{source: "grid_search", iteration: 15}
    )
"""
@spec update_variables(String.t(), map(), map()) ::
  :ok | {:error, term()}
def update_variables(session_id, updates, metadata \\ %{})
```

#### Variable Dependencies

```elixir
@doc """
Adds a dependency between variables.

## Parameters
  - `session_id` - The session identifier
  - `from_var` - Variable that depends on another (ID or name)
  - `to_var` - Variable being depended upon (ID or name)
  - `opts` - Dependency options

## Options
  - `:type` - Dependency type (:data, :constraint, :optimization)
  - `:metadata` - Additional dependency metadata

## Returns
  - `:ok` - Dependency added
  - `{:error, :would_create_cycle}` - Would create circular dependency
  - `{:error, :not_found}` - Variable not found

## Examples
    # Temperature depends on base temperature and style
    :ok = SessionStore.add_dependency(
      session_id,
      :effective_temperature,
      :base_temperature,
      type: :data
    )
"""
@spec add_dependency(String.t(), String.t() | atom(), String.t() | atom(), keyword()) ::
  :ok | {:error, term()}
def add_dependency(session_id, from_var, to_var, opts \\ [])

@doc """
Removes a dependency between variables.
"""
@spec remove_dependency(String.t(), String.t() | atom(), String.t() | atom()) ::
  :ok | {:error, term()}
def remove_dependency(session_id, from_var, to_var)

@doc """
Gets all variables that this variable depends on.

## Returns
  - `{:ok, dependencies}` - List of variable IDs with dependency info
  - `{:error, :not_found}` - Variable not found

## Example Response
    {:ok, [
      %{variable_id: "var_base_temp_123", type: :data},
      %{variable_id: "var_style_456", type: :constraint}
    ]}
"""
@spec get_dependencies(String.t(), String.t() | atom()) ::
  {:ok, [map()]} | {:error, term()}
def get_dependencies(session_id, identifier)

@doc """
Gets all variables that depend on this variable.
"""
@spec get_dependents(String.t(), String.t() | atom()) ::
  {:ok, [map()]} | {:error, term()}
def get_dependents(session_id, identifier)
```

#### Optimization Coordination

```elixir
@doc """
Starts optimization for a variable.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `optimizer_module` - Module implementing Optimizer protocol
  - `opts` - Optimization options

## Options
  - `:max_iterations` - Maximum optimization iterations
  - `:convergence_threshold` - When to stop
  - `:feedback_interval` - How often to report progress
  - `:conflict_resolution` - How to handle multiple optimizers

## Returns
  - `{:ok, optimization_id}` - Unique optimization identifier
  - `{:error, {:already_optimizing, existing_id}}` - Already being optimized
  - `{:error, :access_denied}` - No optimize permission

## Examples
    {:ok, opt_id} = SessionStore.start_optimization(
      session_id,
      :temperature,
      DSPex.Optimizers.BayesianOptimizer,
      max_iterations: 100,
      convergence_threshold: 0.001
    )
"""
@spec start_optimization(String.t(), String.t() | atom(), module(), keyword()) ::
  {:ok, String.t()} | {:error, term()}
def start_optimization(session_id, identifier, optimizer_module, opts \\ [])

@doc """
Stops ongoing optimization for a variable.

## Returns
  - `:ok` - Optimization stopped
  - `{:error, :not_optimizing}` - No active optimization
"""
@spec stop_optimization(String.t(), String.t() | atom()) ::
  :ok | {:error, term()}
def stop_optimization(session_id, identifier)

@doc """
Gets current optimization status for a variable.

## Returns
  - `{:ok, status}` - Current optimization status
  - `{:error, :not_found}` - Variable not found

## Status Structure
    %{
      optimizing: boolean(),
      optimization_id: String.t() | nil,
      optimizer_module: module() | nil,
      iteration: integer(),
      best_value: any(),
      best_metrics: map(),
      started_at: DateTime.t() | nil,
      last_update: DateTime.t() | nil
    }
"""
@spec get_optimization_status(String.t(), String.t() | atom()) ::
  {:ok, map()} | {:error, term()}
def get_optimization_status(session_id, identifier)

@doc """
Gets optimization history for a variable.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `opts` - Query options

## Options
  - `:limit` - Maximum entries to return
  - `:since` - Only entries after this timestamp
  - `:optimizer_id` - Filter by specific optimization run

## Returns
  - `{:ok, history}` - List of optimization entries
  - `{:error, :not_found}` - Variable not found

## History Entry Structure
    %{
      timestamp: DateTime.t(),
      optimization_id: String.t(),
      iteration: integer(),
      value: any(),
      metrics: map(),
      optimizer: String.t()
    }
"""
@spec get_optimization_history(String.t(), String.t() | atom(), keyword()) ::
  {:ok, [map()]} | {:error, term()}
def get_optimization_history(session_id, identifier, opts \\ [])
```

#### Access Control

```elixir
@doc """
Sets access permissions for a variable.

## Parameters
  - `session_id` - The session identifier (must own the variable)
  - `identifier` - Variable ID or name
  - `rules` - List of access rules

## Access Rule Structure
    %{
      session_pattern: String.t() | :any,
      permissions: [:read | :write | :observe | :optimize],
      conditions: map()  # e.g., %{user_role: "admin"}
    }

## Returns
  - `:ok` - Permissions updated
  - `{:error, :not_owner}` - Only owner can set permissions
  - `{:error, :not_found}` - Variable not found

## Examples
    :ok = SessionStore.set_variable_permissions(
      session_id,
      :api_key,
      [
        %{session_pattern: :any, permissions: [:read]},
        %{session_pattern: "admin_*", permissions: [:read, :write, :optimize]}
      ]
    )
"""
@spec set_variable_permissions(String.t(), String.t() | atom(), [map()]) ::
  :ok | {:error, term()}
def set_variable_permissions(session_id, identifier, rules)

@doc """
Checks if a session has specific access to a variable.

## Parameters
  - `session_id` - The session to check
  - `identifier` - Variable ID or name
  - `permission` - Permission to check (:read, :write, :observe, :optimize)

## Returns
  - `:ok` - Access granted
  - `{:error, :access_denied}` - Access denied
  - `{:error, :not_found}` - Variable not found
"""
@spec check_variable_access(String.t(), String.t() | atom(), atom()) ::
  :ok | {:error, term()}
def check_variable_access(session_id, identifier, permission)
```

#### Variable History and Versioning

```elixir
@doc """
Gets the complete value history of a variable.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `opts` - History options

## Options
  - `:limit` - Maximum entries (default: 100)
  - `:offset` - Skip entries for pagination
  - `:include_metadata` - Include update metadata

## Returns
  - `{:ok, history}` - List of historical values
  - `{:error, :not_found}` - Variable not found

## History Entry
    %{
      version: integer(),
      value: any(),
      updated_at: DateTime.t(),
      updated_by: String.t(),
      metadata: map()
    }
"""
@spec get_variable_history(String.t(), String.t() | atom(), keyword()) ::
  {:ok, [map()]} | {:error, term()}
def get_variable_history(session_id, identifier, opts \\ [])

@doc """
Rolls back a variable to a previous version.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `version` - Version number to rollback to

## Returns
  - `:ok` - Rollback successful
  - `{:error, :version_not_found}` - Version doesn't exist
  - `{:error, :cannot_rollback}` - Variable doesn't support rollback

## Examples
    # Rollback to version 5
    :ok = SessionStore.rollback_variable(session_id, :temperature, 5)
    
    # Rollback with metadata
    :ok = SessionStore.rollback_variable(
      session_id,
      :temperature,
      5,
      metadata: %{reason: "optimization_failed"}
    )
"""
@spec rollback_variable(String.t(), String.t() | atom(), integer(), keyword()) ::
  :ok | {:error, term()}
def rollback_variable(session_id, identifier, version, opts \\ [])
```

#### Variable Export/Import

```elixir
@doc """
Exports variables and their configuration.

## Parameters
  - `session_id` - The session identifier
  - `opts` - Export options

## Options
  - `:include_history` - Include historical values
  - `:include_dependencies` - Include dependency graph
  - `:format` - Export format (:json, :binary, :csv)
  - `:filter` - Filter variables by type or pattern

## Returns
  - `{:ok, exported_data}` - Exported variable data
  - `{:error, reason}` - Export failed

## Examples
    {:ok, export} = SessionStore.export_variables(
      session_id,
      format: :json,
      include_history: true
    )
"""
@spec export_variables(String.t(), keyword()) ::
  {:ok, binary()} | {:error, term()}
def export_variables(session_id, opts \\ [])

@doc """
Imports variables from exported data.

## Parameters
  - `session_id` - The session identifier
  - `data` - Exported variable data
  - `opts` - Import options

## Options
  - `:merge_strategy` - How to handle conflicts (:replace, :keep, :merge)
  - `:validate` - Validate all constraints before import
  - `:dry_run` - Test import without applying changes

## Returns
  - `{:ok, import_result}` - Import summary
  - `{:error, reason}` - Import failed
"""
@spec import_variables(String.t(), binary(), keyword()) ::
  {:ok, map()} | {:error, term()}
def import_variables(session_id, data, opts \\ [])
```

### DSPex.Bridge.Variables.ObserverManager

Advanced observer management with filtering and priorities.

```elixir
defmodule DSPex.Bridge.Variables.ObserverManager do
  @moduledoc """
  Manages variable observers with filtering, priorities, and lifecycle.
  """
  
  @type observer_callback :: (variable_id :: String.t(), old_value :: any(), new_value :: any() -> :ok)
  
  @doc """
  Adds an observer with advanced options.
  
  ## Options
    - `:filter` - Function to filter updates (old, new -> boolean)
    - `:priority` - Observer priority (higher executes first)
    - `:debounce_ms` - Minimum ms between notifications
    - `:batch` - Batch multiple updates together
    
  ## Examples
    # Only notify on significant changes
    add_observer(variable_id, self(), &notify/3,
      filter: fn old, new -> abs(new - old) > 0.1 end,
      debounce_ms: 100
    )
  """
  @spec add_observer(String.t(), pid(), observer_callback(), keyword()) :: :ok
  def add_observer(variable_id, observer_pid, callback, opts \\ [])
  
  @doc """
  Notifies observers respecting filters and priorities.
  """
  @spec notify_observers(String.t(), any(), any(), map()) :: :ok
  def notify_observers(variable_id, old_value, new_value, metadata \\ %{})
end
```

### DSPex.Bridge.Variables.Types

Extended type system with complex types.

```elixir
defmodule DSPex.Bridge.Variables.Types.Embedding do
  @behaviour DSPex.Bridge.Variables.Types.Behaviour
  
  @doc """
  Validates embedding/vector values.
  
  ## Constraints
    - `:dimensions` - Required vector dimensions
    - `:normalize` - Whether to normalize vectors
    - `:distance_metric` - Distance calculation method
  
  ## Examples
    validate(%{dimensions: 768, normalize: true}, vector)
  """
  def validate(constraints, value)
  
  def serialize(value) do
    # Efficient binary serialization
    {:ok, :erlang.term_to_binary(value, [:compressed])}
  end
end

defmodule DSPex.Bridge.Variables.Types.Tensor do
  @behaviour DSPex.Bridge.Variables.Types.Behaviour
  
  @doc """
  Validates tensor values with Nx integration.
  
  ## Constraints
    - `:shape` - Required tensor shape
    - `:dtype` - Data type (:f32, :f64, :s64, etc.)
    - `:device` - Computation device (:cpu, :cuda, etc.)
  """
  def validate(constraints, value)
end
```

### DSPex.Bridge.Variables.Analytics

Usage analytics and performance monitoring.

```elixir
defmodule DSPex.Bridge.Variables.Analytics do
  @moduledoc """
  Track and analyze variable usage patterns.
  """
  
  @doc """
  Gets variable access statistics.
  
  ## Returns
    %{
      read_count: integer(),
      write_count: integer(),
      cache_hits: integer(),
      cache_misses: integer(),
      average_read_time_us: float(),
      average_write_time_us: float(),
      observers_count: integer(),
      last_accessed: DateTime.t()
    }
  """
  @spec get_variable_stats(String.t(), String.t() | atom()) ::
    {:ok, map()} | {:error, term()}
  def get_variable_stats(session_id, identifier)
  
  @doc """
  Analyzes usage patterns across all variables.
  
  ## Options
    - `:time_range` - Analysis period
    - `:group_by` - Grouping (:type, :source, :session)
  
  ## Returns
    %{
      most_used: [variable_stats],
      update_frequency: map(),
      access_patterns: map(),
      optimization_effectiveness: map(),
      correlations: map()
    }
  """
  @spec analyze_usage_patterns(String.t(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def analyze_usage_patterns(session_id, opts \\ [])
end
```

## gRPC Service Extensions

### Enhanced Protocol Messages

```protobuf
// Batch operations
message BatchGetVariablesRequest {
  string session_id = 1;
  repeated string variable_ids = 2;
  bool include_metadata = 3;
  bool include_dependencies = 4;
  bool include_stats = 5;
}

message BatchGetVariablesResponse {
  map<string, Variable> variables = 1;
  map<string, VariableStats> stats = 2;
}

message BatchSetVariablesRequest {
  string session_id = 1;
  map<string, google.protobuf.Any> updates = 2;
  map<string, string> metadata = 3;
  bool atomic = 4;  // All or nothing
}

message BatchSetVariablesResponse {
  bool success = 1;
  map<string, string> errors = 2;  // var_id -> error message
}

// Dependency management
message AddDependencyRequest {
  string session_id = 1;
  string from_variable_id = 2;
  string to_variable_id = 3;
  string dependency_type = 4;
  map<string, string> metadata = 5;
}

message GetDependenciesRequest {
  string session_id = 1;
  string variable_id = 2;
  bool include_transitive = 3;
}

message GetDependenciesResponse {
  repeated VariableDependency dependencies = 1;
}

// Optimization
message StartOptimizationRequest {
  string session_id = 1;
  string variable_id = 2;
  string optimizer_type = 3;
  map<string, google.protobuf.Any> optimizer_config = 4;
}

message StartOptimizationResponse {
  string optimization_id = 1;
}

message GetOptimizationStatusRequest {
  string session_id = 1;
  string variable_id = 2;
}

message OptimizationStatus {
  bool is_optimizing = 1;
  string optimization_id = 2;
  int32 iteration = 3;
  google.protobuf.Any best_value = 4;
  map<string, double> best_metrics = 5;
  google.protobuf.Timestamp started_at = 6;
  google.protobuf.Timestamp last_update = 7;
}

// Access control
message SetVariablePermissionsRequest {
  string session_id = 1;
  string variable_id = 2;
  repeated AccessRule rules = 3;
}

message AccessRule {
  string session_pattern = 1;
  repeated string permissions = 2;
  map<string, string> conditions = 3;
}

// History and versioning
message GetVariableHistoryRequest {
  string session_id = 1;
  string variable_id = 2;
  int32 limit = 3;
  int32 offset = 4;
  bool include_metadata = 5;
}

message VariableHistoryEntry {
  int32 version = 1;
  google.protobuf.Any value = 2;
  google.protobuf.Timestamp timestamp = 3;
  string updated_by = 4;
  map<string, string> metadata = 5;
}

message RollbackVariableRequest {
  string session_id = 1;
  string variable_id = 2;
  int32 target_version = 3;
  map<string, string> metadata = 4;
}
```

## Performance Benchmarks

Expected latencies for common operations:

| Operation | P50 | P95 | P99 |
|-----------|-----|-----|-----|
| Single variable read | 0.1ms | 0.5ms | 1ms |
| Single variable write | 0.5ms | 2ms | 5ms |
| Batch read (10 vars) | 0.5ms | 2ms | 5ms |
| Batch write (10 vars) | 2ms | 5ms | 10ms |
| Add dependency | 0.2ms | 1ms | 2ms |
| Start optimization | 1ms | 5ms | 10ms |
| History query (100 entries) | 5ms | 20ms | 50ms |

## Error Recovery Patterns

### Optimistic Concurrency Control

```elixir
def update_with_retry(session_id, var_id, update_fn, max_attempts \\ 3) do
  Enum.reduce_while(1..max_attempts, {:error, :not_started}, fn attempt, _acc ->
    case get_variable(session_id, var_id) do
      {:ok, current} ->
        new_value = update_fn.(current.value)
        case update_variable(session_id, var_id, new_value, %{version: current.version}) do
          :ok -> 
            {:halt, :ok}
          {:error, :version_mismatch} when attempt < max_attempts ->
            Process.sleep(50 * attempt)  # Exponential backoff
            {:cont, {:error, :version_mismatch}}
          error ->
            {:halt, error}
        end
      error ->
        {:halt, error}
    end
  end)
end
```

### Dependency Resolution

```elixir
def safe_update_with_dependencies(session_id, var_id, new_value) do
  with {:ok, deps} <- get_dependencies(session_id, var_id),
       :ok <- validate_dependencies(session_id, deps),
       :ok <- update_variable(session_id, var_id, new_value),
       :ok <- propagate_to_dependents(session_id, var_id) do
    :ok
  else
    {:error, {:dependency_invalid, dep_id}} ->
      # Attempt to fix dependency
      fix_dependency(session_id, dep_id)
      |> case do
        :ok -> safe_update_with_dependencies(session_id, var_id, new_value)
        error -> error
      end
    error ->
      error
  end
end
```

## Thread Safety Guarantees

1. **Atomic Operations**: All single variable operations are atomic
2. **Batch Atomicity**: Batch operations with `atomic: true` are all-or-nothing
3. **Read Consistency**: Reads during optimization see consistent snapshots
4. **Observer Ordering**: Observers notified in priority order, async but ordered
5. **Dependency Safety**: Circular dependencies prevented at write time

## Migration Guide

### From Basic Variables to Advanced Features

```elixir
# Before: Simple variable
{:ok, var_id} = SessionStore.register_variable(session_id, :temp, :float, 0.7)

# After: Variable with full features
{:ok, var_id} = SessionStore.register_variable(
  session_id,
  :temperature,
  :float,
  0.7,
  constraints: %{min: 0.0, max: 2.0, step: 0.1},
  dependencies: [base_temp_id],
  access_rules: [
    %{session_pattern: :any, permissions: [:read]},
    %{session_pattern: "optimizer_*", permissions: [:read, :write, :optimize]}
  ],
  metadata: %{
    description: "LLM generation temperature",
    affects: ["creativity", "consistency"],
    optimization_target: true
  }
)

# Add optimization
{:ok, opt_id} = SessionStore.start_optimization(
  session_id,
  var_id,
  DSPex.Optimizers.BayesianOptimizer,
  max_iterations: 100,
  objective: :maximize_quality
)

# Monitor optimization
{:ok, status} = SessionStore.get_optimization_status(session_id, var_id)
IO.puts("Current best: #{status.best_value} (metric: #{status.best_metrics.quality})")
```

## Security Considerations

1. **Session Isolation**: Complete isolation between sessions
2. **Permission Enforcement**: All operations check permissions
3. **Audit Logging**: All changes logged with actor and timestamp
4. **Rate Limiting**: Per-session rate limits prevent abuse
5. **Value Sanitization**: Type validation prevents injection
6. **Dependency Validation**: Prevents malicious dependency graphs

## Telemetry Events

Extended telemetry for monitoring:

```elixir
# Batch operations
:telemetry.execute(
  [:dspex, :bridge, :variables, :batch_update],
  %{
    count: length(updates),
    duration_us: duration,
    success_count: success_count
  },
  %{session_id: session_id}
)

# Optimization events
:telemetry.execute(
  [:dspex, :bridge, :variables, :optimization, :iteration],
  %{
    iteration: iteration,
    current_value: value,
    metric_value: metric
  },
  %{
    session_id: session_id,
    variable_id: variable_id,
    optimization_id: optimization_id
  }
)

# Access control events
:telemetry.execute(
  [:dspex, :bridge, :variables, :access_check],
  %{duration_us: duration},
  %{
    session_id: session_id,
    variable_id: variable_id,
    permission: permission,
    result: result
  }
)
```
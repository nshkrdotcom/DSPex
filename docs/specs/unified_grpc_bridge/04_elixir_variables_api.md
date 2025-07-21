# Elixir Variables API Specification

## Overview

This document specifies the Elixir-side API for the Variables feature within the unified gRPC Bridge. All variable operations are integrated into the existing SessionStore and exposed via gRPC to Python clients.

## Core Modules

### DSPex.Bridge.SessionStore

The enhanced SessionStore now manages variables alongside tools.

#### Variable Registration

```elixir
@doc """
Registers a new variable in the session with type validation and constraints.

## Parameters
  - `session_id` - The session identifier
  - `name` - Variable name (atom or string)
  - `type` - Variable type (:float, :integer, :string, :boolean, :choice, :module)
  - `initial_value` - Initial value (will be validated against type)
  - `opts` - Options keyword list

## Options
  - `:constraints` - Type-specific constraints (map)
  - `:description` - Human-readable description (string)
  - `:metadata` - Additional metadata (map)
  - `:read_only` - Whether variable can be modified (boolean, default: false)

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
    
    # Constrained integer variable
    {:ok, var_id} = SessionStore.register_variable(
      session_id,
      :max_tokens,
      :integer,
      256,
      constraints: %{min: 1, max: 4096, step: 1}
    )
    
    # Choice variable
    {:ok, var_id} = SessionStore.register_variable(
      session_id,
      :model,
      :choice,
      "gpt-4",
      constraints: %{choices: ["gpt-4", "claude-3", "gemini-pro"]}
    )
    
    # Module-type variable
    {:ok, var_id} = SessionStore.register_variable(
      session_id,
      :reasoning_module,
      :module,
      "Predict",
      constraints: %{choices: ["Predict", "ChainOfThought", "ReAct"]}
    )
"""
@spec register_variable(String.t(), atom() | String.t(), variable_type(), any(), keyword()) ::
  {:ok, String.t()} | {:error, term()}
def register_variable(session_id, name, type, initial_value, opts \\ [])
```

#### Variable Retrieval

```elixir
@doc """
Retrieves a variable by ID or name from the session.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID (string) or name (atom/string)

## Returns
  - `{:ok, Variable.t()}` - The variable struct
  - `{:error, :not_found}` - Variable not found
  - `{:error, :session_not_found}` - Session not found

## Examples
    # Get by ID
    {:ok, variable} = SessionStore.get_variable(session_id, "var_temperature_12345")
    
    # Get by name
    {:ok, variable} = SessionStore.get_variable(session_id, :temperature)
"""
@spec get_variable(String.t(), String.t() | atom()) ::
  {:ok, Variable.t()} | {:error, :not_found | :session_not_found}
def get_variable(session_id, identifier)

@doc """
Lists all variables in a session with optional filtering.

## Parameters
  - `session_id` - The session identifier
  - `opts` - Filter options

## Options
  - `:type` - Filter by variable type
  - `:source` - Filter by source (:elixir or :python)
  - `:include_metadata` - Include full metadata (boolean, default: false)

## Returns
  - `{:ok, [Variable.t()]}` - List of variables
  - `{:error, :session_not_found}` - Session not found

## Examples
    # Get all variables
    {:ok, variables} = SessionStore.list_variables(session_id)
    
    # Get only float variables
    {:ok, float_vars} = SessionStore.list_variables(session_id, type: :float)
"""
@spec list_variables(String.t(), keyword()) ::
  {:ok, [Variable.t()]} | {:error, :session_not_found}
def list_variables(session_id, opts \\ [])
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
  - Custom fields allowed

## Returns
  - `:ok` - Update successful
  - `{:error, :read_only}` - Variable is read-only
  - `{:error, {:validation_failed, reason}}` - Value validation failed
  - `{:error, :not_found}` - Variable not found

## Side Effects
  - Notifies all registered observers
  - Updates optimization history
  - Emits telemetry event

## Examples
    # Simple update
    :ok = SessionStore.update_variable(session_id, :temperature, 0.9)
    
    # Update with metadata
    :ok = SessionStore.update_variable(
      session_id,
      :temperature,
      0.9,
      %{source: "optimizer", iteration: 42}
    )
"""
@spec update_variable(String.t(), String.t() | atom(), any(), map()) ::
  :ok | {:error, term()}
def update_variable(session_id, identifier, new_value, metadata \\ %{})
```

#### Variable Observation

```elixir
@doc """
Registers an observer for variable changes.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `observer_pid` - PID to receive notifications (defaults to caller)

## Observer Messages
    {:variable_updated, variable_id, variable, metadata}

## Returns
  - `:ok` - Observer registered
  - `{:error, :not_found}` - Variable not found

## Examples
    # Observe variable
    :ok = SessionStore.observe_variable(session_id, :temperature)
    
    # Receive updates
    receive do
      {:variable_updated, var_id, variable, metadata} ->
        IO.puts("Variable #{var_id} updated to #{variable.value}")
    end
"""
@spec observe_variable(String.t(), String.t() | atom(), pid() | nil) ::
  :ok | {:error, term()}
def observe_variable(session_id, identifier, observer_pid \\ nil)

@doc """
Removes an observer for variable changes.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name
  - `observer_pid` - PID to remove (defaults to caller)

## Returns
  - `:ok` - Observer removed or was not observing

## Examples
    :ok = SessionStore.unobserve_variable(session_id, :temperature)
"""
@spec unobserve_variable(String.t(), String.t() | atom(), pid() | nil) :: :ok
def unobserve_variable(session_id, identifier, observer_pid \\ nil)
```

#### Variable Deletion

```elixir
@doc """
Deletes a variable from the session.

## Parameters
  - `session_id` - The session identifier
  - `identifier` - Variable ID or name

## Returns
  - `:ok` - Variable deleted
  - `{:error, :not_found}` - Variable not found
  - `{:error, :has_dependents}` - Other variables depend on this one

## Side Effects
  - Notifies observers of deletion
  - Removes from optimization history
  - Cleans up dependencies

## Examples
    :ok = SessionStore.delete_variable(session_id, :old_temperature)
"""
@spec delete_variable(String.t(), String.t() | atom()) ::
  :ok | {:error, term()}
def delete_variable(session_id, identifier)
```

### DSPex.Bridge.Variables.Variable

The Variable struct and its operations.

```elixir
defmodule DSPex.Bridge.Variables.Variable do
  @moduledoc """
  Represents a variable in the DSPex system.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: atom(),
    type: atom(),
    value: any(),
    constraints: map(),
    metadata: map(),
    source: :elixir | :python,
    read_only: boolean(),
    optimization_history: [optimization_entry()],
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  @type optimization_entry :: %{
    timestamp: DateTime.t(),
    value: any(),
    optimizer_id: String.t() | nil,
    metrics: map()
  }
  
  defstruct [
    :id,
    :name,
    :type,
    :value,
    :constraints,
    :metadata,
    :source,
    :read_only,
    :optimization_history,
    :created_at,
    :updated_at
  ]
  
  @doc """
  Validates a value against the variable's type and constraints.
  
  ## Returns
    - `{:ok, validated_value}` - Value is valid
    - `{:error, reason}` - Validation failed
  """
  @spec validate_value(t(), any()) :: {:ok, any()} | {:error, term()}
  def validate_value(%__MODULE__{} = variable, value)
  
  @doc """
  Converts variable to protobuf representation for gRPC.
  """
  @spec to_proto(t()) :: VariableProto.t()
  def to_proto(%__MODULE__{} = variable)
  
  @doc """
  Creates variable from protobuf representation.
  """
  @spec from_proto(VariableProto.t()) :: {:ok, t()} | {:error, term()}
  def from_proto(proto)
end
```

### DSPex.Bridge.Variables.Types

Type modules for variable validation.

```elixir
defmodule DSPex.Bridge.Variables.Types do
  @moduledoc """
  Variable type definitions and behaviors.
  """
  
  @doc """
  Behavior that all variable types must implement.
  """
  defmodule Behaviour do
    @callback validate(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback cast(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback validate_constraint(constraint :: atom(), spec :: any(), value :: any()) :: 
      :ok | {:error, String.t()}
    @callback serialize(value :: any()) :: any()
    @callback deserialize(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback default_constraints() :: keyword()
  end
end
```

#### Built-in Types

```elixir
defmodule DSPex.Bridge.Variables.Types.Float do
  @behaviour DSPex.Bridge.Variables.Types.Behaviour
  
  @doc """
  Validates float values.
  
  ## Constraints
    - `:min` - Minimum value (inclusive)
    - `:max` - Maximum value (inclusive)
    - `:step` - Step size for discrete values
  
  ## Examples
    validate(1.5) # => {:ok, 1.5}
    validate(2)   # => {:ok, 2.0}  # Integers converted
    validate("x") # => {:error, "must be a number"}
  """
  def validate(value)
  
  @doc """
  Validates specific constraints for float type.
  """
  def validate_constraint(:min, min_value, value) when value >= min_value, do: :ok
  def validate_constraint(:min, min_value, value), 
    do: {:error, "value #{value} below minimum #{min_value}"}
end

defmodule DSPex.Bridge.Variables.Types.Module do
  @behaviour DSPex.Bridge.Variables.Types.Behaviour
  
  @doc """
  Validates module-type variables.
  
  ## Constraints
    - `:choices` - List of allowed module names
  
  ## Special Handling
    Module variables are serialized as special references that Python
    can use to dynamically select DSPy modules.
  """
  def validate(value)
  
  def serialize(module_name) do
    %{
      "__dspex_type__" => "module_reference",
      "module_name" => to_string(module_name)
    }
  end
end
```

### DSPex.Bridge.Variables.Registry

Low-level registry operations (used by SessionStore).

```elixir
defmodule DSPex.Bridge.Variables.Registry do
  @moduledoc """
  Low-level variable registry operations.
  This module is used internally by SessionStore.
  """
  
  @doc """
  Generates a unique variable ID based on name and timestamp.
  """
  @spec generate_id(atom() | String.t()) :: String.t()
  def generate_id(name) do
    timestamp = System.unique_integer([:positive, :monotonic])
    "var_#{name}_#{timestamp}"
  end
  
  @doc """
  Validates variable type module exists and is loaded.
  """
  @spec validate_type(atom()) :: {:ok, module()} | {:error, :invalid_type}
  def validate_type(type)
  
  @doc """
  Resolves variable identifier to ID.
  Handles both direct IDs and name lookups.
  """
  @spec resolve_identifier(map(), String.t() | atom()) :: 
    {:ok, String.t()} | {:error, :not_found}
  def resolve_identifier(variables, identifier)
end
```

## gRPC Service Extensions

### Variable-Specific RPCs

```elixir
defmodule DSPex.Bridge.GRPCServer do
  use GRPC.Server, service: DSPex.Bridge.SnakepitBridge.Service
  
  @impl true
  def get_variable(%GetVariableRequest{} = request, _stream) do
    case SessionStore.get_variable(request.session_id, request.variable_id) do
      {:ok, variable} ->
        %GetVariableResponse{
          variable: Variable.to_proto(variable)
        }
        
      {:error, :not_found} ->
        raise GRPC.RPCError, 
          status: :not_found, 
          message: "Variable '#{request.variable_id}' not found"
          
      {:error, :session_not_found} ->
        raise GRPC.RPCError,
          status: :not_found,
          message: "Session '#{request.session_id}' not found"
    end
  end
  
  @impl true
  def set_variable(%SetVariableRequest{} = request, _stream) do
    with {:ok, value} <- Serialization.deserialize_any(request.value),
         :ok <- SessionStore.update_variable(
           request.session_id,
           request.variable_id,
           value,
           Map.put(request.metadata, "source", "python")
         ) do
      %SetVariableResponse{success: true}
    else
      {:error, reason} ->
        %SetVariableResponse{
          success: false,
          error_message: format_error(reason)
        }
    end
  end
  
  @impl true
  def list_variables(%ListVariablesRequest{} = request, _stream) do
    case SessionStore.list_variables(request.session_id, request.filters) do
      {:ok, variables} ->
        %ListVariablesResponse{
          variables: Enum.map(variables, &Variable.to_proto/1)
        }
        
      {:error, :session_not_found} ->
        raise GRPC.RPCError,
          status: :not_found,
          message: "Session not found"
    end
  end
  
  @impl true
  def watch_variables(%WatchVariablesRequest{} = request, stream) do
    # Implementation covered in streaming section
  end
end
```

## Telemetry Events

Variables emit the following telemetry events:

```elixir
# Variable registered
:telemetry.execute(
  [:dspex, :bridge, :variable, :registered],
  %{count: 1},
  %{
    session_id: session_id,
    variable_id: variable_id,
    type: type,
    source: :elixir
  }
)

# Variable updated
:telemetry.execute(
  [:dspex, :bridge, :variable, :updated],
  %{
    old_value: old_value,
    new_value: new_value,
    update_duration_ms: duration
  },
  %{
    session_id: session_id,
    variable_id: variable_id,
    update_source: metadata.source
  }
)

# Variable deleted
:telemetry.execute(
  [:dspex, :bridge, :variable, :deleted],
  %{count: 1},
  %{session_id: session_id, variable_id: variable_id}
)
```

## Usage Examples

### Complete Variable Lifecycle

```elixir
# Create session
{:ok, session_id} = SessionStore.create_session()

# Register a temperature variable
{:ok, temp_id} = SessionStore.register_variable(
  session_id,
  :temperature,
  :float,
  0.7,
  constraints: %{min: 0.0, max: 2.0},
  description: "LLM generation temperature"
)

# Register a model selection variable
{:ok, model_id} = SessionStore.register_variable(
  session_id,
  :llm_model,
  :choice,
  "gpt-4",
  constraints: %{
    choices: ["gpt-4", "gpt-3.5-turbo", "claude-3-opus", "gemini-pro"]
  }
)

# Register a module-type variable for reasoning strategy
{:ok, reasoning_id} = SessionStore.register_variable(
  session_id,
  :reasoning_strategy,
  :module,
  "ChainOfThought",
  constraints: %{
    choices: ["Predict", "ChainOfThought", "ReAct", "ProgramOfThought"]
  },
  metadata: %{
    affects: ["reasoning_depth", "token_usage", "latency"]
  }
)

# Update temperature based on optimization
:ok = SessionStore.update_variable(
  session_id,
  temp_id,
  0.9,
  %{
    source: "bayesian_optimizer",
    iteration: 15,
    improvement: 0.03
  }
)

# List all variables
{:ok, variables} = SessionStore.list_variables(session_id)

# Clean up
:ok = SessionStore.delete_variable(session_id, temp_id)
```

### Observer Pattern Example

```elixir
defmodule TemperatureMonitor do
  use GenServer
  
  def start_link(session_id, variable_name) do
    GenServer.start_link(__MODULE__, {session_id, variable_name})
  end
  
  def init({session_id, variable_name}) do
    # Start observing
    :ok = SessionStore.observe_variable(session_id, variable_name)
    {:ok, %{session_id: session_id, variable_name: variable_name, history: []}}
  end
  
  def handle_info({:variable_updated, var_id, variable, metadata}, state) do
    IO.puts("Temperature changed to #{variable.value} by #{metadata["source"]}")
    
    # Track history
    new_history = [{DateTime.utc_now(), variable.value} | state.history]
    
    # Check for anomalies
    if variable.value > 1.5 do
      Logger.warn("Temperature unusually high: #{variable.value}")
    end
    
    {:noreply, %{state | history: new_history}}
  end
end
```

## Error Handling

### Common Error Patterns

```elixir
# Type validation errors
{:error, {:validation_failed, "must be a number"}}
{:error, {:constraint_violation, :max, 2.0, 2.5}}

# Session errors  
{:error, :session_not_found}
{:error, :session_expired}

# Variable errors
{:error, :variable_not_found}
{:error, :read_only}
{:error, :has_dependents}

# Concurrency errors
{:error, :optimistic_lock_failure}
{:error, {:already_optimizing, optimizer_pid}}
```

### Error Recovery

```elixir
# Retry pattern for concurrent updates
def safe_update_variable(session_id, var_id, new_value, attempts \\ 3) do
  case SessionStore.update_variable(session_id, var_id, new_value) do
    :ok -> 
      :ok
      
    {:error, :optimistic_lock_failure} when attempts > 0 ->
      Process.sleep(50)
      safe_update_variable(session_id, var_id, new_value, attempts - 1)
      
    error -> 
      error
  end
end
```

## Performance Considerations

1. **Variable names are indexed** for O(1) lookup by name
2. **Updates are atomic** using ETS compare-and-swap
3. **Observers are notified asynchronously** to avoid blocking
4. **History is limited** to last 100 entries per variable
5. **Batch operations** available for multiple variable updates

## Security Considerations

1. **Session isolation**: Variables cannot be accessed across sessions
2. **Type validation**: All values validated before storage
3. **Read-only variables**: Support for immutable configuration
4. **Audit trail**: All updates tracked with metadata
5. **Rate limiting**: Can be applied per session
# Stage 1: Core Variable Implementation

## Overview

Stage 1 implements the fundamental variable system, establishing Elixir as the source of truth for all state. This stage focuses on basic CRUD operations for variables with simple types, laying the groundwork for more advanced features in later stages.

## Goals

1. Extend SessionStore to manage variables with type validation
2. Implement gRPC handlers for variable operations
3. Build Python SessionContext with caching and type conversion
4. Enable cross-language state synchronization
5. Demonstrate bidirectional variable updates

## Deliverables

- Enhanced SessionStore with variable management
- Working Get/Set variable RPCs
- Python variable cache with TTL
- Type system for basic types (float, integer, string, boolean)
- Integration tests proving cross-language state sync

## Detailed Implementation Plan

### 1. Extend SessionStore for Variables

#### Update `snakepit/lib/snakepit/bridge/session_store.ex`:

```elixir
defmodule Snakepit.Bridge.SessionStore do
  use GenServer
  require Logger
  
  alias Snakepit.Bridge.Variables.{Variable, Types}
  
  @table_name :snakepit_sessions
  
  defstruct [
    :session_id,
    :tools,
    :variables,         # Map of var_id => Variable struct
    :variable_index,    # Map of name => var_id for fast lookup
    :metadata,
    :created_at,
    :last_accessed_at
  ]
  
  # Existing session management code...
  
  # Variable Operations
  
  @doc """
  Register a new variable in the session.
  """
  def register_variable(session_id, name, type, initial_value, opts \\ []) do
    GenServer.call(__MODULE__, {:register_variable, session_id, name, type, initial_value, opts})
  end
  
  @doc """
  Get a variable by ID or name.
  """
  def get_variable(session_id, identifier) do
    GenServer.call(__MODULE__, {:get_variable, session_id, identifier})
  end
  
  @doc """
  Update a variable's value.
  """
  def update_variable(session_id, identifier, new_value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_variable, session_id, identifier, new_value, metadata})
  end
  
  @doc """
  List all variables in a session.
  """
  def list_variables(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:list_variables, session_id, opts})
  end
  
  # Batch operations
  
  @doc """
  Get multiple variables at once.
  """
  def get_variables(session_id, identifiers) do
    GenServer.call(__MODULE__, {:get_variables, session_id, identifiers})
  end
  
  @doc """
  Update multiple variables atomically.
  """
  def update_variables(session_id, updates, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_variables, session_id, updates, metadata})
  end
  
  # GenServer callbacks for variables
  
  def handle_call({:register_variable, session_id, name, type, initial_value, opts}, _from, state) do
    with {:ok, session} <- get_session(state, session_id),
         {:ok, type_module} <- Types.get_type_module(type),
         {:ok, validated_value} <- type_module.validate(initial_value) do
      
      var_id = generate_variable_id(name)
      
      variable = %Variable{
        id: var_id,
        name: name,
        type: type,
        value: validated_value,
        constraints: opts[:constraints] || %{},
        metadata: Map.merge(
          %{
            created_at: DateTime.utc_now(),
            source: :elixir,
            description: opts[:description]
          },
          opts[:metadata] || %{}
        ),
        last_updated_at: DateTime.utc_now()
      }
      
      # Validate constraints
      case type_module.validate_constraints(validated_value, variable.constraints) do
        :ok ->
          updated_session = session
          |> Map.update!(:variables, &Map.put(&1, var_id, variable))
          |> Map.update!(:variable_index, &Map.put(&1, name, var_id))
          |> touch_session()
          
          new_state = put_session(state, session_id, updated_session)
          
          Logger.info("Registered variable #{name} (#{var_id}) in session #{session_id}")
          
          {:reply, {:ok, var_id}, new_state}
          
        {:error, reason} ->
          {:reply, {:error, {:constraint_violation, reason}}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:get_variable, session_id, identifier}, _from, state) do
    with {:ok, session} <- get_session(state, session_id),
         {:ok, var_id} <- resolve_variable_id(session, identifier),
         {:ok, variable} <- Map.fetch(session.variables, var_id) do
      
      updated_session = touch_session(session)
      new_state = put_session(state, session_id, updated_session)
      
      {:reply, {:ok, variable}, new_state}
    else
      :error -> {:reply, {:error, :variable_not_found}, state}
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:update_variable, session_id, identifier, new_value, metadata}, _from, state) do
    with {:ok, session} <- get_session(state, session_id),
         {:ok, var_id} <- resolve_variable_id(session, identifier),
         {:ok, variable} <- Map.fetch(session.variables, var_id),
         {:ok, type_module} <- Types.get_type_module(variable.type),
         {:ok, validated_value} <- type_module.validate(new_value),
         :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
      
      updated_variable = %{variable |
        value: validated_value,
        last_updated_at: DateTime.utc_now(),
        metadata: Map.merge(variable.metadata, metadata)
      }
      
      updated_session = session
      |> Map.update!(:variables, &Map.put(&1, var_id, updated_variable))
      |> touch_session()
      
      new_state = put_session(state, session_id, updated_session)
      
      Logger.debug("Updated variable #{var_id} in session #{session_id}")
      
      {:reply, :ok, new_state}
    else
      :error -> {:reply, {:error, :variable_not_found}, state}
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:list_variables, session_id, opts}, _from, state) do
    with {:ok, session} <- get_session(state, session_id) do
      variables = session.variables
      |> Map.values()
      |> filter_variables(opts)
      
      updated_session = touch_session(session)
      new_state = put_session(state, session_id, updated_session)
      
      {:reply, {:ok, variables}, new_state}
    else
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:get_variables, session_id, identifiers}, _from, state) do
    with {:ok, session} <- get_session(state, session_id) do
      results = Enum.reduce(identifiers, %{}, fn identifier, acc ->
        case resolve_variable_id(session, identifier) do
          {:ok, var_id} ->
            case Map.fetch(session.variables, var_id) do
              {:ok, variable} -> Map.put(acc, identifier, {:ok, variable})
              :error -> Map.put(acc, identifier, {:error, :not_found})
            end
          {:error, _} ->
            Map.put(acc, identifier, {:error, :not_found})
        end
      end)
      
      updated_session = touch_session(session)
      new_state = put_session(state, session_id, updated_session)
      
      {:reply, {:ok, results}, new_state}
    else
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:update_variables, session_id, updates, metadata}, _from, state) do
    with {:ok, session} <- get_session(state, session_id) do
      # Validate all updates first
      validated_updates = Enum.reduce_while(updates, {:ok, []}, fn {identifier, new_value}, {:ok, acc} ->
        with {:ok, var_id} <- resolve_variable_id(session, identifier),
             {:ok, variable} <- Map.fetch(session.variables, var_id),
             {:ok, type_module} <- Types.get_type_module(variable.type),
             {:ok, validated_value} <- type_module.validate(new_value),
             :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
          {:cont, {:ok, [{var_id, variable, validated_value} | acc]}}
        else
          error -> {:halt, {:error, {identifier, error}}}
        end
      end)
      
      case validated_updates do
        {:ok, updates_list} ->
          # Apply all updates
          updated_variables = Enum.reduce(updates_list, session.variables, fn {var_id, variable, new_value}, vars ->
            updated_var = %{variable |
              value: new_value,
              last_updated_at: DateTime.utc_now(),
              metadata: Map.merge(variable.metadata, metadata)
            }
            Map.put(vars, var_id, updated_var)
          end)
          
          updated_session = session
          |> Map.put(:variables, updated_variables)
          |> touch_session()
          
          new_state = put_session(state, session_id, updated_session)
          
          {:reply, :ok, new_state}
          
        error ->
          {:reply, error, state}
      end
    else
      error -> {:reply, error, state}
    end
  end
  
  # Helper functions
  
  defp generate_variable_id(name) do
    "var_#{name}_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp resolve_variable_id(session, identifier) when is_binary(identifier) do
    # Check if it's already a var_id
    if Map.has_key?(session.variables, identifier) do
      {:ok, identifier}
    else
      # Try to resolve as name
      case Map.fetch(session.variable_index, identifier) do
        {:ok, var_id} -> {:ok, var_id}
        :error -> {:error, :not_found}
      end
    end
  end
  
  defp resolve_variable_id(session, identifier) when is_atom(identifier) do
    resolve_variable_id(session, Atom.to_string(identifier))
  end
  
  defp filter_variables(variables, opts) do
    variables
    |> filter_by_type(opts[:type])
    |> filter_by_source(opts[:source])
  end
  
  defp filter_by_type(variables, nil), do: variables
  defp filter_by_type(variables, type), do: Enum.filter(variables, &(&1.type == type))
  
  defp filter_by_source(variables, nil), do: variables
  defp filter_by_source(variables, source), do: Enum.filter(variables, &(&1.metadata.source == source))
  
  defp touch_session(session) do
    %{session | last_accessed_at: DateTime.utc_now()}
  end
end
```

### 2. Create Variable Type System

#### Create `snakepit/lib/snakepit/bridge/variables/variable.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.Variable do
  @moduledoc """
  Represents a variable in the bridge system.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t() | atom(),
    type: atom(),
    value: any(),
    constraints: map(),
    metadata: map(),
    last_updated_at: DateTime.t()
  }
  
  defstruct [
    :id,
    :name,
    :type,
    :value,
    :constraints,
    :metadata,
    :last_updated_at
  ]
  
  @doc """
  Convert variable to protobuf representation.
  """
  def to_proto(%__MODULE__{} = var) do
    Snakepit.Bridge.Variable.new(
      id: var.id,
      name: to_string(var.name),
      type: to_string(var.type),
      value: encode_value(var.value, var.type),
      constraints_json: Jason.encode!(var.constraints),
      metadata: var.metadata,
      source: if(var.metadata[:source] == :python, do: :PYTHON, else: :ELIXIR),
      last_updated_at: DateTime.to_unix(var.last_updated_at, :millisecond)
    )
  end
  
  @doc """
  Create variable from protobuf representation.
  """
  def from_proto(proto) do
    %__MODULE__{
      id: proto.id,
      name: proto.name,
      type: String.to_existing_atom(proto.type),
      value: decode_value(proto.value, proto.type),
      constraints: Jason.decode!(proto.constraints_json),
      metadata: Map.new(proto.metadata),
      last_updated_at: DateTime.from_unix!(proto.last_updated_at, :millisecond)
    }
  end
  
  defp encode_value(value, type) do
    # This will be expanded with proper Any encoding
    # For now, use JSON encoding
    type_tag = "#{type}:#{Jason.encode!(value)}"
    Google.Protobuf.Any.new(
      type_url: "type.googleapis.com/snakepit.bridge.#{type}",
      value: type_tag
    )
  end
  
  defp decode_value(any, type_string) do
    # Extract the JSON-encoded value
    # This is temporary - will use proper Any decoding later
    [_, json] = String.split(any.value, ":", parts: 2)
    Jason.decode!(json)
  end
end
```

#### Create `snakepit/lib/snakepit/bridge/variables/types.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.Types do
  @moduledoc """
  Type system for variables.
  """
  
  @type_modules %{
    float: Snakepit.Bridge.Variables.Types.Float,
    integer: Snakepit.Bridge.Variables.Types.Integer,
    string: Snakepit.Bridge.Variables.Types.String,
    boolean: Snakepit.Bridge.Variables.Types.Boolean
  }
  
  def get_type_module(type) when is_atom(type) do
    case Map.fetch(@type_modules, type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_type, type}}
    end
  end
  
  def get_type_module(type) when is_binary(type) do
    get_type_module(String.to_existing_atom(type))
  rescue
    ArgumentError -> {:error, {:unknown_type, type}}
  end
  
  def list_types, do: Map.keys(@type_modules)
end

defmodule Snakepit.Bridge.Variables.Types.Behaviour do
  @callback validate(value :: any()) :: {:ok, any()} | {:error, String.t()}
  @callback validate_constraints(value :: any(), constraints :: map()) :: :ok | {:error, String.t()}
  @callback serialize(value :: any()) :: binary()
  @callback deserialize(binary :: binary()) :: {:ok, any()} | {:error, String.t()}
end

defmodule Snakepit.Bridge.Variables.Types.Float do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_float(value), do: {:ok, value}
  def validate(value) when is_integer(value), do: {:ok, value * 1.0}
  def validate(_), do: {:error, "must be a number"}
  
  @impl true
  def validate_constraints(value, constraints) do
    with :ok <- check_min(value, constraints[:min]),
         :ok <- check_max(value, constraints[:max]) do
      :ok
    end
  end
  
  @impl true
  def serialize(value), do: to_string(value)
  
  @impl true
  def deserialize(binary) do
    case Float.parse(binary) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "invalid float"}
    end
  end
  
  defp check_min(_value, nil), do: :ok
  defp check_min(value, min) when value >= min, do: :ok
  defp check_min(value, min), do: {:error, "value #{value} is below minimum #{min}"}
  
  defp check_max(_value, nil), do: :ok
  defp check_max(value, max) when value <= max, do: :ok
  defp check_max(value, max), do: {:error, "value #{value} is above maximum #{max}"}
end

defmodule Snakepit.Bridge.Variables.Types.Integer do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_integer(value), do: {:ok, value}
  def validate(_), do: {:error, "must be an integer"}
  
  @impl true
  def validate_constraints(value, constraints) do
    with :ok <- check_min(value, constraints[:min]),
         :ok <- check_max(value, constraints[:max]),
         :ok <- check_step(value, constraints) do
      :ok
    end
  end
  
  @impl true
  def serialize(value), do: to_string(value)
  
  @impl true
  def deserialize(binary) do
    case Integer.parse(binary) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "invalid integer"}
    end
  end
  
  defp check_min(_value, nil), do: :ok
  defp check_min(value, min) when value >= min, do: :ok
  defp check_min(value, min), do: {:error, "value #{value} is below minimum #{min}"}
  
  defp check_max(_value, nil), do: :ok
  defp check_max(value, max) when value <= max, do: :ok
  defp check_max(value, max), do: {:error, "value #{value} is above maximum #{max}"}
  
  defp check_step(_value, %{step: nil}), do: :ok
  defp check_step(_value, %{}), do: :ok
  defp check_step(value, %{step: step, min: min}) do
    if rem(value - min, step) == 0 do
      :ok
    else
      {:error, "value #{value} is not a multiple of step #{step} from minimum #{min}"}
    end
  end
  defp check_step(value, %{step: step}) do
    if rem(value, step) == 0 do
      :ok
    else
      {:error, "value #{value} is not a multiple of step #{step}"}
    end
  end
end

defmodule Snakepit.Bridge.Variables.Types.String do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_binary(value), do: {:ok, value}
  def validate(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def validate(_), do: {:error, "must be a string"}
  
  @impl true
  def validate_constraints(value, constraints) do
    with :ok <- check_min_length(value, constraints[:min_length]),
         :ok <- check_max_length(value, constraints[:max_length]),
         :ok <- check_pattern(value, constraints[:pattern]) do
      :ok
    end
  end
  
  @impl true
  def serialize(value), do: value
  
  @impl true
  def deserialize(binary) when is_binary(binary), do: {:ok, binary}
  def deserialize(_), do: {:error, "invalid string"}
  
  defp check_min_length(_value, nil), do: :ok
  defp check_min_length(value, min) when byte_size(value) >= min, do: :ok
  defp check_min_length(value, min), do: {:error, "string length #{byte_size(value)} is below minimum #{min}"}
  
  defp check_max_length(_value, nil), do: :ok
  defp check_max_length(value, max) when byte_size(value) <= max, do: :ok
  defp check_max_length(value, max), do: {:error, "string length #{byte_size(value)} is above maximum #{max}"}
  
  defp check_pattern(_value, nil), do: :ok
  defp check_pattern(value, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, value) do
          :ok
        else
          {:error, "value does not match pattern #{pattern}"}
        end
      {:error, _} ->
        {:error, "invalid regex pattern"}
    end
  end
end

defmodule Snakepit.Bridge.Variables.Types.Boolean do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_boolean(value), do: {:ok, value}
  def validate(_), do: {:error, "must be a boolean"}
  
  @impl true
  def validate_constraints(_value, _constraints), do: :ok
  
  @impl true
  def serialize(true), do: "true"
  def serialize(false), do: "false"
  
  @impl true
  def deserialize("true"), do: {:ok, true}
  def deserialize("false"), do: {:ok, false}
  def deserialize(_), do: {:error, "invalid boolean"}
end
```

### 3. Implement gRPC Handlers

#### Update `snakepit/lib/snakepit/grpc/server.ex`:

```elixir
defmodule Snakepit.GRPC.Server do
  use GRPC.Server, service: Snakepit.Bridge.SnakepitBridge.Service
  
  alias Snakepit.Bridge.{SessionStore, Variables.Variable}
  require Logger
  
  @impl true
  def get_variable(request, _stream) do
    case SessionStore.get_variable(request.session_id, request.variable_id) do
      {:ok, variable} ->
        Snakepit.Bridge.GetVariableResponse.new(
          variable: Variable.to_proto(variable)
        )
        
      {:error, :session_not_found} ->
        raise GRPC.RPCError,
          status: :not_found,
          message: "Session not found: #{request.session_id}"
          
      {:error, :variable_not_found} ->
        raise GRPC.RPCError,
          status: :not_found,
          message: "Variable not found: #{request.variable_id}"
    end
  end
  
  @impl true
  def set_variable(request, _stream) do
    with {:ok, value} <- decode_any_value(request.value),
         :ok <- SessionStore.update_variable(
           request.session_id,
           request.variable_id,
           value,
           Map.put(request.metadata, "source", "python")
         ) do
      
      Snakepit.Bridge.SetVariableResponse.new(
        success: true
      )
    else
      {:error, :session_not_found} ->
        Snakepit.Bridge.SetVariableResponse.new(
          success: false,
          error_message: "Session not found"
        )
        
      {:error, :variable_not_found} ->
        Snakepit.Bridge.SetVariableResponse.new(
          success: false,
          error_message: "Variable not found"
        )
        
      {:error, reason} ->
        Snakepit.Bridge.SetVariableResponse.new(
          success: false,
          error_message: inspect(reason)
        )
    end
  end
  
  @impl true
  def get_variables(request, _stream) do
    case SessionStore.get_variables(request.session_id, request.variable_ids) do
      {:ok, results} ->
        variables = Enum.reduce(results, %{}, fn {id, result}, acc ->
          case result do
            {:ok, variable} ->
              Map.put(acc, id, Variable.to_proto(variable))
            {:error, _} ->
              acc  # Skip missing variables
          end
        end)
        
        Snakepit.Bridge.BatchGetVariablesResponse.new(
          variables: variables
        )
        
      {:error, :session_not_found} ->
        raise GRPC.RPCError,
          status: :not_found,
          message: "Session not found"
    end
  end
  
  @impl true
  def set_variables(request, _stream) do
    updates = Enum.reduce(request.updates, %{}, fn {id, any_value}, acc ->
      case decode_any_value(any_value) do
        {:ok, value} -> Map.put(acc, id, value)
        {:error, _} -> acc
      end
    end)
    
    if request.atomic do
      case SessionStore.update_variables(request.session_id, updates, request.metadata) do
        :ok ->
          Snakepit.Bridge.BatchSetVariablesResponse.new(success: true)
          
        {:error, {identifier, reason}} ->
          Snakepit.Bridge.BatchSetVariablesResponse.new(
            success: false,
            errors: %{identifier => inspect(reason)}
          )
          
        {:error, reason} ->
          Snakepit.Bridge.BatchSetVariablesResponse.new(
            success: false,
            errors: %{"_general" => inspect(reason)}
          )
      end
    else
      # Non-atomic updates - attempt each one
      errors = Enum.reduce(updates, %{}, fn {id, value}, acc ->
        case SessionStore.update_variable(request.session_id, id, value, request.metadata) do
          :ok -> acc
          {:error, reason} -> Map.put(acc, id, inspect(reason))
        end
      end)
      
      Snakepit.Bridge.BatchSetVariablesResponse.new(
        success: map_size(errors) == 0,
        errors: errors
      )
    end
  end
  
  defp decode_any_value(any) do
    # Temporary implementation using the type tag approach
    # Will be replaced with proper Any decoding
    case String.split(any.value, ":", parts: 2) do
      [type, json] ->
        value = Jason.decode!(json)
        {:ok, value}
      _ ->
        {:error, :invalid_encoding}
    end
  rescue
    e -> {:error, e}
  end
end
```

### 4. Enhance Python SessionContext

#### Update `snakepit/priv/python/snakepit_bridge/session_context.py`:

```python
"""
Enhanced SessionContext with variable support.
"""

import asyncio
import json
import time
from typing import Dict, Any, Optional, Tuple, List, Union
from datetime import datetime
import logging

import grpc
from google.protobuf import any_pb2

from .grpc import snakepit_bridge_pb2 as pb2
from .grpc import snakepit_bridge_pb2_grpc as pb2_grpc
from .serialization import VariableSerializer

logger = logging.getLogger(__name__)


class VariableCache:
    """Simple TTL-based cache for variables."""
    
    def __init__(self, ttl: float = 1.0):
        self._cache: Dict[str, Tuple[Any, float]] = {}
        self._ttl = ttl
        self._stats = {
            'hits': 0,
            'misses': 0,
            'evictions': 0
        }
    
    def get(self, key: str) -> Optional[Any]:
        """Get value from cache if not expired."""
        if key in self._cache:
            value, timestamp = self._cache[key]
            if time.time() - timestamp < self._ttl:
                self._stats['hits'] += 1
                return value
            else:
                # Expired
                del self._cache[key]
                self._stats['evictions'] += 1
        
        self._stats['misses'] += 1
        return None
    
    def set(self, key: str, value: Any):
        """Set value in cache."""
        self._cache[key] = (value, time.time())
    
    def invalidate(self, key: Optional[str] = None):
        """Invalidate specific key or entire cache."""
        if key:
            self._cache.pop(key, None)
        else:
            self._cache.clear()
    
    def get_stats(self) -> Dict[str, int]:
        """Get cache statistics."""
        total = self._stats['hits'] + self._stats['misses']
        hit_rate = self._stats['hits'] / total if total > 0 else 0
        
        return {
            **self._stats,
            'size': len(self._cache),
            'hit_rate': hit_rate
        }


class SessionContext:
    """
    Enhanced session context with full variable support.
    """
    
    def __init__(self, session_id: str, channel: grpc.aio.Channel):
        self.session_id = session_id
        self.channel = channel
        self.stub = pb2_grpc.SnakepitBridgeStub(channel)
        
        # Variable management
        self._variable_cache = VariableCache()
        self._serializer = VariableSerializer()
        
        # Tools (Stage 2)
        self._tools: Dict[str, Any] = {}
        
        # Metadata
        self.metadata: Dict[str, str] = {}
        
        logger.info(f"SessionContext created for session {session_id}")
    
    # Variable Operations
    
    async def get_variable(self, name: str, default: Any = None, 
                          bypass_cache: bool = False) -> Any:
        """Get a variable value from the session."""
        # Check cache first
        if not bypass_cache:
            cached_value = self._variable_cache.get(name)
            if cached_value is not None:
                return cached_value
        
        try:
            # Fetch from server
            request = pb2.GetVariableRequest(
                session_id=self.session_id,
                variable_id=name
            )
            
            response = await self.stub.GetVariable(request)
            
            # Deserialize value
            value = self._serializer.deserialize(
                response.variable.value,
                response.variable.type
            )
            
            # Cache it
            self._variable_cache.set(name, value)
            
            return value
            
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND and default is not None:
                return default
            raise KeyError(f"Variable '{name}' not found")
    
    async def set_variable(self, name: str, value: Any, 
                          metadata: Optional[Dict[str, str]] = None) -> None:
        """Set a variable value in the session."""
        # Serialize value
        any_value = self._serializer.serialize(value)
        
        request = pb2.SetVariableRequest(
            session_id=self.session_id,
            variable_id=name,
            value=any_value,
            metadata=metadata or {}
        )
        
        response = await self.stub.SetVariable(request)
        
        if not response.success:
            raise ValueError(f"Failed to set variable: {response.error_message}")
        
        # Update cache
        self._variable_cache.set(name, value)
    
    async def get_variables(self, names: List[str], 
                           defaults: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Get multiple variables efficiently."""
        defaults = defaults or {}
        
        # Check cache for all variables
        results = {}
        missing = []
        
        for name in names:
            cached_value = self._variable_cache.get(name)
            if cached_value is not None:
                results[name] = cached_value
            else:
                missing.append(name)
        
        if missing:
            # Fetch missing from server
            request = pb2.BatchGetVariablesRequest(
                session_id=self.session_id,
                variable_ids=missing
            )
            
            response = await self.stub.GetVariables(request)
            
            for var_id, var_proto in response.variables.items():
                value = self._serializer.deserialize(
                    var_proto.value,
                    var_proto.type
                )
                results[var_id] = value
                self._variable_cache.set(var_id, value)
        
        # Apply defaults for any still missing
        for name in names:
            if name not in results and name in defaults:
                results[name] = defaults[name]
        
        return results
    
    async def update_variables(self, updates: Dict[str, Any], 
                              metadata: Optional[Dict[str, str]] = None,
                              atomic: bool = True) -> Dict[str, Union[bool, str]]:
        """Update multiple variables."""
        # Serialize all values
        serialized_updates = {}
        for name, value in updates.items():
            serialized_updates[name] = self._serializer.serialize(value)
        
        request = pb2.BatchSetVariablesRequest(
            session_id=self.session_id,
            updates=serialized_updates,
            metadata=metadata or {},
            atomic=atomic
        )
        
        response = await self.stub.SetVariables(request)
        
        if response.success:
            # Update cache for all successful updates
            for name, value in updates.items():
                self._variable_cache.set(name, value)
            return {name: True for name in updates}
        else:
            # Return error details
            results = {}
            for name in updates:
                if name in response.errors:
                    results[name] = response.errors[name]
                else:
                    results[name] = True
                    self._variable_cache.set(name, updates[name])
            return results
    
    async def list_variables(self) -> Dict[str, Dict[str, Any]]:
        """List all variables in the session."""
        # For Stage 1, we'll implement a simple version
        # Stage 3 will add the full RPC
        raise NotImplementedError("list_variables will be implemented in Stage 3")
    
    # Cache Management
    
    def set_cache_ttl(self, ttl: float):
        """Set cache TTL."""
        self._variable_cache._ttl = ttl
    
    def invalidate_cache(self, name: Optional[str] = None):
        """Invalidate variable cache."""
        self._variable_cache.invalidate(name)
    
    def get_cache_stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        return self._variable_cache.get_stats()
```

#### Create `snakepit/priv/python/snakepit_bridge/serialization.py`:

```python
"""
Variable serialization for gRPC transport.
"""

import json
from typing import Any
from google.protobuf import any_pb2


class VariableSerializer:
    """Handles serialization of variables for gRPC transport."""
    
    def serialize(self, value: Any) -> any_pb2.Any:
        """Serialize a Python value to protobuf Any."""
        # Determine type
        if isinstance(value, bool):
            type_name = "boolean"
        elif isinstance(value, int):
            type_name = "integer"
        elif isinstance(value, float):
            type_name = "float"
        elif isinstance(value, str):
            type_name = "string"
        else:
            # Fallback to JSON for complex types
            type_name = "json"
            value = json.dumps(value)
        
        # Create type tag (temporary approach)
        type_tag = f"{type_name}:{json.dumps(value)}"
        
        any_value = any_pb2.Any()
        any_value.type_url = f"type.googleapis.com/snakepit.bridge.{type_name}"
        any_value.value = type_tag.encode('utf-8')
        
        return any_value
    
    def deserialize(self, any_value: any_pb2.Any, type_hint: str) -> Any:
        """Deserialize protobuf Any to Python value."""
        # Extract type tag
        type_tag = any_value.value.decode('utf-8')
        
        # Parse type and JSON value
        type_name, json_str = type_tag.split(':', 1)
        raw_value = json.loads(json_str)
        
        # Convert based on type
        if type_name == "boolean":
            return bool(raw_value)
        elif type_name == "integer":
            return int(raw_value)
        elif type_name == "float":
            return float(raw_value)
        elif type_name == "string":
            return str(raw_value)
        else:
            # Complex type - return as-is
            return raw_value
```

### 5. Integration Tests

#### Create `test/snakepit/grpc_stage1_integration_test.exs`:

```elixir
defmodule Snakepit.GRPCStage1IntegrationTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.GRPC.Client
  
  @moduletag :integration
  
  setup do
    # Start SessionStore if not already started
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Create a test session
    session_id = "test_session_#{System.unique_integer()}"
    {:ok, _} = SessionStore.create_session(session_id)
    
    # Start Python bridge
    port = 50200 + System.unique_integer([:positive]) |> rem(100)
    
    # Start gRPC server process
    python_port = start_python_bridge(port)
    
    # Connect client
    {:ok, channel} = Client.connect(port)
    
    # Initialize Python session
    {:ok, _} = Client.initialize_session(channel, session_id)
    
    on_exit(fn ->
      Client.cleanup_session(channel, session_id)
      GRPC.Channel.close(channel)
      stop_python_bridge(python_port)
      SessionStore.delete_session(session_id)
    end)
    
    {:ok, session_id: session_id, channel: channel, port: port}
  end
  
  describe "cross-language variable synchronization" do
    test "Elixir can set variable, Python can read it", %{session_id: session_id, channel: channel} do
      # Register variable in Elixir
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        "temperature",
        :float,
        0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Python reads it
      {:ok, response} = Client.get_variable(channel, session_id, "temperature")
      
      assert response.variable.name == "temperature"
      assert response.variable.type == "float"
      
      # Deserialize value
      assert decode_value(response.variable.value) == 0.7
    end
    
    test "Python can set variable, Elixir can read it", %{session_id: session_id, channel: channel} do
      # Register variable first
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        "max_tokens",
        :integer,
        256
      )
      
      # Python updates it
      {:ok, response} = Client.set_variable(channel, session_id, "max_tokens", 512)
      assert response.success == true
      
      # Verify in Elixir
      {:ok, variable} = SessionStore.get_variable(session_id, "max_tokens")
      assert variable.value == 512
      assert variable.metadata["source"] == "python"
    end
    
    test "batch operations work correctly", %{session_id: session_id, channel: channel} do
      # Register multiple variables
      {:ok, _} = SessionStore.register_variable(session_id, "var1", :string, "hello")
      {:ok, _} = SessionStore.register_variable(session_id, "var2", :integer, 42)
      {:ok, _} = SessionStore.register_variable(session_id, "var3", :boolean, true)
      
      # Batch get from Python
      {:ok, response} = Client.get_variables(channel, session_id, ["var1", "var2", "var3"])
      
      assert map_size(response.variables) == 3
      assert decode_value(response.variables["var1"].value) == "hello"
      assert decode_value(response.variables["var2"].value) == 42
      assert decode_value(response.variables["var3"].value) == true
      
      # Batch update from Python
      updates = %{
        "var1" => encode_value("world", :string),
        "var2" => encode_value(100, :integer)
      }
      
      {:ok, update_response} = Client.set_variables(channel, session_id, updates, %{}, true)
      assert update_response.success == true
      
      # Verify in Elixir
      {:ok, var1} = SessionStore.get_variable(session_id, "var1")
      assert var1.value == "world"
      
      {:ok, var2} = SessionStore.get_variable(session_id, "var2")
      assert var2.value == 100
    end
    
    test "type validation works across languages", %{session_id: session_id, channel: channel} do
      # Register typed variable
      {:ok, _} = SessionStore.register_variable(
        session_id,
        "strict_int",
        :integer,
        10,
        constraints: %{min: 0, max: 100}
      )
      
      # Try to set invalid value from Python
      {:ok, response} = Client.set_variable(channel, session_id, "strict_int", 150)
      assert response.success == false
      assert response.error_message =~ "above maximum"
      
      # Value should remain unchanged
      {:ok, var} = SessionStore.get_variable(session_id, "strict_int")
      assert var.value == 10
    end
  end
  
  # Test helpers
  
  defp start_python_bridge(port) do
    # Start Python gRPC server
    # This is simplified - in real tests, use proper process management
    python_cmd = """
    python3 -m snakepit_bridge.grpc_bridge --port #{port}
    """
    
    Port.open({:spawn, python_cmd}, [:binary, :exit_status])
    
    # Wait for server to start
    wait_for_port(port)
  end
  
  defp stop_python_bridge(port) do
    Port.close(port)
  end
  
  defp wait_for_port(port, attempts \\ 20)
  defp wait_for_port(_port, 0), do: raise "Python bridge failed to start"
  defp wait_for_port(port, attempts) do
    case :gen_tcp.connect('localhost', port, [:binary], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok
      {:error, _} ->
        Process.sleep(100)
        wait_for_port(port, attempts - 1)
    end
  end
  
  defp encode_value(value, type) do
    # Temporary encoding
    type_tag = "#{type}:#{Jason.encode!(value)}"
    Google.Protobuf.Any.new(
      type_url: "type.googleapis.com/snakepit.bridge.#{type}",
      value: type_tag
    )
  end
  
  defp decode_value(any) do
    [_type, json] = String.split(any.value, ":", parts: 2)
    Jason.decode!(json)
  end
end
```

### 6. Python Integration Test

Create `snakepit/priv/python/tests/test_stage1_variables.py`:

```python
import asyncio
import pytest
import grpc

from snakepit_bridge.session_context import SessionContext


@pytest.mark.asyncio
async def test_variable_operations():
    """Test basic variable operations."""
    # Connect to test server (assumed to be running)
    channel = grpc.aio.insecure_channel('localhost:50051')
    session = SessionContext("test_session", channel)
    
    try:
        # Set a variable
        await session.set_variable('test_var', 42)
        
        # Get it back
        value = await session.get_variable('test_var')
        assert value == 42
        
        # Update it
        await session.set_variable('test_var', 100)
        value = await session.get_variable('test_var')
        assert value == 100
        
        # Test cache
        value1 = await session.get_variable('test_var')  # Should hit cache
        value2 = await session.get_variable('test_var', bypass_cache=True)  # Force fetch
        assert value1 == value2
        
        stats = session.get_cache_stats()
        assert stats['hits'] > 0
        
    finally:
        await channel.close()


@pytest.mark.asyncio
async def test_batch_operations():
    """Test batch variable operations."""
    channel = grpc.aio.insecure_channel('localhost:50051')
    session = SessionContext("test_session", channel)
    
    try:
        # Set multiple variables
        results = await session.update_variables({
            'var1': 'hello',
            'var2': 42,
            'var3': 3.14,
            'var4': True
        })
        
        assert all(v is True for v in results.values())
        
        # Get them all
        values = await session.get_variables(['var1', 'var2', 'var3', 'var4'])
        
        assert values['var1'] == 'hello'
        assert values['var2'] == 42
        assert values['var3'] == 3.14
        assert values['var4'] is True
        
    finally:
        await channel.close()
```

## Success Criteria

1. **Variable CRUD**: Can create, read, update variables from both languages
2. **Type Safety**: Type validation works across language boundary
3. **Caching Works**: Python cache reduces server calls
4. **Batch Operations**: Can get/set multiple variables efficiently
5. **State Sync**: Changes in one language immediately visible in other

## Common Issues and Solutions

### Issue: Type Serialization Mismatch
- **Solution**: Ensure consistent JSON encoding on both sides
- **Solution**: Add logging to debug serialization

### Issue: Cache Inconsistency
- **Solution**: Always update cache after successful set
- **Solution**: Add cache invalidation on errors

### Issue: Constraint Validation Differences
- **Solution**: Implement identical validation logic
- **Solution**: Test edge cases thoroughly

## Performance Considerations

1. **Cache TTL**: Default 1 second is conservative, can be increased
2. **Batch Size**: Batch operations should be limited to ~100 variables
3. **Serialization**: JSON is temporary, will move to proper protobuf in future

## Next Stage

Stage 2 will integrate variables with tools and DSPy modules:
- Variable-aware proxy tools
- DSPy module mixins for variable binding
- Automatic variable injection
- Tool execution with variable context
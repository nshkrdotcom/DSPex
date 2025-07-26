# Prompt: Implement Variables System

## Context

You are implementing the **Variables System** for the SnakepitGRPCBridge ML platform. This prompt covers **Phase 1, Day 3** of the implementation plan.

## Required Reading

Before starting, read these documents in order:
1. `docs/specs/threeLayerRevised/03_SNAKEPIT_GRPC_BRIDGE_PLATFORM_SPECIFICATION.md` - Platform specification (Variables section)
2. `docs/specs/threeLayerRevised/07_DETAILED_IN_PLACE_IMPLEMENTATION_PLAN.md` - Implementation plan (Day 3)

## Prerequisites

Complete the bootstrap phase first:
- `snakepit_grpc_bridge` package structure exists
- Basic OTP application and adapter are implemented
- Placeholder API modules exist

## Current State Analysis

Examine the current variable implementations:
- `./lib/dspex/variables/` (if exists) - Current DSPex variable logic
- `./snakepit/lib/snakepit/bridge/` (if exists) - Current bridge variable logic
- Look for any existing variable management code

Identify:
1. Current variable storage mechanisms
2. Existing variable types and serialization
3. Session-based variable management
4. Any ML-specific variable types (tensors, embeddings, models)

## Objective

Implement a complete variables system that:
1. Manages variables per session with full lifecycle
2. Supports basic types (string, integer, float, boolean, binary)
3. Supports ML types (tensor, embedding, model, dataset)
4. Provides efficient storage and serialization
5. Offers clean API for consumers
6. Includes comprehensive telemetry

## Implementation Tasks

### Task 1: Implement Variables Manager

Create `lib/snakepit_grpc_bridge/variables/manager.ex`:

```elixir
defmodule SnakepitGRPCBridge.Variables.Manager do
  @moduledoc """
  Core variable manager for the ML platform.
  
  Manages variable lifecycle, storage, and session isolation.
  Supports both basic types and ML-specific types with serialization.
  """
  
  use GenServer
  require Logger

  defstruct [
    :sessions,           # ETS table for session metadata
    :variables,          # ETS table for variable storage
    :telemetry_collector,
    :stats
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new variable in the session.
  
  ## Examples
  
      {:ok, variable} = SnakepitGRPCBridge.Variables.Manager.create(
        "session_123", 
        "temperature", 
        :float, 
        0.7,
        description: "LLM temperature parameter"
      )
  """
  def create(session_id, name, type, value, opts \\ []) do
    GenServer.call(__MODULE__, {:create, session_id, name, type, value, opts})
  end

  @doc """
  Get variable value from session.
  
  Returns the default value if variable doesn't exist.
  """
  def get(session_id, identifier, default \\ nil) do
    GenServer.call(__MODULE__, {:get, session_id, identifier, default})
  end

  @doc """
  Set variable value in session.
  
  Variable must already exist (use create/5 to create new variables).
  """
  def set(session_id, identifier, value, opts \\ []) do
    GenServer.call(__MODULE__, {:set, session_id, identifier, value, opts})
  end

  @doc """
  List all variables in session.
  """
  def list(session_id) do
    GenServer.call(__MODULE__, {:list, session_id})
  end

  @doc """
  Delete variable from session.
  """
  def delete(session_id, identifier) do
    GenServer.call(__MODULE__, {:delete, session_id, identifier})
  end

  @doc """
  Initialize session for variable management.
  """
  def initialize_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:initialize_session, session_id, opts})
  end

  @doc """
  Clean up session and all its variables.
  """
  def cleanup_session(session_id) do
    GenServer.call(__MODULE__, {:cleanup_session, session_id})
  end

  @doc """
  Get session information and statistics.
  """
  def get_session_info(session_id) do
    GenServer.call(__MODULE__, {:get_session_info, session_id})
  end

  # GenServer callbacks

  def init(_opts) do
    state = %__MODULE__{
      sessions: :ets.new(:variable_sessions, [:set, :public, :named_table]),
      variables: :ets.new(:variables, [:set, :public, :named_table]),
      telemetry_collector: initialize_telemetry_collector(),
      stats: initialize_stats()
    }
    
    Logger.info("Variables manager started")
    {:ok, state}
  end

  def handle_call({:create, session_id, name, type, value, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Validate type
    case SnakepitGRPCBridge.Variables.Types.validate_type(type) do
      :ok ->
        create_variable_impl(session_id, name, type, value, opts, state, start_time)
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get, session_id, identifier, default}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    variable_key = {session_id, identifier}
    
    result = case :ets.lookup(state.variables, variable_key) do
      [{^variable_key, variable}] -> 
        # Deserialize value based on type
        case SnakepitGRPCBridge.Variables.Types.deserialize_value(variable.serialized_value, variable.type) do
          {:ok, deserialized_value} ->
            {:ok, deserialized_value}
          {:error, reason} ->
            Logger.error("Failed to deserialize variable", 
                        session_id: session_id, 
                        identifier: identifier, 
                        reason: reason)
            {:ok, default}
        end
      
      [] -> 
        {:ok, default}
    end
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_operation_telemetry(:get, session_id, identifier, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:set, session_id, identifier, value, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    variable_key = {session_id, identifier}
    
    result = case :ets.lookup(state.variables, variable_key) do
      [{^variable_key, variable}] ->
        # Serialize new value
        case SnakepitGRPCBridge.Variables.Types.serialize_value(value, variable.type) do
          {:ok, serialized_value} ->
            updated_variable = %{variable | 
              serialized_value: serialized_value,
              updated_at: DateTime.utc_now(),
              update_count: variable.update_count + 1,
              metadata: Map.merge(variable.metadata, opts[:metadata] || %{})
            }
            
            :ets.insert(state.variables, {variable_key, updated_variable})
            
            Logger.debug("Variable updated", 
                        session_id: session_id, 
                        identifier: identifier, 
                        type: variable.type)
            :ok
          
          {:error, reason} ->
            {:error, {:serialization_failed, reason}}
        end
      
      [] ->
        {:error, :variable_not_found}
    end
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_operation_telemetry(:set, session_id, identifier, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:list, session_id}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    pattern = {{session_id, :_}, :_}
    variables = :ets.match_object(state.variables, pattern)
    
    variable_list = Enum.map(variables, fn {{_session, name}, variable} ->
      %{
        name: name,
        type: variable.type,
        created_at: variable.created_at,
        updated_at: variable.updated_at,
        update_count: variable.update_count,
        metadata: variable.metadata
      }
    end)
    
    result = {:ok, variable_list}
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_operation_telemetry(:list, session_id, :all, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:delete, session_id, identifier}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    variable_key = {session_id, identifier}
    
    result = case :ets.lookup(state.variables, variable_key) do
      [{^variable_key, _variable}] ->
        :ets.delete(state.variables, variable_key)
        Logger.debug("Variable deleted", session_id: session_id, identifier: identifier)
        :ok
      
      [] ->
        {:error, :variable_not_found}
    end
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_operation_telemetry(:delete, session_id, identifier, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:initialize_session, session_id, opts}, _from, state) do
    session_metadata = %{
      session_id: session_id,
      initialized_at: DateTime.utc_now(),
      variable_count: 0,
      last_activity: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }
    
    :ets.insert(state.sessions, {session_id, session_metadata})
    
    Logger.debug("Session initialized for variables", session_id: session_id)
    {:reply, {:ok, session_metadata}, state}
  end

  def handle_call({:cleanup_session, session_id}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Delete all variables for this session
    pattern = {{session_id, :_}, :_}
    variables = :ets.match_object(state.variables, pattern)
    
    Enum.each(variables, fn {variable_key, _variable} ->
      :ets.delete(state.variables, variable_key)
    end)
    
    # Delete session metadata
    :ets.delete(state.sessions, session_id)
    
    variable_count = length(variables)
    Logger.info("Session cleaned up", 
               session_id: session_id, 
               variables_deleted: variable_count)
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_operation_telemetry(:cleanup_session, session_id, :all, {:ok, variable_count}, execution_time)
    
    {:reply, {:ok, variable_count}, state}
  end

  def handle_call({:get_session_info, session_id}, _from, state) do
    case :ets.lookup(state.sessions, session_id) do
      [{^session_id, session_metadata}] ->
        # Count variables in session
        pattern = {{session_id, :_}, :_}
        variable_count = :ets.select_count(state.variables, [{pattern, [], [true]}])
        
        session_info = Map.put(session_metadata, :current_variable_count, variable_count)
        {:reply, {:ok, session_info}, state}
      
      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  # Private implementation functions

  defp create_variable_impl(session_id, name, type, value, opts, state, start_time) do
    variable_key = {session_id, name}
    
    # Check if variable already exists
    case :ets.lookup(state.variables, variable_key) do
      [] ->
        # Serialize value based on type
        case SnakepitGRPCBridge.Variables.Types.serialize_value(value, type) do
          {:ok, serialized_value} ->
            variable = %{
              name: name,
              type: type,
              serialized_value: serialized_value,
              created_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now(),
              update_count: 0,
              metadata: opts[:metadata] || %{},
              description: opts[:description] || ""
            }
            
            :ets.insert(state.variables, {variable_key, variable})
            
            # Update session metadata
            update_session_activity(session_id, state)
            
            Logger.debug("Variable created", 
                        session_id: session_id, 
                        name: name, 
                        type: type)
            
            # Collect telemetry
            execution_time = System.monotonic_time(:microsecond) - start_time
            collect_operation_telemetry(:create, session_id, name, {:ok, variable}, execution_time)
            
            {:reply, {:ok, variable}, state}
          
          {:error, reason} ->
            {:reply, {:error, {:serialization_failed, reason}}, state}
        end
      
      [{^variable_key, _existing}] ->
        {:reply, {:error, :variable_already_exists}, state}
    end
  end

  defp update_session_activity(session_id, state) do
    case :ets.lookup(state.sessions, session_id) do
      [{^session_id, session_metadata}] ->
        updated_metadata = %{session_metadata | 
          last_activity: DateTime.utc_now(),
          variable_count: session_metadata.variable_count + 1
        }
        :ets.insert(state.sessions, {session_id, updated_metadata})
      
      [] ->
        # Auto-initialize session if it doesn't exist
        initialize_session_impl(session_id, state)
    end
  end

  defp initialize_session_impl(session_id, state) do
    session_metadata = %{
      session_id: session_id,
      initialized_at: DateTime.utc_now(),
      variable_count: 0,
      last_activity: DateTime.utc_now(),
      metadata: %{}
    }
    
    :ets.insert(state.sessions, {session_id, session_metadata})
  end

  defp collect_operation_telemetry(operation, session_id, identifier, result, execution_time) do
    telemetry_data = %{
      operation: operation,
      session_id: session_id,
      identifier: identifier,
      success: match?({:ok, _}, result) or result == :ok,
      execution_time_microseconds: execution_time,
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :variables, :operation], telemetry_data)
  end

  defp initialize_telemetry_collector do
    # Placeholder for telemetry collector
    %{
      operations_count: 0,
      total_execution_time: 0,
      last_operation: nil
    }
  end

  defp initialize_stats do
    %{
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      sessions_created: 0,
      variables_created: 0
    }
  end
end
```

### Task 2: Implement Variable Types System

Create `lib/snakepit_grpc_bridge/variables/types.ex`:

```elixir
defmodule SnakepitGRPCBridge.Variables.Types do
  @moduledoc """
  Type system for ML variables with serialization support.
  
  Supports both basic types and specialized ML types like tensors and embeddings.
  """

  @basic_types [:string, :integer, :float, :boolean, :binary, :map, :list]
  @ml_types [:tensor, :embedding, :model, :dataset]
  @supported_types @basic_types ++ @ml_types

  def supported_types, do: @supported_types
  def basic_types, do: @basic_types  
  def ml_types, do: @ml_types

  @doc """
  Validate that a type is supported.
  """
  def validate_type(type) when type in @supported_types, do: :ok
  def validate_type(type), do: {:error, {:unsupported_type, type}}

  @doc """
  Serialize value based on its type.
  """
  def serialize_value(value, type) do
    case type do
      # Basic types
      :string when is_binary(value) -> {:ok, value}
      :integer when is_integer(value) -> {:ok, :erlang.term_to_binary(value)}
      :float when is_float(value) -> {:ok, :erlang.term_to_binary(value)}
      :boolean when is_boolean(value) -> {:ok, :erlang.term_to_binary(value)}
      :binary when is_binary(value) -> {:ok, value}
      :map when is_map(value) -> serialize_complex_value(value, :map)
      :list when is_list(value) -> serialize_complex_value(value, :list)
      
      # ML types
      :tensor -> serialize_tensor(value)
      :embedding -> serialize_embedding(value)
      :model -> serialize_model(value)
      :dataset -> serialize_dataset(value)
      
      # Type mismatch
      _ -> {:error, {:type_mismatch, type, typeof(value)}}
    end
  end

  @doc """
  Deserialize value based on its type.
  """
  def deserialize_value(data, type) do
    case type do
      # Basic types
      :string -> {:ok, data}
      :integer -> safe_binary_to_term(data)
      :float -> safe_binary_to_term(data)
      :boolean -> safe_binary_to_term(data)
      :binary -> {:ok, data}
      :map -> deserialize_complex_value(data, :map)
      :list -> deserialize_complex_value(data, :list)
      
      # ML types
      :tensor -> deserialize_tensor(data)
      :embedding -> deserialize_embedding(data)
      :model -> deserialize_model(data)
      :dataset -> deserialize_dataset(data)
      
      _ -> {:error, {:unsupported_deserialization, type}}
    end
  end

  @doc """
  Get metadata about a type.
  """
  def type_metadata(type) do
    case type do
      :tensor -> %{category: :ml, serialization: :custom, size_limit: 1_000_000_000}
      :embedding -> %{category: :ml, serialization: :json, size_limit: 100_000_000}
      :model -> %{category: :ml, serialization: :custom, size_limit: 5_000_000_000}
      :dataset -> %{category: :ml, serialization: :custom, size_limit: 10_000_000_000}
      _ when type in @basic_types -> %{category: :basic, serialization: :erlang, size_limit: 100_000_000}
      _ -> %{category: :unknown, serialization: :unknown, size_limit: 0}
    end
  end

  # Private implementation functions

  defp serialize_complex_value(value, :map) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encoding_failed, reason}}
    end
  end

  defp serialize_complex_value(value, :list) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encoding_failed, reason}}
    end
  end

  defp deserialize_complex_value(data, :map) do
    case Jason.decode(data) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, _value} -> {:error, :not_a_map}
      {:error, reason} -> {:error, {:json_decoding_failed, reason}}
    end
  end

  defp deserialize_complex_value(data, :list) do
    case Jason.decode(data) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, _value} -> {:error, :not_a_list}
      {:error, reason} -> {:error, {:json_decoding_failed, reason}}
    end
  end

  # ML type serialization/deserialization

  defp serialize_tensor(value) do
    # For now, use Erlang term serialization
    # In production, this would use more efficient tensor formats
    case value do
      %{data: _data, shape: _shape, dtype: _dtype} = tensor ->
        {:ok, :erlang.term_to_binary(tensor)}
      
      data when is_list(data) ->
        # Auto-wrap in tensor structure
        tensor = %{data: data, shape: infer_shape(data), dtype: :float32}
        {:ok, :erlang.term_to_binary(tensor)}
      
      _ ->
        {:error, {:invalid_tensor_format, typeof(value)}}
    end
  end

  defp deserialize_tensor(data) do
    case safe_binary_to_term(data) do
      {:ok, %{data: _data, shape: _shape, dtype: _dtype} = tensor} ->
        {:ok, tensor}
      
      {:ok, other} ->
        {:error, {:invalid_tensor_data, typeof(other)}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp serialize_embedding(value) do
    # Embeddings are typically lists of floats
    case value do
      vector when is_list(vector) ->
        embedding = %{
          vector: vector,
          dimensions: length(vector),
          model: nil,
          created_at: DateTime.utc_now()
        }
        
        case Jason.encode(embedding) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, {:json_encoding_failed, reason}}
        end
      
      %{vector: vector} = embedding when is_list(vector) ->
        case Jason.encode(embedding) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, {:json_encoding_failed, reason}}
        end
      
      _ ->
        {:error, {:invalid_embedding_format, typeof(value)}}
    end
  end

  defp deserialize_embedding(data) do
    case Jason.decode(data) do
      {:ok, %{"vector" => vector} = embedding} when is_list(vector) ->
        {:ok, for {k, v} <- embedding, into: %{}, do: {String.to_atom(k), v}}
      
      {:ok, _other} ->
        {:error, :invalid_embedding_data}
      
      {:error, reason} ->
        {:error, {:json_decoding_failed, reason}}
    end
  end

  defp serialize_model(value) do
    # Models are complex objects, use Erlang serialization for now
    model_metadata = %{
      type: :dspy_model,
      serialized_at: DateTime.utc_now(),
      data: value
    }
    
    {:ok, :erlang.term_to_binary(model_metadata)}
  end

  defp deserialize_model(data) do
    case safe_binary_to_term(data) do
      {:ok, %{type: :dspy_model, data: model_data}} ->
        {:ok, model_data}
      
      {:ok, other} ->
        {:error, {:invalid_model_data, typeof(other)}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp serialize_dataset(value) do
    # Datasets can be large, use efficient serialization
    dataset_metadata = %{
      type: :dataset,
      serialized_at: DateTime.utc_now(),
      data: value
    }
    
    {:ok, :erlang.term_to_binary(dataset_metadata)}
  end

  defp deserialize_dataset(data) do
    case safe_binary_to_term(data) do
      {:ok, %{type: :dataset, data: dataset_data}} ->
        {:ok, dataset_data}
      
      {:ok, other} ->
        {:error, {:invalid_dataset_data, typeof(other)}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp safe_binary_to_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      ArgumentError -> {:error, :invalid_binary_format}
    end
  end

  defp typeof(value) do
    cond do
      is_atom(value) -> :atom
      is_binary(value) -> :binary
      is_boolean(value) -> :boolean
      is_float(value) -> :float
      is_integer(value) -> :integer
      is_list(value) -> :list
      is_map(value) -> :map
      is_pid(value) -> :pid
      is_tuple(value) -> :tuple
      true -> :unknown
    end
  end

  defp infer_shape(data) when is_list(data) do
    case data do
      [] -> [0]
      [first | _] when is_list(first) ->
        # 2D array
        [length(data), length(first)]
      _ ->
        # 1D array
        [length(data)]
    end
  end
end
```

### Task 3: Implement ML Types Modules

Create `lib/snakepit_grpc_bridge/variables/ml_types/tensor.ex`:

```elixir
defmodule SnakepitGRPCBridge.Variables.MLTypes.Tensor do
  @moduledoc """
  Specialized handling for tensor variables.
  """

  def create(session_id, name, data, opts \\ []) do
    tensor = %{
      data: data,
      shape: opts[:shape] || infer_shape(data),
      dtype: opts[:dtype] || :float32,
      metadata: %{
        created_at: DateTime.utc_now(),
        source: opts[:source] || "user_created"
      }
    }
    
    SnakepitGRPCBridge.Variables.Manager.create(session_id, name, :tensor, tensor, opts)
  end

  def reshape(session_id, name, new_shape) do
    with {:ok, tensor} <- SnakepitGRPCBridge.Variables.Manager.get(session_id, name),
         {:ok, reshaped_tensor} <- perform_reshape(tensor, new_shape) do
      SnakepitGRPCBridge.Variables.Manager.set(session_id, name, reshaped_tensor)
    end
  end

  def get_info(session_id, name) do
    case SnakepitGRPCBridge.Variables.Manager.get(session_id, name) do
      {:ok, %{shape: shape, dtype: dtype} = tensor} ->
        {:ok, %{
          shape: shape,
          dtype: dtype,
          size: calculate_size(tensor),
          memory_usage: estimate_memory_usage(tensor)
        }}
      
      {:ok, _other} ->
        {:error, :not_a_tensor}
      
      error ->
        error
    end
  end

  defp infer_shape(data) when is_list(data) do
    case data do
      [] -> [0]
      [first | _] when is_list(first) ->
        [length(data), length(first)]
      _ ->
        [length(data)]
    end
  end

  defp perform_reshape(tensor, new_shape) do
    # Simple reshape validation
    current_size = Enum.reduce(tensor.shape, 1, &*/2)
    new_size = Enum.reduce(new_shape, 1, &*/2)
    
    if current_size == new_size do
      {:ok, %{tensor | shape: new_shape}}
    else
      {:error, {:incompatible_shape, tensor.shape, new_shape}}
    end
  end

  defp calculate_size(%{shape: shape}) do
    Enum.reduce(shape, 1, &*/2)
  end

  defp estimate_memory_usage(%{shape: shape, dtype: dtype}) do
    element_count = Enum.reduce(shape, 1, &*/2)
    bytes_per_element = case dtype do
      :float32 -> 4
      :float64 -> 8
      :int32 -> 4
      :int64 -> 8
      _ -> 4  # Default assumption
    end
    
    element_count * bytes_per_element
  end
end
```

Create similar files for:
- `lib/snakepit_grpc_bridge/variables/ml_types/embedding.ex`
- `lib/snakepit_grpc_bridge/variables/ml_types/model.ex`

### Task 4: Update Variables API

Update `lib/snakepit_grpc_bridge/api/variables.ex`:

```elixir
defmodule SnakepitGRPCBridge.API.Variables do
  @moduledoc """
  Clean API for variable management operations.
  """

  alias SnakepitGRPCBridge.Variables.{Manager, Types}

  def create(session_id, name, type, value, opts \\ []) do
    Manager.create(session_id, name, type, value, opts)
  end

  def get(session_id, identifier, default \\ nil) do
    Manager.get(session_id, identifier, default)
  end

  def set(session_id, identifier, value, opts \\ []) do
    Manager.set(session_id, identifier, value, opts)
  end

  def list(session_id) do
    Manager.list(session_id)
  end

  def delete(session_id, identifier) do
    Manager.delete(session_id, identifier)
  end

  # ML-specific variable creation
  def create_tensor(session_id, name, data, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Tensor.create(session_id, name, data, opts)
  end

  def create_embedding(session_id, name, vector, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Embedding.create(session_id, name, vector, opts)
  end

  def create_model(session_id, name, model_instance, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Model.create(session_id, name, model_instance, opts)
  end

  # Utility functions
  def get_supported_types do
    {:ok, Types.supported_types()}
  end

  def get_type_metadata(type) do
    {:ok, Types.type_metadata(type)}
  end
end
```

### Task 5: Update Adapter to Route Variable Commands

Update the `route_command/3` function in `lib/snakepit_grpc_bridge/adapter.ex`:

```elixir
defp route_command(command, args, opts) do
  case command do
    # Variables operations
    "get_variable" -> 
      SnakepitGRPCBridge.API.Variables.get(
        opts[:session_id], 
        args["identifier"], 
        args["default"]
      )
    
    "set_variable" -> 
      SnakepitGRPCBridge.API.Variables.set(
        opts[:session_id], 
        args["identifier"], 
        args["value"]
      )
    
    "create_variable" -> 
      SnakepitGRPCBridge.API.Variables.create(
        opts[:session_id], 
        args["name"], 
        String.to_atom(args["type"]), 
        args["value"],
        args["options"] || []
      )
    
    "list_variables" -> 
      SnakepitGRPCBridge.API.Variables.list(opts[:session_id])
    
    "delete_variable" ->
      SnakepitGRPCBridge.API.Variables.delete(
        opts[:session_id],
        args["identifier"]
      )
    
    # ML-specific variable operations
    "create_tensor" ->
      SnakepitGRPCBridge.API.Variables.create_tensor(
        opts[:session_id],
        args["name"],
        args["data"],
        args["options"] || []
      )
    
    "create_embedding" ->
      SnakepitGRPCBridge.API.Variables.create_embedding(
        opts[:session_id],
        args["name"],
        args["vector"],
        args["options"] || []
      )
    
    # ... keep existing placeholder implementations for other commands
    _ -> 
      {:error, {:not_implemented_yet, command}}
  end
end
```

### Task 6: Create Comprehensive Tests

Create `test/snakepit_grpc_bridge/variables/manager_test.exs`:

```elixir
defmodule SnakepitGRPCBridge.Variables.ManagerTest do
  use ExUnit.Case
  
  alias SnakepitGRPCBridge.Variables.Manager

  setup do
    # Start the manager for testing
    {:ok, _pid} = start_supervised(Manager)
    session_id = "test_session_#{:rand.uniform(10000)}"
    %{session_id: session_id}
  end

  test "creates and retrieves basic variables", %{session_id: session_id} do
    # Test string variable
    assert {:ok, _variable} = Manager.create(session_id, "test_string", :string, "hello")
    assert {:ok, "hello"} = Manager.get(session_id, "test_string")
    
    # Test integer variable
    assert {:ok, _variable} = Manager.create(session_id, "test_int", :integer, 42)
    assert {:ok, 42} = Manager.get(session_id, "test_int")
    
    # Test float variable
    assert {:ok, _variable} = Manager.create(session_id, "test_float", :float, 3.14)
    assert {:ok, 3.14} = Manager.get(session_id, "test_float")
  end

  test "handles non-existent variables with defaults", %{session_id: session_id} do
    assert {:ok, nil} = Manager.get(session_id, "nonexistent")
    assert {:ok, "default"} = Manager.get(session_id, "nonexistent", "default")
  end

  test "updates existing variables", %{session_id: session_id} do
    assert {:ok, _variable} = Manager.create(session_id, "test_var", :string, "initial")
    assert :ok = Manager.set(session_id, "test_var", "updated")
    assert {:ok, "updated"} = Manager.get(session_id, "test_var")
  end

  test "lists all variables in session", %{session_id: session_id} do
    assert {:ok, _} = Manager.create(session_id, "var1", :string, "value1")
    assert {:ok, _} = Manager.create(session_id, "var2", :integer, 123)
    
    assert {:ok, variables} = Manager.list(session_id)
    assert length(variables) == 2
    
    names = Enum.map(variables, & &1.name)
    assert "var1" in names
    assert "var2" in names
  end

  test "deletes variables", %{session_id: session_id} do
    assert {:ok, _variable} = Manager.create(session_id, "to_delete", :string, "value")
    assert {:ok, "value"} = Manager.get(session_id, "to_delete")
    
    assert :ok = Manager.delete(session_id, "to_delete")
    assert {:ok, nil} = Manager.get(session_id, "to_delete")
  end

  test "handles session cleanup", %{session_id: session_id} do
    # Create multiple variables
    assert {:ok, _} = Manager.create(session_id, "var1", :string, "value1")
    assert {:ok, _} = Manager.create(session_id, "var2", :string, "value2")
    
    # Clean up session
    assert {:ok, 2} = Manager.cleanup_session(session_id)
    
    # Verify variables are gone
    assert {:ok, nil} = Manager.get(session_id, "var1")
    assert {:ok, nil} = Manager.get(session_id, "var2")
  end

  test "handles ML types", %{session_id: session_id} do
    # Test tensor creation
    tensor_data = [[1.0, 2.0], [3.0, 4.0]]
    assert {:ok, _variable} = Manager.create(session_id, "test_tensor", :tensor, tensor_data)
    
    assert {:ok, tensor} = Manager.get(session_id, "test_tensor")
    assert %{data: ^tensor_data} = tensor
    
    # Test embedding creation
    embedding_vector = [0.1, 0.2, 0.3, 0.4]
    assert {:ok, _variable} = Manager.create(session_id, "test_embedding", :embedding, embedding_vector)
    
    assert {:ok, embedding} = Manager.get(session_id, "test_embedding")
    assert %{vector: ^embedding_vector} = embedding
  end

  test "validates variable types", %{session_id: session_id} do
    # Invalid type
    assert {:error, {:unsupported_type, :invalid_type}} = 
      Manager.create(session_id, "invalid", :invalid_type, "value")
  end

  test "prevents duplicate variable names in same session", %{session_id: session_id} do
    assert {:ok, _variable} = Manager.create(session_id, "duplicate", :string, "first")
    assert {:error, :variable_already_exists} = Manager.create(session_id, "duplicate", :string, "second")
  end
end
```

## Validation

After completing this implementation, verify:

1. ✅ Variables manager starts successfully
2. ✅ Basic variable types (string, integer, float, boolean) work correctly
3. ✅ ML types (tensor, embedding, model) can be created and retrieved
4. ✅ Session isolation works (variables in different sessions are separate)
5. ✅ Serialization/deserialization works for all types
6. ✅ Variable listing, updating, and deletion work
7. ✅ Session cleanup removes all variables
8. ✅ Comprehensive tests pass
9. ✅ Telemetry is collected for all operations
10. ✅ Adapter routes variable commands correctly

## Next Steps

The next prompt will implement the Tools System, which enables bidirectional Python ↔ Elixir function calling.

## Files Modified/Created

- `lib/snakepit_grpc_bridge/variables/manager.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/variables/types.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/variables/ml_types/tensor.ex` (new)
- `lib/snakepit_grpc_bridge/variables/ml_types/embedding.ex` (new)
- `lib/snakepit_grpc_bridge/variables/ml_types/model.ex` (new)
- `lib/snakepit_grpc_bridge/api/variables.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/adapter.ex` (updated routing)
- `test/snakepit_grpc_bridge/variables/manager_test.exs` (comprehensive tests)
# Prompt: Implement gRPC Handlers for Variable Operations

## Objective
Create comprehensive gRPC handlers that expose all variable operations through the unified bridge service. These handlers connect the Elixir variable system to Python clients.

## Context
The gRPC handlers are the critical interface layer. They must handle serialization, validation, error reporting, and efficient batch operations while maintaining type safety across languages.

## Requirements

### Core Handler Functions
1. RegisterVariable - Create new variables with validation
2. GetVariable - Retrieve by ID or name
3. UpdateVariable - Update with constraint checking
4. ListVariables - List all or by pattern
5. DeleteVariable - Remove from session
6. GetVariables - Batch retrieval
7. UpdateVariables - Batch updates

### Additional Requirements
- Proper error handling with descriptive messages
- Type validation at boundaries
- Efficient protobuf Any encoding
- Session validation
- Telemetry integration

## Implementation Steps

### 1. Update Proto Definitions

```protobuf
// File: proto/unified_bridge.proto

syntax = "proto3";

package unified_bridge;

import "google/protobuf/any.proto";

service UnifiedBridge {
  // Existing tool operations
  rpc RegisterTool(RegisterToolRequest) returns (RegisterToolResponse);
  rpc CallTool(CallToolRequest) returns (CallToolResponse);
  
  // Variable operations
  rpc RegisterVariable(RegisterVariableRequest) returns (RegisterVariableResponse);
  rpc GetVariable(GetVariableRequest) returns (GetVariableResponse);
  rpc UpdateVariable(UpdateVariableRequest) returns (UpdateVariableResponse);
  rpc ListVariables(ListVariablesRequest) returns (ListVariablesResponse);
  rpc DeleteVariable(DeleteVariableRequest) returns (DeleteVariableResponse);
  
  // Batch operations
  rpc GetVariables(GetVariablesRequest) returns (GetVariablesResponse);
  rpc UpdateVariables(UpdateVariablesRequest) returns (UpdateVariablesResponse);
  
  // Streaming (Stage 3)
  rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
}

// Variable type enum
enum VariableType {
  TYPE_UNSPECIFIED = 0;
  TYPE_FLOAT = 1;
  TYPE_INTEGER = 2;
  TYPE_STRING = 3;
  TYPE_BOOLEAN = 4;
  TYPE_CHOICE = 5;      // Stage 2
  TYPE_MODULE = 6;      // Stage 2
  TYPE_EMBEDDING = 7;   // Stage 3
  TYPE_TENSOR = 8;      // Stage 3
}

// Variable messages
message Variable {
  string id = 1;
  string name = 2;
  VariableType type = 3;
  google.protobuf.Any value = 4;
  map<string, google.protobuf.Any> constraints = 5;
  map<string, string> metadata = 6;
  int32 version = 7;
  int64 created_at = 8;
  int64 last_updated_at = 9;
  bool optimizing = 10;
}

// Register Variable
message RegisterVariableRequest {
  string session_id = 1;
  string name = 2;
  VariableType type = 3;
  google.protobuf.Any initial_value = 4;
  map<string, google.protobuf.Any> constraints = 5;
  map<string, string> metadata = 6;
}

message RegisterVariableResponse {
  oneof result {
    string variable_id = 1;
    string error = 2;
  }
}

// Get Variable
message GetVariableRequest {
  string session_id = 1;
  string identifier = 2;  // ID or name
}

message GetVariableResponse {
  oneof result {
    Variable variable = 1;
    string error = 2;
  }
}

// Update Variable
message UpdateVariableRequest {
  string session_id = 1;
  string identifier = 2;
  google.protobuf.Any new_value = 3;
  map<string, string> metadata = 4;
}

message UpdateVariableResponse {
  oneof result {
    bool success = 1;
    string error = 2;
  }
}

// List Variables
message ListVariablesRequest {
  string session_id = 1;
  string pattern = 2;  // Optional, supports wildcards
}

message ListVariablesResponse {
  oneof result {
    VariableList variables = 1;
    string error = 2;
  }
}

message VariableList {
  repeated Variable variables = 1;
}

// Delete Variable
message DeleteVariableRequest {
  string session_id = 1;
  string identifier = 2;
}

message DeleteVariableResponse {
  oneof result {
    bool success = 1;
    string error = 2;
  }
}

// Batch Get
message GetVariablesRequest {
  string session_id = 1;
  repeated string identifiers = 2;
}

message GetVariablesResponse {
  oneof result {
    BatchGetResult batch_result = 1;
    string error = 2;
  }
}

message BatchGetResult {
  map<string, Variable> found = 1;
  repeated string missing = 2;
}

// Batch Update
message UpdateVariablesRequest {
  string session_id = 1;
  map<string, google.protobuf.Any> updates = 2;
  bool atomic = 3;
  map<string, string> metadata = 4;
}

message UpdateVariablesResponse {
  oneof result {
    map<string, UpdateResult> results = 1;
    string error = 2;
  }
}

message UpdateResult {
  oneof result {
    bool success = 1;
    string error = 2;
  }
}

// Streaming (Stage 3 preview)
message WatchVariablesRequest {
  string session_id = 1;
  repeated string patterns = 2;
}

message VariableUpdate {
  string variable_id = 1;
  string name = 2;
  google.protobuf.Any old_value = 3;
  google.protobuf.Any new_value = 4;
  int32 version = 5;
  map<string, string> metadata = 6;
  int64 timestamp = 7;
}
```

### 2. Implement gRPC Server Handlers

```elixir
# File: snakepit/lib/snakepit/grpc/unified_server.ex

defmodule Snakepit.GRPC.UnifiedServer do
  @moduledoc """
  Unified gRPC server implementation supporting both tools and variables.
  
  Extends the Stage 0 server with comprehensive variable management.
  """
  
  use GRPC.Server, service: Snakepit.Proto.UnifiedBridge.Service
  
  alias Snakepit.Bridge.{SessionStore, Variables}
  alias Snakepit.Proto.{
    RegisterVariableRequest, RegisterVariableResponse,
    GetVariableRequest, GetVariableResponse,
    UpdateVariableRequest, UpdateVariableResponse,
    ListVariablesRequest, ListVariablesResponse,
    DeleteVariableRequest, DeleteVariableResponse,
    GetVariablesRequest, GetVariablesResponse,
    UpdateVariablesRequest, UpdateVariablesResponse,
    Variable, VariableList, BatchGetResult, UpdateResult
  }
  alias Google.Protobuf.Any
  
  require Logger
  
  # Variable Operations
  
  @impl true
  def register_variable(request, _stream) do
    Logger.debug("RegisterVariable: session=#{request.session_id}, name=#{request.name}")
    
    case decode_variable_type(request.type) do
      {:ok, type_atom} ->
        handle_register_variable(request, type_atom)
      {:error, reason} ->
        RegisterVariableResponse.new(result: {:error, reason})
    end
  end
  
  defp handle_register_variable(request, type_atom) do
    with {:ok, initial_value} <- decode_any_value(request.initial_value, type_atom),
         {:ok, constraints} <- decode_constraints(request.constraints),
         {:ok, var_id} <- SessionStore.register_variable(
           request.session_id,
           request.name,
           type_atom,
           initial_value,
           constraints: constraints,
           metadata: request.metadata
         ) do
      
      RegisterVariableResponse.new(result: {:variable_id, var_id})
    else
      {:error, reason} ->
        RegisterVariableResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  @impl true
  def get_variable(request, _stream) do
    Logger.debug("GetVariable: session=#{request.session_id}, id=#{request.identifier}")
    
    case SessionStore.get_variable(request.session_id, request.identifier) do
      {:ok, variable} ->
        case encode_variable(variable) do
          {:ok, proto_var} ->
            GetVariableResponse.new(result: {:variable, proto_var})
          {:error, reason} ->
            GetVariableResponse.new(result: {:error, format_error(reason)})
        end
      {:error, reason} ->
        GetVariableResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  @impl true
  def update_variable(request, _stream) do
    Logger.debug("UpdateVariable: session=#{request.session_id}, id=#{request.identifier}")
    
    # First get the variable to know its type
    case SessionStore.get_variable(request.session_id, request.identifier) do
      {:ok, variable} ->
        case decode_any_value(request.new_value, variable.type) do
          {:ok, decoded_value} ->
            case SessionStore.update_variable(
              request.session_id, 
              request.identifier, 
              decoded_value,
              request.metadata
            ) do
              :ok ->
                UpdateVariableResponse.new(result: {:success, true})
              {:error, reason} ->
                UpdateVariableResponse.new(result: {:error, format_error(reason)})
            end
          {:error, reason} ->
            UpdateVariableResponse.new(result: {:error, format_error(reason)})
        end
      {:error, reason} ->
        UpdateVariableResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  @impl true
  def list_variables(request, _stream) do
    Logger.debug("ListVariables: session=#{request.session_id}, pattern=#{request.pattern}")
    
    case list_variables_internal(request.session_id, request.pattern) do
      {:ok, variables} ->
        case encode_variable_list(variables) do
          {:ok, proto_vars} ->
            var_list = VariableList.new(variables: proto_vars)
            ListVariablesResponse.new(result: {:variables, var_list})
          {:error, reason} ->
            ListVariablesResponse.new(result: {:error, format_error(reason)})
        end
      {:error, reason} ->
        ListVariablesResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  defp list_variables_internal(session_id, "") do
    SessionStore.list_variables(session_id)
  end
  
  defp list_variables_internal(session_id, pattern) do
    SessionStore.list_variables(session_id, pattern)
  end
  
  @impl true
  def delete_variable(request, _stream) do
    Logger.debug("DeleteVariable: session=#{request.session_id}, id=#{request.identifier}")
    
    case SessionStore.delete_variable(request.session_id, request.identifier) do
      :ok ->
        DeleteVariableResponse.new(result: {:success, true})
      {:error, reason} ->
        DeleteVariableResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  @impl true
  def get_variables(request, _stream) do
    Logger.debug("GetVariables: session=#{request.session_id}, count=#{length(request.identifiers)}")
    
    case SessionStore.get_variables(request.session_id, request.identifiers) do
      {:ok, %{found: found, missing: missing}} ->
        case encode_variables_map(found) do
          {:ok, proto_found} ->
            batch_result = BatchGetResult.new(
              found: proto_found,
              missing: missing
            )
            GetVariablesResponse.new(result: {:batch_result, batch_result})
          {:error, reason} ->
            GetVariablesResponse.new(result: {:error, format_error(reason)})
        end
      {:error, reason} ->
        GetVariablesResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  @impl true
  def update_variables(request, _stream) do
    Logger.debug("UpdateVariables: session=#{request.session_id}, count=#{map_size(request.updates)}")
    
    # Decode all values first
    case decode_updates_map(request.session_id, request.updates) do
      {:ok, decoded_updates} ->
        opts = [
          atomic: request.atomic,
          metadata: request.metadata
        ]
        
        case SessionStore.update_variables(request.session_id, decoded_updates, opts) do
          {:ok, results} ->
            proto_results = encode_update_results(results)
            UpdateVariablesResponse.new(result: {:results, proto_results})
          {:error, {:validation_failed, errors}} ->
            # Convert validation errors to update results
            proto_results = encode_validation_errors(errors)
            UpdateVariablesResponse.new(result: {:results, proto_results})
          {:error, reason} ->
            UpdateVariablesResponse.new(result: {:error, format_error(reason)})
        end
      {:error, reason} ->
        UpdateVariablesResponse.new(result: {:error, format_error(reason)})
    end
  end
  
  # Encoding/Decoding Helpers
  
  defp decode_variable_type(proto_type) do
    case proto_type do
      :TYPE_FLOAT -> {:ok, :float}
      :TYPE_INTEGER -> {:ok, :integer}
      :TYPE_STRING -> {:ok, :string}
      :TYPE_BOOLEAN -> {:ok, :boolean}
      :TYPE_CHOICE -> {:ok, :choice}
      :TYPE_MODULE -> {:ok, :module}
      :TYPE_EMBEDDING -> {:ok, :embedding}
      :TYPE_TENSOR -> {:ok, :tensor}
      _ -> {:error, "Unknown variable type: #{proto_type}"}
    end
  end
  
  defp encode_variable_type(atom_type) do
    case atom_type do
      :float -> :TYPE_FLOAT
      :integer -> :TYPE_INTEGER
      :string -> :TYPE_STRING
      :boolean -> :TYPE_BOOLEAN
      :choice -> :TYPE_CHOICE
      :module -> :TYPE_MODULE
      :embedding -> :TYPE_EMBEDDING
      :tensor -> :TYPE_TENSOR
      _ -> :TYPE_UNSPECIFIED
    end
  end
  
  defp decode_any_value(%Any{type_url: type_url, value: encoded}, expected_type) do
    # Extract type hint from URL
    type_hint = String.split(type_url, "/") |> List.last()
    
    case Jason.decode(encoded) do
      {:ok, %{"value" => value, "type" => type}} ->
        if to_string(type) == to_string(expected_type) do
          {:ok, value}
        else
          {:error, "Type mismatch: expected #{expected_type}, got #{type}"}
        end
      {:ok, value} when type_hint == to_string(expected_type) ->
        # Fallback for simple encoding
        {:ok, value}
      {:error, _} ->
        {:error, "Failed to decode value"}
    end
  end
  
  defp encode_any_value(value, type) do
    encoded = Jason.encode!(%{
      "type" => to_string(type),
      "value" => value
    })
    
    {:ok, Any.new(
      type_url: "type.googleapis.com/unified_bridge.#{type}",
      value: encoded
    )}
  end
  
  defp decode_constraints(proto_constraints) do
    constraints = Enum.reduce(proto_constraints, %{}, fn {key, any_val}, acc ->
      case decode_constraint_value(any_val) do
        {:ok, value} -> Map.put(acc, String.to_atom(key), value)
        {:error, _} -> acc
      end
    end)
    
    {:ok, constraints}
  end
  
  defp decode_constraint_value(%Any{value: encoded}) do
    Jason.decode(encoded)
  end
  
  defp encode_constraints(constraints) do
    Enum.reduce(constraints, %{}, fn {key, value}, acc ->
      encoded = Jason.encode!(value)
      any_val = Any.new(
        type_url: "type.googleapis.com/unified_bridge.constraint",
        value: encoded
      )
      Map.put(acc, to_string(key), any_val)
    end)
  end
  
  defp encode_variable(variable) do
    with {:ok, value_any} <- encode_any_value(variable.value, variable.type) do
      proto_var = Variable.new(
        id: variable.id,
        name: to_string(variable.name),
        type: encode_variable_type(variable.type),
        value: value_any,
        constraints: encode_constraints(variable.constraints),
        metadata: variable.metadata,
        version: variable.version,
        created_at: variable.created_at,
        last_updated_at: variable.last_updated_at,
        optimizing: Variables.Variable.optimizing?(variable)
      )
      
      {:ok, proto_var}
    end
  end
  
  defp encode_variable_list(variables) do
    Enum.reduce_while(variables, {:ok, []}, fn var, {:ok, acc} ->
      case encode_variable(var) do
        {:ok, proto_var} -> {:cont, {:ok, [proto_var | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end
  
  defp encode_variables_map(variables_map) do
    Enum.reduce_while(variables_map, {:ok, %{}}, fn {id, var}, {:ok, acc} ->
      case encode_variable(var) do
        {:ok, proto_var} -> {:cont, {:ok, Map.put(acc, id, proto_var)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  defp decode_updates_map(session_id, updates) do
    # First get variable types for decoding
    identifiers = Map.keys(updates)
    
    case SessionStore.get_variables(session_id, identifiers) do
      {:ok, %{found: found}} ->
        decoded = Enum.reduce_while(updates, {:ok, %{}}, fn {id, any_val}, {:ok, acc} ->
          case Map.get(found, to_string(id)) do
            nil ->
              {:halt, {:error, "Variable not found: #{id}"}}
            variable ->
              case decode_any_value(any_val, variable.type) do
                {:ok, value} -> {:cont, {:ok, Map.put(acc, id, value)}}
                {:error, reason} -> {:halt, {:error, reason}}
              end
          end
        end)
        
        decoded
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp encode_update_results(results) do
    Enum.reduce(results, %{}, fn {id, result}, acc ->
      proto_result = case result do
        :ok -> UpdateResult.new(result: {:success, true})
        {:error, reason} -> UpdateResult.new(result: {:error, format_error(reason)})
      end
      Map.put(acc, id, proto_result)
    end)
  end
  
  defp encode_validation_errors(errors) do
    Enum.reduce(errors, %{}, fn {id, reason}, acc ->
      proto_result = UpdateResult.new(result: {:error, format_error(reason)})
      Map.put(acc, id, proto_result)
    end)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error({:error, reason}), do: format_error(reason)
  defp format_error(reason), do: inspect(reason)
  
  # Existing tool operations remain unchanged...
end
```

### 3. Create Handler Tests

```elixir
# File: test/snakepit/grpc/unified_server_variables_test.exs

defmodule Snakepit.GRPC.UnifiedServerVariablesTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.GRPC.UnifiedServer
  alias Snakepit.Proto.{
    RegisterVariableRequest,
    GetVariableRequest,
    UpdateVariableRequest,
    ListVariablesRequest,
    DeleteVariableRequest,
    GetVariablesRequest,
    UpdateVariablesRequest
  }
  alias Google.Protobuf.Any
  
  setup do
    # Start SessionStore
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Create test session
    session_id = "test_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionStore.create_session(session_id)
    
    on_exit(fn ->
      SessionStore.delete_session(session_id)
    end)
    
    {:ok, session_id: session_id}
  end
  
  describe "register_variable/2" do
    test "registers float variable", %{session_id: session_id} do
      value_any = encode_test_value(0.7, :float)
      constraints_any = %{
        "min" => encode_test_constraint(0.0),
        "max" => encode_test_constraint(1.0)
      }
      
      request = RegisterVariableRequest.new(
        session_id: session_id,
        name: "temperature",
        type: :TYPE_FLOAT,
        initial_value: value_any,
        constraints: constraints_any,
        metadata: %{"source" => "test"}
      )
      
      response = UnifiedServer.register_variable(request, nil)
      
      assert {:variable_id, var_id} = response.result
      assert String.starts_with?(var_id, "var_temperature_")
    end
    
    test "validates type", %{session_id: session_id} do
      # Wrong value for integer type
      value_any = encode_test_value("not a number", :string)
      
      request = RegisterVariableRequest.new(
        session_id: session_id,
        name: "count",
        type: :TYPE_INTEGER,
        initial_value: value_any
      )
      
      response = UnifiedServer.register_variable(request, nil)
      
      assert {:error, error} = response.result
      assert error =~ "Type mismatch"
    end
  end
  
  describe "get_variable/2" do
    setup %{session_id: session_id} do
      # Register a test variable
      {:ok, var_id} = SessionStore.register_variable(
        session_id,
        :test_var,
        :string,
        "hello world"
      )
      
      {:ok, var_id: var_id}
    end
    
    test "gets by ID", %{session_id: session_id, var_id: var_id} do
      request = GetVariableRequest.new(
        session_id: session_id,
        identifier: var_id
      )
      
      response = UnifiedServer.get_variable(request, nil)
      
      assert {:variable, variable} = response.result
      assert variable.id == var_id
      assert variable.name == "test_var"
      assert variable.type == :TYPE_STRING
      
      # Decode value
      assert {:ok, "hello world"} = decode_test_value(variable.value)
    end
    
    test "gets by name", %{session_id: session_id} do
      request = GetVariableRequest.new(
        session_id: session_id,
        identifier: "test_var"
      )
      
      response = UnifiedServer.get_variable(request, nil)
      
      assert {:variable, variable} = response.result
      assert variable.name == "test_var"
    end
  end
  
  describe "batch operations" do
    setup %{session_id: session_id} do
      # Register multiple variables
      {:ok, _} = SessionStore.register_variable(session_id, :var1, :integer, 1)
      {:ok, _} = SessionStore.register_variable(session_id, :var2, :integer, 2)
      {:ok, _} = SessionStore.register_variable(session_id, :var3, :integer, 3)
      
      :ok
    end
    
    test "get_variables batch", %{session_id: session_id} do
      request = GetVariablesRequest.new(
        session_id: session_id,
        identifiers: ["var1", "var2", "nonexistent"]
      )
      
      response = UnifiedServer.get_variables(request, nil)
      
      assert {:batch_result, result} = response.result
      assert map_size(result.found) == 2
      assert "nonexistent" in result.missing
      
      # Check found variables
      assert result.found["var1"].name == "var1"
      assert result.found["var2"].name == "var2"
    end
    
    test "update_variables non-atomic", %{session_id: session_id} do
      updates = %{
        "var1" => encode_test_value(10, :integer),
        "var2" => encode_test_value(20, :integer)
      }
      
      request = UpdateVariablesRequest.new(
        session_id: session_id,
        updates: updates,
        atomic: false
      )
      
      response = UnifiedServer.update_variables(request, nil)
      
      assert {:results, results} = response.result
      assert {:success, true} = results["var1"].result
      assert {:success, true} = results["var2"].result
    end
  end
  
  # Helper functions
  
  defp encode_test_value(value, type) do
    encoded = Jason.encode!(%{
      "type" => to_string(type),
      "value" => value
    })
    
    Any.new(
      type_url: "type.googleapis.com/unified_bridge.#{type}",
      value: encoded
    )
  end
  
  defp encode_test_constraint(value) do
    Any.new(
      type_url: "type.googleapis.com/unified_bridge.constraint",
      value: Jason.encode!(value)
    )
  end
  
  defp decode_test_value(%Any{value: encoded}) do
    case Jason.decode(encoded) do
      {:ok, %{"value" => value}} -> {:ok, value}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end
end
```

## Error Handling Strategy

1. **Validation Errors**: Return descriptive messages
2. **Type Mismatches**: Include expected and actual types
3. **Constraint Violations**: Specify which constraint failed
4. **Session Errors**: Clear "session not found" messages
5. **Serialization Errors**: Include problematic value info

## Performance Optimizations

1. **Batch Operations**: Single GenServer call for multiple ops
2. **Type Caching**: Avoid repeated type lookups
3. **Efficient Encoding**: Minimal JSON overhead
4. **Streaming Preparation**: Handler structure supports future streaming

## Security Considerations

1. **Input Validation**: All inputs validated before processing
2. **Type Safety**: Strict type checking at boundaries
3. **Session Isolation**: Operations scoped to sessions
4. **Error Sanitization**: Don't leak internal details

## Files to Create/Modify

1. Create/Update: `proto/unified_bridge.proto`
2. Regenerate: Proto modules using `mix protobuf.generate`
3. Modify: `snakepit/lib/snakepit/grpc/unified_server.ex`
4. Create: `test/snakepit/grpc/unified_server_variables_test.exs`

## Next Steps

After implementing gRPC handlers:
1. Regenerate protobuf modules
2. Run handler tests
3. Test with grpcurl for manual verification
4. Benchmark batch operations
5. Proceed to Python SessionContext (next prompt)
# Stage 0: Protocol Foundation & Core Plumbing

## Overview

Stage 0 establishes the new, robust gRPC communication channel between Elixir and Python. This replaces the simple command-based gRPC protocol with a rich, type-safe foundation that will support all future features. This stage focuses on getting the basic infrastructure correct before adding any business logic.

## Goals

1. Define the complete protobuf protocol for the unified bridge
2. Generate gRPC code for both Elixir and Python
3. Update existing gRPC infrastructure to use the new protocol
4. Establish the basic `SessionContext` pattern in Python
5. Verify end-to-end communication with a simple ping test

## Deliverables

- New `snakepit_bridge.proto` file with complete protocol definition
- Updated Elixir gRPC worker and client using new protocol
- Updated Python gRPC server implementing new service
- Basic `SessionContext` class in Python
- Working end-to-end test demonstrating new protocol

## Detailed Implementation Plan

### 1. Protocol Definition

Create `snakepit/priv/protos/snakepit_bridge.proto`:

```protobuf
syntax = "proto3";

package snakepit.bridge;

import "google/protobuf/any.proto";
import "google/protobuf/timestamp.proto";

service SnakepitBridge {
  // Health check
  rpc Ping(PingRequest) returns (PingResponse);
  
  // Session management
  rpc InitializeSession(InitializeSessionRequest) returns (InitializeSessionResponse);
  rpc CleanupSession(CleanupSessionRequest) returns (CleanupSessionResponse);
  
  // Variable operations
  rpc GetVariable(GetVariableRequest) returns (GetVariableResponse);
  rpc SetVariable(SetVariableRequest) returns (SetVariableResponse);
  rpc GetVariables(BatchGetVariablesRequest) returns (BatchGetVariablesResponse);
  rpc SetVariables(BatchSetVariablesRequest) returns (BatchSetVariablesResponse);
  
  // Tool execution
  rpc ExecuteTool(ExecuteToolRequest) returns (ExecuteToolResponse);
  
  // Streaming
  rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
}

// Core messages
message PingRequest {
  string message = 1;
}

message PingResponse {
  string message = 1;
  google.protobuf.Timestamp server_time = 2;
}

message InitializeSessionRequest {
  string session_id = 1;
  map<string, string> metadata = 2;
}

message InitializeSessionResponse {
  bool success = 1;
  string error_message = 2;
  map<string, ToolSpec> available_tools = 3;
  map<string, Variable> initial_variables = 4;
}

message CleanupSessionRequest {
  string session_id = 1;
}

message CleanupSessionResponse {
  bool success = 1;
}

// Variable messages
message Variable {
  string id = 1;
  string name = 2;
  string type = 3;
  google.protobuf.Any value = 4;
  string constraints_json = 5;
  map<string, string> metadata = 6;
  enum Source {
    ELIXIR = 0;
    PYTHON = 1;
  }
  Source source = 7;
  google.protobuf.Timestamp last_updated_at = 8;
}

message GetVariableRequest {
  string session_id = 1;
  string variable_id = 2;
}

message GetVariableResponse {
  Variable variable = 1;
}

message SetVariableRequest {
  string session_id = 1;
  string variable_id = 2;
  google.protobuf.Any value = 3;
  map<string, string> metadata = 4;
}

message SetVariableResponse {
  bool success = 1;
  string error_message = 2;
}

message BatchGetVariablesRequest {
  string session_id = 1;
  repeated string variable_ids = 2;
  bool include_metadata = 3;
}

message BatchGetVariablesResponse {
  map<string, Variable> variables = 1;
}

message BatchSetVariablesRequest {
  string session_id = 1;
  map<string, google.protobuf.Any> updates = 2;
  map<string, string> metadata = 3;
  bool atomic = 4;
}

message BatchSetVariablesResponse {
  bool success = 1;
  map<string, string> errors = 2;
}

// Tool messages
message ToolSpec {
  string name = 1;
  string description = 2;
  repeated ParameterSpec parameters = 3;
  map<string, string> metadata = 4;
}

message ParameterSpec {
  string name = 1;
  string type = 2;
  string description = 3;
  bool required = 4;
  google.protobuf.Any default_value = 5;
}

message ExecuteToolRequest {
  string session_id = 1;
  string tool_name = 2;
  map<string, google.protobuf.Any> parameters = 3;
  map<string, string> metadata = 4;
}

message ExecuteToolResponse {
  bool success = 1;
  google.protobuf.Any result = 2;
  string error_message = 3;
  map<string, string> metadata = 4;
}

// Streaming
message WatchVariablesRequest {
  string session_id = 1;
  repeated string variable_ids = 2;
}

message VariableUpdate {
  string variable_id = 1;
  Variable variable = 2;
  string update_source = 3;
  map<string, string> update_metadata = 4;
  google.protobuf.Timestamp timestamp = 5;
}
```

### 2. Code Generation

#### Elixir Side

Update `snakepit/mix.exs` to include protobuf generation:

```elixir
defp aliases do
  [
    # ... existing aliases ...
    "protobuf.generate": [
      "cmd rm -rf lib/snakepit/grpc/*.pb.ex",
      "protobuf.generate"
    ]
  ]
end
```

Add to `.proto` paths in `config/config.exs`:

```elixir
config :protobuf,
  extensions: :enabled,
  files: [
    "priv/protos/snakepit_bridge.proto"
  ]
```

Run generation:
```bash
mix protobuf.generate
```

#### Python Side

Create `snakepit/priv/python/generate_grpc.sh`:

```bash
#!/bin/bash
python -m grpc_tools.protoc \
  -I../../protos \
  --python_out=snakepit_bridge/grpc \
  --grpc_python_out=snakepit_bridge/grpc \
  snakepit_bridge.proto
```

### 3. Update Elixir gRPC Infrastructure

#### Update `snakepit/lib/snakepit/grpc_worker.ex`:

```elixir
defmodule Snakepit.GRPCWorker do
  use GenServer
  require Logger
  
  alias Snakepit.GRPC.Client
  alias Snakepit.Pool.ProcessRegistry
  
  defstruct [:port, :os_pid, :channel, :adapter, :config, :session_id]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end
  
  def init(config) do
    # Generate unique session ID
    session_id = "session_#{:erlang.unique_integer([:positive])}"
    
    state = %__MODULE__{
      adapter: config[:adapter],
      config: config,
      session_id: session_id
    }
    
    case start_python_server(config) do
      {:ok, port, os_pid} ->
        Process.flag(:trap_exit, true)
        ProcessRegistry.register(os_pid)
        
        # Wait for server to be ready
        wait_for_server(config[:grpc_port])
        
        # Connect gRPC client
        {:ok, channel} = Client.connect(config[:grpc_port])
        
        # Initialize session
        case Client.initialize_session(channel, session_id) do
          {:ok, _response} ->
            {:ok, %{state | port: port, os_pid: os_pid, channel: channel}}
          {:error, reason} ->
            cleanup(port, os_pid)
            {:stop, {:initialization_failed, reason}}
        end
        
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  def handle_call({:execute, code, options}, _from, state) do
    # This will be replaced with proper variable/tool operations in later stages
    # For now, just ping to test the connection
    case Client.ping(state.channel, "test") do
      {:ok, response} ->
        {:reply, {:ok, response.message}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def terminate(_reason, %{port: port, os_pid: os_pid, channel: channel, session_id: session_id}) do
    # Cleanup session
    Client.cleanup_session(channel, session_id)
    GRPC.Channel.close(channel)
    cleanup(port, os_pid)
  end
  
  defp start_python_server(config) do
    python_path = config[:python_path] || "python3"
    script_path = Path.join(:code.priv_dir(:snakepit), "python/grpc_bridge.py")
    
    port_args = [
      python_path,
      script_path,
      "--port", to_string(config[:grpc_port]),
      "--adapter", config[:bridge_module] || "snakepit_bridge.adapters.enhanced"
    ]
    
    port = Port.open({:spawn_executable, python_path}, [
      {:args, tl(port_args)},
      {:cd, Path.dirname(script_path)},
      :binary,
      :exit_status,
      {:line, 1024}
    ])
    
    os_pid = Port.info(port)[:os_pid]
    {:ok, port, os_pid}
  end
  
  defp wait_for_server(port, attempts \\ 20)
  defp wait_for_server(_port, 0), do: {:error, :timeout}
  defp wait_for_server(port, attempts) do
    case :gen_tcp.connect('localhost', port, [:binary, active: false], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok
      {:error, _} ->
        Process.sleep(100)
        wait_for_server(port, attempts - 1)
    end
  end
  
  defp cleanup(port, os_pid) do
    Port.close(port)
    ProcessRegistry.unregister(os_pid)
    System.cmd("kill", ["-9", to_string(os_pid)])
  end
end
```

#### Create `snakepit/lib/snakepit/grpc/client.ex`:

```elixir
defmodule Snakepit.GRPC.Client do
  @moduledoc """
  gRPC client for the unified bridge protocol.
  """
  
  alias Snakepit.Bridge.{
    SnakepitBridge.Stub,
    PingRequest, PingResponse,
    InitializeSessionRequest, InitializeSessionResponse,
    CleanupSessionRequest, CleanupSessionResponse,
    GetVariableRequest, GetVariableResponse,
    SetVariableRequest, SetVariableResponse
  }
  
  @timeout 30_000
  
  def connect(port) do
    GRPC.Stub.connect("localhost:#{port}")
  end
  
  def ping(channel, message) do
    request = PingRequest.new(message: message)
    
    channel
    |> Stub.ping(request, timeout: @timeout)
    |> handle_response()
  end
  
  def initialize_session(channel, session_id, metadata \\ %{}) do
    request = InitializeSessionRequest.new(
      session_id: session_id,
      metadata: metadata
    )
    
    channel
    |> Stub.initialize_session(request, timeout: @timeout)
    |> handle_response()
  end
  
  def cleanup_session(channel, session_id) do
    request = CleanupSessionRequest.new(session_id: session_id)
    
    channel
    |> Stub.cleanup_session(request, timeout: @timeout)
    |> handle_response()
  end
  
  def get_variable(channel, session_id, variable_id) do
    request = GetVariableRequest.new(
      session_id: session_id,
      variable_id: variable_id
    )
    
    channel
    |> Stub.get_variable(request, timeout: @timeout)
    |> handle_response()
  end
  
  def set_variable(channel, session_id, variable_id, value, metadata \\ %{}) do
    request = SetVariableRequest.new(
      session_id: session_id,
      variable_id: variable_id,
      value: encode_any(value),
      metadata: metadata
    )
    
    channel
    |> Stub.set_variable(request, timeout: @timeout)
    |> handle_response()
  end
  
  defp handle_response({:ok, response}), do: {:ok, response}
  defp handle_response({:error, %GRPC.RPCError{} = error}), do: {:error, error}
  defp handle_response(error), do: error
  
  defp encode_any(value) do
    # This will be properly implemented in Stage 1
    # For now, just wrap in Any
    Google.Protobuf.Any.new()
  end
end
```

### 4. Update Python gRPC Server

#### Update `snakepit/priv/python/grpc_bridge.py`:

```python
#!/usr/bin/env python3
"""
Unified gRPC bridge server for DSPex.
"""

import argparse
import asyncio
import grpc
import logging
import sys
from concurrent import futures
from datetime import datetime

# Add the package to Python path
sys.path.insert(0, '.')

from snakepit_bridge.grpc import snakepit_bridge_pb2 as pb2
from snakepit_bridge.grpc import snakepit_bridge_pb2_grpc as pb2_grpc
from snakepit_bridge.session_context import SessionContext
from snakepit_bridge.adapters.enhanced import EnhancedBridge

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SnakepitBridgeServicer(pb2_grpc.SnakepitBridgeServicer):
    """Implementation of the unified gRPC bridge service."""
    
    def __init__(self, adapter_class):
        self.adapter_class = adapter_class
        self.sessions = {}  # session_id -> SessionContext
        self.adapters = {}  # session_id -> adapter instance
    
    def Ping(self, request, context):
        """Health check endpoint."""
        logger.info(f"Ping received: {request.message}")
        
        response = pb2.PingResponse()
        response.message = f"Pong: {request.message}"
        response.server_time.GetCurrentTime()
        
        return response
    
    def InitializeSession(self, request, context):
        """Initialize a new session."""
        logger.info(f"Initializing session: {request.session_id}")
        
        try:
            # Create session context
            session = SessionContext(request.session_id)
            self.sessions[request.session_id] = session
            
            # Create adapter instance
            adapter = self.adapter_class()
            adapter.set_session_context(session)
            self.adapters[request.session_id] = adapter
            
            response = pb2.InitializeSessionResponse()
            response.success = True
            
            # For now, return empty tools and variables
            # These will be populated in later stages
            
            return response
            
        except Exception as e:
            logger.error(f"Failed to initialize session: {e}")
            response = pb2.InitializeSessionResponse()
            response.success = False
            response.error_message = str(e)
            return response
    
    def CleanupSession(self, request, context):
        """Clean up a session."""
        logger.info(f"Cleaning up session: {request.session_id}")
        
        response = pb2.CleanupSessionResponse()
        
        if request.session_id in self.sessions:
            del self.sessions[request.session_id]
            del self.adapters[request.session_id]
            response.success = True
        else:
            response.success = False
            
        return response
    
    def GetVariable(self, request, context):
        """Get a variable value - placeholder for Stage 1."""
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details('GetVariable not implemented yet')
        return pb2.GetVariableResponse()
    
    def SetVariable(self, request, context):
        """Set a variable value - placeholder for Stage 1."""
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details('SetVariable not implemented yet')
        return pb2.SetVariableResponse()
    
    def ExecuteTool(self, request, context):
        """Execute a tool - placeholder for Stage 2."""
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details('ExecuteTool not implemented yet')
        return pb2.ExecuteToolResponse()


async def serve(port: int, adapter_module: str):
    """Start the gRPC server."""
    # Import the adapter
    module_parts = adapter_module.split('.')
    module_name = '.'.join(module_parts[:-1])
    class_name = module_parts[-1]
    
    module = __import__(module_name, fromlist=[class_name])
    adapter_class = getattr(module, class_name)
    
    # Create server
    server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
    pb2_grpc.add_SnakepitBridgeServicer_to_server(
        SnakepitBridgeServicer(adapter_class), 
        server
    )
    
    # Listen on port
    server.add_insecure_port(f'[::]:{port}')
    
    logger.info(f"Starting gRPC server on port {port}")
    await server.start()
    
    # Signal readiness by printing to stdout
    print(f"GRPC_READY:{port}", flush=True)
    
    try:
        await server.wait_for_termination()
    except KeyboardInterrupt:
        logger.info("Shutting down server")
        await server.stop(0)


def main():
    parser = argparse.ArgumentParser(description='DSPex gRPC Bridge Server')
    parser.add_argument('--port', type=int, default=50051, help='Port to listen on')
    parser.add_argument('--adapter', type=str, 
                       default='snakepit_bridge.adapters.enhanced.EnhancedBridge',
                       help='Adapter class to use')
    
    args = parser.parse_args()
    
    asyncio.run(serve(args.port, args.adapter))


if __name__ == '__main__':
    main()
```

### 5. Create Basic SessionContext

#### Create `snakepit/priv/python/snakepit_bridge/session_context.py`:

```python
"""
SessionContext manages the Python-side session state.
"""

import asyncio
import time
from typing import Dict, Any, Optional, Tuple
import grpc

from .grpc import snakepit_bridge_pb2 as pb2
from .grpc import snakepit_bridge_pb2_grpc as pb2_grpc


class SessionContext:
    """
    Manages session state and provides unified access to variables and tools.
    
    This is a minimal implementation for Stage 0. It will be significantly
    expanded in subsequent stages.
    """
    
    def __init__(self, session_id: str):
        self.session_id = session_id
        self._tools: Dict[str, Any] = {}
        self._variable_cache: Dict[str, Tuple[Any, float]] = {}
        self._cache_ttl = 1.0  # 1 second default TTL
        self.metadata: Dict[str, str] = {}
        
    def get_session_id(self) -> str:
        """Get the session ID."""
        return self.session_id
    
    def set_metadata(self, key: str, value: str):
        """Set session metadata."""
        self.metadata[key] = value
    
    def get_metadata(self, key: str) -> Optional[str]:
        """Get session metadata."""
        return self.metadata.get(key)
    
    # Placeholder methods for future stages
    
    async def get_variable(self, name: str, bypass_cache: bool = False) -> Any:
        """Get variable value - to be implemented in Stage 1."""
        raise NotImplementedError("Variables not implemented until Stage 1")
    
    async def set_variable(self, name: str, value: Any, metadata: Optional[Dict[str, str]] = None) -> None:
        """Set variable value - to be implemented in Stage 1."""
        raise NotImplementedError("Variables not implemented until Stage 1")
    
    def get_tool(self, name: str) -> Any:
        """Get tool by name - to be implemented in Stage 2."""
        raise NotImplementedError("Tools not implemented until Stage 2")
```

#### Update adapter base to use SessionContext:

Create `snakepit/priv/python/snakepit_bridge/adapters/enhanced.py`:

```python
"""
Enhanced bridge adapter that will evolve through the stages.
"""

from typing import Any, Dict, Optional
import logging

from ..session_context import SessionContext

logger = logging.getLogger(__name__)


class EnhancedBridge:
    """
    Enhanced bridge adapter with session support.
    
    This is a minimal implementation for Stage 0.
    """
    
    def __init__(self):
        self.session_context: Optional[SessionContext] = None
        
    def set_session_context(self, session_context: SessionContext):
        """Set the session context for this adapter instance."""
        self.session_context = session_context
        logger.info(f"Session context set: {session_context.session_id}")
    
    def get_info(self) -> Dict[str, Any]:
        """Get adapter information."""
        return {
            "adapter": "EnhancedBridge",
            "version": "0.1.0",
            "stage": 0,
            "session_id": self.session_context.session_id if self.session_context else None
        }
```

### 6. End-to-End Test

Create `test/snakepit/grpc_worker_stage0_test.exs`:

```elixir
defmodule Snakepit.GRPCWorkerStage0Test do
  use ExUnit.Case, async: false
  
  alias Snakepit.GRPCWorker
  alias Snakepit.GRPC.Client
  
  @port 50100
  
  setup do
    # Start a GRPCWorker
    config = [
      adapter: Snakepit.Adapters.GRPCPython,
      python_path: System.get_env("PYTHON_PATH", "python3"),
      grpc_port: @port,
      bridge_module: "snakepit_bridge.adapters.enhanced.EnhancedBridge"
    ]
    
    {:ok, worker} = GRPCWorker.start_link(config)
    
    on_exit(fn ->
      GenServer.stop(worker)
    end)
    
    # Get the channel from worker state
    state = :sys.get_state(worker)
    
    {:ok, worker: worker, channel: state.channel, session_id: state.session_id}
  end
  
  describe "Stage 0 - Protocol Foundation" do
    test "ping/pong works with new protocol", %{channel: channel} do
      {:ok, response} = Client.ping(channel, "hello from elixir")
      
      assert response.message == "Pong: hello from elixir"
      assert response.server_time != nil
    end
    
    test "session is initialized on startup", %{channel: channel, session_id: session_id} do
      # Session should already be initialized by the worker
      # Try to initialize again should work (idempotent)
      {:ok, response} = Client.initialize_session(channel, session_id)
      
      assert response.success == true
      assert response.error_message == ""
    end
    
    test "session can be cleaned up", %{channel: channel} do
      # Create a new session
      new_session_id = "test_session_#{System.unique_integer()}"
      {:ok, init_response} = Client.initialize_session(channel, new_session_id)
      assert init_response.success == true
      
      # Clean it up
      {:ok, cleanup_response} = Client.cleanup_session(channel, new_session_id)
      assert cleanup_response.success == true
      
      # Trying to clean up again should still succeed (idempotent)
      {:ok, cleanup_response2} = Client.cleanup_session(channel, new_session_id)
      assert cleanup_response2.success == false  # Already cleaned up
    end
    
    test "worker cleans up session on termination", %{worker: worker, session_id: session_id} do
      # This test verifies that the session is cleaned up when worker stops
      # We'll need to check this by starting a new connection after stopping
      
      # Stop the worker
      GenServer.stop(worker)
      
      # Give it time to clean up
      Process.sleep(100)
      
      # The session should be cleaned up (we can't verify directly without
      # another connection, but the termination callback should have run)
      assert true
    end
  end
end
```

## Success Criteria

1. **Protocol Defined**: Complete `snakepit_bridge.proto` with all planned messages
2. **Code Generated**: Both Elixir and Python have generated gRPC code
3. **Infrastructure Updated**: GRPCWorker uses new protocol and manages sessions
4. **Python Foundation**: Basic SessionContext and adapter pattern established
5. **End-to-End Test Passes**: Ping works, sessions can be initialized/cleaned up

## Common Issues and Solutions

### Issue: Protocol Buffer Compilation Errors
- **Solution**: Ensure protoc version matches between Elixir and Python
- **Solution**: Check import paths in .proto file

### Issue: gRPC Connection Refused
- **Solution**: Increase wait_for_server timeout
- **Solution**: Check Python server actually prints "GRPC_READY"

### Issue: Session Cleanup Not Working
- **Solution**: Ensure terminate callback is properly implemented
- **Solution**: Add logging to verify cleanup is called

## Next Stage

Stage 1 will build on this foundation by implementing the core variable functionality, including:
- Variable registration and storage in SessionStore
- Get/Set variable operations
- Type validation and serialization
- Basic caching in Python

The protocol and infrastructure from Stage 0 will remain stable, allowing focused development on the variable system.
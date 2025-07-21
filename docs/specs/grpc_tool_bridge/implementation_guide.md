# gRPC Tool Bridge Implementation Guide

## Table of Contents

1. [Setup and Configuration](#setup-and-configuration)
2. [Phase 1: Core Tool Execution](#phase-1-core-tool-execution)
3. [Phase 2: Variable Integration](#phase-2-variable-integration)
4. [Phase 3: Advanced Features](#phase-3-advanced-features)
5. [Error Handling Patterns](#error-handling-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Deployment Considerations](#deployment-considerations)

## Setup and Configuration

### Prerequisites

- Elixir 1.14+ with OTP 25+
- Python 3.9+ with asyncio support
- Protocol Buffers compiler (protoc)
- gRPC libraries for both languages

### Initial Configuration

#### Elixir Side Configuration

```elixir
# config/config.exs
config :dspex,
  grpc_port: 50051,
  grpc_host: "0.0.0.0",
  session_timeout_ms: 300_000,  # 5 minutes
  max_concurrent_sessions: 1000,
  tool_execution_timeout_ms: 30_000

config :grpc,
  max_receive_message_length: 10 * 1024 * 1024,  # 10MB
  max_send_message_length: 10 * 1024 * 1024,
  keepalive_time_ms: 30_000,
  keepalive_timeout_ms: 10_000

# Initialize the SessionStore on application start
# lib/dspex/application.ex
def start(_type, _args) do
  children = [
    DSPex.Bridge.SessionStore,
    {GRPC.Server.Supervisor, endpoint: DSPex.Bridge.Endpoint, port: 50051}
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

#### Python Side Configuration

```python
# config.py
GRPC_CONFIG = {
    "max_message_length": 10 * 1024 * 1024,  # 10MB
    "keepalive_time_ms": 30000,
    "keepalive_timeout_ms": 10000,
    "max_concurrent_rpcs": 100,
}

TOOL_BRIDGE_CONFIG = {
    "default_timeout_ms": 30000,
    "stream_chunk_size": 65536,  # 64KB
    "enable_telemetry": True,
    "enable_caching": True,
    "cache_ttl_seconds": 300,
}

# grpc_setup.py
def create_grpc_channel(address: str) -> grpc.aio.Channel:
    """Create configured async gRPC channel."""
    options = [
        ("grpc.max_receive_message_length", GRPC_CONFIG["max_message_length"]),
        ("grpc.max_send_message_length", GRPC_CONFIG["max_message_length"]),
        ("grpc.keepalive_time_ms", GRPC_CONFIG["keepalive_time_ms"]),
        ("grpc.keepalive_timeout_ms", GRPC_CONFIG["keepalive_timeout_ms"]),
    ]
    return grpc.aio.insecure_channel(address, options=options)
```

### Protocol Buffer Compilation

```bash
# Compile protobuf definitions
cd protos
protoc --elixir_out=plugins=grpc:../lib/dspex/grpc \
       --python_out=../snakepit/priv/python \
       --grpc_python_out=../snakepit/priv/python \
       dspex_bridge.proto
```

## Phase 1: Core Tool Execution

### Overview

Phase 1 implements the minimal viable tool bridge with:
- Session initialization
- Synchronous tool execution
- Streaming tool execution
- Session cleanup

### Step 1: Define the Protobuf Service

```protobuf
// protos/dspex_bridge.proto (Phase 1 subset)
service SnakepitBridge {
    rpc InitializeSession(InitializeSessionRequest) returns (InitializeSessionResponse);
    rpc ExecuteTool(ToolCallRequest) returns (ToolCallResponse);
    rpc StreamTool(ToolStreamRequest) returns (stream ToolStreamChunk);
    rpc CleanupSession(CleanupSessionRequest) returns (StatusResponse);
}
```

### Step 2: Implement Elixir Server Handler

```elixir
# lib/dspex/grpc/bridge_server.ex
defmodule DSPex.GRPC.BridgeServer do
  use GRPC.Server, service: DSPex.Bridge.SnakepitBridge.Service

  alias DSPex.Bridge.SessionStore
  alias DSPex.Tools.Registry

  def initialize_session(request, _stream) do
    # Why: Create session in centralized store, not in Python worker
    case SessionStore.create_session(request.session_id, request.metadata) do
      {:ok, session} ->
        # Get tools registered for this session
        tools = Registry.get_session_tools(request.session_id)
        
        # Convert to protobuf specs
        tool_specs = Enum.map(tools, &tool_to_proto_spec/1)
        
        %InitializeSessionResponse{
          success: true,
          tool_count: length(tool_specs),
          capabilities: ["streaming", "variables"]
        }
      
      {:error, reason} ->
        %InitializeSessionResponse{
          success: false,
          error: %ErrorInfo{
            type: "SessionCreationError",
            message: to_string(reason)
          }
        }
    end
  end

  def execute_tool(request, _stream) do
    # Why: All state lookup happens in Elixir, Python remains stateless
    with {:ok, tool} <- SessionStore.get_tool(request.session_id, request.tool_id),
         {:ok, args} <- deserialize_args(request.args),
         {:ok, kwargs} <- deserialize_kwargs(request.kwargs),
         {:ok, result} <- Registry.execute(tool.id, args, kwargs) do
      
      %ToolCallResponse{
        success: true,
        result: serialize_value(result),
        request_id: request.request_id,
        metrics: build_metrics()
      }
    else
      {:error, reason} ->
        %ToolCallResponse{
          success: false,
          error: build_error(reason),
          request_id: request.request_id
        }
    end
  end

  def stream_tool(request, stream) do
    # Why: Streaming allows progressive results for long-running tools
    case SessionStore.get_tool(request.session_id, request.tool_id) do
      {:ok, tool} ->
        Task.async(fn ->
          stream_tool_execution(tool, request, stream)
        end)
      
      {:error, reason} ->
        # Send single error chunk and close stream
        GRPC.Server.send_reply(stream, %ToolStreamChunk{
          stream_id: request.stream_id,
          content: {:error, build_error(reason)}
        })
    end
  end

  defp stream_tool_execution(tool, request, stream) do
    Registry.stream(
      tool.id,
      deserialize_args(request.args),
      fn chunk ->
        # Send each chunk to Python
        GRPC.Server.send_reply(stream, %ToolStreamChunk{
          stream_id: request.stream_id,
          sequence: chunk.sequence,
          content: {:data, serialize_value(chunk.data)}
        })
      end,
      deserialize_kwargs(request.kwargs)
    )
    
    # Send completion signal
    GRPC.Server.send_reply(stream, %ToolStreamChunk{
      stream_id: request.stream_id,
      content: {:complete, %CompleteSignal{
        total_chunks: stream.chunk_count,
        metrics: build_metrics()
      }}
    })
  end
end
```

### Step 3: Implement Python Client

```python
# snakepit/priv/python/grpc_tool_bridge.py
import asyncio
from typing import Dict, Any, Optional
import grpc

from dspex_bridge_pb2 import *
from dspex_bridge_pb2_grpc import SnakepitBridgeStub

class ToolBridgeClient:
    """Client for executing tools via gRPC.
    
    Why: This is the Python-side entry point for the tool bridge.
    It maintains the session context and provides clean APIs.
    """
    
    def __init__(self, server_address: str):
        self.channel = create_grpc_channel(server_address)
        self.stub = SnakepitBridgeStub(self.channel)
        self.session_id: Optional[str] = None
        
    async def initialize_session(self, session_id: str, metadata: Dict[str, str] = None) -> bool:
        """Initialize a new tool bridge session.
        
        Why: Sessions provide isolation and state management on the Elixir side.
        """
        request = InitializeSessionRequest(
            session_id=session_id,
            callback_address=f"localhost:{GRPC_CONFIG['callback_port']}",
            metadata=metadata or {}
        )
        
        try:
            response = await self.stub.InitializeSession(request)
            if response.success:
                self.session_id = session_id
                return True
            else:
                raise RuntimeError(f"Session init failed: {response.error.message}")
        except grpc.RpcError as e:
            raise ConnectionError(f"gRPC error: {e.code()}: {e.details()}")
    
    async def execute_tool(self, tool_id: str, *args, **kwargs) -> Any:
        """Execute a tool synchronously.
        
        Why: Simple request-response pattern for most tools.
        """
        if not self.session_id:
            raise RuntimeError("Session not initialized")
            
        request = ToolCallRequest(
            session_id=self.session_id,
            tool_id=tool_id,
            args=[serialize_value(arg) for arg in args],
            kwargs={k: serialize_value(v) for k, v in kwargs.items()},
            request_id=f"req_{uuid.uuid4().hex[:8]}"
        )
        
        response = await self.stub.ExecuteTool(request)
        
        if response.success:
            return deserialize_value(response.result)
        else:
            raise ToolExecutionError(
                tool_name=tool_id,
                error_type=response.error.type,
                message=response.error.message,
                details=dict(response.error.details)
            )
    
    async def stream_tool(self, tool_id: str, *args, **kwargs):
        """Execute a tool and stream results.
        
        Why: Streaming enables progressive results for long-running operations.
        """
        if not self.session_id:
            raise RuntimeError("Session not initialized")
            
        request = ToolStreamRequest(
            session_id=self.session_id,
            tool_id=tool_id,
            args=[serialize_value(arg) for arg in args],
            kwargs={k: serialize_value(v) for k, v in kwargs.items()},
            stream_id=f"stream_{uuid.uuid4().hex[:8]}"
        )
        
        async for chunk in self.stub.StreamTool(request):
            if chunk.HasField("data"):
                yield deserialize_value(chunk.data)
            elif chunk.HasField("complete"):
                # Stream finished successfully
                return
            elif chunk.HasField("error"):
                raise ToolExecutionError(
                    tool_name=tool_id,
                    error_type=chunk.error.type,
                    message=chunk.error.message
                )
```

### Step 4: Integration with DSPy

```python
# Integration point for DSPy modules
class GRPCToolBridge:
    """Bridge between DSPy and Elixir tools.
    
    Why: DSPy expects callable tools, so we wrap gRPC calls
    in a familiar interface.
    """
    
    def __init__(self, server_address: str):
        self.client = ToolBridgeClient(server_address)
        self.tools: Dict[str, AsyncGRPCProxyTool] = {}
        
    async def initialize(self, session_id: str) -> Dict[str, Any]:
        """Initialize session and create tool proxies."""
        # Initialize gRPC session
        await self.client.initialize_session(session_id)
        
        # Get tool specs from Elixir
        tool_specs = await self._fetch_tool_specs()
        
        # Create proxy tools
        for spec in tool_specs:
            if spec.type == ToolType.STREAMING:
                proxy = StreamingGRPCProxyTool(spec, self.client)
            else:
                proxy = AsyncGRPCProxyTool(spec, self.client)
            
            self.tools[spec.name] = proxy
            
        return self.tools
    
    def get_dspy_tools(self) -> List[dspy.Tool]:
        """Convert proxies to DSPy tools.
        
        Why: DSPy has its own Tool abstraction that provides
        additional metadata and validation.
        """
        dspy_tools = []
        for name, proxy in self.tools.items():
            tool = dspy.Tool(
                func=proxy,
                name=name,
                desc=proxy.__doc__ or f"Elixir tool: {name}"
            )
            dspy_tools.append(tool)
        return dspy_tools
```

## Phase 2: Variable Integration

### Overview

Phase 2 adds shared state management between Elixir and Python:
- Get/set session variables
- Type-safe serialization
- Variable metadata

### Step 1: Extend Protobuf Definitions

```protobuf
// Add to service definition
rpc GetSessionVariable(GetVariableRequest) returns (VariableResponse);
rpc SetSessionVariable(SetVariableRequest) returns (StatusResponse);
```

### Step 2: Implement Variable Operations in Elixir

```elixir
# Extend the bridge server
def get_session_variable(request, _stream) do
  # Why: Variables enable shared context between languages
  case SessionStore.get_variable(request.session_id, request.variable_name) do
    {:ok, value, metadata} ->
      %VariableResponse{
        exists: true,
        value: serialize_value(value),
        metadata: metadata_to_proto(metadata)
      }
    
    {:error, :not_found} ->
      %VariableResponse{
        exists: false
      }
  end
end

def set_session_variable(request, _stream) do
  # Why: Bidirectional state updates enable complex workflows
  with {:ok, value} <- deserialize_value(request.value),
       :ok <- SessionStore.set_variable(
         request.session_id,
         request.variable_name,
         value,
         request.metadata
       ) do
    %StatusResponse{success: true}
  else
    {:error, reason} ->
      %StatusResponse{
        success: false,
        error: build_error(reason)
      }
  end
end
```

### Step 3: Python Variable Access

```python
# Extend SessionContext with variable support
class SessionContext:
    """Enhanced with variable bridge support."""
    
    async def get_variable(self, name: str) -> Any:
        """Get a session variable from Elixir.
        
        Why: Variables provide shared state without coupling
        tool implementations.
        """
        request = GetVariableRequest(
            session_id=self.session_id,
            variable_name=name,
            include_metadata=True
        )
        
        response = await self.stub.GetSessionVariable(request)
        
        if response.exists:
            # Cache locally for performance
            self._variables[name] = deserialize_value(response.value)
            return self._variables[name]
        else:
            raise KeyError(f"Variable '{name}' not found in session")
    
    async def set_variable(self, name: str, value: Any, 
                          metadata: Dict[str, str] = None) -> None:
        """Set a session variable in Elixir.
        
        Why: Tools can produce intermediate results that other
        tools or the Elixir side can consume.
        """
        request = SetVariableRequest(
            session_id=self.session_id,
            variable_name=name,
            value=serialize_value(value),
            metadata=VariableMetadata(
                type=type(value).__name__,
                created_by="python",
                tags=metadata or {}
            ),
            create_if_missing=True
        )
        
        response = await self.stub.SetSessionVariable(request)
        
        if response.success:
            # Update local cache
            self._variables[name] = value
        else:
            raise RuntimeError(f"Failed to set variable: {response.error.message}")
```

### Step 4: Variable-Aware Tools

```python
class VariableAwareProxyTool(AsyncGRPCProxyTool):
    """Tool that can access session variables.
    
    Why: Many tools need context from previous operations,
    and variables provide a clean way to share this.
    """
    
    async def __call__(self, *args, **kwargs):
        # Tools can read configuration from variables
        config = await self.session_context.get_variable("tool_config")
        if config and self.name in config:
            kwargs.update(config[self.name])
        
        # Execute with enriched context
        result = await super().__call__(*args, **kwargs)
        
        # Store results for downstream tools
        await self.session_context.set_variable(
            f"last_{self.name}_result",
            result,
            metadata={"tool": self.name, "timestamp": datetime.now().isoformat()}
        )
        
        return result
```

## Phase 3: Advanced Features

### Batch Operations

```python
async def execute_batch(self, batch_requests: List[Dict[str, Any]]) -> List[Any]:
    """Execute multiple tools in parallel.
    
    Why: Batch operations reduce round-trip overhead and
    enable efficient parallel execution.
    """
    request = BatchToolCallRequest(
        session_id=self.session_id,
        batch_id=f"batch_{uuid.uuid4().hex[:8]}",
        items=[
            ToolCallItem(
                index=i,
                tool_id=req["tool_id"],
                args=[serialize_value(arg) for arg in req.get("args", [])],
                kwargs={k: serialize_value(v) 
                       for k, v in req.get("kwargs", {}).items()}
            )
            for i, req in enumerate(batch_requests)
        ],
        config=BatchConfig(
            parallel=True,
            stop_on_error=False,
            max_parallel=10
        )
    )
    
    response = await self.stub.BatchExecuteTools(request)
    
    # Process results maintaining order
    results = []
    for item in sorted(response.results, key=lambda x: x.index):
        if item.success:
            results.append(deserialize_value(item.result))
        else:
            results.append(ToolExecutionError(
                tool_name=batch_requests[item.index]["tool_id"],
                error_type=item.error.type,
                message=item.error.message
            ))
    
    return results
```

### ReAct Agent Integration

```python
async def create_react_agent(self, signature: str, 
                           tool_names: List[str] = None,
                           max_iters: int = 5) -> str:
    """Create a ReAct agent with Elixir tools.
    
    Why: ReAct agents need tools, and this provides
    seamless integration with Elixir-side tools.
    """
    # Filter tools if specific subset requested
    if tool_names:
        tools = [self.tools[name] for name in tool_names 
                if name in self.tools]
    else:
        tools = list(self.tools.values())
    
    # Convert to DSPy tools
    dspy_tools = [
        dspy.Tool(func=tool, name=tool.name, desc=tool.__doc__)
        for tool in tools
    ]
    
    # Create agent
    agent = dspy.ReAct(
        signature=signature,
        tools=dspy_tools,
        max_iters=max_iters
    )
    
    # Store in session
    agent_id = f"react_{self.session_id}_{uuid.uuid4().hex[:8]}"
    await self.session_context.set_variable(
        f"agent_{agent_id}",
        agent,
        metadata={"type": "react_agent", "signature": signature}
    )
    
    return agent_id
```

## Error Handling Patterns

### Consistent Error Types

```python
class ToolBridgeError(Exception):
    """Base error for tool bridge operations."""
    pass

class ToolExecutionError(ToolBridgeError):
    """Tool execution failed."""
    def __init__(self, tool_name: str, error_type: str, 
                 message: str, details: Dict[str, Any] = None):
        self.tool_name = tool_name
        self.error_type = error_type
        self.details = details or {}
        super().__init__(f"Tool '{tool_name}' failed ({error_type}): {message}")

class ToolCommunicationError(ToolBridgeError):
    """gRPC communication failed."""
    def __init__(self, tool_name: str, code: grpc.StatusCode, details: str):
        self.tool_name = tool_name
        self.code = code
        super().__init__(f"Communication error for '{tool_name}': {code} - {details}")

class SessionError(ToolBridgeError):
    """Session-related error."""
    pass
```

### Error Recovery

```python
async def execute_with_retry(self, tool_id: str, *args, 
                           max_retries: int = 3, **kwargs) -> Any:
    """Execute tool with automatic retry on transient errors.
    
    Why: Network issues and transient failures shouldn't
    crash the entire workflow.
    """
    last_error = None
    
    for attempt in range(max_retries):
        try:
            return await self.execute_tool(tool_id, *args, **kwargs)
        except ToolCommunicationError as e:
            if e.code in [grpc.StatusCode.UNAVAILABLE, 
                         grpc.StatusCode.DEADLINE_EXCEEDED]:
                # Transient error, retry with backoff
                last_error = e
                await asyncio.sleep(2 ** attempt)
                continue
            else:
                # Non-transient error, fail immediately
                raise
        except ToolExecutionError as e:
            if e.error_type == "RateLimitExceeded":
                # Rate limit, retry with longer backoff
                last_error = e
                await asyncio.sleep(10 * (attempt + 1))
                continue
            else:
                # Tool logic error, don't retry
                raise
    
    # All retries exhausted
    raise last_error
```

## Performance Optimization

### Connection Pooling

```python
class ChannelPool:
    """Reuse gRPC channels for better performance.
    
    Why: Creating new channels is expensive, and most
    sessions will connect to the same Elixir nodes.
    """
    
    def __init__(self, max_channels_per_target: int = 5):
        self._channels: Dict[str, List[grpc.aio.Channel]] = {}
        self._round_robin: Dict[str, int] = {}
        self._lock = asyncio.Lock()
        self.max_per_target = max_channels_per_target
        
    async def get_channel(self, target: str) -> grpc.aio.Channel:
        async with self._lock:
            if target not in self._channels:
                # Create initial channel
                channel = create_grpc_channel(target)
                self._channels[target] = [channel]
                self._round_robin[target] = 0
                return channel
            
            # Round-robin among existing channels
            channels = self._channels[target]
            index = self._round_robin[target]
            channel = channels[index]
            
            # Update round-robin counter
            self._round_robin[target] = (index + 1) % len(channels)
            
            # Expand pool if needed and under limit
            if len(channels) < self.max_per_target:
                new_channel = create_grpc_channel(target)
                channels.append(new_channel)
            
            return channel
```

### Result Caching

```python
from functools import lru_cache
from cachetools import TTLCache

class CachedSessionContext(SessionContext):
    """Session context with intelligent caching.
    
    Why: Many tools are called repeatedly with the same
    arguments, especially in iterative agents.
    """
    
    def __init__(self, *args, cache_ttl: int = 300, **kwargs):
        super().__init__(*args, **kwargs)
        self._tool_cache = TTLCache(maxsize=1000, ttl=cache_ttl)
        
    async def execute_tool_cached(self, tool_id: str, *args, **kwargs) -> Any:
        # Create cache key from tool and arguments
        cache_key = (tool_id, args, tuple(sorted(kwargs.items())))
        
        # Check cache
        if cache_key in self._tool_cache:
            return self._tool_cache[cache_key]
        
        # Execute and cache
        result = await self.execute_tool(tool_id, *args, **kwargs)
        self._tool_cache[cache_key] = result
        return result
```

## Deployment Considerations

### Health Checks

```python
async def health_check(channel: grpc.aio.Channel) -> bool:
    """Verify gRPC service is healthy.
    
    Why: Load balancers and orchestrators need to know
    when a service is ready to accept traffic.
    """
    stub = SnakepitBridgeStub(channel)
    request = HealthCheckRequest(service="tool_bridge")
    
    try:
        response = await asyncio.wait_for(
            stub.HealthCheck(request),
            timeout=5.0
        )
        return response.status == HealthCheckResponse.SERVING
    except (grpc.RpcError, asyncio.TimeoutError):
        return False
```

### Graceful Shutdown

```python
class GracefulShutdownMixin:
    """Handle shutdown gracefully.
    
    Why: In-flight tool executions should complete before
    the service terminates.
    """
    
    def __init__(self):
        self._shutdown_event = asyncio.Event()
        self._active_calls = set()
        
    async def execute_with_tracking(self, coro):
        task = asyncio.create_task(coro)
        self._active_calls.add(task)
        try:
            return await task
        finally:
            self._active_calls.discard(task)
    
    async def shutdown(self, timeout: float = 30.0):
        """Graceful shutdown with timeout."""
        self._shutdown_event.set()
        
        # Wait for active calls to complete
        if self._active_calls:
            try:
                await asyncio.wait_for(
                    asyncio.gather(*self._active_calls, return_exceptions=True),
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                # Force cancel remaining tasks
                for task in self._active_calls:
                    task.cancel()
```

## Summary

This implementation guide provides a complete roadmap for building the gRPC tool bridge:

1. **Phase 1** establishes the core infrastructure with minimal complexity
2. **Phase 2** adds powerful variable integration for shared state
3. **Phase 3** builds advanced features on the solid foundation

Key principles throughout:
- **Stateless Python workers** for resilience and scalability
- **Centralized state in Elixir** for consistency
- **Async/await patterns** for efficient concurrency
- **Rich error handling** for production reliability
- **Performance optimization** from day one

The phased approach ensures each milestone delivers working functionality while building toward the complete vision.
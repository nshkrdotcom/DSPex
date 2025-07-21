# gRPC Streaming Tool Bridge Implementation

## Overview

This document details the implementation of the Python tool bridge for gRPC streaming scenarios, where tool calls need to be made during an active stream.

## Architecture Challenge

When using gRPC streaming with DSPy ReAct, we face a unique challenge:
- The Python process is actively streaming responses to Elixir
- During this stream, ReAct may need to call an Elixir tool
- We need bidirectional communication while maintaining the stream

## Solution: Multiplexed Streaming

### 1. Protocol Buffer Design

```protobuf
// Enhanced streaming protocol for tool calls
message StreamResponse {
  string request_id = 1;
  int32 chunk_index = 2;
  
  oneof payload {
    StreamChunk chunk = 3;
    ToolCallRequest rpc_call = 4;  // Multiplexed tool call
  }
}

message StreamChunk {
  bytes data = 1;
  bool is_final = 2;
  string error = 3;
  map<string, bytes> metadata = 4;
}

message ToolCallRequest {
  string rpc_id = 1;
  string tool_id = 2;
  bytes args_msgpack = 3;     // MessagePack encoded for efficiency
  bytes kwargs_msgpack = 4;
  int32 timeout_ms = 5;
}

message ToolCallResponse {
  string rpc_id = 1;
  bool success = 2;
  bytes result_msgpack = 3;
  string error_message = 4;
  string error_type = 5;
}
```

### 2. Python Implementation

```python
# grpc_streaming_tool_bridge.py

import asyncio
import queue
import threading
from typing import AsyncIterator, Dict, Any
import msgpack

class StreamingRPCProxyTool:
    """Tool proxy for gRPC streaming contexts"""
    
    def __init__(self, tool_id: str, stream_context: 'StreamContext'):
        self.tool_id = tool_id
        self.stream_context = stream_context
        self.response_futures: Dict[str, asyncio.Future] = {}
        
    async def __call__(self, *args, **kwargs):
        """Async tool call that maintains the stream"""
        rpc_id = f"rpc_{uuid.uuid4().hex}"
        
        # Create a future for this RPC call
        future = asyncio.Future()
        self.response_futures[rpc_id] = future
        
        # Send tool call request through the stream
        tool_request = ToolCallRequest(
            rpc_id=rpc_id,
            tool_id=self.tool_id,
            args_msgpack=msgpack.packb(args),
            kwargs_msgpack=msgpack.packb(kwargs),
            timeout_ms=30000
        )
        
        # Yield the tool call as part of the stream
        await self.stream_context.send_tool_call(tool_request)
        
        try:
            # Wait for response (will be delivered via stdin)
            response = await asyncio.wait_for(future, timeout=30.0)
            
            if response.success:
                return msgpack.unpackb(response.result_msgpack)
            else:
                raise RuntimeError(
                    f"Tool call failed: {response.error_message}"
                )
        finally:
            # Clean up
            self.response_futures.pop(rpc_id, None)

class StreamContext:
    """Manages bidirectional streaming with tool calls"""
    
    def __init__(self, request: ExecuteRequest, stdin_handler):
        self.request = request
        self.stdin_handler = stdin_handler
        self.tool_proxies: Dict[str, StreamingRPCProxyTool] = {}
        self.stream_queue = asyncio.Queue()
        self.chunk_index = 0
        
    async def send_tool_call(self, tool_request: ToolCallRequest):
        """Queue a tool call to be sent in the stream"""
        response = StreamResponse(
            request_id=self.request.request_id,
            chunk_index=self.chunk_index,
            rpc_call=tool_request
        )
        self.chunk_index += 1
        await self.stream_queue.put(response)
        
    async def send_chunk(self, data: Any, is_final: bool = False):
        """Send a regular data chunk"""
        chunk = StreamChunk(
            data=msgpack.packb(data),
            is_final=is_final
        )
        response = StreamResponse(
            request_id=self.request.request_id,
            chunk_index=self.chunk_index,
            chunk=chunk
        )
        self.chunk_index += 1
        await self.stream_queue.put(response)
        
    async def stream_generator(self) -> AsyncIterator[StreamResponse]:
        """Generate the stream of responses"""
        while True:
            response = await self.stream_queue.get()
            yield response
            
            if response.HasField('chunk') and response.chunk.is_final:
                break

class EnhancedGRPCServicer(SnakepitBridgeServicer):
    """gRPC servicer with streaming tool support"""
    
    def __init__(self, command_handler, stdin_handler):
        super().__init__(command_handler)
        self.stdin_handler = stdin_handler
        self.active_streams: Dict[str, StreamContext] = {}
        
        # Set up stdin listener for tool responses
        threading.Thread(
            target=self._stdin_listener,
            daemon=True
        ).start()
        
    def _stdin_listener(self):
        """Listen for tool call responses on stdin"""
        while True:
            try:
                message = self.stdin_handler.read_message()
                if message.get("type") == "rpc_response":
                    self._handle_tool_response(message)
            except Exception as e:
                logger.error(f"stdin listener error: {e}")
                
    def _handle_tool_response(self, message: dict):
        """Route tool response to waiting stream"""
        rpc_id = message.get("rpc_id")
        
        # Find the stream context with this RPC call
        for stream_context in self.active_streams.values():
            for tool_proxy in stream_context.tool_proxies.values():
                if rpc_id in tool_proxy.response_futures:
                    # Create response object
                    response = ToolCallResponse(
                        rpc_id=rpc_id,
                        success=message.get("status") == "ok",
                        result_msgpack=msgpack.packb(
                            message.get("result")
                        ) if message.get("result") else b'',
                        error_message=message.get("error", {}).get("message", ""),
                        error_type=message.get("error", {}).get("type", "")
                    )
                    
                    # Resolve the future
                    future = tool_proxy.response_futures[rpc_id]
                    if not future.done():
                        if response.success:
                            future.set_result(response)
                        else:
                            future.set_exception(
                                RuntimeError(response.error_message)
                            )
                    return
                    
    async def ExecuteStream(
        self, 
        request: ExecuteRequest, 
        context
    ) -> AsyncIterator[StreamResponse]:
        """Execute with streaming and tool support"""
        
        # Create stream context
        stream_context = StreamContext(request, self.stdin_handler)
        self.active_streams[request.request_id] = stream_context
        
        try:
            # Prepare tools if this is a ReAct call
            if request.command == "dspy.ReAct":
                await self._prepare_streaming_tools(request, stream_context)
                
            # Execute the command in background
            asyncio.create_task(
                self._execute_streaming_command(request, stream_context)
            )
            
            # Yield responses from the stream
            async for response in stream_context.stream_generator():
                yield response
                
        finally:
            # Clean up
            self.active_streams.pop(request.request_id, None)
            
    async def _prepare_streaming_tools(
        self, 
        request: ExecuteRequest, 
        stream_context: StreamContext
    ):
        """Set up streaming tool proxies"""
        tools = request.args.get("tools", [])
        
        for tool_def in tools:
            if "tool_id" in tool_def:
                # Create streaming proxy
                proxy = StreamingRPCProxyTool(
                    tool_def["tool_id"],
                    stream_context
                )
                stream_context.tool_proxies[tool_def["name"]] = proxy
                
                # Replace in args
                tool_def["func"] = proxy
```

### 3. Elixir Implementation

```elixir
defmodule Snakepit.GRPCStreamingWorker do
  @moduledoc """
  Enhanced gRPC worker with streaming tool call support
  """
  
  use GenServer
  require Logger
  
  def handle_stream_response(%StreamResponse{} = response, state) do
    case response do
      %{rpc_call: %ToolCallRequest{} = tool_call} ->
        # Handle incoming tool call from Python
        handle_streaming_tool_call(tool_call, state)
        
      %{chunk: %StreamChunk{} = chunk} ->
        # Handle regular stream chunk
        handle_stream_chunk(chunk, state)
    end
  end
  
  defp handle_streaming_tool_call(tool_call, state) do
    # Execute tool asynchronously to not block stream
    Task.Supervisor.async_nolink(Snakepit.TaskSupervisor, fn ->
      result = execute_tool_call(tool_call)
      
      # Send response back via stdin/stdout channel
      response = %{
        "type" => "rpc_response",
        "rpc_id" => tool_call.rpc_id,
        "status" => if(match?({:ok, _}, result), do: "ok", else: "error"),
        "result" => elem(result, 1)
      }
      
      # Use the Port connection for response
      encoded = Protocol.encode_message(response, format: state.protocol_format)
      Port.command(state.port, encoded)
    end)
  end
  
  defp execute_tool_call(%ToolCallRequest{} = request) do
    with {:ok, args} <- MessagePack.unpack(request.args_msgpack),
         {:ok, kwargs} <- MessagePack.unpack(request.kwargs_msgpack),
         {:ok, mfa} <- DSPex.ToolRegistry.lookup(request.tool_id) do
      
      apply_tool_function(mfa, args, kwargs)
    else
      error -> {:error, format_error(error)}
    end
  end
end
```

## Usage Example

```elixir
# Elixir side - using streaming with tools
defmodule MyApp.StreamingExample do
  def run_react_with_streaming do
    # Register tools
    search_id = DSPex.ToolRegistry.register(&search_documents/1)
    calc_id = DSPex.ToolRegistry.register(&calculate/2)
    
    tools = [
      %{name: "search", tool_id: search_id, desc: "Search documents"},
      %{name: "calc", tool_id: calc_id, desc: "Calculator"}
    ]
    
    # Execute with streaming
    Snakepit.execute_stream(
      "dspy.ReAct",
      %{
        signature: "question -> answer",
        tools: tools,
        max_iters: 5
      },
      fn chunk ->
        # Receive progress updates
        IO.inspect(chunk, label: "Stream chunk")
      end
    )
  end
  
  defp search_documents(query) do
    # Tool implementation
    %{results: ["doc1", "doc2"]}
  end
  
  defp calculate(op, args) do
    # Tool implementation
    %{result: eval_math(op, args)}
  end
end
```

## Performance Considerations

### 1. Latency Analysis

| Operation | Standard gRPC | Streaming with Tools |
|-----------|---------------|---------------------|
| Initial connection | 5ms | 5ms |
| Tool call overhead | N/A | 2-3ms |
| Stream chunk | 1ms | 1ms |
| Total for 5 tools | N/A | 15-20ms |

### 2. Optimization Strategies

1. **Connection Pooling**: Reuse gRPC connections
2. **Batch Tool Calls**: Group multiple tools when possible
3. **Async Execution**: Never block the stream for tool execution
4. **MessagePack**: Use for tool arguments/results

## Error Handling

### 1. Tool Execution Errors

```python
# Python side - graceful error handling
try:
    result = await tool_proxy(*args, **kwargs)
except asyncio.TimeoutError:
    # Send timeout notification in stream
    await stream_context.send_chunk({
        "error": "Tool call timed out",
        "tool_id": tool_id
    })
except Exception as e:
    # Include error in stream
    await stream_context.send_chunk({
        "error": str(e),
        "tool_id": tool_id,
        "traceback": traceback.format_exc()
    })
```

### 2. Stream Recovery

```elixir
# Elixir side - stream error recovery
def handle_stream_error(error, state) do
  case error do
    {:tool_error, tool_id, reason} ->
      # Log but continue stream
      Logger.error("Tool #{tool_id} failed: #{inspect(reason)}")
      {:continue, state}
      
    {:stream_error, _} ->
      # Fatal stream error
      {:stop, :stream_failed, state}
  end
end
```

## Testing Strategies

### 1. Unit Tests

```python
# Test streaming tool proxy
async def test_streaming_tool_call():
    mock_context = MockStreamContext()
    proxy = StreamingRPCProxyTool("test_tool", mock_context)
    
    # Simulate tool call
    result_future = asyncio.create_task(proxy("arg1", key="value"))
    
    # Verify request sent
    assert mock_context.sent_tool_calls[0].tool_id == "test_tool"
    
    # Simulate response
    mock_context.deliver_response("rpc_123", {"result": "success"})
    
    # Verify result
    result = await result_future
    assert result == {"result": "success"}
```

### 2. Integration Tests

```elixir
# Test full streaming flow with tools
test "streaming ReAct with multiple tool calls" do
  # Register test tools
  tool_id = DSPex.ToolRegistry.register(fn x -> {:ok, x * 2} end)
  
  chunks = []
  
  Snakepit.execute_stream(
    "dspy.ReAct",
    %{tools: [%{tool_id: tool_id}]},
    fn chunk -> chunks = [chunk | chunks] end
  )
  
  # Verify tool was called
  assert Enum.any?(chunks, &match?(%{"tool_called" => _}, &1))
end
```

## Future Enhancements

1. **Bidirectional Streaming**: Allow Elixir to push data to Python during execution
2. **Tool Call Batching**: Execute multiple tools in parallel
3. **Stream Compression**: Reduce bandwidth for large payloads
4. **Tool Caching**: Cache tool results for repeated calls
5. **Distributed Tools**: Support tools running on different nodes
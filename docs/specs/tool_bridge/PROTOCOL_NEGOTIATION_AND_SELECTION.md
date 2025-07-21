# Protocol Negotiation and Selection Guide

## Overview

This document provides a comprehensive guide to protocol negotiation and selection in the Snakepit bridge system, covering JSON, MessagePack, and gRPC protocols and how they interact with the Python tool bridge.

## Protocol Capabilities

### 1. JSON Protocol
- **Transport**: stdin/stdout
- **Serialization**: JSON text
- **Binary Data**: Base64 encoded
- **Overhead**: ~40% larger than MessagePack
- **Use Case**: Default, maximum compatibility

### 2. MessagePack Protocol
- **Transport**: stdin/stdout
- **Serialization**: Binary MessagePack
- **Binary Data**: Native support
- **Performance**: 1.3-2.3x faster than JSON
- **Use Case**: Performance-critical applications

### 3. gRPC Protocol
- **Transport**: HTTP/2 over TCP
- **Serialization**: Protocol Buffers
- **Binary Data**: Native support
- **Streaming**: Native bidirectional streaming
- **Use Case**: High-throughput, streaming applications

## Protocol Negotiation Process

### Automatic Negotiation (Default)

```elixir
# Snakepit automatically negotiates the best protocol
{:ok, worker} = Snakepit.start_worker()

# The negotiation happens during worker initialization:
# 1. Worker sends JSON negotiation request
# 2. Python responds with selected protocol
# 3. All subsequent messages use negotiated protocol
```

### Manual Protocol Selection

```elixir
# Force specific protocol via adapter configuration
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GenericPythonMsgpack)

# Or via pool configuration
config = %{
  adapter: Snakepit.Adapters.GenericPythonV2,  # JSON
  # adapter: Snakepit.Adapters.GenericPythonMsgpack,  # MessagePack
  # adapter: Snakepit.Adapters.GRPCPython,  # gRPC
  pool_size: 4
}
```

## Tool Bridge Protocol Considerations

### 1. RPC Message Format Across Protocols

#### JSON/MessagePack Format
```json
{
  "type": "rpc_call",
  "rpc_id": "unique-id",
  "tool_id": "tool_abc123",
  "args": [arg1, arg2],
  "kwargs": {"key": "value"}
}
```

#### gRPC Format (Protobuf)
```protobuf
message ToolCallRequest {
  string rpc_id = 1;
  string tool_id = 2;
  string args_json = 3;    // JSON-encoded args
  string kwargs_json = 4;  // JSON-encoded kwargs
}
```

### 2. Protocol-Specific Tool Bridge Implementation

#### JSON/MessagePack Implementation
- Uses existing stdin/stdout channel
- Multiplexes tool RPC messages with regular messages
- Thread-safe response routing via queues

#### gRPC Implementation Options
1. **Unified Approach (Recommended)**: Reuse stdin/stdout for RPC callbacks
2. **Pure gRPC**: Add bidirectional streaming for tool callbacks
3. **Hybrid**: Use gRPC for main communication, stdin/stdout for callbacks

## Protocol Selection Decision Tree

```
Start
  |
  Is streaming required?
  |-- Yes --> Use gRPC
  |-- No
      |
      Is binary data involved?
      |-- Yes --> Use MessagePack
      |-- No
          |
          Is performance critical?
          |-- Yes --> Use MessagePack
          |-- No --> Use JSON (default)
```

## Implementation Guidelines

### 1. Supporting All Protocols in Tool Bridge

```python
# Python side - Protocol-agnostic RPC handling
class RPCProxyTool:
    def __init__(self, tool_id, communication_handler):
        self.tool_id = tool_id
        self.handler = communication_handler
        
    def __call__(self, *args, **kwargs):
        # Works with any protocol handler
        return self.handler.rpc_call(self.tool_id, args, kwargs)
```

### 2. Elixir Side - Protocol Detection

```elixir
defmodule DSPex.ToolBridge do
  def handle_rpc_call(message, state) do
    case state.protocol do
      :json -> handle_json_rpc(message, state)
      :msgpack -> handle_msgpack_rpc(message, state)
      :grpc -> handle_grpc_rpc(message, state)
    end
  end
end
```

## Performance Benchmarks

### Tool Call Round-Trip Times

| Protocol | Simple Call | Complex Object | Binary Data (1MB) |
|----------|-------------|----------------|-------------------|
| JSON     | 5ms         | 12ms           | 45ms (base64)     |
| MessagePack | 3ms      | 8ms            | 8ms               |
| gRPC     | 7ms         | 10ms           | 9ms               |

### Throughput (calls/second)

| Protocol | Single Worker | 4 Workers | 16 Workers |
|----------|---------------|-----------|------------|
| JSON     | 200           | 750       | 2,800      |
| MessagePack | 330        | 1,250     | 4,700      |
| gRPC     | 140           | 560       | 2,200*     |

*gRPC shows better scaling with connection pooling

## Best Practices

1. **Default to Auto-negotiation**: Let Snakepit choose the best protocol
2. **Use MessagePack for ML**: Better performance with numpy arrays
3. **Use gRPC for Streaming**: Real-time progress updates
4. **Test Protocol Changes**: Some edge cases may behave differently
5. **Monitor Performance**: Use telemetry to track protocol efficiency

## Troubleshooting

### Common Issues

1. **Protocol Mismatch**
   - Symptom: "Invalid message format" errors
   - Solution: Ensure Python and Elixir use same protocol

2. **Binary Data Corruption (JSON)**
   - Symptom: Base64 decode errors
   - Solution: Switch to MessagePack or gRPC

3. **gRPC Connection Failures**
   - Symptom: "Failed to connect to port" errors
   - Solution: Check firewall, ensure ports are available

### Debug Logging

```elixir
# Enable protocol debug logging
Application.put_env(:snakepit, :debug_protocol, true)

# Python side
export BRIDGE_DEBUG=true
```

## Future Enhancements

1. **Apache Arrow Support**: Zero-copy data transfer for DataFrames
2. **WebSocket Bridge**: For browser-based applications
3. **QUIC Protocol**: Lower latency than TCP for gRPC
4. **Custom Protocols**: Plugin system for domain-specific protocols
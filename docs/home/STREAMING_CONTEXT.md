# DSPex Streaming Implementation Context

## Current Situation

We are implementing gRPC streaming functionality for DSPy operations in DSPex. The user has correctly identified that I made a fundamental architectural error by suggesting to implement streaming in the client library instead of using the existing streaming infrastructure that already exists in the snakepit dependency.

## Key Facts

1. **Streaming functionality ALREADY EXISTS** in `./snakepit` - DO NOT reimplement it
2. **The issue is NOT missing streaming** - it's a dependency/adapter configuration problem
3. **gRPC dependencies exist** in snakepit but aren't being loaded properly in DSPex context
4. **All streaming belongs in the server/bridge side**, not in client code

## What We've Done So Far

### Completed Tasks
- ✅ Updated snakepit to feat-grpc branch in `./mix.exs` 
- ✅ Fixed LM inheritance issue in `./snakepit/_build/dev/lib/snakepit/priv/python/enhanced_bridge.py`
- ✅ Added `_resolve_stored_references` method to enhanced bridge
- ✅ Created streaming example `./examples/dspy/05_streaming_inference_pipeline.exs`
- ✅ All existing DSPy functionality works with enhanced bridge

### Current Problem
- Attempting to use `Snakepit.Adapters.GRPCPython` fails with `:undef` error for `executable_path/0`
- This is because gRPC adapter has conditional compilation that prevents loading when dependencies aren't available

## Critical References - READ THESE

### Snakepit Streaming Infrastructure (ALREADY IMPLEMENTED)
```
./snakepit/lib/snakepit.ex:87              - def execute_stream/4 (main API)
./snakepit/lib/snakepit/pool/pool.ex:57    - def execute_stream/4 (pool implementation)  
./snakepit/lib/snakepit/grpc_worker.ex:98  - def execute_stream/5 (gRPC worker)
./snakepit/lib/snakepit/grpc/client.ex:53  - def execute_stream/5 (gRPC client)
```

### Adapter and Dependencies
```
./snakepit/lib/snakepit/adapters/grpc_python.ex      - gRPC adapter (conditional compilation issue)
./snakepit/mix.exs:32-33                             - grpc and protobuf deps (optional: true)
./snakepit/lib/snakepit/adapters/enhanced_python.ex  - Current working adapter
```

### Documentation to Read
```
./snakepit/README_GRPC.md                            - Complete gRPC streaming guide
./snakepit/docs/specs/grpc_streaming_examples.md     - Practical streaming examples
./snakepit/examples/grpc_streaming_demo.exs          - Working streaming demo
./snakepit/examples/grpc_non_streaming_demo.exs      - Non-streaming demo
```

### Python Bridge Infrastructure  
```
./snakepit/priv/python/grpc_bridge.py               - gRPC Python bridge
./snakepit/priv/python/enhanced_bridge.py           - Enhanced bridge (currently used)
./snakepit/priv/python/snakepit_bridge/grpc/        - gRPC protocol buffers
```

## Next Steps (DO NOT IMPLEMENT STREAMING - USE EXISTING)

### Immediate Task
1. **Fix gRPC adapter dependency issue** - The adapter exists but won't compile due to conditional compilation
2. **Get existing `Snakepit.execute_stream/4` working** - Don't implement new streaming

### Key Code Locations to Examine
```bash
# Check what's preventing gRPC adapter from loading
./snakepit/lib/snakepit/adapters/grpc_python.ex:1-2  # Conditional compilation check

# Understand existing streaming API
./snakepit/lib/snakepit.ex:86-97                     # Main execute_stream function

# See how gRPC should work
./snakepit/examples/grpc_streaming_demo.exs:50       # Working example usage
```

### Configuration Issue
The problem is in this check:
```elixir
# From ./snakepit/lib/snakepit.ex:92-93
unless function_exported?(adapter, :uses_grpc?, 0) and adapter.uses_grpc?() do
  {:error, :streaming_not_supported}
```

The GRPCPython adapter isn't loading due to:
```elixir
# From ./snakepit/lib/snakepit/adapters/grpc_python.ex:1-2
if Code.ensure_loaded?(GRPC.Channel) and Code.ensure_loaded?(Protobuf) do
  defmodule Snakepit.Adapters.GRPCPython do
```

## Current Working Example
```bash
# This currently works with enhanced adapter (non-streaming)
mix run examples/dspy/05_streaming_inference_pipeline.exs
```

## Goal
Get this working:
```elixir
# Should work once gRPC adapter is fixed
Snakepit.execute_stream("batch_inference", %{
  batch_items: ["image1.jpg", "image2.jpg"]
}, fn chunk ->
  IO.puts("Result: #{chunk["result"]}")
end)
```

## What NOT to Do
- ❌ DO NOT implement streaming in enhanced_bridge.py
- ❌ DO NOT add streaming methods to DSPex client code  
- ❌ DO NOT create custom streaming protocols
- ❌ DO NOT modify the Python bridge for streaming (it's already there)

## What TO Do
- ✅ Fix the gRPC adapter dependency/compilation issue
- ✅ Use existing `Snakepit.execute_stream/4` API
- ✅ Leverage existing gRPC infrastructure in `./snakepit`
- ✅ Update the streaming example to use real streaming once adapter works

## Error Context
When attempting to use `Snakepit.Adapters.GRPCPython`:
```
{:undef, [{Snakepit.Adapters.GRPCPython, :executable_path, [], []}
```

This means the module isn't compiled due to the conditional compilation check failing.

## Investigation Commands
```bash
# Check if gRPC deps are available
cd ./snakepit && python -c "import grpc, snakepit_bridge.grpc.snakepit_pb2; print('✅ gRPC available')"

# Check Elixir gRPC deps  
mix run -e "IO.puts(Code.ensure_loaded?(GRPC.Channel)); IO.puts(Code.ensure_loaded?(Protobuf))"

# Look at working streaming example
cat ./snakepit/examples/grpc_streaming_demo.exs
```

The issue is likely that GRPC.Channel and Protobuf modules aren't being loaded in the DSPex application context, even though they exist in snakepit's dependencies.
# DSPy Examples

## Current State

**Important**: DSPy itself does NOT support streaming. When you call a DSPy module, it:
1. Sends the complete prompt to the LLM
2. Waits for the complete response
3. Returns the full result

While Snakepit's gRPC adapter supports streaming at the transport layer, this doesn't help with DSPy because DSPy doesn't yield partial results.

## Examples

### Q&A Examples

1. **`simple_qa_demo.exs`** - Basic Q&A using the default EnhancedPython adapter
   ```bash
   mix run examples/dspy/simple_qa_demo.exs
   ```

2. **`grpc_qa_demo.exs`** - Q&A using the gRPC adapter (requires gRPC dependencies)
   ```bash
   # First ensure gRPC is available:
   # mix deps.get && mix deps.compile
   mix run examples/dspy/grpc_qa_demo.exs
   ```

3. **`adapter_comparison.exs`** - Compares EnhancedPython vs GRPCPython adapters
   ```bash
   mix run examples/dspy/adapter_comparison.exs
   ```

### Simulated Streaming

**`simple_streaming_demo.exs`** - Demonstrates UI techniques for progressive display:
- Word-by-word display
- Chunk-based display  
- Sentence-by-sentence display

This is NOT real streaming - it's just breaking up the complete response for better UX.

## Streaming Techniques

### Progressive Display
```elixir
words = String.split(answer, ~r/\s+/)
Enum.each(words, fn word ->
  IO.write("#{word} ")
  IO.binwrite(:stdio, "")  # Force flush
  Process.sleep(50)        # Simulate typing
end)
```

### Chunked Output
```elixir
chunks = Enum.chunk_every(words, 5)
Enum.each(chunks, fn chunk ->
  IO.write(Enum.join(chunk, " "))
  IO.binwrite(:stdio, "")
  Process.sleep(200)
end)
```

## Adapter Comparison

| Adapter | Protocol | Streaming Support | Use Case |
|---------|----------|------------------|----------|
| **EnhancedPython** | stdin/stdout | ❌ No | Default, simple, lower overhead |
| **GRPCPython** | gRPC/HTTP2 | ✅ Yes* | High throughput, distributed systems |

*Note: Adapter supports streaming, but DSPy doesn't use it

## Future Work

True streaming with DSPy would require:

1. **DSPy Changes**: DSPy itself would need to support yielding partial tokens
2. **LLM Provider Support**: The underlying LLM API must support streaming
3. **New Bridge Protocol**: A streaming-aware protocol between Elixir and Python
4. **New DSPex APIs**: Stream-based module interfaces

## Benefits of Streaming

Even simulated streaming provides:
- Better user experience with immediate feedback
- Progressive display of long responses
- Natural feel for conversational AI
- Reduced perceived latency

## Implementation Notes

The key to simulating streaming in Elixir:
1. Split the response into manageable chunks
2. Use `IO.write/1` for output without newlines
3. Force flush with `IO.binwrite(:stdio, "")`
4. Add delays with `Process.sleep/1`

This creates a typing effect that mimics real streaming behavior.
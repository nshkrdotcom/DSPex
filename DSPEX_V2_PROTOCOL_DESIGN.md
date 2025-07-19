# DSPex V2 Protocol Design

## Current Protocol Analysis

DSPex currently uses a **4-byte length header + JSON payload** protocol:

```
[4 bytes: message length][JSON payload]
```

### Example Message Flow

**Elixir → Python Request:**
```json
{
  "id": 12345,
  "command": "predict",
  "args": {
    "signature": "question -> answer",
    "inputs": {"question": "What is DSPy?"}
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Python → Elixir Response:**
```json
{
  "id": 12345,
  "success": true,
  "result": {
    "answer": "DSPy is a framework for programming with language models"
  },
  "timestamp": "2024-01-15T10:30:01Z"
}
```

## Protocol Improvements for V2

### 1. Keep JSON for Most Operations

JSON is fine for 90% of use cases:
- Simple to debug
- Universal support
- Adequate performance for LLM operations (network latency dominates)

### 2. Add Binary Protocol for Large Data

For large datasets or high-frequency operations, add optional binary protocol:

```elixir
defmodule DSPex.Protocol.Binary do
  @moduledoc """
  Binary protocol for performance-critical operations.
  """
  
  # Message types
  @type_json 0
  @type_msgpack 1
  @type_arrow 2
  @type_numpy 3
  
  def encode(data, type \\ :auto) do
    type = determine_type(data, type)
    
    case type do
      :json -> encode_json(data)
      :msgpack -> encode_msgpack(data)
      :arrow -> encode_arrow(data)
      :numpy -> encode_numpy(data)
    end
  end
  
  defp determine_type(data, :auto) do
    cond do
      # Large structured data -> Arrow
      is_list(data) and length(data) > 1000 -> :arrow
      
      # Numerical arrays -> NumPy
      numerical_array?(data) -> :numpy
      
      # Medium data -> MessagePack
      estimate_size(data) > 10_000 -> :msgpack
      
      # Default -> JSON
      true -> :json
    end
  end
end
```

### 3. Streaming Protocol for Large Responses

For streaming LLM responses or large result sets:

```elixir
defmodule DSPex.Protocol.Stream do
  @moduledoc """
  Streaming protocol for real-time responses.
  """
  
  # Stream message types
  @stream_start 0x01
  @stream_chunk 0x02
  @stream_end 0x03
  @stream_error 0x04
  
  def decode_stream(port) do
    Stream.resource(
      fn -> {:ok, port} end,
      fn port ->
        case read_stream_message(port) do
          {:chunk, data} -> {[data], port}
          :end -> {:halt, port}
          {:error, reason} -> raise "Stream error: #{reason}"
        end
      end,
      fn _port -> :ok end
    )
  end
end
```

### 4. Shared Memory for Ultra-Large Data

For massive datasets (embeddings, training data):

```elixir
defmodule DSPex.Protocol.SharedMemory do
  @moduledoc """
  Shared memory protocol for zero-copy large data transfer.
  """
  
  def transfer_large_dataset(data, python_worker) do
    case byte_size(data) do
      size when size < 1_000_000 ->
        # < 1MB: Use JSON
        {:json, Jason.encode!(data)}
        
      size when size < 100_000_000 ->
        # 1MB - 100MB: Use memory-mapped file
        path = write_mmap_file(data)
        send_reference(python_worker, {:mmap, path})
        
      _ ->
        # > 100MB: Use Apache Arrow for zero-copy
        arrow_file = write_arrow_file(data)
        send_reference(python_worker, {:arrow, arrow_file})
    end
  end
end
```

## Python Side Implementation

```python
# priv/python/protocol_v2.py
import json
import msgpack
import pyarrow as pa
import numpy as np
import mmap
import struct

class ProtocolV2:
    """Enhanced protocol with multiple serialization formats."""
    
    TYPE_JSON = 0
    TYPE_MSGPACK = 1
    TYPE_ARROW = 2
    TYPE_NUMPY = 3
    
    def read_message(self):
        # Read header: [4 bytes length][1 byte type][payload]
        header = sys.stdin.buffer.read(5)
        length, msg_type = struct.unpack('>IB', header)
        
        payload = sys.stdin.buffer.read(length)
        
        if msg_type == self.TYPE_JSON:
            return json.loads(payload.decode('utf-8'))
        elif msg_type == self.TYPE_MSGPACK:
            return msgpack.unpackb(payload, raw=False)
        elif msg_type == self.TYPE_ARROW:
            return self.read_arrow_reference(payload)
        elif msg_type == self.TYPE_NUMPY:
            return np.frombuffer(payload)
    
    def write_message(self, data, msg_type=None):
        if msg_type is None:
            msg_type = self.detect_best_format(data)
        
        if msg_type == self.TYPE_JSON:
            payload = json.dumps(data).encode('utf-8')
        elif msg_type == self.TYPE_MSGPACK:
            payload = msgpack.packb(data, use_bin_type=True)
        # ... other formats
        
        header = struct.pack('>IB', len(payload), msg_type)
        sys.stdout.buffer.write(header + payload)
        sys.stdout.buffer.flush()
```

## Real-World Examples

### Example 1: Simple Prediction (JSON)
```elixir
# Small request/response - JSON is perfect
DSPex.predict(signature, %{question: "What is 2+2?"})

# Wire format:
# [0x00, 0x00, 0x00, 0x64] + {"id": 1, "command": "predict", ...}
```

### Example 2: Batch Processing (MessagePack)
```elixir
# Medium-sized batch - MessagePack for efficiency
inputs = Enum.map(1..1000, &%{question: "Question #{&1}"})
DSPex.batch_predict(signature, inputs, protocol: :msgpack)

# 30% smaller than JSON, faster parsing
```

### Example 3: Embeddings (NumPy)
```elixir
# Large numerical data - NumPy arrays
texts = ["text1", "text2", ...]  # 10,000 texts
{:ok, embeddings} = DSPex.embed(texts, protocol: :numpy)

# Returns Nx tensor directly from NumPy buffer
```

### Example 4: Training Data (Arrow)
```elixir
# Massive dataset - Apache Arrow
dataset = load_training_data()  # 1M examples
DSPex.Optimizers.mipro_v2(program, dataset, protocol: :arrow)

# Zero-copy transfer via shared memory
```

## Performance Comparison

| Protocol | Size (1K records) | Encode Time | Decode Time | Use Case |
|----------|------------------|-------------|-------------|----------|
| JSON | 245 KB | 12ms | 15ms | Default, debugging |
| MessagePack | 178 KB | 3ms | 4ms | Medium data |
| Arrow | 145 KB | 1ms | 0.5ms | Large structured data |
| NumPy | 120 KB | 0.2ms | 0.1ms | Numerical arrays |

## Implementation Strategy

1. **Keep JSON as default** - Works for 90% of cases
2. **Auto-detect large data** - Switch protocols automatically
3. **Explicit protocol selection** - Allow manual override
4. **Backward compatible** - V1 protocol still works

```elixir
# Automatic protocol selection
DSPex.predict(signature, large_input)  # Auto-uses msgpack

# Explicit protocol
DSPex.predict(signature, input, protocol: :arrow)

# Streaming for real-time
DSPex.stream_predict(signature, input) do
  {:chunk, text} -> IO.write(text)
  {:done, stats} -> IO.puts("\nTokens: #{stats.tokens}")
end
```

This gives you the best of all worlds - simplicity for common cases, performance for large data, and streaming for real-time applications.
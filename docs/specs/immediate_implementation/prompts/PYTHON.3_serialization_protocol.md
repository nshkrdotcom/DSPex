# Task: PYTHON.3 - Serialization Protocol

## Context
You are implementing the serialization protocol for efficient data exchange between Elixir and Python processes. This protocol must handle complex data types, maintain type fidelity, and optimize for performance.

## Required Reading

### 1. Snakepit Protocol Documentation
- **File**: `/home/home/p/g/n/dspex/snakepit/README.md`
  - Lines 451-470: Port communication details
  - Binary protocol with 4-byte length headers

### 2. Bridge Protocol Implementation
- **File**: Look for protocol examples in Snakepit
  - Message format patterns
  - Error handling in protocol

### 3. Architecture Serialization Requirements
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Protocol flexibility section
  - Support for JSON, MessagePack, Arrow

### 4. Python Bridge Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/python/bridge.ex`
  - Current serialization approach
  - Type conversion patterns

### 5. ML Type Requirements
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 97-113: ML-specific types
  - Embeddings, tensors, probabilities

## Implementation Requirements

### Protocol Module Structure
```elixir
defmodule DSPex.Python.Protocol do
  @moduledoc """
  Serialization protocol for Elixir-Python communication
  """
  
  @formats [:json, :msgpack, :arrow]
  @default_format :json
  
  defmodule Message do
    defstruct [
      :id,
      :command,
      :args,
      :metadata,
      :format,
      :timestamp
    ]
  end
  
  defmodule Response do
    defstruct [
      :id,
      :success,
      :result,
      :error,
      :metadata,
      :timestamp
    ]
  end
end
```

### Type Conversion Tables
```elixir
defmodule DSPex.Python.Protocol.TypeConverter do
  # Elixir to Python type mappings
  @elixir_to_python %{
    # Basic types
    nil: "None",
    true: "True",
    false: "False",
    :atom => :string,
    
    # Collections
    :list => "list",
    :tuple => "tuple",
    :map => "dict",
    :keyword => "dict",
    
    # Numeric types
    :integer => "int",
    :float => "float",
    :decimal => "Decimal",
    
    # Special types
    :datetime => "datetime",
    :date => "date",
    :time => "time"
  }
  
  # ML-specific type handling
  @ml_types %{
    :embedding => {:array, :float32},
    :tensor => {:ndarray, :dynamic},
    :probability => {:float, constraints: [min: 0.0, max: 1.0]},
    :sparse_vector => {:dict, keys: :integer, values: :float}
  }
  
  def convert_to_python(value, type_hint \\ nil)
  def convert_from_python(value, expected_type \\ nil)
end
```

### Serialization Formats
```elixir
defmodule DSPex.Python.Protocol.Formats do
  @behaviour DSPex.Python.Protocol.Format
  
  # JSON Format (default, most compatible)
  defmodule JSON do
    def encode(data) do
      Jason.encode!(data, 
        pretty: false,
        escape: :unicode_safe
      )
    end
    
    def decode(binary) do
      Jason.decode!(binary, keys: :atoms!)
    end
    
    def content_type, do: "application/json"
  end
  
  # MessagePack (faster, binary-safe)
  defmodule MessagePack do
    def encode(data) do
      Msgpax.pack!(data, 
        binary: true,
        ext: DSPex.Python.Protocol.Extensions
      )
    end
    
    def decode(binary) do
      Msgpax.unpack!(binary,
        binary: true,
        ext: DSPex.Python.Protocol.Extensions
      )
    end
    
    def content_type, do: "application/msgpack"
  end
  
  # Apache Arrow (for large datasets)
  defmodule Arrow do
    def encode(data) when is_list(data) do
      # Convert to Arrow format for efficient transfer
      # of large tabular data
    end
    
    def decode(binary) do
      # Parse Arrow format back to Elixir data
    end
    
    def content_type, do: "application/arrow"
  end
end
```

### Protocol Implementation
```elixir
defmodule DSPex.Python.Protocol do
  def encode_request(command, args, opts \\ []) do
    format = opts[:format] || @default_format
    
    message = %Message{
      id: generate_message_id(),
      command: command,
      args: prepare_args(args, format),
      metadata: build_metadata(opts),
      format: format,
      timestamp: System.monotonic_time()
    }
    
    serializer = get_serializer(format)
    binary = serializer.encode(message)
    
    # Add length header for Snakepit
    add_length_header(binary)
  end
  
  def decode_response(binary, expected_format \\ @default_format) do
    # Remove length header
    {_length, payload} = extract_payload(binary)
    
    serializer = get_serializer(expected_format)
    response = serializer.decode(payload)
    
    # Validate and transform response
    validate_response(response)
    |> transform_response()
  end
  
  defp add_length_header(binary) do
    size = byte_size(binary)
    <<size::32-big, binary::binary>>
  end
  
  defp extract_payload(<<length::32-big, payload::binary>>) do
    {length, payload}
  end
end
```

### Special Type Handlers
```elixir
defmodule DSPex.Python.Protocol.SpecialTypes do
  # Handle numpy arrays / tensors
  def encode_tensor(tensor, _opts) do
    %{
      "_type" => "tensor",
      "data" => tensor.data,
      "shape" => tensor.shape,
      "dtype" => tensor.dtype
    }
  end
  
  def decode_tensor(%{"_type" => "tensor"} = data) do
    %DSPex.Tensor{
      data: data["data"],
      shape: data["shape"],
      dtype: String.to_atom(data["dtype"])
    }
  end
  
  # Handle embeddings efficiently
  def encode_embedding(embedding, opts) do
    if opts[:compress] do
      %{
        "_type" => "embedding_compressed",
        "data" => compress_floats(embedding),
        "dims" => length(embedding)
      }
    else
      embedding
    end
  end
  
  # Handle sparse data
  def encode_sparse(sparse_map, _opts) do
    %{
      "_type" => "sparse",
      "indices" => Map.keys(sparse_map),
      "values" => Map.values(sparse_map),
      "size" => sparse_map.size
    }
  end
end
```

### Error Protocol
```elixir
defmodule DSPex.Python.Protocol.Errors do
  @error_types %{
    serialization_error: "SERIALIZATION_ERROR",
    deserialization_error: "DESERIALIZATION_ERROR",
    type_mismatch: "TYPE_MISMATCH",
    protocol_error: "PROTOCOL_ERROR"
  }
  
  def encode_error(error_type, message, details \\ %{}) do
    %{
      error: true,
      type: @error_types[error_type] || "UNKNOWN_ERROR",
      message: message,
      details: details,
      timestamp: DateTime.utc_now()
    }
  end
  
  def decode_error(%{"error" => true} = error) do
    {:error, %{
      type: atomize_error_type(error["type"]),
      message: error["message"],
      details: error["details"] || %{}
    }}
  end
end
```

## Acceptance Criteria
- [ ] Support for JSON, MessagePack, and Arrow formats
- [ ] Bidirectional type conversion for all basic types
- [ ] ML-specific type handling (tensors, embeddings)
- [ ] Length-prefixed binary protocol for Snakepit
- [ ] Error serialization and deserialization
- [ ] Performance optimization for large data
- [ ] Type safety with validation
- [ ] Extensible for custom types
- [ ] Benchmarks showing serialization overhead

## Testing Requirements
Create tests in:
- `test/dspex/python/protocol_test.exs`
- `test/dspex/python/protocol/type_converter_test.exs`

Test scenarios:
- Round-trip conversion for all types
- Large data handling (>1MB)
- Error cases and malformed data
- Performance benchmarks
- Format switching
- Special ML types

## Example Usage
```elixir
# Encode a request
binary = DSPex.Python.Protocol.encode_request(
  "execute_dspy",
  %{
    module: "ChainOfThought",
    inputs: %{
      question: "What is machine learning?",
      embeddings: [0.1, 0.2, 0.3, ...],  # 1024 dims
      metadata: %{temperature: 0.7}
    }
  },
  format: :msgpack  # Use msgpack for efficiency
)

# Decode a response
{:ok, response} = DSPex.Python.Protocol.decode_response(
  binary_response,
  :msgpack
)

# Handle tensor data
tensor_request = DSPex.Python.Protocol.encode_request(
  "process_tensor",
  %{
    tensor: %DSPex.Tensor{
      data: [...],
      shape: [32, 768],
      dtype: :float32
    }
  },
  format: :arrow  # Best for large numeric data
)
```

## Dependencies
- Jason for JSON
- Msgpax for MessagePack (add to deps)
- Consider Arrow library for future
- Coordinates with PYTHON.1 and PYTHON.4

## Time Estimate
6 hours total:
- 2 hours: Core protocol structure
- 1 hour: Type conversion implementation
- 1 hour: Format implementations
- 1 hour: Special type handlers
- 1 hour: Testing and benchmarks

## Notes
- Default to JSON for compatibility
- Use MessagePack for performance
- Consider Arrow for data science workloads
- Add compression for large embeddings
- Monitor serialization overhead
- Plan for protocol versioning
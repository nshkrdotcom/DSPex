# Stage 1 Prompt 7: Wire Protocol and JSON Schema Generation

## OBJECTIVE

Implement a comprehensive wire protocol system for communication between Elixir and external systems (Python, APIs, providers), along with robust JSON schema generation capabilities that support multiple provider formats (OpenAI, Anthropic, etc.), versioning, and efficient serialization/deserialization with proper error handling and validation.

## COMPLETE IMPLEMENTATION CONTEXT

### WIRE PROTOCOL ARCHITECTURE OVERVIEW

From STAGE_1_FOUNDATION_IMPLEMENTATION.md and Python bridge implementation:

```
┌─────────────────────────────────────────────────────────────┐
│                Wire Protocol Architecture                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Protocol        │  │ Message         │  │ Schema       ││
│  │ Definition      │  │ Framing         │  │ Generation   ││
│  │ - JSON format   │  │ - Length prefix │  │ - OpenAI     ││
│  │ - Request/Resp  │  │ - Binary safety │  │ - Anthropic  ││
│  │ - Error format  │  │ - Streaming     │  │ - Custom     ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Versioning      │  │ Compression     │  │ Security     ││
│  │ - Protocol vers │  │ - Optional gzip │  │ - Validation ││
│  │ - Schema vers   │  │ - Efficient     │  │ - Sanitization││
│  │ - Compatibility │  │ - Large payloads│  │ - Rate limit ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### EXISTING PROTOCOL FOUNDATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule DSPex.PythonBridge.Protocol do
  @moduledoc """
  Wire protocol for Python bridge communication.
  """
  
  def encode_request(id, command, args) do
    request = %{
      id: id,
      command: to_string(command),
      args: args,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Jason.encode!(request)
  end
  
  def decode_response(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "success" => true, "result" => result}} ->
        {:ok, id, result}
      
      {:ok, %{"id" => id, "success" => false, "error" => error}} ->
        {:error, id, error}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### COMPREHENSIVE WIRE PROTOCOL IMPLEMENTATION

**Enhanced Protocol with Versioning and Validation:**
```elixir
defmodule DSPex.Protocol.WireProtocol do
  @moduledoc """
  Comprehensive wire protocol for communication with external systems.
  Supports versioning, compression, validation, and multiple message types.
  """
  
  alias DSPex.Protocol.{MessageFraming, Validation, Compression}
  
  @protocol_version "1.0"
  @supported_versions ["1.0"]
  @max_message_size 100 * 1024 * 1024  # 100MB
  
  @type message_type :: :request | :response | :notification | :stream
  @type protocol_options :: %{
    version: String.t(),
    compression: boolean(),
    validate: boolean(),
    timeout: pos_integer()
  }
  
  defstruct [
    :version,
    :message_id,
    :message_type,
    :timestamp,
    :payload,
    :compression,
    :checksum,
    :metadata
  ]
  
  @type t :: %__MODULE__{
    version: String.t(),
    message_id: String.t(),
    message_type: message_type(),
    timestamp: DateTime.t(),
    payload: term(),
    compression: boolean(),
    checksum: String.t() | nil,
    metadata: map()
  }
  
  def encode_message(payload, opts \\ %{}) do
    message = create_message(payload, opts)
    
    with {:ok, validated_message} <- validate_message(message, opts),
         {:ok, serialized} <- serialize_message(validated_message, opts),
         {:ok, compressed} <- maybe_compress(serialized, opts),
         {:ok, framed} <- MessageFraming.frame_message(compressed, opts) do
      {:ok, framed}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  def decode_message(data, opts \\ %{}) do
    with {:ok, unframed} <- MessageFraming.unframe_message(data, opts),
         {:ok, decompressed} <- maybe_decompress(unframed, opts),
         {:ok, message} <- deserialize_message(decompressed, opts),
         {:ok, validated} <- validate_message(message, opts) do
      {:ok, validated}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp create_message(payload, opts) do
    version = Map.get(opts, :version, @protocol_version)
    compression = Map.get(opts, :compression, false)
    message_type = Map.get(opts, :message_type, :request)
    
    %__MODULE__{
      version: version,
      message_id: generate_message_id(),
      message_type: message_type,
      timestamp: DateTime.utc_now(),
      payload: payload,
      compression: compression,
      metadata: Map.get(opts, :metadata, %{})
    }
  end
  
  defp validate_message(message, opts) do
    if Map.get(opts, :validate, true) do
      Validation.validate_message(message)
    else
      {:ok, message}
    end
  end
  
  defp serialize_message(message, _opts) do
    try do
      serialized = Jason.encode!(%{
        version: message.version,
        message_id: message.message_id,
        message_type: message.message_type,
        timestamp: DateTime.to_iso8601(message.timestamp),
        payload: message.payload,
        compression: message.compression,
        metadata: message.metadata
      })
      
      checksum = calculate_checksum(serialized)
      
      final_message = Jason.encode!(%{
        data: serialized,
        checksum: checksum
      })
      
      {:ok, final_message}
    rescue
      error -> {:error, "Serialization failed: #{inspect(error)}"}
    end
  end
  
  defp deserialize_message(data, _opts) do
    try do
      case Jason.decode(data) do
        {:ok, %{"data" => serialized_data, "checksum" => checksum}} ->
          if verify_checksum(serialized_data, checksum) do
            case Jason.decode(serialized_data) do
              {:ok, message_data} ->
                message = %__MODULE__{
                  version: message_data["version"],
                  message_id: message_data["message_id"],
                  message_type: String.to_existing_atom(message_data["message_type"]),
                  timestamp: DateTime.from_iso8601!(message_data["timestamp"]),
                  payload: message_data["payload"],
                  compression: message_data["compression"],
                  checksum: checksum,
                  metadata: message_data["metadata"] || %{}
                }
                {:ok, message}
              
              {:error, reason} ->
                {:error, "Inner deserialization failed: #{inspect(reason)}"}
            end
          else
            {:error, "Checksum verification failed"}
          end
        
        {:ok, _} ->
          {:error, "Invalid message format"}
        
        {:error, reason} ->
          {:error, "JSON decode failed: #{inspect(reason)}"}
      end
    rescue
      error -> {:error, "Deserialization failed: #{inspect(error)}"}
    end
  end
  
  defp maybe_compress(data, opts) do
    if Map.get(opts, :compression, false) do
      Compression.compress(data)
    else
      {:ok, data}
    end
  end
  
  defp maybe_decompress(data, opts) do
    if Map.get(opts, :compression, false) do
      Compression.decompress(data)
    else
      {:ok, data}
    end
  end
  
  defp generate_message_id do
    Ash.UUID.generate()
  end
  
  defp calculate_checksum(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
  
  defp verify_checksum(data, expected_checksum) do
    actual_checksum = calculate_checksum(data)
    actual_checksum == expected_checksum
  end
  
  def create_request(command, args, opts \\ %{}) do
    payload = %{
      command: to_string(command),
      args: args
    }
    
    opts = Map.put(opts, :message_type, :request)
    encode_message(payload, opts)
  end
  
  def create_response(request_id, result, opts \\ %{}) do
    payload = %{
      request_id: request_id,
      success: true,
      result: result
    }
    
    opts = Map.put(opts, :message_type, :response)
    encode_message(payload, opts)
  end
  
  def create_error_response(request_id, error, opts \\ %{}) do
    payload = %{
      request_id: request_id,
      success: false,
      error: format_error(error)
    }
    
    opts = Map.put(opts, :message_type, :response)
    encode_message(payload, opts)
  end
  
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
  
  def supported_versions, do: @supported_versions
  def current_version, do: @protocol_version
  def max_message_size, do: @max_message_size
end
```

### MESSAGE FRAMING IMPLEMENTATION

**Binary Message Framing with Length Prefix:**
```elixir
defmodule DSPex.Protocol.MessageFraming do
  @moduledoc """
  Message framing for reliable binary communication.
  Supports length-prefixed messages with optional compression indicators.
  """
  
  @length_header_size 4
  @compression_flag_size 1
  @version_size 2
  @total_header_size @length_header_size + @compression_flag_size + @version_size
  
  def frame_message(data, opts \\ %{}) when is_binary(data) do
    compression_flag = if Map.get(opts, :compression, false), do: 1, else: 0
    version = Map.get(opts, :protocol_version, 1)
    
    data_length = byte_size(data)
    
    if data_length > DSPex.Protocol.WireProtocol.max_message_size() do
      {:error, "Message too large: #{data_length} bytes"}
    else
      header = <<
        data_length::big-unsigned-32,
        compression_flag::8,
        version::big-unsigned-16
      >>
      
      framed_message = header <> data
      {:ok, framed_message}
    end
  end
  
  def unframe_message(data, _opts \\ %{}) when is_binary(data) do
    case data do
      <<length::big-unsigned-32, compression_flag::8, version::big-unsigned-16, payload::binary>> ->
        if byte_size(payload) == length do
          compression = compression_flag == 1
          
          {:ok, %{
            payload: payload,
            compression: compression,
            version: version,
            length: length
          }}
        else
          {:error, "Payload length mismatch: expected #{length}, got #{byte_size(payload)}"}
        end
      
      _ when byte_size(data) < @total_header_size ->
        {:error, "Incomplete header: #{byte_size(data)} bytes"}
      
      _ ->
        {:error, "Invalid frame format"}
    end
  end
  
  def frame_streaming_message(data, chunk_id, total_chunks, opts \\ %{}) do
    # For streaming large messages
    metadata = %{
      chunk_id: chunk_id,
      total_chunks: total_chunks,
      streaming: true
    }
    
    opts = Map.put(opts, :metadata, metadata)
    frame_message(data, opts)
  end
  
  def calculate_frame_overhead do
    @total_header_size
  end
  
  def max_payload_size do
    DSPex.Protocol.WireProtocol.max_message_size() - @total_header_size
  end
end
```

### PROTOCOL VALIDATION SYSTEM

**Comprehensive Message Validation:**
```elixir
defmodule DSPex.Protocol.Validation do
  @moduledoc """
  Validation system for wire protocol messages.
  Ensures message integrity, format compliance, and security.
  """
  
  alias DSPex.Protocol.WireProtocol
  
  def validate_message(%WireProtocol{} = message) do
    validations = [
      {:version, &validate_version/1},
      {:message_id, &validate_message_id/1},
      {:message_type, &validate_message_type/1},
      {:timestamp, &validate_timestamp/1},
      {:payload, &validate_payload/1},
      {:metadata, &validate_metadata/1}
    ]
    
    case run_validations(message, validations) do
      :ok -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp run_validations(message, validations) do
    Enum.reduce_while(validations, :ok, fn {field, validator}, _acc ->
      field_value = Map.get(message, field)
      
      case validator.(field_value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "#{field} validation failed: #{reason}"}}
      end
    end)
  end
  
  defp validate_version(version) when is_binary(version) do
    if version in WireProtocol.supported_versions() do
      :ok
    else
      {:error, "Unsupported version: #{version}"}
    end
  end
  
  defp validate_version(_), do: {:error, "Version must be a string"}
  
  defp validate_message_id(message_id) when is_binary(message_id) do
    case Ash.UUID.info(message_id) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Invalid UUID format"}
    end
  end
  
  defp validate_message_id(_), do: {:error, "Message ID must be a UUID string"}
  
  defp validate_message_type(type) when type in [:request, :response, :notification, :stream] do
    :ok
  end
  
  defp validate_message_type(type), do: {:error, "Invalid message type: #{inspect(type)}"}
  
  defp validate_timestamp(%DateTime{} = _timestamp), do: :ok
  defp validate_timestamp(_), do: {:error, "Timestamp must be a DateTime"}
  
  defp validate_payload(payload) when is_map(payload) do
    # Validate payload structure based on message type
    validate_payload_structure(payload)
  end
  
  defp validate_payload(_), do: {:error, "Payload must be a map"}
  
  defp validate_payload_structure(%{"command" => command, "args" => args}) 
       when is_binary(command) and is_map(args) do
    # Request payload validation
    validate_command_args(command, args)
  end
  
  defp validate_payload_structure(%{"request_id" => request_id, "success" => success}) 
       when is_binary(request_id) and is_boolean(success) do
    # Response payload validation
    :ok
  end
  
  defp validate_payload_structure(_payload) do
    # Allow other payload structures for flexibility
    :ok
  end
  
  defp validate_command_args(command, args) do
    # Validate specific command arguments
    case command do
      "create_program" -> validate_create_program_args(args)
      "execute_program" -> validate_execute_program_args(args)
      "list_programs" -> :ok  # No args needed
      _ -> :ok  # Allow unknown commands for extensibility
    end
  end
  
  defp validate_create_program_args(args) do
    required_keys = ["id", "signature"]
    missing_keys = required_keys -- Map.keys(args)
    
    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, "Missing required keys: #{inspect(missing_keys)}"}
    end
  end
  
  defp validate_execute_program_args(args) do
    required_keys = ["program_id", "inputs"]
    missing_keys = required_keys -- Map.keys(args)
    
    if Enum.empty?(missing_keys) do
      :ok
    else
      {:error, "Missing required keys: #{inspect(missing_keys)}"}
    end
  end
  
  defp validate_metadata(metadata) when is_map(metadata), do: :ok
  defp validate_metadata(_), do: {:error, "Metadata must be a map"}
  
  def validate_json_payload(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, _decoded} -> :ok
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end
  
  def sanitize_payload(payload) when is_map(payload) do
    # Remove potentially dangerous fields and sanitize values
    payload
    |> remove_dangerous_keys()
    |> sanitize_string_values()
    |> limit_payload_size()
  end
  
  defp remove_dangerous_keys(payload) do
    dangerous_keys = ["__proto__", "constructor", "prototype", "__dirname", "__filename"]
    Map.drop(payload, dangerous_keys)
  end
  
  defp sanitize_string_values(payload) do
    Map.new(payload, fn
      {key, value} when is_binary(value) ->
        sanitized_value = value
                         |> String.replace(~r/[<>\"'&]/, "")  # Remove potentially dangerous chars
                         |> String.slice(0, 10000)  # Limit string length
        {key, sanitized_value}
      
      {key, value} when is_map(value) ->
        {key, sanitize_string_values(value)}
      
      {key, value} when is_list(value) ->
        {key, Enum.map(value, fn
          item when is_map(item) -> sanitize_string_values(item)
          item when is_binary(item) -> String.slice(item, 0, 1000)
          item -> item
        end)}
      
      {key, value} ->
        {key, value}
    end)
  end
  
  defp limit_payload_size(payload) do
    encoded_size = Jason.encode!(payload) |> byte_size()
    max_size = 50 * 1024 * 1024  # 50MB limit for payload
    
    if encoded_size > max_size do
      %{"error" => "Payload too large", "size" => encoded_size, "max_size" => max_size}
    else
      payload
    end
  end
end
```

### COMPRESSION SUPPORT

**Optional Message Compression:**
```elixir
defmodule DSPex.Protocol.Compression do
  @moduledoc """
  Optional compression support for large messages.
  Uses gzip compression with configurable thresholds.
  """
  
  @compression_threshold 1024  # Compress messages larger than 1KB
  @compression_level 6  # Balance between speed and compression ratio
  
  def compress(data) when is_binary(data) do
    if byte_size(data) > @compression_threshold do
      try do
        compressed = :zlib.gzip(data, @compression_level)
        
        # Only use compression if it actually reduces size
        if byte_size(compressed) < byte_size(data) do
          {:ok, compressed}
        else
          {:ok, data}  # Return original if compression doesn't help
        end
      rescue
        error -> {:error, "Compression failed: #{inspect(error)}"}
      end
    else
      {:ok, data}
    end
  end
  
  def compress(data), do: {:error, "Data must be binary"}
  
  def decompress(data) when is_binary(data) do
    try do
      # Try to decompress; if it fails, assume data wasn't compressed
      case :zlib.gunzip(data) do
        decompressed when is_binary(decompressed) ->
          {:ok, decompressed}
        _ ->
          {:ok, data}  # Return original if not compressed
      end
    rescue
      # If decompression fails, return original data
      _error -> {:ok, data}
    end
  end
  
  def decompress(data), do: {:error, "Data must be binary"}
  
  def should_compress?(data) when is_binary(data) do
    byte_size(data) > @compression_threshold
  end
  
  def should_compress?(_), do: false
  
  def estimate_compression_ratio(data) when is_binary(data) do
    if byte_size(data) > @compression_threshold do
      try do
        compressed = :zlib.gzip(data, @compression_level)
        original_size = byte_size(data)
        compressed_size = byte_size(compressed)
        
        ratio = compressed_size / original_size
        {:ok, ratio}
      rescue
        _ -> {:error, "Failed to estimate compression"}
      end
    else
      {:ok, 1.0}  # No compression benefit for small data
    end
  end
  
  def compression_stats(data) when is_binary(data) do
    original_size = byte_size(data)
    
    case compress(data) do
      {:ok, compressed} ->
        compressed_size = byte_size(compressed)
        
        %{
          original_size: original_size,
          compressed_size: compressed_size,
          compression_ratio: compressed_size / original_size,
          space_saved: original_size - compressed_size,
          space_saved_percent: ((original_size - compressed_size) / original_size) * 100
        }
      
      {:error, reason} ->
        %{error: reason}
    end
  end
end
```

### JSON SCHEMA GENERATION SYSTEM

**Multi-Provider JSON Schema Generation:**
```elixir
defmodule DSPex.Protocol.JsonSchema do
  @moduledoc """
  Comprehensive JSON schema generation for multiple providers and use cases.
  Supports OpenAI, Anthropic, Google, and custom schema formats.
  """
  
  alias DSPex.Types.{Registry, Serializer}
  
  @providers [:openai, :anthropic, :google, :custom]
  @schema_version "2020-12"
  
  def generate_schema(signature_module, provider \\ :openai, opts \\ %{}) do
    with {:ok, signature} <- load_signature(signature_module),
         {:ok, base_schema} <- create_base_schema(signature, provider, opts),
         {:ok, enhanced_schema} <- enhance_schema(base_schema, provider, opts),
         {:ok, validated_schema} <- validate_schema(enhanced_schema, provider) do
      {:ok, validated_schema}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp load_signature(signature_module) do
    try do
      signature = signature_module.__signature__()
      {:ok, signature}
    rescue
      error -> {:error, "Failed to load signature: #{inspect(error)}"}
    end
  end
  
  defp create_base_schema(signature, provider, opts) do
    case provider do
      :openai -> create_openai_schema(signature, opts)
      :anthropic -> create_anthropic_schema(signature, opts)
      :google -> create_google_schema(signature, opts)
      :custom -> create_custom_schema(signature, opts)
      _ -> {:error, "Unsupported provider: #{provider}"}
    end
  end
  
  defp create_openai_schema(signature, opts) do
    properties = create_properties(signature.inputs ++ signature.outputs, :openai, opts)
    required_fields = get_required_fields(signature.inputs ++ signature.outputs)
    
    schema = %{
      type: "object",
      properties: properties,
      required: required_fields,
      additionalProperties: false
    }
    
    schema = maybe_add_description(schema, opts)
    schema = maybe_add_examples(schema, signature, opts)
    
    {:ok, schema}
  end
  
  defp create_anthropic_schema(signature, opts) do
    # Anthropic uses similar structure but with some differences
    properties = create_properties(signature.inputs ++ signature.outputs, :anthropic, opts)
    required_fields = get_required_fields(signature.inputs ++ signature.outputs)
    
    schema = %{
      type: "object",
      properties: properties,
      required: required_fields
    }
    
    # Anthropic prefers descriptions over examples
    schema = maybe_add_description(schema, opts)
    schema = maybe_add_anthropic_hints(schema, signature, opts)
    
    {:ok, schema}
  end
  
  defp create_google_schema(signature, opts) do
    # Google Vertex AI schema format
    properties = create_properties(signature.inputs ++ signature.outputs, :google, opts)
    required_fields = get_required_fields(signature.inputs ++ signature.outputs)
    
    schema = %{
      type: "object",
      properties: properties,
      required: required_fields,
      "$schema" => "https://json-schema.org/draft/#{@schema_version}/schema"
    }
    
    schema = maybe_add_description(schema, opts)
    
    {:ok, schema}
  end
  
  defp create_custom_schema(signature, opts) do
    # Flexible custom schema format
    properties = create_properties(signature.inputs ++ signature.outputs, :custom, opts)
    required_fields = get_required_fields(signature.inputs ++ signature.outputs)
    
    base_schema = %{
      type: "object",
      properties: properties,
      required: required_fields,
      "$schema" => "https://json-schema.org/draft/#{@schema_version}/schema"
    }
    
    # Add custom fields from options
    custom_fields = Map.get(opts, :custom_fields, %{})
    schema = Map.merge(base_schema, custom_fields)
    
    {:ok, schema}
  end
  
  defp create_properties(fields, provider, opts) do
    Enum.reduce(fields, %{}, fn {name, type, constraints}, acc ->
      case create_field_schema(name, type, constraints, provider, opts) do
        {:ok, field_schema} ->
          Map.put(acc, name, field_schema)
        
        {:error, reason} ->
          Logger.warning("Failed to create schema for field #{name}: #{reason}")
          acc
      end
    end)
  end
  
  defp create_field_schema(name, type, constraints, provider, opts) do
    case Registry.get_type_info(type) do
      nil ->
        {:error, "Unknown type: #{inspect(type)}"}
      
      type_info ->
        base_schema = type_info.json_schema
        enhanced_schema = apply_constraints_to_schema(base_schema, type, constraints)
        provider_schema = apply_provider_specific_enhancements(enhanced_schema, type, provider)
        
        # Add field-specific metadata
        final_schema = maybe_add_field_description(provider_schema, name, opts)
        
        {:ok, final_schema}
    end
  end
  
  defp apply_constraints_to_schema(schema, type, constraints) do
    Enum.reduce(constraints, schema, fn {constraint, value}, acc ->
      apply_constraint_to_schema(acc, type, constraint, value)
    end)
  end
  
  defp apply_constraint_to_schema(schema, :string, :min_length, value) do
    Map.put(schema, :minLength, value)
  end
  
  defp apply_constraint_to_schema(schema, :string, :max_length, value) do
    Map.put(schema, :maxLength, value)
  end
  
  defp apply_constraint_to_schema(schema, :string, :pattern, %Regex{} = regex) do
    Map.put(schema, :pattern, Regex.source(regex))
  end
  
  defp apply_constraint_to_schema(schema, :string, :format, value) do
    Map.put(schema, :format, value)
  end
  
  defp apply_constraint_to_schema(schema, type, :min, value) when type in [:integer, :float] do
    Map.put(schema, :minimum, value)
  end
  
  defp apply_constraint_to_schema(schema, type, :max, value) when type in [:integer, :float] do
    Map.put(schema, :maximum, value)
  end
  
  defp apply_constraint_to_schema(schema, :integer, :multiple_of, value) do
    Map.put(schema, :multipleOf, value)
  end
  
  defp apply_constraint_to_schema(schema, :atom, :one_of, values) do
    string_values = Enum.map(values, &to_string/1)
    Map.put(schema, :enum, string_values)
  end
  
  defp apply_constraint_to_schema(schema, {:list, _inner}, :min_length, value) do
    Map.put(schema, :minItems, value)
  end
  
  defp apply_constraint_to_schema(schema, {:list, _inner}, :max_length, value) do
    Map.put(schema, :maxItems, value)
  end
  
  defp apply_constraint_to_schema(schema, {:list, _inner}, :unique, true) do
    Map.put(schema, :uniqueItems, true)
  end
  
  defp apply_constraint_to_schema(schema, :embedding, :dimensions, value) do
    schema
    |> Map.put(:minItems, value)
    |> Map.put(:maxItems, value)
  end
  
  defp apply_constraint_to_schema(schema, _type, _constraint, _value) do
    # Unknown constraint, return schema unchanged
    schema
  end
  
  defp apply_provider_specific_enhancements(schema, type, provider) do
    case provider do
      :openai -> apply_openai_enhancements(schema, type)
      :anthropic -> apply_anthropic_enhancements(schema, type)
      :google -> apply_google_enhancements(schema, type)
      :custom -> schema
    end
  end
  
  defp apply_openai_enhancements(schema, :embedding) do
    schema
    |> Map.put(:description, "Vector embedding as array of floats")
    |> Map.put_new(:minItems, 1)
    |> Map.put_new(:maxItems, 4096)  # Common embedding dimension limit
  end
  
  defp apply_openai_enhancements(schema, :reasoning_chain) do
    Map.put(schema, :description, "Step-by-step reasoning as array of strings")
  end
  
  defp apply_openai_enhancements(schema, :probability) do
    schema
    |> Map.put(:description, "Probability value between 0 and 1")
    |> Map.put(:minimum, 0.0)
    |> Map.put(:maximum, 1.0)
  end
  
  defp apply_openai_enhancements(schema, _type), do: schema
  
  defp apply_anthropic_enhancements(schema, :embedding) do
    Map.put(schema, :description, "Numerical vector representation")
  end
  
  defp apply_anthropic_enhancements(schema, :reasoning_chain) do
    Map.put(schema, :description, "Sequential reasoning steps")
  end
  
  defp apply_anthropic_enhancements(schema, _type), do: schema
  
  defp apply_google_enhancements(schema, :embedding) do
    schema
    |> Map.put(:description, "Dense vector representation")
    |> Map.put(:format, "float-array")
  end
  
  defp apply_google_enhancements(schema, _type), do: schema
  
  defp get_required_fields(fields) do
    Enum.map(fields, fn {name, _type, _constraints} -> name end)
  end
  
  defp maybe_add_description(schema, opts) do
    case Map.get(opts, :description) do
      nil -> schema
      description -> Map.put(schema, :description, description)
    end
  end
  
  defp maybe_add_examples(schema, signature, opts) do
    case Map.get(opts, :examples) do
      nil ->
        # Generate example based on signature
        generated_example = generate_example_from_signature(signature)
        Map.put(schema, :examples, [generated_example])
      
      examples when is_list(examples) ->
        Map.put(schema, :examples, examples)
      
      example ->
        Map.put(schema, :examples, [example])
    end
  end
  
  defp maybe_add_anthropic_hints(schema, signature, _opts) do
    # Anthropic-specific enhancements
    hints = %{
      "input_fields" => length(signature.inputs),
      "output_fields" => length(signature.outputs),
      "complexity" => calculate_signature_complexity(signature)
    }
    
    Map.put(schema, :anthropic_hints, hints)
  end
  
  defp maybe_add_field_description(schema, field_name, opts) do
    field_descriptions = Map.get(opts, :field_descriptions, %{})
    
    case Map.get(field_descriptions, field_name) do
      nil -> schema
      description -> Map.put(schema, :description, description)
    end
  end
  
  defp generate_example_from_signature(signature) do
    all_fields = signature.inputs ++ signature.outputs
    
    Enum.reduce(all_fields, %{}, fn {name, type, _constraints}, acc ->
      example_value = generate_example_value(type)
      Map.put(acc, name, example_value)
    end)
  end
  
  defp generate_example_value(:string), do: "example text"
  defp generate_example_value(:integer), do: 42
  defp generate_example_value(:float), do: 3.14
  defp generate_example_value(:boolean), do: true
  defp generate_example_value(:probability), do: 0.75
  defp generate_example_value(:confidence_score), do: 0.85
  defp generate_example_value(:embedding), do: [0.1, 0.2, 0.3, 0.4, 0.5]
  defp generate_example_value(:reasoning_chain), do: ["analyze input", "apply logic", "generate output"]
  defp generate_example_value({:list, inner_type}) do
    [generate_example_value(inner_type), generate_example_value(inner_type)]
  end
  defp generate_example_value({:dict, _key_type, value_type}) do
    %{"key1" => generate_example_value(value_type), "key2" => generate_example_value(value_type)}
  end
  defp generate_example_value(_), do: "example"
  
  defp calculate_signature_complexity(signature) do
    all_fields = signature.inputs ++ signature.outputs
    
    base_complexity = length(all_fields)
    type_complexity = Enum.sum(Enum.map(all_fields, fn {_name, type, _constraints} ->
      case type do
        basic when basic in [:string, :integer, :float, :boolean] -> 1
        ml when ml in [:embedding, :probability, :confidence_score] -> 2
        {:list, _} -> 3
        {:dict, _, _} -> 4
        {:union, types} -> length(types)
        _ -> 2
      end
    end))
    
    # Normalize to 1-10 scale
    normalized = min(10, (base_complexity + type_complexity) / 5)
    round(normalized)
  end
  
  defp enhance_schema(schema, provider, opts) do
    # Apply additional enhancements based on options
    enhanced = schema
    
    enhanced = if Map.get(opts, :strict_mode, false) do
      Map.put(enhanced, :additionalProperties, false)
    else
      enhanced
    end
    
    enhanced = if version = Map.get(opts, :schema_version) do
      Map.put(enhanced, :"$schema", "https://json-schema.org/draft/#{version}/schema")
    else
      enhanced
    end
    
    enhanced = if title = Map.get(opts, :title) do
      Map.put(enhanced, :title, title)
    else
      enhanced
    end
    
    {:ok, enhanced}
  end
  
  defp validate_schema(schema, provider) do
    # Basic schema validation
    required_fields = case provider do
      :openai -> [:type, :properties]
      :anthropic -> [:type, :properties]
      :google -> [:type, :properties]
      :custom -> [:type]
    end
    
    missing_fields = Enum.filter(required_fields, &(not Map.has_key?(schema, &1)))
    
    if Enum.empty?(missing_fields) do
      {:ok, schema}
    else
      {:error, "Missing required schema fields: #{inspect(missing_fields)}"}
    end
  end
  
  def validate_against_schema(data, schema) do
    # Basic validation of data against generated schema
    try do
      case ExJsonSchema.Validator.validate(schema, data) do
        :ok -> {:ok, data}
        {:error, errors} -> {:error, "Schema validation failed: #{inspect(errors)}"}
      end
    rescue
      error -> {:error, "Schema validation exception: #{inspect(error)}"}
    end
  end
  
  def supported_providers, do: @providers
  def schema_version, do: @schema_version
end
```

### COMPREHENSIVE TESTING FRAMEWORK

**Wire Protocol and JSON Schema Testing:**
```elixir
defmodule DSPex.Protocol.WireProtocolTest do
  use ExUnit.Case
  
  alias DSPex.Protocol.{WireProtocol, MessageFraming, Validation, Compression, JsonSchema}
  
  defmodule TestSignature do
    use DSPex.Signature
    
    signature question: :string, context: {:list, :string} -> 
             answer: :string, confidence: :probability, reasoning: :reasoning_chain
  end
  
  describe "wire protocol encoding/decoding" do
    test "encodes and decodes basic messages" do
      payload = %{command: "test", args: %{param: "value"}}
      
      {:ok, encoded} = WireProtocol.encode_message(payload)
      {:ok, decoded} = WireProtocol.decode_message(encoded)
      
      assert decoded.payload == payload
      assert decoded.version == WireProtocol.current_version()
      assert decoded.message_type == :request
    end
    
    test "handles compression" do
      large_payload = %{
        command: "test",
        args: %{
          data: String.duplicate("x", 2000)  # Large enough to trigger compression
        }
      }
      
      opts = %{compression: true}
      
      {:ok, encoded} = WireProtocol.encode_message(large_payload, opts)
      {:ok, decoded} = WireProtocol.decode_message(encoded, opts)
      
      assert decoded.payload == large_payload
      assert decoded.compression == true
    end
    
    test "validates message integrity with checksum" do
      payload = %{command: "test", args: %{}}
      
      {:ok, encoded} = WireProtocol.encode_message(payload)
      
      # Corrupt the message
      corrupted = String.replace(encoded, "test", "xxxx", global: false)
      
      {:error, reason} = WireProtocol.decode_message(corrupted)
      assert reason =~ "checksum"
    end
    
    test "rejects oversized messages" do
      huge_payload = %{
        command: "test",
        args: %{
          data: String.duplicate("x", 200 * 1024 * 1024)  # 200MB
        }
      }
      
      {:error, reason} = WireProtocol.encode_message(huge_payload)
      assert reason =~ "too large"
    end
    
    test "handles different message types" do
      request_payload = %{command: "test", args: %{}}
      response_payload = %{request_id: "123", success: true, result: %{}}
      
      {:ok, request_encoded} = WireProtocol.encode_message(request_payload, %{message_type: :request})
      {:ok, response_encoded} = WireProtocol.encode_message(response_payload, %{message_type: :response})
      
      {:ok, decoded_request} = WireProtocol.decode_message(request_encoded)
      {:ok, decoded_response} = WireProtocol.decode_message(response_encoded)
      
      assert decoded_request.message_type == :request
      assert decoded_response.message_type == :response
    end
  end
  
  describe "message framing" do
    test "frames and unframes messages correctly" do
      data = "test message data"
      
      {:ok, framed} = MessageFraming.frame_message(data)
      {:ok, unframed} = MessageFraming.unframe_message(framed)
      
      assert unframed.payload == data
      assert unframed.compression == false
    end
    
    test "handles compression flag in framing" do
      data = "test message data"
      opts = %{compression: true}
      
      {:ok, framed} = MessageFraming.frame_message(data, opts)
      {:ok, unframed} = MessageFraming.unframe_message(framed)
      
      assert unframed.compression == true
    end
    
    test "rejects malformed frames" do
      invalid_frame = <<1, 2, 3>>  # Too short
      
      {:error, reason} = MessageFraming.unframe_message(invalid_frame)
      assert reason =~ "Incomplete header"
    end
    
    test "detects payload length mismatches" do
      # Create a frame with incorrect length
      data = "short"
      fake_length = 1000
      
      malformed_frame = <<fake_length::big-unsigned-32, 0::8, 1::big-unsigned-16>> <> data
      
      {:error, reason} = MessageFraming.unframe_message(malformed_frame)
      assert reason =~ "length mismatch"
    end
  end
  
  describe "message validation" do
    test "validates correct messages" do
      message = %WireProtocol{
        version: "1.0",
        message_id: Ash.UUID.generate(),
        message_type: :request,
        timestamp: DateTime.utc_now(),
        payload: %{command: "test", args: %{}},
        compression: false,
        metadata: %{}
      }
      
      {:ok, validated} = Validation.validate_message(message)
      assert validated == message
    end
    
    test "rejects invalid versions" do
      message = %WireProtocol{
        version: "99.0",  # Unsupported version
        message_id: Ash.UUID.generate(),
        message_type: :request,
        timestamp: DateTime.utc_now(),
        payload: %{},
        compression: false,
        metadata: %{}
      }
      
      {:error, reason} = Validation.validate_message(message)
      assert reason =~ "version"
    end
    
    test "rejects invalid UUIDs" do
      message = %WireProtocol{
        version: "1.0",
        message_id: "not-a-uuid",
        message_type: :request,
        timestamp: DateTime.utc_now(),
        payload: %{},
        compression: false,
        metadata: %{}
      }
      
      {:error, reason} = Validation.validate_message(message)
      assert reason =~ "UUID"
    end
    
    test "sanitizes dangerous payload content" do
      dangerous_payload = %{
        "__proto__" => "malicious",
        "normal_field" => "<script>alert('xss')</script>",
        "nested" => %{
          "constructor" => "bad",
          "safe_field" => "good"
        }
      }
      
      sanitized = Validation.sanitize_payload(dangerous_payload)
      
      refute Map.has_key?(sanitized, "__proto__")
      refute Map.has_key?(sanitized["nested"], "constructor")
      assert sanitized["normal_field"] =~ "scriptalert('xss')/script"  # Dangerous chars removed
      assert sanitized["nested"]["safe_field"] == "good"
    end
  end
  
  describe "compression" do
    test "compresses large data effectively" do
      large_data = String.duplicate("repetitive data ", 1000)
      
      {:ok, compressed} = Compression.compress(large_data)
      {:ok, decompressed} = Compression.decompress(compressed)
      
      assert decompressed == large_data
      assert byte_size(compressed) < byte_size(large_data)
    end
    
    test "skips compression for small data" do
      small_data = "small"
      
      {:ok, result} = Compression.compress(small_data)
      assert result == small_data  # Should return original for small data
    end
    
    test "handles compression statistics" do
      data = String.duplicate("compress me ", 500)
      
      stats = Compression.compression_stats(data)
      
      assert stats.original_size > 0
      assert stats.compressed_size > 0
      assert stats.compression_ratio < 1.0
      assert stats.space_saved > 0
      assert stats.space_saved_percent > 0
    end
  end
  
  describe "JSON schema generation" do
    test "generates OpenAI compatible schema" do
      {:ok, schema} = JsonSchema.generate_schema(TestSignature, :openai)
      
      assert schema.type == "object"
      assert Map.has_key?(schema.properties, :question)
      assert Map.has_key?(schema.properties, :answer)
      assert Map.has_key?(schema.properties, :confidence)
      
      # Check that confidence is properly constrained as probability
      confidence_schema = schema.properties.confidence
      assert confidence_schema.type == "number"
      assert confidence_schema.minimum == 0.0
      assert confidence_schema.maximum == 1.0
    end
    
    test "generates Anthropic compatible schema" do
      {:ok, schema} = JsonSchema.generate_schema(TestSignature, :anthropic)
      
      assert schema.type == "object"
      assert Map.has_key?(schema.properties, :reasoning)
      
      # Anthropic schemas shouldn't have examples
      refute Map.has_key?(schema, :examples)
      
      # But should have hints
      assert Map.has_key?(schema, :anthropic_hints)
    end
    
    test "applies constraints to schema fields" do
      defmodule ConstrainedSignature do
        use DSPex.Signature
        
        signature name: {:string, min_length: 2, max_length: 50} -> 
                 score: {:integer, min: 0, max: 100}
      end
      
      {:ok, schema} = JsonSchema.generate_schema(ConstrainedSignature, :openai)
      
      name_schema = schema.properties.name
      assert name_schema.minLength == 2
      assert name_schema.maxLength == 50
      
      score_schema = schema.properties.score
      assert score_schema.minimum == 0
      assert score_schema.maximum == 100
    end
    
    test "handles complex nested types" do
      defmodule NestedSignature do
        use DSPex.Signature
        
        signature items: {:list, :string}, config: {:dict, :string, :integer} -> 
                 results: {:list, :map}
      end
      
      {:ok, schema} = JsonSchema.generate_schema(NestedSignature, :openai)
      
      items_schema = schema.properties.items
      assert items_schema.type == "array"
      assert items_schema.items.type == "string"
      
      config_schema = schema.properties.config
      assert config_schema.type == "object"
      assert config_schema.additionalProperties.type == "integer"
    end
    
    test "validates data against generated schema" do
      {:ok, schema} = JsonSchema.generate_schema(TestSignature, :openai)
      
      valid_data = %{
        question: "What is AI?",
        context: ["machine learning", "neural networks"],
        answer: "AI is artificial intelligence",
        confidence: 0.85,
        reasoning: ["analyzed question", "retrieved context", "generated answer"]
      }
      
      invalid_data = %{
        question: 123,  # Should be string
        confidence: 1.5  # Should be 0-1
      }
      
      # Note: This test assumes ExJsonSchema is available
      # {:ok, _} = JsonSchema.validate_against_schema(valid_data, schema)
      # {:error, _} = JsonSchema.validate_against_schema(invalid_data, schema)
    end
  end
  
  describe "protocol integration" do
    test "full round trip with compression and validation" do
      payload = %{
        command: "execute_program",
        args: %{
          program_id: "test-123",
          inputs: %{
            question: "Test question",
            context: ["context1", "context2"]
          }
        }
      }
      
      opts = %{
        compression: true,
        validate: true,
        message_type: :request
      }
      
      # Encode
      {:ok, encoded} = WireProtocol.encode_message(payload, opts)
      
      # Decode
      {:ok, decoded} = WireProtocol.decode_message(encoded, opts)
      
      assert decoded.payload == payload
      assert decoded.compression == true
      assert decoded.message_type == :request
    end
    
    test "handles protocol errors gracefully" do
      # Test various error conditions
      {:error, _} = WireProtocol.decode_message("invalid data")
      {:error, _} = WireProtocol.decode_message(<<1, 2, 3>>)  # Too short
      
      # Test oversized payload
      huge_payload = %{data: String.duplicate("x", 200 * 1024 * 1024)}
      {:error, _} = WireProtocol.encode_message(huge_payload)
    end
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the comprehensive wire protocol and JSON schema generation system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/protocol/
├── wire_protocol.ex         # Main protocol implementation
├── message_framing.ex       # Binary message framing
├── validation.ex            # Message validation and sanitization
├── compression.ex           # Optional compression support
├── json_schema.ex          # Multi-provider schema generation
├── versioning.ex           # Protocol versioning support
└── supervisor.ex           # Protocol system supervision

test/dspex/protocol/
├── wire_protocol_test.exs   # Protocol encoding/decoding tests
├── message_framing_test.exs # Framing and binary handling tests  
├── validation_test.exs      # Validation and security tests
├── compression_test.exs     # Compression functionality tests
├── json_schema_test.exs     # Schema generation tests
└── integration_test.exs     # End-to-end protocol tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Wire Protocol (`lib/dspex/protocol/wire_protocol.ex`)**:
   - Complete message encoding/decoding with versioning
   - Checksum validation for message integrity
   - Support for different message types (request/response/notification)
   - Comprehensive error handling and recovery

2. **Message Framing (`lib/dspex/protocol/message_framing.ex`)**:
   - Binary framing with length prefixes
   - Compression flag handling
   - Protocol version in frame headers
   - Streaming support for large messages

3. **Validation System (`lib/dspex/protocol/validation.ex`)**:
   - Message structure validation
   - Payload sanitization for security
   - Command argument validation
   - Size limits and safety checks

4. **Compression Support (`lib/dspex/protocol/compression.ex`)**:
   - Optional gzip compression for large messages
   - Intelligent compression decisions
   - Compression statistics and analysis
   - Fallback for incompressible data

5. **JSON Schema Generation (`lib/dspex/protocol/json_schema.ex`)**:
   - Multi-provider schema support (OpenAI, Anthropic, Google)
   - Constraint application to schemas
   - Example generation and validation
   - Custom schema format support

### QUALITY REQUIREMENTS:

- **Reliability**: Robust error handling and message integrity validation
- **Performance**: Efficient encoding/decoding with optional compression
- **Security**: Payload sanitization and validation
- **Compatibility**: Multi-provider schema generation
- **Extensibility**: Support for protocol versioning and new providers
- **Documentation**: Clear documentation for all protocol features
- **Testing**: Comprehensive test coverage for all scenarios

### INTEGRATION POINTS:

- Must integrate with Python bridge communication layer
- Should support type system for schema generation
- Must work with adapter pattern for external communications
- Should enable provider-specific optimizations
- Must support signature system for automatic schema creation

### SUCCESS CRITERIA:

1. Protocol encoding/decoding works reliably
2. Message framing handles binary data correctly
3. Validation catches security issues and malformed data
4. Compression reduces message size for large payloads
5. JSON schema generation supports all major providers
6. Protocol versioning enables backward compatibility
7. Error handling provides meaningful feedback
8. Performance meets requirements for high-throughput scenarios
9. All test scenarios pass with comprehensive coverage
10. Integration with other system components works seamlessly

This wire protocol and schema generation system provides the critical communication infrastructure that enables reliable, secure, and efficient data exchange between the DSPy-Ash integration and external systems.
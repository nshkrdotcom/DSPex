# gRPC Protocol Definition for Tool Bridge

## Overview

This document defines the complete gRPC protocol for the DSPex tool bridge, including all message types, service methods, and data serialization formats.

## Implementation Phases

To deliver value faster, we recommend implementing the service in phases:

### Phase 1: Core Tool Execution (V1)
- `InitializeSession` - Session setup
- `ExecuteTool` - Synchronous tool calls  
- `StreamTool` - Streaming tool execution
- `CleanupSession` - Resource cleanup

### Phase 2: Variable Integration
- `GetSessionVariable` - Read shared state
- `SetSessionVariable` - Write shared state

### Phase 3: Advanced Features
- `BatchExecuteTools` - Batch operations
- `CreateReActAgent` - Agent lifecycle
- `ExecuteAgent` - Agent execution

### Phase 4: Monitoring & Observability
- Remaining session management methods
- Variable watching capabilities
- Health and metrics endpoints

## Service Definition

```protobuf
syntax = "proto3";

package dspex.bridge;

import "google/protobuf/any.proto";
import "google/protobuf/struct.proto";
import "google/protobuf/timestamp.proto";

// Main service for bidirectional tool bridge
service SnakepitBridge {
    // Session Management
    rpc InitializeSession(InitializeSessionRequest) returns (InitializeSessionResponse);
    rpc CleanupSession(CleanupSessionRequest) returns (StatusResponse);
    rpc GetSessionInfo(GetSessionInfoRequest) returns (SessionInfo);
    
    // Tool Operations
    rpc GetSessionTools(GetSessionToolsRequest) returns (GetSessionToolsResponse);
    rpc ExecuteTool(ToolCallRequest) returns (ToolCallResponse);
    rpc StreamTool(ToolStreamRequest) returns (stream ToolStreamChunk);
    rpc BatchExecuteTools(BatchToolCallRequest) returns (BatchToolCallResponse);
    
    // Variable Operations (Integration with Variable Bridge)
    rpc GetSessionVariable(GetVariableRequest) returns (VariableResponse);
    rpc SetSessionVariable(SetVariableRequest) returns (StatusResponse);
    rpc ListSessionVariables(ListVariablesRequest) returns (ListVariablesResponse);
    rpc WatchSessionVariables(WatchVariablesRequest) returns (stream VariableUpdate);
    
    // Agent Operations
    rpc CreateReActAgent(CreateReActAgentRequest) returns (CreateReActAgentResponse);
    rpc ExecuteAgent(ExecuteAgentRequest) returns (stream AgentExecutionChunk);
    
    // Health and Monitoring
    rpc HealthCheck(HealthCheckRequest) returns (HealthCheckResponse);
    rpc GetMetrics(GetMetricsRequest) returns (MetricsResponse);
}
```

## Core Message Types

### Session Management

```protobuf
message InitializeSessionRequest {
    string session_id = 1;
    string callback_address = 2;  // gRPC address for Python->Elixir calls
    map<string, string> metadata = 3;
    SessionConfig config = 4;
}

message SessionConfig {
    int32 max_concurrent_tools = 1;
    int32 default_timeout_ms = 2;
    bool enable_caching = 3;
    bool enable_telemetry = 4;
}

message InitializeSessionResponse {
    bool success = 1;
    int32 tool_count = 2;
    repeated string capabilities = 3;  // ["streaming", "batch", "variables"]
    ErrorInfo error = 4;
}

message CleanupSessionRequest {
    string session_id = 1;
    bool force = 2;  // Force cleanup even with active operations
}

message GetSessionInfoRequest {
    string session_id = 1;
}

message SessionInfo {
    string session_id = 1;
    google.protobuf.Timestamp created_at = 2;
    google.protobuf.Timestamp last_activity = 3;
    int32 tool_count = 4;
    int32 variable_count = 5;
    int32 active_operations = 6;
    map<string, string> metadata = 7;
}
```

### Tool Specifications

```protobuf
enum ToolType {
    STANDARD = 0;
    STREAMING = 1;
    BATCH = 2;
    COMPOSITE = 3;
}

message ToolSpec {
    string tool_id = 1;
    string name = 2;
    string description = 3;
    ToolType type = 4;
    repeated ArgumentSpec arguments = 5;
    ArgumentSpec return_type = 6;
    map<string, string> metadata = 7;
    repeated string examples = 8;
    ValidationRules validation = 9;
    ResourceLimits limits = 10;
}

message ArgumentSpec {
    string name = 1;
    string python_type = 2;      // "str", "int", "List[str]", etc.
    string elixir_type = 3;      // "binary", "integer", "[binary]", etc.
    bool required = 4;
    string description = 5;
    google.protobuf.Any default_value = 6;
    repeated string allowed_values = 7;  // For enums
    ValidationRules validation = 8;
}

message ValidationRules {
    string pattern = 1;          // Regex pattern
    double min_value = 2;
    double max_value = 3;
    int32 min_length = 4;
    int32 max_length = 5;
    repeated string custom_rules = 6;  // Rule names to apply
}

message ResourceLimits {
    int32 timeout_ms = 1;
    int64 max_memory_bytes = 2;
    int32 max_concurrent_calls = 3;
    int32 rate_limit_per_minute = 4;
}
```

### Tool Execution

```protobuf
message ToolCallRequest {
    string session_id = 1;
    string tool_id = 2;
    repeated google.protobuf.Any args = 3;
    map<string, google.protobuf.Any> kwargs = 4;
    string request_id = 5;  // For tracking
    int32 timeout_ms = 6;   // Override default timeout
    map<string, string> context = 7;  // Additional context
}

message ToolCallResponse {
    bool success = 1;
    google.protobuf.Any result = 2;
    ErrorInfo error = 3;
    ExecutionMetrics metrics = 4;
    string request_id = 5;
}

message ToolStreamRequest {
    string session_id = 1;
    string tool_id = 2;
    repeated google.protobuf.Any args = 3;
    map<string, google.protobuf.Any> kwargs = 4;
    string stream_id = 5;
    StreamConfig config = 6;
}

message StreamConfig {
    int32 chunk_size = 1;
    int32 buffer_size = 2;
    bool backpressure_enabled = 3;
}

message ToolStreamChunk {
    string stream_id = 1;
    int32 sequence = 2;
    
    oneof content {
        google.protobuf.Any data = 3;
        StreamMetadata metadata = 4;
        CompleteSignal complete = 5;
        ErrorInfo error = 6;
    }
}

message StreamMetadata {
    string key = 1;
    google.protobuf.Any value = 2;
}

message CompleteSignal {
    int32 total_chunks = 1;
    ExecutionMetrics metrics = 2;
}
```

### Batch Operations

```protobuf
message BatchToolCallRequest {
    string session_id = 1;
    string batch_id = 2;
    repeated ToolCallItem items = 3;
    BatchConfig config = 4;
}

message ToolCallItem {
    int32 index = 1;
    string tool_id = 2;
    repeated google.protobuf.Any args = 3;
    map<string, google.protobuf.Any> kwargs = 4;
}

message BatchConfig {
    bool parallel = 1;          // Execute in parallel vs sequential
    bool stop_on_error = 2;     // Stop batch on first error
    int32 max_parallel = 3;     // Max concurrent executions
}

message BatchToolCallResponse {
    string batch_id = 1;
    repeated ToolCallResult results = 2;
    BatchMetrics metrics = 3;
}

message ToolCallResult {
    int32 index = 1;
    bool success = 2;
    google.protobuf.Any result = 3;
    ErrorInfo error = 4;
    ExecutionMetrics metrics = 5;
}
```

### Variable Operations

```protobuf
message GetVariableRequest {
    string session_id = 1;
    string variable_name = 2;
    bool include_metadata = 3;
}

message VariableResponse {
    bool exists = 1;
    google.protobuf.Any value = 2;
    VariableMetadata metadata = 3;
}

message SetVariableRequest {
    string session_id = 1;
    string variable_name = 2;
    google.protobuf.Any value = 3;
    VariableMetadata metadata = 4;
    bool create_if_missing = 5;
}

message VariableMetadata {
    string type = 1;
    google.protobuf.Timestamp created_at = 2;
    google.protobuf.Timestamp updated_at = 3;
    string created_by = 4;  // "elixir" or "python"
    map<string, string> tags = 5;
}

message ListVariablesRequest {
    string session_id = 1;
    string prefix = 2;
    repeated string tags = 3;
    int32 limit = 4;
}

message ListVariablesResponse {
    repeated VariableInfo variables = 1;
}

message VariableInfo {
    string name = 1;
    string type = 2;
    int32 size_bytes = 3;
    VariableMetadata metadata = 4;
}

message WatchVariablesRequest {
    string session_id = 1;
    repeated string variable_names = 2;
    bool include_initial = 3;  // Send current values first
}

message VariableUpdate {
    string name = 1;
    google.protobuf.Any value = 2;
    string operation = 3;  // "set", "delete", "update"
    google.protobuf.Timestamp timestamp = 4;
}
```

### Agent Operations

```protobuf
message CreateReActAgentRequest {
    string session_id = 1;
    string signature = 2;
    repeated string tool_names = 3;  // Subset of session tools
    int32 max_iters = 4;
    AgentConfig config = 5;
}

message AgentConfig {
    bool verbose = 1;
    bool return_intermediate_steps = 2;
    map<string, google.protobuf.Any> llm_config = 3;
}

message CreateReActAgentResponse {
    string agent_id = 1;
    int32 tool_count = 2;
    repeated string capabilities = 3;
}

message ExecuteAgentRequest {
    string agent_id = 1;
    google.protobuf.Struct input = 2;
    map<string, google.protobuf.Any> context = 3;
    bool stream = 4;
}

message AgentExecutionChunk {
    string agent_id = 1;
    
    oneof content {
        ThoughtChunk thought = 2;
        ActionChunk action = 3;
        ObservationChunk observation = 4;
        ResultChunk result = 5;
        ErrorInfo error = 6;
    }
}

message ThoughtChunk {
    string text = 1;
    int32 step = 2;
}

message ActionChunk {
    string tool_name = 1;
    google.protobuf.Struct tool_input = 2;
    int32 step = 3;
}

message ObservationChunk {
    google.protobuf.Any tool_output = 1;
    int32 step = 2;
    ExecutionMetrics metrics = 3;
}

message ResultChunk {
    google.protobuf.Struct final_answer = 1;
    int32 total_steps = 2;
    repeated IntermediateStep steps = 3;
}

message IntermediateStep {
    ThoughtChunk thought = 1;
    ActionChunk action = 2;
    ObservationChunk observation = 3;
}
```

### Common Types

```protobuf
message StatusResponse {
    bool success = 1;
    string message = 2;
    ErrorInfo error = 3;
}

message ErrorInfo {
    string type = 1;      // "ToolNotFound", "ValidationError", etc.
    string message = 2;
    map<string, string> details = 3;
    string stacktrace = 4;  // Optional, for debugging
    google.protobuf.Timestamp timestamp = 5;
}

message ExecutionMetrics {
    int64 duration_ms = 1;
    int64 cpu_time_ms = 2;
    int64 memory_bytes = 3;
    map<string, double> custom_metrics = 4;
}

message BatchMetrics {
    int32 total_items = 1;
    int32 successful_items = 2;
    int32 failed_items = 3;
    int64 total_duration_ms = 4;
    double avg_duration_ms = 5;
}

message HealthCheckRequest {
    string service = 1;
}

message HealthCheckResponse {
    enum ServingStatus {
        UNKNOWN = 0;
        SERVING = 1;
        NOT_SERVING = 2;
    }
    ServingStatus status = 1;
    map<string, ServingStatus> dependencies = 2;
}

message GetMetricsRequest {
    repeated string metric_names = 1;
    google.protobuf.Timestamp start_time = 2;
    google.protobuf.Timestamp end_time = 3;
}

message MetricsResponse {
    map<string, MetricValue> metrics = 1;
}

message MetricValue {
    oneof value {
        int64 integer_value = 1;
        double double_value = 2;
        string string_value = 3;
        MetricHistogram histogram = 4;
    }
}

message MetricHistogram {
    repeated Bucket buckets = 1;
    int64 count = 2;
    double sum = 3;
}

message Bucket {
    double upper_bound = 1;
    int64 count = 2;
}
```

## Serialization Formats

### Type Mapping

| Python Type | Protobuf Any | Elixir Type |
|-------------|--------------|-------------|
| str | StringValue | binary |
| int | Int64Value | integer |
| float | DoubleValue | float |
| bool | BoolValue | boolean |
| list | ListValue | list |
| dict | Struct | map |
| bytes | BytesValue | binary |
| None | NullValue | nil |
| DataFrame | Custom serialization | map |

### Custom Type Serialization

```python
def serialize_value(value: Any) -> google.protobuf.Any:
    """Serialize Python value to protobuf Any.
    
    Note: This is a critical function that requires rigorous implementation.
    For V1, using google.protobuf.Any provides flexibility. For V2, consider
    a concrete Value message with oneof for better type safety.
    """
    any_value = google.protobuf.Any()
    
    if isinstance(value, str):
        any_value.Pack(StringValue(value=value))
    elif isinstance(value, int):
        any_value.Pack(Int64Value(value=value))
    elif isinstance(value, float):
        any_value.Pack(DoubleValue(value=value))
    elif isinstance(value, bool):
        any_value.Pack(BoolValue(value=value))
    elif isinstance(value, bytes):
        any_value.Pack(BytesValue(value=value))
    elif value is None:
        any_value.Pack(NullValue())
    elif isinstance(value, list):
        list_value = ListValue()
        for item in value:
            list_value.values.append(serialize_to_value(item))
        any_value.Pack(list_value)
    elif isinstance(value, dict):
        struct_value = Struct()
        for k, v in value.items():
            struct_value.fields[k].CopyFrom(serialize_to_value(v))
        any_value.Pack(struct_value)
    elif hasattr(value, 'to_parquet'):  # pandas DataFrame
        # Custom DataFrame serialization
        df_bytes = value.to_parquet()
        any_value.Pack(BytesValue(value=df_bytes))
        any_value.type_url = "type.googleapis.com/pandas.DataFrame"
    else:
        # Fallback: serialize as string representation
        any_value.Pack(StringValue(value=str(value)))
        any_value.type_url = f"type.googleapis.com/python.{type(value).__name__}"
    
    return any_value

def deserialize_value(any_value: google.protobuf.Any) -> Any:
    """Deserialize protobuf Any to Python value.
    
    Handles all standard types plus custom types like pandas DataFrames.
    """
    if any_value.Is(StringValue.DESCRIPTOR):
        return any_value.Unpack(StringValue).value
    elif any_value.Is(Int64Value.DESCRIPTOR):
        return any_value.Unpack(Int64Value).value
    elif any_value.Is(DoubleValue.DESCRIPTOR):
        return any_value.Unpack(DoubleValue).value
    elif any_value.Is(BoolValue.DESCRIPTOR):
        return any_value.Unpack(BoolValue).value
    elif any_value.Is(BytesValue.DESCRIPTOR):
        bytes_val = any_value.Unpack(BytesValue).value
        # Check for custom types
        if any_value.type_url == "type.googleapis.com/pandas.DataFrame":
            import pandas as pd
            import io
            return pd.read_parquet(io.BytesIO(bytes_val))
        return bytes_val
    elif any_value.Is(NullValue.DESCRIPTOR):
        return None
    elif any_value.Is(ListValue.DESCRIPTOR):
        list_value = any_value.Unpack(ListValue)
        return [deserialize_from_value(v) for v in list_value.values]
    elif any_value.Is(Struct.DESCRIPTOR):
        struct_value = any_value.Unpack(Struct)
        return {k: deserialize_from_value(v) for k, v in struct_value.fields.items()}
    else:
        raise ValueError(f"Unknown type URL: {any_value.type_url}")
```

## Error Codes

| Error Type | Description | Recovery Action |
|------------|-------------|-----------------|
| ToolNotFound | Tool ID not registered | Check session tools |
| ValidationError | Input validation failed | Fix input parameters |
| TimeoutError | Execution timeout | Retry with longer timeout |
| ResourceExhausted | Rate limit exceeded | Backoff and retry |
| SessionExpired | Session no longer valid | Create new session |
| InternalError | Unexpected error | Check logs, report bug |

## Performance Guidelines

1. **Message Size Limits**
   - Max message size: 10MB (configurable)
   - Recommended chunk size for streaming: 64KB
   - Batch size limit: 100 items

2. **Timeout Defaults**
   - Standard tool call: 30 seconds
   - Streaming tool: 5 minutes
   - Batch operations: 10 minutes

3. **Connection Management**
   - Keep-alive interval: 30 seconds
   - Max idle time: 5 minutes
   - Connection pool size: 10-50

## Security Considerations

1. **Authentication**: Use mTLS for production
2. **Encryption**: TLS 1.3 minimum
3. **Rate Limiting**: Per-session and global limits
4. **Input Validation**: Schema-based validation before execution
5. **Audit Logging**: All tool executions logged with session context
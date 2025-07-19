# Task: LLM.3 - HTTP Adapter Implementation

## Context
You are implementing the HTTP adapter for DSPex, which provides direct HTTP communication with LLM APIs. This adapter is optimized for simple completions with minimal overhead and maximum performance.

## Required Reading

### 1. Existing HTTP Adapter
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapters/http.ex`
  - Review current implementation approach
  - Note HTTP client usage (Finch, HTTPoison, etc.)

### 2. LLM Adapter Protocol
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/prompts/LLM.1_adapter_protocol.md`
  - Review protocol requirements
  - Focus on simple string generation

### 3. Adaptive LLM Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/02_CORE_COMPONENTS_DETAILED.md`
  - Section: "Component 4: Adaptive LLM Architecture"
  - Note when HTTP adapter is preferred

### 4. Success Criteria
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Section: "Stage 6: Adaptive LLM Architecture"
  - HTTP adapter selection scenarios

### 5. Requirements
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/REQUIREMENTS.md`
  - NFR.1: Performance requirements (<50ms overhead)
  - IR.2: LLM provider integration patterns

## Implementation Requirements

### Adapter Structure
```elixir
defmodule DSPex.LLM.Adapters.HTTP do
  @behaviour DSPex.LLM.Adapter
  
  defstruct [
    :base_url,
    :headers,
    :timeout,
    :pool_config,
    :retry_config,
    :format
  ]
  
  # Supported formats
  @formats [:openai, :anthropic, :google, :custom]
end
```

### Provider Configurations
```elixir
# OpenAI format
%{
  base_url: "https://api.openai.com/v1",
  endpoint: "/chat/completions",
  headers: %{
    "Authorization" => "Bearer #{api_key}",
    "Content-Type" => "application/json"
  },
  format: :openai
}

# Anthropic format
%{
  base_url: "https://api.anthropic.com/v1",
  endpoint: "/messages",
  headers: %{
    "x-api-key" => api_key,
    "anthropic-version" => "2023-06-01"
  },
  format: :anthropic
}

# Custom format
%{
  base_url: "http://localhost:8000",
  endpoint: "/generate",
  format: :custom,
  request_builder: &build_custom_request/2,
  response_parser: &parse_custom_response/1
}
```

### Connection Pooling
```elixir
# Using Finch for connection pooling
def start_link(config) do
  pool_config = [
    size: config[:pool_size] || 10,
    count: config[:pool_count] || 2,
    protocol: :http2,
    conn_opts: [
      timeout: config[:connect_timeout] || 5_000
    ]
  ]
  
  Finch.start_link(
    name: __MODULE__,
    pools: %{
      default: pool_config
    }
  )
end
```

### Request Building
```elixir
defp build_request(:openai, prompt, opts) do
  %{
    model: opts[:model] || "gpt-3.5-turbo",
    messages: format_messages(prompt, opts),
    temperature: opts[:temperature] || 0.7,
    max_tokens: opts[:max_tokens],
    stream: opts[:stream] || false
  }
end

defp build_request(:anthropic, prompt, opts) do
  %{
    model: opts[:model] || "claude-3-sonnet",
    messages: format_messages(prompt, opts),
    max_tokens: opts[:max_tokens] || 1024
  }
end
```

### Streaming Support
```elixir
def stream(adapter, prompt, opts) do
  request = build_streaming_request(adapter, prompt, opts)
  
  Stream.resource(
    fn -> start_streaming(adapter, request) end,
    fn conn -> receive_chunk(conn) end,
    fn conn -> cleanup_connection(conn) end
  )
end

defp receive_chunk(conn) do
  case Finch.stream_next(conn) do
    {:ok, chunk} -> {[parse_sse_chunk(chunk)], conn}
    :done -> {:halt, conn}
    {:error, reason} -> raise "Streaming error: #{inspect(reason)}"
  end
end
```

## Acceptance Criteria
- [ ] Implements all adapter protocol functions
- [ ] Supports OpenAI, Anthropic, and Google formats
- [ ] Allows custom format configuration
- [ ] Connection pooling with Finch or similar
- [ ] Streaming support for compatible endpoints
- [ ] Retry logic with exponential backoff
- [ ] Request/response logging (configurable)
- [ ] Performance: <50ms overhead for simple requests
- [ ] Timeout handling with clear errors
- [ ] Rate limiting awareness

## Error Handling
```elixir
case Finch.request(request, __MODULE__) do
  {:ok, %{status: 200, body: body}} ->
    parse_response(adapter.format, body)
    
  {:ok, %{status: 429, headers: headers}} ->
    retry_after = get_retry_after(headers)
    {:error, {:rate_limited, retry_after}}
    
  {:ok, %{status: status, body: body}} ->
    {:error, {:api_error, status, parse_error(body)}}
    
  {:error, %Mint.TransportError{reason: :timeout}} ->
    {:error, :timeout}
    
  {:error, reason} ->
    {:error, {:connection_error, reason}}
end
```

## Testing Requirements
Create tests in:
- `test/dspex/llm/adapters/http_test.exs`

Test scenarios:
- Successful completion requests
- Streaming responses
- Various error conditions (timeout, rate limit, API errors)
- Connection pool behavior
- Retry logic
- Different provider formats

Use Bypass or similar for HTTP mocking.

## Example Usage
```elixir
# Simple completion
adapter = %DSPex.LLM.Adapters.HTTP{
  base_url: "https://api.openai.com/v1",
  headers: %{"Authorization" => "Bearer sk-..."},
  format: :openai
}

{:ok, response} = DSPex.LLM.Adapter.generate(
  adapter,
  "What is the capital of France?",
  model: "gpt-3.5-turbo",
  max_tokens: 50
)

# Streaming
{:ok, stream} = DSPex.LLM.Adapter.stream(
  adapter,
  "Tell me a story",
  model: "gpt-4",
  max_tokens: 1000
)

Enum.each(stream, fn chunk ->
  IO.write(chunk)
end)
```

## Dependencies
- Requires LLM.1 (Adapter Protocol) complete
- HTTP client library (Finch recommended)
- Jason for JSON parsing
- Bypass for testing (optional)

## Time Estimate
6 hours total:
- 2 hours: Core HTTP implementation with pooling
- 1 hour: Provider format support
- 1 hour: Streaming implementation
- 1 hour: Error handling and retries
- 1 hour: Comprehensive testing

## Notes
- Optimize for low latency
- Consider caching DNS lookups
- Implement proper SSL/TLS configuration
- Add telemetry for request tracking
- Consider circuit breaker for reliability
- Log requests/responses for debugging (with PII filtering)
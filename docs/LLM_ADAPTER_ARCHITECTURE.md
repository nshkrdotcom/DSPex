# DSPex LLM Adapter Architecture

## Overview

The LLM adapter architecture provides a flexible, pluggable system for integrating various LLM providers and libraries into DSPex. This design allows easy switching between different implementations without changing application code.

## Design Principles

1. **Adapter Pattern**: Common interface with multiple implementations
2. **Provider Agnostic**: Application code doesn't depend on specific providers
3. **Easy Extension**: New adapters can be added without modifying core code
4. **Configuration Driven**: Runtime adapter selection based on config
5. **Graceful Fallback**: Chain adapters for resilience

## Architecture

### Core Components

```elixir
defmodule DSPex.LLM.Adapter do
  @moduledoc """
  Behaviour defining the LLM adapter interface.
  """
  
  @type client :: map()
  @type prompt :: String.t() | list(map())
  @type options :: keyword()
  @type response :: map()
  
  @callback configure(provider :: atom(), config :: map()) :: 
    {:ok, client()} | {:error, term()}
    
  @callback generate(client(), prompt(), options()) :: 
    {:ok, response()} | {:error, term()}
    
  @callback stream(client(), prompt(), options()) :: 
    {:ok, Enumerable.t()} | {:error, term()}
    
  @callback batch(client(), prompts :: list(prompt()), options()) :: 
    {:ok, list(response())} | {:error, term()}
    
  @optional_callbacks stream: 3, batch: 3
end
```

### Available Adapters

#### 1. InstructorLite Adapter
```elixir
defmodule DSPex.LLM.Adapters.InstructorLite do
  @behaviour DSPex.LLM.Adapter
  
  @supported_providers [:openai, :anthropic, :gemini, :grok, :llamacpp]
  
  def configure(provider, config) when provider in @supported_providers do
    # InstructorLite handles provider-specific details
    {:ok, %{
      adapter: __MODULE__,
      provider: provider,
      config: config,
      response_model: config[:response_model]
    }}
  end
  
  def generate(client, prompt, opts) do
    InstructorLite.instruct(
      %{input: format_prompt(prompt)},
      response_model: client.response_model || opts[:response_model],
      adapter_context: build_context(client, opts)
    )
  end
end
```

#### 2. HTTP Adapter
```elixir
defmodule DSPex.LLM.Adapters.HTTP do
  @behaviour DSPex.LLM.Adapter
  
  def configure(provider, config) do
    endpoint = provider_endpoint(provider, config)
    headers = build_headers(provider, config)
    
    {:ok, %{
      adapter: __MODULE__,
      provider: provider,
      endpoint: endpoint,
      headers: headers,
      config: config
    }}
  end
  
  def generate(client, prompt, opts) do
    body = build_request_body(client.provider, prompt, opts)
    
    Req.post(client.endpoint,
      headers: client.headers,
      json: body,
      receive_timeout: opts[:timeout] || 30_000
    )
    |> handle_response(client.provider)
  end
  
  def stream(client, prompt, opts) do
    # SSE streaming for supported providers
    body = build_request_body(client.provider, prompt, Keyword.put(opts, :stream, true))
    
    stream = Req.post!(client.endpoint,
      headers: client.headers,
      json: body,
      into: :stream
    )
    
    {:ok, parse_sse_stream(stream, client.provider)}
  end
end
```

#### 3. Python Bridge Adapter
```elixir
defmodule DSPex.LLM.Adapters.Python do
  @behaviour DSPex.LLM.Adapter
  
  def configure(provider, config) do
    # Use Snakepit for Python LLM libraries
    {:ok, %{
      adapter: __MODULE__,
      provider: provider,
      config: config,
      pool: :llm_pool
    }}
  end
  
  def generate(client, prompt, opts) do
    Snakepit.execute(:llm_generate, %{
      provider: client.provider,
      prompt: prompt,
      config: client.config,
      opts: opts
    }, pool: client.pool)
  end
end
```

### Client Configuration

```elixir
# Using InstructorLite
{:ok, client} = DSPex.LLM.Client.new(
  adapter: :instructor_lite,
  provider: :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  response_model: MySchema
)

# Using HTTP adapter
{:ok, client} = DSPex.LLM.Client.new(
  adapter: :http,
  provider: :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-3-opus-20240229"
)

# Using Python bridge
{:ok, client} = DSPex.LLM.Client.new(
  adapter: :python,
  provider: :huggingface,
  model: "meta-llama/Llama-2-7b-hf"
)
```

### Adapter Selection Strategy

```elixir
defmodule DSPex.LLM.Client do
  @default_adapter_priority [:instructor_lite, :http, :python]
  
  def new(opts) do
    adapter_type = opts[:adapter] || select_best_adapter(opts)
    adapter_module = adapter_module(adapter_type)
    
    with {:ok, client} <- adapter_module.configure(opts[:provider], opts) do
      {:ok, enrich_client(client, opts)}
    end
  end
  
  defp select_best_adapter(opts) do
    # Smart selection based on requirements
    cond do
      opts[:response_model] -> :instructor_lite  # Structured output needed
      opts[:stream] -> :http                     # Streaming required
      opts[:local_model] -> :python              # Local model execution
      true -> hd(@default_adapter_priority)      # Default
    end
  end
end
```

### Usage in DSPex

```elixir
defmodule DSPex do
  def predict(signature, inputs, opts \\ []) do
    # Router determines if we use native LLM or Python DSPy
    case Router.route(:predict, signature) do
      :native ->
        # Use LLM adapter directly
        client = get_or_create_client(opts)
        prompt = format_prompt(signature, inputs)
        DSPex.LLM.Client.generate(client, prompt, opts)
        
      :python ->
        # Delegate to Python DSPy
        DSPex.Python.Bridge.execute(:predict, signature, inputs, opts)
    end
  end
end
```

## Benefits

1. **Flexibility**: Switch between providers without code changes
2. **Testability**: Easy to mock adapters for testing
3. **Extensibility**: Add new providers by implementing adapter behaviour
4. **Performance**: Choose optimal adapter based on use case
5. **Resilience**: Fallback chains for high availability

## Future Adapters

- **Ollama**: For local model execution
- **vLLM**: For high-performance inference
- **Modal**: For serverless GPU execution
- **Replicate**: For hosted model inference
- **Together**: For open model inference

## Configuration Examples

```elixir
# config/config.exs
config :dspex, :llm,
  default_adapter: :instructor_lite,
  adapters: [
    instructor_lite: [
      default_provider: :openai,
      providers: [
        openai: [api_key: {:system, "OPENAI_API_KEY"}],
        anthropic: [api_key: {:system, "ANTHROPIC_API_KEY"}]
      ]
    ],
    http: [
      timeout: 60_000,
      pool_size: 10
    ],
    python: [
      pool: :llm_pool,
      script: "llm_bridge.py"
    ]
  ]

# Runtime configuration
config :dspex, :llm_router,
  rules: [
    # Use InstructorLite for structured output
    {[response_model: _], :instructor_lite},
    # Use HTTP for streaming
    {[stream: true], :http},
    # Use Python for local models
    {[provider: :huggingface], :python}
  ]
```

## Testing

```elixir
defmodule DSPex.LLM.Adapters.Mock do
  @behaviour DSPex.LLM.Adapter
  
  def configure(_provider, config) do
    {:ok, %{adapter: __MODULE__, responses: config[:responses] || []}}
  end
  
  def generate(client, _prompt, _opts) do
    case client.responses do
      [response | rest] ->
        # Return mocked response and update state
        {:ok, response}
      [] ->
        {:error, :no_mock_responses}
    end
  end
end

# In tests
{:ok, client} = DSPex.LLM.Client.new(
  adapter: :mock,
  responses: [
    %{text: "Mocked response 1"},
    %{text: "Mocked response 2"}
  ]
)
```

## Migration Path

For existing DSPex users:

1. **Phase 1**: Add adapter layer alongside existing implementation
2. **Phase 2**: Migrate existing LLM calls to use adapters
3. **Phase 3**: Deprecate old implementation
4. **Phase 4**: Remove old implementation

This ensures backward compatibility while moving to the new architecture.
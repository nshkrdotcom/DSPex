# DSPex

<p align="center">
  <img src="assets/dspex-logo.svg" alt="DSPex Logo" width="200" height="200">
</p>

DSPex is a native Elixir implementation of [DSPy](https://github.com/stanfordnlp/dspy) (Declarative Self-improving Language Programs) that provides a unified interface for working with Large Language Models. It combines high-performance native Elixir implementations with Python DSPy integration through [Snakepit](https://github.com/nshkrdotcom/snakepit) for complex ML tasks.

## Features

- 🚀 **Hybrid Architecture**: Native Elixir for performance-critical operations, Python for complex ML
- 🔌 **Multiple LLM Adapters**: Gemini, InstructorLite, HTTP, Python bridge, and mock adapters
- 🎯 **DSPy Core Features**: Signatures, Predict, Chain of Thought, ReAct, and more
- 🔄 **Pipeline Composition**: Build complex workflows with sequential, parallel, and conditional execution
- 📊 **Smart Routing**: Automatically chooses the best implementation (native vs Python)
- 🏃 **Streaming Support**: Real-time streaming for supported providers (e.g., Gemini)

## DSPy Integration

DSPex provides comprehensive wrappers for all DSPy modules through Snakepit. See [DSPy Integration Guide](./README_DSPY_INTEGRATION.md) for details on:

- All available DSPy modules (Predict, ChainOfThought, ReAct, etc.)
- Optimizers (BootstrapFewShot, MIPRO, COPRO, etc.)  
- Retrievers (ColBERTv2, 20+ vector databases)
- Complete examples and usage patterns

## Installation

Add `dspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.1.2"}
  ]
end
```

## Quick Start

### Basic LLM Interaction

```elixir
# Configure a client (Gemini 2.0 Flash recommended - fast and free tier)
{:ok, client} = DSPex.lm_client(
  adapter: :gemini,
  api_key: System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-lite"
)

# Generate a response
{:ok, response} = DSPex.lm_generate(client, "What is Elixir?")
IO.puts(response)
```

### DSPy Operations

```elixir
# Parse a signature
{:ok, signature} = DSPex.signature("question: str -> answer: str")

# Basic prediction
{:ok, result} = DSPex.predict(signature, %{question: "What is DSPy?"})

# Chain of thought reasoning
{:ok, cot_result} = DSPex.chain_of_thought(
  signature, 
  %{question: "Explain quantum computing step by step"}
)
```

### Pipeline Composition

```elixir
# Define a complex pipeline mixing native and Python operations
pipeline = DSPex.pipeline([
  {:native, Signature, spec: "query -> keywords: list[str]"},
  {:python, "dspy.ChainOfThought", signature: "keywords -> analysis"},
  {:parallel, [
    {:native, Search, index: "docs"},
    {:python, "dspy.ColBERTv2", k: 10}
  ]},
  {:native, Template, template: "Results: <%= @results %>"}
])

# Execute the pipeline
{:ok, result} = DSPex.run_pipeline(pipeline, %{query: "machine learning trends"})
```

## LLM Adapters

DSPex provides multiple LLM adapters for different use cases:

### Gemini Adapter
Native Google Gemini API integration with streaming support:

```elixir
{:ok, client} = DSPex.lm_client(
  adapter: :gemini,
  api_key: System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-lite",
  generation_config: %{
    temperature: 0.7,
    max_output_tokens: 1000
  }
)

# Streaming responses
{:ok, stream} = DSPex.lm_generate(client, "Write a story", stream: true)
stream |> Enum.each(&IO.write/1)
```

### InstructorLite Adapter
For structured output with Ecto schema validation:

```elixir
defmodule Person do
  use Ecto.Schema
  
  embedded_schema do
    field :name, :string
    field :age, :integer
    field :occupation, :string
  end
end

{:ok, client} = DSPex.lm_client(
  adapter: :instructor_lite,
  provider: :gemini,
  api_key: System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-lite"
)

{:ok, person} = DSPex.lm_generate(
  client, 
  "Extract: John Doe is a 30-year-old software engineer",
  response_model: Person
)
```

### HTTP Adapter
Generic adapter for any HTTP-based LLM API:

```elixir
{:ok, client} = DSPex.lm_client(
  adapter: :http,
  base_url: "https://api.example.com",
  api_key: System.get_env("API_KEY"),
  model: "custom-model"
)
```

## Examples

The `examples/` directory contains comprehensive examples demonstrating DSPex capabilities:

### DSPy Integration Examples (`examples/dspy/`)

- **00_dspy_mock_demo.exs** - Basic test to verify DSPy integration is working
- **01_question_answering_pipeline.exs** - Core DSPy modules: Predict, ChainOfThought, optimization
- **02_code_generation_system.exs** - Advanced reasoning with ProgramOfThought, ReAct, and Retry
- **03_document_analysis_rag.exs** - Retrieval-augmented generation with ColBERTv2 and vector databases
- **04_optimization_showcase.exs** - All DSPy optimizers and advanced features
- **05_streaming_inference_pipeline.exs** - Streaming ML inference demonstrations
- **simple_qa_demo.exs** - Simple question-answering with DSPy
- **grpc_qa_demo.exs** - DSPy over gRPC transport (requires Snakepit v0.3.3+)
- **debug_qa_demo.exs** - Debugging tools for DSPy integration
- **adapter_comparison.exs** - Compare EnhancedPython vs gRPC adapters

### Quick Start Examples

- **qa_with_gemini_ex.exs** - Native Gemini adapter example
- **qa_with_instructor_lite.exs** - Structured output with InstructorLite
- **dspy_python_integration.exs** - Python DSPy bridge demonstration
- **comprehensive_dspy_gemini.exs** - Full DSPy features with Gemini
- **advanced_signature_example.exs** - Complex business scenarios:
  - Document intelligence and analysis
  - Customer support automation
  - Financial risk assessment
  - Product recommendation systems

Run examples with any LLM provider:
```bash
# With Gemini (recommended - fast and free tier)
export GOOGLE_API_KEY=your-gemini-api-key
mix run examples/dspy/simple_qa_demo.exs

# Run gRPC transport demo (requires gRPC dependencies)
mix run examples/dspy/grpc_qa_demo.exs

# With OpenAI
export OPENAI_API_KEY=your-openai-api-key
# Then update the example's config.exs

# With Anthropic, Cohere, or any other provider
# Set the appropriate API key and update config.exs
```

**Note**: DSPy examples default to Gemini 2.0 Flash Lite for its speed and free tier, but work with any supported LLM provider.

## Architecture

DSPex uses a hybrid architecture that combines the best of both worlds:

```
User Request
    ↓
DSPex API
    ↓
Router (decides native vs Python)
    ↓
Native Module ←→ Python Bridge
                      ↓
                  Snakepit
                      ↓
                  Python DSPy
```

### Core Components

- **DSPex** - Clean public API
- **DSPex.Router** - Smart routing between native and Python implementations
- **DSPex.Pipeline** - Workflow orchestration
- **DSPex.Native.\*** - Native Elixir implementations (Signature, Template, Validator)
- **DSPex.Python.\*** - Python bridge via Snakepit
- **DSPex.LLM.\*** - LLM adapter system

## Configuration

```elixir
# config/config.exs
config :dspex,
  router: [
    prefer_native: true,
    fallback_to_python: true
  ]

config :snakepit,
  python_path: "python3",
  pool_size: 4
```

## Testing

DSPex uses a three-layer testing architecture:

```bash
# Run all tests
mix test

# Run specific test layers
mix test.fast        # Layer 1: Mock adapter tests (~70ms)
mix test.protocol    # Layer 2: Protocol tests
mix test.integration # Layer 3: Full integration tests
```

## Development

```bash
# Interactive shell
iex -S mix

# Code quality tools
mix format           # Format code
mix credo            # Static analysis
mix dialyzer         # Type checking
```

## Known Issues

1. **InstructorLite + Gemini**: InstructorLite generates JSON schemas with `additionalProperties` that Gemini doesn't accept. Use the native Gemini adapter for Gemini models.

2. **Python Environment**: Python with DSPy is required for Python bridge features. See [Snakepit setup instructions](https://github.com/nshkrdotcom/snakepit) for Python environment configuration.

## Roadmap

- [ ] Complete Python DSPy integration
- [ ] Additional native module implementations
- [ ] Distributed execution support
- [ ] Model management and optimization features
- [ ] Comprehensive documentation
- [ ] Performance benchmarks

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Acknowledgments

- [DSPy](https://github.com/stanfordnlp/dspy) - The original Python implementation
- [Snakepit](https://github.com/nshkrdotcom/snakepit) - Python integration for Elixir
- [InstructorLite](https://github.com/martosaur/instructor_lite) - Structured output library

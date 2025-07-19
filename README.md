# DSPex

DSPex is a native Elixir implementation of [DSPy](https://github.com/stanfordnlp/dspy) (Declarative Self-improving Language Programs) that provides a unified interface for working with Large Language Models. It combines high-performance native Elixir implementations with Python DSPy integration through [Snakepit](https://github.com/nshkrdotcom/snakepit) for complex ML tasks.

## Features

- 🚀 **Hybrid Architecture**: Native Elixir for performance-critical operations, Python for complex ML
- 🔌 **Multiple LLM Adapters**: Gemini, InstructorLite, HTTP, Python bridge, and mock adapters
- 🎯 **DSPy Core Features**: Signatures, Predict, Chain of Thought, ReAct, and more
- 🔄 **Pipeline Composition**: Build complex workflows with sequential, parallel, and conditional execution
- 📊 **Smart Routing**: Automatically chooses the best implementation (native vs Python)
- 🏃 **Streaming Support**: Real-time streaming for supported providers (e.g., Gemini)

## Installation

Add `dspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic LLM Interaction

```elixir
# Configure a client
{:ok, client} = DSPex.lm_client(
  adapter: :gemini,
  api_key: System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-exp"
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
  api_key: System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-exp",
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
  provider: :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: "gpt-4o-mini"
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

The `examples/` directory contains several example scripts:

- **qa_with_gemini_ex.exs** - Comprehensive Gemini usage including streaming, batch processing, and creative writing
- **qa_simple_instructor_lite.exs** - Simple Q&A without structured output
- **qa_with_instructor_lite.exs** - Structured data extraction with Ecto schemas
- **advanced_signature_example.exs** - Complex business scenarios:
  - Document intelligence and analysis
  - Customer support automation
  - Financial risk assessment
  - Product recommendation systems

Run examples with:
```bash
mix run examples/qa_with_gemini_ex.exs
```

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

2. **Python Environment**: Ensure Python with DSPy is properly installed for Python bridge features.

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

[Add your license here]

## Acknowledgments

- [DSPy](https://github.com/stanfordnlp/dspy) - The original Python implementation
- [Snakepit](https://github.com/nshkrdotcom/snakepit) - Python integration for Elixir
- [InstructorLite](https://github.com/thmsmlr/instructor_lite) - Structured output library
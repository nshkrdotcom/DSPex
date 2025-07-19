# DSPex

DSPex provides a unified Elixir interface for DSPy (Declarative Self-improving Language Programs). It seamlessly blends native Elixir implementations for performance-critical operations with Python-based execution for complex ML tasks.

## Features

- **Native Signature Parsing**: High-performance DSPy signature parsing in pure Elixir
- **Smart Routing**: Automatically routes operations to native or Python implementations
- **Pipeline Composition**: Mix native and Python steps in complex ML workflows
- **Session Support**: Maintain state across operations with session affinity
- **Extensible Architecture**: Easy to add new native implementations or Python modules

## Installation

Add `dspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.1.0"}
  ]
end
```

## Basic Usage

```elixir
# Parse a signature
{:ok, signature} = DSPex.signature("question: str -> answer: str")

# Execute a prediction
{:ok, result} = DSPex.predict(signature, %{question: "What is DSPy?"})

# Use chain of thought reasoning
{:ok, cot_result} = DSPex.chain_of_thought(
  signature, 
  %{question: "Explain quantum computing"}
)

# Create a pipeline mixing native and Python
pipeline = DSPex.pipeline([
  {:native, DSPex.Native.Signature, spec: "query -> keywords: list[str]"},
  {:python, "dspy.ChainOfThought", signature: "keywords -> summary"},
  {:native, DSPex.Native.Template, template: "Summary: <%= @summary %>"}
])

{:ok, result} = DSPex.run_pipeline(pipeline, %{query: "machine learning"})
```

## Architecture

DSPex uses a smart router to direct operations:

- **Native Implementations**: Signatures, templates, validation, metrics
- **Python via Snakepit**: DSPy modules, optimizers, complex ML operations
- **Hybrid Pipeline**: Seamlessly mix both in a single workflow

## Configuration

Configure Python environment:

```elixir
config :snakepit,
  pooling_enabled: true,
  python_path: "python3",
  script_path: "priv/python/dspy_general.py"
```

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run with different test modes
TEST_MODE=mock_adapter mix test      # Fast unit tests
TEST_MODE=full_integration mix test  # Full Python integration

# Start interactive console
iex -S mix
```

## License

Apache 2.0
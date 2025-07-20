# DSPex DSPy Integration Guide

## Overview

DSPex provides comprehensive Elixir wrappers for [DSPy](https://github.com/stanfordnlp/dspy) functionality through the high-performance [Snakepit](./snakepit) bridge. This integration enables you to use all DSPy modules, optimizers, and retrievers with idiomatic Elixir APIs while maintaining full compatibility with the Python ecosystem.

## Architecture

DSPex uses Snakepit's generalized Python invocation to call DSPy modules directly without complex wrapper scripts. Each module instance is stored in Python memory with a unique ID, enabling stateful operations across multiple calls.

## Available Modules

### Core Prediction Modules

- **`DSPex.Modules.Predict`** - Basic prediction without reasoning
- **`DSPex.Modules.ChainOfThought`** - Step-by-step reasoning before answers
- **`DSPex.Modules.ReAct`** - Reasoning + Acting with tool usage
- **`DSPex.Modules.ProgramOfThought`** - Code-based problem solving
- **`DSPex.Modules.MultiChainComparison`** - Compare multiple reasoning chains
- **`DSPex.Modules.Retry`** - Self-refinement through retries

### Optimizers

- **`DSPex.Optimizers.BootstrapFewShot`** - Automatic few-shot example generation
- **`DSPex.Optimizers.MIPRO`** - Multi-instruction prompt optimization
- **`DSPex.Optimizers.MIPROv2`** - Enhanced MIPRO with better performance
- **`DSPex.Optimizers.COPRO`** - Coordinate prompt optimization
- **`DSPex.Optimizers.BootstrapFewShotWithRandomSearch`** - Bootstrap with hyperparameter search

### Retrievers

- **`DSPex.Retrievers.ColBERTv2`** - Dense passage retrieval
- **`DSPex.Retrievers.Retrieve`** - Generic retrieval supporting:
  - ChromaDB, Pinecone, Weaviate, Qdrant
  - FAISS, Milvus, MongoDB Atlas
  - PostgreSQL (pgvector), Snowflake
  - And 15+ more vector databases

### Supporting Modules

- **`DSPex.LM`** - Language model configuration (30+ providers via LiteLLM)
- **`DSPex.Assertions`** - Output constraints and validation
- **`DSPex.Evaluation`** - Comprehensive evaluation framework
- **`DSPex.Examples`** - Dataset management
- **`DSPex.Settings`** - Global DSPy settings
- **`DSPex.Config`** - System initialization
- **`DSPex.Modules`** - Central module registry

## Quick Start

```elixir
# 1. Initialize DSPex with DSPy
{:ok, _} = DSPex.Config.init()

# 2. Configure your language model
# Configure Gemini 2.0 Flash (recommended - fast and free tier available)
DSPex.LM.configure("google/gemini-2.0-flash-exp", api_key: System.get_env("GOOGLE_API_KEY"))

# Or use other providers
DSPex.LM.configure("openai/gpt-4", api_key: System.get_env("OPENAI_API_KEY"))

# 3. Create and use a module
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is DSPy?"})
```

## Key Features

### 1. Direct DSPy Invocation
Each wrapper uses Snakepit's `call` method to directly invoke DSPy classes:
```elixir
Snakepit.Python.call("dspy.ChainOfThought", %{signature: signature}, opts)
```

### 2. Stateful Operations
Objects are stored in Python memory with unique IDs:
```elixir
{:ok, "cot_a1b2c3d4"} = DSPex.Modules.ChainOfThought.create("question -> answer")
# Later...
{:ok, result} = DSPex.Modules.ChainOfThought.execute("cot_a1b2c3d4", inputs)
```

### 3. Session Support
Maintains state across multiple operations:
```elixir
DSPex.Session.with_session(fn opts ->
  {:ok, model} = DSPex.Modules.Predict.create("input -> output", opts)
  {:ok, result} = DSPex.Modules.Predict.execute(model, %{input: "test"}, opts)
end)
```

### 4. Flexible Configuration
All DSPy options are supported through keyword lists:
```elixir
{:ok, optimizer} = DSPex.Optimizers.BootstrapFewShot.optimize(
  program_id,
  trainset,
  max_bootstrapped_demos: 3,
  max_labeled_demos: 16,
  max_rounds: 2
)
```

## Language Model Providers

DSPex supports 30+ LLM providers through LiteLLM:

```elixir
# OpenAI
DSPex.LM.openai("gpt-4")

# Anthropic
DSPex.LM.anthropic("claude-3-opus-20240229")

# Google
DSPex.LM.gemini("gemini-pro")

# Local models
DSPex.LM.ollama("llama2", api_base: "http://localhost:11434")

# Azure
DSPex.LM.azure("my-deployment", 
  api_key: System.get_env("AZURE_API_KEY"),
  api_base: System.get_env("AZURE_API_BASE")
)
```

## Examples

See the [examples directory](./examples/dspy/) for complete demonstrations:

1. **Question Answering Pipeline** - Multi-stage QA with retrieval
2. **Code Generation System** - Planning, implementation, and testing
3. **Document Analysis** - Extraction, summarization, and insights
4. **Optimization Showcase** - Comparing different optimizers

## Performance Considerations

- **Latency**: 2-100ms per operation (depends on module complexity)
- **Throughput**: 1k-50k ops/sec with proper pooling
- **Memory**: Python processes managed by Snakepit
- **Scaling**: Configure pool size based on workload

## Future: Dual Implementation Support

DSPex is designed to support both Python DSPy and native Elixir implementations. As modules are ported to native Elixir, they will automatically be used for better performance while maintaining the same API. See [Dual Implementation Architecture](./docs/DUAL_IMPLEMENTATION_SUPPORT_SEAMLESS_20250719.md) for details.

## Requirements

- Elixir 1.14+
- Python 3.8+
- DSPy: `pip install dspy-ai`
- (Optional) MessagePack: `pip install msgpack` for better performance

## Configuration

For the examples to work properly, Snakepit needs to be configured with pooling enabled:

```elixir
# In your application config or before starting the applications
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :wire_protocol, :auto)
Application.put_env(:snakepit, :pool_config, %{pool_size: 4})
```

## Installation

```elixir
# In your mix.exs
def deps do
  [
    {:dspex, "~> 0.1.0"}
  ]
end
```

Then install Python dependencies:
```bash
pip install dspy-ai litellm msgpack

# Verify installation
python -c "import dspy; print(f'DSPy {dspy.__version__} installed successfully')"
```

## Running Examples

The examples demonstrate all DSPy wrappers but require DSPy to be installed. They will use mock responses if no API key is configured:

```bash
# Run examples
mix run examples/dspy/01_question_answering_pipeline.exs
mix run examples/dspy/02_code_generation_system.exs
mix run examples/dspy/03_document_analysis_rag.exs
mix run examples/dspy/04_optimization_showcase.exs
```

## Contributing

DSPex is under active development. Contributions are welcome! Priority areas:

1. Native Elixir implementations of core modules
2. Additional convenience wrappers
3. Performance optimizations
4. Documentation and examples

## License

Apache 2.0 - See LICENSE file for details.
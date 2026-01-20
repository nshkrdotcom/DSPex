<p align="center">
  <img src="assets/DSPex.svg" alt="DSPex Logo" width="200">
</p>

<p align="center">
  <strong>DSPy for Elixir via SnakeBridge</strong><br>
  Declarative LLM programming with full access to Stanford's DSPy framework
</p>

<p align="center">
  <a href="https://hex.pm/packages/dspex"><img src="https://img.shields.io/hexpm/v/dspex.svg" alt="Hex Version"></a>
  <a href="https://hex.pm/packages/dspex"><img src="https://img.shields.io/hexpm/dt/dspex.svg" alt="Hex Downloads"></a>
  <a href="https://hexdocs.pm/dspex"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="Documentation"></a>
  <a href="https://github.com/nshkrdotcom/dspex/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/dspex.svg" alt="License"></a>
</p>

---

## Overview

DSPex brings [DSPy](https://github.com/stanfordnlp/dspy) — Stanford's framework for programming language models — to Elixir. Rather than generating wrapper code, DSPex provides a minimal, transparent interface through [SnakeBridge](https://github.com/nshkrdotcom/snakebridge)'s Universal FFI. Call any DSPy function directly from Elixir with full type safety and automatic Python lifecycle management.

**Why DSPex?**

- **Zero boilerplate** — No code generation needed, just call Python directly
- **Full DSPy access** — Signatures, Predict, ChainOfThought, optimizers, and more
- **100+ LLM providers** — OpenAI, Anthropic, Google, Ollama, and anything LiteLLM supports
- **Production-ready timeouts** — Built-in profiles for ML inference workloads
- **Elixir-native error handling** — `{:ok, result}` / `{:error, reason}` everywhere

## Installation

Prerequisites (one-time):
- Python 3.9+
- [uv](https://docs.astral.sh/uv/) for Python package setup:
  `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Optional (RLM example only): Deno runtime (external binary), install via asdf:
  `asdf plugin add deno https://github.com/asdf-community/asdf-deno.git`
  `asdf install`
  (uses the pinned version in `.tool-versions`)

Add DSPex to your `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.5.0"}
  ]
end
```

Create `config/runtime.exs` for Python bridge configuration:

```elixir
import Config
SnakeBridge.ConfigHelper.configure_snakepit!()
```

Then install dependencies and set up Python:

```bash
mix deps.get
mix snakebridge.setup  # Creates managed venv + installs dspy-ai automatically
```

SnakeBridge manages an isolated venv under `priv/snakepit/python/venv`; no manual venv creation or pip installs needed.

The RLM flagship example uses DSPy’s default PythonInterpreter (Pyodide/WASM), which requires Deno on your PATH.

## Quick Start

```elixir
DSPex.run(fn ->
  # 1. Create and configure a language model
  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  # 2. Create a predictor with a signature
  predict = DSPex.predict!("question -> answer")

  # 3. Run inference
  result = DSPex.method!(predict, "forward", [], question: "What is the capital of France?")
  answer = DSPex.attr!(result, "answer")

  IO.puts(answer)  # => "Paris"
end)
```

## Core Concepts

### Signatures

DSPy signatures define input/output contracts using a simple arrow syntax:

```elixir
# Single input/output
predict = DSPex.predict!("question -> answer")

# Multiple fields
predict = DSPex.predict!("context, question -> answer")

# Rich multi-field signatures
predict = DSPex.predict!("title, content -> category, keywords, sentiment")
```

### Modules

DSPex supports all DSPy modules:

```elixir
# Simple prediction
predict = DSPex.predict!("question -> answer")

# Chain-of-thought reasoning (includes intermediate steps)
cot = DSPex.chain_of_thought!("question -> answer")
result = DSPex.method!(cot, "forward", [], question: "What is 15% of 80?")
reasoning = DSPex.attr!(result, "reasoning")  # Shows step-by-step thinking
answer = DSPex.attr!(result, "answer")
```

### Language Models

Any LiteLLM-compatible provider works out of the box:

```elixir
# Google Gemini (default)
lm = DSPex.lm!("gemini/gemini-flash-lite-latest", temperature: 0.7)

# OpenAI
lm = DSPex.lm!("openai/gpt-4o-mini")

# Anthropic
lm = DSPex.lm!("anthropic/claude-3-sonnet-20240229")

# Local Ollama
lm = DSPex.lm!("ollama/llama2")
```

### Direct LM Calls

Bypass modules and call the LM directly:

```elixir
lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
DSPex.configure!(lm: lm)

# Direct call with messages
messages = [%{role: "user", content: "Say hello in French"}]
response = DSPex.method!(lm, "forward", [messages])
```

## Examples

DSPex includes 20 comprehensive examples demonstrating various use cases:

Use `mix run --no-start` so DSPex owns the Snakepit lifecycle and closes the
process registry DETS cleanly (avoids repair warnings after unclean exits).

| Example | Description | Run Command |
|---------|-------------|-------------|
| `basic.exs` | Simple Q&A prediction | `mix run --no-start examples/basic.exs` |
| `chain_of_thought.exs` | Reasoning with visible steps | `mix run --no-start examples/chain_of_thought.exs` |
| `qa_with_context.exs` | Context-aware Q&A | `mix run --no-start examples/qa_with_context.exs` |
| `multi_hop_qa.exs` | Multi-hop question answering | `mix run --no-start examples/multi_hop_qa.exs` |
| `rag.exs` | Retrieval-augmented generation | `mix run --no-start examples/rag.exs` |
| `custom_signature.exs` | Signatures with instructions | `mix run --no-start examples/custom_signature.exs` |
| `multi_field.exs` | Multiple inputs/outputs | `mix run --no-start examples/multi_field.exs` |
| `classification.exs` | Sentiment analysis | `mix run --no-start examples/classification.exs` |
| `entity_extraction.exs` | Extract people, orgs, locations | `mix run --no-start examples/entity_extraction.exs` |
| `code_gen.exs` | Code generation with reasoning | `mix run --no-start examples/code_gen.exs` |
| `math_reasoning.exs` | Complex math problem solving | `mix run --no-start examples/math_reasoning.exs` |
| `summarization.exs` | Text summarization | `mix run --no-start examples/summarization.exs` |
| `translation.exs` | Multi-language translation | `mix run --no-start examples/translation.exs` |
| `custom_module.exs` | Custom module composition | `mix run --no-start examples/custom_module.exs` |
| `optimization.exs` | BootstrapFewShot optimization | `mix run --no-start examples/optimization.exs` |
| `flagship_multi_pool_gepa.exs` | Multi-pool GEPA + numpy analytics pipeline | `mix run --no-start examples/flagship_multi_pool_gepa.exs` |
| `flagship_multi_pool_rlm.exs` | Multi-pool RLM + numpy analytics pipeline | `mix run --no-start examples/flagship_multi_pool_rlm.exs` |
| `rlm/rlm_data_extraction_experiment_fixed.exs` | RLM data extraction on NYC 311 (real dataset) | `mix run --no-start examples/rlm/rlm_data_extraction_experiment_fixed.exs` |
| `direct_lm_call.exs` | Direct LM interaction | `mix run --no-start examples/direct_lm_call.exs` |
| `timeout_test.exs` | Timeout configuration demo | `mix run --no-start examples/timeout_test.exs` |

Realistic RLM benchmark: the NYC 311 data extraction experiment uses 50,000 real records with exact, computable ground truth. On `gemini/gemini-flash-lite-latest`, an observed run scored RLM 100% vs Direct 0%.

For flagship walkthroughs, see:
- `guides/flagship_multi_pool_gepa.md` (GEPA)
- `guides/flagship_multi_pool_rlm.md` (RLM)

## Timeout Configuration

DSPex leverages SnakeBridge's timeout architecture, designed for ML inference workloads. By default, all DSPy calls use the `:ml_inference` profile (10 minute timeout).

### Timeout Profiles

| Profile | Timeout | Use Case |
|---------|---------|----------|
| `:default` | 2 min | Standard Python calls |
| `:streaming` | 30 min | Streaming responses |
| `:ml_inference` | 10 min | LLM inference (DSPex default) |
| `:batch_job` | 1 hour | Long-running batch operations |

### Per-Call Timeout Override

```elixir
# Use a different profile
DSPex.method!(predict, "forward", [],
  question: "Complex analysis...",
  __runtime__: [timeout_profile: :batch_job]
)

# Set exact timeout in milliseconds
DSPex.method!(predict, "forward", [],
  question: "Quick question",
  __runtime__: [timeout: 30_000]  # 30 seconds
)

# Helper functions
opts = DSPex.with_timeout([question: "test"], timeout: 60_000)
DSPex.method!(predict, "forward", [], opts)

# Profile helper
DSPex.method!(predict, "forward", [],
  Keyword.merge([question: "test"], DSPex.timeout_profile(:batch_job))
)
```

### Global Configuration

```elixir
# config/config.exs
config :snakebridge,
  runtime: [
    library_profiles: %{"dspy" => :ml_inference}
  ]
```

## API Reference

DSPex provides a thin wrapper over SnakeBridge's Universal FFI:

### Lifecycle

| Function | Description |
|----------|-------------|
| `DSPex.run/1,2` | Wrap code in Python lifecycle management |

### DSPy Helpers

| Function | Description |
|----------|-------------|
| `DSPex.lm/1,2` | Create a DSPy language model |
| `DSPex.configure/0,1` | Configure DSPy global settings |
| `DSPex.predict/1,2` | Create a Predict module |
| `DSPex.chain_of_thought/1,2` | Create a ChainOfThought module |

### Universal FFI

| Function | Description |
|----------|-------------|
| `DSPex.call/2-4` | Call any Python function or class |
| `DSPex.method/2-4` | Call a method on a Python object |
| `DSPex.attr/2` | Get an attribute from a Python object |
| `DSPex.set_attr/3` | Set an attribute on a Python object |
| `DSPex.get/2` | Get a module attribute |
| `DSPex.ref?/1` | Check if a value is a Python object reference |
| `DSPex.bytes/1` | Encode binary data as Python bytes |

### Timeout Helpers

| Function | Description |
|----------|-------------|
| `DSPex.with_timeout/2` | Add timeout options to call opts |
| `DSPex.timeout_profile/1` | Get timeout profile opts |
| `DSPex.timeout_ms/1` | Get exact timeout opts |

All functions have `!` variants that raise on error instead of returning `{:error, reason}`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Your Elixir App                      │
├─────────────────────────────────────────────────────────┤
│                      DSPex.run/1                        │
│              (Python lifecycle wrapper)                 │
├─────────────────────────────────────────────────────────┤
│                   SnakeBridge.call/4                    │
│                   (Universal FFI)                       │
├─────────────────────────────────────────────────────────┤
│                    Snakepit gRPC                        │
│              (Python process bridge)                    │
├─────────────────────────────────────────────────────────┤
│                     Python DSPy                         │
│            (Stanford's LLM framework)                   │
├─────────────────────────────────────────────────────────┤
│                   LLM Providers                         │
│     (OpenAI, Anthropic, Google, Ollama, etc.)           │
└─────────────────────────────────────────────────────────┘
```

**Key Design Principles:**

- **Minimal wrapper** — DSPex delegates to SnakeBridge, no magic
- **No code generation** — Call Python directly at runtime
- **Automatic lifecycle** — Snakepit manages Python processes
- **Session-aware** — Maintains Python state across calls
- **Thread-safe** — gRPC bridge handles concurrency

## Requirements

- **Elixir** ~> 1.18
- **Python** 3.8+
- **API Key** — Set `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc. based on your provider

## Related Projects

- [DSPy](https://github.com/stanfordnlp/dspy) — The Python framework DSPex wraps
- [SnakeBridge](https://github.com/nshkrdotcom/snakebridge) — The Python-Elixir bridge powering DSPex
- [Snakepit](https://github.com/nshkrdotcom/snakepit) — Python process pool and gRPC server

## License

MIT License. See [LICENSE](LICENSE) for details.

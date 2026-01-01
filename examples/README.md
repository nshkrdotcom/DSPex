# DSPex Examples

This directory contains comprehensive examples demonstrating DSPex capabilities. All examples require an OpenAI API key set via `OPENAI_API_KEY` environment variable.

## Prerequisites

```bash
# Install dependencies and set up Python environment
mix deps.get
mix snakebridge.setup

# Set your API key
export OPENAI_API_KEY="your-key-here"
```

## Running Examples

Run any example individually:

```bash
mix run examples/basic.exs
```

Or run all examples with the test script:

```bash
./examples/run_all.sh
```

---

## Core Examples

### Basic Q&A (`basic.exs`)

The foundational DSPex example showing core concepts:
- Creating and configuring a language model
- Using `DSPex.predict!/1` with a simple signature
- Running inference with `DSPex.method!/4`

```elixir
predict = DSPex.predict!("question -> answer")
result = DSPex.method!(predict, "forward", [], question: "What is the capital of Hawaii?")
answer = DSPex.attr!(result, "answer")
```

**Run:** `mix run examples/basic.exs`

---

### Chain of Thought (`chain_of_thought.exs`)

Shows step-by-step reasoning with visible intermediate steps:
- Uses `DSPex.chain_of_thought!/1` for reasoning tasks
- Exposes `reasoning` attribute alongside the answer
- Ideal for math, logic, and multi-step problems

```elixir
cot = DSPex.chain_of_thought!("question -> answer")
result = DSPex.method!(cot, "forward", [], question: "What is 15% of 80?")
reasoning = DSPex.attr!(result, "reasoning")  # Shows step-by-step thinking
answer = DSPex.attr!(result, "answer")
```

**Run:** `mix run examples/chain_of_thought.exs`

---

### Q&A with Context (`qa_with_context.exs`)

Context-aware question answering with multiple input fields:
- Demonstrates multi-input signatures (`context, question -> answer`)
- Useful for RAG (Retrieval-Augmented Generation) patterns
- Shows how to pass additional grounding context

```elixir
qa = DSPex.predict!("context, question -> answer")
result = DSPex.method!(qa, "forward", [], context: context, question: question)
```

**Run:** `mix run examples/qa_with_context.exs`

---

## Signature Patterns

### Multi-Field Signatures (`multi_field.exs`)

Multiple inputs and outputs in a single signature:
- Shows rich input/output schemas (`title, content -> category, keywords, tone`)
- Demonstrates extracting multiple output fields

```elixir
analyzer = DSPex.predict!("title, content -> category, keywords, tone")
result = DSPex.method!(analyzer, "forward", [], title: title, content: content)
category = DSPex.attr!(result, "category")
keywords = DSPex.attr!(result, "keywords")
tone = DSPex.attr!(result, "tone")
```

**Run:** `mix run examples/multi_field.exs`

---

### Custom Signature with Instructions (`custom_signature.exs`)

Create signatures with custom system instructions:
- Uses `dspy.Signature` directly for fine-grained control
- Adds custom instructions via `with_instructions/1` method
- Creates predictor from custom signature object

```elixir
sig = DSPex.call!("dspy", "Signature", ["question -> answer"])
sig = DSPex.method!(sig, "with_instructions", [
  "You are a helpful assistant that answers questions concisely in one sentence."
])
predict = DSPex.call!("dspy", "Predict", [sig])
```

**Run:** `mix run examples/custom_signature.exs`

---

## Use Case Examples

### Classification (`classification.exs`)

Sentiment analysis and text classification:
- Simple `text -> sentiment` signature
- Batch processing multiple inputs

```elixir
classifier = DSPex.predict!("text -> sentiment")
result = DSPex.method!(classifier, "forward", [], text: "I love this product!")
sentiment = DSPex.attr!(result, "sentiment")
```

**Run:** `mix run examples/classification.exs`

---

### Entity Extraction (`entity_extraction.exs`)

Extract named entities from text:
- Multi-output signature for different entity types
- Extracts people, organizations, and locations

```elixir
extractor = DSPex.predict!("text -> people, organizations, locations")
result = DSPex.method!(extractor, "forward", [], text: text)
people = DSPex.attr!(result, "people")
orgs = DSPex.attr!(result, "organizations")
locations = DSPex.attr!(result, "locations")
```

**Run:** `mix run examples/entity_extraction.exs`

---

### Summarization (`summarization.exs`)

Text summarization with simple signature:
- Demonstrates `text -> summary` pattern
- Works with longer text inputs

```elixir
summarizer = DSPex.predict!("text -> summary")
result = DSPex.method!(summarizer, "forward", [], text: long_text)
summary = DSPex.attr!(result, "summary")
```

**Run:** `mix run examples/summarization.exs`

---

### Translation (`translation.exs`)

Multi-language translation:
- Two-input signature with target language parameter
- Demonstrates translation to Spanish, French, Japanese

```elixir
translator = DSPex.predict!("text, target_language -> translation")
result = DSPex.method!(translator, "forward", [], 
  text: "Hello, how are you?", 
  target_language: "Spanish"
)
translation = DSPex.attr!(result, "translation")
```

**Run:** `mix run examples/translation.exs`

---

### Code Generation (`code_gen.exs`)

Generate code with chain-of-thought reasoning:
- Uses ChainOfThought for step-by-step code generation
- Multi-language support (Python, Elixir, etc.)

```elixir
coder = DSPex.chain_of_thought!("task, language -> code")
result = DSPex.method!(coder, "forward", [], 
  task: "Write a function to check if a number is prime", 
  language: "Python"
)
reasoning = DSPex.attr!(result, "reasoning")
code = DSPex.attr!(result, "code")
```

**Run:** `mix run examples/code_gen.exs`

---

### Math Reasoning (`math_reasoning.exs`)

Solve math problems with step-by-step reasoning:
- ChainOfThought module for mathematical problems
- Shows working for algebra, geometry, and arithmetic

```elixir
solver = DSPex.chain_of_thought!("problem -> answer")
result = DSPex.method!(solver, "forward", [], 
  problem: "If 3x + 7 = 22, what is x?"
)
reasoning = DSPex.attr!(result, "reasoning")
answer = DSPex.attr!(result, "answer")
```

**Run:** `mix run examples/math_reasoning.exs`

---

## Advanced Examples

### Direct LM Calls (`direct_lm_call.exs`)

Bypass DSPy modules and call the LM directly:
- Uses `__call__` method on the language model
- Works with raw message format
- Returns list of completions

```elixir
lm = DSPex.lm!("openai/gpt-4o-mini", temperature: 0.9)
messages = [%{"role" => "user", "content" => "Tell me a joke about programming."}]
completions = DSPex.method!(lm, "__call__", [], messages: messages)
response = Enum.at(completions, 0)
```

**Run:** `mix run examples/direct_lm_call.exs`

---

### Timeout Configuration (`timeout_test.exs`)

Comprehensive timeout configuration examples:
- Default ML inference timeout (10 minutes)
- Per-call timeout overrides with exact milliseconds
- Per-call timeout with profiles (`:default`, `:streaming`, `:ml_inference`, `:batch_job`)
- Helper functions: `DSPex.with_timeout/2`, `DSPex.timeout_profile/1`, `DSPex.timeout_ms/1`

```elixir
# Exact timeout in milliseconds
result = DSPex.method!(predict, "forward", [],
  question: "Complex query...",
  __runtime__: [timeout: 120_000]  # 2 minutes
)

# Using a timeout profile
result = DSPex.method!(predict, "forward", [],
  question: "Long computation...",
  __runtime__: [timeout_profile: :batch_job]  # 1 hour
)

# Using helper functions
opts = DSPex.with_timeout([question: "test"], timeout: 60_000)
result = DSPex.method!(predict, "forward", [], opts)
```

**Timeout Profiles:**
| Profile | Duration | Use Case |
|---------|----------|----------|
| `:default` | 2 min | Standard Python calls |
| `:streaming` | 30 min | Streaming responses |
| `:ml_inference` | 10 min | LLM inference (DSPex default) |
| `:batch_job` | 1 hour | Long-running batch operations |

**Run:** `mix run examples/timeout_test.exs`

---

## Running All Examples

The `run_all.sh` script runs all examples sequentially with:
- Colorized output
- Per-example timing
- Pass/fail summary
- Automatic timeout handling (configurable via `DSPEX_RUN_TIMEOUT_SECONDS`)

```bash
# Run with default 120s timeout per example
./examples/run_all.sh

# Run with custom timeout (300s per example)
DSPEX_RUN_TIMEOUT_SECONDS=300 ./examples/run_all.sh

# Disable timeout
DSPEX_RUN_TIMEOUT_SECONDS=0 ./examples/run_all.sh
```

## Example Index

| Example | Module | Description |
|---------|--------|-------------|
| `basic.exs` | Predict | Simple Q&A prediction |
| `chain_of_thought.exs` | ChainOfThought | Reasoning with visible steps |
| `qa_with_context.exs` | Predict | Context-aware Q&A |
| `multi_field.exs` | Predict | Multiple inputs/outputs |
| `custom_signature.exs` | Predict | Signatures with instructions |
| `classification.exs` | Predict | Sentiment analysis |
| `entity_extraction.exs` | Predict | Extract people, orgs, locations |
| `summarization.exs` | Predict | Text summarization |
| `translation.exs` | Predict | Multi-language translation |
| `code_gen.exs` | ChainOfThought | Code generation with reasoning |
| `math_reasoning.exs` | ChainOfThought | Math problem solving |
| `direct_lm_call.exs` | Direct LM | Raw LM interaction |
| `timeout_test.exs` | Various | Timeout configuration demo |

## Troubleshooting

### Missing API Key
```
Error: OPENAI_API_KEY not set
```
Set your API key: `export OPENAI_API_KEY="your-key"`

### Python/DSPy Not Installed
```
Error: Module dspy not found
```
Run: `mix snakebridge.setup`

### Timeout Errors
For complex queries, increase the timeout:
```elixir
DSPex.method!(predict, "forward", [],
  question: "...",
  __runtime__: [timeout_profile: :batch_job]
)
```

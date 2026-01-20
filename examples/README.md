# DSPex Examples

This directory contains comprehensive examples demonstrating DSPex capabilities. All examples require a Gemini API key set via `GEMINI_API_KEY` environment variable.

## Prerequisites

```bash
# Install dependencies and set up Python environment
mix deps.get
mix snakebridge.setup

# Set your API key
export GEMINI_API_KEY="your-key-here"
```

RLM examples only (Deno runtime, external binary):

```bash
asdf plugin add deno https://github.com/asdf-community/asdf-deno.git
asdf install
```

This uses the pinned Deno version in `.tool-versions`.
Required for `flagship_multi_pool_rlm.exs` and `rlm/rlm_data_extraction_experiment.exs`.

## Running Examples

Run any example individually:

```bash
mix run --no-start examples/basic.exs
```

`--no-start` ensures DSPex owns the Snakepit lifecycle and closes the process
registry DETS cleanly (avoids repair warnings after unclean exits).

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

**Run:** `mix run --no-start examples/basic.exs`

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

**Run:** `mix run --no-start examples/chain_of_thought.exs`

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

**Run:** `mix run --no-start examples/qa_with_context.exs`

---

### Multi-hop QA (`multi_hop_qa.exs`)

Answer questions that require multiple steps:
- Breaks the question into two hops
- Feeds hop 1 output into hop 2 context
- Demonstrates explicit chaining of predictions

```elixir
hop1 = DSPex.predict!("question -> answer")
hop2 = DSPex.predict!("context, question -> answer")

hop1_result = DSPex.method!(hop1, "forward", [], question: "Which state is the University of Michigan located in?")
state = DSPex.attr!(hop1_result, "answer")

context = "The University of Michigan is located in #{state}."
hop2_result = DSPex.method!(hop2, "forward", [], context: context, question: "What is the capital of #{state}?")
```

**Run:** `mix run --no-start examples/multi_hop_qa.exs`

---

### RAG (`rag.exs`)

Retrieval-augmented generation with a simple Elixir retriever:
- Selects top documents with naive keyword matching
- Feeds retrieved context into a DSPy predictor
- Highlights the retrieval + generation pattern

```elixir
top_docs = SimpleRetriever.retrieve(docs, question, 2)
context = top_docs |> Enum.map(& &1.text) |> Enum.join("\n\n")
rag = DSPex.predict!("context, question -> answer")
result = DSPex.method!(rag, "forward", [], context: context, question: question)
```

**Run:** `mix run --no-start examples/rag.exs`

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

**Run:** `mix run --no-start examples/multi_field.exs`

---

### Custom Signature with Instructions (`custom_signature.exs`)

Create signatures with custom system instructions:
- Uses `Dspy.make_signature/2` for wrapper-backed signature creation
- Adds custom instructions at creation time
- Creates predictor from custom signature object

```elixir
{:ok, sig} =
  Dspy.make_signature(
    "question -> answer",
    "You are a helpful assistant that answers questions concisely in one sentence."
  )

predict = DSPex.predict!(sig)
```

**Run:** `mix run --no-start examples/custom_signature.exs`

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

**Run:** `mix run --no-start examples/classification.exs`

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

**Run:** `mix run --no-start examples/entity_extraction.exs`

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

**Run:** `mix run --no-start examples/summarization.exs`

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

**Run:** `mix run --no-start examples/translation.exs`

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

**Run:** `mix run --no-start examples/code_gen.exs`

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

**Run:** `mix run --no-start examples/math_reasoning.exs`

---

## Advanced Examples

### Custom Module (`custom_module.exs`)

Compose multiple predictors into a custom Elixir module:
- Extracts keywords first
- Feeds keywords into a second predictor
- Shows how to build a reusable pipeline

```elixir
qa = CustomQA.new()
{keywords, answer} = CustomQA.forward(qa, question)
```

**Run:** `mix run --no-start examples/custom_module.exs`

---

### Optimization (`optimization.exs`)

Optimize a student module with `BootstrapFewShot`:
- Builds a tiny training set with `Dspy.Example`
- Compiles a predictor with few-shot bootstrapping
- Demonstrates the optimizer workflow

```elixir
{:ok, optimizer} = Dspy.BootstrapFewShot.new([])
{:ok, optimized} = Dspy.BootstrapFewShot.compile(optimizer, student, trainset: trainset)
```

**Run:** `mix run --no-start examples/optimization.exs`

---

### Flagship Multi-Pool + GEPA (`flagship_multi_pool_gepa.exs`)

End-to-end demo that exercises the full SnakeBridge + Snakepit stack:
- Two strict-affinity DSPy pools (triage + GEPA optimizer)
- A hint-affinity analytics pool using numpy
- GEPA prompt optimization with `max_metric_calls=3`
- Prompt history inspection (via LM history + graceful serialization)

```bash
mix run --no-start examples/flagship_multi_pool_gepa.exs
```

**Run:** `mix run --no-start examples/flagship_multi_pool_gepa.exs`

Guide: `guides/flagship_multi_pool_gepa.md`

---

### Flagship Multi-Pool + RLM (`flagship_multi_pool_rlm.exs`)

End-to-end demo showcasing Recursive Language Models with multi-pool routing:
- Two strict-affinity DSPy pools (triage + RLM)
- A hint-affinity analytics pool using numpy
- RLM analysis over a long context buffer
- Prompt history inspection (via LM history)

**Note:** RLM uses `PythonInterpreter`, which requires Deno (external runtime).
Install via asdf: `asdf plugin add deno https://github.com/asdf-community/asdf-deno.git` then `asdf install`.

```bash
mix run --no-start examples/flagship_multi_pool_rlm.exs
```

**Run:** `mix run --no-start examples/flagship_multi_pool_rlm.exs`

Guide: `guides/flagship_multi_pool_rlm.md`

---

### RLM Data Extraction (NYC 311) (`rlm/rlm_data_extraction_experiment.exs`)

Realistic, structured data extraction at scale:
- Uses 50,000 rows of NYC 311 service request data (real government dataset)
- Builds a large document-like context and compares RLM vs direct LLM
- Observed result with `gemini/gemini-flash-lite-latest`: RLM 100% vs Direct 0%

```bash
mix run --no-start examples/rlm/rlm_data_extraction_experiment.exs
```

Guide: `examples/rlm/README.md`

---

### Direct LM Calls (`direct_lm_call.exs`)

Bypass DSPy modules and call the LM directly:
- Uses `__call__` method on the language model
- Works with raw message format
- Returns list of completions

```elixir
lm = DSPex.lm!("gemini/gemini-flash-lite-latest", temperature: 0.9)
messages = [%{"role" => "user", "content" => "Tell me a joke about programming."}]
completions = DSPex.method!(lm, "__call__", [], messages: messages)
response = Enum.at(completions, 0)
```

**Run:** `mix run --no-start examples/direct_lm_call.exs`

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

**Run:** `mix run --no-start examples/timeout_test.exs`

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
| `multi_hop_qa.exs` | Predict | Multi-hop question answering |
| `rag.exs` | Predict | Retrieval-augmented generation |
| `multi_field.exs` | Predict | Multiple inputs/outputs |
| `custom_signature.exs` | Predict | Signatures with instructions |
| `classification.exs` | Predict | Sentiment analysis |
| `entity_extraction.exs` | Predict | Extract people, orgs, locations |
| `summarization.exs` | Predict | Text summarization |
| `translation.exs` | Predict | Multi-language translation |
| `code_gen.exs` | ChainOfThought | Code generation with reasoning |
| `math_reasoning.exs` | ChainOfThought | Math problem solving |
| `custom_module.exs` | Pipeline | Custom module composition |
| `optimization.exs` | Optimizer | BootstrapFewShot optimization |
| `flagship_multi_pool_gepa.exs` | Flagship | Multi-pool GEPA + numpy analytics |
| `flagship_multi_pool_rlm.exs` | Flagship | Multi-pool RLM + numpy analytics |
| `rlm/rlm_data_extraction_experiment.exs` | RLM | NYC 311 data extraction (real dataset) |
| `direct_lm_call.exs` | Direct LM | Raw LM interaction |
| `timeout_test.exs` | Various | Timeout configuration demo |

## Troubleshooting

### Missing API Key
```
Error: GEMINI_API_KEY not set
```
Set your API key: `export GEMINI_API_KEY="your-key"`

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

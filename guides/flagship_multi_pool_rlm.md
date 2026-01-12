# Flagship Multi-Pool RLM Demo

This guide explains the DSPex flagship example that exercises multi-pool routing,
strict session affinity for stateful DSPy refs, Recursive Language Models (RLM),
and numpy-based evaluation.

## What It Demonstrates

- **Multiple DSPy pools with strict affinity** for stateful refs (predictors, LMs, RLM).
- **Parallel sessions per pool** for concurrent triage predictions.
- **Analytics pool with hint affinity** for stateless numpy calculations.
- **RLM over long context** using a sandboxed interpreter (Deno + Pyodide).
- **Prompt history inspection** via LM history.

## Prerequisites

```bash
mix deps.get
mix snakebridge.setup
export GEMINI_API_KEY="your-key-here"
```

RLM uses `PythonInterpreter`, which requires Deno:

```bash
# macOS/Linux
curl -fsSL https://deno.land/install.sh | sh

# Or via Homebrew
brew install deno
```

## Running The Example

```bash
mix run --no-start examples/flagship_multi_pool_rlm.exs
```

## Pool Configuration

The example uses three pools:

```elixir
ConfigHelper.snakepit_config(
  pools: [
    %{name: :triage_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :rlm_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :analytics_pool, pool_size: 2, affinity: :hint}
  ]
)
```

**Why strict affinity?** DSPy predictors, LMs, and RLM modules are Python refs
that must remain on the same worker for session consistency.

## RLM Usage

RLM is created with a signature and a capped recursion budget:

```elixir
{:ok, rlm} =
  Dspy.Predict.RLM.new(
    "context, query -> output",
    4,
    12,
    4_000,
    false,
    [],
    nil,
    nil,
    max_depth: 2,
    __runtime__: [pool_name: :rlm_pool, session_id: session_id]
  )
```

The example stores a long context buffer and asks for a summary:

```elixir
result =
  DSPex.method!(
    rlm,
    "forward",
    [],
    context: context,
    query: "Identify the top two recurring issues and recommend next actions.",
    __runtime__: [pool_name: :rlm_pool, session_id: session_id]
  )
```

RLM keeps the context in a sandboxed Python REPL, letting the model explore it
without injecting the entire context into every prompt.

## Prompt History

The example inspects LM history for triage and RLM sessions using a safe `eval`
call scoped to the session. This avoids serialization issues with raw response
objects and still demonstrates the full prompt flow.

## Troubleshooting

If the RLM step is skipped:

```
Deno not found; skipping RLM step (install Deno to enable RLM).
```

Install Deno and rerun the example.

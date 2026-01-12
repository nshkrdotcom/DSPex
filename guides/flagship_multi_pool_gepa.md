# Flagship Multi-Pool GEPA Demo

This guide explains the DSPex flagship example that exercises multi-pool routing, strict session
affinity for stateful DSPy refs, GEPA prompt optimization, and numpy-based evaluation.

## What It Demonstrates

- **Multiple DSPy pools with strict affinity** for stateful refs (predictors and LMs).
- **Parallel sessions per pool** to fan out work across multiple workers.
- **Analytics pool with hint affinity** for stateless numpy calculations.
- **GEPA optimization** with a small budget (`max_metric_calls=3`).
- **Prompt inspection** via LM history with graceful serialization.

## Prerequisites

```bash
mix deps.get
mix snakebridge.setup
export GEMINI_API_KEY="your-key-here"
```

## Running The Example

```bash
mix run --no-start examples/flagship_multi_pool_gepa.exs
```

## Pool Configuration

The example overrides the default single pool and uses explicit multi-pool config:

```elixir
ConfigHelper.snakepit_config(
  pools: [
    %{name: :triage_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :optimizer_pool, pool_size: 2, affinity: :strict_queue},
    %{name: :analytics_pool, pool_size: 2, affinity: :hint}
  ]
)
```

**Why strict affinity?** DSPy predictors and LMs are Python refs, which must stay on the same
worker for the session. The strict pools guarantee that routing never jumps workers under load.

## GEPA Metric Definition

GEPA requires a metric with this signature:

```python
def metric(gold, pred, trace=None, pred_name=None, pred_trace=None):
    ...
```

The example defines it from Elixir using Python `exec`, and returns
`dspy.Prediction(score=..., feedback=...)`. The metric compares category + urgency and
provides a short feedback string for GEPA to reflect on.

## Prompt Inspection

Each pool exposes its prompt history through the LM object's `history` field. The example
fetches the last few entries via `builtins.eval`, and SnakeBridge's graceful serialization
keeps non-serializable `ModelResponse` values as refs while preserving the rest of the data.

```elixir
code = "list(lm.history[-6:])"
history = DSPex.call!("builtins", "eval", [code, %{"lm" => lm}], __runtime__: runtime_opts)
```

The example prints the last 6 interactions per pool and highlights ref-wrapped responses.

## Session Rehydration

Strict affinity guarantees same-worker routing as long as the worker stays alive. If a worker
crashes or is recycled, Snakepit returns `:session_worker_unavailable` so callers can rebuild
state. The flagship demo detects this condition for the insights session and rehydrates the
ChainOfThought module in a fresh session before retrying.

## Tips

- Increase `max_metric_calls` for a more realistic GEPA run.
- Swap models by changing `@model` in the example.
- Use larger pools if you want more concurrent DSPy sessions.

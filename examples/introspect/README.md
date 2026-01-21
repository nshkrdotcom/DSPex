# DSPy API Introspection (RLM)

This example uses RLM to analyze the generated DSPy Elixir wrapper sources and
produce a compact API cheat sheet or focused summaries.

Run:

```bash
mix run --no-start examples/introspect/dspy_api_introspect.exs
```

Requirements:
- `GEMINI_API_KEY` (or another supported LLM provider)
- Deno for PythonInterpreter (asdf or deno.land/install)

Defaults:
- Uses the full `lib/snakebridge_generated/dspy` context (all generated modules)
- Traces the last 30 LM calls with prompt/response truncated to 2000 chars
- Does not truncate the final result (use `--result-chars` to limit)
- Preset prompts append default rules + FACTS (use `--no-rules` / `--no-facts` to disable)
  - Default rules enforce final-only output (no reasoning or meta commentary)

Notes:
- `--file` can be a single `.ex` file or a directory of generated modules.

Presets:
- `api` (default): compact API cheat sheet + CLI hints
- `predict`: minimal Predict workflow
- `rlm`: minimal RLM workflow
- `history`: history and tracing APIs

Examples:

```bash
mix run --no-start examples/introspect/dspy_api_introspect.exs --preset rlm
mix run --no-start examples/introspect/dspy_api_introspect.exs \
  --prompt "Summarize LM configuration and history inspection" \
  --signature "context, query -> output"
mix run --no-start examples/introspect/dspy_api_introspect.exs --trace-prompt-chars 2000
mix run --no-start examples/introspect/dspy_api_introspect.exs --result-chars 0
```

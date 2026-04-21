# AGENTS.md

This file is for coding agents working in this repository. Keep it accurate when
the build, generation flow, or project layout changes.

## Project Summary

DSPex provides DSPy for Elixir through SnakeBridge. There are two public access
layers:

- `DSPex` in `lib/dspex.ex`: hand-written convenience wrapper over
  `SnakeBridge.call/4`, `SnakeBridge.call!/4`, and related FFI helpers.
- `Dspy.*` in `lib/snakebridge_generated/dspy`: generated SnakeBridge bindings
  for the Python `dspy` package.

The generated modules are intentionally checked in. They are used for HexDocs,
IDE navigation, and direct Elixir access to DSPy's public API surface.

## Important Files

- `mix.exs`: package metadata, deps, SnakeBridge compiler, and Python dependency
  declaration.
- `config/config.exs`: SnakeBridge config. `generated_layout: :split` means
  generation writes many per-module files under `lib/snakebridge_generated`.
- `snakebridge.lock`: generation/runtime metadata, requested/resolved Python
  package versions, and generator hashes.
- `lib/dspex.ex`: hand-written public convenience API.
- `lib/snakebridge_generated/**`: generated files. Do not hand-edit these.
- `examples/README.md`, `guides/*.md`: user-facing workflow docs.
- `CHANGELOG.md`: update the `[Unreleased]` section for dependency and generated
  surface changes.

## Generated Surface Rules

- Do not manually edit files under `lib/snakebridge_generated`.
- If generated output is wrong, change SnakeBridge, the Python dependency config,
  or the upstream Python package version, then regenerate.
- Generated file headers should show the current SnakeBridge and DSPy versions,
  for example `# Library: dspy 3.2.0`.
- `Dspy.*` modules are thin wrappers over `SnakeBridge.Runtime`; they should
  contain `__snakebridge_python_name__/0`, optional
  `__snakebridge_python_class__/0`, `__snakebridge_library__/0`, `new/3` for
  classes, and method/function wrappers that call `SnakeBridge.Runtime`.

## Updating DSPy And Regenerating

Use this flow when bumping the Python `dspy` dependency:

1. Check the worktree:
   ```bash
   git status --short
   ```

2. Update the DSPy version in `mix.exs`:
   ```elixir
   {:dspy, "x.y.z", generate: :all, module_mode: :explicit, max_class_methods: 500}
   ```

3. Add a `[Unreleased]` changelog note saying DSPy was upgraded and the generated
   `Dspy.*` wrapper surface was regenerated.

4. Remove old generated artifacts:
   ```bash
   rm -rf lib/snakebridge_generated
   ```

5. Regenerate:
   ```bash
   HEX_HOME=/tmp/dspex_hex_home mix snakebridge.regen --clean
   ```

   `HEX_HOME=/tmp/dspex_hex_home` avoids failures from a broken user-level Hex
   config. If Hex is healthy in the environment, plain `mix snakebridge.regen
   --clean` is fine.

6. Confirm the lock file and generated headers:
   ```bash
   rg -n '"requested":|"resolved":|"version":' snakebridge.lock
   rg -n 'Library: dspy|Requested:|Observed at generation:' lib/snakebridge_generated | head -n 80
   ```

7. Check generated file count and new/deleted files:
   ```bash
   find lib/snakebridge_generated -type f -name '*.ex' | sort | wc -l
   git status --short
   ```

## Build And Test Commands

Prefer these commands after code or generation changes:

```bash
HEX_HOME=/tmp/dspex_hex_home mix compile
HEX_HOME=/tmp/dspex_hex_home mix test
```

Run examples with `--no-start` so DSPex owns the Snakepit lifecycle:

```bash
mix run --no-start examples/basic.exs
```

Most examples require `GEMINI_API_KEY`. RLM examples also require Deno.

## Common Gotchas

- Local `mix help ...` can fail if the user-level Hex config is invalid. Retry
  with `HEX_HOME=/tmp/dspex_hex_home`.
- Do not run `mix run` examples without `--no-start`; the docs use `--no-start`
  to avoid unclean Snakepit DETS shutdown warnings.
- Generated modules may be numerous and noisy in diffs. Review high-level
  signals first: version headers, new/deleted modules, lock metadata, and
  whether `mix compile` passes.
- The generated surface uses `module_mode: :explicit` by design. Do not switch to
  broader discovery unless the user explicitly wants a much larger surface.
- `max_class_methods: 500` is a guardrail for inheritance-heavy DSPy classes.
  Keep it unless there is a specific missing-method reason to change it.

## Review Checklist For Dependency Bumps

- `mix.exs` requests the intended DSPy version.
- `snakebridge.lock` requested/resolved/version entries match the intended DSPy
  version.
- Generated headers mention the intended DSPy version.
- New generated files are plausible for the upstream DSPy release.
- No hand-written files under `lib/` changed unintentionally, except deliberate
  updates such as `lib/dspex.ex`.
- `CHANGELOG.md` has an `[Unreleased]` note.
- `mix compile` passes.
- `mix test` passes, or the failure is recorded with the exact reason.

## Release Version Bumps

When the user asks to cut or prepare a release version:

- Update `@version` in `mix.exs`.
- Update the README install snippet (`{:dspex, "~> x.y.z"}`).
- Move relevant `[Unreleased]` changelog notes into `## [x.y.z] - YYYY-MM-DD`.
- Add the matching changelog compare link and advance `[Unreleased]` to compare
  from the new tag.
- Search the repo for the old version and review every remaining hit:
  ```bash
  rg -n 'old\\.version|new\\.version' README.md CHANGELOG.md mix.exs examples guides config lib test AGENTS.md
  ```

# Changelog

All notable changes to DSPex will be documented in this file.

## [Unreleased]

## [0.9.0] - 2026-01-25

### Changed
- Updated SnakeBridge dependency to a local path (`../snakebridge`) for development in this workspace.
- Switched DSPy generation to `module_mode: :explicit` to avoid broad/nuclear submodule discovery and keep the generated surface focused on explicit `__all__` exports.
- Added `max_class_methods` guardrail to keep generated wrappers small for inheritance-heavy classes.

## [0.8.0] - 2026-01-23

### Added
- New generated modules: `Dspy.Metadata`, `Dspy.Dsp`, `Dspy.Predict.Retry`, `Dspy.Retrievers.DatabricksRm`, `Dspy.Retrievers.WeaviateRm`.
- Docstring fallback for methods without docstrings now inherit their class-level docstring (e.g., RLM methods display the RLM module description).
- Config hash tracking in `snakebridge.lock` for library configuration changes.
- README documentation for `mix snakebridge.regen` command (with `--clean` option) to refresh generated wrappers.

### Changed
- Upgraded to SnakeBridge 0.14.0 and Snakepit 0.11.1; regenerated all DSPy bindings.
- Refined type specs for module/class references (improved naming precision).

### Removed
- `Dspy.ChainOfThoughtWithHint` and `Dspy.Program` modules (removed upstream in DSPy).

## [0.7.0] - 2026-01-21

### Added
- HexDocs grouping for generated `Dspy.*` modules to mirror DSPy’s package structure.
- Python docstring metadata surfaced in generated module docs (via SnakeBridge 0.13.0).

### Changed
- Upgraded to SnakeBridge 0.13.0 and regenerated DSPy bindings/manifest.
- README and guides updated to reflect dual access: generated `Dspy.*` modules plus `DSPex` FFI helpers.

## [0.6.0] - 2026-01-21

### Added
- NYC 311 RLM data extraction experiment (50k records) with caching, ground-truth evaluation, and documentation.
- DSPy API introspection example using RLM with presets, rules/facts toggles, trace controls, and context modes.
- Split generated DSPy wrappers into per-module files (SnakeBridge 0.12.0), replacing the monolithic `dspy.ex`.

### Changed
- Examples now use generated native bindings (`Dspy.*` modules) and `Snakepit.run_as_script/2` instead of the DSPex wrapper layer.
- Flagship demos now use native `Dspy.GEPA`, `Dspy.BootstrapFewShot`, and `Dspy.Predict.RLM` modules.
- RLM data extraction experiment consolidated into one script, switched pandas to stdlib CSV, and improved evaluation + extraction logic.
- RLM data extraction experiment now includes trace controls and LM history inspection settings via environment variables.
- Examples index/run-all scripts updated to include the NYC 311 experiment and introspection guide.

## [0.5.0] - 2026-01-19

### Added
- Flagship multi-pool RLM example plus guide, including session rehydration and prompt history inspection.

### Changed
- Regenerated DSPy wrappers/manifest with SnakeBridge 0.11.0 and DSPy 3.1.2 (full API surface, updated graceful serialization helpers).
- Examples now lean on generated wrappers for signature creation, examples, GEPA optimization, and RLM, with tuple return handling.
- RLM flagship uses `Dspy.Predict.RLM` to match DSPy 3.1.2’s export path.
- RLM flagship init now matches DSPy 3.1.2 RLM parameters (removed unsupported `max_depth`).
- Flagship GEPA/RLM demos now inspect LM history via `builtins.eval` with graceful serialization safeguards.
- Examples index, run-all script, and docs now include the RLM flagship demo and guide.
- README setup now calls out `uv` and the managed venv location for first-time installs.
- Runtime Python selection now prefers the Snakepit-managed venv, avoiding mismatched installs on clean setups.
- RLM docs now include Deno/asdf setup guidance with a pinned `.tool-versions`.

## [0.4.0] - 2026-01-12

### Added
- Flagship multi-pool GEPA example with a dedicated guide (strict session affinity, GEPA optimization, numpy analytics pool).
- New examples: `custom_module`, `multi_hop_qa`, `optimization`, `rag`, plus updated examples index and run-all script.
- `GracefulSerialization.Helpers` module for handling non-serializable Python objects.
- Basic DSPex API/timeout helper tests.
- Credo config for linting.
- CI setup now installs `uv` for Python tooling.

### Changed
- Upgraded SnakeBridge to 0.9.0 and Snakepit to 0.11.0; regenerated DSPy bindings/manifest.
- Default model switched to Gemini and examples now require `GEMINI_API_KEY`.
- `DSPex.run/2` defaults to `restart: true` and ensures SnakeBridge starts cleanly.
- `attr/3`, `attr!/3`, and `set_attr/4` accept runtime options for pool routing.
- Examples now use `mix run --no-start`; dev logger level set to `:warning`.
- CI uses `mix test` instead of `mix test.all`.

## [0.3.0] - 2026-01-02

### Changed
- Simplified to minimal wrapper architecture using SnakeBridge Universal FFI
- Single `DSPex` module with direct pass-through to SnakeBridge
- Updated documentation with comprehensive README
- **Default model switched from OpenAI to Gemini** (`gemini/gemini-flash-lite-latest`)
- Examples now require `GEMINI_API_KEY` instead of `OPENAI_API_KEY`
- Examples should be run with `mix run --no-start` for clean DETS lifecycle
- Upgraded to SnakeBridge 0.9.0 and Snakepit 0.11.0
- `DSPex.run/2` now defaults to `restart: true` and ensures SnakeBridge is started
- Dev logger level changed to `:warning`

### Added
- Timeout helper functions: `with_timeout/2`, `timeout_profile/1`, `timeout_ms/1`
- 18 comprehensive examples covering all major use cases
- **Flagship multi-pool GEPA example** (`flagship_multi_pool_gepa.exs`) demonstrating:
  - Multiple DSPy pools with strict session affinity
  - Parallel sessions per pool for concurrent work
  - Analytics pool with hint affinity for stateless numpy calculations
  - GEPA prompt optimization with metrics and feedback
  - Prompt history inspection via graceful serialization
- New guide: `guides/flagship_multi_pool_gepa.md`
- Multi-pool runtime options: `pool_name` and `affinity` parameters
- Extended `attr/3`, `attr!/3`, and `set_attr/4` to accept runtime options
- `GracefulSerialization.Helpers` module for handling non-serializable Python objects
- Assets configuration for hex.pm package
- Badges and improved documentation

## [0.2.1] - 2025-10-25

### Changed
- Updated to Snakepit 0.6.3
- SnakeBridge integration improvements

## [0.2.0] - 2025-10-08

### Added
- New professional SVG logo
- CI workflow with Python setup
- Python setup.py for dspex_adapters package
- Python requirements.txt for dependencies
- ALTAR integration roadmaps and v1.0 vision documentation

### Changed
- Migrated DSPy integration architecture
- Fixed compiler warnings in pipeline.ex

### Fixed
- Example result extraction
- Snakepit orphan process handling

## [0.1.1] - 2025-07-24

### Added
- Bidirectional tool calls support
- Example scripts with proper shutdown handling
- Performance test suite (excluded from default runs)

### Changed
- Removed DSPex state management layer in favor of Snakepit SessionStore
- Removed legacy JSON bridges
- Migrated to Snakepit 0.4

### Removed
- Obsolete lib modules and tests
- Legacy state management code

## [0.1.0] - 2025-07-13

Initial experimental release with direct Snakepit integration.

### Added
- Basic DSPy bridge via Snakepit gRPC
- Session management
- Pool-based Python process management
- Initial examples and test infrastructure

[Unreleased]: https://github.com/nshkrdotcom/DSPex/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/nshkrdotcom/DSPex/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/nshkrdotcom/DSPex/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/nshkrdotcom/DSPex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/DSPex/releases/tag/v0.1.0

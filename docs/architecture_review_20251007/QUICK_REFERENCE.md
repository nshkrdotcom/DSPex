# Quick Reference Guide

## One-Page Summary

### The Situation

- **Snakepit v0.4.2** has 469 LOC of DSPy code
- **DSPex v0.2.0** uses Snakepit for Python bridge
- **Problem**: Domain logic in infrastructure layer
- **Solution**: Move DSPy code from Snakepit → DSPex

### The Plan

```
Week 1          Week 2          Week 3
│               │               │
├─ Snakepit     ├─ Elixir       ├─ Testing
│  v0.4.3       │  Migration    │  & Docs
│  Deprecate    │  10 modules   │  Tag v0.2.1
│               │               │
```

### The Impact

| Project | Files Changed | LOC Changed | Risk |
|---------|---------------|-------------|------|
| **Snakepit** | 5 files | +135 lines | Very Low |
| **DSPex Python** | 1 new file | +469 lines | Low |
| **DSPex Elixir** | 10 files | ~500 lines | Medium |

### The Numbers

- **Total Effort**: 18-28 hours (2-3 days)
- **Breaking Changes**: 0 (during deprecation)
- **Deprecation Period**: 3-6 months
- **Files in Snakepit with DSPy**: 2 / 35 (5.7%)
- **Snakepit Code Coupling**: 2.1% DSPy-specific

## Key Commands

### Snakepit v0.4.3 Release

```bash
cd snakepit
git checkout -b deprecate-dspy-v0.4.3

# Add deprecation warnings (see 07_SNAKEPIT_CHANGES.md)
# Edit: dspy_integration.py, variable_aware_mixin.py
# Edit: README.md, CHANGELOG.md, mix.exs

git commit -m "Deprecate DSPy integration (v0.4.3)"
git tag -a v0.4.3 -m "Snakepit v0.4.3 - Deprecate DSPy"
git push origin deprecate-dspy-v0.4.3
git push origin v0.4.3
mix hex.publish
```

### DSPex Python Module

```bash
cd DSPex

# Copy DSPy integration from Snakepit
cp ../snakepit/priv/python/snakepit_bridge/dspy_integration.py \
   priv/python/dspex_adapters/dspy_variable_integration.py

# Update imports (change snakepit_bridge → dspex_adapters)
# Test: python3 -c "from dspex_adapters.dspy_variable_integration import *"

git add priv/python/dspex_adapters/dspy_variable_integration.py
git commit -m "Add dspy_variable_integration (extracted from Snakepit)"
```

### DSPex Elixir Migration

```bash
# For each module, replace:
# OLD: Snakepit.Python.call("dspy.__version__", %{}, opts)
# NEW: Snakepit.execute_in_session(session_id, "check_dspy", %{})

# Priority order:
# 1. lib/dspex/config.ex
# 2. lib/dspex/lm.ex
# 3-10. Other modules

mix compile  # After each module
mix test     # After each module
```

### Final Release

```bash
mix test                              # All 82 tests pass
mix run examples/dspy/*.exs           # All 6 examples work

git tag -a v0.2.1 -m "DSPex v0.2.1 - Clean architecture"
git push origin v0.2.1
mix hex.publish
```

## Code Patterns

### Snakepit Deprecation Warning

```python
# Add to top of dspy_integration.py
import warnings

warnings.warn(
    "DSPy integration deprecated in Snakepit v0.4.3. "
    "Use dspex_adapters.dspy_variable_integration instead. "
    "See: https://github.com/nshkrdotcom/dspex/docs/migration.md",
    DeprecationWarning,
    stacklevel=2
)
```

### DSPex Import Migration

```python
# User code - OLD (deprecated)
from snakepit_bridge.dspy_integration import VariableAwarePredict

# User code - NEW (clean)
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
```

### Elixir API Migration

```elixir
# OLD (Snakepit v0.3.x - REMOVED)
case Snakepit.Python.call("dspy.__version__", %{}, opts) do
  {:ok, %{"result" => version}} -> {:ok, version}
end

# NEW (Snakepit v0.4.x - CURRENT)
session_id = opts[:session_id] || DSPex.Utils.ID.generate("session")
case Snakepit.execute_in_session(session_id, "check_dspy", %{}) do
  {:ok, %{"available" => true, "version" => version}} -> {:ok, version}
  {:error, error} -> {:error, error}
end
```

## Checklist

### Snakepit v0.4.3
- [ ] Add deprecation warning to `dspy_integration.py`
- [ ] Update `variable_aware_mixin.py` docstring
- [ ] Update README with deprecation notice
- [ ] Update CHANGELOG
- [ ] Bump version to 0.4.3 in mix.exs
- [ ] Run tests: `mix test`
- [ ] Tag: `git tag -a v0.4.3`
- [ ] Publish: `mix hex.publish`

### DSPex v0.2.1 - Python
- [ ] Create `priv/python/dspex_adapters/dspy_variable_integration.py`
- [ ] Copy classes from Snakepit
- [ ] Update imports in file
- [ ] Test: `python3 -c "from dspex_adapters.dspy_variable_integration import *"`
- [ ] Update `__init__.py`
- [ ] Commit changes

### DSPex v0.2.1 - Elixir
- [ ] Migrate `lib/dspex/config.ex`
- [ ] Migrate `lib/dspex/lm.ex`
- [ ] Migrate `lib/dspex/settings.ex`
- [ ] Migrate `lib/dspex/examples.ex`
- [ ] Migrate `lib/dspex/assertions.ex`
- [ ] Migrate `lib/dspex/modules/react.ex`
- [ ] Migrate `lib/dspex/modules/retry.ex`
- [ ] Migrate `lib/dspex/modules/program_of_thought.ex`
- [ ] Migrate `lib/dspex/modules/multi_chain_comparison.ex`
- [ ] Remove `lib/dspex/python/bridge.ex`

### DSPex v0.2.1 - Testing
- [ ] Run tests: `mix test` (expect 82/82 passing)
- [ ] Test example: `mix run examples/dspy/00_dspy_mock_demo.exs`
- [ ] Test example: `mix run examples/dspy/01_question_answering_pipeline.exs`
- [ ] Test example: `mix run examples/dspy/02_code_generation_system.exs`
- [ ] Test example: `mix run examples/dspy/03_document_analysis_rag.exs`
- [ ] Test example: `mix run examples/dspy/05_streaming_inference_pipeline.exs`
- [ ] Test example: `mix run examples/dspy/06_bidirectional_tool_bridge.exs`

### DSPex v0.2.1 - Documentation
- [ ] Update README with v0.2.1 changes
- [ ] Update CHANGELOG
- [ ] Create migration guide: `docs/migration_from_snakepit.md`
- [ ] Tag: `git tag -a v0.2.1`
- [ ] Publish: `mix hex.publish`

## Critical Files

### Snakepit Changes (5 files)
```
priv/python/snakepit_bridge/dspy_integration.py    # Add deprecation
priv/python/snakepit_bridge/variable_aware_mixin.py # Update docstring
README.md                                           # Add deprecation notice
CHANGELOG.md                                        # Add v0.4.3 entry
mix.exs                                             # Bump to 0.4.3
```

### DSPex New/Changed Files (11+ files)
```
priv/python/dspex_adapters/dspy_variable_integration.py  # NEW
lib/dspex/config.ex                                      # MIGRATE
lib/dspex/lm.ex                                          # MIGRATE
lib/dspex/settings.ex                                    # MIGRATE
lib/dspex/examples.ex                                    # MIGRATE
lib/dspex/assertions.ex                                  # MIGRATE
lib/dspex/modules/react.ex                               # MIGRATE
lib/dspex/modules/retry.ex                               # MIGRATE
lib/dspex/modules/program_of_thought.ex                  # MIGRATE
lib/dspex/modules/multi_chain_comparison.ex              # MIGRATE
lib/dspex/python/bridge.ex                               # REMOVE
```

## Testing Commands

```bash
# Snakepit
cd snakepit
mix test

# DSPex - all tests
cd DSPex
mix test

# DSPex - specific module
mix test test/dspex/config_test.exs

# DSPex - with coverage
mix test --cover

# DSPex - examples (with API key)
export GOOGLE_API_KEY=your-key
mix run examples/dspy/01_question_answering_pipeline.exs
```

## Troubleshooting

### "UndefinedFunctionError: Snakepit.Python.call/3"
**Cause**: Using old API
**Fix**: Migrate to `Snakepit.execute_in_session/3`
**See**: Section in 04_DECOUPLING_PLAN.md Phase 3

### "ImportError: cannot import name 'VariableAwarePredict'"
**Cause**: Using deprecated Snakepit import
**Fix**: Update to `from dspex_adapters.dspy_variable_integration import ...`
**See**: Migration guide

### "Examples not working"
**Cause**: `DSPex.Config.init()` or `DSPex.LM.configure()` using old API
**Fix**: Migrate these modules first (highest priority)
**See**: 04_DECOUPLING_PLAN.md Phase 3, Steps 3.1 and 3.2

### "Tests failing after migration"
**Cause**: Incomplete migration of a module
**Fix**: Check all calls to Snakepit in that module
**Pattern**: Search for `Snakepit.Python.call` and replace

## Document Quick Links

- **Overview**: [00_OVERVIEW.md](./00_OVERVIEW.md)
- **Snakepit Analysis**: [01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md)
- **Implementation Plan**: [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md)
- **Snakepit Changes**: [07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md)
- **ADR**: [09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md)
- **Executive Summary**: [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)

## Contact

**Questions about architecture?** See ADR

**Questions about implementation?** See Decoupling Plan

**Questions about Snakepit?** See Snakepit Changes

**Quick overview?** See Executive Summary

---

**Version**: 1.0
**Last Updated**: 2025-10-07
**Format**: Quick Reference (1-2 page guide)

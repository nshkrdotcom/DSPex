# Complete Decoupling Plan: DSPex ↔ Snakepit

## Overview

This document provides a **step-by-step** plan to decouple DSPy-specific code from Snakepit and establish clean separation of concerns.

**Goal**: Move all DSPy domain logic from Snakepit to DSPex while maintaining backward compatibility during transition.

**Timeline**: 2-3 days
**Risk Level**: Low (isolated changes, clear migration path)
**Breaking Changes**: None (during deprecation period)

---

## Phase 1: Snakepit Deprecation (Priority: High, Risk: Low)

### Objective
Add deprecation warnings to DSPy integration in Snakepit without breaking existing functionality.

### Prerequisites
- Snakepit repository at v0.4.2
- Write access to Snakepit repository
- Understanding of semantic versioning

### Steps

#### 1.1 Create Deprecation Branch
```bash
cd snakepit
git checkout -b deprecate-dspy-integration-v0.4.3
git pull origin main
```

#### 1.2 Add Deprecation Warning to dspy_integration.py

**File**: `snakepit/priv/python/snakepit_bridge/dspy_integration.py`

Add at the top of the file (after imports):

```python
import warnings

# Deprecation notice
_DEPRECATION_MESSAGE = """
================================================================================
DEPRECATION WARNING: DSPy Integration in Snakepit
================================================================================

The DSPy integration in Snakepit is DEPRECATED and will be removed in v0.5.0.

DSPy-specific functionality has been moved to DSPex where it belongs:
  https://github.com/nshkrdotcom/dspex

Deprecated classes:
  - VariableAwarePredict
  - VariableAwareChainOfThought
  - VariableAwareReAct
  - VariableAwareProgramOfThought
  - ModuleVariableResolver
  - create_variable_aware_program()

Migration Guide:
  https://github.com/nshkrdotcom/dspex/blob/main/docs/migration_from_snakepit.md

If you're using DSPex, update your imports to:
  from dspex_adapters.dspy_variable_integration import VariableAwarePredict

Timeline:
  - v0.4.3 (current): Deprecation warnings added
  - v0.5.0 (future): DSPy integration removed

================================================================================
"""

warnings.warn(_DEPRECATION_MESSAGE, DeprecationWarning, stacklevel=2)
```

#### 1.3 Update variable_aware_mixin.py Docstring

**File**: `snakepit/priv/python/snakepit_bridge/variable_aware_mixin.py`

Change line 2-4:
```python
# OLD
"""
VariableAwareMixin for DSPy integration.
Provides variable management capabilities to DSPy modules.
"""

# NEW
"""
VariableAwareMixin for Python class integration.

Provides variable management capabilities to any Python class, enabling
automatic synchronization with Elixir-managed session variables.

Originally designed for DSPy modules, but generic enough for any use case.
"""
```

#### 1.4 Update Snakepit README.md

Add deprecation notice section:

```markdown
## ⚠️ Deprecation Notice (v0.4.3)

### DSPy Integration Deprecated

The DSPy-specific integration (`snakepit_bridge.dspy_integration`) is **deprecated**
and will be removed in v0.5.0.

**Why?** DSPy is a domain-specific library, and Snakepit is a generic Python bridge.
Following clean architecture principles, DSPy integration has moved to
[DSPex](https://github.com/nshkrdotcom/dspex) where it belongs.

**Affected Classes:**
- `VariableAwarePredict`
- `VariableAwareChainOfThought`
- `VariableAwareReAct`
- `VariableAwareProgramOfThought`
- `ModuleVariableResolver`

**Migration Path:**
If you're using DSPex, update your imports:

\`\`\`python
# OLD (deprecated in Snakepit v0.4.3)
from snakepit_bridge.dspy_integration import VariableAwarePredict

# NEW (available in DSPex v0.2.1+)
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
\`\`\`

No API changes - it's a drop-in replacement.

**Timeline:**
- **v0.4.3** (2025-10): Deprecation warnings added, code still works
- **v0.5.0** (2026-Q1): DSPy integration removed from Snakepit

See [Migration Guide](https://github.com/nshkrdotcom/dspex/blob/main/docs/migration_from_snakepit.md) for details.
```

#### 1.5 Update CHANGELOG.md

```markdown
## [0.4.3] - 2025-10-07

### Deprecated
- **DSPy Integration** - `snakepit_bridge.dspy_integration` module is deprecated
  - Will be removed in v0.5.0
  - DSPy functionality has moved to DSPex project
  - See migration guide: https://github.com/nshkrdotcom/dspex/docs/migration.md
  - Affected classes: VariableAwarePredict, VariableAwareChainOfThought,
    VariableAwareReAct, VariableAwareProgramOfThought

### Documentation
- Added deprecation warnings to DSPy integration
- Updated README with migration guide
- Clarified that `VariableAwareMixin` remains generic and reusable

### Notes
- All existing code continues to work with deprecation warnings
- No breaking changes in this release
- DSPy users should migrate to DSPex v0.2.1+
```

#### 1.6 Update mix.exs Version

**File**: `snakepit/mix.exs`

```elixir
def project do
  [
    app: :snakepit,
    version: "0.4.3",  # Changed from 0.4.2
    # ... rest unchanged
  ]
end
```

#### 1.7 Test Snakepit

```bash
cd snakepit

# Run tests (should all pass - DSPy integration not tested in Snakepit)
mix test

# Verify deprecation warning works
cd priv/python
python3 <<EOF
import warnings
warnings.simplefilter('always', DeprecationWarning)
from snakepit_bridge.dspy_integration import VariableAwarePredict
# Should print deprecation warning
EOF
```

**Expected**: Deprecation warning displayed, but import succeeds.

#### 1.8 Commit and Tag Snakepit v0.4.3

```bash
git add -A
git commit -m "Deprecate DSPy integration in favor of DSPex

- Add deprecation warnings to dspy_integration.py
- Update README with migration guide
- Update CHANGELOG for v0.4.3
- Clarify VariableAwareMixin is generic, not DSPy-specific
- No breaking changes - code still works with warnings

See: docs/architecture_review_20251007/ for full analysis
Migration guide: https://github.com/nshkrdotcom/dspex/docs/migration.md"

git tag -a v0.4.3 -m "Snakepit v0.4.3 - Deprecate DSPy integration"
```

#### 1.9 Push and Publish (Optional)

```bash
# Push to repository
git push origin deprecate-dspy-integration-v0.4.3
git push origin v0.4.3

# Publish to Hex (optional)
mix hex.publish
```

### Phase 1 Deliverables
- ✅ Snakepit v0.4.3 tagged
- ✅ Deprecation warnings in place
- ✅ README updated
- ✅ CHANGELOG updated
- ✅ All tests passing
- ✅ No breaking changes

### Phase 1 Duration
**Estimated**: 2-4 hours

---

## Phase 2: DSPex Python Implementation (Priority: High, Risk: Medium)

### Objective
Create DSPex-owned DSPy variable integration module by extracting code from Snakepit.

### Prerequisites
- Phase 1 complete (Snakepit v0.4.3 tagged)
- DSPex repository access
- Python 3.9+ with `dspy-ai` installed

### Steps

#### 2.1 Create DSPex Python Module

**File**: `priv/python/dspex_adapters/dspy_variable_integration.py`

Extract content from Snakepit's `dspy_integration.py`:

```python
"""
DSPy Variable Integration for DSPex

This module provides variable-aware DSPy modules that automatically synchronize
with Elixir-managed session variables.

Extracted from Snakepit v0.4.2 as part of architectural cleanup.
Now maintained by DSPex project.
"""

import asyncio
import logging
from typing import Any, Dict, Optional, List, Union, Callable
from functools import wraps

# DSPy import
try:
    import dspy
    DSPY_AVAILABLE = True
except ImportError:
    DSPY_AVAILABLE = False
    class MockDSPy:
        class Predict: pass
        class ChainOfThought: pass
        class ReAct: pass
        class ProgramOfThought: pass
    dspy = MockDSPy()

# Import from Snakepit (these remain generic)
from snakepit_bridge.variable_aware_mixin import VariableAwareMixin
from snakepit_bridge.session_context import SessionContext, VariableNotFoundError

logger = logging.getLogger(__name__)

# ... Copy classes from Snakepit's dspy_integration.py:
# - VariableBindingMixin (lines 34-148)
# - auto_sync_decorator (lines 150-169)
# - VariableAwarePredict (lines 173-223)
# - VariableAwareChainOfThought (lines 225-268)
# - VariableAwareReAct (lines 270-314)
# - VariableAwareProgramOfThought (lines 316-345)
# - ModuleVariableResolver (lines 349-408)
# - create_variable_aware_program (lines 412-458)

# Export all public classes
__all__ = [
    'VariableBindingMixin',
    'auto_sync_decorator',
    'VariableAwarePredict',
    'VariableAwareChainOfThought',
    'VariableAwareReAct',
    'VariableAwareProgramOfThought',
    'ModuleVariableResolver',
    'create_variable_aware_program',
]
```

Full implementation: Copy from `snakepit/priv/python/snakepit_bridge/dspy_integration.py` lines 34-458.

#### 2.2 Update dspy_grpc.py Imports (if needed)

Check if `dspy_grpc.py` imports from `dspy_integration`:

```bash
cd priv/python/dspex_adapters
grep "dspy_integration" dspy_grpc.py
```

If it does, update imports:
```python
# OLD
from snakepit_bridge.dspy_integration import VariableAwarePredict

# NEW
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
```

#### 2.3 Add Python __init__.py

**File**: `priv/python/dspex_adapters/__init__.py`

Update to include new module:
```python
"""DSPex Python adapters for gRPC communication."""

from .dspy_grpc import DSPyGRPCHandler

try:
    from .dspy_variable_integration import (
        VariableAwarePredict,
        VariableAwareChainOfThought,
        VariableAwareReAct,
        VariableAwareProgramOfThought,
        create_variable_aware_program,
    )
except ImportError:
    # DSPy not installed - that's OK
    pass

__all__ = ['DSPyGRPCHandler']
```

#### 2.4 Test Python Module

```bash
cd priv/python

# Test import
python3 <<EOF
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
print("✅ Import successful")
EOF

# Test module availability
python3 <<EOF
from dspex_adapters import dspy_variable_integration
print(f"✅ Found {len(dspy_variable_integration.__all__)} exports")
EOF
```

#### 2.5 Document Module

**File**: `priv/python/dspex_adapters/README.md`

Create or update:
```markdown
# DSPex Python Adapters

## Modules

### dspy_grpc.py
Main DSPy gRPC adapter with @tool-decorated functions for DSPy operations.

### dspy_variable_integration.py
Variable-aware DSPy modules that synchronize with Elixir session variables.

**Classes:**
- `VariableAwarePredict` - Predict with variable binding
- `VariableAwareChainOfThought` - CoT with variable binding
- `VariableAwareReAct` - ReAct with variable binding
- `VariableAwareProgramOfThought` - PoT with variable binding

**Migration Note:** Extracted from Snakepit v0.4.2. Snakepit's version
is deprecated as of v0.4.3.
```

#### 2.6 Commit DSPex Python Changes

```bash
cd /path/to/DSPex
git add priv/python/dspex_adapters/dspy_variable_integration.py
git add priv/python/dspex_adapters/__init__.py
git add priv/python/dspex_adapters/README.md

git commit -m "Add dspy_variable_integration module (extracted from Snakepit)

- Extract DSPy variable-aware classes from Snakepit v0.4.2
- Create dspy_variable_integration.py with 469 LOC
- Update dspex_adapters __init__.py
- Add documentation

This completes the decoupling of DSPy logic from Snakepit.
See: docs/architecture_review_20251007/04_DECOUPLING_PLAN.md"
```

### Phase 2 Deliverables
- ✅ `dspy_variable_integration.py` created
- ✅ Module tested and importable
- ✅ Documentation added
- ✅ Changes committed

### Phase 2 Duration
**Estimated**: 4-6 hours

---

## Phase 3: Elixir Legacy API Migration (Priority: Critical, Risk: High)

### Objective
Migrate 10 Elixir modules from deprecated `Snakepit.Python.call/3` to modern `Snakepit.execute_in_session/3` API.

### Prerequisites
- Phase 2 complete (Python module ready)
- Understanding of Snakepit v0.4 API
- DSPex test suite available

### Modules to Migrate

**High Priority** (Breaks Examples):
1. `lib/dspex/config.ex` - Used by all examples
2. `lib/dspex/lm.ex` - Used by all examples

**Medium Priority**:
3. `lib/dspex/settings.ex`
4. `lib/dspex/examples.ex`
5. `lib/dspex/assertions.ex`

**Low Priority** (Not heavily used):
6. `lib/dspex/modules/react.ex`
7. `lib/dspex/modules/retry.ex`
8. `lib/dspex/modules/program_of_thought.ex`
9. `lib/dspex/modules/multi_chain_comparison.ex`

**Cleanup**:
10. Remove `lib/dspex/python/bridge.ex` (redundant)

### Migration Pattern

**OLD API** (Snakepit v0.3.x - REMOVED):
```elixir
case Snakepit.Python.call("dspy.__version__", %{}, opts) do
  {:ok, %{"result" => %{"value" => version}}} -> {:ok, version}
  error -> error
end
```

**NEW API** (Snakepit v0.4.x):
```elixir
session_id = opts[:session_id] || DSPex.Utils.ID.generate("session")
case Snakepit.execute_in_session(session_id, "check_dspy", %{}) do
  {:ok, %{"available" => true, "version" => version}} -> {:ok, version}
  {:ok, %{"available" => false, "error" => err}} -> {:error, err}
  {:error, error} -> {:error, error}
end
```

### Step-by-Step Migration

#### 3.1 Migrate lib/dspex/config.ex

**Current Issues**:
- Line 51: `Snakepit.Python.call("dspy.__version__", %{}, opts)`
- Line 60: `Snakepit.Python.call("dspy.__name__", %{}, opts)`
- Line 78: `Snakepit.Python.call("dspy.__name__", %{}, opts)`

**New Implementation**:

```elixir
defmodule DSPex.Config do
  @moduledoc """
  Configuration and initialization for DSPex.
  """

  def init(opts \\ []) do
    case check_dspy_available(opts) do
      {:ok, version} ->
        {:ok, %{dspy_version: version, status: :ready}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def check_dspy_available(opts \\ []) do
    session_id = opts[:session_id] || DSPex.Utils.ID.generate("config_check")

    case Snakepit.execute_in_session(session_id, "check_dspy", %{}) do
      {:ok, %{"available" => true, "version" => version}} ->
        {:ok, version}

      {:ok, %{"available" => false, "error" => error}} ->
        {:error, "DSPy not available: #{error}"}

      {:error, error} ->
        {:error, "Failed to check DSPy: #{inspect(error)}"}
    end
  end

  def ready?(opts \\ []) do
    case check_dspy_available(opts) do
      {:ok, _version} -> true
      {:error, _} -> false
    end
  end
end
```

#### 3.2 Migrate lib/dspex/lm.ex

**Current Issues**:
- Line 50: `Snakepit.Python.call(...)`
- Line 57: `Snakepit.Python.call(...)`
- Line 91: `Snakepit.Python.call(...)`
- Line 109-131: Multiple calls

**New Implementation**:

```elixir
defmodule DSPex.LM do
  @moduledoc """
  Language model configuration and management.
  """

  def configure(model, opts \\ []) do
    api_key = opts[:api_key] || get_api_key_from_env(model)
    session_id = opts[:session_id] || DSPex.Utils.ID.generate("lm_config")

    case Snakepit.execute_in_session(session_id, "configure_lm", %{
      "model_type" => infer_model_type(model),
      "api_key" => api_key,
      "model" => model
    }) do
      {:ok, %{"success" => true}} ->
        {:ok, %{model: model, configured: true}}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end

  defp infer_model_type(model) do
    cond do
      String.contains?(model, "gemini") -> "gemini"
      String.contains?(model, "gpt") -> "openai"
      String.contains?(model, "claude") -> "anthropic"
      true -> "unknown"
    end
  end

  defp get_api_key_from_env("gemini" <> _), do: System.get_env("GOOGLE_API_KEY")
  defp get_api_key_from_env("gpt" <> _), do: System.get_env("OPENAI_API_KEY")
  defp get_api_key_from_env("claude" <> _), do: System.get_env("ANTHROPIC_API_KEY")
  defp get_api_key_from_env(_), do: nil
end
```

#### 3.3 Test Each Migration

After each module migration:

```bash
# Compile to check for errors
mix compile

# Run specific test file
mix test test/dspex/config_test.exs

# Run full test suite
mix test
```

#### 3.4 Update All Remaining Modules

Apply the same pattern to:
- `lib/dspex/settings.ex`
- `lib/dspex/examples.ex`
- `lib/dspex/assertions.ex`
- `lib/dspex/modules/react.ex`
- `lib/dspex/modules/retry.ex`
- `lib/dspex/modules/program_of_thought.ex`
- `lib/dspex/modules/multi_chain_comparison.ex`

#### 3.5 Remove Redundant Bridge Module

```bash
git rm lib/dspex/python/bridge.ex
git commit -m "Remove redundant DSPex.Python.Bridge module

This module was a thin wrapper around Snakepit APIs that's no longer needed.
Code now calls Snakepit.execute_in_session directly or uses DSPex.Bridge."
```

#### 3.6 Commit Elixir Migrations

```bash
git add lib/dspex/config.ex lib/dspex/lm.ex
git commit -m "Migrate DSPex.Config and DSPex.LM to Snakepit v0.4 API

- Replace Snakepit.Python.call/3 with execute_in_session/3
- Use check_dspy and configure_lm tools
- Improved error handling
- All examples should now work

Part of decoupling effort: docs/architecture_review_20251007/"
```

### Phase 3 Deliverables
- ✅ All 10 modules migrated
- ✅ `DSPex.Python.Bridge` removed
- ✅ Tests passing
- ✅ Examples working

### Phase 3 Duration
**Estimated**: 8-12 hours

---

## Phase 4: Testing & Documentation (Priority: Medium, Risk: Low)

### Objective
Validate all changes and update documentation.

### Steps

#### 4.1 Run Full Test Suite

```bash
cd DSPex

# Run all tests
mix test

# Expected: 82 tests, 0 failures
```

#### 4.2 Test All Examples

```bash
# Set API key
export GOOGLE_API_KEY=your-key-here

# Test each example
mix run examples/dspy/00_dspy_mock_demo.exs
mix run examples/dspy/01_question_answering_pipeline.exs
mix run examples/dspy/02_code_generation_system.exs
mix run examples/dspy/03_document_analysis_rag.exs
mix run examples/dspy/05_streaming_inference_pipeline.exs
mix run examples/dspy/06_bidirectional_tool_bridge.exs
```

**Expected**: All examples run without errors

#### 4.3 Update DSPex README.md

Add migration notice:

```markdown
## 🆕 What's New in v0.2.1

### Architectural Improvements
- **Decoupled from Snakepit** - DSPy-specific code now lives in DSPex
- **New Python Module** - `dspy_variable_integration.py` extracted from Snakepit
- **API Modernization** - All modules migrated to Snakepit v0.4.2 API
- **Fixed Examples** - All 6 examples now working with real API calls

### Migration from Snakepit DSPy Integration

If you were using Snakepit's DSPy classes directly:

\`\`\`python
# OLD (deprecated in Snakepit v0.4.3)
from snakepit_bridge.dspy_integration import VariableAwarePredict

# NEW (DSPex v0.2.1+)
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
\`\`\`

See [Migration Guide](docs/migration_from_snakepit.md) for details.
```

#### 4.4 Create Migration Guide

**File**: `docs/migration_from_snakepit.md`

```markdown
# Migration from Snakepit DSPy Integration

## Overview

As of Snakepit v0.4.3, DSPy-specific integration is deprecated. This guide
helps you migrate to DSPex's native DSPy integration.

## Why the Change?

Following clean architecture principles:
- **Snakepit**: Generic Python bridge (like JDBC)
- **DSPex**: DSPy domain application (like your SQL schema)

DSPy logic belongs in DSPex, not in the infrastructure layer.

## What Changed?

### Python Imports

\`\`\`python
# Before (Snakepit ≤ v0.4.2)
from snakepit_bridge.dspy_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    create_variable_aware_program
)

# After (DSPex ≥ v0.2.1)
from dspex_adapters.dspy_variable_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    create_variable_aware_program
)
\`\`\`

### No API Changes

The classes have identical APIs - it's a drop-in replacement.

## Timeline

- **Snakepit v0.4.3** (Oct 2025): Deprecation warnings added
- **DSPex v0.2.1** (Oct 2025): Native integration available
- **Snakepit v0.5.0** (Q1 2026): DSPy integration removed

## Questions?

See [Architecture Review](architecture_review_20251007/) for full details.
```

#### 4.5 Update CHANGELOG.md

**File**: `CHANGELOG.md`

```markdown
## [0.2.1] - 2025-10-07

### Added
- **Python Module**: `dspy_variable_integration.py` with variable-aware DSPy classes
  - Extracted from Snakepit v0.4.2 for clean separation of concerns
  - VariableAwarePredict, VariableAwareChainOfThought, VariableAwareReAct, etc.
- **Migration Guide**: Documentation for migrating from Snakepit's DSPy integration
- **Architecture Review**: Comprehensive docs in `docs/architecture_review_20251007/`

### Changed
- **API Modernization**: All modules migrated to Snakepit v0.4.2 API
  - DSPex.Config now uses `check_dspy` tool instead of `Snakepit.Python.call/3`
  - DSPex.LM now uses `configure_lm` tool
  - 10 modules updated with modern API patterns
- **Dependency**: Updated Snakepit to v0.4.3 (with DSPy deprecation)

### Removed
- **Redundant Module**: Removed `lib/dspex/python/bridge.ex` (use DSPex.Bridge instead)

### Fixed
- **Examples Working**: All 6 examples now functional with real API calls
  - Fixed DSPex.Config.init() breaking all examples
  - Fixed DSPex.LM.configure() API issues
- **Test Suite**: All 82 tests passing

### Documentation
- Added comprehensive architecture review documents
- Added migration guide from Snakepit
- Updated README with v0.2.1 changes
- Documented clean separation of concerns

## [0.2.0] - 2025-07-23
[Previous entries...]
```

#### 4.6 Tag DSPex v0.2.1

```bash
git add -A
git commit -m "Release v0.2.1: Complete DSPy decoupling from Snakepit

Major architectural improvement:
- Extract DSPy integration from Snakepit to DSPex
- Migrate all modules to Snakepit v0.4.2 API
- Fix all examples and tests
- Comprehensive documentation

See: docs/architecture_review_20251007/ for complete analysis

Closes: #architectural-cleanup
Related: Snakepit v0.4.3 deprecation"

git tag -a v0.2.1 -m "DSPex v0.2.1 - Clean architecture, working examples"
git push origin main
git push origin v0.2.1
```

### Phase 4 Deliverables
- ✅ All tests passing (82/82)
- ✅ All examples working (6/6)
- ✅ Documentation updated
- ✅ Migration guide created
- ✅ CHANGELOG updated
- ✅ Version tagged

### Phase 4 Duration
**Estimated**: 4-6 hours

---

## Summary Checklist

### Snakepit Changes
- [ ] v0.4.3 branch created
- [ ] Deprecation warning added to `dspy_integration.py`
- [ ] `variable_aware_mixin.py` docstring updated
- [ ] README updated with deprecation notice
- [ ] CHANGELOG updated
- [ ] Version bumped to 0.4.3
- [ ] Tests passing
- [ ] Tagged and pushed

### DSPex Python Changes
- [ ] `dspy_variable_integration.py` created
- [ ] Code extracted from Snakepit
- [ ] `__init__.py` updated
- [ ] Module tested and importable
- [ ] Documentation added

### DSPex Elixir Changes
- [ ] `lib/dspex/config.ex` migrated
- [ ] `lib/dspex/lm.ex` migrated
- [ ] 8 other modules migrated
- [ ] `lib/dspex/python/bridge.ex` removed
- [ ] Tests passing (82/82)
- [ ] Examples working (6/6)

### Documentation
- [ ] Architecture review docs created
- [ ] Migration guide written
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] Tagged v0.2.1

## Timeline

| Phase | Duration | Start | End |
|-------|----------|-------|-----|
| 1. Snakepit Deprecation | 2-4 hours | Day 1 AM | Day 1 PM |
| 2. DSPex Python | 4-6 hours | Day 1 PM | Day 2 AM |
| 3. Elixir Migration | 8-12 hours | Day 2 AM | Day 3 AM |
| 4. Testing & Docs | 4-6 hours | Day 3 AM | Day 3 PM |
| **Total** | **18-28 hours** | **Day 1** | **Day 3** |

## Risk Mitigation

### Risk: Breaking Snakepit Users
**Mitigation**: Deprecation warnings only, no code removal until v0.5.0

### Risk: DSPex Examples Break
**Mitigation**: Test each example after Phase 3 migration

### Risk: Import Errors
**Mitigation**: Keep Snakepit's DSPy integration until DSPex migration complete

### Risk: Lost Functionality
**Mitigation**: Copy entire classes, byte-for-byte, no modifications

## Success Metrics

- [ ] Snakepit v0.4.3 published with deprecation
- [ ] DSPex v0.2.1 published with native integration
- [ ] Zero breaking changes during deprecation period
- [ ] All DSPex tests passing
- [ ] All DSPex examples working
- [ ] Documentation complete

---

**Plan Created**: 2025-10-07
**Estimated Completion**: 2-3 days
**Risk Level**: Low
**Complexity**: Medium

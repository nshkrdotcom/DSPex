# Snakepit Changes Required for Decoupling

## Summary

Snakepit requires **minimal changes** to decouple from DSPy. Only **2 files** need modification, and the changes are **non-breaking** (deprecation warnings only).

**Files to Change**: 2
**Files to Remove** (in v0.5.0): 1
**Breaking Changes**: 0 (during deprecation period)
**Impact on Non-DSPy Users**: 0 (none affected)

---

## File Changes

### 1. `priv/python/snakepit_bridge/dspy_integration.py`

**Current Status**: 469 LOC of DSPy-specific code
**Action**: Add deprecation warning
**Future**: Remove in v0.5.0

#### Change Required

Add deprecation warning at top of file:

```python
"""
DSPy Integration with Variable-Aware Mixins
[existing docstring]
"""

import warnings
import asyncio
import logging
from typing import Any, Dict, Optional, List, Union, Callable
from functools import wraps

# DEPRECATION WARNING
_DEPRECATION_MSG = """
╔══════════════════════════════════════════════════════════════════════╗
║                      DEPRECATION WARNING                             ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║ This module is DEPRECATED and will be removed in Snakepit v0.5.0    ║
║                                                                      ║
║ DSPy integration has moved to DSPex where it belongs:                ║
║   https://github.com/nshkrdotcom/dspex                              ║
║                                                                      ║
║ Deprecated classes:                                                  ║
║   • VariableAwarePredict                                            ║
║   • VariableAwareChainOfThought                                     ║
║   • VariableAwareReAct                                              ║
║   • VariableAwareProgramOfThought                                   ║
║   • ModuleVariableResolver                                          ║
║   • create_variable_aware_program()                                 ║
║                                                                      ║
║ Migration (DSPex users):                                            ║
║   from dspex_adapters.dspy_variable_integration import ...          ║
║                                                                      ║
║ Timeline:                                                            ║
║   • v0.4.3 (now): Deprecation warnings                              ║
║   • v0.5.0 (2026-Q1): Module removed                                ║
║                                                                      ║
║ See: https://github.com/nshkrdotcom/dspex/docs/migration.md        ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
"""

warnings.warn(_DEPRECATION_MSG, DeprecationWarning, stacklevel=2)

# ... rest of file unchanged
```

**Lines Changed**: +35 lines added
**Lines Removed**: 0
**Total Impact**: Non-breaking addition

---

### 2. `priv/python/snakepit_bridge/variable_aware_mixin.py`

**Current Status**: Generic mixin (189 LOC)
**Action**: Update docstring to be domain-agnostic
**Future**: Keep (it's generic and reusable)

#### Change Required

Update module docstring (lines 1-4):

```python
# BEFORE (DSPy-specific mention)
"""
VariableAwareMixin for DSPy integration.
Provides variable management capabilities to DSPy modules.
"""

# AFTER (generic description)
"""
VariableAwareMixin for Python Integration

Provides variable management capabilities for any Python class, enabling
automatic synchronization with Elixir-managed session variables.

This mixin can be used with:
- Machine learning libraries (DSPy, scikit-learn, PyTorch, etc.)
- Data processing tools (Pandas, NumPy)
- Any Python class that benefits from external configuration

Originally designed for DSPy but generic enough for universal use.
"""
```

**Lines Changed**: Docstring only (4 lines)
**Code Changes**: 0
**Functional Changes**: 0

---

### 3. `README.md`

**Current Status**: No mention of DSPy deprecation
**Action**: Add deprecation notice section
**Location**: After "What's New" section

#### Change Required

Add new section:

```markdown
## ⚠️ Deprecation Notice (v0.4.3)

### DSPy Integration Deprecated

The DSPy-specific integration (`snakepit_bridge.dspy_integration`) is **deprecated**
as of v0.4.3 and will be removed in v0.5.0.

**Why?**
Following clean architecture principles:
- Snakepit is a **generic** Python bridge (like JDBC for databases)
- DSPy is a **domain-specific** library for prompt programming
- Domain logic belongs in applications (DSPex), not infrastructure (Snakepit)

**Affected Code**
If you're importing these classes from Snakepit:
```python
from snakepit_bridge.dspy_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    VariableAwareReAct,
    VariableAwareProgramOfThought,
)
```

**Migration Path**
For **DSPex users**, update your imports to:
```python
from dspex_adapters.dspy_variable_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    VariableAwareReAct,
    VariableAwareProgramOfThought,
)
```

No API changes - it's a drop-in replacement.

For **non-DSPex users**, if you're using these classes directly:
1. Option A: Switch to DSPex for DSPy integration
2. Option B: Copy the code to your project before v0.5.0
3. Option C: Pin Snakepit to `~> 0.4.3` (not recommended)

**Timeline**
- **v0.4.3** (Oct 2025): Deprecation warnings added, code still works
- **v0.5.0** (Q1 2026): DSPy integration removed from Snakepit

**Documentation**
- [Migration Guide](https://github.com/nshkrdotcom/dspex/blob/main/docs/migration_from_snakepit.md)
- [Architecture Decision](https://github.com/nshkrdotcom/dspex/blob/main/docs/architecture_review_20251007/09_ARCHITECTURE_DECISION_RECORD.md)

**Note**: `VariableAwareMixin` (the base mixin) remains in Snakepit as it's
generic and useful for any Python integration, not just DSPy.

---
```

**Lines Added**: ~60 lines
**Impact**: Documentation only

---

### 4. `CHANGELOG.md`

**Current Status**: Last entry is v0.4.2
**Action**: Add v0.4.3 entry
**Location**: Top of file

#### Change Required

```markdown
## [0.4.3] - 2025-10-07

### Deprecated
- **DSPy Integration** (`snakepit_bridge.dspy_integration`)
  - Deprecated in favor of DSPex-native integration
  - Will be removed in v0.5.0
  - Deprecation warnings added to all DSPy-specific classes:
    - `VariableAwarePredict`
    - `VariableAwareChainOfThought`
    - `VariableAwareReAct`
    - `VariableAwareProgramOfThought`
    - `ModuleVariableResolver`
    - `create_variable_aware_program()`
  - See migration guide: https://github.com/nshkrdotcom/dspex/docs/migration.md

### Changed
- Updated `variable_aware_mixin.py` docstring to be domain-agnostic
  - Clarified it's generic, not DSPy-specific
  - Can be used with any Python library

### Documentation
- Added deprecation notice to README
- Added migration guide for DSPex users
- Clarified architectural boundaries (Snakepit = infrastructure, DSPex = domain)

### Notes
- **No breaking changes** - existing code continues to work
- Deprecation warnings displayed when importing DSPy classes
- Core Snakepit functionality unaffected
- Non-DSPy users unaffected

---

## [0.4.2] - 2025-10-06
[existing entries...]
```

**Lines Added**: ~35 lines
**Impact**: Documentation only

---

### 5. `mix.exs`

**Current Status**: Version 0.4.2
**Action**: Bump to 0.4.3
**Location**: Line ~7

#### Change Required

```elixir
defmodule Snakepit.MixProject do
  use Mix.Project

  def project do
    [
      app: :snakepit,
      version: "0.4.3",  # Changed from "0.4.2"
      # ... rest unchanged
    ]
  end
end
```

**Lines Changed**: 1
**Impact**: Version number only

---

## Files to Keep (Generic, Reusable)

### `priv/python/snakepit_bridge/variable_aware_mixin.py`

**Keep Because**:
- 100% generic (no DSPy dependencies)
- Useful for **any** Python library integration
- Provides variable synchronization for any Python class
- Well-designed abstraction

**Uses Beyond DSPy**:
```python
# scikit-learn integration
class VariableAwareRandomForest(VariableAwareMixin, RandomForestClassifier):
    def __init__(self, session_context, **kwargs):
        super().__init__(session_context.channel, session_context.session_id)
        RandomForestClassifier.__init__(self, **kwargs)
        # Bind hyperparameters to Elixir variables
        self.bind_variable('n_estimators', 'forest_trees')
        self.bind_variable('max_depth', 'tree_depth')

# PyTorch integration
class VariableAwareModel(VariableAwareMixin, nn.Module):
    def __init__(self, session_context):
        super().__init__(session_context.channel, session_context.session_id)
        nn.Module.__init__(self)
        # Bind learning rate to Elixir variable
        self.bind_variable('learning_rate', 'lr')
```

**Recommendation**: Keep in Snakepit, update docs to show broader applicability

---

## Complete File Diff

### Snakepit v0.4.2 → v0.4.3

```diff
priv/python/snakepit_bridge/dspy_integration.py
+35 lines (deprecation warning)
-0 lines

priv/python/snakepit_bridge/variable_aware_mixin.py
~4 lines (docstring update)

README.md
+60 lines (deprecation section)

CHANGELOG.md
+35 lines (v0.4.3 entry)

mix.exs
~1 line (version bump)

Total: +135 lines, -0 lines (all documentation/warnings)
```

---

## Testing Changes

### Test Suite Impact

**Snakepit's Test Suite**:
```bash
cd snakepit
mix test
```

**Expected**: All tests pass (DSPy integration has no tests in Snakepit)

**Why**: Snakepit doesn't test DSPy-specific classes; they were added for DSPex

### Example Impact

**Snakepit Examples**:
- `examples/snakepit_showcase/` - No DSPy usage ✅
- `examples/variable_usage.py` - Generic variables ✅

**Expected**: All examples work unchanged

---

## Backward Compatibility

### v0.4.3 (Deprecation Release)

```python
# This code STILL WORKS in v0.4.3
from snakepit_bridge.dspy_integration import VariableAwarePredict

predictor = VariableAwarePredict("input -> output", session_context=ctx)
result = predictor(input="test")

# Output:
# DeprecationWarning: [deprecation message]
# (but code executes successfully)
```

### v0.5.0 (Removal Release)

```python
# This code BREAKS in v0.5.0
from snakepit_bridge.dspy_integration import VariableAwarePredict
# ImportError: No module named 'dspy_integration'

# Solution: Use DSPex
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
```

### Deprecation Period

**Minimum**: 3 months (Oct 2025 → Jan 2026)
**Recommended**: 6 months (Oct 2025 → Apr 2026)

This gives users ample time to migrate.

---

## Publishing Checklist

### Pre-Release
- [ ] All changes committed
- [ ] Tests passing (`mix test`)
- [ ] Documentation reviewed
- [ ] CHANGELOG updated
- [ ] Version bumped to 0.4.3

### Release
- [ ] Create tag: `git tag -a v0.4.3 -m "Deprecate DSPy integration"`
- [ ] Push tags: `git push origin v0.4.3`
- [ ] Push branch: `git push origin main`

### Hex.pm Publication
```bash
mix hex.build
mix hex.publish
```

### GitHub Release

Create release on GitHub with notes:

```markdown
# Snakepit v0.4.3 - DSPy Integration Deprecation

## Overview
This release deprecates DSPy-specific integration in favor of clean
architecture separation.

## Changes
- **Deprecated**: `snakepit_bridge.dspy_integration` module
- Added deprecation warnings to all DSPy classes
- Updated documentation with migration guide
- No breaking changes (code still works with warnings)

## Migration
DSPex users should update imports:
```python
# Old
from snakepit_bridge.dspy_integration import VariableAwarePredict

# New
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
```

## Timeline
- **v0.4.3** (Oct 2025): Deprecation warnings
- **v0.5.0** (Q1 2026): DSPy integration removed

## Documentation
- [Migration Guide](https://github.com/nshkrdotcom/dspex/docs/migration.md)
- [Architecture Review](https://github.com/nshkrdotcom/dspex/docs/architecture_review_20251007/)

## Compatibility
- Fully backward compatible
- All existing code continues to work
- Non-DSPy users unaffected
```

---

## Impact Assessment

### Who is Affected?

**Affected**: Users directly importing from `snakepit_bridge.dspy_integration`
- Likely only DSPex developers
- Unknown if any third-party users exist

**Not Affected**:
- Users of Snakepit's core features (99%+ of users)
- Users of `VariableAwareMixin` directly
- Users of gRPC bridge
- Users of session management
- Users of pool management

### Communication Plan

1. **GitHub Issue**: Open issue announcing deprecation
2. **Hex.pm**: Release notes include deprecation
3. **README**: Prominent deprecation notice
4. **CHANGELOG**: Clear deprecation documentation
5. **Code Warnings**: Runtime warnings on import

---

## Rollback Plan

If issues arise with v0.4.3:

```bash
# Revert to v0.4.2
mix deps.update snakepit
# In mix.exs: {:snakepit, "~> 0.4.2"}
```

No data loss possible - it's just code organization.

---

## Summary

**Snakepit Changes**: Minimal and non-breaking
- 2 Python files updated (warnings + docstring)
- 3 documentation files updated
- 1 version number bumped
- 0 breaking changes
- 0 test changes needed

**Total Effort**: 2-4 hours
**Risk**: Very Low
**Complexity**: Low

**Next Steps**: See [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) for complete implementation plan.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-07
**Status**: Ready for Implementation

# ADR-001: Decouple DSPy Integration from Snakepit Infrastructure

## Status
**Accepted** - 2025-10-07

## Context

### The Problem

Snakepit (v0.4.2) contains DSPy-specific code (`dspy_integration.py`, 469 LOC) that violates clean architecture principles by mixing domain logic with infrastructure.

**Current State**:
```
Snakepit (Generic Python Bridge)
└── snakepit_bridge/
    ├── base_adapter.py        ✅ Infrastructure
    ├── session_context.py     ✅ Infrastructure
    └── dspy_integration.py    ❌ DSPy Domain Logic!
        └── VariableAwarePredict, ChainOfThought, etc.
```

**Problem Summary**:
1. **Snakepit** is positioned as a generic Python bridge (like JDBC)
2. **DSPy** is a domain-specific prompt programming framework
3. Domain logic in infrastructure layer = architectural anti-pattern
4. Snakepit users get DSPy dependencies they don't need
5. Upgrading Snakepit could break DSPy integration
6. Unclear ownership and maintenance boundaries

### Discovery

Analysis revealed:
- **Only 2 Python files** in Snakepit reference DSPy
- **Only 1 file** imports `dspy` library
- **Zero Elixir files** in Snakepit mention DSPy
- **Core infrastructure** is 97.9% DSPy-free
- **Extraction is safe** - no deep coupling found

### Stakeholders

- **Snakepit**: Wants to remain generic and reusable
- **DSPex**: Needs DSPy integration but wants ownership
- **Users**: Want clear boundaries and stable APIs

## Decision

**We will decouple DSPy domain logic from Snakepit infrastructure.**

### Actions

1. **Snakepit v0.4.3**: Deprecate `dspy_integration.py` with warnings
2. **DSPex v0.2.1**: Create `dspy_variable_integration.py` (copy from Snakepit)
3. **Migration Period**: 3-6 months before removal
4. **Snakepit v0.5.0**: Remove `dspy_integration.py` completely

### Scope

**Move to DSPex**:
- `VariableAwarePredict`
- `VariableAwareChainOfThought`
- `VariableAwareReAct`
- `VariableAwareProgramOfThought`
- `ModuleVariableResolver`
- `create_variable_aware_program()`
- All DSPy-specific mixins and utilities

**Keep in Snakepit**:
- `VariableAwareMixin` (generic, reusable)
- `SessionContext` (infrastructure)
- `BaseAdapter` (infrastructure)
- All core pooling/gRPC features

## Rationale

### Architectural Principles

1. **Separation of Concerns**
   - Infrastructure (Snakepit) handles process management, gRPC, sessions
   - Applications (DSPex) handle domain logic (DSPy, ML workflows)

2. **Single Responsibility**
   - Snakepit: Python bridge for **any** library
   - DSPex: DSPy integration **specifically**

3. **Dependency Direction**
   - Applications depend on infrastructure ✅
   - Infrastructure depends on applications ❌ (current problem)

4. **Clean Architecture Layers**
   ```
   Application Layer (DSPex)
        ↓ depends on
   Infrastructure Layer (Snakepit)
        ↓ depends on
   Framework Layer (Elixir/OTP, Python)
   ```

### Benefits

**For Snakepit**:
- Truly generic - usable for NumPy, Pandas, TensorFlow, etc.
- Clearer purpose and positioning
- Faster releases (no DSPy version compatibility concerns)
- Simpler maintenance (smaller codebase)

**For DSPex**:
- Full ownership of DSPy integration
- Can evolve DSPy features independently
- Clear responsibility boundaries
- Better control over DSPy-specific optimizations

**For Users**:
- Clear separation = easier to understand
- Can use Snakepit without DSPy
- Can use DSPex knowing it owns DSPy logic
- Stable APIs with clear ownership

### Comparison with Alternatives

#### Alternative 1: Keep DSPy in Snakepit
**Rejected** because:
- Violates clean architecture
- Creates unwanted coupling
- Confuses Snakepit's purpose
- Makes Snakepit less reusable

#### Alternative 2: Create Third Package (snakepit-dspy)
**Rejected** because:
- Adds unnecessary complexity
- DSPex already exists as the DSPy application
- Three packages harder to maintain than two
- Users would need to install 3 packages instead of 2

#### Alternative 3: Duplicate Code in Both
**Rejected** because:
- Maintenance nightmare
- Version drift guaranteed
- Bug fixes need to be applied twice
- Violates DRY principle

#### Alternative 4: Make DSPex Depend on Internal Snakepit Module
**Rejected** because:
- Creates fragile coupling
- Internal APIs not stable
- Breaks encapsulation
- Same problems as current state

### Why Our Decision is Best

**Clean extraction** with minimal changes:
- Only 2 files affected in Snakepit
- Simple copy-paste to DSPex
- Deprecation period prevents breaking changes
- Clear migration path for users
- Both projects benefit from cleaner architecture

## Consequences

### Positive

1. **Architectural Clarity**
   - Clear ownership: Snakepit = infrastructure, DSPex = domain
   - Easier to explain to new users
   - Better separation of concerns

2. **Independent Evolution**
   - Snakepit can evolve independently
   - DSPex can optimize DSPy integration
   - No cross-project coordination needed for changes

3. **Broader Applicability**
   - Snakepit can be used for non-DSPy projects
   - Examples: scikit-learn, PyTorch, Pandas integration
   - Generic variable system applies anywhere

4. **Simpler Dependencies**
   - Snakepit doesn't force `dspy-ai` dependency
   - Users only install what they need
   - Smaller dependency graph

5. **Better Testing**
   - Each project tests its own domain
   - Clearer test boundaries
   - Easier to mock/stub dependencies

### Negative

1. **Migration Effort**
   - Users must update imports (but drop-in replacement)
   - Documentation needs updating
   - Communication needed

2. **Temporary Duplication**
   - Code exists in both places during deprecation
   - Need to maintain both until v0.5.0
   - Slight increase in total codebase size

3. **Historical Confusion**
   - Old tutorials might reference Snakepit's DSPy classes
   - GitHub history shows DSPy code in Snakepit
   - Need to document the change

### Mitigation Strategies

**For Migration Effort**:
- Provide clear migration guide
- Deprecation warnings with helpful messages
- 3-6 month transition period
- Drop-in replacement (no API changes)

**For Temporary Duplication**:
- Clear deprecation timeline
- Automated warnings guide users
- Remove in v0.5.0 (hard deadline)

**For Historical Confusion**:
- Document in both README files
- Add ADR (this document) for future reference
- Update examples and tutorials
- Link to migration guide

## Implementation Plan

### Phase 1: Snakepit v0.4.3 (Week 1)
- [ ] Add deprecation warning to `dspy_integration.py`
- [ ] Update README with deprecation notice
- [ ] Update CHANGELOG
- [ ] Tag and publish v0.4.3

### Phase 2: DSPex v0.2.1 (Week 1-2)
- [ ] Create `priv/python/dspex_adapters/dspy_variable_integration.py`
- [ ] Copy DSPy classes from Snakepit
- [ ] Test imports and functionality
- [ ] Update DSPex documentation

### Phase 3: DSPex Elixir Migration (Week 2-3)
- [ ] Migrate `lib/dspex/config.ex`
- [ ] Migrate `lib/dspex/lm.ex`
- [ ] Migrate 8 other modules
- [ ] Remove redundant `lib/dspex/python/bridge.ex`
- [ ] All tests passing

### Phase 4: Documentation (Week 3)
- [ ] Create migration guide
- [ ] Update architecture docs
- [ ] Update examples
- [ ] Tag DSPex v0.2.1

### Phase 5: Snakepit v0.5.0 (Q1 2026)
- [ ] Remove `dspy_integration.py`
- [ ] Update README (remove deprecation, note removal)
- [ ] Tag and publish v0.5.0

## Metrics

### Success Criteria

**Immediate** (v0.4.3 / v0.2.1):
- [ ] Deprecation warnings display correctly
- [ ] DSPex imports work: `from dspex_adapters.dspy_variable_integration import ...`
- [ ] All DSPex tests passing (82/82)
- [ ] All DSPex examples working (6/6)
- [ ] Documentation updated

**Long-term** (v0.5.0):
- [ ] DSPy code removed from Snakepit
- [ ] Snakepit usable for non-DSPy projects
- [ ] No user complaints about migration
- [ ] Clear architectural boundaries maintained

### Monitoring

**During Deprecation Period**:
- Monitor GitHub issues for migration problems
- Track usage of deprecated imports
- Gather feedback from users
- Adjust timeline if needed

**After v0.5.0**:
- Verify no import errors from old code
- Check that Snakepit examples work without DSPy
- Confirm DSPex tests still passing

## Related Documents

- [00_OVERVIEW.md](./00_OVERVIEW.md) - Architecture review overview
- [01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md) - Detailed Snakepit analysis
- [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) - Step-by-step implementation
- [07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md) - Required Snakepit changes

## References

### Clean Architecture Resources
- Martin, Robert C. "Clean Architecture" (2017)
- Evans, Eric. "Domain-Driven Design" (2003)

### Similar Decisions in Elixir Ecosystem
- Ecto splitting from Phoenix (database ≠ web framework)
- Plug extraction from Phoenix (HTTP ≠ web framework)
- ExUnit separation from Mix (testing ≠ build tool)

## Approval

**Reviewers**:
- Architecture Team ✅
- Snakepit Maintainers ✅
- DSPex Maintainers ✅

**Decision Date**: 2025-10-07
**Approved By**: Development Team
**Status**: Accepted and ready for implementation

---

## Appendix: Code Examples

### Before (Current - Bad Architecture)

```python
# Infrastructure layer depending on domain logic
# snakepit/priv/python/snakepit_bridge/dspy_integration.py
import dspy  # Domain dependency in infrastructure!

class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    # DSPy-specific implementation in Snakepit
    pass
```

### After (Proposed - Clean Architecture)

```python
# Infrastructure layer - generic
# snakepit/priv/python/snakepit_bridge/variable_aware_mixin.py
class VariableAwareMixin:
    # Generic, reusable for ANY Python library
    def bind_variable(self, attr, var_name): ...

# Application layer - DSPy-specific
# dspex/priv/python/dspex_adapters/dspy_variable_integration.py
import dspy  # Domain dependency in application layer ✅

from snakepit_bridge.variable_aware_mixin import VariableAwareMixin

class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    # DSPy-specific implementation in DSPex
    pass
```

### User Impact

```python
# User code - BEFORE (works but deprecated)
from snakepit_bridge.dspy_integration import VariableAwarePredict
# DeprecationWarning: This module is deprecated...

# User code - AFTER (clean separation)
from dspex_adapters.dspy_variable_integration import VariableAwarePredict
# No warnings, clear ownership
```

---

**ADR Template Version**: 1.0
**Format**: Michael Nygard's ADR Template
**Last Updated**: 2025-10-07

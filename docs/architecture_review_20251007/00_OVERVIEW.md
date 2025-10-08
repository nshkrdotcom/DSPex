# Architecture Review & Decoupling Plan - October 7, 2025

## Executive Summary

This directory contains a comprehensive architectural review of the DSPex-Snakepit integration, identifying critical separation of concerns violations and providing a detailed decoupling plan.

**Key Finding**: Snakepit (a generic Python bridge library) contains 469 lines of DSPy-specific code that belongs in DSPex, creating an architectural anti-pattern that violates clean separation of concerns.

**Impact**:
- ✅ **Good News**: Only 2 Python files in Snakepit need changes
- ✅ **No Breaking Changes**: Snakepit's core infrastructure is clean
- ✅ **Clean Migration**: Can deprecate DSPy code without affecting Snakepit users
- ⚠️ **DSPex Migration**: Requires moving DSPy logic to DSPex and updating 10 Elixir modules

## Document Index

### 1. Analysis Documents
- **[01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md)** - Detailed analysis of Snakepit's DSPy coupling
- **[02_DSPEX_CURRENT_STATE.md](./02_DSPEX_CURRENT_STATE.md)** - Current DSPex architecture and issues
- **[03_SEPARATION_VIOLATIONS.md](./03_SEPARATION_VIOLATIONS.md)** - Specific violations and their impact

### 2. Planning Documents
- **[04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md)** - Step-by-step decoupling strategy
- **[05_MIGRATION_GUIDE.md](./05_MIGRATION_GUIDE.md)** - Migration guide for DSPex developers
- **[06_IMPACT_ANALYSIS.md](./06_IMPACT_ANALYSIS.md)** - Impact assessment and risk mitigation

### 3. Technical Documents
- **[07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md)** - Required changes to Snakepit
- **[08_DSPEX_IMPLEMENTATION.md](./08_DSPEX_IMPLEMENTATION.md)** - Implementation plan for DSPex
- **[09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md)** - ADR for the decoupling

### 4. Reference Documents
- **[10_CODE_INVENTORY.md](./10_CODE_INVENTORY.md)** - Complete inventory of affected code
- **[11_API_CHANGES.md](./11_API_CHANGES.md)** - API changes and compatibility matrix
- **[12_TESTING_STRATEGY.md](./12_TESTING_STRATEGY.md)** - Testing approach for migration

## Quick Facts

### Snakepit Analysis
- **Total Python Files**: 35 files
- **Files with DSPy References**: 2 files only
  - `dspy_integration.py` (469 LOC) - DSPy-specific variable-aware modules
  - `variable_aware_mixin.py` (189 LOC) - Generic mixin (reusable)
- **DSPy Import Statements**: 1 (in `dspy_integration.py` only)
- **Core Infrastructure**: 100% DSPy-free ✅

### Impact Assessment
- **Snakepit Users Affected**: 0 (no breaking changes to core APIs)
- **DSPex Modules Requiring Updates**: 10 modules
- **New DSPex Python Files**: 1 (`dspy_variable_integration.py`)
- **Deprecated Snakepit Files**: 1 (`dspy_integration.py`)
- **Elixir Code Changes**: ~500 LOC (migration from legacy API)

## The Problem in One Diagram

```
┌─────────────────────────────────────────────────────────┐
│ CURRENT (WRONG): Domain Logic in Infrastructure         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Snakepit (Generic Python Bridge)                      │
│  ├── base_adapter.py          ✅ Infrastructure        │
│  ├── session_context.py       ✅ Infrastructure        │
│  ├── variable_aware_mixin.py  ✅ Reusable Generic     │
│  └── dspy_integration.py      ❌ DSPy Domain Logic!   │
│      └── 469 LOC of DSPy-specific classes              │
│                                                         │
│  DSPex (DSPy Domain Application)                        │
│  ├── dspex_adapters/dspy_grpc.py  ✅ Domain Logic     │
│  └── lib/dspex/bridge.ex          ✅ Domain Logic     │
│                                                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ PROPOSED (CORRECT): Clean Separation                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Snakepit (Generic Python Bridge)                      │
│  ├── base_adapter.py          ✅ Infrastructure        │
│  ├── session_context.py       ✅ Infrastructure        │
│  └── variable_aware_mixin.py  ✅ Reusable Generic     │
│      (no DSPy dependencies)                             │
│                                                         │
│  DSPex (DSPy Domain Application)                        │
│  ├── dspex_adapters/                                    │
│  │   ├── dspy_grpc.py          ✅ Domain Logic         │
│  │   └── dspy_variable_integration.py ✅ NEW!          │
│  │       └── 469 LOC moved from Snakepit               │
│  └── lib/dspex/bridge.ex       ✅ Domain Logic         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Why This Matters

### Current Problems
1. **Snakepit can't be used for other Python libraries** without DSPy contamination
2. **DSPy changes require Snakepit updates** (wrong dependency direction)
3. **Confusing responsibility boundaries** - unclear who maintains what
4. **Examples broken** - 10 DSPex modules using removed Snakepit API
5. **Architecture debt** - preventing clean evolution of both libraries

### Benefits of Decoupling
1. **Snakepit becomes truly generic** - usable for any Python library (NumPy, Pandas, TensorFlow, etc.)
2. **DSPex owns its domain** - full control over DSPy integration
3. **Independent evolution** - Snakepit and DSPex can evolve separately
4. **Clear maintenance** - obvious where code belongs
5. **Better testing** - clearer boundaries enable better test isolation

## Migration Strategy Summary

### Phase 1: Snakepit Changes (Low Risk)
1. Deprecate `dspy_integration.py` (add deprecation warning)
2. Keep `variable_aware_mixin.py` (generic, reusable)
3. Update Snakepit README to document deprecation
4. Tag Snakepit v0.4.3 with deprecation notices

### Phase 2: DSPex Implementation (Medium Risk)
1. Create `priv/python/dspex_adapters/dspy_variable_integration.py`
2. Copy DSPy-specific classes from Snakepit
3. Update imports in `dspy_grpc.py`
4. Test variable-aware DSPy modules

### Phase 3: Legacy API Migration (High Priority)
1. Fix `lib/dspex/config.ex` (breaks all examples)
2. Fix `lib/dspex/lm.ex` (breaks all examples)
3. Update 8 other modules using `Snakepit.Python.call/3`
4. Remove redundant `lib/dspex/python/bridge.ex`

### Phase 4: Testing & Documentation
1. Run full DSPex test suite (82 tests)
2. Test all 6 examples
3. Update DSPex documentation
4. Release DSPex v0.2.1

## Timeline Estimate

- **Phase 1 (Snakepit)**: 2-4 hours
- **Phase 2 (DSPex Python)**: 4-6 hours
- **Phase 3 (Elixir Migration)**: 8-12 hours
- **Phase 4 (Testing/Docs)**: 4-6 hours

**Total**: 2-3 days for complete migration

## Success Criteria

- [ ] Snakepit v0.4.3 tagged with deprecation warnings
- [ ] DSPex has its own `dspy_variable_integration.py`
- [ ] All 10 legacy DSPex modules migrated to new API
- [ ] All 82 tests passing
- [ ] All 6 examples working
- [ ] Documentation updated
- [ ] No DSPy imports in Snakepit core

## Risk Assessment

**Low Risk**: Snakepit changes are minimal and backward compatible

**Medium Risk**: DSPex Python migration is straightforward copy-paste

**High Risk**: Elixir API migration affects 10 modules but clear pattern exists

**Mitigation**: Staged rollout with comprehensive testing at each phase

## Next Steps

1. Read [01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md) for detailed Snakepit analysis
2. Review [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) for step-by-step plan
3. Follow [05_MIGRATION_GUIDE.md](./05_MIGRATION_GUIDE.md) for implementation
4. Use [12_TESTING_STRATEGY.md](./12_TESTING_STRATEGY.md) for validation

---

**Generated**: 2025-10-07
**Status**: Ready for Implementation
**Reviewed By**: Architecture Team

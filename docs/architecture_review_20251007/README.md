# Architecture Review & Decoupling Plan - October 7, 2025

This directory contains a comprehensive architectural analysis and decoupling plan for separating DSPy-specific code from Snakepit infrastructure into DSPex.

## 📖 Quick Start

**New here?** Start with:
1. [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md) - High-level overview (5 min read)
2. [00_OVERVIEW.md](./00_OVERVIEW.md) - Detailed overview with diagrams (10 min read)

**Ready to implement?** Go to:
- [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) - Step-by-step implementation guide

## 📚 Documentation Structure

### Executive Documents
- **[EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)** - For decision makers and stakeholders
  - TL;DR summary
  - Risk assessment
  - Timeline and effort estimates
  - Success criteria

- **[00_OVERVIEW.md](./00_OVERVIEW.md)** - For everyone
  - Problem statement
  - Document index
  - Quick facts
  - Migration strategy overview

### Analysis Documents
- **[01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md)** - For architects
  - File-by-file analysis of Snakepit
  - Coupling metrics (only 2.1% DSPy-coupled!)
  - What makes Snakepit clean
  - Usage analysis

### Implementation Documents
- **[04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md)** - For developers
  - Complete step-by-step plan
  - Code examples and diffs
  - Testing procedures
  - 4 phases with detailed instructions

- **[07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md)** - For Snakepit maintainers
  - Exact changes needed in Snakepit
  - File-by-file diffs
  - Publishing checklist
  - Backward compatibility details

### Decision Records
- **[09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md)** - For long-term reference
  - Why we're making this change
  - Alternatives considered
  - Consequences (positive and negative)
  - Formal ADR following Michael Nygard's template

## 🎯 The Problem

**Current**: Snakepit (generic Python bridge) contains 469 lines of DSPy-specific code

**Issue**: Domain logic in infrastructure layer (architectural anti-pattern)

**Impact**:
- Snakepit can't be used generically
- Unclear ownership boundaries
- Examples broken (legacy API usage)

## ✨ The Solution

**Move** DSPy classes from Snakepit → DSPex

**Method**:
1. Deprecate in Snakepit v0.4.3 (warnings only)
2. Create in DSPex v0.2.1 (new Python module)
3. Migrate 10 Elixir modules to modern API
4. Remove from Snakepit v0.5.0 (Q1 2026)

**Result**: Clean separation, both projects benefit

## 📊 Key Findings

### Snakepit
- ✅ **97.9% DSPy-free** - core infrastructure is clean
- ✅ **Only 2 Python files** affected
- ✅ **Only 1 file** imports `dspy`
- ✅ **Zero Elixir files** mention DSPy
- ✅ **Extraction is safe** - no deep coupling

### DSPex
- ⚠️ **10 modules** need API migration
- ⚠️ **1 redundant bridge** module to remove
- ✅ **Tests passing** (82/82)
- ❌ **Examples broken** (using legacy API)

## ⏱️ Timeline

| Phase | Duration | Risk | Complexity |
|-------|----------|------|------------|
| 1. Snakepit Deprecation | 2-4 hours | Very Low | Low |
| 2. DSPex Python | 4-6 hours | Low | Low |
| 3. Elixir Migration | 8-12 hours | Medium | Medium |
| 4. Testing & Docs | 4-6 hours | Low | Low |
| **Total** | **18-28 hours** | **Low** | **Medium** |

**Calendar Time**: 2-3 days with focused work

## 🎬 Reading Guide by Role

### Decision Maker / Stakeholder
1. [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)
2. [09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md) - Section: "Decision" and "Benefits"

**Time**: 15 minutes

### Software Architect
1. [00_OVERVIEW.md](./00_OVERVIEW.md)
2. [01_SNAKEPIT_ANALYSIS.md](./01_SNAKEPIT_ANALYSIS.md)
3. [09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md)

**Time**: 45 minutes

### Developer (Implementation)
1. [00_OVERVIEW.md](./00_OVERVIEW.md) - Quick facts
2. [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) - Full implementation guide
3. [07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md) - If working on Snakepit

**Time**: 1-2 hours (then 2-3 days implementation)

### Snakepit Maintainer
1. [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)
2. [07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md)
3. [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) - Phase 1 only

**Time**: 30 minutes (then 2-4 hours implementation)

### DSPex Maintainer
1. [00_OVERVIEW.md](./00_OVERVIEW.md)
2. [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md) - Phases 2-4
3. [09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md) - For context

**Time**: 1 hour (then 16-24 hours implementation)

## 🚀 Implementation Phases

### Phase 1: Snakepit Deprecation
**Goal**: Add warnings without breaking anything
**Files**: 5 (Python, README, CHANGELOG, mix.exs)
**Time**: 2-4 hours
**Risk**: Very Low

### Phase 2: DSPex Python
**Goal**: Create DSPex-owned DSPy module
**Files**: 1 new Python file + imports
**Time**: 4-6 hours
**Risk**: Low

### Phase 3: Elixir Migration
**Goal**: Update 10 modules to modern API
**Files**: 10 Elixir modules
**Time**: 8-12 hours
**Risk**: Medium

### Phase 4: Testing & Docs
**Goal**: Validate and document
**Files**: README, CHANGELOG, migration guide
**Time**: 4-6 hours
**Risk**: Low

## ✅ Success Criteria

**Immediate** (v0.4.3 / v0.2.1):
- [ ] Snakepit v0.4.3 tagged with deprecation
- [ ] DSPex v0.2.1 with native integration
- [ ] All tests passing (82/82)
- [ ] All examples working (6/6)
- [ ] Migration guide published

**Long-term** (v0.5.0):
- [ ] DSPy code removed from Snakepit
- [ ] Clean architecture maintained
- [ ] No user complaints
- [ ] Both projects can evolve independently

## 🔒 Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking users | Deprecation warnings, 3-6 month transition |
| Import errors | Test Python module first, clear error messages |
| Lost functionality | Byte-for-byte copy, no modifications |
| Tests fail | Test after each module migration |

## 📞 Questions?

**Architecture questions**: See [09_ARCHITECTURE_DECISION_RECORD.md](./09_ARCHITECTURE_DECISION_RECORD.md)

**Implementation questions**: See [04_DECOUPLING_PLAN.md](./04_DECOUPLING_PLAN.md)

**Snakepit-specific questions**: See [07_SNAKEPIT_CHANGES.md](./07_SNAKEPIT_CHANGES.md)

**Quick overview**: See [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)

## 📅 Document History

| Version | Date | Status | Notes |
|---------|------|--------|-------|
| 1.0 | 2025-10-07 | Ready | Initial comprehensive review |

## 🏗️ Related Projects

- **Snakepit**: https://github.com/nshkrdotcom/snakepit (v0.4.2)
- **DSPex**: https://github.com/nshkrdotcom/dspex (v0.2.0)

## 📜 License

This architectural documentation is part of the DSPex project and follows the same MIT license.

---

**Status**: ✅ Ready for Implementation
**Created**: 2025-10-07
**Last Updated**: 2025-10-07
**Maintainer**: Architecture Team

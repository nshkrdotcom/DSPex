# Architectural Realignment: Snakepit-DSPex Delineation (Option B)

**Date**: July 24, 2025  
**Author**: Claude Code  
**Status**: Proposed Architecture  
**Version**: 1.0

## Executive Summary

This document proposes a comprehensive architectural realignment between Snakepit and DSPex to address current boundary issues, dependency complexities, and overlapping responsibilities. The proposed changes will create cleaner separation of concerns, eliminate circular dependencies, and improve maintainability while preserving all existing functionality.

## Current State Analysis

### Existing Architecture Problems

1. **Circular Dependency Risk**
   - DSPex depends on Snakepit (`{:snakepit, "~> 0.4.1"}`)
   - DSPex's Python adapter imports `snakepit_bridge`
   - Creates potential circular import chains

2. **Split Variables Ownership**
   - Variables infrastructure in Snakepit (SessionStore, types)
   - Variables user API in DSPex (DSPex.Variables)
   - Inconsistent access patterns across domains

3. **Fragmented DSPy Integration**
   - Snakepit: `dspy_integration.py` (variable-aware mixins)
   - DSPex: `dspy_grpc.py` (schema bridge tools)
   - Maintenance overhead across repositories

4. **Python Package Complexity**
   - Two separate packages: `snakepit_bridge` and `dspex_adapters`
   - Complex distribution and versioning
   - Unclear dependency relationships

## Proposed Architecture (Option B)

### New Delineation Principle

**SNAKEPIT**: Universal Infrastructure for Cross-Language Integration  
**DSPex**: Domain-Specific DSPy Framework and Orchestration

### Detailed Responsibility Matrix

| Component | Current Owner | Proposed Owner | Rationale |
|-----------|---------------|----------------|-----------|
| gRPC Bridge & Sessions | Snakepit | Snakepit | Core infrastructure |
| Worker Management | Snakepit | Snakepit | Process management |
| Tool Framework | Snakepit | Snakepit | Generic capability |
| Variables Infrastructure | Snakepit | Snakepit | Universal state management |
| Variables User API | DSPex | **Snakepit** | Should be infrastructure |
| Context Management | DSPex | **Snakepit** | Session management |
| DSPy Integration | Split | **DSPex** | Domain-specific |
| Schema Bridge | DSPex | DSPex | DSPy-specific tooling |
| LLM Adapters | DSPex | DSPex | Domain orchestration |

## Implementation Plan

### Phase 1: Variables Migration (Week 1)

#### 1.1 Move Variables API to Snakepit

**Files to Move:**
```
DSPex → Snakepit
├── lib/dspex/variables.ex → lib/snakepit/variables.ex
├── lib/dspex/context.ex → lib/snakepit/context.ex
└── Related test files
```

**API Changes:**
```elixir
# Before (DSPex)
{:ok, ctx} = DSPex.Context.start_link()
DSPex.Variables.defvariable(ctx, :temp, :float, 0.7)
temp = DSPex.Variables.get(ctx, :temp)

# After (Snakepit)  
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :temp, :float, 0.7)
temp = Snakepit.Variables.get(ctx, :temp)
```

**Backward Compatibility:**
```elixir
# DSPex provides aliases for smooth migration
defmodule DSPex.Variables do
  @deprecated "Use Snakepit.Variables instead"
  defdelegate defvariable(ctx, name, type, value, opts \\ []), to: Snakepit.Variables
  defdelegate get(ctx, identifier, default \\ nil), to: Snakepit.Variables
  defdelegate set(ctx, identifier, value, opts \\ []), to: Snakepit.Variables
  # ... all other functions
end

defmodule DSPex.Context do
  @deprecated "Use Snakepit.Context instead" 
  defdelegate start_link(opts \\ []), to: Snakepit.Context
  defdelegate get_session_id(ctx), to: Snakepit.Context
  # ... all other functions
end
```

#### 1.2 Update Snakepit Module Structure

**New Snakepit Structure:**
```
lib/snakepit/
├── bridge/
│   ├── session_store.ex      # Existing
│   ├── tool_registry.ex      # Existing  
│   └── variables.ex          # Existing types & infrastructure
├── context.ex               # Moved from DSPex
├── variables.ex             # Moved from DSPex (user API)
├── grpc/                    # Existing gRPC infrastructure
├── pool/                    # Existing worker management
└── application.ex           # Updated supervision tree
```

#### 1.3 Update DSPex Dependencies

**Updated DSPex Code:**
```elixir
# Replace all DSPex.Variables calls
DSPex.Variables.set(ctx, :temp, 0.8)
# Becomes:
Snakepit.Variables.set(ctx, :temp, 0.8)

# Replace all DSPex.Context calls  
{:ok, ctx} = DSPex.Context.start_link()
# Becomes:
{:ok, ctx} = Snakepit.Context.start_link()
```

### Phase 2: DSPy Integration Consolidation (Week 2)

#### 2.1 Move DSPy Integration to DSPex

**Files to Move:**
```
Snakepit → DSPex
├── snakepit_bridge/dspy_integration.py → dspex/priv/python/dspex_dspy/integration.py
├── snakepit_bridge/variable_aware_mixin.py → dspex/priv/python/dspex_dspy/mixins.py
└── Related DSPy-specific code
```

#### 2.2 Consolidate Python DSPy Code

**New DSPex Python Structure:**
```
dspex/priv/python/
├── dspex_dspy/
│   ├── __init__.py
│   ├── schema_bridge.py     # call_dspy, discover_schema (existing)
│   ├── integration.py       # Moved from snakepit (variable-aware modules)
│   ├── mixins.py           # Moved from snakepit (VariableAwareMixin)
│   ├── adapters.py         # DSPy-specific gRPC adapter
│   └── utils.py            # DSPy utilities
├── requirements.txt
└── setup.py               # For pip installation
```

#### 2.3 Enhanced DSPy Integration

**Unified DSPy Module:**
```python
# dspex_dspy/integration.py
from .mixins import VariableAwareMixin
from .schema_bridge import call_dspy, discover_schema
from snakepit_bridge import SessionContext, BaseAdapter, tool

class DSPyIntegration:
    """Unified DSPy integration with both schema bridge and variable awareness"""
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        self.schema_cache = {}
    
    def create_variable_aware_module(self, class_path: str, **kwargs):
        """Create DSPy module with automatic variable binding"""
        # Combines schema bridge creation with variable awareness
        instance = call_dspy(class_path, "__init__", [], kwargs)
        return VariableAwareWrapper(instance, self.session_context)
    
    def discover_and_cache_schema(self, module_path: str = "dspy"):
        """Discover DSPy schema with intelligent caching"""
        if module_path not in self.schema_cache:
            self.schema_cache[module_path] = discover_schema(module_path)
        return self.schema_cache[module_path]
```

### Phase 3: Python Package Reorganization (Week 3)

#### 3.1 Clean Snakepit Python Package

**Snakepit Python (Infrastructure Only):**
```
snakepit/priv/python/snakepit_bridge/
├── __init__.py
├── session_context.py      # Core session management
├── base_adapter.py         # Generic adapter framework  
├── variables.py            # Variable operations (moved from types)
├── serialization.py        # Cross-language serialization
├── types.py               # Type system
└── adapters/
    ├── showcase/           # Generic example adapters
    └── enhanced.py         # Generic enhanced operations
```

**Remove from Snakepit:**
- All DSPy-specific code
- Variable-aware mixins  
- DSPy integration modules

#### 3.2 Complete DSPex Python Package

**DSPex Python (DSPy Domain):**
```
dspex/priv/python/dspex_dspy/
├── __init__.py
├── schema_bridge.py        # Universal DSPy caller
├── integration.py          # Variable-aware DSPy modules
├── mixins.py              # VariableAwareMixin and related
├── adapters.py            # DSPy-specific gRPC adapter
├── optimization.py        # DSPy optimizer integration
├── utils.py               # DSPy utilities
└── templates/             # Code generation templates
```

#### 3.3 Clear Dependency Chain

**Python Dependencies:**
```python
# snakepit_bridge (no external domain dependencies)
dependencies = [
    "grpcio>=1.50.0",
    "protobuf>=4.0.0", 
    "typing-extensions>=4.0.0"
]

# dspex_dspy (depends on snakepit_bridge + DSPy)
dependencies = [
    "snakepit-bridge>=0.4.1",  # Infrastructure dependency
    "dspy-ai>=2.0.0",          # Domain dependency
    "instructor>=0.4.0",       # LLM integration
]
```

### Phase 4: API Updates and Documentation (Week 4)

#### 4.1 Update All Examples

**DSPex Examples Update:**
```elixir
# examples/dspy/01_question_answering_pipeline.exs

# OLD:
{:ok, ctx} = DSPex.Context.start_link()
DSPex.Variables.defvariable(ctx, :temperature, :float, 0.7)

# NEW:  
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :temperature, :float, 0.7)

# DSPy-specific functionality remains in DSPex
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
```

#### 4.2 Migration Guide

**Migration Documentation:**
```markdown
# Migration Guide: DSPex 0.2.x → 0.3.0

## Breaking Changes

### Variables API Moved to Snakepit
- `DSPex.Variables.*` → `Snakepit.Variables.*`
- `DSPex.Context.*` → `Snakepit.Context.*`

### Python Package Changes  
- `snakepit_bridge.dspy_integration` → `dspex_dspy.integration`
- `snakepit_bridge.variable_aware_mixin` → `dspex_dspy.mixins`

## Automated Migration

Run the provided migration script:
```bash
mix dspex.migrate.variables
```

This will update your codebase automatically.
```

#### 4.3 Version Compatibility

**Snakepit Version Bump:**
```elixir
# snakepit/mix.exs
version: "0.5.0"  # Major version bump for API additions

# New public APIs:
# - Snakepit.Variables.*
# - Snakepit.Context.*
```

**DSPex Version Bump:**
```elixir  
# dspex/mix.exs
version: "0.3.0"  # Major version bump for breaking changes

# Breaking changes:
# - Variables API moved to Snakepit dependency
# - Python package restructured
```

## Benefits Analysis

### 1. Cleaner Architecture

**Before:**
```
DSPex → Snakepit (infrastructure)
dspex_adapters → snakepit_bridge (Python)
DSPex.Variables → Snakepit.SessionStore (implementation)
```

**After:**
```
DSPex → Snakepit (clean infrastructure dependency)
dspex_dspy → snakepit_bridge (clean Python dependency)  
Snakepit.Variables → Snakepit.SessionStore (consistent)
```

### 2. Better Reusability

**Snakepit becomes truly universal:**
- Variables work for any domain, not just DSPy
- Other projects can use Snakepit without DSPy dependencies
- Clean separation enables independent development

**DSPex becomes focused:**
- Single source of truth for all DSPy functionality
- No coordination needed across repositories
- Faster iteration on DSPy-specific features

### 3. Improved Maintenance

**Reduced Complexity:**
- Variables have single ownership (Snakepit)
- DSPy integration has single ownership (DSPex)
- Clear boundaries reduce mental overhead

**Better Testing:**
- Infrastructure tests in Snakepit
- Domain tests in DSPex  
- No cross-repository test coordination

### 4. Enhanced User Experience

**Consistent APIs:**
```elixir
# All infrastructure through Snakepit
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.set(ctx, :temp, 0.8)

# All DSPy functionality through DSPex
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, schema} = DSPex.Bridge.discover_schema("dspy")
```

**Logical Grouping:**
- Infrastructure operations feel like infrastructure
- Domain operations feel like domain functionality
- Clear mental model for developers

## Risk Mitigation

### 1. Breaking Changes

**Mitigation Strategy:**
- Provide deprecated aliases for 1 full version
- Automated migration script
- Comprehensive migration documentation
- Clear timeline and communication

**Example Deprecation:**
```elixir
defmodule DSPex.Variables do
  @moduledoc """
  DEPRECATED: Use Snakepit.Variables instead.
  
  This module will be removed in DSPex v0.4.0.
  Run `mix dspex.migrate.variables` to update your code.
  """
  
  @deprecated "Use Snakepit.Variables.defvariable/5 instead"
  defdelegate defvariable(ctx, name, type, value, opts \\ []), to: Snakepit.Variables
end
```

### 2. Python Package Distribution

**Mitigation Strategy:**
- Publish both packages to PyPI simultaneously
- Update pip installation instructions
- Provide Docker images with both packages pre-installed

**Installation Guide:**
```bash
# For Snakepit users (infrastructure only)
pip install snakepit-bridge

# For DSPex users (includes snakepit-bridge)
pip install dspex-dspy

# For development (both packages in development mode)
pip install -e ./snakepit/priv/python
pip install -e ./dspex/priv/python
```

### 3. Documentation Updates

**Comprehensive Update Plan:**
- README files in both repositories
- API documentation regeneration
- Tutorial updates
- Example code updates
- Migration guides

## Implementation Timeline

### Week 1: Variables Migration
- [ ] Move `DSPex.Variables` → `Snakepit.Variables`
- [ ] Move `DSPex.Context` → `Snakepit.Context`
- [ ] Add deprecation aliases in DSPex
- [ ] Update Snakepit supervision tree
- [ ] Test migration completeness

### Week 2: DSPy Consolidation  
- [ ] Move DSPy Python code to DSPex
- [ ] Consolidate variable-aware mixins
- [ ] Update Python imports and dependencies
- [ ] Test DSPy integration functionality
- [ ] Update gRPC adapter registration

### Week 3: Package Reorganization
- [ ] Clean Snakepit Python package
- [ ] Finalize DSPex Python package
- [ ] Update setup.py and requirements
- [ ] Test Python package installation
- [ ] Update CI/CD pipelines

### Week 4: Documentation & Release
- [ ] Update all examples
- [ ] Write migration documentation
- [ ] Create automated migration script
- [ ] Update API documentation
- [ ] Prepare release notes

## Success Criteria

### Functional Requirements
- [ ] All existing functionality preserved
- [ ] No performance regressions
- [ ] All tests passing
- [ ] Examples working with new APIs

### Architectural Requirements  
- [ ] No circular dependencies
- [ ] Clear separation of concerns
- [ ] Consistent API patterns
- [ ] Logical ownership boundaries

### User Experience Requirements
- [ ] Smooth migration path provided
- [ ] Clear documentation available  
- [ ] Intuitive API organization
- [ ] Minimal learning curve for changes

## Conclusion

This architectural realignment addresses fundamental structural issues in the current Snakepit-DSPex split while preserving all functionality and providing a clear migration path. The proposed changes will result in:

1. **Cleaner Architecture**: Clear boundaries and dependencies
2. **Better Maintainability**: Single ownership of related functionality
3. **Improved Usability**: Logical grouping of APIs
4. **Enhanced Reusability**: Infrastructure truly independent of domain

The implementation plan spreads changes across 4 weeks to minimize risk and ensure thorough testing. The end result will be a more robust, maintainable, and intuitive system that better serves both infrastructure and domain-specific needs.

**Recommendation**: Proceed with Option B implementation as outlined above.
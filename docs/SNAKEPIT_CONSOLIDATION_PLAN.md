# Snakepit Consolidation Plan: Moving DSPy Bridge to Snakepit

**Date**: July 25, 2025  
**Author**: Claude Code  
**Status**: Migration Plan  
**Version**: 1.0

## Executive Summary

This document outlines the plan to move all DSPy bridge functionality from DSPex into Snakepit, making Snakepit the comprehensive cross-language bridge (including DSPy support) and keeping DSPex as a thin orchestration layer. This aligns with the Single Responsibility Principle where Snakepit becomes the universal bridge and DSPex focuses purely on high-level orchestration.

## Current State Analysis

### DSPex Current Structure (Heavy Bridge + Orchestration)
```
dspex/
├── lib/dspex/
│   ├── variables.ex              # DEPRECATED → Already delegates to Snakepit
│   ├── context.ex               # DEPRECATED → Already delegates to Snakepit  
│   ├── bridge.ex                # MOVE → Core DSPy bridge metaprogramming
│   ├── modules/                 # MOVE → DSPy module implementations
│   │   ├── predict.ex
│   │   ├── chain_of_thought.ex
│   │   ├── react.ex
│   │   ├── program_of_thought.ex
│   │   ├── multi_chain_comparison.ex
│   │   └── retry.ex
│   ├── native/                  # MOVE → Native Elixir DSPy functionality
│   │   ├── signature.ex
│   │   ├── template.ex
│   │   ├── validator.ex
│   │   ├── metrics.ex
│   │   └── registry.ex
│   ├── python/                  # MOVE → Python bridge utilities
│   │   └── bridge.ex
│   ├── bridge/                  # MOVE → Bridge tooling
│   │   └── tools.ex
│   ├── config.ex                # KEEP → LLM configuration management
│   ├── pipeline.ex              # KEEP → High-level pipeline orchestration
│   ├── settings.ex              # KEEP → Settings management
│   ├── lm.ex                    # KEEP → Language model abstractions
│   ├── models.ex                # KEEP → Model management
│   ├── examples.ex              # KEEP → Example management
│   ├── assertions.ex            # KEEP → High-level assertions
│   └── llm/                     # KEEP → LLM adapter infrastructure
│       ├── client.ex
│       ├── adapter.ex
│       └── adapters/
├── priv/python/
│   ├── dspex_dspy/             # MOVE → Full Python DSPy integration
│   │   ├── integration.py       # Variable-aware DSPy modules
│   │   ├── schema_bridge.py     # Universal DSPy caller
│   │   ├── mixins.py           # VariableAwareMixin
│   │   ├── adapters.py         # DSPy gRPC handlers
│   │   └── utils.py            # DSPy utilities
│   ├── dspex_adapters/         # MOVE → DSPy adapters
│   └── setup.py               # MOVE → Python package setup
```

### Snakepit Current Structure (Pure Infrastructure)
```
snakepit/
├── lib/snakepit/
│   ├── bridge/                 # Session + protocol infrastructure
│   ├── pool/                   # Process pooling
│   └── adapters/              # Generic language adapters
├── priv/python/
│   └── snakepit_bridge/       # Basic Python infrastructure
```

## Proposed Architecture: Snakepit as Universal Bridge

### New Snakepit Structure (Comprehensive Bridge)
```
snakepit/
├── lib/snakepit/
│   ├── core/                   # Pure infrastructure (existing)
│   │   ├── pool/              # Process pooling
│   │   ├── session/           # Session management
│   │   └── grpc/             # Basic gRPC infrastructure
│   ├── bridge/                # Cross-language bridge (existing + expanded)
│   │   ├── session_store.ex   # Existing
│   │   ├── variables.ex       # Already moved from DSPex
│   │   ├── context.ex         # Already moved from DSPex
│   │   └── tools.ex          # Move from DSPex.Bridge.Tools
│   ├── dspy/                  # Complete DSPy integration (NEW)
│   │   ├── bridge.ex          # Move from DSPex.Bridge
│   │   ├── modules/           # Move from DSPex.Modules.*
│   │   ├── native/            # Move from DSPex.Native.*
│   │   ├── python_bridge.ex   # Move from DSPex.Python.Bridge
│   │   └── schema.ex          # DSPy schema management
│   └── adapters/              # Enhanced adapters (existing + expanded)
│       ├── generic_python.ex  # Existing
│       ├── enhanced_python.ex # Existing
│       └── dspy.ex            # New DSPy-specific adapter
├── priv/python/
│   ├── snakepit_bridge/       # Existing infrastructure
│   └── snakepit_dspy/         # Move from DSPex (NEW)
│       ├── integration.py     # Variable-aware DSPy modules
│       ├── schema_bridge.py   # Universal DSPy caller
│       ├── mixins.py         # VariableAwareMixin
│       ├── adapters.py       # DSPy gRPC handlers
│       └── utils.py          # DSPy utilities
```

### New DSPex Structure (Thin Orchestration)
```
dspex/
├── lib/dspex/
│   ├── config.ex              # LLM configuration management
│   ├── pipeline.ex            # High-level pipeline orchestration  
│   ├── settings.ex            # Settings management
│   ├── lm.ex                  # Language model abstractions
│   ├── models.ex              # Model management
│   ├── examples.ex            # Example management
│   ├── assertions.ex          # High-level assertions
│   └── llm/                   # LLM adapter infrastructure
│       ├── client.ex
│       ├── adapter.ex
│       └── adapters/
├── examples/                  # High-level usage examples
└── docs/                     # User documentation
```

## Migration Plan

### Phase 1: Move Elixir DSPy Code (Week 1)

#### 1.1 Create DSPy Module Structure in Snakepit
```bash
# In snakepit repository
mkdir -p lib/snakepit/dspy
mkdir -p lib/snakepit/dspy/modules
mkdir -p lib/snakepit/dspy/native
```

#### 1.2 Move Core DSPy Bridge Files
**Files to Move:**
```
DSPex → Snakepit
├── lib/dspex/bridge.ex → lib/snakepit/dspy/bridge.ex
├── lib/dspex/bridge/tools.ex → lib/snakepit/bridge/tools.ex
├── lib/dspex/python/bridge.ex → lib/snakepit/dspy/python_bridge.ex
├── lib/dspex/modules/*.ex → lib/snakepit/dspy/modules/*.ex
└── lib/dspex/native/*.ex → lib/snakepit/dspy/native/*.ex
```

**Namespace Changes:**
```elixir
# Before (DSPex)
defmodule DSPex.Bridge do
defmodule DSPex.Modules.Predict do
defmodule DSPex.Native.Signature do
defmodule DSPex.Python.Bridge do

# After (Snakepit)
defmodule Snakepit.DSPy.Bridge do
defmodule Snakepit.DSPy.Modules.Predict do
defmodule Snakepit.DSPy.Native.Signature do
defmodule Snakepit.DSPy.PythonBridge do
```

#### 1.3 Update Internal References
**Update all module references within moved files:**
```elixir
# Replace all DSPex.* references with Snakepit.*
# Update alias statements
# Update @moduledoc references
```

### Phase 2: Move Python DSPy Code (Week 2)

#### 2.1 Create Python Structure in Snakepit
```bash
# In snakepit/priv/python/
mkdir -p snakepit_dspy
```

#### 2.2 Move Python DSPy Package
**Files to Move:**
```
DSPex → Snakepit
├── priv/python/dspex_dspy/ → priv/python/snakepit_dspy/
├── priv/python/dspex_adapters/ → priv/python/snakepit_dspy/adapters/
└── priv/python/setup.py → priv/python/setup_dspy.py
```

**Python Package Changes:**
```python
# Before (dspex_dspy)
from dspex_dspy import integration, schema_bridge, mixins
from dspex_adapters import dspy_grpc

# After (snakepit_dspy)
from snakepit_dspy import integration, schema_bridge, mixins
from snakepit_dspy.adapters import dspy_grpc
```

#### 2.3 Update Python Package Configuration
```python
# snakepit/priv/python/setup_dspy.py
setup(
    name="snakepit-dspy",
    version="1.0.0",
    packages=find_packages(),
    install_requires=[
        "snakepit-bridge>=0.5.0",  # Infrastructure dependency
        "dspy-ai>=2.0.0",          # DSPy framework
    ]
)
```

### Phase 3: Update Dependencies and APIs (Week 3)

#### 3.1 Update Snakepit Dependencies
```elixir
# snakepit/mix.exs
def deps do
  [
    {:jason, "~> 1.0"},
    {:dspy, "~> 2.0.0", optional: true},  # Optional DSPy dependency
    # ... existing deps
  ]
end
```

#### 3.2 Update DSPex to Use Snakepit DSPy
**Replace DSPex modules with Snakepit delegates:**
```elixir
# dspex/lib/dspex.ex
defmodule DSPex do
  @moduledoc """
  High-level orchestration APIs for DSPy workflows.
  
  This module provides user-friendly APIs that delegate to the
  comprehensive DSPy bridge in Snakepit.
  """
  
  # Delegate core DSPy operations to Snakepit
  defdelegate create_predictor(signature, opts \\ []), 
    to: Snakepit.DSPy.Modules.Predict, as: :create
    
  defdelegate discover_schema(module_path \\ "dspy"), 
    to: Snakepit.DSPy.Bridge
    
  defdelegate call_dspy(class_path, method, args, kwargs), 
    to: Snakepit.DSPy.Bridge
    
  # High-level orchestration functions
  def create_pipeline(steps, opts \\ []) do
    DSPex.Pipeline.new(steps, opts)
  end
  
  def configure_llm(provider, opts \\ []) do
    DSPex.Config.set_llm(provider, opts)
  end
end
```

#### 3.3 Create Compatibility Layer
```elixir
# dspex/lib/dspex/bridge.ex - Compatibility wrapper
defmodule DSPex.Bridge do
  @moduledoc """
  DEPRECATED: Use Snakepit.DSPy.Bridge instead.
  
  This module provides backward compatibility and will be removed in v0.5.0.
  """
  
  @deprecated "Use Snakepit.DSPy.Bridge instead"
  defdelegate discover_schema(path), to: Snakepit.DSPy.Bridge
  
  @deprecated "Use Snakepit.DSPy.Bridge instead"  
  defdelegate call_dspy(class, method, args, kwargs), to: Snakepit.DSPy.Bridge
  
  @deprecated "Use Snakepit.DSPy.Bridge instead"
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    quote do
      require Snakepit.DSPy.Bridge
      Snakepit.DSPy.Bridge.defdsyp(unquote(module_name), 
                                   unquote(class_path), 
                                   unquote(config))
    end
  end
end
```

### Phase 4: Update Examples and Documentation (Week 4)

#### 4.1 Update All Examples
**DSPex Examples (High-level orchestration):**
```elixir
# examples/dspy/orchestrated_pipeline.exs
# Focus on high-level orchestration, not bridge details

# Create context through Snakepit (infrastructure)
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :temperature, :float, 0.7)

# Configure LLM through DSPex (orchestration)
DSPex.configure_llm(:openai, model: "gpt-4", api_key: System.get_env("OPENAI_API_KEY"))

# Create pipeline through DSPex (orchestration)
pipeline = DSPex.create_pipeline([
  {:reasoning, "question -> reasoning", type: :chain_of_thought},
  {:answer, "reasoning -> answer", type: :predict}
])

# Execute pipeline
result = DSPex.Pipeline.run(pipeline, %{question: "Explain quantum computing"})
```

**Snakepit Examples (Bridge functionality):**
```elixir
# examples/dspy/direct_bridge_usage.exs
# Focus on direct bridge usage for power users

# Create context
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :temperature, :float, 0.7)

# Direct DSPy bridge usage
{:ok, predictor} = Snakepit.DSPy.Modules.Predict.create(
  "question -> answer", 
  session_context: ctx
)

result = Snakepit.DSPy.Modules.Predict.call(predictor, %{question: "What is DSPy?"})
```

#### 4.2 Update Documentation Structure
```
snakepit/
├── docs/
│   ├── dspy_bridge.md         # DSPy bridge documentation
│   ├── variables.md           # Variable system
│   └── python_integration.md  # Python integration details

dspex/  
├── docs/
│   ├── getting_started.md     # High-level usage
│   ├── pipelines.md          # Pipeline orchestration
│   └── llm_adapters.md       # LLM configuration
```

## Dependency Chain After Migration

### Clean Architecture
```
┌─────────────────┐
│     DSPex       │  ← Thin orchestration layer
│   (v0.4.0)      │    • Pipeline management
│                 │    • LLM configuration  
│                 │    • High-level APIs
└─────────────────┘
          │
          ▼
┌─────────────────┐
│   SNAKEPIT      │  ← Universal bridge (comprehensive)
│   (v0.5.0)      │    • Process pooling + sessions
│                 │    • Variables + context
│                 │    • Complete DSPy bridge
│                 │    • Python integration
└─────────────────┘
```

### Benefits Analysis

#### 1. **Architectural Cohesion**
- **Snakepit**: Single responsibility = universal cross-language bridge
- **DSPex**: Single responsibility = high-level orchestration
- **Clean separation** between infrastructure and domain logic

#### 2. **Reduced Complexity**
- **DSPex becomes lightweight** - easier to understand and maintain
- **All bridge complexity** contained in Snakepit
- **Single source of truth** for DSPy integration

#### 3. **Enhanced Reusability**
- **Other projects** can use full DSPy bridge from Snakepit
- **Snakepit becomes standalone** DSPy integration solution
- **DSPex patterns** can be replicated for other domains

#### 4. **Better Maintenance**
- **DSPy updates** only affect Snakepit
- **Pipeline logic** isolated in DSPex
- **Clear ownership** of each component

## Risk Mitigation

### 1. **Breaking Changes Management**
```elixir
# Provide 2-version deprecation cycle
# DSPex 0.4.0: Add compatibility layer with deprecation warnings
# DSPex 0.5.0: Remove compatibility layer

# Example compatibility
defmodule DSPex.Modules.Predict do
  @deprecated "Use Snakepit.DSPy.Modules.Predict instead"
  defdelegate create(signature, opts), to: Snakepit.DSPy.Modules.Predict
end
```

### 2. **Version Coordination**
```elixir
# Ensure compatible versions
# dspex/mix.exs
def deps do
  [
    {:snakepit, "~> 0.5.0"},  # Requires DSPy bridge functionality
    # ...
  ]
end
```

### 3. **Migration Tooling**
```bash
# Provide automated migration script
mix dspex.migrate.to_snakepit_bridge

# Script updates:
# - Import statements
# - Module references
# - Example code
```

## Implementation Timeline

### Week 1: Elixir Code Migration
- [ ] Create DSPy module structure in Snakepit
- [ ] Move all DSPex.Bridge, DSPex.Modules, DSPex.Native to Snakepit
- [ ] Update namespaces and internal references
- [ ] Basic integration testing

### Week 2: Python Code Migration  
- [ ] Move Python DSPy packages to Snakepit
- [ ] Update Python package configuration
- [ ] Update Python imports and references
- [ ] Test Python package functionality

### Week 3: API Updates and Dependencies
- [ ] Update Snakepit and DSPex dependencies
- [ ] Create DSPex compatibility layer
- [ ] Update DSPex to delegate to Snakepit
- [ ] Integration testing across repositories

### Week 4: Documentation and Examples
- [ ] Update all examples for new architecture
- [ ] Update documentation structure
- [ ] Create migration guides
- [ ] Prepare release notes

## Success Criteria

### Functional Requirements
- [ ] All existing functionality preserved
- [ ] No performance regressions  
- [ ] All tests passing in both repositories
- [ ] Examples working with new architecture

### Architectural Requirements
- [ ] Clean separation: DSPex = orchestration, Snakepit = bridge
- [ ] Single responsibility principle maintained
- [ ] No circular dependencies
- [ ] Clear ownership boundaries

### User Experience Requirements
- [ ] Smooth migration path with compatibility layer
- [ ] Clear documentation for both repositories
- [ ] Intuitive API organization
- [ ] Easy upgrade process

## Conclusion

This consolidation plan transforms the architecture into a clean two-layer system:

### **Snakepit (Universal Bridge)**
- **Complete infrastructure**: Process pooling, sessions, gRPC
- **Complete bridge functionality**: Variables, context, tools
- **Complete DSPy integration**: All DSPy bridge code (Elixir + Python)
- **Standalone value**: Can be used independently for DSPy integration

### **DSPex (Pure Orchestration)**  
- **High-level APIs**: Pipeline management, configuration
- **LLM abstractions**: Model management, adapters
- **User experience**: Examples, documentation, ease of use
- **Clean delegation**: All bridge operations delegate to Snakepit

**Result**: A more maintainable, reusable, and architecturally sound system that follows SRP principles while preserving all functionality and providing clear upgrade paths.

**Recommendation**: Proceed with this consolidation to achieve the optimal balance of functionality, maintainability, and architectural clarity.
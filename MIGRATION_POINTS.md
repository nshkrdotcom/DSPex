# Migration Points Identification

## Overview

This document identifies all specific migration points in the codebase where changes will be required during the refactoring from DSPex to Snakepit.

## Critical Migration Points

### 1. Module Namespace Migrations

#### DSPex.Bridge → Snakepit.DSPy.Bridge
**Files affected:**
- `lib/dspex/bridge.ex` (451+ lines)
- All files importing DSPex.Bridge
- Macro usage sites (`use DSPex.Bridge`)

**Migration steps:**
1. Copy to `snakepit/lib/snakepit/dspy/bridge.ex`
2. Update module declaration
3. Update all internal references
4. Create compatibility module in DSPex

#### DSPex.Modules.* → Snakepit.DSPy.Modules.*
**Modules to migrate:**
- `DSPex.Modules.Predict` → `Snakepit.DSPy.Modules.Predict`
- `DSPex.Modules.ChainOfThought` → `Snakepit.DSPy.Modules.ChainOfThought`
- `DSPex.Modules.ReAct` → `Snakepit.DSPy.Modules.ReAct`
- `DSPex.Modules.ProgramOfThought` → `Snakepit.DSPy.Modules.ProgramOfThought`
- `DSPex.Modules.MultiChainComparison` → `Snakepit.DSPy.Modules.MultiChainComparison`
- `DSPex.Modules.Retry` → `Snakepit.DSPy.Modules.Retry`

#### DSPex.Native.* → Snakepit.DSPy.Native.*
**Modules to migrate:**
- `DSPex.Native.Signature` → `Snakepit.DSPy.Native.Signature`
- `DSPex.Native.Template` → `Snakepit.DSPy.Native.Template`
- `DSPex.Native.Validator` → `Snakepit.DSPy.Native.Validator`
- `DSPex.Native.Metrics` → `Snakepit.DSPy.Native.Metrics`
- `DSPex.Native.Registry` → `Snakepit.DSPy.Native.Registry`

### 2. Import Statement Updates

#### Files with Snakepit imports (50+ occurrences)
```elixir
# Current imports to update
alias DSPex.Bridge
alias DSPex.Modules.Predict
alias DSPex.Native.Signature

# New imports after migration
alias Snakepit.DSPy.Bridge
alias Snakepit.DSPy.Modules.Predict
alias Snakepit.DSPy.Native.Signature
```

**Affected files:**
- All example files in `/examples/`
- All test files referencing these modules
- Any application code using DSPex

### 3. Macro Usage Updates

#### defdsyp Macro Usage
**Current usage:**
```elixir
defmodule MyModule do
  use DSPex.Bridge
  
  defdsyp __MODULE__, "dspy.Predict", config
end
```

**After migration:**
```elixir
defmodule MyModule do
  use Snakepit.DSPy.Bridge
  
  defdsyp __MODULE__, "dspy.Predict", config
end
```

### 4. Configuration Changes

#### Application Configuration
**Current (config/config.exs):**
```elixir
config :dspex,
  python_path: "python3",
  dspy_enabled: true,
  bridge_timeout: 30_000
```

**After migration:**
```elixir
config :dspex,
  # High-level orchestration config only
  
config :snakepit,
  dspy: [
    python_path: "python3",
    enabled: true,
    bridge_timeout: 30_000
  ]
```

### 5. Python Package Migrations

#### Python Module Paths
**Current structure:**
```
dspex/priv/python/
├── dspex_dspy/
├── dspex_adapters/
└── dspex_helper.py
```

**Target structure:**
```
snakepit/priv/python/
├── snakepit_dspy/
├── snakepit_dspy/adapters/
└── snakepit_dspy/helpers.py
```

**Import updates needed:**
```python
# Current
from dspex_dspy import integration
from dspex_adapters import dspy_grpc

# After
from snakepit_dspy import integration
from snakepit_dspy.adapters import dspy_grpc
```

### 6. Test File Migrations

#### Test Module Updates
**Files to update:**
- `test/dspex/bridge_test.exs` (if exists)
- `test/dspex/modules/*_test.exs`
- `test/dspex/native/*_test.exs`

**Changes required:**
1. Update module names in tests
2. Update import statements
3. Update test helper references
4. Ensure test isolation maintained

### 7. Documentation Updates

#### README and Guide Updates
**Files to update:**
- `README.md` - Update examples
- `docs/BRIDGE_ARCHITECTURE.md` - Update references
- `docs/specs/*/` - Update technical specs
- Example files - Update all usage examples

### 8. Public API Preservation

#### Compatibility Layer Implementation
```elixir
# lib/dspex/bridge.ex (compatibility)
defmodule DSPex.Bridge do
  @moduledoc """
  DEPRECATED: Use Snakepit.DSPy.Bridge
  
  This module provides backwards compatibility.
  Will be removed in v0.5.0.
  """
  
  @deprecated "Use Snakepit.DSPy.Bridge"
  defdelegate discover_schema(path), to: Snakepit.DSPy.Bridge
  
  @deprecated "Use Snakepit.DSPy.Bridge"
  defdelegate call_dspy(class, method, args, kwargs), 
    to: Snakepit.DSPy.Bridge
end
```

### 9. Dependency Updates

#### mix.exs Updates
**DSPex mix.exs:**
```elixir
defp deps do
  [
    {:snakepit, "~> 0.5.0"},  # Requires DSPy support
    # Remove direct Python bridge deps
  ]
end
```

**Snakepit mix.exs:**
```elixir
defp deps do
  [
    # Add DSPy-specific dependencies
    {:dspy, "~> 2.0", optional: true},
  ]
end
```

### 10. CI/CD Pipeline Updates

#### GitHub Actions / CI Configuration
- Update test commands
- Update build paths
- Update coverage reports
- Update deployment scripts

## Migration Execution Order

### Phase 1: Setup (Day 1)
1. Create directory structure in Snakepit
2. Set up configuration framework
3. Create compatibility modules in DSPex

### Phase 2: Code Movement (Days 2-3)
1. Move Native modules first (fewer dependencies)
2. Move Bridge core module
3. Move DSPy modules
4. Move Python packages

### Phase 3: Reference Updates (Days 4-5)
1. Update all imports in moved modules
2. Update cross-references
3. Update configuration
4. Update tests

### Phase 4: Testing (Days 6-7)
1. Run Snakepit tests
2. Run DSPex tests with compatibility layer
3. Run integration tests
4. Fix any issues

### Phase 5: Documentation (Day 8)
1. Update all documentation
2. Create migration guide
3. Update examples
4. Release notes

## Risk Areas

### High Risk
1. **Macro system changes** - defdsyp macro is complex
2. **Python package imports** - Many files may import these
3. **Test coverage** - Must maintain same coverage

### Medium Risk
1. **Configuration changes** - Apps need updates
2. **Example code** - Must all be updated
3. **Documentation** - Extensive updates needed

### Low Risk
1. **Simple module moves** - Mechanical process
2. **Import updates** - Can be automated
3. **Compatibility layer** - Simple delegation

## Validation Checklist

After each migration point:
- [ ] All tests pass
- [ ] No compilation warnings
- [ ] Documentation updated
- [ ] Examples work
- [ ] Performance unchanged
- [ ] Public API preserved
- [ ] No breaking changes without compatibility
# Migration Strategy

## Overview

This document outlines a phased migration strategy to transition from the current DSPy-specific implementation to the generalized multi-framework architecture. The strategy prioritizes backward compatibility and gradual adoption.

## Migration Principles

1. **Zero Breaking Changes**: Existing code must continue to work unchanged
2. **Incremental Adoption**: Teams can migrate at their own pace
3. **Feature Parity**: New architecture provides all current functionality
4. **Performance Preservation**: No regression in speed or resource usage
5. **Clear Deprecation Path**: Ample warning before removing old APIs

## Phase 1: Python Infrastructure (Week 1-2)

### Objective
Refactor Python bridge to support pluggable frameworks while maintaining current functionality.

### Tasks

#### 1.1 Extract Base Bridge Class
```python
# priv/python/base_bridge.py
# New file containing generic bridge functionality
class BaseBridge(ABC):
    # Extract protocol handling, stats, health checks
    # Leave DSPy-specific logic in dspy_bridge.py
```

#### 1.2 Refactor DSPy Bridge
```python
# priv/python/dspy_bridge.py
# Before: Monolithic implementation
class DSPyBridge:
    def __init__(self):
        # All logic mixed together
        
# After: Inherits from BaseBridge
from base_bridge import BaseBridge

class DSPyBridge(BaseBridge):
    def _initialize_framework(self):
        # DSPy-specific init only
```

#### 1.3 Maintain Backward Compatibility
```python
# priv/python/dspy_bridge.py
# Keep the same entry point for existing deployments
if __name__ == "__main__":
    # Existing logic preserved
    bridge = DSPyBridge()
    bridge.run()
```

### Validation
- All existing tests pass without modification
- Performance benchmarks show no regression
- Python bridge can be deployed without Elixir changes

## Phase 2: Elixir Infrastructure (Week 2-3)

### Objective
Add framework-agnostic infrastructure without modifying existing adapters.

### Tasks

#### 2.1 Create Base Adapter Behaviour
```elixir
# lib/dspex/adapters/base_ml_adapter.ex
defmodule DSPex.Adapters.BaseMLAdapter do
  # New behaviour for ML adapters
  # Provides common functionality
end
```

#### 2.2 Add Bridge Registry
```elixir
# lib/dspex/ml_bridge_registry.ex
defmodule DSPex.MLBridgeRegistry do
  # New registry for managing bridges
  # Does not affect existing code
end
```

#### 2.3 Create Unified Interface
```elixir
# lib/dspex/ml_bridge.ex
defmodule DSPex.MLBridge do
  # New unified interface
  # Wraps existing adapters
end
```

### Validation
- Existing `DSPex.Adapters.PythonPort` and `PythonPoolV2` unchanged
- New modules can be added without breaking builds
- All existing tests continue to pass

## Phase 3: Bridge Integration (Week 3-4)

### Objective
Integrate new and old systems, enabling both to coexist.

### Tasks

#### 3.1 Wrap Existing Adapters
```elixir
# Make existing adapters discoverable by new system
config :dspex, :ml_bridges,
  bridges: [
    dspy: %{
      adapter: DSPex.Adapters.PythonPoolV2,  # Existing adapter
      python_script: "priv/python/dspy_bridge.py"
    }
  ]
```

#### 3.2 Add Adapter Detection
```elixir
defmodule DSPex.MLBridge do
  def get_adapter(:dspy) do
    # Returns existing adapter for backward compatibility
    {:ok, DSPex.Adapters.PythonPoolV2}
  end
end
```

#### 3.3 Dual Interface Support
```elixir
# Old interface (preserved)
DSPex.Adapters.PythonPoolV2.create_program(signature)

# New interface (optional)
{:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
adapter.create_program(signature)
```

### Validation
- Both old and new interfaces work correctly
- No changes required to existing application code
- Performance remains identical

## Phase 4: Documentation and Examples (Week 4)

### Objective
Provide clear migration guides and examples for both interfaces.

### Tasks

#### 4.1 Migration Guide
```markdown
# Migrating to the New ML Bridge Architecture

## Option 1: Continue Using Current Code
No changes needed! Your existing code will continue to work.

## Option 2: Gradual Migration
Start using the new unified interface alongside existing code.

## Option 3: Full Migration
Update all code to use the new architecture.
```

#### 4.2 Example Updates
Show both old and new patterns:
```elixir
# Old way (still supported)
alias DSPex.Adapters.PythonPoolV2
{:ok, program_id} = PythonPoolV2.create_program(signature)

# New way (recommended)
alias DSPex.MLBridge
{:ok, dspy} = MLBridge.get_adapter(:dspy)
{:ok, program_id} = dspy.create_program(signature)
```

#### 4.3 Add Framework Examples
- Create example for adding LangChain
- Create template for custom frameworks
- Show multi-framework usage

### Validation
- Documentation builds without errors
- Examples run successfully
- Migration path is clear

## Phase 5: Deprecation Planning (Month 2+)

### Objective
Plan for eventual removal of old interfaces (far future).

### Tasks

#### 5.1 Add Deprecation Warnings
```elixir
defmodule DSPex.Adapters.PythonPort do
  @deprecated "Use DSPex.MLBridge.get_adapter(:dspy) instead"
  def create_program(signature, options \\ []) do
    # Existing implementation
  end
end
```

#### 5.2 Telemetry for Usage Tracking
```elixir
:telemetry.execute(
  [:dspex, :deprecated_api],
  %{count: 1},
  %{api: :python_port_adapter}
)
```

#### 5.3 Migration Tooling
```elixir
# Mix task for automated migration
mix dspex.migrate_to_ml_bridge --dry-run
mix dspex.migrate_to_ml_bridge --apply
```

### Timeline
- Month 1-3: No deprecation warnings
- Month 4-6: Soft deprecation (logs only)
- Month 7-12: Deprecation warnings
- Year 2: Consider removal (based on usage)

## Migration Patterns

### Pattern 1: Adapter Wrapper

For teams that want to migrate gradually:

```elixir
defmodule MyApp.MLAdapter do
  @moduledoc """
  Wrapper that provides both old and new interfaces
  """
  
  # Old interface (delegated)
  defdelegate create_program(signature), to: DSPex.Adapters.PythonPoolV2
  defdelegate execute_program(id, inputs), to: DSPex.Adapters.PythonPoolV2
  
  # New interface (wrapped)
  def get_adapter(framework) do
    DSPex.MLBridge.get_adapter(framework)
  end
end
```

### Pattern 2: Feature Flag Migration

For applications that need controlled rollout:

```elixir
defmodule MyApp.ML do
  def create_program(signature) do
    if feature_enabled?(:new_ml_bridge) do
      {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
      adapter.create_program(signature)
    else
      DSPex.Adapters.PythonPoolV2.create_program(signature)
    end
  end
end
```

### Pattern 3: Module-by-Module Migration

For large codebases:

```elixir
# Phase 1: New modules use new interface
defmodule MyApp.NewFeature do
  alias DSPex.MLBridge
  
  def process(text) do
    {:ok, dspy} = MLBridge.get_adapter(:dspy)
    # Use new interface
  end
end

# Phase 2: Migrate existing modules one by one
defmodule MyApp.ExistingFeature do
  # Gradually update to new interface
end
```

## Testing Strategy

### 1. Parallel Testing
Run tests against both old and new interfaces:

```elixir
defmodule MigrationTest do
  test "both interfaces produce same results" do
    signature = create_test_signature()
    
    # Old interface
    {:ok, result1} = DSPex.Adapters.PythonPoolV2.create_program(signature)
    
    # New interface
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, result2} = adapter.create_program(signature)
    
    assert result1 == result2
  end
end
```

### 2. Performance Comparison
Ensure no performance regression:

```elixir
defmodule PerformanceTest do
  test "new interface performance" do
    # Benchmark old interface
    old_time = :timer.tc(fn ->
      Enum.each(1..100, fn _ ->
        DSPex.Adapters.PythonPoolV2.create_program(signature)
      end)
    end)
    
    # Benchmark new interface
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
    new_time = :timer.tc(fn ->
      Enum.each(1..100, fn _ ->
        adapter.create_program(signature)
      end)
    end)
    
    # Allow 5% variance
    assert new_time <= old_time * 1.05
  end
end
```

### 3. Integration Testing
Test mixed usage:

```elixir
test "old and new interfaces work together" do
  # Create with old interface
  {:ok, program_id} = DSPex.Adapters.PythonPoolV2.create_program(signature)
  
  # Execute with new interface
  {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
  {:ok, result} = adapter.execute_program(program_id, inputs)
  
  assert result
end
```

## Rollback Plan

Each phase includes rollback capability:

### Phase 1 Rollback
```bash
# Revert Python changes
git checkout previous_version -- priv/python/
mix deps.get
mix compile
```

### Phase 2-3 Rollback
```bash
# Remove new modules (they're additive)
rm lib/dspex/adapters/base_ml_adapter.ex
rm lib/dspex/ml_bridge*.ex
mix compile
```

### Phase 4-5 Rollback
- Remove deprecation warnings
- Restore original documentation
- No code changes needed

## Success Metrics

### Technical Metrics
- [ ] All existing tests pass (100%)
- [ ] Performance benchmarks within 5% of baseline
- [ ] Zero breaking changes in public API
- [ ] Memory usage remains constant

### Adoption Metrics
- [ ] Documentation satisfaction (survey)
- [ ] Successful migration of example apps
- [ ] Community feedback positive
- [ ] New framework added successfully

### Business Metrics
- [ ] No increase in support tickets
- [ ] Migration completed within timeline
- [ ] No production incidents
- [ ] Team productivity maintained

## Risk Mitigation

### Risk 1: Hidden Dependencies
**Mitigation**: Extensive testing of edge cases, gradual rollout

### Risk 2: Performance Regression
**Mitigation**: Continuous benchmarking, performance tests in CI

### Risk 3: User Confusion
**Mitigation**: Clear documentation, migration guides, examples

### Risk 4: Integration Issues
**Mitigation**: Feature flags, gradual adoption, rollback plan

## Timeline Summary

- **Week 1-2**: Python infrastructure (Phase 1)
- **Week 2-3**: Elixir infrastructure (Phase 2)
- **Week 3-4**: Integration (Phase 3)
- **Week 4**: Documentation (Phase 4)
- **Month 2+**: Deprecation planning (Phase 5)

Total migration time: 4 weeks for infrastructure, indefinite for user adoption

## Conclusion

This migration strategy enables DSPex to support multiple ML frameworks while maintaining complete backward compatibility. The phased approach minimizes risk and allows teams to adopt the new architecture at their own pace. The existing DSPy functionality remains unchanged, ensuring zero disruption to current users.
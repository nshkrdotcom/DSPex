# DSPex Variables Bridge Implementation: Reacclimation Prompt

## Context Refresher

You are implementing Phase 1 of the DSPex Variables Bridge - a revolutionary system that enables cross-module parameter optimization in language model programming. This represents a fundamental shift from DSPy's module-centric approach to a variable-centric paradigm.

## Required Reading to Get Up to Speed

### 1. Core Architecture Understanding

**Read these files in order:**

1. **`lib/dspex.ex`** - Main module entry point
   - Focus on: Module structure and public API design patterns
   - Key sections: Module documentation and main function signatures

2. **`lib/dspex/lm.ex`** - Language model configuration
   - Focus on: How LM configuration works, `configure/2` function
   - Key pattern: Settings management and Python bridge usage

3. **`lib/dspex/modules/predict.ex`** - Core DSPy module wrapper
   - Focus on: How DSPy modules are wrapped, `create/2` and `call/2` patterns
   - Key insight: Stored module pattern with IDs

4. **`snakepit/lib/snakepit/python.ex`** - Python bridge core
   - Focus on: `call/3` function signature, session management
   - Key sections: How Python code is executed and results returned

5. **`snakepit/priv/python/enhanced_command_handler.py`** - Python command handler
   - Focus on: `handle_command` method, object storage mechanism
   - Key sections: Lines 50-150 (core command handling)
   - Critical: Understand the `stored_objects` dictionary pattern

### 2. Variables System Design

**Essential documentation:**

1. **`docs/specs/dspex_variables_implementation_strategy.md`**
   - Read: Entire document, especially "Phase 1: DSPy Adapter Layer" section
   - Key concepts: Variable Registry, DSPy Variable Adapter, Integration Layer

2. **`docs/specs/dspex_cognitive_orchestration/02_variable_coordination_system.md`**
   - Focus on: Variable structure (lines 50-80), Core operations (lines 85-120)
   - Key insight: Variables as coordination points, not just parameters

3. **`docs/GENERALIZED_VARIABLES_DSPY_FEASIBILITY_20250719.md`**
   - Focus on: "Minimum Native Components" section (lines 82-227)
   - Critical: Understand why native evaluation is essential

### 3. Integration Patterns

**Study these examples:**

1. **`examples/dspy/01_basic_usage.exs`**
   - Focus on: How DSPy modules are currently used
   - Pattern to extend: Module creation and invocation

2. **`lib/dspex/settings.ex`**
   - Focus on: Configuration management pattern
   - Key insight: How settings propagate to Python

## Current State Summary

### What Exists:
- Basic DSPy module wrappers (Predict, ChainOfThought, etc.)
- Python bridge with object storage
- Settings and LM configuration
- Module ID generation and storage pattern

### What's Missing (You Will Build):
- Variable Registry (GenServer-based)
- Variable types and constraints
- Python-side variable injection
- Cross-module variable sharing
- Variable observation pattern

## Phase 1 Implementation Goals

### 1. Variable Registry (Elixir Side)
Build a GenServer that:
- Manages all variables in the system
- Tracks observers and dependencies
- Stores optimization history
- Provides atomic updates with notifications

### 2. Python Variable Adapter
Create Python code that:
- Injects variable values into DSPy modules
- Tracks variable usage during execution
- Reports impact back to Elixir
- Maintains DSPy compatibility

### 3. Integration Layer
Connect the two sides:
- Variable-aware module creation
- Execution with variable application
- Feedback extraction and propagation

## Key Technical Challenges

1. **State Synchronization**: Variables must stay synchronized between Elixir and Python across multiple calls
2. **Module Wrapping**: Must wrap DSPy modules without breaking their functionality
3. **Performance**: Variable updates should have minimal overhead (<10ms)
4. **Compatibility**: Existing DSPy code must continue working unchanged

## Implementation Approach

### Start Here:

1. **Create Variable Registry GenServer**
   - File: `lib/dspex/variables/registry.ex`
   - Use ETS for fast lookups
   - Implement observer pattern
   - Add telemetry events

2. **Create Variable Type System**
   - File: `lib/dspex/variables/types.ex`
   - Start with: Float, Integer, Choice, Module
   - Each type needs: validate/1, cast/1, constraints/0

3. **Extend Python Command Handler**
   - File: `snakepit/priv/python/dspex_variables.py` (new)
   - Import and extend EnhancedCommandHandler
   - Add variable injection mechanism
   - Create VariableAwareModule wrapper

4. **Build Integration Bridge**
   - File: `lib/dspex/variables/dspy_bridge.ex`
   - Functions: create_variable_aware_module/3, execute_with_variables/3
   - Handle variable value propagation
   - Extract and process feedback

### Code Patterns to Follow:

```elixir
# Module creation pattern (from existing code)
{:ok, module_id} = Snakepit.Python.call(:python, code, store_as: id)

# Settings pattern (for variable values)
DSPex.Settings.put(:variables, variable_values)

# Observer pattern (new)
Registry.observe(variable_id, self())
```

```python
# Object storage pattern (from existing)
self.stored_objects[store_as] = result

# Method call pattern (to extend)
obj = self._resolve_stored_ref(obj_ref)
method = getattr(obj, method_name)
result = method(*args, **kwargs)
```

## Success Criteria for Phase 1

1. **Variable Registration**: Can create and manage variables with constraints
2. **Value Injection**: Variables affect DSPy module behavior
3. **Change Observation**: Observers get notified of variable updates  
4. **Backward Compatibility**: All existing examples still work
5. **Performance**: <10ms overhead per variable operation

## Next Steps After Reading

1. Review the existing codebase with focus on the patterns mentioned
2. Create the directory structure for new modules
3. Start with Variable Registry implementation
4. Test each component in isolation before integration
5. Create examples demonstrating variable usage

Remember: The goal is not to modify DSPy but to wrap and extend it with variable awareness while maintaining full compatibility.
# Migration Guide: DSPex 0.2.x → 0.3.0

This guide helps you migrate from DSPex 0.2.x to DSPex 0.3.0, which introduces a major architectural realignment between Snakepit and DSPex.

## Overview of Changes

DSPex 0.3.0 introduces a cleaner architectural separation:

- **Snakepit 0.5.0**: Universal infrastructure (Context, Variables, Sessions)
- **DSPex 0.3.0**: Domain-specific DSPy framework and orchestration

## Breaking Changes

### 1. Variables API Moved to Snakepit

**Before (DSPex 0.2.x):**
```elixir
{:ok, ctx} = DSPex.Context.start_link()
DSPex.Variables.defvariable(ctx, :temperature, :float, 0.7)
temp = DSPex.Variables.get(ctx, :temperature)
DSPex.Variables.set(ctx, :temperature, 0.8)
```

**After (DSPex 0.3.0):**
```elixir
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :temperature, :float, 0.7)
temp = Snakepit.Variables.get(ctx, :temperature)
Snakepit.Variables.set(ctx, :temperature, 0.8)
```

### 2. Context API Moved to Snakepit

**Before (DSPex 0.2.x):**
```elixir
{:ok, ctx} = DSPex.Context.start_link()
session_id = DSPex.Context.get_session_id(ctx)
info = DSPex.Context.get_info(ctx)
```

**After (DSPex 0.3.0):**
```elixir
{:ok, ctx} = Snakepit.Context.start_link()
session_id = Snakepit.Context.get_session_id(ctx)
info = Snakepit.Context.get_info(ctx)
```

### 3. Python Package Changes

**Before (DSPex 0.2.x):**
```python
from snakepit_bridge.dspy_integration import VariableAwarePredict
from snakepit_bridge.variable_aware_mixin import VariableAwareMixin
from dspex_adapters.dspy_grpc import DSPyGRPCHandler
```

**After (DSPex 0.3.0):**
```python
from dspex_dspy import VariableAwarePredict, VariableAwareMixin, DSPyGRPCHandler
```

### 4. Adapter Configuration

**Before (DSPex 0.2.x):**
```elixir
Application.put_env(:snakepit, :pool_config, %{
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})
```

**After (DSPex 0.3.0):**
```elixir
Application.put_env(:snakepit, :pool_config, %{
  adapter_args: ["--adapter", "dspex_dspy.adapters.DSPyGRPCHandler"]
})
```

## Migration Steps

### Step 1: Update Dependencies

**Update mix.exs:**
```elixir
# Update Snakepit dependency
{:snakepit, "~> 0.5.0"}
```

**Update Python requirements:**
```bash
# Uninstall old packages
pip uninstall snakepit-bridge dspex-adapters

# Install new packages  
pip install snakepit-bridge>=0.5.0 dspex-dspy>=0.3.0
```

### Step 2: Update Elixir Code

#### Automated Migration (Recommended)

Run the automated migration script:
```bash
mix dspex.migrate.variables
```

This script will:
- Update all `DSPex.Variables` calls to `Snakepit.Variables`
- Update all `DSPex.Context` calls to `Snakepit.Context`
- Add the new import statements
- Generate a migration report

#### Manual Migration

If you prefer manual migration:

1. **Replace module references:**
   ```bash
   # Find and replace in your codebase
   find . -name "*.ex" -o -name "*.exs" | xargs sed -i 's/DSPex\.Variables/Snakepit.Variables/g'
   find . -name "*.ex" -o -name "*.exs" | xargs sed -i 's/DSPex\.Context/Snakepit.Context/g'
   ```

2. **Update imports:**
   ```elixir
   # Add to modules that use variables/context
   alias Snakepit.{Context, Variables}
   ```

3. **Update examples and tests:**
   - Update all example files
   - Update test files
   - Update documentation

### Step 3: Update Python Code

#### DSPy Integration Code

**Before:**
```python
from snakepit_bridge.dspy_integration import (
    VariableAwarePredict, 
    create_variable_aware_program
)
from snakepit_bridge.variable_aware_mixin import VariableAwareMixin
from dspex_adapters.dspy_grpc import DSPyGRPCHandler
```

**After:**
```python
from dspex_dspy import (
    VariableAwarePredict,
    create_variable_aware_program,
    VariableAwareMixin,
    DSPyGRPCHandler
)
```

#### Schema Bridge Code

**Before:**
```python
from dspex_adapters.dspy_grpc import call_dspy, discover_schema
```

**After:**
```python
from dspex_dspy import call_dspy, discover_schema
```

### Step 4: Update Configuration

#### Application Configuration

**Before:**
```elixir
# config/config.exs
config :dspex,
  context_backend: :session_store

config :snakepit,
  adapter_module: Snakepit.Adapters.GRPCPython,
  pool_config: %{
    adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
  }
```

**After:**
```elixir
# config/config.exs - simplified
config :snakepit,
  adapter_module: Snakepit.Adapters.GRPCPython,
  pool_config: %{
    adapter_args: ["--adapter", "dspex_dspy.adapters.DSPyGRPCHandler"]
  }
```

#### Python Installation

**Before:**
```bash
pip install -e ./snakepit/priv/python
pip install -e ./priv/python
```

**After:**
```bash
pip install -e ./snakepit/priv/python  # Infrastructure only
pip install -e ./priv/python          # DSPy functionality
```

### Step 5: Test Migration

#### Compilation Test

```bash
# Test Elixir compilation
mix deps.get
mix compile

# Should show deprecation warnings for any remaining DSPex.Variables usage
```

#### Runtime Test

Run the new architecture demo:
```bash
mix run examples/dspy/new_architecture_demo.exs
```

#### Python Integration Test

```python
# Test Python imports
from dspex_dspy import VariableAwarePredict, DSPyGRPCHandler
from snakepit_bridge import SessionContext

print("✓ All imports successful")
```

## Backward Compatibility

### Deprecation Period

DSPex 0.3.0 provides **backward compatibility** for one full version:

- `DSPex.Variables.*` → Delegates to `Snakepit.Variables.*` (with warnings)
- `DSPex.Context.*` → Delegates to `Snakepit.Context.*` (with warnings)

### Deprecation Timeline

- **DSPex 0.3.0**: Deprecated APIs work with warnings
- **DSPex 0.4.0**: Deprecated APIs removed

### Warning Examples

When using deprecated APIs, you'll see warnings like:
```
warning: DSPex.Variables.get/3 is deprecated. Use Snakepit.Variables instead
```

## Common Migration Issues

### Issue 1: Import Errors

**Problem:**
```elixir
** (UndefinedFunctionError) function DSPex.Variables.get/2 is undefined
```

**Solution:**
Update the import:
```elixir
# Change this:
alias DSPex.Variables

# To this:
alias Snakepit.Variables
```

### Issue 2: Python Import Errors

**Problem:**
```python
ModuleNotFoundError: No module named 'snakepit_bridge.dspy_integration'
```

**Solution:**
```python
# Change this:
from snakepit_bridge.dspy_integration import VariableAwarePredict

# To this:
from dspex_dspy import VariableAwarePredict
```

### Issue 3: Adapter Configuration

**Problem:**
```
ERROR: Failed to load adapter dspex_adapters.dspy_grpc.DSPyGRPCHandler
```

**Solution:**
```elixir
# Update adapter path in config
config :snakepit,
  pool_config: %{
    adapter_args: ["--adapter", "dspex_dspy.adapters.DSPyGRPCHandler"]
  }
```

### Issue 4: Session Context

**Problem:**
Code that directly accesses DSPex context internals.

**Solution:**
Use the public API:
```elixir
# Instead of accessing internals:
# session_id = ctx.session_id

# Use the public API:
session_id = Snakepit.Context.get_session_id(ctx)
```

## Benefits After Migration

### 1. Cleaner Architecture

```elixir
# Infrastructure operations feel like infrastructure
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.set(ctx, :temp, 0.8)

# Domain operations feel like domain functionality  
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
```

### 2. Better Reusability

Snakepit can now be used independently:
```elixir
# Use Snakepit for any framework, not just DSPy
{:ok, ctx} = Snakepit.Context.start_link()
Snakepit.Variables.defvariable(ctx, :model_name, :string, "gpt-4")

# Use with TensorFlow, PyTorch, or any other framework
```

### 3. Improved Maintainability

- Variables have single ownership (Snakepit)
- DSPy integration has single ownership (DSPex)
- Clear dependency chain: DSPex → Snakepit

### 4. Enhanced Developer Experience

- Logical grouping of functionality
- Consistent API patterns
- Better discoverability

## Validation

### Migration Checklist

- [ ] Updated Snakepit dependency to 0.5.0
- [ ] Updated DSPex version to 0.3.0
- [ ] Replaced all `DSPex.Variables` with `Snakepit.Variables`
- [ ] Replaced all `DSPex.Context` with `Snakepit.Context`
- [ ] Updated Python imports to use `dspex_dspy`
- [ ] Updated adapter configuration
- [ ] Updated examples and tests
- [ ] All tests passing
- [ ] No compilation errors
- [ ] Deprecation warnings addressed (optional for 0.3.0)

### Success Criteria

- ✅ All existing functionality preserved
- ✅ No performance regressions
- ✅ All tests passing
- ✅ Examples working with new APIs
- ✅ Clean separation of concerns
- ✅ Logical API organization

## Getting Help

### Resources

- **Documentation**: Updated API docs available
- **Examples**: See `examples/dspy/new_architecture_demo.exs`
- **Migration Script**: `mix dspex.migrate.variables`

### Common Questions

**Q: Do I need to migrate immediately?**
A: No, the old APIs work in DSPex 0.3.0 with deprecation warnings. You have until DSPex 0.4.0 to migrate.

**Q: Will this break my existing code?**
A: No, DSPex 0.3.0 maintains backward compatibility. Your code will work but may show deprecation warnings.

**Q: How long does migration take?**
A: Most projects can be migrated in 15-30 minutes using the automated migration script.

**Q: What if I find issues?**
A: Please report issues on the [DSPex GitHub repository](https://github.com/nshkrdotcom/dspex/issues).

## Conclusion

The DSPex 0.3.0 migration brings significant architectural improvements while maintaining backward compatibility. The new separation between Snakepit (infrastructure) and DSPex (domain-specific functionality) creates a more maintainable, reusable, and intuitive system.

Follow this guide step-by-step, use the automated migration tools, and enjoy the benefits of the new architecture!
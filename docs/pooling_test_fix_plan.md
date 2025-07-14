# Pooling Test Fix Plan

## Overview
This document outlines the specific fixes needed to resolve the 20 integration test failures introduced by the pooling implementation.

## Fix Categories

### 1. Port Mock Implementation (Priority: High)
**Affected Tests:** PoolWorker tests 1-6
**Issue:** Tests use `self()` as mock port, but code calls `Port.connect` which requires real Port

**Solutions:**
1. **Option A**: Modify PoolWorker to check if port is actually a Port before calling connect
   ```elixir
   if is_port(port) do
     Port.connect(port, self())
   end
   ```

2. **Option B**: Create a proper MockPort that doesn't use Port.connect
   - Already have `DSPex.Test.MockPort` module
   - Need to update PoolWorker tests to use it properly

3. **Option C**: Add a test mode flag to skip Port.connect in tests

### 2. Dynamic Pool Naming (Priority: High)
**Affected Tests:** SessionPool tests 7-14
**Issue:** Fixed pool name causes conflicts between tests

**Solution:**
1. Modify SessionPool to accept pool name in options:
   ```elixir
   def start_link(opts) do
     name = Keyword.get(opts, :name, __MODULE__)
     pool_name = Keyword.get(opts, :pool_name, :"#{name}_pool")
     # Use pool_name for NimblePool registration
   end
   ```

2. Update `pool_name/0` to use state-based name:
   ```elixir
   defp pool_name(name) do
     :"#{name}_pool"
   end
   ```

### 3. Health Status Alignment (Priority: High)
**Affected Tests:** PoolWorker tests 1, 4, 6
**Issue:** Tests expect `:ready` but implementation uses `:healthy`

**Solution:**
1. Update test expectations to use correct status values:
   - `:ready` → `:healthy`
   - `:initializing` stays the same
   - Add `:degraded` status handling

### 4. Supervision Tree Setup (Priority: High)
**Affected Tests:** Integration tests 15-20
**Issue:** Python bridge not available in test environment

**Solutions:**
1. **For Layer 3 tests**: Ensure proper supervisor starts based on configuration
   - Check if pooling is enabled in config
   - Start appropriate supervisor (pooled vs single)

2. **Update test_helper.exs**: Add pooling mode configuration
   ```elixir
   case System.get_env("TEST_MODE") do
     "full_integration" ->
       # Start pooling supervisor for integration tests
       Application.put_env(:dspex, :pooling_enabled, true)
     _ ->
       # Use single instance for other tests
       Application.put_env(:dspex, :pooling_enabled, false)
   end
   ```

3. **Conditional supervisor**: Make ConditionalSupervisor check pooling config

### 5. Adapter Factory Updates (Priority: Medium)
**Affected Tests:** Adapter compliance tests 16-20
**Issue:** Factory returns PythonPool adapter but pool isn't initialized

**Solution:**
1. Update factory to check if pooling is available:
   ```elixir
   defp resolve_adapter(:layer_3) do
     if pooling_enabled?() and pool_available?() do
       DSPex.Adapters.PythonPool
     else
       DSPex.Adapters.PythonPort
     end
   end
   ```

## Implementation Order

1. **Fix health status values** (quick fix)
2. **Add dynamic pool naming** (prevents test conflicts)
3. **Fix port mock implementation** (unblocks PoolWorker tests)
4. **Update supervision setup** (enables integration tests)
5. **Update adapter factory** (completes integration)

## Test Categories After Fix

### Layer 1 (Mock Tests)
- Should not start any Python processes
- Use mock adapters only
- No pooling infrastructure needed

### Layer 2 (Bridge Mock Tests)
- Use mock ports that don't require Port.connect
- Test protocol and communication logic
- No real Python processes

### Layer 3 (Integration Tests)
- Start real Python processes
- Use either pooled or single-instance mode
- Full integration testing

## Configuration Strategy

Add configuration to control pooling:
```elixir
config :dspex,
  pooling_enabled: false,  # Default for tests
  pool_size: 2,           # Small pool for tests
  pool_mode: :test        # Special test mode
```

For production:
```elixir
config :dspex,
  pooling_enabled: true,
  pool_size: System.schedulers_online() * 2,
  pool_mode: :production
```
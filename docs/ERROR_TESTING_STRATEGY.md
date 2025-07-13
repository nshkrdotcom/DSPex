# Error Testing Strategy: Ensuring Comprehensive Failure Testing

This document analyzes the current state of error condition testing and provides recommendations for ensuring we have proper failing tests for each error condition.

## Current State Analysis

### The Paradox: Warnings Without Failures

Our tests generate numerous warnings but still pass. This happens because:

1. **Warnings are logged, not asserted** - The code logs warnings via `Logger.warning/1` or `IO.warn/1`, but tests don't verify these logs
2. **Error paths return valid results** - Many error handlers fall back to defaults rather than failing
3. **Tests verify behavior, not logging** - Tests check that the system handles errors gracefully but don't verify warnings were generated

### Example: Configuration Validation

```elixir
# In lib/dspex/config.ex
defp parse_integer(value, key, default) when is_binary(value) do
  case Integer.parse(value) do
    {int, ""} -> int
    _ ->
      Logger.warning("Invalid integer value for #{key}: #{value}")  # Logs warning
      default  # Returns default instead of failing
  end
end

# In test/dspex/config_test.exs
test "handles invalid environment variable values" do
  System.put_env("DSPEX_BRIDGE_TIMEOUT", "invalid_number")
  config = Config.get(:python_bridge)
  assert Map.has_key?(config, :default_timeout)  # Test passes! No failure!
end
```

## Recommendations for Comprehensive Error Testing

### 1. Capture and Assert on Logs

Use `ExUnit.CaptureLog` to verify warnings are actually logged:

```elixir
import ExUnit.CaptureLog

test "logs warning and uses default for invalid timeout" do
  log = capture_log(fn ->
    System.put_env("DSPEX_BRIDGE_TIMEOUT", "not_a_number")
    config = Config.get(:python_bridge)
    assert config[:default_timeout] == 30_000  # Verify behavior
  end)
  
  assert log =~ "Invalid integer value for default_timeout: not_a_number"  # Verify warning
end
```

### 2. Create Explicit Negative Test Cases

For each error condition, create tests that verify both the error and its effects:

```elixir
describe "error conditions" do
  test "returns error for malformed JSON responses" do
    # Don't just test that it handles the error - test what error it returns
    assert {:error, :decode_error} = Protocol.decode_response("not json")
  end
  
  test "returns specific error for binary data" do
    binary_data = :erlang.term_to_binary("data")
    assert {:error, :binary_data} = Protocol.decode_response(binary_data)
  end
  
  test "fails to create bridge with invalid Python path" do
    # Test that it actually fails, not just logs
    assert {:error, :python_not_found} = Bridge.start_link(python_path: "/invalid/path")
  end
end
```

### 3. Test Error Propagation

Ensure errors propagate correctly through the system:

```elixir
test "adapter returns error when bridge is not available" do
  # Stop the bridge to simulate failure
  GenServer.stop(DSPex.PythonBridge.Bridge)
  
  # Verify adapter handles missing bridge
  assert {:error, :bridge_not_running} = 
    DSPex.Adapters.PythonPort.create_program(%{signature: %{}})
end
```

### 4. Implement Strict Mode Testing

Add configuration option for strict error handling in tests:

```elixir
# In config/test.exs
config :dspex, :strict_errors, true

# In source code
defp handle_invalid_config(key, value) do
  if Application.get_env(:dspex, :strict_errors, false) do
    raise ArgumentError, "Invalid value for #{key}: #{value}"
  else
    Logger.warning("Invalid value for #{key}: #{value}")
    get_default(key)
  end
end
```

### 5. Create Error Condition Test Matrix

For each module, create a matrix of error conditions:

| Module | Error Condition | Current Behavior | Should Test |
|--------|----------------|------------------|-------------|
| Config | Invalid integer | Logs warning, uses default | ✓ Warning logged<br>✓ Default value used<br>✓ No crash |
| Protocol | Invalid JSON | Returns {:error, :decode_error} | ✓ Error tuple returned<br>✓ Warning logged<br>✓ Request correlation maintained |
| TestMode | Invalid mode | Falls back to :mock_adapter | ✓ Fallback behavior<br>✓ Warning logged<br>✓ No crash |
| Bridge | Python not found | Returns error tuple | ✓ Specific error returned<br>✓ Supervisor handles failure<br>✓ Fallback available |

### 6. Add Parameterized Error Tests

Use ExUnit's parameterized testing for comprehensive coverage:

```elixir
describe "handles various invalid inputs" do
  @invalid_configs [
    {"DSPEX_BRIDGE_TIMEOUT", "not_a_number", :default_timeout, 30_000},
    {"DSPEX_MAX_RETRIES", "invalid", :max_retries, 3},
    {"DSPEX_BRIDGE_TIMEOUT", "-1", :default_timeout, 30_000}  # Negative number
  ]
  
  for {env_var, invalid_value, config_key, expected} <- @invalid_configs do
    test "handles invalid #{env_var} = #{invalid_value}" do
      log = capture_log(fn ->
        System.put_env(unquote(env_var), unquote(invalid_value))
        config = Config.get(:python_bridge)
        assert config[unquote(config_key)] == unquote(expected)
      end)
      
      assert log =~ "Invalid"
    end
  end
end
```

### 7. Implement Error Injection Testing

Create a test helper for injecting errors:

```elixir
defmodule ErrorInjection do
  def with_failing_bridge(fun) do
    # Temporarily replace bridge with failing version
    original = Process.whereis(DSPex.PythonBridge.Bridge)
    if original, do: GenServer.stop(original)
    
    # Start a bridge that always fails
    {:ok, _} = GenServer.start_link(FailingBridge, [], name: DSPex.PythonBridge.Bridge)
    
    try do
      fun.()
    after
      # Restore original
      GenServer.stop(DSPex.PythonBridge.Bridge)
      if original, do: DSPex.PythonBridge.Bridge.start_link()
    end
  end
end

test "handles bridge failures gracefully" do
  ErrorInjection.with_failing_bridge(fn ->
    assert {:error, _} = SomeModule.operation_requiring_bridge()
  end)
end
```

## Implementation Priority

1. **High Priority**: Add log assertions to existing tests that trigger warnings
2. **Medium Priority**: Create dedicated error condition test suites
3. **Low Priority**: Implement strict mode for development/CI environments

## Benefits of Comprehensive Error Testing

1. **Confidence in Error Handling** - Know that errors are handled correctly, not just logged
2. **Regression Prevention** - Catch when error handling behavior changes
3. **Documentation** - Tests serve as documentation of expected error behavior
4. **Debugging** - Clear test failures when error handling breaks

## Example: Refactoring an Existing Test

### Before (Current State)
```elixir
test "handles invalid environment variable gracefully" do
  System.put_env("TEST_MODE", "invalid_mode")
  assert TestMode.current_test_mode() == :mock_adapter
end
```

### After (With Comprehensive Error Testing)
```elixir
test "handles invalid environment variable gracefully" do
  log = capture_log(fn ->
    System.put_env("TEST_MODE", "invalid_mode")
    
    # Verify fallback behavior
    assert TestMode.current_test_mode() == :mock_adapter
    
    # Verify no crash when using the mode
    assert is_atom(TestMode.get_adapter_module())
  end)
  
  # Verify warning was logged
  assert log =~ "Invalid TEST_MODE: invalid_mode"
  assert log =~ "using default: mock_adapter"
  
  # Verify system still functional
  adapter = TestMode.get_adapter_module()
  assert adapter.supports_test_layer?(:layer_1)
end
```

## Conclusion

While our current tests verify that the system handles errors gracefully (which is why they pass despite warnings), we should enhance them to also verify that appropriate warnings are logged and that error conditions are properly detected and reported. This will give us greater confidence in our error handling and make the test suite more robust.
# Test Pattern Preservation Guide

## Overview

This document captures all test patterns currently in use across the DSPex codebase that must be preserved during the refactoring process.

## Test File Organization

### Current Test Structure
```
dspex/
├── test/
│   ├── dspex/
│   │   ├── context_call_test.exs
│   │   ├── variables_integration_test.exs
│   │   ├── variables_test.exs
│   │   ├── native/
│   │   │   └── signature_test.exs
│   │   └── llm/
│   │       ├── client_test.exs
│   │       ├── live_test.exs
│   │       └── adapters/
│   │           ├── instructor_lite_test.exs
│   │           ├── mock_test.exs
│   │           └── gemini_test.exs
│   ├── dspex_test.exs
│   ├── test_helper.exs
│   └── python/
│       └── test_stage2_integration.py

snakepit/
├── test/
│   ├── snakepit_test.exs
│   └── test_helper.exs
└── test_bridge_quarantine/
    ├── bridge/
    │   ├── session_store_test.exs
    │   ├── serialization_test.exs
    │   ├── property_test.exs
    │   └── variables/
    │       ├── variable_test.exs
    │       └── types_test.exs
    └── integration/
        └── grpc_bridge_integration_test.exs
```

## Core Test Patterns

### 1. Unit Test Pattern

```elixir
defmodule ModuleNameTest do
  use ExUnit.Case, async: true
  
  # Module-level setup
  setup_all do
    # One-time setup
    :ok
  end
  
  # Test-level setup
  setup do
    # Per-test setup
    {:ok, state: initial_state}
  end
  
  describe "function_name/arity" do
    test "description of behavior", %{state: state} do
      # Arrange
      input = prepare_input()
      
      # Act
      result = Module.function_name(input)
      
      # Assert
      assert result == expected_value
    end
    
    test "handles error case" do
      assert_raise ArgumentError, fn ->
        Module.function_with_bad_input(nil)
      end
    end
  end
end
```

### 2. Integration Test Pattern

```elixir
defmodule IntegrationTest do
  use ExUnit.Case, async: false  # No async for integration tests
  
  @moduletag :integration
  
  setup do
    # Start required services
    {:ok, session} = start_session()
    
    on_exit(fn ->
      # Cleanup
      cleanup_session(session)
    end)
    
    {:ok, session: session}
  end
  
  test "full workflow", %{session: session} do
    # Multiple steps testing integration
    {:ok, result1} = step_one(session)
    {:ok, result2} = step_two(session, result1)
    assert final_step(session, result2) == :success
  end
end
```

### 3. Context/Session Test Pattern

```elixir
defmodule ContextTest do
  use ExUnit.Case, async: true
  
  setup do
    {:ok, ctx} = Context.start_link()
    {:ok, ctx: ctx}
  end
  
  test "context operations", %{ctx: ctx} do
    # Test context-aware operations
    assert {:ok, _} = Context.put(ctx, :key, "value")
    assert Context.get(ctx, :key) == "value"
  end
end
```

### 4. Variable System Test Pattern

```elixir
defmodule VariablesTest do
  use ExUnit.Case, async: true
  
  setup do
    {:ok, ctx} = Context.start_link()
    {:ok, ctx: ctx}
  end
  
  describe "defvariable/5" do
    test "creates typed variables", %{ctx: ctx} do
      assert {:ok, var_id} = Variables.defvariable(ctx, :test, :string, "hello")
      assert String.starts_with?(var_id, "var_")
      assert Variables.get(ctx, :test) == "hello"
    end
    
    test "enforces constraints", %{ctx: ctx} do
      assert {:ok, _} = Variables.defvariable(
        ctx, :score, :float, 0.5, 
        constraints: %{min: 0.0, max: 1.0}
      )
      
      # Valid update
      assert :ok = Variables.set(ctx, :score, 0.8)
      
      # Invalid update
      assert {:error, _} = Variables.set(ctx, :score, 1.5)
    end
  end
end
```

### 5. Mock Adapter Test Pattern

```elixir
defmodule MockAdapterTest do
  use ExUnit.Case, async: true
  
  setup do
    # Configure mock adapter
    config = %{
      adapter: DSPex.LLM.Adapters.Mock,
      responses: %{
        "test_prompt" => "mocked response"
      }
    }
    
    {:ok, config: config}
  end
  
  test "uses mock responses", %{config: config} do
    client = DSPex.LLM.Client.new(config)
    result = DSPex.LLM.Client.call(client, "test_prompt")
    assert result == {:ok, "mocked response"}
  end
end
```

### 6. Property-Based Test Pattern

```elixir
defmodule PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "serialization round-trip" do
    check all value <- term() do
      serialized = Serialization.encode(value)
      {:ok, deserialized} = Serialization.decode(serialized)
      assert deserialized == value
    end
  end
  
  property "variable constraints" do
    check all min <- integer(),
              max <- integer(min..10000),
              value <- integer() do
      constraints = %{min: min, max: max}
      valid? = value >= min and value <= max
      
      result = Validator.validate_integer(value, constraints)
      assert (result == :ok) == valid?
    end
  end
end
```

### 7. Python Integration Test Pattern

```python
# test/python/test_integration.py
import pytest
from snakepit_bridge import SessionContext

class TestPythonIntegration:
    @pytest.fixture
    def session(self):
        ctx = SessionContext()
        yield ctx
        ctx.cleanup()
    
    def test_dspy_integration(self, session):
        # Test Python-side functionality
        result = session.execute("dspy.Predict", {
            "signature": "question -> answer"
        })
        assert result["success"] == True
        assert "instance_id" in result
```

### 8. Async Test Pattern

```elixir
defmodule AsyncTest do
  use ExUnit.Case, async: true
  
  test "concurrent operations" do
    tasks = for i <- 1..10 do
      Task.async(fn ->
        {:ok, result} = perform_operation(i)
        result
      end)
    end
    
    results = Task.await_many(tasks)
    assert length(results) == 10
    assert Enum.all?(results, & &1.success)
  end
end
```

### 9. Streaming Test Pattern

```elixir
defmodule StreamingTest do
  use ExUnit.Case
  
  test "handles streaming responses" do
    {:ok, stream} = start_streaming_operation()
    
    chunks = Enum.take(stream, 5)
    assert length(chunks) == 5
    assert Enum.all?(chunks, &is_binary/1)
  end
end
```

### 10. Error Handling Test Pattern

```elixir
defmodule ErrorHandlingTest do
  use ExUnit.Case
  
  describe "error scenarios" do
    test "handles timeout" do
      assert {:error, :timeout} = 
        Operation.execute_with_timeout(100, fn ->
          Process.sleep(200)
        end)
    end
    
    test "handles invalid input" do
      assert {:error, {:invalid_input, _}} = 
        Operation.process(nil)
    end
    
    test "handles Python bridge errors" do
      assert {:error, {:python_error, message}} = 
        Bridge.call("invalid.module", %{})
      
      assert message =~ "ModuleNotFoundError"
    end
  end
end
```

## Test Helpers and Utilities

### 1. Test Helper Module

```elixir
# test/test_helper.exs
ExUnit.start()

defmodule TestHelpers do
  def with_session(fun) do
    {:ok, session} = start_test_session()
    try do
      fun.(session)
    after
      cleanup_session(session)
    end
  end
  
  def assert_eventually(fun, timeout \\ 5000) do
    assert wait_until(fun, timeout)
  end
  
  defp wait_until(fun, timeout) when timeout > 0 do
    if fun.() do
      true
    else
      Process.sleep(100)
      wait_until(fun, timeout - 100)
    end
  end
  
  defp wait_until(_, _), do: false
end
```

### 2. Factory Pattern

```elixir
defmodule Factory do
  def build(:signature) do
    %{
      inputs: [%{name: :input, type: :string}],
      outputs: [%{name: :output, type: :string}]
    }
  end
  
  def build(:context) do
    {:ok, ctx} = Context.start_link()
    ctx
  end
  
  def build(:predictor, signature \\ build(:signature)) do
    {:ok, predictor_id} = DSPex.Modules.Predict.create(signature)
    predictor_id
  end
end
```

## Test Configuration Patterns

### 1. Environment-based Configuration

```elixir
# config/test.exs
config :dspex,
  llm_adapter: DSPex.LLM.Adapters.Mock,
  pool_size: 1,
  startup_timeout: 1000

config :snakepit,
  pools: [
    test: [
      size: 1,
      adapter: Snakepit.Adapters.Mock
    ]
  ]
```

### 2. Test Tags and Filtering

```elixir
# Tag slow tests
@tag :slow
test "expensive operation" do
  # ...
end

# Tag integration tests
@moduletag :integration
defmodule IntegrationTest do
  # ...
end

# Run only unit tests
# mix test --exclude integration

# Run all tests including slow ones
# mix test --include slow
```

## Preservation Requirements

### 1. Maintain Test Isolation
- Each test must be independent
- No shared state between tests
- Proper cleanup in `on_exit` callbacks

### 2. Preserve Async Capability
- Unit tests should remain `async: true`
- Integration tests stay `async: false`
- No global state modifications in async tests

### 3. Keep Test Patterns Consistent
- AAA pattern (Arrange, Act, Assert)
- Descriptive test names
- Group related tests with `describe`

### 4. Maintain Coverage Standards
- Minimum 80% code coverage
- Critical paths must have 100% coverage
- Property tests for data transformations

### 5. Preserve Helper Functions
- Context creation helpers
- Assertion helpers
- Factory functions
- Mock setup utilities

## Migration Checklist

When migrating tests during refactoring:

- [ ] Update module names in test files
- [ ] Update import/alias statements
- [ ] Verify all test helpers still work
- [ ] Ensure mock adapters are compatible
- [ ] Update configuration for new structure
- [ ] Run full test suite after each change
- [ ] Verify async tests still pass in parallel
- [ ] Check property tests with new modules
- [ ] Update Python integration tests
- [ ] Ensure CI/CD pipeline still works
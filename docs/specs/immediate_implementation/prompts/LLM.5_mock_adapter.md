# Task: LLM.5 - Mock Adapter for Testing

## Context
You are implementing a mock adapter that simulates LLM behavior for testing purposes. This adapter enables fast, deterministic testing of DSPex components without making actual LLM API calls.

## Required Reading

### 1. Existing Mock Adapter
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapters/mock.ex`
  - Review current mock patterns
  - Note response simulation approach

### 2. Testing Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/03_IMPLEMENTATION_ROADMAP.md`
  - Section on three-layer testing
  - Layer 1 mock requirements

### 3. libStaging Mock Patterns
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 231-238: Mock testing patterns
  - Mock client manager example

### 4. LLM Adapter Protocol
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/prompts/LLM.1_adapter_protocol.md`
  - Protocol functions to implement
  - Expected behavior patterns

### 5. Test Patterns
- **File**: Look for test files using mock adapter
  - Common mock scenarios
  - Response patterns

## Implementation Requirements

### Mock Adapter Structure
```elixir
defmodule DSPex.LLM.Adapters.Mock do
  @behaviour DSPex.LLM.Adapter
  
  defstruct [
    :responses,           # Predefined responses
    :response_pattern,    # :sequential | :random | :function
    :delay,              # Simulate network delay
    :failure_rate,       # Simulate failures
    :call_history,       # Track calls for assertions
    :behavior_overrides  # Per-test customization
  ]
end
```

### Response Configuration
```elixir
# Static responses
%Mock{
  responses: %{
    "What is 2+2?" => "4",
    "default" => "This is a mock response"
  }
}

# Pattern-based responses
%Mock{
  response_pattern: :function,
  response_fn: fn prompt, opts ->
    cond do
      String.contains?(prompt, "error") ->
        {:error, :simulated_error}
        
      opts[:schema] ->
        generate_mock_structured(opts[:schema])
        
      true ->
        "Mock response for: #{prompt}"
    end
  end
}

# Sequential responses
%Mock{
  response_pattern: :sequential,
  responses: ["First", "Second", "Third"],
  current_index: 0
}
```

### Structured Output Generation
```elixir
defp generate_mock_structured(schema) do
  schema
  |> Enum.map(fn {key, type} ->
    {key, generate_mock_value(type)}
  end)
  |> Map.new()
end

defp generate_mock_value(:string), do: "mock_string"
defp generate_mock_value(:integer), do: 42
defp generate_mock_value(:float), do: 3.14
defp generate_mock_value(:boolean), do: true
defp generate_mock_value({:array, type}), do: [generate_mock_value(type)]
defp generate_mock_value({:optional, type}), do: generate_mock_value(type)
defp generate_mock_value(map) when is_map(map) do
  generate_mock_structured(map)
end
```

### Behavior Simulation
```elixir
def generate(adapter, prompt, opts) do
  # Record call
  record_call(adapter, {:generate, prompt, opts})
  
  # Simulate delay
  if adapter.delay do
    Process.sleep(adapter.delay)
  end
  
  # Simulate failures
  if should_fail?(adapter) do
    {:error, select_error_type(adapter)}
  else
    {:ok, get_mock_response(adapter, prompt, opts)}
  end
end

defp should_fail?(%{failure_rate: rate}) when is_number(rate) do
  :rand.uniform() < rate
end

defp select_error_type(adapter) do
  Enum.random([
    :timeout,
    {:api_error, 500, "Internal server error"},
    {:rate_limited, 60},
    :network_error
  ])
end
```

### Call History Tracking
```elixir
defmodule MockHistory do
  use Agent
  
  def start_link do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end
  
  def record_call(call) do
    Agent.update(__MODULE__, &[call | &1])
  end
  
  def get_calls do
    Agent.get(__MODULE__, &Enum.reverse(&1))
  end
  
  def clear do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
  
  def assert_called(expected) do
    calls = get_calls()
    unless Enum.any?(calls, &match?(^expected, &1)) do
      raise "Expected call not found: #{inspect(expected)}"
    end
  end
end
```

### Test Helpers
```elixir
defmodule DSPex.LLM.MockHelpers do
  def with_mock_responses(responses, fun) do
    adapter = %Mock{responses: responses}
    Process.put(:mock_adapter, adapter)
    
    try do
      fun.(adapter)
    after
      Process.delete(:mock_adapter)
      MockHistory.clear()
    end
  end
  
  def assert_llm_called(prompt) do
    MockHistory.assert_called({:generate, prompt, _})
  end
  
  def stub_structured_response(schema, response) do
    adapter = Process.get(:mock_adapter)
    updated = %{adapter | 
      behavior_overrides: Map.put(
        adapter.behavior_overrides || %{},
        schema,
        response
      )
    }
    Process.put(:mock_adapter, updated)
  end
end
```

## Acceptance Criteria
- [ ] Implements all adapter protocol functions
- [ ] Supports static and dynamic responses
- [ ] Generates valid structured outputs for schemas
- [ ] Simulates realistic delays and failures
- [ ] Tracks call history for test assertions
- [ ] Provides test helper functions
- [ ] Supports streaming simulation
- [ ] Thread-safe for concurrent tests
- [ ] Deterministic behavior for given inputs

## Testing the Mock
Create tests in:
- `test/dspex/llm/adapters/mock_test.exs`

Test scenarios:
- Response pattern modes
- Structured output generation
- Failure simulation
- Call history tracking
- Concurrent usage
- Helper functions

## Example Usage
```elixir
# In tests
defmodule MyTest do
  use ExUnit.Case
  import DSPex.LLM.MockHelpers
  
  test "processes user query" do
    with_mock_responses(%{
      "Hello" => "Hi there!",
      "default" => "Mock response"
    }, fn adapter ->
      # Your test code
      result = MyModule.process("Hello")
      assert result == "Hi there!"
      
      # Verify LLM was called
      assert_llm_called("Hello")
    end)
  end
  
  test "handles structured output" do
    adapter = %Mock{
      response_pattern: :function,
      response_fn: fn _prompt, opts ->
        if opts[:schema] do
          %{
            "name" => "Test User",
            "age" => 25,
            "active" => true
          }
        end
      end
    }
    
    {:ok, user} = DSPex.LLM.Adapter.generate(
      adapter,
      "Generate user",
      schema: %{name: :string, age: :integer, active: :boolean}
    )
    
    assert user["name"] == "Test User"
  end
end
```

## Dependencies
- Requires LLM.1 (Adapter Protocol) complete
- No external dependencies
- Used by all test suites

## Time Estimate
4 hours total:
- 1 hour: Core mock implementation
- 1 hour: Response pattern systems
- 1 hour: Test helpers and utilities
- 1 hour: Testing the mock itself

## Notes
- Keep mock behavior predictable
- Add helpers for common test scenarios
- Consider property-based testing support
- Make debugging easy with good error messages
- Support both simple and complex test cases
- Consider adding fixture loading from files
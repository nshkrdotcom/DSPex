# DSPex 3-Layer Testing Architecture

A comprehensive testing framework that provides fast development cycles while maintaining full system confidence through layered test execution.

## 📝 One-Paragraph Summary

**Run `mix test.fast` for daily development (70ms), `mix test.protocol` for wire protocol validation, and `mix test.integration` for full Python DSPy integration testing.** The 3-layer architecture separates pure Elixir unit tests (Layer 1) that run in milliseconds using mock adapters, from protocol validation tests (Layer 2) that verify wire communication without Python dependencies, from complete end-to-end integration tests (Layer 3) that require a full Python DSPy environment. This design enables rapid TDD cycles while maintaining comprehensive system validation - run `mix test.all` to execute all layers sequentially with progress reporting.

## 🏗️ Architecture Overview

### Layer 1: Mock Adapter (Pure Elixir)
- **Purpose**: Fast unit testing without external dependencies
- **Speed**: ~70ms execution time
- **Concurrency**: Up to 50 concurrent tests
- **Use Case**: 90%+ of development testing, TDD cycles

### Layer 2: Bridge Mock (Protocol Testing)
- **Purpose**: Validate wire protocol and serialization
- **Speed**: ~500ms execution time  
- **Concurrency**: Up to 10 concurrent tests
- **Use Case**: Critical protocol paths, error handling

### Layer 3: Full Integration (Real Python)
- **Purpose**: End-to-end validation with real DSPy
- **Speed**: 2-5s per test
- **Concurrency**: Sequential execution
- **Use Case**: Smoke tests, production confidence

## 🚀 Quick Start

### Using Mix Commands (Recommended)

```bash
# Layer 1: Fast unit tests with mock adapter (~70ms)
mix test.fast

# Layer 2: Protocol testing without full Python bridge
mix test.protocol  

# Layer 3: Full integration tests with Python bridge
mix test.integration

# Run all layers sequentially with status reporting
mix test.all
```

### Using Environment Variables (Advanced)

```bash
# Layer 1: Fast unit tests with mock adapter (default)
mix test
TEST_MODE=mock_adapter mix test

# Layer 2: Test bridge protocol without Python
TEST_MODE=bridge_mock mix test

# Layer 3: Complete E2E tests with real Python DSPy
TEST_MODE=full_integration mix test
```

## 📋 Layer Execution Script

Use the provided script for comprehensive layer testing:

```bash
# Run specific layers
./scripts/test_layers.exs mock              # Layer 1 only
./scripts/test_layers.exs bridge            # Layer 2 only  
./scripts/test_layers.exs full              # Layer 3 only

# Run all layers in sequence
./scripts/test_layers.exs all

# With timing and performance analysis
./scripts/test_layers.exs all --timing --stats

# Verbose output for debugging
./scripts/test_layers.exs mock --verbose --trace

# Parallel execution (Layers 1-2)
./scripts/test_layers.exs all --parallel
```

### Script Options
- `--verbose, -v`: Show detailed command output
- `--trace, -t`: Enable ExUnit test tracing
- `--parallel, -p`: Run compatible layers in parallel
- `--timing`: Show execution timing
- `--stats`: Show performance analysis
- `--help, -h`: Display help information

## ⚙️ Configuration

### Environment Variables
```bash
# Set test mode
export TEST_MODE=mock_adapter    # Layer 1 (default)
export TEST_MODE=bridge_mock     # Layer 2
export TEST_MODE=full_integration # Layer 3
```

### Application Configuration
```elixir
# config/test_dspy.exs
config :dspex, :test_mode, :mock_adapter  # Default layer

# Layer 1: Mock Adapter
config :dspex, :mock_adapter,
  response_delay_ms: 0,        # No delay for speed
  error_rate: 0.0,             # No random errors
  deterministic: true,         # Consistent responses
  mock_responses: %{}          # Custom responses

# Layer 2: Bridge Mock Server  
config :dspex, :bridge_mock_server,
  response_delay_ms: 10,       # Minimal protocol overhead
  error_probability: 0.0,      # No random errors
  max_programs: 100,           # Program limit
  enable_logging: true         # Debug logging
```

## 🧪 Test Organization

### Layer 1 Tests (Fast Unit Tests)
```elixir
# test/dspex/adapters/mock_test.exs
defmodule MyBusinessLogicTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Adapters.Mock
  
  test "business logic works correctly" do
    {:ok, _} = Mock.start_link()
    
    # Test your Ash business logic with deterministic responses
    signature = %{
      "inputs" => [%{"name" => "question", "type" => "string"}],
      "outputs" => [%{"name" => "answer", "type" => "string"}]
    }
    
    {:ok, _} = Mock.create_program(%{id: "test", signature: signature})
    {:ok, result} = Mock.execute_program("test", %{"question" => "test"})
    
    assert Map.has_key?(result, "answer")
  end
end
```

### Layer 2 Tests (Protocol Validation)
```elixir
# Run with: TEST_MODE=bridge_mock mix test
test "protocol handles errors correctly" do
  # Test serialization, timeouts, error scenarios
  # without needing Python dependencies
end
```

### Layer 3 Tests (Full Integration)
```elixir
# Existing integration tests - preserved as-is
# Run with: TEST_MODE=full_integration mix test
test "complete system integration" do
  # Real Python DSPy testing
  # Full end-to-end workflows
end
```

## 📊 Performance Targets

| Layer | Target Time | Typical Use | Concurrency |
|-------|-------------|-------------|-------------|
| Layer 1 | < 5 seconds | Development, TDD | High (50) |
| Layer 2 | < 15 seconds | Protocol validation | Medium (10) |
| Layer 3 | < 2 minutes | E2E confidence | Sequential (1) |

## 🔄 Development Workflow

### 1. Fast Development (Layer 1)
```bash
# Rapid TDD cycle - run constantly during development
TEST_MODE=mock_adapter mix test --stale
```

### 2. Protocol Check (Layer 2)  
```bash
# Before commits - validate protocol changes
TEST_MODE=bridge_mock mix test
```

### 3. Pre-Production (Layer 3)
```bash
# Before releases - full system validation
TEST_MODE=full_integration mix test
```

### 4. Complete Validation
```bash
# Run all layers with performance monitoring
./scripts/test_layers.exs all --timing --stats
```

## 🎯 Testing Strategies

### Test Distribution
- **90%+ tests**: Layer 1 (business logic, edge cases)
- **5-10% tests**: Layer 2 (critical protocol paths)
- **1-5% tests**: Layer 3 (smoke tests, key workflows)

### Layer-Specific Testing

#### Layer 1: Focus on Business Logic
- Ash resource behaviors
- Data transformations  
- Error handling
- Edge cases
- Concurrent operations

#### Layer 2: Focus on Protocol
- Request/response serialization
- Error propagation
- Timeout handling
- Message correlation
- Wire format validation

#### Layer 3: Focus on Integration
- Real DSPy model calls
- Complete workflows
- Production scenarios
- Performance under load

## 🛠️ Advanced Usage

### Custom Mock Scenarios
```elixir
# Set up custom response scenarios
Mock.set_scenario(:custom_qa, %{
  "answer" => "Custom test response"
})

# Error injection for resilience testing
Mock.inject_error(%{
  create_program: %{
    probability: 0.1,
    type: :network_error,
    message: "Simulated network failure"
  }
})
```

### Bridge Mock Configuration
```elixir
# Add error scenarios to bridge mock
BridgeMockServer.add_error_scenario(:test_server, %{
  command: "execute_program",
  probability: 1.0,
  error_type: :timeout,
  message: "Request timeout"
})
```

### Performance Analysis
```bash
# Detailed performance breakdown
./scripts/test_layers.exs all --timing --stats --verbose

# Example output:
# Layer 1: ✅ 0.07s (target: 5s) - 99% faster than target
# Layer 2: ✅ 0.5s (target: 15s) - 97% faster than target  
# Layer 3: ✅ 8.2s (target: 120s) - 93% faster than target
```

## 🐛 Debugging

### Test Mode Detection Issues
```bash
# Check current test mode
iex -S mix
iex> DSPex.Testing.TestMode.current_test_mode()
:mock_adapter

# Verify environment
echo $TEST_MODE
```

### Layer-Specific Debugging
```bash
# Layer 1 debugging
TEST_MODE=mock_adapter mix test --trace --max-cases=1

# Layer 2 debugging  
TEST_MODE=bridge_mock mix test --trace --verbose

# Layer 3 debugging
TEST_MODE=full_integration mix test --trace --timeout=60000
```

### Mock Adapter State Inspection
```elixir
# In tests or IEx
{:ok, _} = DSPex.Adapters.Mock.start_link()

# Check statistics
DSPex.Adapters.Mock.get_stats()

# Inspect programs
DSPex.Adapters.Mock.get_programs()

# Reset state
DSPex.Adapters.Mock.reset()
```

## 🔧 CI/CD Integration

### GitHub Actions Example
```yaml
name: Test All Layers
on: [push, pull_request]

jobs:
  test-layer-1:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: TEST_MODE=mock_adapter mix test --max-cases=50
      
  test-layer-2:
    runs-on: ubuntu-latest  
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: TEST_MODE=bridge_mock mix test --max-cases=10
      
  test-layer-3:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - uses: actions/setup-python@v4
      - run: pip install dspy-ai google-generativeai
      - run: TEST_MODE=full_integration mix test --max-cases=1
```

### Pre-commit Hooks
```bash
#!/bin/sh
# .git/hooks/pre-commit

echo "Running Layer 1 tests..."
TEST_MODE=mock_adapter mix test || exit 1

echo "Running Layer 2 tests..."  
TEST_MODE=bridge_mock mix test || exit 1

echo "All tests passed!"
```

## 📚 API Reference

### Test Mode Functions
```elixir
# Get current test mode
DSPex.Testing.TestMode.current_test_mode()

# Set process-level override
DSPex.Testing.TestMode.set_test_mode(:bridge_mock)

# Get effective mode (with overrides)
DSPex.Testing.TestMode.effective_test_mode()

# Get layer configuration
DSPex.Testing.TestMode.get_test_config()

# Check capabilities
DSPex.Testing.TestMode.layer_supports_async?()
DSPex.Testing.TestMode.get_isolation_level()
```

### Mock Adapter API
```elixir
# Start/stop
{:ok, pid} = DSPex.Adapters.Mock.start_link()

# Bridge-compatible API
{:ok, result} = DSPex.Adapters.Mock.ping()
{:ok, result} = DSPex.Adapters.Mock.create_program(config)
{:ok, result} = DSPex.Adapters.Mock.execute_program(id, inputs)

# Test utilities
DSPex.Adapters.Mock.reset()
DSPex.Adapters.Mock.get_stats()
DSPex.Adapters.Mock.set_scenario(name, config)
DSPex.Adapters.Mock.inject_error(config)
```

## 🤝 Contributing

When adding new tests:

1. **Layer 1**: Add fast unit tests for all business logic
2. **Layer 2**: Add protocol tests for new bridge commands
3. **Layer 3**: Add integration tests only for critical workflows

Follow the testing pyramid: many Layer 1 tests, some Layer 2 tests, few Layer 3 tests.

## 📈 Monitoring

Track test execution performance:

```bash
# Regular performance check
./scripts/test_layers.exs all --timing --stats

# Performance regression detection
# Layer 1 taking >5s = investigate
# Layer 2 taking >15s = investigate  
# Layer 3 taking >2m = investigate
```

---

**🎉 Happy Testing!** The 3-layer architecture provides fast feedback loops while maintaining comprehensive system confidence.
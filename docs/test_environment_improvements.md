# Long-Term Test Environment Improvements for DSPex

## Overview
This document outlines a comprehensive strategy for improving the DSPex test environment with a focus on long-term maintainability, scalability, and addressing current DSPy integration issues.

## Current Issues to Address

### 1. Language Model Configuration
- **Problem**: "No LM is loaded" errors in integration tests
- **Root Cause**: DSPy requires a configured language model (Gemini) but tests don't properly initialize it

### 2. Test Isolation
- **Problem**: Program ID conflicts, shared state between tests
- **Root Cause**: Tests use hardcoded IDs and share global resources

### 3. Resource Management
- **Problem**: Python processes spawned during tests, port leaks, broken pipes
- **Root Cause**: Improper cleanup and resource lifecycle management

## Proposed Architecture

### 1. Test Environment Layers (Enhanced)

```elixir
defmodule DSPex.Test.Environment do
  @moduledoc """
  Centralized test environment configuration and management.
  """
  
  defstruct [
    :layer,
    :adapter,
    :python_enabled,
    :pooling_enabled,
    :lm_config,
    :isolation_level,
    :resource_manager
  ]
  
  @layers %{
    unit: %{
      adapter: :mock,
      python_enabled: false,
      pooling_enabled: false,
      lm_config: :mock,
      isolation_level: :full
    },
    integration: %{
      adapter: :bridge_mock,
      python_enabled: true,
      pooling_enabled: false,
      lm_config: :mock,
      isolation_level: :namespace
    },
    e2e: %{
      adapter: :python_pool,
      python_enabled: true,
      pooling_enabled: true,
      lm_config: :real,
      isolation_level: :session
    }
  }
end
```

### 2. Language Model Test Configuration

```elixir
defmodule DSPex.Test.LMConfig do
  @moduledoc """
  Manages language model configuration for different test scenarios.
  """
  
  def setup_test_lm(mode) do
    case mode do
      :mock ->
        # Use a deterministic mock LM for unit tests
        setup_mock_lm()
        
      :cached ->
        # Use cached responses for integration tests
        setup_cached_lm()
        
      :real ->
        # Use real Gemini API with test quotas
        setup_real_lm()
    end
  end
  
  defp setup_mock_lm do
    # Configure DSPy with a mock LM that returns predictable responses
    %{
      type: :mock,
      responses: %{
        "test_input" => "test_output",
        default: "mock_response"
      }
    }
  end
  
  defp setup_cached_lm do
    # Use VCR-like response caching for deterministic integration tests
    %{
      type: :cached,
      cache_dir: "test/fixtures/lm_responses",
      fallback: :record  # Record new responses when not cached
    }
  end
  
  defp setup_real_lm do
    # Real API with rate limiting and cost controls
    %{
      type: :gemini,
      api_key: System.get_env("GEMINI_TEST_API_KEY"),
      rate_limit: 10,  # requests per minute
      cost_limit: 1.00,  # dollars per test run
      model: "gemini-1.5-flash"  # Cheaper model for tests
    }
  end
end
```

### 3. Test Isolation Framework

```elixir
defmodule DSPex.Test.Isolation do
  @moduledoc """
  Provides test isolation mechanisms at different levels.
  """
  
  defmacro isolated_test(name, opts \\ [], do: block) do
    quote do
      test unquote(name), context do
        isolation = DSPex.Test.Isolation.setup(unquote(opts))
        
        try do
          # Create isolated namespace
          namespace = isolation.create_namespace()
          
          # Override context with isolated resources
          context = Map.merge(context, %{
            namespace: namespace,
            program_prefix: namespace,
            session_id: "#{namespace}_session",
            adapter: isolation.create_adapter(namespace)
          })
          
          unquote(block)
        after
          DSPex.Test.Isolation.cleanup(isolation)
        end
      end
    end
  end
  
  def setup(opts) do
    %{
      id: generate_test_id(),
      resources: [],
      cleanup_tasks: [],
      level: Keyword.get(opts, :level, :full)
    }
  end
  
  def cleanup(isolation) do
    # Run all cleanup tasks in reverse order
    Enum.reverse(isolation.cleanup_tasks)
    |> Enum.each(& &1.())
  end
end
```

### 4. Resource Management

```elixir
defmodule DSPex.Test.ResourceManager do
  @moduledoc """
  Manages test resources lifecycle (ports, processes, files).
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Set up resource tracking
    {:ok, %{
      resources: %{
        ports: MapSet.new(),
        processes: MapSet.new(),
        temp_files: MapSet.new()
      },
      cleanup_on_exit: true
    }}
  end
  
  def track_port(port) do
    GenServer.call(__MODULE__, {:track, :ports, port})
  end
  
  def track_process(pid) do
    GenServer.call(__MODULE__, {:track, :processes, pid})
  end
  
  def cleanup_all do
    GenServer.call(__MODULE__, :cleanup_all)
  end
  
  # Automatic cleanup on test process exit
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cleanup_for_process(pid, state)
    {:noreply, state}
  end
end
```

### 5. Python Bridge Test Manager

```elixir
defmodule DSPex.Test.PythonBridgeManager do
  @moduledoc """
  Manages Python bridge lifecycle for tests with proper initialization.
  """
  
  def setup_bridge(opts) do
    mode = Keyword.get(opts, :mode, :test)
    
    case mode do
      :mock ->
        setup_mock_bridge()
        
      :isolated ->
        setup_isolated_bridge(opts)
        
      :shared ->
        setup_shared_bridge(opts)
    end
  end
  
  defp setup_isolated_bridge(opts) do
    # Each test gets its own Python process
    config = %{
      mode: :pool_worker,
      session_namespace: opts[:namespace],
      lm_config: DSPex.Test.LMConfig.setup_test_lm(opts[:lm_mode] || :mock),
      cleanup_on_exit: true
    }
    
    # Start bridge with test configuration
    {:ok, bridge} = DSPex.PythonBridge.start_link(config)
    
    # Initialize DSPy with test LM
    :ok = initialize_test_dspy(bridge, config.lm_config)
    
    bridge
  end
  
  defp initialize_test_dspy(bridge, lm_config) do
    # Send initialization command to Python bridge
    DSPex.PythonBridge.execute(bridge, :init_test_lm, lm_config)
  end
end
```

### 6. Test Fixtures and Factories

```elixir
defmodule DSPex.Test.Fixtures do
  @moduledoc """
  Provides test fixtures and factories for consistent test data.
  """
  
  use ExMachina
  
  def program_factory do
    %{
      id: sequence(:program_id, &"test_program_#{&1}_#{:rand.uniform(10000)}"),
      signature: signature_factory(),
      metadata: %{
        test: true,
        created_at: DateTime.utc_now()
      }
    }
  end
  
  def signature_factory do
    %{
      inputs: [
        %{name: "input", type: "string", description: "Test input"}
      ],
      outputs: [
        %{name: "output", type: "string", description: "Test output"}
      ]
    }
  end
  
  def session_factory do
    %{
      id: sequence(:session_id, &"test_session_#{&1}_#{System.unique_integer([:positive])}"),
      user_id: sequence(:user_id, &"test_user_#{&1}"),
      started_at: DateTime.utc_now()
    }
  end
end
```

### 7. Enhanced Test Helper

```elixir
# test/test_helper.exs
# Load test framework
Code.require_file("support/test_environment.ex", __DIR__)
Code.require_file("support/lm_config.ex", __DIR__)
Code.require_file("support/isolation.ex", __DIR__)
Code.require_file("support/resource_manager.ex", __DIR__)

# Start resource manager
{:ok, _} = DSPex.Test.ResourceManager.start_link([])

# Configure test environment based on TEST_MODE
test_mode = System.get_env("TEST_MODE", "unit") |> String.to_atom()
test_env = DSPex.Test.Environment.setup(test_mode)

# Configure application
Application.put_env(:dspex, :test_environment, test_env)
Application.put_env(:dspex, :python_bridge_enabled, test_env.python_enabled)
Application.put_env(:dspex, :pooling_enabled, test_env.pooling_enabled)

# Set up LM configuration
lm_config = DSPex.Test.LMConfig.setup_test_lm(test_env.lm_config)
Application.put_env(:dspex, :test_lm_config, lm_config)

# Configure ExUnit
ExUnit.configure(
  exclude: exclude_tags_for_mode(test_mode),
  timeout: timeout_for_mode(test_mode),
  max_failures: 1  # Stop on first failure in CI
)

# Start ExUnit
ExUnit.start()

# Cleanup hook
System.at_exit(fn _ ->
  DSPex.Test.ResourceManager.cleanup_all()
end)
```

### 8. Test Configuration Schema

```yaml
# config/test.exs
import Config

config :dspex, :test,
  # Resource limits
  max_python_processes: 4,
  max_pool_size: 2,
  process_timeout: 30_000,
  
  # LM Configuration
  lm_modes: %{
    unit: :mock,
    integration: :cached,
    e2e: :real
  },
  
  # Cleanup policies
  cleanup_policy: :aggressive,
  retain_on_failure: true,
  
  # Performance
  parallel: true,
  max_parallel_cases: System.schedulers_online()
```

### 9. CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Test Suite

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    env:
      TEST_MODE: unit
      MIX_ENV: test
    steps:
      - uses: actions/checkout@v2
      - name: Run unit tests
        run: mix test --only unit
        
  integration-tests:
    runs-on: ubuntu-latest
    env:
      TEST_MODE: integration
      MIX_ENV: test
      # Use cached LM responses
      LM_CACHE_DIR: test/fixtures/lm_responses
    steps:
      - uses: actions/checkout@v2
      - name: Cache LM responses
        uses: actions/cache@v2
        with:
          path: test/fixtures/lm_responses
          key: lm-responses-${{ hashFiles('test/**/*.exs') }}
      - name: Run integration tests
        run: mix test --only integration
        
  e2e-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    env:
      TEST_MODE: e2e
      MIX_ENV: test
      GEMINI_TEST_API_KEY: ${{ secrets.GEMINI_TEST_API_KEY }}
    steps:
      - uses: actions/checkout@v2
      - name: Run E2E tests
        run: mix test --only e2e --max-failures 5
```

## Implementation Strategy

### Phase 1: Foundation (Week 1-2)
1. Implement TestEnvironment module
2. Create ResourceManager for cleanup
3. Add LMConfig for mock/cached/real modes
4. Update test_helper.exs

### Phase 2: Isolation (Week 3-4)
1. Implement Isolation framework
2. Add namespace support to adapters
3. Create test factories
4. Update existing tests to use isolation

### Phase 3: Python Bridge (Week 5-6)
1. Implement PythonBridgeManager
2. Add DSPy initialization in tests
3. Create LM response caching system
4. Fix remaining integration tests

### Phase 4: CI/CD (Week 7-8)
1. Set up test matrix in CI
2. Add performance benchmarks
3. Implement cost monitoring for LM usage
4. Create test reporting dashboard

## Benefits

1. **Reliability**: Deterministic tests with proper isolation
2. **Performance**: Parallel execution with resource pooling
3. **Cost Control**: LM API usage monitoring and caching
4. **Debugging**: Better error messages and test artifacts
5. **Scalability**: Easy to add new test scenarios
6. **Maintainability**: Clear separation of concerns

## Success Metrics

- Test execution time < 5 minutes
- Zero flaky tests
- LM API costs < $10/month
- 100% test coverage for critical paths
- Resource leaks: 0
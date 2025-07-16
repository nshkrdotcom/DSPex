# Testing Strategy

## Overview

This document outlines the comprehensive testing strategy for the generalized Python adapter architecture, ensuring reliability, performance, and compatibility across multiple ML frameworks.

## Testing Principles

1. **Maintain Existing Coverage**: All current tests must continue to pass
2. **Framework Isolation**: Test each framework independently
3. **Integration Testing**: Verify cross-framework interactions
4. **Performance Validation**: Ensure no regression
5. **Chaos Engineering**: Test failure scenarios

## Test Architecture

### Layer Structure

Based on DSPex's existing 3-layer test architecture:

```
Layer 1: Mock Adapter Tests (Fast, No Python)
Layer 2: Bridge Mock Tests (Medium, Mock Python)
Layer 3: Full Integration Tests (Slow, Real Python)
```

### Extended for Multi-Framework

```
Layer 1: Framework-agnostic adapter tests
Layer 2: Framework-specific mock tests
Layer 3: Real framework integration tests
Layer 4: Cross-framework integration tests (New)
```

## Test Categories

### 1. Unit Tests

#### Base Bridge Tests (Python)

```python
# test/python/test_base_bridge.py
import unittest
from unittest.mock import Mock, patch
from base_bridge import BaseBridge

class TestBaseBridge(unittest.TestCase):
    
    def setUp(self):
        # Create a concrete implementation for testing
        class TestBridge(BaseBridge):
            def _initialize_framework(self):
                self.test_initialized = True
                
            def _register_handlers(self):
                return {
                    'ping': self.ping,
                    'test_command': self.test_handler
                }
                
            def get_framework_info(self):
                return {'name': 'test', 'version': '1.0'}
                
            def test_handler(self, args):
                return {'result': 'test'}
        
        self.bridge = TestBridge()
    
    def test_initialization(self):
        self.assertTrue(hasattr(self.bridge, 'stats'))
        self.assertTrue(self.bridge.test_initialized)
        self.assertIn('ping', self.bridge._handlers)
    
    def test_request_handling(self):
        request = {
            'id': 123,
            'command': 'test_command',
            'args': {}
        }
        
        response = self.bridge._handle_request(request)
        
        self.assertTrue(response['success'])
        self.assertEqual(response['id'], 123)
        self.assertEqual(response['result']['result'], 'test')
    
    def test_error_handling(self):
        request = {
            'id': 456,
            'command': 'unknown_command',
            'args': {}
        }
        
        response = self.bridge._handle_request(request)
        
        self.assertFalse(response['success'])
        self.assertIn('error', response)
        self.assertEqual(response['id'], 456)
    
    def test_stats_tracking(self):
        initial_count = self.bridge.stats['requests_processed']
        
        self.bridge._handle_request({
            'id': 1,
            'command': 'ping',
            'args': {}
        })
        
        self.assertEqual(
            self.bridge.stats['requests_processed'],
            initial_count + 1
        )
    
    @patch('sys.stdin.buffer')
    @patch('sys.stdout.buffer')
    def test_protocol_handling(self, mock_stdout, mock_stdin):
        # Test message framing
        message = b'{"id":1,"command":"ping","args":{}}'
        length_header = struct.pack('>I', len(message))
        
        mock_stdin.read.side_effect = [length_header, message, b'']
        
        # Run one iteration
        try:
            self.bridge.run()
        except SystemExit:
            pass
        
        # Verify response was sent
        mock_stdout.write.assert_called()
```

#### Base Adapter Tests (Elixir)

```elixir
defmodule DSPex.Adapters.BaseMLAdapterTest do
  use ExUnit.Case
  
  defmodule TestAdapter do
    use DSPex.Adapters.BaseMLAdapter
    
    @impl true
    def get_framework_info do
      {:ok, %{name: "test", version: "1.0"}}
    end
    
    @impl true
    def validate_environment do
      :ok
    end
    
    @impl true
    def initialize(_options) do
      {:ok, %{initialized: true}}
    end
  end
  
  setup do
    # Mock configuration
    Application.put_env(:dspex, TestAdapter, %{
      bridge_module: MockBridge,
      python_script: "test_bridge.py"
    })
    
    :ok
  end
  
  describe "base functionality" do
    test "provides default resource operations" do
      assert function_exported?(TestAdapter, :create_resource, 3)
      assert function_exported?(TestAdapter, :execute_resource, 3)
      assert function_exported?(TestAdapter, :list_resources, 2)
      assert function_exported?(TestAdapter, :delete_resource, 2)
    end
    
    test "delegates to bridge module" do
      expect(MockBridge, :execute_anonymous, fn "create_model", _, _ ->
        {:ok, %{"resource_id" => "123"}}
      end)
      
      result = TestAdapter.create_resource("model", %{type: "test"})
      assert {:ok, %{"resource_id" => "123"}} = result
    end
    
    test "supports session-based execution" do
      expect(MockBridge, :execute_in_session, fn "session_1", "predict", _, _ ->
        {:ok, %{"result" => "prediction"}}
      end)
      
      result = TestAdapter.execute_resource(
        "resource_1",
        %{input: "test"},
        session_id: "session_1"
      )
      
      assert {:ok, _} = result
    end
  end
end
```

### 2. Integration Tests

#### Framework-Specific Tests

```elixir
defmodule DSPex.Adapters.DSPyAdapterIntegrationTest do
  use DSPex.Test.UnifiedTestFoundation, isolation: :pool_testing
  
  @moduletag :integration
  @moduletag :layer_3
  
  setup do
    # Ensure Python bridge is available
    ensure_python_bridge_started()
    
    # Configure DSPy
    {:ok, _} = DSPex.Adapters.DSPyAdapter.configure_lm(%{
      type: "gemini",
      model: "gemini-1.5-flash",
      api_key: System.get_env("GEMINI_API_KEY")
    })
    
    :ok
  end
  
  describe "DSPy operations" do
    test "create and execute program" do
      signature = %{
        name: "TestSignature",
        inputs: %{
          question: %{description: "A question"}
        },
        outputs: %{
          answer: %{description: "The answer"}
        }
      }
      
      {:ok, result} = DSPex.Adapters.DSPyAdapter.predict(
        signature,
        %{question: "What is 2+2?"}
      )
      
      assert result["answer"] =~ ~r/4|four/i
    end
    
    test "handles concurrent operations" do
      tasks = for i <- 1..10 do
        Task.async(fn ->
          DSPex.Adapters.DSPyAdapter.predict(
            simple_signature(),
            %{input: "Test #{i}"}
          )
        end)
      end
      
      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
    end
  end
end
```

#### Cross-Framework Tests

```elixir
defmodule DSPex.MLBridge.CrossFrameworkTest do
  use DSPex.Test.UnifiedTestFoundation, isolation: :pool_testing
  
  @moduletag :integration
  @moduletag :cross_framework
  @moduletag :layer_4
  
  setup do
    # Start multiple frameworks
    for framework <- [:dspy, :langchain] do
      {:ok, _} = DSPex.MLBridge.ensure_started(framework)
    end
    
    :ok
  end
  
  test "multiple frameworks can coexist" do
    # Use DSPy
    {:ok, dspy} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, dspy_result} = dspy.predict(
      test_signature(),
      %{input: "DSPy test"}
    )
    
    # Use LangChain
    {:ok, langchain} = DSPex.MLBridge.get_adapter(:langchain)
    {:ok, langchain_result} = langchain.ask("LangChain test")
    
    assert dspy_result
    assert langchain_result
  end
  
  test "framework switching performance" do
    results = measure_performance fn ->
      for _ <- 1..100 do
        framework = Enum.random([:dspy, :langchain])
        {:ok, adapter} = DSPex.MLBridge.get_adapter(framework)
        adapter.get_stats()
      end
    end
    
    assert results.avg_time < 1_000  # < 1ms per switch
  end
  
  test "resource isolation between frameworks" do
    # Create resource in DSPy
    {:ok, dspy} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, %{"program_id" => program_id}} = dspy.create_program(
      test_signature(),
      :predict
    )
    
    # Verify LangChain can't access it
    {:ok, langchain} = DSPex.MLBridge.get_adapter(:langchain)
    {:error, _} = langchain.execute_resource(program_id, %{})
  end
end
```

### 3. Performance Tests

#### Baseline Comparison

```elixir
defmodule DSPex.MLBridge.PerformanceTest do
  use DSPex.Test.PoolPerformanceFramework
  
  @moduletag :performance
  
  performance_test "adapter lookup overhead" do
    set_baseline fn ->
      # Direct adapter access (current)
      DSPex.Adapters.PythonPoolV2.get_stats()
    end
    
    measure fn ->
      # New unified interface
      {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
      adapter.get_stats()
    end
    
    assert_performance_within 5  # Max 5% overhead
  end
  
  performance_test "multi-framework memory usage" do
    initial_memory = :erlang.memory(:total)
    
    # Start multiple frameworks
    for framework <- [:dspy, :langchain, :custom] do
      {:ok, _} = DSPex.MLBridge.ensure_started(framework)
    end
    
    # Perform operations
    for _ <- 1..100 do
      framework = Enum.random([:dspy, :langchain, :custom])
      {:ok, adapter} = DSPex.MLBridge.get_adapter(framework)
      adapter.get_stats()
    end
    
    final_memory = :erlang.memory(:total)
    memory_increase = final_memory - initial_memory
    
    # Assert reasonable memory usage (< 200MB for 3 frameworks)
    assert memory_increase < 200 * 1024 * 1024
  end
  
  performance_test "concurrent framework operations" do
    frameworks = [:dspy, :langchain, :custom]
    
    results = benchmark_concurrent(
      concurrency: [1, 10, 50, 100],
      duration: 10_000,
      operation: fn ->
        framework = Enum.random(frameworks)
        {:ok, adapter} = DSPex.MLBridge.get_adapter(framework)
        adapter.get_stats()
      end
    )
    
    assert_linear_scaling(results, tolerance: 0.2)
  end
end
```

### 4. Chaos Engineering Tests

#### Framework Failure Scenarios

```elixir
defmodule DSPex.MLBridge.ChaosTest do
  use DSPex.Test.PoolChaosHelpers
  
  @moduletag :chaos
  
  chaos_test "framework crash recovery" do
    {:ok, dspy} = DSPex.MLBridge.get_adapter(:dspy)
    
    # Simulate Python process crash
    simulate_worker_crash(:dspy)
    
    # Should recover and work
    assert eventually(fn ->
      case dspy.get_stats() do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end
  
  chaos_test "memory exhaustion handling" do
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:custom)
    
    # Create many large resources
    resources = for i <- 1..100 do
      adapter.create_resource("model", %{
        size: "large",
        data: String.duplicate("x", 10_000_000)  # 10MB
      })
    end
    
    # Should handle gracefully
    assert Enum.count(resources, fn {:ok, _} -> true; _ -> false end) > 0
    assert Process.alive?(adapter.pool_pid)
  end
  
  chaos_test "rapid framework switching" do
    frameworks = [:dspy, :langchain, :custom]
    
    # Rapidly switch frameworks
    tasks = for _ <- 1..1000 do
      Task.async(fn ->
        framework = Enum.random(frameworks)
        {:ok, adapter} = DSPex.MLBridge.get_adapter(framework)
        adapter.get_stats()
      end)
    end
    
    results = Task.await_many(tasks, 30_000)
    success_rate = Enum.count(results, fn {:ok, _} -> true; _ -> false end) / 1000
    
    assert success_rate > 0.95  # 95% success rate
  end
end
```

### 5. Migration Tests

#### Compatibility Tests

```elixir
defmodule DSPex.MLBridge.MigrationTest do
  use ExUnit.Case
  
  @moduletag :migration
  
  test "old and new interfaces produce same results" do
    signature = test_signature()
    inputs = %{question: "What is Elixir?"}
    
    # Old interface
    {:ok, old_result} = DSPex.Adapters.PythonPoolV2.create_program(signature)
    {:ok, old_output} = DSPex.Adapters.PythonPoolV2.execute_program(
      old_result["program_id"],
      inputs
    )
    
    # New interface
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, new_result} = adapter.create_program(signature)
    {:ok, new_output} = adapter.execute_program(
      new_result["program_id"],
      inputs
    )
    
    # Results should be equivalent (not necessarily identical due to LLM)
    assert old_output["answer"]
    assert new_output["answer"]
  end
  
  test "mixed usage works correctly" do
    # Create with old interface
    {:ok, %{"program_id" => program_id}} = 
      DSPex.Adapters.PythonPoolV2.create_program(test_signature())
    
    # Execute with new interface
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, result} = adapter.execute_program(program_id, %{input: "test"})
    
    assert result
  end
end
```

## Test Infrastructure

### 1. Framework Test Helpers

```elixir
defmodule DSPex.Test.FrameworkHelpers do
  @moduledoc """
  Helpers for testing multiple ML frameworks
  """
  
  def with_framework(framework, fun) do
    {:ok, adapter} = DSPex.MLBridge.ensure_started(framework)
    
    try do
      fun.(adapter)
    after
      cleanup_framework(framework)
    end
  end
  
  def with_frameworks(frameworks, fun) do
    adapters = for framework <- frameworks do
      {:ok, adapter} = DSPex.MLBridge.ensure_started(framework)
      {framework, adapter}
    end
    
    try do
      fun.(adapters)
    after
      Enum.each(frameworks, &cleanup_framework/1)
    end
  end
  
  def assert_framework_compatible(framework, operation) do
    with_framework(framework, fn adapter ->
      assert {:ok, _} = operation.(adapter)
    end)
  end
  
  defp cleanup_framework(framework) do
    case DSPex.MLBridge.get_adapter(framework) do
      {:ok, adapter} -> adapter.cleanup()
      _ -> :ok
    end
  end
end
```

### 2. Mock Framework Implementation

```python
# test/python/mock_ml_bridge.py
from base_bridge import BaseBridge
import time
import random

class MockMLBridge(BaseBridge):
    """Mock ML framework for testing"""
    
    def _initialize_framework(self):
        self.resources = {}
        self.operations = []
        self.failure_rate = 0.0
        
    def _register_handlers(self):
        return {
            'ping': self.ping,
            'get_stats': self.get_stats,
            'get_info': self.get_info,
            'cleanup': self.cleanup,
            'create_resource': self.create_resource,
            'execute_resource': self.execute_resource,
            'set_failure_rate': self.set_failure_rate,
            'get_operations': self.get_operations
        }
    
    def get_framework_info(self):
        return {
            'name': 'mock',
            'version': '1.0.0',
            'capabilities': ['testing', 'simulation']
        }
    
    def create_resource(self, args):
        if random.random() < self.failure_rate:
            raise RuntimeError("Simulated failure")
            
        resource_id = str(uuid.uuid4())
        self.resources[resource_id] = {
            'type': args.get('type'),
            'config': args.get('config'),
            'created_at': time.time()
        }
        
        self.operations.append({
            'operation': 'create_resource',
            'resource_id': resource_id,
            'timestamp': time.time()
        })
        
        return {'resource_id': resource_id}
    
    def execute_resource(self, args):
        if random.random() < self.failure_rate:
            raise RuntimeError("Simulated failure")
            
        resource_id = args['resource_id']
        if resource_id not in self.resources:
            raise ValueError(f"Resource not found: {resource_id}")
            
        # Simulate processing time
        time.sleep(random.uniform(0.01, 0.05))
        
        self.operations.append({
            'operation': 'execute_resource',
            'resource_id': resource_id,
            'timestamp': time.time()
        })
        
        return {
            'result': f"Mock result for {resource_id}",
            'execution_time': random.uniform(0.01, 0.05)
        }
    
    def set_failure_rate(self, args):
        self.failure_rate = args.get('rate', 0.0)
        return {'failure_rate': self.failure_rate}
    
    def get_operations(self, args):
        return {'operations': self.operations}
```

### 3. Property-Based Testing

```elixir
defmodule DSPex.MLBridge.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  @moduletag :property
  
  property "framework adapters maintain consistent interface" do
    check all framework <- member_of([:dspy, :langchain, :mock]),
              resource_type <- string(:alphanumeric, min_length: 1),
              config <- map_of(atom(), term()) do
      
      {:ok, adapter} = DSPex.MLBridge.get_adapter(framework)
      
      # All adapters should support basic operations
      assert function_exported?(adapter.__info__(:module), :create_resource, 3)
      assert function_exported?(adapter.__info__(:module), :execute_resource, 3)
      
      # Operations should return consistent structure
      case adapter.create_resource(resource_type, config) do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, "resource_id") or Map.has_key?(result, :resource_id)
          
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)
      end
    end
  end
  
  property "concurrent operations don't corrupt state" do
    check all operations <- list_of(
                tuple({
                  member_of([:create, :execute, :delete]),
                  string(:alphanumeric, min_length: 1)
                }),
                min_length: 10,
                max_length: 100
              ) do
      
      {:ok, adapter} = DSPex.MLBridge.get_adapter(:mock)
      
      # Execute operations concurrently
      tasks = Enum.map(operations, fn {op, id} ->
        Task.async(fn ->
          case op do
            :create -> adapter.create_resource("test", %{id: id})
            :execute -> adapter.execute_resource(id, %{})
            :delete -> adapter.delete_resource(id)
          end
        end)
      end)
      
      results = Task.await_many(tasks, 5000)
      
      # No crashes
      assert length(results) == length(operations)
      
      # State should be consistent
      {:ok, stats} = adapter.get_stats()
      assert is_map(stats)
    end
  end
end
```

## Continuous Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/ml-bridge-tests.yml
name: ML Bridge Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'
          
      - name: Install Python dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-test.txt
          
      - name: Run Python unit tests
        run: |
          python -m pytest test/python/test_base_bridge.py -v
          
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
          
      - name: Run Elixir unit tests
        run: |
          mix deps.get
          mix test --only unit
  
  integration-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        framework: [dspy, langchain, mock]
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up test environment
        run: |
          docker-compose -f docker-compose.test.yml up -d
          
      - name: Run framework tests
        env:
          TEST_FRAMEWORK: ${{ matrix.framework }}
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          mix test --only integration --only $TEST_FRAMEWORK
  
  performance-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run performance benchmarks
        run: |
          mix run bench/ml_bridge_bench.exs
          
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: performance-results
          path: bench/results/
          
      - name: Check for regression
        run: |
          mix performance.check --baseline main
```

### Test Environments

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  test-dspy:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - ML_FRAMEWORK=dspy
      - PYTHONPATH=/app
    volumes:
      - ./priv/python:/app/python
      
  test-langchain:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - ML_FRAMEWORK=langchain
      - PYTHONPATH=/app
    volumes:
      - ./priv/python:/app/python
      
  test-mock:
    build:
      context: .
      dockerfile: Dockerfile.test
    environment:
      - ML_FRAMEWORK=mock
      - PYTHONPATH=/app
    volumes:
      - ./test/python:/app/python
```

## Test Data Management

### Framework-Specific Fixtures

```elixir
defmodule DSPex.Test.Fixtures do
  def framework_fixtures do
    %{
      dspy: %{
        signature: %{
          name: "QA",
          inputs: %{question: %{description: "Question to answer"}},
          outputs: %{answer: %{description: "Answer"}}
        },
        test_input: %{question: "What is DSPy?"}
      },
      
      langchain: %{
        chain_config: %{
          template: "Answer: {input}",
          input_variables: ["input"]
        },
        test_input: %{input: "What is LangChain?"}
      },
      
      mock: %{
        resource_config: %{type: "test_model", size: "small"},
        test_input: %{data: "test data"}
      }
    }
  end
  
  def get_fixture(framework, key) do
    framework_fixtures()
    |> get_in([framework, key])
  end
end
```

## Test Metrics and Reporting

### Coverage Requirements

```elixir
# mix.exs
def project do
  [
    # ...
    test_coverage: [
      summary: [
        threshold: 90
      ],
      ignore_modules: [
        ~r/Test\./
      ]
    ]
  ]
end
```

### Test Dashboard

```elixir
defmodule DSPex.Test.Dashboard do
  @moduledoc """
  Generates test metrics dashboard
  """
  
  def generate_report do
    %{
      frameworks_tested: count_tested_frameworks(),
      test_coverage: calculate_coverage(),
      performance_metrics: collect_performance_metrics(),
      failure_analysis: analyze_failures(),
      cross_framework_compatibility: compatibility_matrix()
    }
    |> generate_html_report()
    |> write_to_file("test_results/dashboard.html")
  end
  
  defp compatibility_matrix do
    frameworks = [:dspy, :langchain, :mock]
    
    for f1 <- frameworks, f2 <- frameworks, f1 != f2 do
      {f1, f2, test_cross_compatibility(f1, f2)}
    end
    |> Enum.into(%{})
  end
end
```

## Conclusion

This comprehensive testing strategy ensures:

1. **Quality**: High coverage across all components
2. **Reliability**: Chaos testing for production readiness
3. **Performance**: No regression from current implementation
4. **Compatibility**: Smooth migration path
5. **Maintainability**: Clear test organization and documentation

The multi-layered approach allows fast unit tests during development while providing thorough integration testing before deployment.
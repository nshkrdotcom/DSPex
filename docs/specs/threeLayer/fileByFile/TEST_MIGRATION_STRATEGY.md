# Test Migration Strategy for Cognitive Architecture

## Overview

This document outlines the comprehensive strategy for migrating tests from the current architecture to the cognitive-ready SnakepitGrpcBridge structure, including new tests for cognitive features.

## Test Migration Scope

### Tests to Migrate from Snakepit

**Deleted in reorg-bridge** (need recreation in SnakepitGrpcBridge):
- `test/integration/grpc_bridge_integration_test.exs`
- `test/snakepit/bridge/property_test.exs`
- `test/snakepit/bridge/python_integration_test.exs`
- `test/snakepit/bridge/serialization_test.exs`
- `test/snakepit/bridge/session_integration_test.exs`
- `test/snakepit/bridge/session_store_variables_test.exs`
- `test/snakepit/bridge/session_test.exs`
- `test/snakepit/bridge/variables/types_test.exs`
- `test/snakepit/bridge/variables/variable_test.exs`
- `test/snakepit/grpc/bridge_server_test.exs`
- `test/snakepit/python_test.exs`
- `test/unit/bridge/session_store_test.exs`
- `test/unit/grpc/grpc_worker_test.exs`

### Tests to Update in DSPex

**Current Tests**:
- `test/dspex/variables_test.exs`
- `test/dspex/context_call_test.exs`
- `test/dspex/variables_integration_test.exs`

## Test Organization in SnakepitGrpcBridge

```
snakepit_grpc_bridge/test/
├── unit/
│   ├── bridge/
│   │   ├── session_store_test.exs
│   │   ├── variables_test.exs
│   │   ├── variables/
│   │   │   ├── types_test.exs
│   │   │   └── type_specific_tests/
│   │   ├── tool_registry_test.exs
│   │   └── serialization_test.exs
│   ├── cognitive/
│   │   ├── worker_test.exs
│   │   ├── scheduler_test.exs
│   │   ├── evolution_test.exs
│   │   └── collaboration_test.exs
│   ├── schema/
│   │   ├── dspy_test.exs
│   │   └── cache_test.exs
│   ├── codegen/
│   │   └── dspy_test.exs
│   └── grpc/
│       ├── server_test.exs
│       └── client_test.exs
├── integration/
│   ├── dspy_integration_test.exs
│   ├── python_bridge_test.exs
│   ├── session_lifecycle_test.exs
│   ├── tool_bridge_test.exs
│   └── end_to_end_test.exs
├── cognitive_readiness/
│   ├── telemetry_collection_test.exs
│   ├── performance_monitoring_test.exs
│   ├── learning_infrastructure_test.exs
│   └── evolution_readiness_test.exs
├── performance/
│   ├── benchmark_test.exs
│   ├── load_test.exs
│   └── memory_usage_test.exs
└── support/
    ├── test_helpers.ex
    ├── mock_python_bridge.ex
    └── telemetry_helpers.ex
```

## Migration Strategy by Test Type

### 1. Unit Tests Migration

#### SessionStore Tests
**Original**: `test/unit/bridge/session_store_test.exs`
**Target**: `snakepit_grpc_bridge/test/unit/bridge/session_store_test.exs`

**Enhancements**:
```elixir
# Add telemetry tests
describe "telemetry collection" do
  test "emits events on session creation" do
    :telemetry.attach("test", [:snakepit_grpc_bridge, :session, :created], &capture_telemetry/4, %{})
    
    {:ok, _session} = SessionStore.create_session("test_session")
    
    assert_receive {:telemetry_event, measurements, metadata}
    assert measurements.duration > 0
    assert metadata.session_id == "test_session"
  end
end

# Add performance tests
describe "performance characteristics" do
  test "session creation under 1ms" do
    {time, {:ok, _}} = :timer.tc(fn ->
      SessionStore.create_session("perf_test")
    end)
    
    assert time < 1000 # microseconds
  end
end
```

#### Variables Tests
**Original**: `test/snakepit/bridge/variables/variable_test.exs`
**Target**: `snakepit_grpc_bridge/test/unit/bridge/variables_test.exs`

**Enhancements**:
```elixir
# Add type inference tests
describe "cognitive type inference" do
  test "tracks type usage patterns" do
    # Set various types
    Variables.set("session1", "count", 42)
    Variables.set("session1", "name", "test")
    Variables.set("session1", "ratio", 0.95)
    
    # Check type usage telemetry
    stats = Variables.get_type_usage_stats()
    assert stats.integer.count > 0
    assert stats.string.count > 0
    assert stats.float.count > 0
  end
end
```

### 2. Integration Tests Migration

#### gRPC Bridge Integration
**Original**: `test/integration/grpc_bridge_integration_test.exs`
**Target**: `snakepit_grpc_bridge/test/integration/dspy_integration_test.exs`

**New Structure**:
```elixir
defmodule SnakepitGrpcBridge.Integration.DSPyTest do
  use ExUnit.Case
  
  setup_all do
    # Start bridge with cognitive features
    {:ok, _} = SnakepitGrpcBridge.start_link(
      cognitive_features: %{
        telemetry_collection: true,
        performance_monitoring: true
      }
    )
    
    :ok
  end
  
  describe "complete DSPy workflow" do
    test "schema discovery with caching" do
      # First call - uncached
      {time1, {:ok, schema1}} = :timer.tc(fn ->
        SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
      end)
      
      # Second call - cached
      {time2, {:ok, schema2}} = :timer.tc(fn ->
        SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
      end)
      
      assert schema1 == schema2
      assert time2 < time1 / 2 # Cached should be much faster
    end
    
    test "instance creation and execution" do
      session_id = "test_#{:rand.uniform(1000)}"
      
      # Create predictor instance
      {:ok, result} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "dspy.Predict",
        "method" => "__init__",
        "args" => ["question -> answer"],
        "kwargs" => %{}
      })
      
      assert result["success"] == true
      instance_id = result["instance_id"]
      
      # Execute prediction
      {:ok, prediction} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "stored.#{instance_id}",
        "method" => "__call__",
        "args" => [],
        "kwargs" => %{"question" => "What is cognitive architecture?"}
      })
      
      assert prediction["success"] == true
      assert Map.has_key?(prediction["result"], "answer")
    end
  end
end
```

### 3. New Cognitive Readiness Tests

#### Telemetry Collection Test
**New Test**: `snakepit_grpc_bridge/test/cognitive_readiness/telemetry_collection_test.exs`

```elixir
defmodule SnakepitGrpcBridge.CognitiveReadiness.TelemetryCollectionTest do
  use ExUnit.Case
  
  @telemetry_events [
    [:snakepit_grpc_bridge, :worker, :execution],
    [:snakepit_grpc_bridge, :schema, :discovery],
    [:snakepit_grpc_bridge, :codegen, :wrapper_generated],
    [:snakepit_grpc_bridge, :evolution, :implementation_selected]
  ]
  
  test "all cognitive modules emit telemetry" do
    captured_events = capture_telemetry_events(@telemetry_events)
    
    # Execute operations that trigger each module
    session_id = "telemetry_test"
    
    # Schema operation
    {:ok, _} = SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
    
    # Worker operation
    {:ok, _} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
      "class_path" => "dspy.Predict",
      "method" => "__init__",
      "args" => ["test"],
      "kwargs" => %{}
    })
    
    # Wait for async telemetry
    Process.sleep(100)
    
    events = get_captured_events(captured_events)
    assert length(events) >= 2
    
    # Verify event structure
    Enum.each(events, fn event ->
      assert Map.has_key?(event, :measurements)
      assert Map.has_key?(event, :metadata)
      assert event.measurements.duration > 0
    end)
  end
  
  test "telemetry data quality for ML training" do
    # Execute diverse operations
    operations = [
      {:schema_discovery, fn -> 
        SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
      end},
      {:simple_call, fn ->
        SnakepitGrpcBridge.execute_dspy("session1", "call_dspy_bridge", %{
          "class_path" => "dspy.Predict",
          "method" => "__init__",
          "args" => ["simple"],
          "kwargs" => %{}
        })
      end},
      {:complex_call, fn ->
        SnakepitGrpcBridge.execute_dspy("session2", "call_dspy_bridge", %{
          "class_path" => "dspy.ChainOfThought",
          "method" => "__init__",
          "args" => ["complex -> reasoning, answer"],
          "kwargs" => %{"max_hops" => 3}
        })
      end}
    ]
    
    results = Enum.map(operations, fn {name, op} ->
      {time, result} = :timer.tc(op)
      %{
        operation: name,
        success: match?({:ok, _}, result),
        duration_us: time
      }
    end)
    
    # Verify diversity in data
    durations = Enum.map(results, & &1.duration_us)
    assert Enum.max(durations) > Enum.min(durations)
    assert Enum.all?(results, & &1.success)
  end
end
```

#### Performance Monitoring Test
**New Test**: `snakepit_grpc_bridge/test/cognitive_readiness/performance_monitoring_test.exs`

```elixir
defmodule SnakepitGrpcBridge.CognitiveReadiness.PerformanceMonitoringTest do
  use ExUnit.Case
  
  test "worker performance tracking" do
    # Get initial performance summary
    initial_summary = SnakepitGrpcBridge.Cognitive.Worker.get_performance_summary()
    
    # Execute operations
    for i <- 1..10 do
      session_id = "perf_test_#{i}"
      SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "dspy.Predict",
        "method" => "__init__",
        "args" => ["test"],
        "kwargs" => %{}
      })
    end
    
    # Get updated summary
    updated_summary = SnakepitGrpcBridge.Cognitive.Worker.get_performance_summary()
    
    assert updated_summary.total_tasks_executed > initial_summary.total_tasks_executed
    assert updated_summary.average_execution_time > 0
    assert updated_summary.success_rate > 0.9
  end
  
  test "evolution implementation selection tracking" do
    insights = SnakepitGrpcBridge.Cognitive.Evolution.get_selection_insights()
    
    assert Map.has_key?(insights, :selection_history)
    assert Map.has_key?(insights, :performance_data)
    assert Map.has_key?(insights, :optimization_opportunities)
  end
end
```

### 4. Performance Tests

#### Benchmark Test
**New Test**: `snakepit_grpc_bridge/test/performance/benchmark_test.exs`

```elixir
defmodule SnakepitGrpcBridge.Performance.BenchmarkTest do
  use ExUnit.Case
  
  @tag :performance
  test "DSPy call latency within targets" do
    session_id = "benchmark_test"
    
    # Warm up
    for _ <- 1..5 do
      execute_dspy_call(session_id)
    end
    
    # Measure
    times = for _ <- 1..100 do
      {time, {:ok, _}} = :timer.tc(fn ->
        execute_dspy_call(session_id)
      end)
      time
    end
    
    avg_time = Enum.sum(times) / length(times)
    p95_time = Enum.at(Enum.sort(times), round(length(times) * 0.95))
    
    # Performance targets
    assert avg_time < 100_000  # 100ms average
    assert p95_time < 200_000  # 200ms 95th percentile
    
    IO.puts("Average latency: #{avg_time / 1000}ms")
    IO.puts("P95 latency: #{p95_time / 1000}ms")
  end
  
  defp execute_dspy_call(session_id) do
    SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
      "class_path" => "dspy.Predict",
      "method" => "__init__",
      "args" => ["question -> answer"],
      "kwargs" => %{}
    })
  end
end
```

## DSPex Test Updates

### Update Variables Test
```elixir
# test/dspex/variables_test.exs
# Change from:
alias Snakepit.Bridge.SessionStore

# To:
alias SnakepitGrpcBridge

# Update all SessionStore calls to use SnakepitGrpcBridge APIs
```

### Update Context Test
```elixir
# test/dspex/context_call_test.exs
# Update to use SnakepitGrpcBridge for session management
```

## Test Helpers and Support

### Telemetry Test Helpers
```elixir
defmodule SnakepitGrpcBridge.Test.TelemetryHelpers do
  def capture_telemetry_events(event_names) do
    test_pid = self()
    
    Enum.each(event_names, fn event_name ->
      :telemetry.attach(
        "test_#{:rand.uniform(10000)}",
        event_name,
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, %{
            measurements: measurements,
            metadata: metadata,
            timestamp: DateTime.utc_now()
          }})
        end,
        nil
      )
    end)
  end
  
  def assert_telemetry_received(timeout \\ 1000) do
    assert_receive {:telemetry_event, event}, timeout
    event
  end
end
```

### Mock Python Bridge
```elixir
defmodule SnakepitGrpcBridge.Test.MockPythonBridge do
  def start_link(_opts) do
    {:ok, spawn(fn -> :timer.sleep(:infinity) end)}
  end
  
  def execute(_pid, "discover_dspy_schema", %{"module_path" => "dspy"}) do
    {:ok, %{
      "success" => true,
      "schema" => %{
        "classes" => %{
          "Predict" => %{"methods" => ["__init__", "__call__"]},
          "ChainOfThought" => %{"methods" => ["__init__", "__call__"]}
        }
      }
    }}
  end
  
  # Add more mock responses as needed
end
```

## Test Execution Strategy

### Phase 1: Core Unit Tests
1. Migrate SessionStore tests
2. Migrate Variables tests
3. Migrate Tool Registry tests
4. Add cognitive module unit tests

### Phase 2: Integration Tests
1. Migrate Python bridge tests
2. Migrate gRPC integration tests
3. Add end-to-end workflow tests

### Phase 3: Cognitive Readiness Tests
1. Add telemetry collection tests
2. Add performance monitoring tests
3. Add learning infrastructure tests

### Phase 4: Performance Tests
1. Add benchmark tests
2. Add load tests
3. Add memory usage tests

### Phase 5: DSPex Updates
1. Update existing DSPex tests
2. Add integration tests with new bridge
3. Verify backward compatibility

## CI/CD Configuration

```yaml
# .github/workflows/test.yml
name: Cognitive Architecture Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        test-suite: [unit, integration, cognitive, performance]
    
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run tests
        run: mix test --only ${{ matrix.test-suite }}
```

## Success Metrics

1. **Test Coverage**: > 95% for all modules
2. **Performance**: No regression from current implementation
3. **Cognitive Readiness**: 100% telemetry coverage
4. **Integration**: All DSPex tests pass with new bridge
5. **Documentation**: All tests documented with examples
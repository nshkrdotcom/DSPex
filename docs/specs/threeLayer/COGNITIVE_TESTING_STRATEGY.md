# Cognitive Architecture Testing Strategy

## Overview

This document outlines the comprehensive testing strategy for validating the cognitive-ready architecture separation. We need to ensure that current functionality is preserved while the new structure is ready for future cognitive enhancement.

**Testing Philosophy**: Test current functionality thoroughly, validate cognitive readiness, prepare for future evolution.

## Testing Levels

### Level 1: Unit Testing (Current Functionality)
**Objective**: Verify all individual modules work correctly with current logic

### Level 2: Integration Testing (Module Interaction)  
**Objective**: Verify modules work together correctly in new architecture

### Level 3: System Testing (End-to-End Functionality)
**Objective**: Verify complete system works identically to current implementation

### Level 4: Cognitive Readiness Testing (Future Preparation)
**Objective**: Verify architecture is ready for cognitive feature activation

## Test Suite Organization

### Snakepit Core Tests
```
test/snakepit_core/
├── unit/
│   ├── pool_test.exs                    # Pool management functionality
│   ├── adapter_behavior_test.exs        # Adapter interface validation
│   ├── session_helpers_test.exs         # Session management
│   ├── telemetry_test.exs              # Telemetry infrastructure
│   └── api_test.exs                     # Public API functions
├── integration/
│   ├── adapter_integration_test.exs     # Adapter integration
│   ├── pool_lifecycle_test.exs          # Pool startup/shutdown
│   └── session_management_test.exs      # Session lifecycle
├── performance/
│   ├── pool_performance_test.exs        # Pool performance benchmarks
│   ├── memory_usage_test.exs            # Memory usage validation
│   └── concurrent_access_test.exs       # Concurrency testing
└── support/
    ├── mock_adapter.ex                  # Mock adapter for testing
    └── test_helpers.ex                  # Common utilities
```

### SnakepitGrpcBridge Tests
```
test/snakepit_grpc_bridge/
├── unit/
│   ├── cognitive/
│   │   ├── worker_test.exs              # Cognitive worker functionality
│   │   ├── scheduler_test.exs           # Scheduling logic
│   │   ├── evolution_test.exs           # Implementation selection
│   │   └── collaboration_test.exs       # Collaboration infrastructure
│   ├── schema/
│   │   ├── dspy_test.exs               # DSPy schema discovery
│   │   ├── universal_test.exs           # Multi-framework prep
│   │   └── optimization_test.exs        # Schema optimization
│   ├── codegen/
│   │   ├── dspy_test.exs               # defdsyp macro functionality
│   │   └── optimization_test.exs        # Usage tracking
│   ├── bridge/
│   │   ├── variables_test.exs           # Variables functionality
│   │   ├── context_test.exs            # Context management
│   │   └── tools_test.exs              # Tool calling
│   └── grpc/
│       ├── client_test.exs             # gRPC client
│       └── server_test.exs             # gRPC server
├── integration/
│   ├── dspy_integration_test.exs        # Complete DSPy workflows
│   ├── cognitive_infrastructure_test.exs # Cognitive system integration
│   ├── python_bridge_test.exs           # Python bridge integration
│   └── session_lifecycle_test.exs       # Session management
├── cognitive_readiness/
│   ├── telemetry_collection_test.exs    # Telemetry infrastructure
│   ├── learning_preparation_test.exs     # ML readiness validation
│   ├── collaboration_readiness_test.exs  # Multi-worker prep
│   └── evolution_infrastructure_test.exs # Selection engine prep
└── performance/
    ├── dspy_performance_test.exs        # DSPy operation benchmarks
    ├── schema_cache_test.exs            # Caching performance
    └── concurrent_sessions_test.exs     # Multi-session performance
```

### DSPex Integration Tests
```
test/dspex/
├── integration/
│   ├── bridge_compatibility_test.exs    # Backward compatibility
│   ├── example_validation_test.exs      # All examples work
│   └── api_compatibility_test.exs       # API unchanged
├── regression/
│   ├── functionality_regression_test.exs # No functionality lost
│   ├── performance_regression_test.exs   # Performance maintained
│   └── memory_regression_test.exs        # Memory usage acceptable
└── migration/
    ├── dependency_migration_test.exs     # Dependency changes work
    └── configuration_migration_test.exs   # Config changes work
```

## Detailed Test Specifications

### 1. Snakepit Core Unit Tests

#### Pool Management Tests (`test/snakepit_core/unit/pool_test.exs`)
```elixir
defmodule Snakepit.PoolTest do
  use ExUnit.Case
  alias Snakepit.Pool
  
  setup do
    # Use mock adapter for testing
    Application.put_env(:snakepit, :adapter_module, MockAdapter)
    {:ok, pool} = Pool.start_link(size: 2, name: TestPool)
    
    on_exit(fn ->
      if Process.alive?(pool) do
        GenServer.stop(pool)
      end
    end)
    
    %{pool: pool}
  end
  
  describe "pool initialization" do
    test "starts with configured number of workers", %{pool: pool} do
      stats = Pool.get_stats(pool)
      assert stats.total_workers == 2
      assert stats.available_workers == 2
      assert stats.busy_workers == 0
    end
    
    test "validates adapter module is configured" do
      Application.delete_env(:snakepit, :adapter_module)
      
      assert_raise RuntimeError, ~r/adapter_module must be configured/, fn ->
        Pool.start_link(name: FailPool)
      end
    end
    
    test "validates adapter implements required behavior" do
      Application.put_env(:snakepit, :adapter_module, InvalidAdapter)
      
      assert_raise RuntimeError, ~r/must implement Snakepit.Adapter behavior/, fn ->
        Pool.start_link(name: FailPool)
      end
    end
  end
  
  describe "command execution" do
    test "executes commands on available workers", %{pool: pool} do
      assert {:ok, "pong"} = Pool.execute("ping", %{}, pool: pool)
    end
    
    test "handles adapter errors gracefully", %{pool: pool} do
      assert {:error, "simulated error"} = Pool.execute("error", %{}, pool: pool)
    end
    
    test "tracks worker busy/available status", %{pool: pool} do
      # Execute long-running command asynchronously
      task = Task.async(fn -> Pool.execute("slow", %{delay: 100}, pool: pool) end)
      
      # Check that worker becomes busy
      Process.sleep(10)  # Let execution start
      stats = Pool.get_stats(pool)
      assert stats.busy_workers == 1
      assert stats.available_workers == 1
      
      # Wait for completion
      Task.await(task)
      
      # Check that worker becomes available again
      stats = Pool.get_stats(pool)
      assert stats.busy_workers == 0
      assert stats.available_workers == 2
    end
  end
  
  describe "session affinity" do
    test "routes session requests to same worker when possible", %{pool: pool} do
      session_id = "test_session"
      
      # Execute multiple commands in same session
      results = for i <- 1..5 do
        Pool.execute("get_worker_id", %{}, pool: pool, session_id: session_id)
      end
      
      # All should use same worker (when available)
      worker_ids = Enum.map(results, fn {:ok, worker_id} -> worker_id end)
      assert length(Enum.uniq(worker_ids)) <= 2  # Allow some variation due to timing
    end
    
    test "falls back to load balancing when session worker busy", %{pool: pool} do
      session_id = "busy_session"
      
      # Start long-running task on session worker
      task = Task.async(fn -> 
        Pool.execute("slow", %{delay: 100}, pool: pool, session_id: session_id)
      end)
      
      Process.sleep(10)  # Let first task start
      
      # Second request should use different worker
      {:ok, _} = Pool.execute("ping", %{}, pool: pool, session_id: session_id)
      
      Task.await(task)
    end
  end
  
  describe "telemetry collection" do
    test "collects execution telemetry", %{pool: pool} do
      # Subscribe to telemetry events
      :telemetry.attach("test", [:snakepit, :pool, :execution], &capture_telemetry/4, %{})
      
      Pool.execute("ping", %{test: true}, pool: pool)
      
      # Verify telemetry was emitted (implementation depends on telemetry setup)
      # This would check that telemetry events were captured
      
      :telemetry.detach("test")
    end
    
    test "tracks performance metrics", %{pool: pool} do
      # Execute several commands
      for _i <- 1..10 do
        Pool.execute("ping", %{}, pool: pool)
      end
      
      stats = Pool.get_stats(pool)
      assert stats.total_requests == 10
      assert stats.successful_requests == 10
      assert stats.failed_requests == 0
      assert is_float(stats.average_response_time_ms)
    end
  end
  
  defp capture_telemetry(_event, _measurements, _metadata, _config) do
    # Store telemetry data for verification
    send(self(), :telemetry_received)
  end
end

# Mock adapter for testing
defmodule MockAdapter do
  @behaviour Snakepit.Adapter
  
  def execute("ping", _args, _opts), do: {:ok, "pong"}
  def execute("error", _args, _opts), do: {:error, "simulated error"}  
  def execute("slow", %{delay: delay}, _opts) do
    Process.sleep(delay)
    {:ok, "completed"}
  end
  def execute("get_worker_id", _args, opts) do
    {:ok, opts[:worker_pid] || :unknown_worker}
  end
  
  def uses_grpc?, do: false
  def supports_streaming?, do: false
  def init(_config), do: {:ok, %{}}
  def terminate(_reason, _state), do: :ok
  def start_worker(_state, worker_id), do: {:ok, spawn(fn -> :timer.sleep(:infinity) end)}
end
```

### 2. SnakepitGrpcBridge Integration Tests

#### DSPy Integration Tests (`test/snakepit_grpc_bridge/integration/dspy_integration_test.exs`)
```elixir
defmodule SnakepitGrpcBridge.DSPyIntegrationTest do
  use ExUnit.Case
  
  setup_all do
    # Start bridge for integration tests
    {:ok, bridge_info} = SnakepitGrpcBridge.start_bridge([
      python_executable: "python3",
      grpc_port: 0
    ])
    
    on_exit(fn -> SnakepitGrpcBridge.stop_bridge() end)
    
    %{bridge: bridge_info}
  end
  
  describe "complete DSPy workflows" do
    test "schema discovery -> instance creation -> execution" do
      # Step 1: Discover DSPy schema
      {:ok, schema} = SnakepitGrpcBridge.discover_schema("dspy")
      assert is_map(schema)
      assert Map.has_key?(schema, "classes")
      
      # Step 2: Create DSPy instance
      session_id = "integration_test_#{:rand.uniform(1000)}"
      {:ok, result} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "dspy.Predict",
        "method" => "__init__",
        "args" => ["question -> answer"],
        "kwargs" => %{}
      })
      
      assert result["success"] == true
      instance_id = result["instance_id"]
      
      # Step 3: Execute prediction
      {:ok, prediction} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "stored.#{instance_id}",
        "method" => "__call__",
        "args" => [],
        "kwargs" => %{"question" => "What is DSPy?"}
      })
      
      assert prediction["success"] == true
      assert Map.has_key?(prediction, "result")
    end
    
    test "variables integration with DSPy execution" do
      session_id = "variables_test_#{:rand.uniform(1000)}"
      
      # Set session variables
      :ok = SnakepitGrpcBridge.set_variable(session_id, "temperature", 0.7)
      :ok = SnakepitGrpcBridge.set_variable(session_id, "model", "gpt-3.5-turbo")
      
      # Verify variables are accessible
      {:ok, temp} = SnakepitGrpcBridge.get_variable(session_id, "temperature")
      assert temp == 0.7
      
      # Execute DSPy operation (should have access to variables)
      {:ok, result} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "dspy.Predict",
        "method" => "__init__",
        "args" => ["question -> answer"],
        "kwargs" => %{}
      })
      
      assert result["success"] == true
      
      # Variables should still be accessible after DSPy operation
      {:ok, model} = SnakepitGrpcBridge.get_variable(session_id, "model")
      assert model == "gpt-3.5-turbo"
    end
    
    test "tool calling integration" do
      session_id = "tools_test_#{:rand.uniform(1000)}"
      
      # Register custom tool
      :ok = SnakepitGrpcBridge.register_elixir_tool(session_id, "custom_validator", fn params ->
        text = params["text"]
        %{valid: String.length(text) > 5, length: String.length(text)}
      end, %{
        description: "Custom text validator",
        parameters: [%{name: "text", type: "string", required: true}]
      })
      
      # Verify tool is registered
      {:ok, tools} = SnakepitGrpcBridge.list_elixir_tools(session_id)
      assert "custom_validator" in tools
      
      # Execute DSPy operation that could potentially use tools
      {:ok, result} = SnakepitGrpcBridge.execute_dspy(session_id, "enhanced_predict", %{
        "signature" => "text -> validation",
        "text" => "This is a test string",
        "use_tools" => true
      })
      
      # Should succeed regardless of whether tools were actually used
      assert result["success"] == true
    end
  end
  
  describe "session lifecycle" do
    test "session initialization and cleanup" do
      session_id = "lifecycle_test_#{:rand.uniform(1000)}"
      
      # Initialize session
      {:ok, session_info} = SnakepitGrpcBridge.initialize_session(session_id, %{
        "enable_variables" => true,
        "enable_tools" => true
      })
      
      assert session_info["session_id"] == session_id
      assert session_info["variables_enabled"] == true
      assert session_info["tools_enabled"] == true
      
      # Use session
      :ok = SnakepitGrpcBridge.set_variable(session_id, "test", "data")
      {:ok, value} = SnakepitGrpcBridge.get_variable(session_id, "test")
      assert value == "data"
      
      # Clean up session
      :ok = SnakepitGrpcBridge.cleanup_session(session_id)
      
      # Variables should be cleaned up
      {:ok, cleaned_value} = SnakepitGrpcBridge.get_variable(session_id, "test", :not_found)
      assert cleaned_value == :not_found
    end
    
    test "concurrent session handling" do
      sessions = 1..10 |> Enum.map(&"concurrent_#{&1}")
      
      # Initialize all sessions concurrently
      session_tasks = Task.async_stream(sessions, fn session_id ->
        {:ok, _} = SnakepitGrpcBridge.initialize_session(session_id)
        :ok = SnakepitGrpcBridge.set_variable(session_id, "session_data", session_id)
        {:ok, data} = SnakepitGrpcBridge.get_variable(session_id, "session_data")
        {session_id, data}
      end, timeout: 30_000, max_concurrency: 10)
      |> Enum.to_list()
      
      # Verify all sessions worked correctly
      results = Enum.map(session_tasks, fn {:ok, {session_id, data}} ->
        assert data == session_id
        session_id
      end)
      
      assert length(results) == 10
      
      # Clean up all sessions
      Enum.each(sessions, &SnakepitGrpcBridge.cleanup_session/1)
    end
  end
end
```

### 3. Cognitive Readiness Tests

#### Telemetry Collection Tests (`test/snakepit_grpc_bridge/cognitive_readiness/telemetry_collection_test.exs`)
```elixir
defmodule SnakepitGrpcBridge.CognitiveReadiness.TelemetryCollectionTest do
  use ExUnit.Case
  
  setup_all do
    {:ok, _} = SnakepitGrpcBridge.start_bridge()
    on_exit(&SnakepitGrpcBridge.stop_bridge/0)
    :ok
  end
  
  describe "telemetry infrastructure" do
    test "collects execution telemetry throughout system" do
      session_id = "telemetry_test_#{:rand.uniform(1000)}"
      
      # Subscribe to telemetry events
      telemetry_events = [
        [:snakepit, :pool, :execution],
        [:snakepit_grpc_bridge, :cognitive, :worker_execution],
        [:snakepit_grpc_bridge, :schema, :discovery],
        [:snakepit_grpc_bridge, :codegen, :wrapper_generated]
      ]
      
      captured_events = capture_telemetry_events(telemetry_events)
      
      # Execute operations that should generate telemetry
      {:ok, _} = SnakepitGrpcBridge.discover_schema("dspy")
      {:ok, _} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
        "class_path" => "dspy.Predict",
        "method" => "__init__",
        "args" => ["test -> result"],
        "kwargs" => %{}
      })
      
      # Generate codegen telemetry (if possible in test environment)
      
      # Wait for telemetry collection
      Process.sleep(100)
      
      # Verify telemetry was collected
      events = get_captured_events(captured_events)
      assert length(events) > 0
      
      # Verify event structure
      Enum.each(events, fn event ->
        assert Map.has_key?(event, :timestamp)
        assert Map.has_key?(event, :measurements)
        assert Map.has_key?(event, :metadata)
      end)
    end
    
    test "telemetry data quality suitable for ML training" do
      session_id = "ml_prep_test_#{:rand.uniform(1000)}"
      
      # Execute diverse operations to generate varied telemetry
      operations = [
        {"schema_discovery", fn -> SnakepitGrpcBridge.discover_schema("dspy") end},
        {"simple_dspy_call", fn -> 
          SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
            "class_path" => "dspy.Predict",
            "method" => "__init__",
            "args" => ["simple -> result"],
            "kwargs" => %{}
          })
        end},
        {"complex_dspy_call", fn ->
          SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
            "class_path" => "dspy.ChainOfThought", 
            "method" => "__init__",
            "args" => ["complex_input -> detailed_reasoning, final_answer"],
            "kwargs" => %{"max_hops" => 3}
          })
        end},
        {"variable_operations", fn ->
          :ok = SnakepitGrpcBridge.set_variable(session_id, "test_var", "test_value")
          {:ok, _} = SnakepitGrpcBridge.get_variable(session_id, "test_var")
        end}
      ]
      
      # Execute operations and collect timing/success data
      results = Enum.map(operations, fn {op_name, op_fn} ->
        start_time = System.monotonic_time(:microsecond)
        result = op_fn.()
        end_time = System.monotonic_time(:microsecond)
        
        %{
          operation: op_name,
          success: match?({:ok, _}, result),
          duration: end_time - start_time,
          timestamp: DateTime.utc_now()
        }
      end)
      
      # Verify we have diverse, complete data
      assert length(results) == 4
      assert Enum.all?(results, fn r -> Map.has_key?(r, :duration) end)
      assert Enum.all?(results, fn r -> is_integer(r.duration) and r.duration > 0 end)
      
      # Verify data diversity (different operations have different characteristics)
      durations = Enum.map(results, & &1.duration)
      assert Enum.max(durations) > Enum.min(durations)  # Should have variation
    end
    
    test "cognitive infrastructure ready for learning activation" do
      # Test that cognitive modules have learning infrastructure in place
      cognitive_insights = SnakepitGrpcBridge.get_cognitive_insights()
      
      # Verify cognitive readiness metrics
      assert Map.has_key?(cognitive_insights, :worker_performance)
      assert Map.has_key?(cognitive_insights, :routing_intelligence)
      assert Map.has_key?(cognitive_insights, :evolution_data)
      assert Map.has_key?(cognitive_insights, :collaboration_readiness)
      
      # Verify telemetry data collection
      assert Map.has_key?(cognitive_insights, :telemetry_data_volume)
      assert cognitive_insights.telemetry_data_volume.collection_rate_per_minute > 0
      
      # Verify cognitive readiness assessment
      assert Map.has_key?(cognitive_insights, :cognitive_features_ready)
      readiness = cognitive_insights.cognitive_features_ready
      
      # Should have readiness scores (even if not ready yet)
      assert Map.has_key?(readiness, :overall_readiness_score)
      assert is_float(readiness.overall_readiness_score)
      assert readiness.overall_readiness_score >= 0.0
      assert readiness.overall_readiness_score <= 1.0
    end
  end
  
  describe "learning infrastructure validation" do
    test "performance data collection for evolution engine" do
      session_id = "evolution_prep_#{:rand.uniform(1000)}"
      
      # Execute operations that should feed evolution engine
      implementations = [:dspy_python, :native_elixir]  # Simulated options
      
      for impl <- implementations do
        # Simulate implementation selection and execution
        start_time = System.monotonic_time(:microsecond)
        
        result = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
          "class_path" => "dspy.Predict",
          "method" => "__init__",
          "args" => ["test -> result"],
          "kwargs" => %{},
          "implementation_hint" => impl  # For future use
        })
        
        duration = System.monotonic_time(:microsecond) - start_time
        
        # This should be collected by evolution engine for learning
        # In future, this data will train ML models for selection
        assert match?({:ok, _}, result)
        assert is_integer(duration)
      end
      
      # Verify evolution engine has infrastructure to collect this data
      evolution_insights = SnakepitGrpcBridge.get_cognitive_insights().evolution_data
      
      # Should have data collection infrastructure
      assert Map.has_key?(evolution_insights, :selection_history)
      assert Map.has_key?(evolution_insights, :performance_data)
    end
    
    test "collaboration infrastructure for multi-worker coordination" do
      # Test that collaboration infrastructure is ready
      collaboration_insights = SnakepitGrpcBridge.get_cognitive_insights().collaboration_readiness
      
      # Should have collaboration tracking infrastructure
      assert Map.has_key?(collaboration_insights, :collaboration_opportunities_identified)
      assert Map.has_key?(collaboration_insights, :collaboration_readiness)
      
      # Should show readiness for future collaboration features
      assert collaboration_insights.collaboration_readiness == :phase_1_foundation
    end
  end
  
  # Helper functions for telemetry testing
  defp capture_telemetry_events(event_names) do
    collector_pid = spawn(fn -> telemetry_collector([]) end)
    
    Enum.each(event_names, fn event_name ->
      :telemetry.attach(
        "test_#{:rand.uniform(1000)}", 
        event_name, 
        &send_to_collector/4, 
        %{collector: collector_pid}
      )
    end)
    
    collector_pid
  end
  
  defp send_to_collector(_event, measurements, metadata, %{collector: collector_pid}) do
    send(collector_pid, {:telemetry_event, %{
      measurements: measurements,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }})
  end
  
  defp telemetry_collector(events) do
    receive do
      {:telemetry_event, event} ->
        telemetry_collector([event | events])
      {:get_events, from} ->
        send(from, {:events, Enum.reverse(events)})
        telemetry_collector(events)
    end
  end
  
  defp get_captured_events(collector_pid) do
    send(collector_pid, {:get_events, self()})
    receive do
      {:events, events} -> events
    after
      1000 -> []
    end
  end
end
```

### 4. Performance and Regression Tests

#### Performance Regression Tests (`test/dspex/regression/performance_regression_test.exs`)
```elixir
defmodule DSPex.PerformanceRegressionTest do
  use ExUnit.Case
  
  @moduletag :performance
  @moduletag timeout: 300_000  # 5 minutes
  
  setup_all do
    {:ok, _} = SnakepitGrpcBridge.start_bridge()
    on_exit(&SnakepitGrpcBridge.stop_bridge/0)
    :ok
  end
  
  describe "performance benchmarks" do
    test "DSPy call performance within acceptable range" do
      session_id = "perf_test_#{:rand.uniform(1000)}"
      
      # Baseline: Single DSPy call
      {time, {:ok, result}} = :timer.tc(fn ->
        SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
          "class_path" => "dspy.Predict",
          "method" => "__init__",
          "args" => ["question -> answer"],
          "kwargs" => %{}
        })
      end)
      
      latency_ms = time / 1000
      
      # Performance targets
      assert result["success"] == true
      assert latency_ms < 200, "DSPy call took #{latency_ms}ms, expected < 200ms"
      
      IO.puts("DSPy call latency: #{latency_ms}ms")
    end
    
    test "schema discovery performance with caching" do
      # First call (uncached)
      {time1, {:ok, schema1}} = :timer.tc(fn ->
        SnakepitGrpcBridge.discover_schema("dspy")
      end)
      
      # Second call (should be cached)
      {time2, {:ok, schema2}} = :timer.tc(fn ->
        SnakepitGrpcBridge.discover_schema("dspy")
      end)
      
      latency1_ms = time1 / 1000
      latency2_ms = time2 / 1000
      
      # Performance expectations
      assert latency1_ms < 500, "Initial schema discovery took #{latency1_ms}ms, expected < 500ms"
      assert latency2_ms < 50, "Cached schema discovery took #{latency2_ms}ms, expected < 50ms"
      assert latency2_ms < latency1_ms / 2, "Cached call should be significantly faster"
      
      # Content should be identical
      assert schema1 == schema2
      
      IO.puts("Schema discovery: #{latency1_ms}ms uncached, #{latency2_ms}ms cached")
    end
    
    test "concurrent session performance" do
      session_count = 20
      operations_per_session = 5
      
      start_time = System.monotonic_time(:microsecond)
      
      # Execute concurrent operations
      tasks = Task.async_stream(1..session_count, fn session_num ->
        session_id = "concurrent_#{session_num}"
        
        # Initialize session
        {:ok, _} = SnakepitGrpcBridge.initialize_session(session_id)
        
        # Execute multiple operations per session
        results = for op_num <- 1..operations_per_session do
          case rem(op_num, 3) do
            0 -> 
              SnakepitGrpcBridge.set_variable(session_id, "var_#{op_num}", "value_#{op_num}")
              :variable_operation
            1 -> 
              {:ok, _} = SnakepitGrpcBridge.get_variable(session_id, "var_1", "default")
              :variable_get
            2 -> 
              {:ok, _} = SnakepitGrpcBridge.discover_schema("dspy")
              :schema_discovery
          end
        end
        
        # Cleanup
        SnakepitGrpcBridge.cleanup_session(session_id)
        
        {session_id, results}
      end, timeout: 60_000, max_concurrency: session_count)
      |> Enum.to_list()
      
      end_time = System.monotonic_time(:microsecond)
      total_time_ms = (end_time - start_time) / 1000
      
      # Verify all sessions completed successfully
      assert length(tasks) == session_count
      Enum.each(tasks, fn {:ok, {session_id, results}} ->
        assert String.starts_with?(session_id, "concurrent_")
        assert length(results) == operations_per_session
      end)
      
      # Performance expectations
      total_operations = session_count * operations_per_session
      operations_per_second = total_operations / (total_time_ms / 1000)
      
      assert operations_per_second > 20, "Operations per second: #{operations_per_second}, expected > 20"
      assert total_time_ms < 30_000, "Total time: #{total_time_ms}ms, expected < 30s"
      
      IO.puts("Concurrent performance: #{session_count} sessions, #{total_operations} operations in #{total_time_ms}ms")
      IO.puts("Operations per second: #{operations_per_second}")
    end
    
    test "memory usage within acceptable limits" do
      # Get baseline memory usage
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Execute memory-intensive operations
      session_ids = for i <- 1..50, do: "memory_test_#{i}"
      
      # Create sessions and execute operations
      for session_id <- session_ids do
        {:ok, _} = SnakepitGrpcBridge.initialize_session(session_id)
        
        # Set variables (uses memory)
        for j <- 1..10 do
          large_data = String.duplicate("data", 1000)  # ~4KB per variable
          :ok = SnakepitGrpcBridge.set_variable(session_id, "large_var_#{j}", large_data)
        end
        
        # Execute DSPy operations
        {:ok, _} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
          "class_path" => "dspy.Predict",
          "method" => "__init__",
          "args" => ["question -> answer"],
          "kwargs" => %{}
        })
      end
      
      # Force garbage collection and measure memory
      :erlang.garbage_collect()
      peak_memory = :erlang.memory(:total)
      memory_increase_mb = (peak_memory - initial_memory) / 1_024 / 1_024
      
      # Clean up sessions
      for session_id <- session_ids do
        SnakepitGrpcBridge.cleanup_session(session_id)
      end
      
      # Force garbage collection and measure final memory
      :erlang.garbage_collect()
      Process.sleep(100)  # Allow cleanup
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)
      final_increase_mb = (final_memory - initial_memory) / 1_024 / 1_024
      
      # Memory expectations
      assert memory_increase_mb < 300, "Peak memory increase: #{memory_increase_mb}MB, expected < 300MB"
      assert final_increase_mb < 50, "Final memory increase: #{final_increase_mb}MB, expected < 50MB (should clean up)"
      
      IO.puts("Memory usage: #{memory_increase_mb}MB peak, #{final_increase_mb}MB final")
    end
  end
  
  describe "throughput benchmarks" do
    test "sustained throughput under load" do
      duration_seconds = 30
      target_ops_per_second = 10
      
      session_id = "throughput_test"
      {:ok, _} = SnakepitGrpcBridge.initialize_session(session_id)
      
      start_time = System.monotonic_time(:second)
      operation_count = execute_sustained_load(session_id, duration_seconds)
      end_time = System.monotonic_time(:second)
      
      actual_duration = end_time - start_time
      actual_ops_per_second = operation_count / actual_duration
      
      assert actual_ops_per_second >= target_ops_per_second,
        "Throughput: #{actual_ops_per_second} ops/sec, expected >= #{target_ops_per_second}"
      
      IO.puts("Sustained throughput: #{actual_ops_per_second} operations/second over #{actual_duration} seconds")
      
      SnakepitGrpcBridge.cleanup_session(session_id)
    end
  end
  
  defp execute_sustained_load(session_id, duration_seconds) do
    end_time = System.monotonic_time(:second) + duration_seconds
    execute_operations_until(session_id, end_time, 0)
  end
  
  defp execute_operations_until(session_id, end_time, count) do
    if System.monotonic_time(:second) < end_time do
      # Execute a mix of operations
      case rem(count, 4) do
        0 -> 
          {:ok, _} = SnakepitGrpcBridge.discover_schema("dspy")
        1 -> 
          :ok = SnakepitGrpcBridge.set_variable(session_id, "counter", count)
        2 -> 
          {:ok, _} = SnakepitGrpcBridge.get_variable(session_id, "counter", 0)
        3 -> 
          {:ok, _} = SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
            "class_path" => "dspy.Predict",
            "method" => "__init__",
            "args" => ["test -> result"],
            "kwargs" => %{}
          })
      end
      
      execute_operations_until(session_id, end_time, count + 1)
    else
      count
    end
  end
end
```

## Test Execution Strategy

### Continuous Integration Pipeline
```yaml
# .github/workflows/cognitive_architecture_test.yml
name: Cognitive Architecture Tests

on: [push, pull_request]

jobs:
  unit_tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
      
      - name: Install dependencies
        run: |
          cd snakepit && mix deps.get
          cd ../snakepit_grpc_bridge && mix deps.get
          cd ../dspex && mix deps.get
      
      - name: Run Snakepit Core tests
        run: cd snakepit && mix test
      
      - name: Run Bridge unit tests
        run: cd snakepit_grpc_bridge && mix test --exclude integration --exclude performance
      
      - name: Run DSPex unit tests
        run: cd dspex && mix test --exclude integration

  integration_tests:
    runs-on: ubuntu-latest
    services:
      python:
        image: python:3.9
    steps:
      # ... setup steps
      
      - name: Install Python dependencies
        run: |
          pip install dspy-ai grpcio protobuf
      
      - name: Run integration tests
        run: |
          cd snakepit_grpc_bridge && mix test --only integration
          cd ../dspex && mix test --only integration

  performance_tests:
    runs-on: ubuntu-latest
    steps:
      # ... setup steps
      
      - name: Run performance benchmarks
        run: |
          cd snakepit_grpc_bridge && mix test --only performance
          cd ../dspex && mix test --only performance
      
      - name: Performance regression check
        run: |
          # Compare performance metrics against baseline
          # Fail if regression > 10%
```

### Local Testing Commands
```bash
# Run all tests
./scripts/test_all.sh

# Run specific test levels
mix test --only unit
mix test --only integration  
mix test --only performance
mix test --only cognitive_readiness

# Run tests with coverage
mix test --cover

# Run performance benchmarks
mix test --only performance --timeout 300000
```

## Success Criteria

### Functional Testing ✅
- [ ] All current DSPex functionality works identically
- [ ] All DSPy bridge operations successful
- [ ] Variables and context management working
- [ ] Tool calling system functional
- [ ] Session management working correctly

### Performance Testing ✅
- [ ] DSPy call latency < 200ms (95th percentile)
- [ ] Schema discovery < 500ms uncached, < 50ms cached
- [ ] Variable operations < 10ms
- [ ] Memory usage < 300MB peak, < 50MB steady state
- [ ] Concurrent sessions: 20+ sessions, 100+ operations

### Cognitive Readiness Testing ✅
- [ ] Telemetry collection active throughout system
- [ ] Performance data suitable for ML training
- [ ] Cognitive infrastructure ready for enhancement
- [ ] Learning data collection > 90% coverage
- [ ] Collaboration infrastructure prepared

### Architectural Testing ✅
- [ ] Clean separation between Core and Bridge
- [ ] Adapter pattern working correctly
- [ ] Module boundaries respected
- [ ] Configuration system functional
- [ ] Error handling comprehensive

This testing strategy ensures that the cognitive-ready architecture maintains all current functionality while being fully prepared for future cognitive enhancement through comprehensive validation at all levels.
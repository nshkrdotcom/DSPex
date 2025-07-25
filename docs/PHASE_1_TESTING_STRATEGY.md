# Phase 1 Testing Strategy: Comprehensive Validation

**Date**: July 25, 2025  
**Author**: Claude Code  
**Status**: Phase 1 Testing Requirements  
**Version**: 1.0

## Overview

This document defines the comprehensive testing strategy for Phase 1 migration. The strategy ensures 100% functional compatibility while validating the new cognitive framework infrastructure.

**Testing Philosophy**: **Zero Regression, Maximum Coverage, Performance Baseline**

## Testing Levels

### Level 1: Unit Testing (Immediate Feedback)
**Target**: Individual cognitive modules
**Execution Time**: < 5 minutes
**Coverage**: 95%+

### Level 2: Integration Testing (Component Interaction)
**Target**: Cognitive system integration
**Execution Time**: < 15 minutes  
**Coverage**: 90%+

### Level 3: System Testing (End-to-End Validation)
**Target**: Complete system workflows
**Execution Time**: < 30 minutes
**Coverage**: 85%+

### Level 4: Performance Testing (Baseline Validation)
**Target**: Performance regression detection
**Execution Time**: < 45 minutes
**Coverage**: Key performance paths

## Test Categories

### 1. Functional Compatibility Tests

#### 1.1 DSPy Bridge Compatibility Tests
```elixir
# test/snakepit/schema/dspy_compatibility_test.exs
defmodule Snakepit.Schema.DSPyCompatibilityTest do
  @moduledoc """
  Ensures that moved DSPy functionality works identically to original.
  
  These tests validate that all DSPy bridge operations produce identical
  results before and after the migration.
  """
  
  use ExUnit.Case
  alias Snakepit.Schema.DSPy
  
  @moduletag :compatibility
  @moduletag timeout: 60_000
  
  describe "schema discovery compatibility" do
    test "discovers same schema as original implementation" do
      # Test against known DSPy schema structure
      expected_schema = load_reference_schema("dspy_reference_schema.json")
      
      {:ok, discovered_schema} = DSPy.discover_schema("dspy")
      
      assert schema_functionally_equivalent?(discovered_schema, expected_schema)
    end
    
    test "handles missing modules identically to original" do
      assert {:error, reason} = DSPy.discover_schema("nonexistent_module")
      assert reason =~ "ModuleNotFoundError"
    end
    
    test "respects discovery options" do
      opts = [include_private: true, max_depth: 5]
      {:ok, schema_with_opts} = DSPy.discover_schema("dspy", opts)
      {:ok, schema_without_opts} = DSPy.discover_schema("dspy")
      
      # Schema with private should have more content
      assert schema_size(schema_with_opts) >= schema_size(schema_without_opts)
    end
  end
  
  describe "DSPy method calling compatibility" do
    test "creates DSPy instances identically to original" do
      # Test basic Predict creation
      result = DSPy.call_dspy("dspy.Predict", "__init__", ["question -> answer"], %{})
      
      assert {:ok, instance_data} = result
      assert instance_data["instance_id"]
      assert instance_data["type"] == "constructor"
      assert instance_data["class_name"] == "Predict"
    end
    
    test "executes DSPy methods identically to original" do
      # Create instance first
      {:ok, instance_data} = DSPy.call_dspy("dspy.Predict", "__init__", ["question -> answer"], %{})
      instance_id = instance_data["instance_id"]
      
      # Execute method
      execution_result = DSPy.call_dspy(
        "stored.#{instance_id}",
        "__call__",
        [],
        %{"question" => "What is 2+2?"}
      )
      
      assert {:ok, result} = execution_result
      assert is_map(result)
      assert result["answer"]  # Should have answer field
    end
    
    test "handles errors identically to original" do
      # Test invalid class path
      result = DSPy.call_dspy("invalid.NonExistentClass", "__init__", [], %{})
      assert {:error, reason} = result
      assert reason =~ "AttributeError"
    end
  end
  
  # Helper functions
  defp load_reference_schema(filename) do
    Path.join([__DIR__, "fixtures", filename])
    |> File.read!()
    |> Jason.decode!()
  end
  
  defp schema_functionally_equivalent?(schema1, schema2) do
    # Compare essential schema structure, allowing for minor differences
    essential_keys = ["classes", "functions"]
    
    Enum.all?(essential_keys, fn key ->
      Map.get(schema1, key, %{}) |> map_size() == 
      Map.get(schema2, key, %{}) |> map_size()
    end)
  end
  
  defp schema_size(schema) when is_map(schema) do
    (map_size(schema["classes"] || %{}) + 
     map_size(schema["functions"] || %{}) + 
     map_size(schema["constants"] || %{}))
  end
end
```

#### 1.2 Variables System Compatibility Tests
```elixir
# test/snakepit/bridge/enhanced_variables_compatibility_test.exs
defmodule Snakepit.Bridge.EnhancedVariablesCompatibilityTest do
  @moduledoc """
  Validates that enhanced variables system maintains complete compatibility
  with original DSPex.Variables functionality.
  """
  
  use ExUnit.Case
  alias Snakepit.Bridge.EnhancedVariables
  
  @moduletag :compatibility
  
  describe "variable definition compatibility" do
    test "defines variables with identical behavior to original" do
      {:ok, context} = EnhancedVariables.start_link()
      
      # Test basic variable definition
      assert {:ok, var_id} = EnhancedVariables.defvariable(context, :temperature, :float, 0.7)
      assert is_binary(var_id)
      
      # Test retrieval
      assert 0.7 = EnhancedVariables.get(context, :temperature)
    end
    
    test "handles variable types identically to original" do
      {:ok, context} = EnhancedVariables.start_link()
      
      test_cases = [
        {:string_var, :string, "test string"},
        {:int_var, :integer, 42},
        {:float_var, :float, 3.14},
        {:bool_var, :boolean, true},
        {:list_var, :list, [1, 2, 3]},
        {:map_var, :map, %{key: "value"}}
      ]
      
      for {name, type, value} <- test_cases do
        assert {:ok, _} = EnhancedVariables.defvariable(context, name, type, value)
        assert ^value = EnhancedVariables.get(context, name)
      end
    end
    
    test "enforces constraints identically to original" do
      {:ok, context} = EnhancedVariables.start_link()
      
      # Test constraint validation
      constraints = %{min: 0.0, max: 1.0}
      assert {:ok, _} = EnhancedVariables.defvariable(
        context, :temp, :float, 0.5, constraints: constraints
      )
      
      # Valid update
      assert :ok = EnhancedVariables.set(context, :temp, 0.8)
      
      # Invalid update (should fail)
      assert {:error, _reason} = EnhancedVariables.set(context, :temp, 1.5)
    end
  end
  
  describe "variable operations compatibility" do
    setup do
      {:ok, context} = EnhancedVariables.start_link()
      
      # Setup test variables
      EnhancedVariables.defvariable(context, :temp, :float, 0.7)
      EnhancedVariables.defvariable(context, :model, :string, "gpt-4")
      EnhancedVariables.defvariable(context, :max_tokens, :integer, 100)
      
      {:ok, context: context}
    end
    
    test "lists variables identically to original", %{context: context} do
      variables = EnhancedVariables.list(context)
      
      assert length(variables) == 3
      
      # Check that all expected variables are present
      variable_names = Enum.map(variables, fn var -> var.name end)
      assert :temp in variable_names
      assert :model in variable_names
      assert :max_tokens in variable_names
    end
    
    test "gets variables with default values", %{context: context} do
      # Existing variable
      assert 0.7 = EnhancedVariables.get(context, :temp)
      
      # Non-existent variable with default
      assert "default" = EnhancedVariables.get(context, :nonexistent, "default")
      
      # Non-existent variable without default
      assert nil = EnhancedVariables.get(context, :nonexistent)
    end
    
    test "sets variables with proper validation", %{context: context} do
      # Valid set operations
      assert :ok = EnhancedVariables.set(context, :temp, 0.9)
      assert 0.9 = EnhancedVariables.get(context, :temp)
      
      assert :ok = EnhancedVariables.set(context, :model, "gpt-3.5")
      assert "gpt-3.5" = EnhancedVariables.get(context, :model)
      
      # Invalid set (variable doesn't exist)
      assert {:error, :variable_not_found} = EnhancedVariables.set(context, :nonexistent, "value")
    end
  end
end
```

### 2. Cognitive Infrastructure Tests

#### 2.1 Telemetry Collection Tests
```elixir
# test/snakepit/cognitive/telemetry_collection_test.exs
defmodule Snakepit.Cognitive.TelemetryCollectionTest do
  @moduledoc """
  Validates that telemetry collection infrastructure works correctly
  without impacting functional behavior.
  """
  
  use ExUnit.Case
  
  @moduletag :cognitive
  @moduletag :telemetry
  
  describe "telemetry collection" do
    setup do
      # Clear telemetry tables
      :ets.delete_all_objects(:cognitive_telemetry)
      
      # Enable telemetry for tests
      Application.put_env(:snakepit, :cognitive_features, %{
        telemetry_collection: true,
        performance_monitoring: true
      })
      
      :ok
    end
    
    test "collects schema discovery telemetry" do
      # Perform schema discovery
      {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
      
      # Wait for telemetry processing
      :timer.sleep(100)
      
      # Verify telemetry was collected
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      
      assert length(telemetry_entries) > 0
      
      # Find schema discovery entry
      discovery_entry = Enum.find(telemetry_entries, fn {_id, data} ->
        data.module_path == "dspy" and Map.has_key?(data, :discovery_time)
      end)
      
      assert discovery_entry
      {_id, data} = discovery_entry
      
      assert data.module_path == "dspy"
      assert is_integer(data.discovery_time)
      assert data.discovery_time > 0
      assert data.phase == :phase_1_enhanced
    end
    
    test "collects variable operation telemetry" do
      {:ok, context} = Snakepit.Bridge.EnhancedVariables.start_link()
      
      # Perform variable operations
      {:ok, _var_id} = Snakepit.Bridge.EnhancedVariables.defvariable(context, :test_var, :string, "test")
      _value = Snakepit.Bridge.EnhancedVariables.get(context, :test_var)
      :ok = Snakepit.Bridge.EnhancedVariables.set(context, :test_var, "updated")
      
      # Wait for telemetry processing
      :timer.sleep(100)
      
      # Verify telemetry collection
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      
      # Should have entries for define, get, and set operations
      definition_entries = Enum.filter(telemetry_entries, fn {_id, data} ->
        Map.has_key?(data, :variable_name) and data.variable_name == :test_var
      end)
      
      assert length(definition_entries) >= 1
    end
    
    test "telemetry collection does not impact performance significantly" do
      # Baseline: operations with telemetry disabled
      Application.put_env(:snakepit, :cognitive_features, %{telemetry_collection: false})
      
      baseline_time = measure_operation_time(fn ->
        {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
      end)
      
      # Test: operations with telemetry enabled
      Application.put_env(:snakepit, :cognitive_features, %{telemetry_collection: true})
      
      telemetry_time = measure_operation_time(fn ->
        {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
      end)
      
      # Telemetry should add less than 10% overhead
      overhead_ratio = (telemetry_time - baseline_time) / baseline_time
      assert overhead_ratio < 0.1, "Telemetry overhead too high: #{overhead_ratio * 100}%"
    end
  end
  
  describe "performance monitoring" do
    test "tracks performance metrics correctly" do
      # Enable performance monitoring
      Application.put_env(:snakepit, :cognitive_features, %{performance_monitoring: true})
      
      # Perform operations
      {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
      
      # Get performance metrics
      metrics = Snakepit.Cognitive.PerformanceMonitor.get_performance_metrics()
      
      assert metrics.total_schema_discoveries >= 1
      assert metrics.average_discovery_time > 0
      assert is_float(metrics.average_discovery_time)
    end
    
    test "generates performance reports" do
      # Trigger performance report generation
      send(Snakepit.Cognitive.PerformanceMonitor, :report_performance)
      
      # Wait for report processing
      :timer.sleep(100)
      
      # Verify report was generated and stored
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      
      report_entry = Enum.find(telemetry_entries, fn {_id, data} ->
        Map.has_key?(data, :system_health) and Map.has_key?(data, :recommendations)
      end)
      
      assert report_entry
      {_id, report} = report_entry
      
      assert report.system_health in [:excellent, :good, :fair, :poor]
      assert is_list(report.recommendations)
    end
  end
  
  defp measure_operation_time(operation_fn) do
    start_time = System.monotonic_time(:microsecond)
    operation_fn.()
    System.monotonic_time(:microsecond) - start_time
  end
end
```

#### 2.2 Feature Flag Tests
```elixir
# test/snakepit/cognitive/feature_flags_test.exs
defmodule Snakepit.Cognitive.FeatureFlagsTest do
  @moduledoc """
  Validates feature flag system for gradual cognitive feature activation.
  """
  
  use ExUnit.Case
  alias Snakepit.Cognitive.FeatureFlags
  
  @moduletag :cognitive
  @moduletag :feature_flags
  
  describe "feature flag management" do
    setup do
      # Reset to default flags
      Application.put_env(:snakepit, :cognitive_features, %{
        telemetry_collection: true,
        performance_monitoring: true,
        performance_learning: false,
        implementation_selection: false
      })
      
      :ok
    end
    
    test "correctly reports enabled and disabled features" do
      assert FeatureFlags.enabled?(:telemetry_collection) == true
      assert FeatureFlags.enabled?(:performance_monitoring) == true
      assert FeatureFlags.enabled?(:performance_learning) == false
      assert FeatureFlags.enabled?(:implementation_selection) == false
      assert FeatureFlags.enabled?(:nonexistent_feature) == false
    end
    
    test "allows dynamic feature activation" do
      assert FeatureFlags.enabled?(:performance_learning) == false
      
      FeatureFlags.enable_feature(:performance_learning, 100)
      
      assert FeatureFlags.enabled?(:performance_learning) == true
    end
    
    test "allows dynamic feature deactivation" do
      assert FeatureFlags.enabled?(:telemetry_collection) == true
      
      FeatureFlags.disable_feature(:telemetry_collection)
      
      assert FeatureFlags.enabled?(:telemetry_collection) == false
    end
    
    test "supports gradual rollout percentages" do
      # Test gradual rollout (this is a basic test - real implementation would need traffic splitting)
      FeatureFlags.enable_feature(:test_feature, 50)
      
      # Feature should be enabled (simplified test)
      current_flags = Application.get_env(:snakepit, :cognitive_features)
      assert current_flags[:test_feature] == 50
    end
  end
end
```

### 3. Integration Tests

#### 3.1 End-to-End Workflow Tests
```elixir
# test/integration/cognitive_workflow_test.exs
defmodule Integration.CognitiveWorkflowTest do
  @moduledoc """
  End-to-end integration tests for complete cognitive workflows.
  
  These tests validate that the entire cognitive system works together
  correctly from user API through to Python execution.
  """
  
  use ExUnit.Case
  
  @moduletag :integration
  @moduletag :slow
  @moduletag timeout: 120_000
  
  describe "complete DSPy workflow" do
    test "end-to-end DSPy prediction workflow" do
      # 1. Start cognitive context
      {:ok, context} = Snakepit.Context.start_link()
      session_id = Snakepit.Context.get_session_id(context)
      
      # 2. Define variables
      {:ok, _temp_id} = Snakepit.Variables.defvariable(context, :temperature, :float, 0.7)
      {:ok, _model_id} = Snakepit.Variables.defvariable(context, :model, :string, "gpt-3.5-turbo")
      
      # 3. Create DSPy module using cognitive system
      {:ok, predictor} = Snakepit.Schema.DSPy.call_dspy(
        "dspy.Predict", 
        "__init__", 
        ["question -> answer"], 
        %{}
      )
      
      assert predictor["instance_id"]
      
      # 4. Execute prediction
      {:ok, result} = Snakepit.Schema.DSPy.call_dspy(
        "stored.#{predictor["instance_id"]}",
        "__call__",
        [],
        %{"question" => "What is the capital of France?"}
      )
      
      assert result["answer"]
      assert String.contains?(result["answer"], "Paris")
      
      # 5. Verify telemetry was collected
      :timer.sleep(100)  # Allow telemetry processing
      
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      assert length(telemetry_entries) > 0
      
      # Should have entries for variable definitions, schema calls, etc.
      schema_entries = Enum.filter(telemetry_entries, fn {_id, data} ->
        Map.has_key?(data, :class_path) and data.class_path == "dspy.Predict"
      end)
      
      assert length(schema_entries) >= 1
    end
    
    test "variable-aware DSPy workflow with optimization" do
      # 1. Setup cognitive context
      {:ok, context} = Snakepit.Context.start_link()
      
      # 2. Define multiple variables for testing
      variables = [
        {:temperature, :float, 0.8},
        {:max_tokens, :integer, 150},
        {:model, :string, "gpt-4"},
        {:reasoning_steps, :integer, 3}
      ]
      
      for {name, type, value} <- variables do
        {:ok, _id} = Snakepit.Variables.defvariable(context, name, type, value)
      end
      
      # 3. Create variable-aware DSPy module
      {:ok, cot_module} = Snakepit.Schema.DSPy.call_dspy(
        "dspy.ChainOfThought",
        "__init__",
        ["question -> reasoning, answer"],
        %{}
      )
      
      # 4. Execute with variable integration
      question = "Explain the process of photosynthesis step by step"
      
      {:ok, result} = Snakepit.Schema.DSPy.call_dspy(
        "stored.#{cot_module["instance_id"]}",
        "__call__",
        [],
        %{
          "question" => question,
          "temperature" => Snakepit.Variables.get(context, :temperature),
          "max_tokens" => Snakepit.Variables.get(context, :max_tokens)
        }
      )
      
      assert result["reasoning"]
      assert result["answer"]
      assert String.contains?(result["reasoning"], "step")
      
      # 5. Verify performance tracking
      performance_metrics = Snakepit.Cognitive.PerformanceMonitor.get_performance_metrics()
      
      assert performance_metrics.total_tasks_executed >= 1
      assert performance_metrics.average_execution_time > 0
    end
  end
  
  describe "cognitive system resilience" do
    test "handles Python errors gracefully with telemetry" do
      # Test error handling and recovery
      {:ok, _context} = Snakepit.Context.start_link()
      
      # Attempt invalid operation
      result = Snakepit.Schema.DSPy.call_dspy(
        "invalid.Module",
        "__init__",
        [],
        %{}
      )
      
      assert {:error, reason} = result
      assert reason =~ "AttributeError"
      
      # Verify error was tracked in telemetry
      :timer.sleep(100)
      
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      error_entries = Enum.filter(telemetry_entries, fn {_id, data} ->
        Map.has_key?(data, :class_path) and data.class_path == "invalid.Module"
      end)
      
      assert length(error_entries) >= 1
    end
    
    test "maintains performance under concurrent load" do
      # Test concurrent operations
      contexts = for i <- 1..5 do
        {:ok, context} = Snakepit.Context.start_link()
        {:ok, _} = Snakepit.Variables.defvariable(context, :test_var, :integer, i)
        context
      end
      
      # Execute concurrent schema discoveries
      tasks = for context <- contexts do
        Task.async(fn ->
          {:ok, schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
          value = Snakepit.Variables.get(context, :test_var)
          {schema, value}
        end)
      end
      
      results = Task.await_many(tasks, 30_000)
      
      # All operations should succeed
      assert length(results) == 5
      Enum.each(results, fn {schema, value} ->
        assert is_map(schema)
        assert is_integer(value)
      end)
      
      # Performance should remain acceptable
      performance_metrics = Snakepit.Cognitive.PerformanceMonitor.get_performance_metrics()
      assert performance_metrics.average_execution_time < 10_000_000  # Less than 10 seconds
    end
  end
end
```

### 4. Performance Baseline Tests

#### 4.1 Performance Regression Tests
```elixir
# test/performance/cognitive_performance_test.exs
defmodule Performance.CognitivePerformanceTest do
  @moduledoc """
  Performance regression tests to ensure cognitive enhancements
  don't significantly impact system performance.
  """
  
  use ExUnit.Case
  
  @moduletag :performance
  @moduletag :slow
  @moduletag timeout: 300_000
  
  @performance_thresholds %{
    schema_discovery_max_time: 5_000_000,    # 5 seconds
    variable_operation_max_time: 100_000,    # 100ms
    dspy_call_max_time: 10_000_000,         # 10 seconds
    memory_growth_max_mb: 50                 # 50MB max growth
  }
  
  describe "performance baselines" do
    test "schema discovery performance" do
      # Measure schema discovery performance
      times = for _i <- 1..10 do
        measure_time(fn ->
          {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
        end)
      end
      
      average_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)
      
      assert average_time < @performance_thresholds.schema_discovery_max_time,
        "Schema discovery too slow: #{average_time}μs (max: #{@performance_thresholds.schema_discovery_max_time}μs)"
      
      assert max_time < @performance_thresholds.schema_discovery_max_time * 2,
        "Schema discovery max time too slow: #{max_time}μs"
    end
    
    test "variable operations performance" do
      {:ok, context} = Snakepit.Bridge.EnhancedVariables.start_link()
      
      # Test variable definition performance
      def_times = for i <- 1..100 do
        measure_time(fn ->
          {:ok, _id} = Snakepit.Bridge.EnhancedVariables.defvariable(context, String.to_atom("var_#{i}"), :integer, i)
        end)
      end
      
      # Test variable access performance
      access_times = for i <- 1..100 do
        measure_time(fn ->
          _value = Snakepit.Bridge.EnhancedVariables.get(context, String.to_atom("var_#{i}"))
        end)
      end
      
      avg_def_time = Enum.sum(def_times) / length(def_times)
      avg_access_time = Enum.sum(access_times) / length(access_times)
      
      assert avg_def_time < @performance_thresholds.variable_operation_max_time,
        "Variable definition too slow: #{avg_def_time}μs"
      
      assert avg_access_time < @performance_thresholds.variable_operation_max_time,
        "Variable access too slow: #{avg_access_time}μs"
    end
    
    test "DSPy call performance" do
      # Create predictor once
      {:ok, predictor} = Snakepit.Schema.DSPy.call_dspy(
        "dspy.Predict", "__init__", ["question -> answer"], %{}
      )
      
      instance_id = predictor["instance_id"]
      
      # Measure execution performance
      execution_times = for i <- 1..5 do  # Fewer iterations due to LLM calls
        measure_time(fn ->
          {:ok, _result} = Snakepit.Schema.DSPy.call_dspy(
            "stored.#{instance_id}",
            "__call__",
            [],
            %{"question" => "What is #{i} + #{i}?"}
          )
        end)
      end
      
      average_time = Enum.sum(execution_times) / length(execution_times)
      
      assert average_time < @performance_thresholds.dspy_call_max_time,
        "DSPy call too slow: #{average_time}μs (max: #{@performance_thresholds.dspy_call_max_time}μs)"
    end
    
    test "memory usage stability" do
      # Measure initial memory
      initial_memory = get_memory_usage()
      
      # Perform many operations
      {:ok, context} = Snakepit.Bridge.EnhancedVariables.start_link()
      
      for i <- 1..1000 do
        {:ok, _id} = Snakepit.Bridge.EnhancedVariables.defvariable(context, String.to_atom("test_#{i}"), :integer, i)
        _value = Snakepit.Bridge.EnhancedVariables.get(context, String.to_atom("test_#{i}"))
        
        # Periodic schema discovery
        if rem(i, 100) == 0 do
          {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
        end
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      :timer.sleep(1000)
      
      final_memory = get_memory_usage()
      memory_growth_mb = (final_memory - initial_memory) / 1_048_576  # Convert to MB
      
      assert memory_growth_mb < @performance_thresholds.memory_growth_max_mb,
        "Memory growth too high: #{memory_growth_mb}MB (max: #{@performance_thresholds.memory_growth_max_mb}MB)"
    end
  end
  
  describe "performance monitoring accuracy" do
    test "telemetry timing accuracy" do
      # Perform operation with external timing
      external_start = System.monotonic_time(:microsecond)
      {:ok, _schema} = Snakepit.Schema.DSPy.discover_schema("dspy")
      external_time = System.monotonic_time(:microsecond) - external_start
      
      # Wait for telemetry processing
      :timer.sleep(100)
      
      # Get telemetry data
      telemetry_entries = :ets.tab2list(:cognitive_telemetry)
      discovery_entry = Enum.find(telemetry_entries, fn {_id, data} ->
        Map.has_key?(data, :discovery_time) and data.module_path == "dspy"
      end)
      
      assert discovery_entry
      {_id, data} = discovery_entry
      
      telemetry_time = data.discovery_time
      
      # Telemetry timing should be within 10% of external timing
      time_difference_ratio = abs(telemetry_time - external_time) / external_time
      assert time_difference_ratio < 0.1,
        "Telemetry timing inaccurate: #{time_difference_ratio * 100}% difference"
    end
  end
  
  defp measure_time(operation) do
    start_time = System.monotonic_time(:microsecond)
    operation.()
    System.monotonic_time(:microsecond) - start_time
  end
  
  defp get_memory_usage do
    :erlang.memory(:total)
  end
end
```

### 5. Compatibility and Migration Tests

#### 5.1 Backward Compatibility Tests
```elixir
# test/compatibility/dspex_compatibility_test.exs
defmodule Compatibility.DSPexCompatibilityTest do
  @moduledoc """
  Tests that validate backward compatibility with existing DSPex APIs.
  
  These tests ensure that existing code continues to work unchanged
  while providing deprecation warnings.
  """
  
  use ExUnit.Case
  import ExUnit.CaptureLog
  
  @moduletag :compatibility
  @moduletag :deprecated
  
  describe "DSPex.Bridge backward compatibility" do
    test "deprecated discover_schema still works with warnings" do
      log_output = capture_log(fn ->
        {:ok, schema} = DSPex.Bridge.discover_schema("dspy")
        assert is_map(schema)
      end)
      
      assert log_output =~ "deprecated"
      assert log_output =~ "Use Snakepit.Schema.DSPy.discover_schema"
    end
    
    test "deprecated call_dspy still works with warnings" do
      log_output = capture_log(fn ->
        result = DSPex.Bridge.call_dspy("dspy.Predict", "__init__", ["question -> answer"], %{})
        assert {:ok, instance_data} = result
        assert instance_data["instance_id"]
      end)
      
      assert log_output =~ "deprecated"
      assert log_output =~ "Use Snakepit.Schema.DSPy.call_dspy"
    end
    
    test "deprecated defdsyp macro still works" do
      log_output = capture_log(fn ->
        defmodule TestDeprecatedModule do
          require DSPex.Bridge
          DSPex.Bridge.defdsyp(__MODULE__, "dspy.Predict", %{})
        end
        
        # Test that the module was created with expected functions
        assert function_exported?(TestDeprecatedModule, :create, 2)
        assert function_exported?(TestDeprecatedModule, :execute, 3)
        assert function_exported?(TestDeprecatedModule, :call, 3)
      end)
      
      assert log_output =~ "deprecated"
    end
  end
  
  describe "DSPex.Variables backward compatibility" do
    test "deprecated variables API still works" do
      # Test that old DSPex.Variables calls are properly delegated
      {:ok, context} = DSPex.Context.start_link()
      
      log_output = capture_log(fn ->
        {:ok, _id} = DSPex.Variables.defvariable(context, :test_var, :float, 0.5)
        value = DSPex.Variables.get(context, :test_var)
        assert value == 0.5
      end)
      
      assert log_output =~ "deprecated"
      assert log_output =~ "Use Snakepit.Variables"
    end
  end
  
  describe "migration status reporting" do
    test "provides migration status information" do
      status = DSPex.Bridge.migration_status()
      
      assert status.status == :deprecated
      assert status.replacement_module == Snakepit.Schema.DSPy
      assert status.migration_guide
      assert status.removal_version == "0.5.0"
      assert is_map(status.current_usage)
    end
  end
end
```

## Test Execution Strategy

### Continuous Integration Pipeline
```yaml
# .github/workflows/phase1_testing.yml
name: Phase 1 Cognitive Testing

on: [push, pull_request]

jobs:
  unit_tests:
    name: Unit Tests (Level 1)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27.0'
          elixir-version: '1.18'
      
      - name: Install dependencies
        run: |
          cd snakepit && mix deps.get
          cd ../dspex && mix deps.get
      
      - name: Run unit tests
        run: |
          cd snakepit && mix test --only unit
          cd ../dspex && mix test --only unit
  
  integration_tests:
    name: Integration Tests (Level 2-3)
    runs-on: ubuntu-latest
    timeout-minutes: 30
    needs: unit_tests
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27.0'
          elixir-version: '1.18'
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Python dependencies
        run: |
          cd snakepit/priv/python && pip install -e .
          cd ../../../dspex/priv/python && pip install -e .
      
      - name: Run integration tests
        run: |
          cd snakepit && mix test --only integration
          cd ../dspex && mix test --only integration
  
  performance_tests:
    name: Performance Tests (Level 4)
    runs-on: ubuntu-latest
    timeout-minutes: 45
    needs: integration_tests
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '27.0'
          elixir-version: '1.18'
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          cd snakepit/priv/python && pip install -e .
          cd ../../../dspex/priv/python && pip install -e .
      
      - name: Run performance tests
        run: |
          cd snakepit && mix test --only performance
          cd ../dspex && mix test --only performance
      
      - name: Performance regression check
        run: |
          # Compare against baseline metrics
          mix run scripts/performance_baseline_check.exs
```

### Local Development Testing
```bash
# test/scripts/run_phase1_tests.sh
#!/bin/bash

echo "🧪 Phase 1 Cognitive Testing Suite"
echo "=================================="

# Level 1: Unit Tests (Fast feedback)
echo "📋 Running Level 1 Unit Tests..."
cd snakepit && mix test --only unit --max-failures 1
if [ $? -ne 0 ]; then
    echo "❌ Unit tests failed. Fix before proceeding."
    exit 1
fi

cd ../dspex && mix test --only unit --max-failures 1
if [ $? -ne 0 ]; then
    echo "❌ DSPex unit tests failed. Fix before proceeding."
    exit 1
fi

echo "✅ Level 1 Unit Tests: PASSED"

# Level 2: Integration Tests
echo "📋 Running Level 2 Integration Tests..."
cd ../snakepit && mix test --only integration
if [ $? -ne 0 ]; then
    echo "❌ Integration tests failed."
    exit 1
fi

cd ../dspex && mix test --only integration
if [ $? -ne 0 ]; then
    echo "❌ DSPex integration tests failed."
    exit 1
fi

echo "✅ Level 2 Integration Tests: PASSED"

# Level 3: Compatibility Tests
echo "📋 Running Level 3 Compatibility Tests..."
cd ../dspex && mix test --only compatibility
if [ $? -ne 0 ]; then
    echo "❌ Compatibility tests failed."
    exit 1
fi

echo "✅ Level 3 Compatibility Tests: PASSED"

# Level 4: Performance Tests
echo "📋 Running Level 4 Performance Tests..."
cd ../snakepit && mix test --only performance
if [ $? -ne 0 ]; then
    echo "❌ Performance tests failed."
    exit 1
fi

echo "✅ Level 4 Performance Tests: PASSED"

echo "🎉 All Phase 1 Tests: PASSED"
echo "Ready for production deployment!"
```

## Test Coverage Requirements

### Coverage Targets
- **Unit Tests**: 95%+ line coverage
- **Integration Tests**: 90%+ feature coverage  
- **Compatibility Tests**: 100% deprecated API coverage
- **Performance Tests**: 100% critical path coverage

### Coverage Analysis
```bash
# Generate coverage reports
mix test --cover
mix coveralls.html

# Validate coverage targets
mix test.coverage.validate --min-coverage 95
```

## Success Criteria

### Phase 1 Testing Success Criteria
- [ ] All functional compatibility tests pass (100%)
- [ ] All cognitive infrastructure tests pass (100%)
- [ ] All integration tests pass (100%)
- [ ] Performance within defined thresholds (100%)
- [ ] Backward compatibility maintained (100%)
- [ ] Memory usage stable (<50MB growth)
- [ ] No regression in existing functionality
- [ ] Telemetry collection working without performance impact

### Phase 1 Deployment Readiness
- [ ] All test levels passing consistently
- [ ] Performance baselines established and maintained
- [ ] Monitoring and alerting configured
- [ ] Rollback procedures tested and documented
- [ ] Team trained on new cognitive architecture
- [ ] Documentation updated and validated

This comprehensive testing strategy ensures that Phase 1 migration maintains 100% functional compatibility while successfully establishing the cognitive framework foundation for future enhancements.
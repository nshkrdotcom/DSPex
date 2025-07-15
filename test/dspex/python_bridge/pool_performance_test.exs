defmodule DSPex.PythonBridge.PoolPerformanceTest do
  @moduledoc """
  Comprehensive performance tests for V2 Pool implementation.
  
  Uses enhanced test infrastructure including:
  - :pool_testing isolation mode
  - Performance testing framework
  - Enhanced pool test helpers
  """
  
  use DSPex.UnifiedTestFoundation, :pool_testing
  import DSPex.EnhancedPoolTestHelpers
  import DSPex.PoolPerformanceFramework
  alias DSPex.PoolPerformanceFramework.PerformanceBenchmark
  
  require Logger
  
  @moduletag :pool_performance
  @moduletag timeout: 120_000  # 2 minutes for performance tests
  
  # Only run in full integration mode
  @moduletag :layer_3
  
  describe "Pool Performance Benchmarks" do
    test "single operation latency benchmark", context do
      # Use the pool from enhanced test infrastructure
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Run single operation latency benchmark
      benchmark = %PerformanceBenchmark{
        name: "single_operation_latency",
        description: "Measures latency of individual pool operations",
        pool_config: context.pool_config,
        warmup_operations: 20,
        test_operations: 100,
        concurrent_users: 1,
        duration_ms: 30_000,
        success_threshold: 0.95,
        latency_p95_threshold_ms: 2000,  # More lenient for tests
        throughput_threshold_ops_sec: 5.0   # Lower threshold for tests
      }
      
      assert {:ok, results} = benchmark_pool_operations(benchmark, pool_info)
      
      # Verify benchmark passed
      assert results.analysis_results.benchmark_passed
      assert results.measurement_results.performance_summary.success_rate >= 0.95
      
      Logger.info("Single operation latency benchmark completed: P95=#{results.measurement_results.performance_summary.latency_p95_ms}ms")
    end
    
    test "concurrent throughput benchmark", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Run concurrent throughput benchmark
      benchmark = %PerformanceBenchmark{
        name: "concurrent_throughput",
        description: "Measures throughput under concurrent load",
        pool_config: context.pool_config,
        warmup_operations: 30,
        test_operations: 200,
        concurrent_users: 4,
        duration_ms: 45_000,
        success_threshold: 0.90,
        latency_p95_threshold_ms: 3000,  # More lenient for concurrent load
        throughput_threshold_ops_sec: 10.0
      }
      
      assert {:ok, results} = benchmark_pool_operations(benchmark, pool_info)
      
      # Verify benchmark passed
      assert results.analysis_results.benchmark_passed
      assert results.measurement_results.performance_summary.success_rate >= 0.90
      
      Logger.info("Concurrent throughput benchmark completed: #{results.measurement_results.performance_summary.throughput_ops_sec} ops/sec")
    end
    
    test "session affinity performance impact", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Test session affinity performance
      assert {:ok, affinity_result} = verify_session_affinity(pool_info, 
        session_count: 3,
        operations_per_session: 5
      )
      
      # Verify session affinity is working
      assert affinity_result.affinity_success_rate >= 0.8
      assert affinity_result.overall_success_rate >= 0.9
      
      Logger.info("Session affinity performance: #{affinity_result.affinity_success_rate * 100}% sessions maintained affinity")
    end
  end
  
  describe "Performance Metrics Collection" do
    test "collect comprehensive performance metrics", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Collect performance metrics
      assert {:ok, metrics} = collect_performance_metrics(pool_info,
        duration_ms: 10_000,
        sample_interval_ms: 1000
      )
      
      # Verify metrics collection
      assert metrics.collection_duration_ms > 0
      assert metrics.operation_metrics.total_operations >= 0
      assert metrics.system_metrics.sample_count > 0
      
      Logger.info("Performance metrics collected: #{metrics.system_metrics.sample_count} samples")
    end
    
    test "monitor pool performance during operations", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Monitor pool performance
      assert {:ok, monitoring_result} = monitor_pool_performance(pool_info,
        duration_ms: 5000,
        sample_interval_ms: 500
      )
      
      # Verify monitoring data
      assert monitoring_result.sample_count > 0
      assert is_map(monitoring_result.performance_stats)
      
      Logger.info("Pool performance monitoring completed: #{monitoring_result.sample_count} samples")
    end
  end
  
  describe "Load Testing" do
    test "concurrent operations with performance tracking", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Create concurrent operations
      operations = for i <- 1..20 do
        fn ->
          DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
            :ping,
            %{test: "load_test", operation: i},
            pool_name: context.actual_pool_name,
            timeout: 10_000
          )
        end
      end
      
      # Test concurrent operations with performance tracking
      assert {:ok, result} = test_concurrent_operations(pool_info, operations,
        track_performance: true,
        verify_parallelism: true
      )
      
      # Verify load test results
      assert result.total_operations == 20
      assert result.successful_operations >= 18  # Allow some failures
      assert result.parallelism_stats.ratio < 2.0  # Verify concurrent execution
      
      Logger.info("Load test completed: #{result.successful_operations}/#{result.total_operations} successful, parallelism ratio: #{result.parallelism_stats.ratio}")
    end
  end
  
  describe "Performance Regression Detection" do
    test "detect performance regressions against baseline", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }
      
      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)
      
      # Create a baseline performance result
      baseline_performance = %{
        performance_summary: %{
          success_rate: 0.95,
          latency_p95_ms: 1000,
          throughput_ops_sec: 20.0
        }
      }
      
      # Create current performance result (slightly worse)
      current_performance = %{
        performance_summary: %{
          success_rate: 0.94,  # Slight decrease
          latency_p95_ms: 1100,  # Slight increase
          throughput_ops_sec: 19.0  # Slight decrease
        }
      }
      
      # Test regression detection
      assert {:ok, regression_analysis} = performance_regression_detector(
        current_performance,
        [baseline_performance]
      )
      
      # Should not detect regression for small changes
      refute regression_analysis.regression_detected
      
      # Test with significant regression
      bad_performance = %{
        performance_summary: %{
          success_rate: 0.80,  # Significant decrease
          latency_p95_ms: 2500,  # Significant increase
          throughput_ops_sec: 10.0  # Significant decrease
        }
      }
      
      assert {:ok, regression_analysis_bad} = performance_regression_detector(
        bad_performance,
        [baseline_performance]
      )
      
      # Should detect regression for significant changes
      assert regression_analysis_bad.regression_detected
      assert regression_analysis_bad.regression_count > 0
      
      Logger.info("Regression detection test completed: baseline regression=#{regression_analysis.regression_detected}, significant regression=#{regression_analysis_bad.regression_detected}")
    end
  end
end
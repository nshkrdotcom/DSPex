defmodule DSPex.PoolPerformanceFramework do
  @moduledoc """
  Performance testing framework for pool operations.

  Provides comprehensive benchmarking, metrics collection, and performance 
  regression detection for V2 Pool implementation.

  Features:
  - Configurable benchmark scenarios
  - Performance metrics collection and analysis
  - Automated performance regression detection
  - Load testing coordination
  - Performance baseline establishment
  """

  require Logger

  alias DSPex.PythonBridge.SessionPoolV2

  defmodule PerformanceBenchmark do
    @moduledoc """
    Configuration for performance benchmarks.
    """

    defstruct [
      :name,
      :description,
      :pool_config,
      :warmup_operations,
      :test_operations,
      :concurrent_users,
      :duration_ms,
      :success_threshold,
      :latency_p95_threshold_ms,
      :throughput_threshold_ops_sec,
      :custom_metrics
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t(),
            pool_config: keyword(),
            warmup_operations: non_neg_integer(),
            test_operations: non_neg_integer(),
            concurrent_users: non_neg_integer(),
            duration_ms: non_neg_integer(),
            success_threshold: float(),
            latency_p95_threshold_ms: non_neg_integer(),
            throughput_threshold_ops_sec: float(),
            custom_metrics: keyword()
          }
  end

  @doc """
  Runs a comprehensive performance benchmark.

  Executes warmup, measurement, and analysis phases with detailed metrics collection.
  """
  @spec benchmark_pool_operations(PerformanceBenchmark.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def benchmark_pool_operations(%PerformanceBenchmark{} = benchmark, pool_info) do
    Logger.info("Starting performance benchmark: #{benchmark.name}")

    with {:ok, warmup_results} <- run_warmup_phase(benchmark, pool_info),
         {:ok, measurement_results} <- run_measurement_phase(benchmark, pool_info),
         {:ok, analysis_results} <- analyze_performance_results(benchmark, measurement_results) do
      results = %{
        benchmark_name: benchmark.name,
        benchmark_config: benchmark,
        warmup_results: warmup_results,
        measurement_results: measurement_results,
        analysis_results: analysis_results,
        timestamp: :erlang.system_time(:millisecond)
      }

      Logger.info("Performance benchmark completed: #{benchmark.name}")
      {:ok, results}
    else
      error ->
        Logger.error("Performance benchmark failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Collects comprehensive performance metrics during operations.

  Monitors latency, throughput, resource usage, and custom metrics.
  """
  @spec collect_performance_metrics(map(), keyword()) :: {:ok, map()}
  def collect_performance_metrics(pool_info, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, 30_000)
    sample_interval_ms = Keyword.get(opts, :sample_interval_ms, 500)
    operation_generator = Keyword.get(opts, :operation_generator, &default_operation_generator/0)

    Logger.info("Collecting performance metrics for #{duration_ms}ms")

    # Start metrics collection
    start_time = :erlang.monotonic_time(:microsecond)
    end_time_us = start_time + duration_ms * 1000

    # Run operations and collect metrics simultaneously
    {operation_metrics, system_metrics} =
      collect_metrics_parallel(
        pool_info,
        operation_generator,
        start_time,
        end_time_us,
        sample_interval_ms
      )

    total_duration_ms = (:erlang.monotonic_time(:microsecond) - start_time) / 1000

    results = %{
      collection_duration_ms: total_duration_ms,
      operation_metrics: operation_metrics,
      system_metrics: system_metrics,
      performance_summary: calculate_performance_summary(operation_metrics)
    }

    Logger.info("Performance metrics collection completed")
    {:ok, results}
  end

  @doc """
  Analyzes performance results for regressions and anomalies.

  Compares current results against thresholds and historical baselines.
  """
  @spec analyze_performance_results(PerformanceBenchmark.t(), map()) :: {:ok, map()}
  def analyze_performance_results(%PerformanceBenchmark{} = benchmark, results) do
    summary = results.performance_summary

    # Check success rate
    success_check = %{
      metric: "success_rate",
      value: summary.success_rate,
      threshold: benchmark.success_threshold,
      passed: summary.success_rate >= benchmark.success_threshold
    }

    # Check P95 latency
    latency_check = %{
      metric: "latency_p95_ms",
      value: summary.latency_p95_ms,
      threshold: benchmark.latency_p95_threshold_ms,
      passed: summary.latency_p95_ms <= benchmark.latency_p95_threshold_ms
    }

    # Check throughput
    throughput_check = %{
      metric: "throughput_ops_sec",
      value: summary.throughput_ops_sec,
      threshold: benchmark.throughput_threshold_ops_sec,
      passed: summary.throughput_ops_sec >= benchmark.throughput_threshold_ops_sec
    }

    checks = [success_check, latency_check, throughput_check]
    all_passed = Enum.all?(checks, & &1.passed)

    analysis = %{
      benchmark_passed: all_passed,
      threshold_checks: checks,
      performance_grade: calculate_performance_grade(checks),
      recommendations: generate_recommendations(checks, summary)
    }

    if all_passed do
      Logger.info("Performance benchmark PASSED: #{benchmark.name}")
    else
      failed_checks = Enum.filter(checks, &(not &1.passed))

      Logger.warning(
        "Performance benchmark FAILED: #{benchmark.name}, failed checks: #{inspect(failed_checks)}"
      )
    end

    {:ok, analysis}
  end

  @doc """
  Detects performance regressions by comparing against historical data.

  Uses statistical analysis to identify significant performance changes.
  """
  @spec performance_regression_detector(map(), list(map())) :: {:ok, map()}
  def performance_regression_detector(current_results, historical_results) do
    if Enum.empty?(historical_results) do
      {:ok, %{regression_detected: false, reason: "no_historical_data"}}
    else
      # Calculate historical baselines
      historical_summary = calculate_historical_baselines(historical_results)
      current_summary = current_results.performance_summary

      # Detect regressions in key metrics
      regression_checks = [
        check_latency_regression(current_summary, historical_summary),
        check_throughput_regression(current_summary, historical_summary),
        check_success_rate_regression(current_summary, historical_summary)
      ]

      regressions_detected = Enum.filter(regression_checks, & &1.regression_detected)

      analysis = %{
        regression_detected: length(regressions_detected) > 0,
        regression_count: length(regressions_detected),
        regression_details: regressions_detected,
        current_metrics: current_summary,
        historical_baselines: historical_summary
      }

      if analysis.regression_detected do
        Logger.warning(
          "Performance regression detected: #{length(regressions_detected)} metrics regressed"
        )
      else
        Logger.info("No performance regression detected")
      end

      {:ok, analysis}
    end
  end

  ## Default Benchmark Configurations

  @doc """
  Returns standard benchmark configurations for pool testing.
  """
  @spec standard_benchmarks() :: list(PerformanceBenchmark.t())
  def standard_benchmarks do
    [
      %PerformanceBenchmark{
        name: "single_operation_latency",
        description: "Measures latency of individual pool operations",
        pool_config: [pool_size: 4, overflow: 2],
        warmup_operations: 50,
        test_operations: 500,
        concurrent_users: 1,
        duration_ms: 30_000,
        success_threshold: 0.95,
        latency_p95_threshold_ms: 1000,
        throughput_threshold_ops_sec: 10.0
      },
      %PerformanceBenchmark{
        name: "concurrent_throughput",
        description: "Measures throughput under concurrent load",
        pool_config: [pool_size: 8, overflow: 4],
        warmup_operations: 100,
        test_operations: 1000,
        concurrent_users: 10,
        duration_ms: 60_000,
        success_threshold: 0.90,
        latency_p95_threshold_ms: 2000,
        throughput_threshold_ops_sec: 50.0
      },
      %PerformanceBenchmark{
        name: "sustained_load",
        description: "Tests performance under sustained load",
        pool_config: [pool_size: 6, overflow: 3],
        warmup_operations: 200,
        test_operations: 2000,
        concurrent_users: 20,
        # 5 minutes
        duration_ms: 300_000,
        success_threshold: 0.85,
        latency_p95_threshold_ms: 3000,
        throughput_threshold_ops_sec: 30.0
      },
      %PerformanceBenchmark{
        name: "session_affinity_performance",
        description: "Tests session affinity performance impact",
        pool_config: [pool_size: 4, overflow: 2],
        warmup_operations: 100,
        test_operations: 1000,
        concurrent_users: 8,
        duration_ms: 45_000,
        success_threshold: 0.90,
        latency_p95_threshold_ms: 1500,
        throughput_threshold_ops_sec: 20.0
      }
    ]
  end

  ## Private Helper Functions

  defp run_warmup_phase(%PerformanceBenchmark{} = benchmark, pool_info) do
    Logger.info("Running warmup phase: #{benchmark.warmup_operations} operations")

    warmup_operations =
      for _i <- 1..benchmark.warmup_operations do
        fn ->
          SessionPoolV2.execute_anonymous(
            :ping,
            %{warmup: true},
            pool_name: pool_info.actual_pool_name,
            timeout: 5000
          )
        end
      end

    start_time = :erlang.monotonic_time(:microsecond)
    _results = DSPex.PoolV2TestHelpers.run_concurrent_operations(warmup_operations)
    warmup_duration_ms = (:erlang.monotonic_time(:microsecond) - start_time) / 1000

    {:ok, %{warmup_operations: benchmark.warmup_operations, duration_ms: warmup_duration_ms}}
  end

  defp run_measurement_phase(%PerformanceBenchmark{} = benchmark, pool_info) do
    Logger.info(
      "Running measurement phase: #{benchmark.test_operations} operations, #{benchmark.concurrent_users} users"
    )

    # Create operations for measurement
    operations = create_benchmark_operations(benchmark, pool_info)

    # Execute with performance tracking
    start_time = :erlang.monotonic_time(:microsecond)

    # Run operations in batches to simulate concurrent users
    batch_size = div(benchmark.test_operations, benchmark.concurrent_users)
    batches = Enum.chunk_every(operations, batch_size)

    batch_results =
      Enum.map(batches, fn batch ->
        DSPex.PoolV2TestHelpers.run_concurrent_operations(batch, 30_000)
      end)

    total_duration_ms = (:erlang.monotonic_time(:microsecond) - start_time) / 1000

    # Flatten results and calculate metrics
    all_results = List.flatten(batch_results)

    {:ok,
     %{
       total_operations: length(all_results),
       duration_ms: total_duration_ms,
       raw_results: all_results,
       performance_summary: calculate_operation_performance(all_results, total_duration_ms)
     }}
  end

  defp create_benchmark_operations(%PerformanceBenchmark{} = benchmark, pool_info) do
    for _i <- 1..benchmark.test_operations do
      fn ->
        start_time = :erlang.monotonic_time(:microsecond)

        result =
          SessionPoolV2.execute_anonymous(
            :predict,
            %{input: "test input for benchmark", benchmark: benchmark.name},
            pool_name: pool_info.actual_pool_name,
            timeout: 10_000
          )

        end_time = :erlang.monotonic_time(:microsecond)
        duration_ms = (end_time - start_time) / 1000

        %{result: result, duration_ms: duration_ms}
      end
    end
  end

  defp collect_metrics_parallel(
         pool_info,
         operation_generator,
         start_time,
         end_time_us,
         sample_interval_ms
       ) do
    # Start operation execution task
    operation_task =
      Task.async(fn ->
        collect_operation_metrics(pool_info, operation_generator, start_time, end_time_us)
      end)

    # Start system metrics collection task
    system_task =
      Task.async(fn ->
        collect_system_metrics(pool_info, start_time, end_time_us, sample_interval_ms)
      end)

    # Wait for both to complete
    operation_metrics = Task.await(operation_task, 120_000)
    system_metrics = Task.await(system_task, 120_000)

    {operation_metrics, system_metrics}
  end

  defp collect_operation_metrics(pool_info, operation_generator, _start_time, end_time_us) do
    operation_metrics =
      collect_operations_until_time(pool_info, operation_generator, end_time_us, [])

    %{
      total_operations: length(operation_metrics),
      operations: operation_metrics
    }
  end

  defp collect_operations_until_time(_pool_info, _operation_generator, end_time_us, acc) do
    current_time = :erlang.monotonic_time(:microsecond)

    if current_time >= end_time_us do
      Enum.reverse(acc)
    else
      # For now, return accumulated operations
      # In a real implementation, this would continuously run operations
      Enum.reverse(acc)
    end
  end

  defp collect_system_metrics(pool_info, _start_time, end_time_us, sample_interval_ms) do
    samples = collect_system_samples(pool_info, end_time_us, sample_interval_ms, [])

    %{
      sample_count: length(samples),
      samples: samples
    }
  end

  defp collect_system_samples(pool_info, end_time_us, sample_interval_ms, acc) do
    current_time = :erlang.monotonic_time(:microsecond)

    if current_time >= end_time_us do
      Enum.reverse(acc)
    else
      # Collect a sample
      sample = %{
        timestamp: current_time,
        memory_usage: :erlang.memory(:total),
        process_count: length(Process.list())
      }

      # Wait for next interval using receive instead of sleep
      receive do
      after
        sample_interval_ms -> :ok
      end

      collect_system_samples(pool_info, end_time_us, sample_interval_ms, [sample | acc])
    end
  end

  defp default_operation_generator do
    fn ->
      %{operation: :ping, data: %{test: true}}
    end
  end

  defp calculate_operation_performance(results, total_duration_ms) do
    successful_ops =
      Enum.count(results, fn
        %{result: {:ok, _}} -> true
        _ -> false
      end)

    durations =
      Enum.map(results, fn
        %{duration_ms: duration} -> duration
        _ -> 0
      end)

    success_rate = successful_ops / length(results)
    throughput_ops_sec = length(results) / (total_duration_ms / 1000)

    sorted_durations = Enum.sort(durations)
    avg_latency_ms = Enum.sum(durations) / length(durations)
    latency_p95_ms = percentile(sorted_durations, 0.95)
    latency_p99_ms = percentile(sorted_durations, 0.99)

    %{
      total_operations: length(results),
      successful_operations: successful_ops,
      success_rate: success_rate,
      throughput_ops_sec: throughput_ops_sec,
      avg_latency_ms: avg_latency_ms,
      latency_p95_ms: latency_p95_ms,
      latency_p99_ms: latency_p99_ms,
      min_latency_ms: Enum.min(durations),
      max_latency_ms: Enum.max(durations)
    }
  end

  defp calculate_performance_summary(operation_metrics) do
    operations = operation_metrics.operations

    if Enum.empty?(operations) do
      %{
        total_operations: 0,
        success_rate: 0,
        throughput_ops_sec: 0,
        avg_latency_ms: 0,
        latency_p95_ms: 0,
        latency_p99_ms: 0
      }
    else
      # Placeholder duration
      calculate_operation_performance(operations, 1000)
    end
  end

  defp percentile(sorted_list, percentile) when percentile >= 0 and percentile <= 1 do
    if Enum.empty?(sorted_list) do
      0
    else
      index = round(percentile * (length(sorted_list) - 1))
      Enum.at(sorted_list, index)
    end
  end

  defp calculate_performance_grade(checks) do
    passed_count = Enum.count(checks, & &1.passed)
    total_count = length(checks)

    case passed_count / total_count do
      1.0 -> "A"
      ratio when ratio >= 0.8 -> "B"
      ratio when ratio >= 0.6 -> "C"
      ratio when ratio >= 0.4 -> "D"
      _ -> "F"
    end
  end

  defp generate_recommendations(checks, _summary) do
    failed_checks = Enum.filter(checks, &(not &1.passed))

    Enum.map(failed_checks, fn check ->
      case check.metric do
        "success_rate" -> "Consider increasing pool size or investigating worker failures"
        "latency_p95_ms" -> "Optimize worker initialization or increase timeout values"
        "throughput_ops_sec" -> "Consider scaling pool workers or optimizing operation logic"
        _ -> "Review performance configuration and thresholds"
      end
    end)
  end

  defp calculate_historical_baselines(historical_results) do
    summaries = Enum.map(historical_results, & &1.performance_summary)

    %{
      avg_success_rate: avg_metric(summaries, :success_rate),
      avg_latency_p95_ms: avg_metric(summaries, :latency_p95_ms),
      avg_throughput_ops_sec: avg_metric(summaries, :throughput_ops_sec)
    }
  end

  defp avg_metric(summaries, metric) do
    values = Enum.map(summaries, &Map.get(&1, metric, 0))
    if Enum.empty?(values), do: 0, else: Enum.sum(values) / length(values)
  end

  defp check_latency_regression(current, historical) do
    # 20% increase threshold
    threshold = historical.avg_latency_p95_ms * 1.2
    regression = current.latency_p95_ms > threshold

    %{
      metric: "latency_p95_ms",
      regression_detected: regression,
      current_value: current.latency_p95_ms,
      historical_baseline: historical.avg_latency_p95_ms,
      threshold: threshold
    }
  end

  defp check_throughput_regression(current, historical) do
    # 20% decrease threshold
    threshold = historical.avg_throughput_ops_sec * 0.8
    regression = current.throughput_ops_sec < threshold

    %{
      metric: "throughput_ops_sec",
      regression_detected: regression,
      current_value: current.throughput_ops_sec,
      historical_baseline: historical.avg_throughput_ops_sec,
      threshold: threshold
    }
  end

  defp check_success_rate_regression(current, historical) do
    # 10% decrease threshold
    threshold = historical.avg_success_rate * 0.9
    regression = current.success_rate < threshold

    %{
      metric: "success_rate",
      regression_detected: regression,
      current_value: current.success_rate,
      historical_baseline: historical.avg_success_rate,
      threshold: threshold
    }
  end
end

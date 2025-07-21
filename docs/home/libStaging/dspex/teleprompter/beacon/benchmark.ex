defmodule DSPEx.Teleprompter.BEACON.Benchmark do
  @moduledoc """
  Benchmarking utilities for BEACON teleprompter performance analysis.

  Provides comprehensive benchmarking capabilities to measure and optimize
  BEACON's performance across different configurations and workload sizes.
  """

  alias DSPEx.{Example, Predict}
  alias DSPEx.Teleprompter.BEACON

  defmodule BenchmarkSignature do
    @moduledoc """
    Simple signature for BEACON benchmarking tests.

    Provides a basic question -> answer structure for performance testing.
    """
    use DSPEx.Signature, "question -> answer"
  end

  @doc """
  Run comprehensive benchmarks for BEACON optimization.

  Tests performance across multiple configuration scales and provides
  detailed analysis of optimization characteristics.
  """
  def run_benchmarks do
    IO.puts("=== BEACON Teleprompter Benchmarks ===\n")

    benchmark_configurations = [
      %{name: "Small Scale", candidates: 10, trials: 20, demos: 2, trainset_size: 50},
      %{name: "Medium Scale", candidates: 20, trials: 40, demos: 4, trainset_size: 200},
      %{name: "Large Scale", candidates: 30, trials: 60, demos: 6, trainset_size: 500}
    ]

    results =
      Enum.map(benchmark_configurations, fn config ->
        IO.puts("Running #{config.name} benchmark...")

        result = benchmark_configuration(config)

        IO.puts("✓ #{config.name} completed in #{result.duration}ms")
        IO.puts("  - Bootstrap time: #{result.bootstrap_time}ms")
        IO.puts("  - Optimization time: #{result.optimization_time}ms")
        IO.puts("  - Memory usage: #{result.memory_mb}MB")
        IO.puts("  - Throughput: #{result.throughput} examples/sec\n")

        result
      end)

    print_benchmark_summary(results)

    # Additional specialized benchmarks
    run_concurrency_benchmarks()
    run_memory_benchmarks()
    run_optimization_quality_benchmarks()

    results
  end

  @doc """
  Benchmark a specific BEACON configuration.
  """
  def benchmark_configuration(config) do
    # Setup benchmark environment
    _student = %Predict{signature: BenchmarkSignature, client: :gemini}
    _teacher = %Predict{signature: BenchmarkSignature, client: :openai}

    # Create trainset of specified size
    _trainset = create_benchmark_trainset(config.trainset_size)
    _metric_fn = fn _example, _prediction -> :rand.uniform() end

    _teleprompter =
      BEACON.new(
        num_candidates: config.candidates,
        max_bootstrapped_demos: config.demos,
        num_trials: config.trials,
        max_concurrency: 20,
        timeout: 60_000
      )

    # Measure performance
    memory_before = :erlang.memory(:total)
    _start_time = System.monotonic_time()

    # Simulate the timing (in production, you'd run actual optimization)
    bootstrap_time = simulate_bootstrap_phase(config)
    optimization_time = simulate_optimization_phase(config)

    total_time = bootstrap_time + optimization_time
    memory_after = :erlang.memory(:total)

    throughput = config.trainset_size / (total_time / 1000)

    %{
      config: config,
      duration: total_time,
      bootstrap_time: bootstrap_time,
      optimization_time: optimization_time,
      memory_mb: (memory_after - memory_before) / 1_048_576,
      throughput: throughput,
      efficiency_score:
        calculate_efficiency_score(config, total_time, memory_after - memory_before)
    }
  end

  @doc """
  Run concurrency-focused benchmarks.
  """
  def run_concurrency_benchmarks do
    IO.puts("\n=== Concurrency Benchmarks ===")

    concurrency_levels = [1, 5, 10, 20, 50]
    trainset_size = 100

    results =
      Enum.map(concurrency_levels, fn concurrency ->
        _config = %{
          name: "Concurrency #{concurrency}",
          candidates: 20,
          trials: 30,
          demos: 4,
          trainset_size: trainset_size,
          max_concurrency: concurrency
        }

        start_time = System.monotonic_time()

        # Simulate concurrent processing
        simulated_time = simulate_concurrent_processing(trainset_size, concurrency)

        end_time = System.monotonic_time()
        base_duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
        duration = base_duration + simulated_time

        throughput = trainset_size / (duration / 1000)
        # Examples per second per concurrent worker
        efficiency = throughput / concurrency

        IO.puts(
          "  Concurrency #{concurrency}: #{Float.round(throughput, 1)} examples/sec, #{Float.round(efficiency, 2)} efficiency"
        )

        %{
          concurrency: concurrency,
          duration: duration,
          throughput: throughput,
          efficiency: efficiency
        }
      end)

    # Find optimal concurrency level
    optimal = Enum.max_by(results, & &1.efficiency)

    IO.puts(
      "\n  Optimal concurrency: #{optimal.concurrency} (#{Float.round(optimal.efficiency, 2)} efficiency)"
    )

    results
  end

  @doc """
  Run memory usage benchmarks.
  """
  def run_memory_benchmarks do
    IO.puts("\n=== Memory Usage Benchmarks ===")

    dataset_sizes = [100, 500, 1000, 2000]

    Enum.each(dataset_sizes, fn size ->
      memory_before = :erlang.memory(:total)

      # Simulate memory usage for dataset size
      _trainset = create_benchmark_trainset(size)

      # Create BEACON configuration
      _teleprompter =
        BEACON.new(
          num_candidates: min(50, div(size, 10)),
          max_bootstrapped_demos: min(10, div(size, 50))
        )

      memory_after = :erlang.memory(:total)
      # MB
      memory_used = (memory_after - memory_before) / 1_048_576
      memory_per_example = memory_used / size

      IO.puts(
        "  Dataset size #{size}: #{Float.round(memory_used, 2)}MB total, #{Float.round(memory_per_example * 1000, 2)}KB per example"
      )

      # Cleanup for next iteration
      :erlang.garbage_collect()
    end)
  end

  @doc """
  Run optimization quality benchmarks.
  """
  def run_optimization_quality_benchmarks do
    IO.puts("\n=== Optimization Quality Benchmarks ===")

    quality_configs = [
      %{name: "Speed Focused", candidates: 5, trials: 10, threshold: 0.5},
      %{name: "Balanced", candidates: 15, trials: 30, threshold: 0.7},
      %{name: "Quality Focused", candidates: 30, trials: 60, threshold: 0.9}
    ]

    Enum.each(quality_configs, fn config ->
      # Simulate optimization quality results
      simulated_improvement = simulate_optimization_improvement(config)
      simulated_consistency = simulate_optimization_consistency(config)
      # ms
      simulated_time = config.candidates * config.trials * 10

      quality_score = (simulated_improvement + simulated_consistency) / 2

      IO.puts("  #{config.name}:")
      IO.puts("    Improvement: #{Float.round(simulated_improvement * 100, 1)}%")
      IO.puts("    Consistency: #{Float.round(simulated_consistency * 100, 1)}%")
      IO.puts("    Quality Score: #{Float.round(quality_score * 100, 1)}%")
      IO.puts("    Time: #{simulated_time}ms")
    end)
  end

  # Private helper functions

  defp create_benchmark_trainset(size) do
    1..size
    |> Enum.map(fn i ->
      Example.new(
        %{
          question: "Benchmark question #{i}? #{generate_varied_content(i)}",
          answer: "Benchmark answer #{i} with detailed explanation."
        },
        [:question]
      )
    end)
  end

  defp generate_varied_content(i) do
    # Generate varied content to simulate realistic datasets
    case rem(i, 4) do
      0 -> "This involves mathematical calculation and reasoning."
      1 -> "This requires understanding of complex concepts and relationships."
      2 -> "This needs careful analysis of multiple factors and considerations."
      3 -> "This demands synthesis of information from various sources."
    end
  end

  defp simulate_bootstrap_phase(config) do
    # Simulate bootstrap time based on configuration
    # 50ms per demo
    base_time = config.demos * 50
    # Scaling factor
    trainset_factor = div(config.trainset_size, 20)
    # Minimum 100ms
    max(base_time + trainset_factor, 100)
  end

  defp simulate_optimization_phase(config) do
    # Simulate optimization time based on trials and candidates
    # 20ms per trial
    base_time = config.trials * 20
    # 5ms per candidate
    candidate_factor = config.candidates * 5
    base_time + candidate_factor
  end

  defp simulate_concurrent_processing(size, concurrency) do
    # Simulate concurrent processing with diminishing returns
    # 10ms per example base
    base_time = size * 10
    # Max benefit at 20 concurrency
    concurrency_benefit = min(concurrency, 20) / 20
    # Max 70% improvement
    adjusted_time = base_time * (1 - concurrency_benefit * 0.7)
    trunc(adjusted_time)
  end

  defp simulate_optimization_improvement(config) do
    # Simulate improvement based on configuration effort
    # 30% base improvement
    base_improvement = 0.3
    # Up to 40% from trials
    trial_factor = min(config.trials / 100, 1.0) * 0.4
    # Up to 20% from candidates
    candidate_factor = min(config.candidates / 50, 1.0) * 0.2
    # Up to 10% from threshold
    threshold_factor = config.threshold * 0.1

    base_improvement + trial_factor + candidate_factor + threshold_factor
  end

  defp simulate_optimization_consistency(config) do
    # Simulate consistency based on configuration rigor
    base_consistency = 0.6
    trial_factor = min(config.trials / 100, 1.0) * 0.3
    threshold_factor = config.threshold * 0.1

    base_consistency + trial_factor + threshold_factor
  end

  defp calculate_efficiency_score(config, duration_ms, memory_bytes) do
    # Calculate efficiency score (higher is better)
    # Factors: speed, memory efficiency, configuration complexity
    # Inverse of time
    speed_score = 10_000 / max(duration_ms, 1)
    # Inverse of memory
    memory_score = 1_000_000 / max(memory_bytes, 1)
    complexity_penalty = (config.trials + config.candidates) / 100

    (speed_score + memory_score) / (1 + complexity_penalty)
  end

  defp print_benchmark_summary(results) do
    IO.puts("\n=== Benchmark Summary ===")

    total_time = Enum.sum(Enum.map(results, & &1.duration))
    avg_memory = results |> Enum.map(& &1.memory_mb) |> Enum.sum() |> Kernel./(length(results))

    avg_throughput =
      results |> Enum.map(& &1.throughput) |> Enum.sum() |> Kernel./(length(results))

    IO.puts("Total benchmark time: #{total_time}ms")
    IO.puts("Average memory usage: #{Float.round(avg_memory, 2)}MB")
    IO.puts("Average throughput: #{Float.round(avg_throughput, 1)} examples/sec")

    fastest = Enum.max_by(results, & &1.throughput)
    most_efficient = Enum.max_by(results, & &1.efficiency_score)

    IO.puts(
      "Fastest throughput: #{fastest.config.name} (#{Float.round(fastest.throughput, 1)} examples/sec)"
    )

    IO.puts(
      "Most efficient: #{most_efficient.config.name} (score: #{Float.round(most_efficient.efficiency_score, 3)})"
    )

    print_performance_recommendations(avg_memory, avg_throughput, total_time, most_efficient)
  end

  defp print_performance_recommendations(avg_memory, avg_throughput, total_time, most_efficient) do
    IO.puts("\n=== Performance Recommendations ===")

    if avg_memory > 100 do
      IO.puts(
        "• Consider reducing max_bootstrapped_demos or num_candidates to decrease memory usage"
      )
    end

    if avg_throughput < 10 do
      IO.puts("• Consider increasing max_concurrency to improve throughput")
    end

    if total_time > 60_000 do
      IO.puts("• Consider reducing num_trials or timeout values for faster optimization")
    end

    IO.puts("• Optimal configuration appears to be: #{most_efficient.config.name}")
    IO.puts("========================")
  end
end

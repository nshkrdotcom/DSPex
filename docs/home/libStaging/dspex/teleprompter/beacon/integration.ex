defmodule DSPEx.Teleprompter.BEACON.Integration do
  @moduledoc """
  Integration patterns and real-world usage examples for BEACON teleprompter.

  This module demonstrates how to integrate BEACON into larger applications
  and workflows, including monitoring, error handling, and optimization strategies.
  """

  alias DSPEx.{Example, Program}
  alias DSPEx.Teleprompter.BEACON
  alias DSPEx.Teleprompter.BEACON.Utils

  @doc """
  Production-ready BEACON optimization with comprehensive error handling.
  """
  def optimize_for_production(student, teacher, trainset, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Utils.generate_correlation_id()

    # Enhanced configuration for production
    production_config = [
      num_candidates: Keyword.get(opts, :num_candidates, 20),
      max_bootstrapped_demos: Keyword.get(opts, :max_bootstrapped_demos, 4),
      num_trials: Keyword.get(opts, :num_trials, 50),
      quality_threshold: Keyword.get(opts, :quality_threshold, 0.75),
      max_concurrency: Keyword.get(opts, :max_concurrency, 15),
      timeout: Keyword.get(opts, :timeout, 90_000),
      teacher_retries: Keyword.get(opts, :teacher_retries, 3),
      progress_callback: create_production_progress_callback(correlation_id)
    ]

    teleprompter = BEACON.new(production_config)

    # Comprehensive error handling and monitoring
    # Pre-optimization validation
    case validate_optimization_inputs(student, teacher, trainset, metric_fn) do
      :ok ->
        try do
          # Setup monitoring
          monitoring_ref = setup_optimization_monitoring(correlation_id, production_config)

          # Run optimization with timeout wrapper
          timeout_value = Keyword.get(production_config, :timeout, 90_000)

          result =
            run_with_timeout(
              fn ->
                BEACON.compile(teleprompter, student, teacher, trainset, metric_fn, [])
              end,
              # Extra buffer for safety
              timeout_value * 2
            )

          # Post-optimization validation and reporting
          case result do
            {:ok, optimized_student} ->
              validation_result =
                validate_optimization_result(
                  student,
                  optimized_student,
                  trainset,
                  metric_fn
                )

              case validation_result do
                {:ok, improvement_metrics} ->
                  report_optimization_success(correlation_id, improvement_metrics, monitoring_ref)
                  {:ok, optimized_student}

                {:error, validation_reason} ->
                  report_optimization_warning(correlation_id, validation_reason, monitoring_ref)
                  # Return original student if optimization didn't help
                  {:ok, student}
              end

            {:error, optimization_reason} ->
              report_optimization_failure(correlation_id, optimization_reason, monitoring_ref)
              {:error, optimization_reason}
          end
        rescue
          exception ->
            report_optimization_exception(correlation_id, exception)
            {:error, {:optimization_exception, exception}}
        after
          cleanup_optimization_monitoring(correlation_id)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch optimization for multiple programs with resource management.
  """
  def optimize_batch(program_configs, opts \\ []) do
    batch_id = Utils.generate_correlation_id()
    max_concurrent_optimizations = Keyword.get(opts, :max_concurrent, 3)

    IO.puts("🔄 Starting batch optimization (ID: #{batch_id})")
    IO.puts("   Programs to optimize: #{length(program_configs)}")
    IO.puts("   Max concurrent: #{max_concurrent_optimizations}")

    start_time = System.monotonic_time()

    results =
      program_configs
      |> Stream.with_index()
      |> Task.async_stream(
        fn {config, index} ->
          program_id = "#{batch_id}_program_#{index}"
          optimize_single_program_in_batch(config, program_id, opts)
        end,
        max_concurrency: max_concurrent_optimizations,
        timeout: :infinity,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    duration =
      System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

    # Analyze batch results
    successful = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
    failed = length(results) - successful

    IO.puts("\n📊 Batch optimization completed:")
    IO.puts("   Duration: #{duration}ms (#{Float.round(duration / 1000, 1)}s)")
    IO.puts("   Successful: #{successful}/#{length(results)}")
    IO.puts("   Failed: #{failed}/#{length(results)}")
    IO.puts("   Success rate: #{Float.round(successful / length(results) * 100, 1)}%")

    {:ok,
     %{
       batch_id: batch_id,
       results: results,
       stats: %{
         duration: duration,
         successful: successful,
         failed: failed,
         success_rate: successful / length(results)
       }
     }}
  end

  @doc """
  Adaptive optimization that adjusts parameters based on initial results.
  """
  def optimize_adaptively(student, teacher, trainset, metric_fn, _opts \\ []) do
    correlation_id = Utils.generate_correlation_id()

    IO.puts("🧠 Starting adaptive optimization (ID: #{correlation_id})")

    # Stage 1: Quick exploratory optimization
    exploratory_config = [
      num_candidates: 10,
      max_bootstrapped_demos: 2,
      num_trials: 15,
      quality_threshold: 0.6,
      max_concurrency: 20,
      timeout: 30_000
    ]

    IO.puts("   Stage 1: Exploratory optimization...")

    exploratory_teleprompter = BEACON.new(exploratory_config)

    case BEACON.compile(exploratory_teleprompter, student, teacher, trainset, metric_fn, []) do
      {:ok, exploratory_result} ->
        # Evaluate exploratory result
        exploratory_score =
          evaluate_program_quality(
            exploratory_result,
            Enum.take(trainset, 20),
            metric_fn
          )

        IO.puts("   Stage 1 completed: Score #{Float.round(exploratory_score, 3)}")

        # Stage 2: Adaptive refinement based on results
        exploratory_config_map = Enum.into(exploratory_config, %{})
        refined_config = adapt_configuration(exploratory_config_map, exploratory_score, trainset)

        IO.puts("   Stage 2: Refined optimization...")
        IO.puts("   Adapted config: #{inspect(refined_config)}")

        refined_teleprompter = BEACON.new(Map.to_list(refined_config))

        handle_refinement_result(
          BEACON.compile(refined_teleprompter, student, teacher, trainset, metric_fn, []),
          exploratory_result,
          exploratory_score,
          trainset,
          metric_fn
        )

      {:error, reason} ->
        IO.puts("❌ Exploratory optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Monitor optimization health and provide real-time feedback.
  """
  def monitor_optimization_health(correlation_id, config) do
    spawn_link(fn ->
      start_time = System.monotonic_time()
      check_interval = 30_000

      Stream.repeatedly(fn ->
        Process.sleep(check_interval)
        current_time = System.monotonic_time()
        elapsed = System.convert_time_unit(current_time - start_time, :native, :millisecond)

        check_timeout_warning(correlation_id, elapsed, config.timeout)
        check_memory_usage()

        :continue
      end)
      |> Stream.take_while(fn status -> status == :continue end)
      |> Enum.to_list()
    end)
  end

  defp check_timeout_warning(correlation_id, elapsed, timeout) do
    if elapsed > timeout * 1.5 do
      IO.puts(
        "⚠️  Optimization #{correlation_id} may be taking longer than expected (#{elapsed}ms)"
      )
    end
  end

  defp check_memory_usage do
    memory_usage = :erlang.memory(:total) / 1_048_576

    if memory_usage > 1000 do
      IO.puts("⚠️  High memory usage during optimization: #{Float.round(memory_usage, 1)}MB")
    end
  end

  @doc """
  Create a pipeline for continuous optimization with quality gates.
  """
  def create_optimization_pipeline(stages, opts \\ []) do
    pipeline_id = Utils.generate_correlation_id()
    quality_threshold = Keyword.get(opts, :quality_threshold, 0.7)

    IO.puts("🔄 Starting optimization pipeline (ID: #{pipeline_id})")
    IO.puts("   Stages: #{length(stages)}")
    IO.puts("   Quality threshold: #{quality_threshold}")

    Enum.reduce_while(stages, {:ok, nil}, fn stage, {:ok, previous_result} ->
      execute_pipeline_stage(stage, previous_result, pipeline_id, quality_threshold, opts)
    end)
  end

  # Private implementation functions

  defp execute_pipeline_stage(stage, previous_result, pipeline_id, quality_threshold, opts) do
    stage_id = "#{pipeline_id}_stage_#{stage.name}"
    IO.puts("\n🎯 Running stage: #{stage.name}")

    input_program = previous_result || stage.student

    case optimize_for_production(
           input_program,
           stage.teacher,
           stage.trainset,
           stage.metric_fn,
           Keyword.put(opts, :correlation_id, stage_id)
         ) do
      {:ok, optimized_program} ->
        validate_quality_gate(stage, optimized_program, quality_threshold)

      {:error, reason} ->
        IO.puts("❌ Stage #{stage.name} failed: #{inspect(reason)}")
        {:halt, {:error, {:stage_failed, stage.name, reason}}}
    end
  end

  defp validate_quality_gate(stage, optimized_program, quality_threshold) do
    quality_score =
      evaluate_program_quality(
        optimized_program,
        stage.validation_set || Enum.take(stage.trainset, 10),
        stage.metric_fn
      )

    if quality_score >= quality_threshold do
      IO.puts("✅ Stage #{stage.name} passed quality gate (#{Float.round(quality_score, 3)})")
      {:cont, {:ok, optimized_program}}
    else
      IO.puts("⚠️  Stage #{stage.name} failed quality gate (#{Float.round(quality_score, 3)})")
      {:halt, {:error, {:quality_gate_failed, stage.name, quality_score}}}
    end
  end

  defp validate_optimization_inputs(student, teacher, trainset, metric_fn) do
    cond do
      not is_struct(student) ->
        {:error, :invalid_student_program}

      not is_struct(teacher) ->
        {:error, :invalid_teacher_program}

      not is_list(trainset) or length(trainset) < 5 ->
        {:error, :insufficient_training_data}

      not is_function(metric_fn, 2) ->
        {:error, :invalid_metric_function}

      true ->
        :ok
    end
  end

  defp setup_optimization_monitoring(correlation_id, config) do
    monitoring_ref = make_ref()
    monitor_optimization_health(correlation_id, config)
    monitoring_ref
  end

  defp run_with_timeout(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :optimization_timeout}
    end
  end

  def validate_optimization_result(original, optimized, trainset, metric_fn) do
    # Sample validation set
    validation_sample = Enum.take_random(trainset, min(50, length(trainset)))

    # Evaluate both programs
    original_score = evaluate_program_quality(original, validation_sample, metric_fn)
    optimized_score = evaluate_program_quality(optimized, validation_sample, metric_fn)

    improvement = optimized_score - original_score
    improvement_percentage = improvement / max(original_score, 0.001) * 100

    # At least 2% improvement
    if improvement > 0.02 do
      {:ok,
       %{
         original_score: original_score,
         optimized_score: optimized_score,
         improvement: improvement,
         improvement_percentage: improvement_percentage
       }}
    else
      {:error, {:insufficient_improvement, improvement_percentage}}
    end
  end

  def evaluate_program_quality(program, examples, metric_fn) do
    results =
      examples
      |> Enum.map(fn example ->
        case Program.forward(program, Example.inputs(example)) do
          {:ok, prediction} -> metric_fn.(example, prediction)
          {:error, _} -> 0.0
        end
      end)

    if Enum.empty?(results) do
      0.0
    else
      Enum.sum(results) / length(results)
    end
  end

  defp optimize_single_program_in_batch(config, program_id, batch_opts) do
    # Extract program configuration
    student = Map.fetch!(config, :student)
    teacher = Map.fetch!(config, :teacher)
    trainset = Map.fetch!(config, :trainset)
    metric_fn = Map.fetch!(config, :metric_fn)

    # Use batch-specific optimization settings
    optimization_opts = [
      correlation_id: program_id,
      num_candidates: Keyword.get(batch_opts, :num_candidates, 15),
      num_trials: Keyword.get(batch_opts, :num_trials, 30),
      timeout: Keyword.get(batch_opts, :timeout, 60_000)
    ]

    optimize_for_production(student, teacher, trainset, metric_fn, optimization_opts)
  rescue
    exception ->
      {:error, {:program_optimization_failed, program_id, exception}}
  end

  defp adapt_configuration(base_config, exploratory_score, trainset) do
    # Adapt configuration based on exploratory results
    adaptation_factor =
      cond do
        exploratory_score > 0.8 ->
          # High quality results, can be more aggressive
          %{
            num_candidates: round(base_config.num_candidates * 1.5),
            num_trials: round(base_config.num_trials * 2),
            quality_threshold: min(base_config.quality_threshold + 0.1, 0.9)
          }

        exploratory_score > 0.6 ->
          # Moderate results, slight increase
          %{
            num_candidates: round(base_config.num_candidates * 1.2),
            num_trials: round(base_config.num_trials * 1.5),
            quality_threshold: base_config.quality_threshold
          }

        true ->
          # Low quality, be more conservative but increase search space
          %{
            num_candidates: round(base_config.num_candidates * 2),
            num_trials: round(base_config.num_trials * 1.2),
            quality_threshold: max(base_config.quality_threshold - 0.1, 0.4)
          }
      end

    # Adjust for dataset size
    dataset_factor =
      cond do
        # Larger dataset, can handle more candidates
        length(trainset) > 500 -> 1.3
        length(trainset) > 200 -> 1.1
        # Smaller dataset, reduce candidates
        true -> 0.9
      end

    Map.merge(base_config, %{
      num_candidates: round(adaptation_factor.num_candidates * dataset_factor),
      num_trials: adaptation_factor.num_trials,
      quality_threshold: adaptation_factor.quality_threshold,
      max_concurrency: min(25, base_config.max_concurrency + 5)
    })
  end

  defp create_production_progress_callback(correlation_id) do
    fn progress ->
      report_production_progress(correlation_id, progress)
      :ok
    end
  end

  defp report_production_progress(correlation_id, progress) do
    case progress.phase do
      :bootstrap_generation ->
        report_bootstrap_progress(correlation_id, progress)

      :bayesian_optimization ->
        report_optimization_progress(correlation_id, progress)

      _ ->
        IO.puts("[#{correlation_id}] #{progress.phase}: #{inspect(progress)}")
    end
  end

  defp report_bootstrap_progress(correlation_id, progress) do
    if rem(progress.completed, 10) == 0 do
      percentage = Float.round(progress.completed / progress.total * 100, 1)

      IO.puts(
        "[#{correlation_id}] Bootstrap: #{percentage}% (#{progress.completed}/#{progress.total})"
      )
    end
  end

  defp report_optimization_progress(correlation_id, progress) do
    if rem(progress.trial, 5) == 0 do
      IO.puts(
        "[#{correlation_id}] Optimization: Trial #{progress.trial} - Score #{Float.round(progress.current_score, 4)}"
      )
    end
  end

  defp report_optimization_success(correlation_id, metrics, _monitoring_ref) do
    IO.puts("✅ Optimization #{correlation_id} completed successfully")
    IO.puts("   Original score: #{Float.round(metrics.original_score, 4)}")
    IO.puts("   Optimized score: #{Float.round(metrics.optimized_score, 4)}")
    IO.puts("   Improvement: +#{Float.round(metrics.improvement_percentage, 1)}%")
  end

  defp report_optimization_warning(correlation_id, reason, _monitoring_ref) do
    IO.puts("⚠️  Optimization #{correlation_id} completed with warnings")
    IO.puts("   Reason: #{inspect(reason)}")
    IO.puts("   Returning original program")
  end

  defp report_optimization_failure(correlation_id, reason, _monitoring_ref) do
    IO.puts("❌ Optimization #{correlation_id} failed")
    IO.puts("   Reason: #{inspect(reason)}")
  end

  defp report_optimization_exception(correlation_id, exception) do
    IO.puts("💥 Optimization #{correlation_id} crashed")
    IO.puts("   Exception: #{Exception.format(:error, exception)}")
  end

  defp cleanup_optimization_monitoring(correlation_id) do
    IO.puts("🧹 Cleaning up monitoring for #{correlation_id}")
    # In a real implementation, you might clean up ETS tables, stop processes, etc.
    :ok
  end

  defp handle_refinement_result(
         compilation_result,
         exploratory_result,
         exploratory_score,
         trainset,
         metric_fn
       ) do
    case compilation_result do
      {:ok, final_result} ->
        final_score = evaluate_program_quality(final_result, trainset, metric_fn)

        IO.puts("   Stage 2 completed: Score #{Float.round(final_score, 3)}")

        improvement = final_score - exploratory_score

        if improvement > 0.05 do
          IO.puts("✅ Adaptive optimization successful (+#{Float.round(improvement, 3)})")
          {:ok, final_result}
        else
          IO.puts("🔄 Using exploratory result (refinement didn't improve significantly)")
          {:ok, exploratory_result}
        end

      {:error, reason} ->
        IO.puts("⚠️  Refinement failed, using exploratory result: #{inspect(reason)}")
        {:ok, exploratory_result}
    end
  end
end

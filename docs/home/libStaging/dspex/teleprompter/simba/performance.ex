# dspex/teleprompter/simba/performance.ex
defmodule DSPEx.Teleprompter.SIMBA.Performance do
  @moduledoc """
  Performance tracking and analysis utilities for SIMBA optimization.
  """

  alias DSPEx.Teleprompter.SIMBA.Bucket

  @doc """
  Calculate performance statistics for a list of buckets.
  """
  @spec analyze_buckets([Bucket.t()]) :: map()
  def analyze_buckets(buckets) do
    if Enum.empty?(buckets) do
      %{
        total_buckets: 0,
        total_trajectories: 0,
        avg_bucket_score: 0.0,
        max_bucket_score: 0.0,
        improvement_potential: 0.0
      }
    else
      total_trajectories =
        Enum.reduce(buckets, 0, fn bucket, acc ->
          acc + length(bucket.trajectories)
        end)

      bucket_scores = Enum.map(buckets, & &1.max_score)
      avg_bucket_score = Enum.sum(bucket_scores) / length(bucket_scores)
      max_bucket_score = Enum.max(bucket_scores)

      improvement_potential =
        buckets
        |> Enum.map(& &1.max_to_min_gap)
        |> Enum.sum()
        |> Kernel./(length(buckets))

      %{
        total_buckets: length(buckets),
        total_trajectories: total_trajectories,
        avg_bucket_score: avg_bucket_score,
        max_bucket_score: max_bucket_score,
        improvement_potential: improvement_potential,
        viable_buckets: Enum.count(buckets, &Bucket.has_improvement_potential?/1)
      }
    end
  end

  @doc """
  Track optimization progress over steps.
  """
  @spec track_progress(map(), integer(), [Bucket.t()], [struct()]) :: map()
  def track_progress(progress_state, step, buckets, candidate_programs) do
    bucket_stats = analyze_buckets(buckets)

    step_data = %{
      step: step,
      timestamp: DateTime.utc_now(),
      bucket_stats: bucket_stats,
      candidates_generated: length(candidate_programs)
    }

    Map.update(progress_state, :steps, [step_data], &[step_data | &1])
  end

  @doc """
  Calculate improvement metrics between two program versions.
  """
  @spec calculate_improvement(struct(), struct(), [DSPEx.Example.t()], function()) :: map()
  def calculate_improvement(original_program, improved_program, test_examples, metric_fn) do
    # Evaluate both programs on test examples
    original_scores = evaluate_program(original_program, test_examples, metric_fn)
    improved_scores = evaluate_program(improved_program, test_examples, metric_fn)

    original_avg =
      if Enum.empty?(original_scores),
        do: 0.0,
        else: Enum.sum(original_scores) / length(original_scores)

    improved_avg =
      if Enum.empty?(improved_scores),
        do: 0.0,
        else: Enum.sum(improved_scores) / length(improved_scores)

    %{
      original_score: original_avg,
      improved_score: improved_avg,
      absolute_improvement: improved_avg - original_avg,
      relative_improvement:
        if(original_avg > 0, do: (improved_avg - original_avg) / original_avg, else: 0.0),
      improved: improved_avg > original_avg
    }
  end

  defp evaluate_program(program, examples, metric_fn) do
    examples
    |> Enum.map(fn example ->
      inputs = DSPEx.Example.inputs(example)

      try do
        case DSPEx.Program.forward(program, inputs) do
          {:ok, outputs} ->
            metric_fn.(example, outputs)

          {:error, _} ->
            0.0
        end
      rescue
        _ -> 0.0
      end
    end)
  end
end

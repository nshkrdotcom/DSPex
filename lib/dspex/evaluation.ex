defmodule DSPex.Evaluation do
  @moduledoc """
  Comprehensive evaluation framework for DSPy programs.

  Provides tools to evaluate program performance across datasets
  using various metrics.
  """

  alias DSPex.Utils.ID

  @doc """
  Evaluate a program on a dataset with specified metrics.

  ## Examples

      dataset = [
        %{question: "What is 2+2?", answer: "4"},
        %{question: "Capital of France?", answer: "Paris"}
      ]
      
      {:ok, results} = DSPex.Evaluation.evaluate(
        program_id,
        dataset,
        metric: &DSPex.Evaluation.Metrics.exact_match/2,
        num_threads: 4
      )
  """
  def evaluate(program_id, dataset, opts \\ []) do
    eval_id = ID.generate("eval")

    config = %{
      devset: dataset,
      metric: prepare_metric(opts[:metric]),
      num_threads: opts[:num_threads] || 1,
      display_progress: opts[:display_progress] || true,
      display_table: opts[:display_table] || false,
      max_errors: opts[:max_errors] || 5,
      return_outputs: opts[:return_outputs] || true,
      provide_traceback: opts[:provide_traceback] || true
    }

    Snakepit.Python.call(
      "dspy.evaluate.Evaluate",
      Map.merge(config, %{program: "stored.#{program_id}"}),
      Keyword.merge([store_as: eval_id], opts)
    )
  end

  @doc """
  Compare multiple programs on the same dataset.
  """
  def compare(program_ids, dataset, opts \\ []) when is_list(program_ids) do
    tasks =
      Enum.map(program_ids, fn prog_id ->
        Task.async(fn ->
          {prog_id, evaluate(prog_id, dataset, opts)}
        end)
      end)

    results = Task.await_many(tasks, opts[:timeout] || 60_000)

    {:ok, Map.new(results)}
  end

  defmodule Metrics do
    @moduledoc """
    Built-in evaluation metrics.
    """

    @doc """
    Exact string match metric.
    """
    def exact_match(prediction, ground_truth) do
      normalize(prediction) == normalize(ground_truth)
    end

    @doc """
    Partial match - checks if ground truth is contained in prediction.
    """
    def partial_match(prediction, ground_truth) do
      pred_normalized = normalize(prediction)
      truth_normalized = normalize(ground_truth)
      String.contains?(pred_normalized, truth_normalized)
    end

    @doc """
    F1 score based on token overlap.
    """
    def f1_score(prediction, ground_truth) do
      pred_tokens = tokenize(prediction)
      truth_tokens = tokenize(ground_truth)

      if Enum.empty?(pred_tokens) or Enum.empty?(truth_tokens) do
        0.0
      else
        intersection =
          MapSet.intersection(
            MapSet.new(pred_tokens),
            MapSet.new(truth_tokens)
          )

        precision = MapSet.size(intersection) / length(pred_tokens)
        recall = MapSet.size(intersection) / length(truth_tokens)

        if precision + recall == 0 do
          0.0
        else
          2 * precision * recall / (precision + recall)
        end
      end
    end

    @doc """
    Semantic similarity using embeddings (requires embedding model).
    """
    def semantic_similarity(prediction, ground_truth, opts \\ []) do
      threshold = opts[:threshold] || 0.8

      # This would call Python side to compute embedding similarity
      case Snakepit.Python.call(
             "dspy.evaluate.metrics.semantic_similarity",
             %{pred: prediction, truth: ground_truth, threshold: threshold},
             opts
           ) do
        {:ok, %{score: score}} -> score >= threshold
        _ -> false
      end
    end

    @doc """
    Custom metric wrapper for user-defined evaluation functions.
    """
    def custom(eval_fn) when is_function(eval_fn, 2) do
      eval_fn
    end

    # Helper functions

    defp normalize(text) when is_binary(text) do
      text
      |> String.downcase()
      |> String.trim()
      |> String.replace(~r/\s+/, " ")
    end

    defp normalize(value), do: to_string(value) |> normalize()

    defp tokenize(text) when is_binary(text) do
      text
      |> normalize()
      |> String.split(~r/\W+/, trim: true)
      |> Enum.filter(&(&1 != ""))
    end

    defp tokenize(value), do: to_string(value) |> tokenize()
  end

  defp prepare_metric(nil), do: "exact_match"
  defp prepare_metric(metric) when is_binary(metric), do: metric

  defp prepare_metric(metric) when is_function(metric) do
    # Register the metric function for Python side
    # This is a placeholder - would need proper implementation
    "custom_metric"
  end
end

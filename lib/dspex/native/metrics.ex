defmodule DSPex.Native.Metrics do
  @moduledoc """
  Native metric calculations for evaluation.

  Provides common ML metrics without Python overhead.
  """

  @doc """
  Calculate exact match between prediction and ground truth.
  """
  @spec exact_match(String.t(), String.t()) :: boolean()
  def exact_match(prediction, ground_truth)
      when is_binary(prediction) and is_binary(ground_truth) do
    String.trim(prediction) == String.trim(ground_truth)
  end

  @doc """
  Calculate F1 score between prediction and ground truth.

  This is a simplified token-based F1 score.
  """
  @spec f1_score(String.t(), String.t()) :: float()
  def f1_score(prediction, ground_truth) when is_binary(prediction) and is_binary(ground_truth) do
    pred_tokens = tokenize(prediction)
    truth_tokens = tokenize(ground_truth)

    pred_set = MapSet.new(pred_tokens)
    truth_set = MapSet.new(truth_tokens)

    intersection = MapSet.intersection(pred_set, truth_set)

    precision =
      if MapSet.size(pred_set) > 0 do
        MapSet.size(intersection) / MapSet.size(pred_set)
      else
        0.0
      end

    recall =
      if MapSet.size(truth_set) > 0 do
        MapSet.size(intersection) / MapSet.size(truth_set)
      else
        0.0
      end

    if precision + recall > 0 do
      2 * (precision * recall) / (precision + recall)
    else
      0.0
    end
  end

  @doc """
  Calculate accuracy over a list of predictions.
  """
  @spec accuracy(list({String.t(), String.t()})) :: float()
  def accuracy(prediction_pairs) when is_list(prediction_pairs) do
    correct =
      Enum.count(prediction_pairs, fn {pred, truth} ->
        exact_match(pred, truth)
      end)

    total = length(prediction_pairs)

    if total > 0 do
      correct / total
    else
      0.0
    end
  end

  # Private functions

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.split(~r/\W+/, trim: true)
  end
end

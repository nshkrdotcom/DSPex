defmodule DSPEx.Teleprompter.BEACON.Utils do
  @moduledoc """
  Shared utilities for BEACON teleprompter examples and testing.

  This module contains common helper functions used across BEACON examples,
  tests, and benchmarks to avoid duplication and ensure consistency.
  """

  @doc """
  Evaluates the quality of reasoning output by checking for mathematical
  operations, logical connectors, and keyword overlap.
  """
  def evaluate_reasoning_quality(expected, actual) do
    expected_keywords = extract_reasoning_keywords(expected)
    actual_keywords = extract_reasoning_keywords(actual)

    keyword_overlap = calculate_keyword_overlap(expected_keywords, actual_keywords)

    # Check for mathematical operations and logical flow
    has_math_operations =
      if is_binary(actual),
        do: String.contains?(actual, ["×", "*", "+", "-", "=", "÷", "/"]),
        else: false

    has_logical_flow = contains_logical_connectors(actual)
    has_step_markers = contains_step_indicators(actual)

    base_score = keyword_overlap * 0.25
    math_bonus = if has_math_operations, do: 0.08, else: 0.0
    logic_bonus = if has_logical_flow, do: 0.04, else: 0.0
    step_bonus = if has_step_markers, do: 0.03, else: 0.0

    min(base_score + math_bonus + logic_bonus + step_bonus, 0.4)
  end

  @doc """
  Calculates text similarity using Jaccard similarity with length normalization.
  """
  def text_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    words1 = String.split(String.downcase(text1))
    words2 = String.split(String.downcase(text2))

    set1 = MapSet.new(words1)
    set2 = MapSet.new(words2)

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    jaccard_similarity = if union == 0, do: 1.0, else: intersection / union

    # Length similarity bonus
    len1 = length(words1)
    len2 = length(words2)
    length_similarity = 1.0 - abs(len1 - len2) / Enum.max([len1, len2, 1])

    # Combine similarities
    jaccard_similarity * 0.8 + length_similarity * 0.2
  end

  def text_similarity(_, _), do: 0.0

  @doc """
  Normalizes answer text for comparison by removing punctuation and case.
  """
  def normalize_answer(answer) when is_binary(answer) do
    answer
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.trim()
  end

  def normalize_answer(_), do: ""

  @doc """
  Extracts keywords from text, filtering out common stop words.
  """
  def extract_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.reject(
      &(&1 in [
          "with",
          "from",
          "that",
          "this",
          "they",
          "have",
          "will",
          "are",
          "for",
          "the",
          "and",
          "some"
        ])
    )
  end

  def extract_keywords(_), do: []

  @doc """
  Extracts numeric value from text string.
  """
  def extract_number(text) when is_binary(text) do
    case Regex.run(~r/\d+(?:\.\d+)?/, text) do
      [number_str] -> parse_number_string(number_str)
      nil -> nil
    end
  end

  def extract_number(_), do: nil

  @doc """
  Creates a detailed progress reporter with timestamps.
  """
  def detailed_progress_reporter(progress) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()

    case progress.phase do
      :bootstrap_generation ->
        completed = Map.get(progress, :completed, 0)
        total = Map.get(progress, :total, 1)
        percentage = Float.round(completed / total * 100, 1)
        IO.puts("[#{timestamp}] 🔄 Bootstrap Generation: #{percentage}% (#{completed}/#{total})")

      :bayesian_optimization ->
        IO.puts(
          "[#{timestamp}] 🎯 Trial #{progress.trial}: Score #{Float.round(progress.current_score, 4)}"
        )

        # Show progress bar for trials
        trial = Map.get(progress, :trial, 0)
        total_trials = Map.get(progress, :total_trials, 1)

        if rem(trial, 5) == 0 do
          progress_bar = create_progress_bar(trial, total_trials)
          IO.puts("     #{progress_bar}")
        end

      :instruction_generation ->
        IO.puts("[#{timestamp}] 📝 Generating instruction candidates...")

      _ ->
        IO.puts("[#{timestamp}] #{progress.phase}: #{inspect(progress)}")
    end
  end

  @doc """
  Generates a correlation ID for tracking optimization runs.
  """
  def generate_correlation_id do
    "beacon-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc """
  Measures execution time of a function and returns results with timing.
  """
  def measure_execution_time(fun) do
    start_time = System.monotonic_time()

    result =
      try do
        fun.()
      rescue
        exception ->
          {:error, exception}
      catch
        :exit, reason ->
          {:error, {:exit, reason}}

        :throw, value ->
          {:error, {:throw, value}}
      end

    duration =
      System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

    %{
      result: result,
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }
  end

  # Private helper functions

  defp parse_number_string(number_str) do
    case Float.parse(number_str) do
      {number, _} ->
        number

      :error ->
        case Integer.parse(number_str) do
          {number, _} -> number
          :error -> nil
        end
    end
  end

  defp extract_reasoning_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.reject(
      &(&1 in [
          "the",
          "and",
          "but",
          "with",
          "from",
          "that",
          "this",
          "they",
          "have",
          "will",
          "are",
          "for"
        ])
    )
  end

  defp extract_reasoning_keywords(_), do: []

  defp calculate_keyword_overlap(keywords1, keywords2) do
    set1 = MapSet.new(keywords1)
    set2 = MapSet.new(keywords2)

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0, do: 1.0, else: intersection / union
  end

  defp contains_logical_connectors(text) when is_binary(text) do
    logical_words = ["then", "so", "therefore", "because", "since", "thus", "hence"]
    Enum.any?(logical_words, &String.contains?(String.downcase(text), &1))
  end

  defp contains_logical_connectors(_), do: false

  defp contains_step_indicators(text) when is_binary(text) do
    step_indicators = ["first", "next", "then", "finally", "step", "="]
    Enum.any?(step_indicators, &String.contains?(String.downcase(text), &1))
  end

  defp contains_step_indicators(_), do: false

  defp create_progress_bar(current, total) do
    percentage = current / total
    filled = round(percentage * 20)
    empty = 20 - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    "Progress: [#{bar}] #{Float.round(percentage * 100, 1)}%"
  end
end

defmodule DSPEx.Teleprompter do
  @moduledoc """
  Behavior for DSPEx teleprompters (optimizers).

  Teleprompters are responsible for improving programs by learning from examples
  and optimizing demonstration selection. They take a student program, a teacher
  program, and training examples, then return an optimized version of the student.

  This module focuses on single-node optimization with excellent local performance.
  Distributed features can be added later as enhancements.

  ## Example

      defmodule MyTeleprompter do
        @behaviour DSPEx.Teleprompter

        @impl true
        def compile(student, teacher, trainset, metric_fn, opts) do
          # Optimization logic here
          {:ok, optimized_student}
        end
      end
  """

  alias DSPEx.Example

  @type program :: struct()
  @type trainset :: [Example.t()]
  @type metric_fn :: (Example.t(), map() -> number())
  @type opts :: keyword()
  @type compilation_result :: {:ok, program()} | {:error, term()}

  @doc """
  Compile (optimize) a student program using a teacher program and training data.

  ## Parameters

  - `student`: The program to be optimized
  - `teacher`: A stronger program used to generate demonstrations
  - `trainset`: Training examples for optimization
  - `metric_fn`: Function to evaluate prediction quality (example, prediction) -> score
  - `opts`: Options for compilation (varies by teleprompter)

  ## Returns

  - `{:ok, optimized_program}` on successful optimization
  - `{:error, reason}` if optimization fails
  """
  @callback compile(
              student :: program(),
              teacher :: program(),
              trainset :: trainset(),
              metric_fn :: metric_fn(),
              opts :: opts()
            ) :: compilation_result()

  @doc """
  Helper function to create a basic metric function for exact match comparison.
  """
  @spec exact_match(atom()) :: metric_fn()
  def exact_match(field) when is_atom(field) do
    fn example, prediction ->
      outputs = Example.outputs(example)
      expected = Map.get(outputs, field)
      actual = Map.get(prediction, field)

      if expected == actual do
        1.0
      else
        0.0
      end
    end
  end

  @doc """
  Helper function to create a metric function that checks if prediction contains expected value.
  """
  @spec contains_match(atom()) :: metric_fn()
  def contains_match(field) when is_atom(field) do
    fn example, prediction ->
      outputs = Example.outputs(example)
      expected = Map.get(outputs, field)
      actual = Map.get(prediction, field)

      calculate_match_score(expected, actual)
    end
  end

  # Calculate match score between expected and actual values
  @spec calculate_match_score(term(), term()) :: float()
  defp calculate_match_score(expected, actual) when is_binary(expected) and is_binary(actual) do
    expected_lower = String.downcase(expected)
    actual_lower = String.downcase(actual)

    cond do
      strings_contain_each_other?(expected_lower, actual_lower) -> 1.0
      words_have_common_match?(expected_lower, actual_lower) -> 1.0
      true -> 0.0
    end
  end

  defp calculate_match_score(expected, actual) do
    if expected == actual, do: 1.0, else: 0.0
  end

  # Check if strings contain each other
  @spec strings_contain_each_other?(String.t(), String.t()) :: boolean()
  defp strings_contain_each_other?(expected_lower, actual_lower) do
    String.contains?(actual_lower, expected_lower) or
      String.contains?(expected_lower, actual_lower)
  end

  # Check if strings have common significant words
  @spec words_have_common_match?(String.t(), String.t()) :: boolean()
  defp words_have_common_match?(expected_lower, actual_lower) do
    expected_words = extract_significant_words(expected_lower)

    Enum.any?(expected_words, fn word ->
      String.length(word) > 2 and String.contains?(actual_lower, word)
    end)
  end

  # Extract significant words (excluding common stop words)
  @spec extract_significant_words(String.t()) :: [String.t()]
  defp extract_significant_words(text) do
    stop_words = [
      "the",
      "a",
      "an",
      "and",
      "or",
      "is",
      "are",
      "was",
      "were",
      "will",
      "would",
      "answer"
    ]

    text
    |> String.split(~r/\W+/, trim: true)
    |> Enum.reject(&(&1 in stop_words))
  end

  @doc """
  Helper function to validate that a module implements the teleprompter behavior.
  """
  @spec implements_behavior?(module()) :: boolean()
  def implements_behavior?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        behaviours =
          module.module_info(:attributes)
          |> Keyword.get(:behaviour, [])

        __MODULE__ in behaviours

      _ ->
        false
    end
  end

  @doc """
  Validates that a student program is properly configured for teleprompter use.
  """
  @spec validate_student(program()) :: :ok | {:error, term()}
  def validate_student(program) do
    cond do
      not is_struct(program) ->
        {:error, :invalid_student_program}

      not DSPEx.Program.implements_program?(program.__struct__) ->
        {:error, :student_does_not_implement_program_behavior}

      true ->
        :ok
    end
  end

  @doc """
  Validates that a teacher program is properly configured for teleprompter use.
  """
  @spec validate_teacher(program()) :: :ok | {:error, term()}
  def validate_teacher(program) do
    cond do
      not is_struct(program) ->
        {:error, :invalid_teacher_program}

      not DSPEx.Program.implements_program?(program.__struct__) ->
        {:error, :teacher_does_not_implement_program_behavior}

      true ->
        :ok
    end
  end

  @doc """
  Validates that a training dataset is properly formatted for teleprompter use.
  """
  @spec validate_trainset(trainset()) :: :ok | {:error, term()}
  def validate_trainset(trainset) do
    cond do
      not is_list(trainset) ->
        {:error, :trainset_must_be_list}

      Enum.empty?(trainset) ->
        {:error, :trainset_cannot_be_empty}

      not Enum.all?(trainset, &is_struct(&1, Example)) ->
        {:error, :trainset_must_contain_examples}

      true ->
        :ok
    end
  end
end

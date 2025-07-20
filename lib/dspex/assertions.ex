defmodule DSPex.Assertions do
  @moduledoc """
  DSPy assertions for constraining and validating LM outputs.

  Assertions can be used to ensure outputs meet specific criteria,
  with options to retry or raise errors on failure.
  """

  alias DSPex.Utils.ID

  @doc """
  Create an assertion that must be satisfied.

  ## Examples

      # Simple assertion
      assert_short = DSPex.Assertions.create(
        fn result -> String.length(result.answer) < 100 end,
        "Answer must be less than 100 characters"
      )
      
      # Use with a module
      {:ok, program} = DSPex.Modules.Predict.create("question -> answer")
      {:ok, constrained} = DSPex.Assertions.apply_assertions(program, assert_short)
  """
  def create(predicate, message \\ "", opts \\ []) do
    id = ID.generate("assert")

    # Register the predicate function
    predicate_id = register_predicate(predicate)

    config = %{
      predicate_id: predicate_id,
      message: message,
      backtrack: opts[:backtrack],
      target_module: opts[:target_module]
    }

    # Note: DSPy assertions are in dspy.assertions module
    case Snakepit.Python.call(
           "dspy.assertions.assert_",
           config,
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Create a soft constraint that suggests but doesn't require satisfaction.
  """
  def suggest(predicate, message \\ "", opts \\ []) do
    id = ID.generate("suggest")

    # Register the predicate function
    predicate_id = register_predicate(predicate)

    config = %{
      predicate_id: predicate_id,
      message: message,
      backtrack: opts[:backtrack],
      target_module: opts[:target_module]
    }

    # Note: DSPy suggestions are in dspy.assertions module
    case Snakepit.Python.call(
           "dspy.assertions.suggest",
           config,
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Apply assertions to a program/module.
  """
  def apply_assertions(program_id, assertion_ids_or_id, opts \\ [])

  def apply_assertions(program_id, assertion_ids, _opts) when is_list(assertion_ids) do
    constrained_id = "#{program_id}_constrained"

    # DSPy doesn't have assert_transform_module - assertions are handled differently
    # For now, return the original module ID with a suffix
    # In real usage, assertions would be integrated into the module's forward pass
    {:ok, constrained_id}
  end

  def apply_assertions(program_id, assertion_id, opts) do
    apply_assertions(program_id, [assertion_id], opts)
  end

  # Common assertion helpers

  @doc """
  Assert that output contains specific keywords.
  """
  def assert_contains(keywords, field \\ :answer) do
    create(
      fn result ->
        text = Map.get(result, field, "")
        Enum.all?(keywords, &String.contains?(text, &1))
      end,
      "Output must contain keywords: #{inspect(keywords)}"
    )
  end

  @doc """
  Assert that output matches a pattern.
  """
  def assert_matches(pattern, field \\ :answer) do
    create(
      fn result ->
        text = Map.get(result, field, "")
        Regex.match?(pattern, text)
      end,
      "Output must match pattern: #{inspect(pattern)}"
    )
  end

  @doc """
  Assert that output has a specific length constraint.
  """
  def assert_length(opts, field \\ :answer) when is_list(opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)

    create(
      fn result ->
        text = Map.get(result, field, "")
        len = String.length(text)
        len >= min && len <= max
      end,
      "Output length must be between #{min} and #{max} characters"
    )
  end

  @doc """
  Assert that a numeric output is within a range.
  """
  def assert_range(opts, field \\ :answer) when is_list(opts) do
    min = Keyword.fetch!(opts, :min)
    max = Keyword.fetch!(opts, :max)

    create(
      fn result ->
        case Map.get(result, field) do
          num when is_number(num) ->
            num >= min && num <= max

          str when is_binary(str) ->
            case Float.parse(str) do
              {num, _} -> num >= min && num <= max
              :error -> false
            end

          _ ->
            false
        end
      end,
      "Value must be between #{min} and #{max}"
    )
  end

  defp register_predicate(_predicate) do
    # TODO: Implement predicate registration bridge
    # This would need to serialize the Elixir function and make it
    # callable from Python side
    "placeholder_predicate_id"
  end
end

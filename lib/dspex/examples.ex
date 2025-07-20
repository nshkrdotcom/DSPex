defmodule DSPex.Examples do
  @moduledoc """
  Example dataset management for DSPex.

  Provides utilities to work with example datasets for training and evaluation.
  """

  @doc """
  Create an example from a map.

  ## Examples

      example = DSPex.Examples.create(%{
        question: "What is the capital of France?",
        answer: "Paris"
      })
  """
  def create(fields, opts \\ []) do
    example_id = opts[:id] || DSPex.Utils.ID.generate("example")

    Snakepit.Python.call(
      "dspy.Example",
      fields,
      Keyword.merge([store_as: example_id], opts)
    )
  end

  @doc """
  Create a dataset from a list of examples.
  """
  def dataset(examples, opts \\ []) when is_list(examples) do
    dataset_id = opts[:store_as] || DSPex.Utils.ID.generate("dataset")

    # Convert to Example objects if needed
    processed_examples =
      Enum.map(examples, fn
        %{} = ex -> ex
        ex when is_binary(ex) -> "stored.#{ex}"
      end)

    Snakepit.Python.call(
      "dspy.datasets.Dataset",
      %{examples: processed_examples},
      Keyword.merge([store_as: dataset_id], opts)
    )
  end

  @doc """
  Load a built-in dataset.

  ## Available datasets:
  - :hotpot_qa - HotPotQA multi-hop reasoning
  - :gsm8k - Grade school math problems
  - :color_objects - Color and object descriptions
  """
  def load_builtin(name, opts \\ []) do
    dataset_loader =
      case name do
        :hotpot_qa -> "dspy.datasets.HotPotQA"
        :gsm8k -> "dspy.datasets.GSM8K"
        :color_objects -> "dspy.datasets.ColorObjects"
        other -> to_string(other)
      end

    split = opts[:split] || "train"

    Snakepit.Python.call(
      "#{dataset_loader}",
      %{split: split},
      opts
    )
  end

  @doc """
  Split a dataset into train/validation/test sets.
  """
  def split_dataset(dataset, opts \\ []) do
    train_size = opts[:train_size] || 0.7
    val_size = opts[:val_size] || 0.15
    # test_size is the remainder

    seed = opts[:seed] || 42

    Snakepit.Python.call(
      "dspy.datasets.split_dataset",
      %{
        dataset: dataset,
        train_size: train_size,
        val_size: val_size,
        seed: seed
      },
      opts
    )
  end

  @doc """
  Sample examples from a dataset.
  """
  def sample(dataset, n, opts \\ []) do
    seed = opts[:seed]

    Snakepit.Python.call(
      "dspy.datasets.sample_dataset",
      %{
        dataset: dataset,
        n: n,
        seed: seed
      },
      opts
    )
  end

  @doc """
  Filter dataset examples based on a predicate.
  """
  def filter(dataset, predicate_fn, opts \\ []) do
    # Note: This would need a way to register Elixir functions
    # on the Python side
    filtered_id = DSPex.Utils.ID.generate("filtered")

    Snakepit.Python.call(
      "dspy.datasets.filter_dataset",
      %{
        dataset: dataset,
        predicate: register_predicate(predicate_fn)
      },
      Keyword.merge([store_as: filtered_id], opts)
    )
  end

  defp register_predicate(_fn) do
    # TODO: Implement predicate registration
    "placeholder_predicate"
  end
end

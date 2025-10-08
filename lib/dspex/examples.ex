defmodule DSPex.Examples do
  @moduledoc """
  Example dataset management for DSPex.

  Provides utilities to work with example datasets for training and evaluation.

  Migrated to Snakepit v0.4.3 API (execute_in_session).
  """

  alias DSPex.Utils.ID

  @doc """
  Create an example from a map.

  ## Examples

      example = DSPex.Examples.create(%{
        question: "What is the capital of France?",
        answer: "Paris"
      })
  """
  def create(fields, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    case DSPex.Bridge.create_instance(
           "dspy.Example",
           fields,
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Create a dataset from a list of examples.
  """
  def dataset(examples, opts \\ []) when is_list(examples) do
    session_id = opts[:session_id] || ID.generate("session")

    # Convert to Example objects if needed
    processed_examples =
      Enum.map(examples, fn
        %{} = ex -> ex
        ex when is_binary(ex) -> "stored.#{ex}"
      end)

    case DSPex.Bridge.create_instance(
           "dspy.datasets.Dataset",
           %{examples: processed_examples},
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Load a built-in dataset.

  ## Available datasets:
  - :hotpot_qa - HotPotQA multi-hop reasoning
  - :gsm8k - Grade school math problems
  - :color_objects - Color and object descriptions
  """
  def load_builtin(name, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    dataset_loader =
      case name do
        :hotpot_qa -> "dspy.datasets.HotPotQA"
        :gsm8k -> "dspy.datasets.GSM8K"
        :color_objects -> "dspy.datasets.ColorObjects"
        other -> to_string(other)
      end

    split = opts[:split] || "train"

    case DSPex.Bridge.create_instance(
           dataset_loader,
           %{split: split},
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Split a dataset into train/validation/test sets.
  """
  def split_dataset(dataset, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    train_size = opts[:train_size] || 0.7
    val_size = opts[:val_size] || 0.15
    # test_size is the remainder

    seed = opts[:seed] || 42

    case DSPex.Bridge.call_dspy(
           "dspy.datasets",
           "split_dataset",
           %{
             dataset: dataset,
             train_size: train_size,
             val_size: val_size,
             seed: seed
           },
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Sample examples from a dataset.
  """
  def sample(dataset, n, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    seed = opts[:seed]

    case DSPex.Bridge.call_dspy(
           "dspy.datasets",
           "sample_dataset",
           %{
             dataset: dataset,
             n: n,
             seed: seed
           },
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Filter dataset examples based on a predicate.

  Note: Predicate registration requires custom bridge implementation.
  Currently returns :not_implemented.
  """
  def filter(_dataset, _predicate_fn, _opts \\ []) do
    # Filtering with Elixir predicates needs bidirectional tool support
    {:error, :not_implemented}
  end
end

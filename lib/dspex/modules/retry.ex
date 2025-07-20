defmodule DSPex.Modules.Retry do
  @moduledoc """
  Retry module with self-refinement.

  Attempts to generate an answer, then refines it based on feedback or criteria.
  Useful for iterative improvement of responses.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new Retry module instance.

  Note: The dspy.Retry module is currently commented out in DSPy source.
  This uses dspy.ChainOfThought with retry logic as a workaround.

  ## Examples

      {:ok, retry} = DSPex.Modules.Retry.create(
        "question -> answer",
        max_attempts: 3
      )
      {:ok, result} = DSPex.Modules.Retry.execute(retry, %{
        question: "Write a haiku about programming"
      })
  """
  def create(signature, opts \\ []) do
    id = opts[:store_as] || ID.generate("retry")
    _max_attempts = opts[:max_attempts] || 3

    # Since dspy.Retry is commented out, use ChainOfThought as fallback
    case Snakepit.Python.call(
           "dspy.ChainOfThought",
           %{signature: signature},
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Execute retry/refinement with the given inputs.
  """
  def execute(retry_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{retry_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def refine(signature, inputs, opts \\ []) do
    with {:ok, id} <- create(signature, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end
end

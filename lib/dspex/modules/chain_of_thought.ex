defmodule DSPex.Modules.ChainOfThought do
  @moduledoc """
  Chain of Thought reasoning module.

  Generates step-by-step reasoning before producing the final answer.
  This helps with complex reasoning tasks and provides interpretability.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new ChainOfThought module instance.

  ## Examples

      {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
      {:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{question: "Why is the sky blue?"})
      # Result includes: %{reasoning: "...", answer: "..."}
  """
  def create(signature, opts \\ []) do
    id = opts[:store_as] || ID.generate("cot")

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
  Execute chain of thought reasoning with the given inputs.
  """
  def execute(cot_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{cot_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def think(signature, inputs, opts \\ []) do
    with {:ok, id} <- create(signature, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end
end

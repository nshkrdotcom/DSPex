defmodule DSPex.Modules.Predict do
  @moduledoc """
  Basic prediction module - the simplest DSPy predictor.

  Directly generates outputs based on the signature without intermediate reasoning.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new Predict module instance.

  ## Examples

      {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
      {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is DSPy?"})
  """
  def create(signature, opts \\ []) do
    id = opts[:store_as] || ID.generate("predict")

    case Snakepit.Python.call(
           "dspy.Predict",
           %{signature: signature},
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Execute a prediction with the given inputs.
  """
  def execute(predictor_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{predictor_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def predict(signature, inputs, opts \\ []) do
    with {:ok, id} <- create(signature, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end
end

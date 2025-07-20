defmodule DSPex.Modules.ProgramOfThought do
  @moduledoc """
  Program of Thought module for code-based reasoning.

  Generates and executes code to solve problems, particularly useful
  for mathematical and algorithmic tasks.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new ProgramOfThought module instance.

  ## Examples

      {:ok, pot} = DSPex.Modules.ProgramOfThought.create("problem -> code, solution")
      {:ok, result} = DSPex.Modules.ProgramOfThought.execute(pot, %{
        problem: "Find the sum of all prime numbers less than 100"
      })
  """
  def create(signature, opts \\ []) do
    id = opts[:store_as] || ID.generate("pot")

    case Snakepit.Python.call(
           "dspy.ProgramOfThought",
           %{signature: signature},
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Execute program generation and execution with the given inputs.
  """
  def execute(pot_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{pot_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def solve_with_code(signature, inputs, opts \\ []) do
    with {:ok, id} <- create(signature, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end
end

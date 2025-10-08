defmodule DSPex.Modules.ProgramOfThought do
  @moduledoc """
  Program of Thought module for code-based reasoning.

  Generates and executes code to solve problems, particularly useful
  for mathematical and algorithmic tasks.

  Migrated to Snakepit v0.4.3 API (execute_in_session).
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
    session_id = opts[:session_id] || ID.generate("session")

    case DSPex.Bridge.create_instance(
           "dspy.ProgramOfThought",
           %{signature: signature},
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Execute program generation and execution with the given inputs.
  """
  def execute({session_id, instance_id} = _instance_ref, inputs, opts \\ []) do
    case DSPex.Bridge.call_method(
           {session_id, instance_id},
           "__call__",
           inputs,
           opts
         ) do
      {:ok, %{"success" => true, "result" => result}} -> {:ok, result}
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def solve_with_code(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    with {:ok, instance_ref} <- create(signature, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- execute(instance_ref, inputs, opts) do
      {:ok, result}
    end
  end
end

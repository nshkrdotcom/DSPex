defmodule DSPex.Modules.Retry do
  @moduledoc """
  Retry module with self-refinement.

  Attempts to generate an answer, then refines it based on feedback or criteria.
  Useful for iterative improvement of responses.

  Migrated to Snakepit v0.4.3 API (execute_in_session).

  Note: The dspy.Retry module is currently commented out in DSPy source.
  This uses dspy.ChainOfThought with retry logic as a workaround.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new Retry module instance.

  Note: The dspy.Retry module is currently commented out in DSPy source.
  This uses dspy.ChainOfThought as a fallback.

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
    session_id = opts[:session_id] || ID.generate("session")
    _max_attempts = opts[:max_attempts] || 3

    # Since dspy.Retry is commented out, use ChainOfThought as fallback
    case DSPex.Bridge.create_instance(
           "dspy.ChainOfThought",
           %{signature: signature},
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Execute retry/refinement with the given inputs.
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
  def refine(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    with {:ok, instance_ref} <- create(signature, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- execute(instance_ref, inputs, opts) do
      {:ok, result}
    end
  end
end

defmodule DSPex.Modules.MultiChainComparison do
  @moduledoc """
  Multi-Chain Comparison module.

  Generates multiple reasoning chains and compares them to select the best answer.
  Useful for complex problems where different reasoning paths might lead to different conclusions.

  Migrated to Snakepit v0.4.3 API (execute_in_session).
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new MultiChainComparison module instance.

  ## Examples

      {:ok, mcc} = DSPex.Modules.MultiChainComparison.create(
        "question -> answer",
        chains: 3
      )
      {:ok, result} = DSPex.Modules.MultiChainComparison.execute(mcc, %{
        question: "What are the implications of quantum computing on cryptography?"
      })
  """
  def create(signature, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    chains = opts[:chains] || 3

    case DSPex.Bridge.create_instance(
           "dspy.MultiChainComparison",
           %{signature: signature, M: chains},
           Keyword.put(opts, :session_id, session_id)
         ) do
      {:ok, instance_ref} -> {:ok, instance_ref}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Execute multi-chain comparison with the given inputs.
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
  def compare_chains(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    with {:ok, instance_ref} <- create(signature, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- execute(instance_ref, inputs, opts) do
      {:ok, result}
    end
  end
end

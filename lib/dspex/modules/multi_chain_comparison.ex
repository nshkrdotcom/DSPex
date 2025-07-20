defmodule DSPex.Modules.MultiChainComparison do
  @moduledoc """
  Multi-Chain Comparison module.

  Generates multiple reasoning chains and compares them to select the best answer.
  Useful for complex problems where different reasoning paths might lead to different conclusions.
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
    id = opts[:store_as] || ID.generate("mcc")
    chains = opts[:chains] || 3

    case Snakepit.Python.call(
           "dspy.MultiChainComparison",
           %{signature: signature, M: chains},
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Execute multi-chain comparison with the given inputs.
  """
  def execute(mcc_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{mcc_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def compare_chains(signature, inputs, opts \\ []) do
    with {:ok, id} <- create(signature, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end
end

defmodule DSPex.Modules do
  @moduledoc """
  Central registry and documentation for all DSPy modules available in DSPex.

  This module provides a unified interface to discover and use all DSPy
  prediction modules through their Elixir wrappers.

  ## Available Modules

  ### Core Prediction Modules
  - `Predict` - Basic prediction without reasoning
  - `ChainOfThought` - Step-by-step reasoning
  - `ReAct` - Reasoning + Acting with tools
  - `ProgramOfThought` - Code-based problem solving
  - `MultiChainComparison` - Compare multiple reasoning chains
  - `Retry` - Self-refinement through retries

  ### Optimizers
  - `BootstrapFewShot` - Automatic few-shot example generation
  - `MIPRO` - Multi-instruction prompt optimization
  - `MIPROv2` - Enhanced MIPRO with better performance
  - `COPRO` - Coordinate prompt optimization
  - `BootstrapFewShotWithRandomSearch` - Bootstrap with hyperparameter search

  ### Retrievers
  - `ColBERTv2` - Dense passage retrieval
  - `Retrieve` - Generic retrieval supporting 20+ vector databases

  ## Usage Examples

      # Simple prediction
      {:ok, pred} = DSPex.Modules.Predict.create("question -> answer")
      {:ok, result} = DSPex.Modules.Predict.execute(pred, %{question: "What is DSPy?"})
      
      # Chain of thought
      {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
      {:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{question: "Explain reasoning"})
      
      # Optimization
      {:ok, optimized} = DSPex.Optimizers.BootstrapFewShot.optimize(pred, trainset)
  """

  @doc """
  List all available DSPy modules.
  """
  def list_modules do
    %{
      prediction: [
        DSPex.Modules.Predict,
        DSPex.Modules.ChainOfThought,
        DSPex.Modules.ReAct,
        DSPex.Modules.ProgramOfThought,
        DSPex.Modules.MultiChainComparison,
        DSPex.Modules.Retry
      ],
      optimizers: [
        DSPex.Optimizers.BootstrapFewShot,
        DSPex.Optimizers.MIPRO,
        DSPex.Optimizers.MIPROv2,
        DSPex.Optimizers.COPRO,
        DSPex.Optimizers.BootstrapFewShotWithRandomSearch
      ],
      retrievers: [
        DSPex.Retrievers.ColBERTv2,
        DSPex.Retrievers.Retrieve
      ]
    }
  end

  @doc """
  Get information about a specific module.
  """
  def info(module_name) when is_atom(module_name) do
    case Code.ensure_loaded(module_name) do
      {:module, _} ->
        {:ok,
         %{
           name: module_name,
           doc: get_module_doc(module_name),
           functions: get_exported_functions(module_name)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a module by name (string or atom).

  ## Examples

      {:ok, module_id} = DSPex.Modules.create("ChainOfThought", "question -> answer")
      {:ok, module_id} = DSPex.Modules.create(:chain_of_thought, "question -> answer")
  """
  def create(module_type, signature, opts \\ [])

  def create("Predict", signature, opts), do: DSPex.Modules.Predict.create(signature, opts)

  def create("ChainOfThought", signature, opts),
    do: DSPex.Modules.ChainOfThought.create(signature, opts)

  def create("ReAct", signature, opts),
    do: DSPex.Modules.ReAct.create(signature, opts[:tools] || [], opts)

  def create("ProgramOfThought", signature, opts),
    do: DSPex.Modules.ProgramOfThought.create(signature, opts)

  def create("MultiChainComparison", signature, opts),
    do: DSPex.Modules.MultiChainComparison.create(signature, opts)

  def create("Retry", signature, opts), do: DSPex.Modules.Retry.create(signature, opts)

  def create(:predict, signature, opts), do: create("Predict", signature, opts)
  def create(:chain_of_thought, signature, opts), do: create("ChainOfThought", signature, opts)
  def create(:react, signature, opts), do: create("ReAct", signature, opts)

  def create(:program_of_thought, signature, opts),
    do: create("ProgramOfThought", signature, opts)

  def create(:multi_chain_comparison, signature, opts),
    do: create("MultiChainComparison", signature, opts)

  def create(:retry, signature, opts), do: create("Retry", signature, opts)

  def create(module_type, _signature, _opts) do
    {:error, "Unknown module type: #{module_type}"}
  end

  defp get_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> doc
      _ -> "No documentation available"
    end
  end

  defp get_exported_functions(module) do
    module.__info__(:functions)
    |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
    |> Enum.sort()
  end
end

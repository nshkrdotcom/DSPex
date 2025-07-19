defmodule DSPex.Python.Registry do
  @moduledoc """
  Registry for Python DSPy modules available through the bridge.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize with known DSPy modules
    registry = %{
      # Core modules
      "dspy.Predict" => %{pool: :general, type: :predictor},
      "dspy.ChainOfThought" => %{pool: :general, type: :predictor},
      "dspy.ChainOfThoughtWithHint" => %{pool: :general, type: :predictor},
      "dspy.ReAct" => %{pool: :general, type: :predictor},
      "dspy.ProgramOfThought" => %{pool: :general, type: :predictor},

      # Optimizers
      "dspy.BootstrapFewShot" => %{pool: :optimizer, type: :optimizer},
      "dspy.BootstrapFewShotWithRandomSearch" => %{pool: :optimizer, type: :optimizer},
      "dspy.MIPRO" => %{pool: :optimizer, type: :optimizer},
      "dspy.MIPROv2" => %{pool: :optimizer, type: :optimizer},
      "dspy.COPRO" => %{pool: :optimizer, type: :optimizer},

      # Retrievers
      "dspy.ColBERTv2" => %{pool: :neural, type: :retriever}
    }

    {:ok, registry}
  end

  @doc """
  List all registered Python modules.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Get information about a Python module.
  """
  def get(module_name) do
    GenServer.call(__MODULE__, {:get, module_name})
  end

  # Server callbacks

  @impl true
  def handle_call(:list, _from, registry) do
    {:reply, Map.keys(registry), registry}
  end

  @impl true
  def handle_call({:get, module_name}, _from, registry) do
    {:reply, Map.get(registry, module_name), registry}
  end
end

defmodule DSPex.Router do
  @moduledoc """
  Routes operations to native Elixir or Python implementations based on
  availability, performance characteristics, and configuration.

  The router maintains registries of available implementations and makes
  intelligent routing decisions to optimize performance while maintaining
  functionality.
  """

  use GenServer

  require Logger

  defstruct [
    :native_registry,
    :python_registry,
    :routing_metrics,
    :config
  ]

  # Native implementations registry
  @native_implementations %{
    # These are always native for performance
    signature: DSPex.Native.Signature,
    template: DSPex.Native.Template,
    validator: DSPex.Native.Validator,
    metrics: DSPex.Native.Metrics,
    lm_client: DSPex.LLM.Client
  }

  # Python module mappings
  @python_modules %{
    # Core DSPy modules
    predict: "dspy.Predict",
    chain_of_thought: "dspy.ChainOfThought",
    chain_of_thought_with_hint: "dspy.ChainOfThoughtWithHint",
    react: "dspy.ReAct",
    program_of_thought: "dspy.ProgramOfThought",
    multi_chain_comparison: "dspy.MultiChainComparison",

    # Optimizers (always Python)
    bootstrap_few_shot: "dspy.BootstrapFewShot",
    bootstrap_few_shot_with_random_search: "dspy.BootstrapFewShotWithRandomSearch",
    mipro: "dspy.MIPRO",
    mipro_v2: "dspy.MIPROv2",
    copro: "dspy.COPRO"
  }

  # Operations that can use either implementation
  @hybrid_operations [:predict, :chain_of_thought]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      native_registry: @native_implementations,
      python_registry: @python_modules,
      routing_metrics: %{},
      config: build_config(opts)
    }

    {:ok, state}
  end

  # Public API

  @doc """
  Route a predict operation.
  """
  def predict(signature, inputs, opts \\ []) do
    route(:predict, [signature, inputs], opts)
  end

  @doc """
  Route a chain of thought operation.
  """
  def chain_of_thought(signature, inputs, opts \\ []) do
    route(:chain_of_thought, [signature, inputs], opts)
  end

  @doc """
  Route a ReAct operation.
  """
  def react(signature, inputs, tools, opts \\ []) do
    route(:react, [signature, inputs, tools], opts)
  end

  @doc """
  Generic routing function for any operation.
  """
  def route(operation, args, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Get routing decision
    implementation = get_routing_decision(operation, opts)

    # Execute with the chosen implementation
    result = execute_with_implementation(implementation, operation, args, opts)

    # Record metrics
    duration = System.monotonic_time(:millisecond) - start_time
    record_routing_metrics(operation, implementation, duration, result)

    result
  end

  # Server callbacks

  @impl true
  def handle_call({:register_native, operation, module}, _from, state) do
    new_registry = Map.put(state.native_registry, operation, module)
    {:reply, :ok, %{state | native_registry: new_registry}}
  end

  @impl true
  def handle_call({:register_python, operation, module_name}, _from, state) do
    new_registry = Map.put(state.python_registry, operation, module_name)
    {:reply, :ok, %{state | python_registry: new_registry}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.routing_metrics, state}
  end

  # Private functions

  defp build_config(opts) do
    %{
      prefer_native: Keyword.get(opts, :prefer_native, true),
      fallback_enabled: Keyword.get(opts, :fallback_enabled, true),
      routing_strategy: Keyword.get(opts, :routing_strategy, :performance)
    }
  end

  defp get_routing_decision(operation, opts) do
    cond do
      # Explicit implementation requested
      opts[:implementation] == :native ->
        :native

      opts[:implementation] == :python ->
        :python

      # Check if native implementation exists
      has_native_implementation?(operation) and should_use_native?(operation, opts) ->
        :native

      # Check if Python implementation exists
      has_python_implementation?(operation) ->
        :python

      # No implementation available
      true ->
        :not_found
    end
  end

  defp has_native_implementation?(operation) do
    case GenServer.call(__MODULE__, {:get_native_registry, operation}) do
      nil -> false
      _ -> true
    end
  catch
    _, _ -> Map.has_key?(@native_implementations, operation)
  end

  defp has_python_implementation?(operation) do
    case GenServer.call(__MODULE__, {:get_python_registry, operation}) do
      nil -> false
      _ -> true
    end
  catch
    _, _ -> Map.has_key?(@python_modules, operation)
  end

  defp should_use_native?(operation, opts) do
    cond do
      # Always use native for these operations
      operation in [:signature, :template, :validator, :metrics] ->
        true

      # Hybrid operations - check configuration and metrics
      operation in @hybrid_operations ->
        prefer_native_for_hybrid?(operation, opts)

      # Default to Python for complex operations
      true ->
        false
    end
  end

  defp prefer_native_for_hybrid?(_operation, opts) do
    # For now, simple logic - can be enhanced with performance metrics
    case opts[:complexity] do
      :simple -> true
      :complex -> false
      # Default to native for better performance
      _ -> true
    end
  end

  defp execute_with_implementation(:native, operation, args, opts) do
    module = @native_implementations[operation]

    if module && function_exported?(module, :execute, length(args) + 1) do
      apply(module, :execute, args ++ [opts])
    else
      {:error, {:not_implemented, operation, :native}}
    end
  end

  defp execute_with_implementation(:python, operation, args, opts) do
    module_name = @python_modules[operation]
    pool = select_pool_for_operation(operation)

    # Prepare arguments for Python
    python_args = prepare_python_args(operation, args)

    DSPex.Python.Bridge.execute(pool, module_name, python_args, opts)
  end

  defp execute_with_implementation(:not_found, operation, _args, _opts) do
    {:error, {:operation_not_found, operation}}
  end

  defp prepare_python_args(:predict, [signature, inputs]) do
    %{
      signature: signature,
      inputs: inputs
    }
  end

  defp prepare_python_args(:chain_of_thought, [signature, inputs]) do
    %{
      signature: signature,
      inputs: inputs
    }
  end

  defp prepare_python_args(:react, [signature, inputs, tools]) do
    %{
      signature: signature,
      inputs: inputs,
      tools: serialize_tools(tools)
    }
  end

  defp prepare_python_args(_, args) do
    # Generic argument preparation
    %{args: args}
  end

  defp serialize_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: tool[:parameters] || %{}
      }
    end)
  end

  defp select_pool_for_operation(operation) do
    cond do
      operation in [:mipro, :mipro_v2, :copro, :bootstrap_few_shot] -> :optimizer
      operation in [:colbert, :rerank] -> :neural
      true -> :general
    end
  end

  defp record_routing_metrics(operation, implementation, duration, result) do
    success =
      case result do
        {:ok, _} -> true
        _ -> false
      end

    :telemetry.execute(
      [:dspex, :router, :route],
      %{duration: duration, success: success},
      %{operation: operation, implementation: implementation}
    )
  end
end

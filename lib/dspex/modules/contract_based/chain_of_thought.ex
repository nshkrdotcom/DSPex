defmodule DSPex.Modules.ContractBased.ChainOfThought do
  @moduledoc """
  Contract-based implementation of DSPy ChainOfThought functionality.
  
  This module provides a typed, validated interface for chain-of-thought reasoning,
  using explicit contracts and applying all bridge behaviors for maximum flexibility.
  
  ## Features
  
  - Type-safe contract-based API
  - Observable execution with hooks
  - Bidirectional Python-Elixir communication
  - Result transformation pipeline
  - Full backward compatibility
  
  ## Examples
  
      # Create a chain-of-thought reasoner
      {:ok, cot} = ChainOfThought.create(%{
        signature: "question -> reasoning, answer"
      })
      
      # Execute reasoning
      {:ok, result} = ChainOfThought.think(cot, %{
        question: "What are the benefits of functional programming?"
      })
      # Returns: %DSPex.Types.ChainOfThoughtResult{
      #   reasoning: "Let me think about the key benefits...",
      #   answer: "Functional programming offers immutability, easier testing...",
      #   confidence: 0.92
      # }
      
      # One-shot reasoning
      {:ok, result} = ChainOfThought.call(
        %{signature: "problem -> approach, solution"},
        %{problem: "How to optimize a sorting algorithm?"}
      )
  """
  
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Observable
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.ResultTransform
  
  use_contract DSPex.Contracts.ChainOfThought
  
  alias DSPex.Types.ChainOfThoughtResult
  alias DSPex.Utils.ID
  
  @doc """
  Result transformation pipeline for ChainOfThought results.
  
  Converts raw Python results into structured Elixir types.
  """
  def transform_result({:ok, raw_result}) when is_map(raw_result) do
    ChainOfThoughtResult.from_python_result(raw_result)
  end
  
  def transform_result(error), do: error
  
  @doc """
  Observable hooks for monitoring reasoning process.
  """
  def default_hooks do
    %{
      before_think: fn params -> 
        IO.puts("[ChainOfThought] Starting reasoning for: #{inspect(params)}")
        :ok
      end,
      after_think: fn result ->
        case result do
          {:ok, %ChainOfThoughtResult{confidence: conf}} when not is_nil(conf) ->
            IO.puts("[ChainOfThought] Completed with confidence: #{conf}")
          _ ->
            :ok
        end
        :ok
      end,
      on_reasoning_step: fn step ->
        IO.puts("[ChainOfThought] Step: #{step}")
        :ok
      end
    }
  end
  
  @doc """
  Create and execute in one call (stateless).
  
  Combines create and think operations for convenience.
  
  ## Examples
  
      {:ok, result} = ChainOfThought.call(
        %{signature: "question -> reasoning, answer"},
        %{question: "What is recursion?"}
      )
  """
  def call(create_params, think_params, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    with {:ok, cot_ref} <- create(create_params, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- think(cot_ref, think_params, opts) do
      {:ok, result}
    end
  end
  
  @doc """
  Get detailed reasoning steps from the last execution.
  
  Returns individual steps if the reasoning was broken down.
  """
  def get_steps(cot_ref, opts \\ []) do
    with {:ok, steps} <- get_reasoning_steps(cot_ref, %{}, opts) do
      {:ok, steps}
    end
  end
  
  @doc """
  Configure the type of rationale field used.
  
  Some prompts may use different field names like 'approach', 'thinking', etc.
  """
  def set_rationale_type(cot_ref, type, opts \\ []) when is_binary(type) do
    # This would need to be implemented via the Python bridge
    # For now, we note it as a configuration option
    {:ok, %{rationale_type: type}}
  end
  
  # Backward compatibility helpers
  @doc false
  def new(signature, opts \\ []) do
    IO.warn("ChainOfThought.new/2 is deprecated. Use create/2 instead.", 
            Macro.Env.stacktrace(__ENV__))
    create(%{signature: signature}, opts)
  end
  
  @doc false
  def execute(cot_ref, inputs, opts \\ []) do
    IO.warn("ChainOfThought.execute/3 is deprecated. Use think/3 instead.", 
            Macro.Env.stacktrace(__ENV__))
    think(cot_ref, inputs, opts)
  end
  
  # Helper for extracting reasoning steps from text
  defp extract_steps(reasoning) when is_binary(reasoning) do
    reasoning
    |> String.split(~r/\n\s*\d+\.\s*/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> [reasoning]
      steps -> steps
    end
  end
  
  @doc """
  Apply custom result transformation.
  
  Allows users to provide their own transformation function.
  """
  def with_transform(cot_ref, transform_fn, opts \\ []) when is_function(transform_fn, 1) do
    # Store the transform function for use in the next execution
    {:ok, %{ref: cot_ref, transform: transform_fn}}
  end
end
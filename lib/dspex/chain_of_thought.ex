defmodule DSPex.ChainOfThought do
  @moduledoc """
  High-level wrapper for Chain of Thought reasoning functionality.
  
  This module provides a simplified API for chain-of-thought operations,
  delegating to the contract-based implementation while maintaining
  backward compatibility.
  
  ## Examples
  
      # Simple usage
      {:ok, result} = DSPex.ChainOfThought.think(
        "What are the environmental impacts of electric vehicles?",
        signature: "question -> reasoning, answer"
      )
      
      # With session
      {:ok, session} = DSPex.Session.new()
      {:ok, cot} = DSPex.ChainOfThought.new("question -> reasoning, answer", session: session)
      {:ok, result} = DSPex.ChainOfThought.execute(cot, %{
        question: "How does photosynthesis work?"
      })
      
      # Access reasoning steps
      IO.puts("Reasoning: #{result.reasoning}")
      IO.puts("Answer: #{result.answer}")
  """
  
  alias DSPex.Modules.ContractBased.ChainOfThought, as: ContractImpl
  
  @doc """
  Create a new ChainOfThought instance.
  
  ## Options
  
  - `:session` - DSPex.Session to use for this instance
  - `:rationale_type` - Type of rationale field (default: "reasoning")
  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:temperature` - LLM temperature setting (default: 0.7)
  """
  defdelegate new(signature, opts \\ []), to: ContractImpl
  
  @doc """
  Execute chain-of-thought reasoning.
  
  Takes an instance created with `new/2` and input parameters.
  """
  defdelegate execute(cot_ref, inputs, opts \\ []), to: ContractImpl
  
  @doc """
  Create a ChainOfThought instance (contract-based API).
  
  ## Parameters
  
  - `params` - Map with `:signature` and optional configuration
  - `opts` - Additional options
  """
  defdelegate create(params, opts \\ []), to: ContractImpl
  
  @doc """
  Execute reasoning (contract-based API).
  
  Takes an instance and input parameters.
  """
  defdelegate think(cot_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  One-shot chain-of-thought reasoning.
  
  Combines creation and execution in a single call.
  
  ## Examples
  
      {:ok, result} = DSPex.ChainOfThought.think(
        "Explain quantum computing",
        signature: "topic -> reasoning, explanation"
      )
  """
  def think(input, opts \\ []) when is_binary(input) do
    signature = opts[:signature] || "question -> reasoning, answer"
    
    create_params = %{
      signature: signature,
      rationale_type: opts[:rationale_type],
      max_retries: opts[:max_retries],
      temperature: opts[:temperature]
    }
    
    think_params = case String.split(signature, " -> ") do
      [inputs, _outputs] ->
        [field | _] = String.split(inputs, ", ")
        %{String.to_atom(String.trim(field)) => input}
      _ ->
        %{question: input}
    end
    
    ContractImpl.call(create_params, think_params, opts)
  end
  
  @doc """
  Create and execute in one call.
  """
  defdelegate call(create_params, think_params, opts \\ []), to: ContractImpl
  
  @doc """
  Get reasoning steps from the last execution.
  """
  defdelegate get_steps(cot_ref, opts \\ []), to: ContractImpl
  
  @doc """
  Compile the chain-of-thought module with an optimizer.
  
  ## Examples
  
      {:ok, compiled} = DSPex.ChainOfThought.compile(cot,
        optimizer: "BootstrapFewShotWithRandomSearch",
        trainset: training_examples
      )
  """
  defdelegate compile(cot_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Reset the module state.
  """
  defdelegate reset(cot_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Forward pass with raw parameters.
  """
  defdelegate forward(cot_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Batch processing of multiple inputs.
  """
  defdelegate batch_forward(cot_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Configure a custom rationale field type.
  """
  defdelegate set_rationale_type(cot_ref, type, opts \\ []), to: ContractImpl
  
  @doc """
  Apply a custom result transformation.
  """
  defdelegate with_transform(cot_ref, transform_fn, opts \\ []), to: ContractImpl
end
defmodule DSPex.Contracts.ChainOfThought do
  @moduledoc """
  Contract for DSPy ChainOfThought functionality.
  
  Defines the interface for chain-of-thought reasoning operations that generate
  step-by-step reasoning before producing the final answer. This helps with
  complex reasoning tasks and provides interpretability.
  
  ## Signature Format
  
  The signature follows the pattern: "input1, input2 -> reasoning, output"
  
  Examples:
  - "question -> reasoning, answer"
  - "context, question -> reasoning, answer"
  - "problem -> approach, solution"
  """
  
  @python_class "dspy.ChainOfThought"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string},
      rationale_type: {:optional, :string, "reasoning"},
      max_retries: {:optional, :integer, 3},
      explain_errors: {:optional, :boolean, false},
      temperature: {:optional, :float, 0.7}
    ],
    returns: :reference,
    description: "Create a new ChainOfThought instance with the given signature"
    
  defmethod :think, :__call__,
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.ChainOfThoughtResult},
    description: "Execute chain-of-thought reasoning with the given inputs"
    
  defmethod :forward, :forward,
    params: :variable_keyword,
    returns: :map,
    description: "Forward pass with arbitrary keyword arguments. Returns raw result data."
    
  defmethod :batch_forward, :batch_forward,
    params: [
      inputs: {:required, {:list, :map}}
    ],
    returns: {:list, :map},
    description: "Execute chain-of-thought reasoning on multiple inputs in a batch"
    
  defmethod :compile, :compile,
    params: [
      optimizer: {:optional, :string, "BootstrapFewShotWithRandomSearch"},
      metric: {:optional, :reference, nil},
      trainset: {:optional, :list, []},
      num_threads: {:optional, :integer, 4}
    ],
    returns: :reference,
    description: "Compile the chain-of-thought module with an optimizer"
    
  defmethod :inspect_signature, :inspect_signature,
    params: [],
    returns: :map,
    description: "Get detailed information about the signature fields"
    
  defmethod :get_reasoning_steps, :get_reasoning_steps,
    params: [],
    returns: {:list, :string},
    description: "Get the individual reasoning steps from the last execution"
    
  defmethod :reset, :reset,
    params: [],
    returns: :map,
    description: "Reset the module state, clearing any cached examples or reasoning"
end
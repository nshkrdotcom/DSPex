defmodule DSPex.Contracts.Predict do
  @moduledoc """
  Contract for DSPy Predict functionality.
  
  Defines the interface for prediction operations with typed parameters
  and return values. This is the fundamental building block for all DSPy modules.
  
  ## Signature Format
  
  The signature follows the pattern: "input1, input2 -> output1, output2"
  
  Examples:
  - "question -> answer"
  - "context, question -> answer"
  - "document -> summary, category"
  """
  
  @python_class "dspy.Predict"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string},
      max_retries: {:optional, :integer, 3},
      explain_errors: {:optional, :boolean, false},
      temperature: {:optional, :float, 0.7}
    ],
    returns: :reference,
    description: "Create a new Predict instance with the given signature and configuration"
    
  defmethod :predict, :__call__,
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.Prediction},
    description: "Execute prediction with the given inputs. Input keys must match signature."
    
  defmethod :forward, :forward,
    params: :variable_keyword,
    returns: :map,
    description: "Forward pass with arbitrary keyword arguments. Returns raw prediction data."
    
  defmethod :batch_forward, :batch_forward,
    params: [
      inputs: {:required, {:list, :map}}
    ],
    returns: {:list, :map},
    description: "Execute predictions on multiple inputs in a batch"
    
  defmethod :compile, :compile,
    params: [
      optimizer: {:optional, :string, "BootstrapFewShot"},
      metric: {:optional, :reference, nil},
      trainset: {:optional, :list, []},
      num_threads: {:optional, :integer, 4}
    ],
    returns: :reference,
    description: "Compile the predictor with an optimizer for improved performance"
    
  defmethod :inspect_signature, :inspect_signature,
    params: [],
    returns: :map,
    description: "Get detailed information about the signature fields"
    
  defmethod :reset, :reset,
    params: [],
    returns: :map,
    description: "Reset the predictor state, clearing any cached examples"
end
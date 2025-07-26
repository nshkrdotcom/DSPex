defmodule DSPex.Contracts.React do
  @moduledoc """
  Contract for DSPy ReAct (Reasoning and Acting) functionality.
  
  Defines the interface for ReAct operations that combine reasoning with
  tool usage. ReAct alternates between thinking about what to do and
  taking actions using tools, then observing the results.
  
  ## Signature Format
  
  The signature typically includes: "task -> thought, action, observation, answer"
  
  Examples:
  - "question -> thought, action, observation, answer"
  - "task, tools -> thought, action, observation, result"
  """
  
  @python_class "dspy.ReAct"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string},
      tools: {:optional, {:list, :reference}, []},
      max_iterations: {:optional, :integer, 5},
      early_stop: {:optional, :boolean, true},
      temperature: {:optional, :float, 0.7}
    ],
    returns: :reference,
    description: "Create a new ReAct instance with the given signature and tools"
    
  defmethod :react, :__call__,
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.ReactResult},
    description: "Execute ReAct loop with the given inputs"
    
  defmethod :forward, :forward,
    params: :variable_keyword,
    returns: :map,
    description: "Forward pass with arbitrary keyword arguments. Returns raw result data."
    
  defmethod :add_tool, :add_tool,
    params: [
      tool: {:required, :reference},
      name: {:optional, :string, nil},
      description: {:optional, :string, nil}
    ],
    returns: :map,
    description: "Add a tool that can be used during the ReAct loop"
    
  defmethod :remove_tool, :remove_tool,
    params: [
      name: {:required, :string}
    ],
    returns: :map,
    description: "Remove a tool by name"
    
  defmethod :list_tools, :list_tools,
    params: [],
    returns: {:list, :map},
    description: "Get a list of all available tools"
    
  defmethod :get_iterations, :get_iterations,
    params: [],
    returns: {:list, :map},
    description: "Get the full list of iterations from the last execution"
    
  defmethod :compile, :compile,
    params: [
      optimizer: {:optional, :string, "BootstrapFewShotWithRandomSearch"},
      metric: {:optional, :reference, nil},
      trainset: {:optional, :list, []},
      num_threads: {:optional, :integer, 4}
    ],
    returns: :reference,
    description: "Compile the ReAct module with an optimizer"
    
  defmethod :reset, :reset,
    params: [],
    returns: :map,
    description: "Reset the module state, clearing any cached iterations"
end
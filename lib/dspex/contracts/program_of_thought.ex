defmodule DSPex.Contracts.ProgramOfThought do
  @moduledoc """
  Contract for DSPy ProgramOfThought functionality.
  
  Defines the interface for program-of-thought operations that solve problems
  by generating and executing code. This approach is particularly effective
  for mathematical, algorithmic, and data processing tasks.
  
  ## Signature Format
  
  The signature typically includes: "problem -> code, explanation"
  
  Examples:
  - "problem -> code, explanation"
  - "task -> program, rationale, result"
  - "data, query -> code, explanation, output"
  """
  
  @python_class "dspy.ProgramOfThought"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string},
      language: {:optional, :string, "python"},
      execute_code: {:optional, :boolean, true},
      sandbox: {:optional, :boolean, true},
      max_iterations: {:optional, :integer, 3},
      temperature: {:optional, :float, 0.7}
    ],
    returns: :reference,
    description: "Create a new ProgramOfThought instance with the given signature"
    
  defmethod :solve, :__call__,
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.ProgramOfThoughtResult},
    description: "Solve the problem by generating and executing code"
    
  defmethod :forward, :forward,
    params: :variable_keyword,
    returns: :map,
    description: "Forward pass with arbitrary keyword arguments. Returns raw result data."
    
  defmethod :generate_code, :generate_code,
    params: :variable_keyword,
    returns: :string,
    description: "Generate code without executing it"
    
  defmethod :execute_code, :execute_code,
    params: [
      code: {:required, :string},
      context: {:optional, :map, %{}}
    ],
    returns: :map,
    description: "Execute the given code in a sandboxed environment"
    
  defmethod :set_language, :set_language,
    params: [
      language: {:required, :string}
    ],
    returns: :map,
    description: "Change the programming language for code generation"
    
  defmethod :get_imports, :get_imports,
    params: [],
    returns: {:list, :string},
    description: "Get the list of imports used in generated code"
    
  defmethod :get_execution_history, :get_execution_history,
    params: [],
    returns: {:list, :map},
    description: "Get the history of code executions"
    
  defmethod :compile, :compile,
    params: [
      optimizer: {:optional, :string, "BootstrapFewShotWithRandomSearch"},
      metric: {:optional, :reference, nil},
      trainset: {:optional, :list, []},
      num_threads: {:optional, :integer, 4}
    ],
    returns: :reference,
    description: "Compile the module with an optimizer"
    
  defmethod :reset, :reset,
    params: [],
    returns: :map,
    description: "Reset the module state, clearing execution history"
end
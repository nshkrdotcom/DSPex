defmodule DSPex.ProgramOfThought do
  @moduledoc """
  High-level wrapper for Program of Thought functionality.
  
  This module provides a simplified API for solving problems by
  generating and executing code, particularly effective for
  mathematical and algorithmic tasks.
  
  ## Examples
  
      # Simple usage
      {:ok, result} = DSPex.ProgramOfThought.solve(
        "Find all prime numbers less than 50",
        language: "python"
      )
      
      # With session
      {:ok, session} = DSPex.Session.new()
      {:ok, solver} = DSPex.ProgramOfThought.new(
        "problem -> code, explanation",
        language: "elixir",
        session: session
      )
      {:ok, result} = DSPex.ProgramOfThought.execute(solver, %{
        problem: "Implement a binary search algorithm"
      })
      
      # Access generated code
      IO.puts("Code:\\n#{result.code}")
      IO.puts("Explanation: #{result.explanation}")
      IO.puts("Output: #{inspect(result.execution_result)}")
  """
  
  alias DSPex.Modules.ContractBased.ProgramOfThought, as: ContractImpl
  
  @doc """
  Create a new ProgramOfThought instance.
  
  ## Options
  
  - `:session` - DSPex.Session to use for this instance
  - `:language` - Programming language to use (default: "python")
  - `:execute_code` - Whether to execute generated code (default: true)
  - `:sandbox` - Use sandboxed execution (default: true)
  - `:max_iterations` - Maximum code generation attempts (default: 3)
  - `:temperature` - LLM temperature setting (default: 0.7)
  """
  defdelegate new(signature, opts \\ []), to: ContractImpl
  
  @doc """
  Execute program generation and execution.
  
  Takes an instance created with `new/2` and input parameters.
  """
  defdelegate execute(solver_ref, inputs, opts \\ []), to: ContractImpl
  
  @doc """
  Create a ProgramOfThought instance (contract-based API).
  
  ## Parameters
  
  - `params` - Map with `:signature` and optional configuration
  - `opts` - Additional options
  """
  defdelegate create(params, opts \\ []), to: ContractImpl
  
  @doc """
  Solve a problem by generating and executing code (contract-based API).
  
  Takes an instance and problem parameters.
  """
  defdelegate solve(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  One-shot problem solving.
  
  Combines creation and execution in a single call.
  
  ## Examples
  
      {:ok, result} = DSPex.ProgramOfThought.solve(
        "Calculate the Fibonacci sequence up to n=20",
        language: "python"
      )
      
      {:ok, result} = DSPex.ProgramOfThought.solve(
        "Sort this list: [5, 2, 8, 1, 9]",
        language: "elixir",
        execute_code: true
      )
  """
  def solve(input, opts \\ []) when is_binary(input) do
    signature = opts[:signature] || "problem -> code, explanation"
    
    create_params = %{
      signature: signature,
      language: opts[:language],
      execute_code: opts[:execute_code],
      sandbox: opts[:sandbox],
      max_iterations: opts[:max_iterations],
      temperature: opts[:temperature]
    }
    
    solve_params = case String.split(signature, " -> ") do
      [inputs, _outputs] ->
        [field | _] = String.split(inputs, ", ")
        %{String.to_atom(String.trim(field)) => input}
      _ ->
        %{problem: input}
    end
    
    ContractImpl.call(create_params, solve_params, opts)
  end
  
  @doc """
  Create and execute in one call.
  """
  defdelegate call(create_params, solve_params, opts \\ []), to: ContractImpl
  
  @doc """
  Generate code without executing it.
  """
  defdelegate generate_only(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Generate code without executing (alias).
  """
  defdelegate generate_code(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Execute previously generated code.
  """
  defdelegate run_code(solver_ref, code, context \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Execute code with context (contract-based API).
  """
  defdelegate execute_code(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Change the programming language.
  """
  defdelegate set_language(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Get imports used in generated code.
  """
  defdelegate get_imports(solver_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Get execution history.
  """
  defdelegate get_history(solver_ref, opts \\ []), to: ContractImpl
  
  @doc """
  Get execution history (contract-based API).
  """
  defdelegate get_execution_history(solver_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Validate code safety before execution.
  """
  defdelegate validate_code(code, language), to: ContractImpl
  
  @doc """
  Create a code template.
  
  ## Examples
  
      template = DSPex.ProgramOfThought.make_template(:python,
        imports: ["import numpy as np", "import pandas as pd"],
        setup: "# Load data",
        cleanup: "# Clean up"
      )
  """
  defdelegate make_template(language, opts \\ []), to: ContractImpl
  
  @doc """
  Compile the module with an optimizer.
  
  ## Examples
  
      {:ok, compiled} = DSPex.ProgramOfThought.compile(solver,
        optimizer: "BootstrapFewShotWithRandomSearch",
        trainset: training_examples
      )
  """
  defdelegate compile(solver_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Reset the module state.
  """
  defdelegate reset(solver_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Forward pass with raw parameters.
  """
  defdelegate forward(solver_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Set execution timeout.
  """
  defdelegate set_timeout(solver_ref, timeout_ms, opts \\ []), to: ContractImpl
  
  @doc """
  Configure allowed imports.
  """
  defdelegate set_allowed_imports(solver_ref, imports, opts \\ []), to: ContractImpl
  
  @doc """
  Apply custom code transformation.
  """
  defdelegate with_code_transform(solver_ref, transform_fn, opts \\ []), to: ContractImpl
  
  @doc """
  Enable step-by-step execution mode.
  """
  defdelegate enable_step_mode(solver_ref, opts \\ []), to: ContractImpl
end
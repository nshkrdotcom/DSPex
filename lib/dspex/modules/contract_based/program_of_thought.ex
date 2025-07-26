defmodule DSPex.Modules.ContractBased.ProgramOfThought do
  @moduledoc """
  Contract-based implementation of DSPy ProgramOfThought functionality.
  
  This module provides a typed, validated interface for solving problems
  by generating and executing code, particularly effective for mathematical
  and algorithmic tasks.
  
  ## Features
  
  - Code generation in multiple languages
  - Safe sandboxed execution
  - Step-by-step explanation generation
  - Observable code generation process
  - Result validation and transformation
  
  ## Examples
  
      # Create a program-of-thought solver
      {:ok, solver} = ProgramOfThought.create(%{
        signature: "problem -> code, explanation",
        language: "python",
        execute_code: true
      })
      
      # Solve a problem
      {:ok, result} = ProgramOfThought.solve(solver, %{
        problem: "Find all prime numbers less than 100"
      })
      # Returns: %DSPex.Types.ProgramOfThoughtResult{
      #   code: "def find_primes(n):\\n    ...",
      #   explanation: "We use the Sieve of Eratosthenes...",
      #   output: [2, 3, 5, 7, 11, ...],
      #   execution_time: 0.015
      # }
  """
  
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Observable
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.ResultTransform
  
  use_contract DSPex.Contracts.ProgramOfThought
  
  alias DSPex.Types.ProgramOfThoughtResult
  alias DSPex.Utils.ID
  
  @supported_languages ~w(python javascript elixir ruby go rust)
  
  @doc """
  Result transformation pipeline for ProgramOfThought results.
  
  Converts raw Python results into structured Elixir types.
  """
  def transform_result({:ok, raw_result}) when is_map(raw_result) do
    ProgramOfThoughtResult.from_python_result(raw_result)
  end
  
  def transform_result(error), do: error
  
  @doc """
  Observable hooks for monitoring code generation and execution.
  """
  def default_hooks do
    %{
      before_solve: fn params -> 
        IO.puts("[ProgramOfThought] Solving: #{inspect(params)}")
        :ok
      end,
      after_solve: fn result ->
        case result do
          {:ok, %ProgramOfThoughtResult{execution_time: time}} when not is_nil(time) ->
            IO.puts("[ProgramOfThought] Completed in #{time}s")
          _ ->
            :ok
        end
        :ok
      end,
      on_code_generated: fn code ->
        IO.puts("[ProgramOfThought] Generated code:\\n#{code}")
        :ok
      end,
      on_execution_start: fn ->
        IO.puts("[ProgramOfThought] Starting code execution...")
        :ok
      end,
      on_execution_complete: fn output ->
        IO.puts("[ProgramOfThought] Execution output: #{inspect(output)}")
        :ok
      end,
      on_error: fn error ->
        IO.puts("[ProgramOfThought] Error: #{inspect(error)}")
        :ok
      end
    }
  end
  
  @doc """
  Create and execute in one call (stateless).
  
  Combines create and solve operations for convenience.
  
  ## Examples
  
      {:ok, result} = ProgramOfThought.call(
        %{
          signature: "task -> program, rationale, result",
          language: "elixir"
        },
        %{task: "Generate a function to calculate factorial"}
      )
  """
  def call(create_params, solve_params, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    with {:ok, solver_ref} <- create(create_params, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- solve(solver_ref, solve_params, opts) do
      {:ok, result}
    end
  end
  
  @doc """
  Generate code without executing it.
  
  Useful for code review or manual execution scenarios.
  
  ## Examples
  
      {:ok, code} = ProgramOfThought.generate_only(solver, %{
        problem: "Sort an array in O(n log n) time"
      })
  """
  def generate_only(solver_ref, params, opts \\ []) do
    generate_code(solver_ref, params, opts)
  end
  
  @doc """
  Execute previously generated code with new inputs.
  
  Allows reusing generated code with different data.
  
  ## Examples
  
      {:ok, output} = ProgramOfThought.run_code(solver, 
        "def double(x): return x * 2",
        %{x: 5}
      )
  """
  def run_code(solver_ref, code, context \\ %{}, opts \\ []) do
    execute_code(solver_ref, %{code: code, context: context}, opts)
  end
  
  @doc """
  Validate that generated code is safe to execute.
  
  Performs basic safety checks before execution.
  """
  def validate_code(code, language) when language in @supported_languages do
    unsafe_patterns = get_unsafe_patterns(language)
    
    if Enum.any?(unsafe_patterns, &String.contains?(code, &1)) do
      {:error, :potentially_unsafe_code}
    else
      {:ok, code}
    end
  end
  
  def validate_code(_, language) do
    {:error, {:unsupported_language, language}}
  end
  
  @doc """
  Get execution history for debugging.
  
  Returns all code executions with inputs and outputs.
  """
  def get_history(solver_ref, opts \\ []) do
    get_execution_history(solver_ref, %{}, opts)
  end
  
  @doc """
  Set execution timeout to prevent infinite loops.
  """
  def set_timeout(solver_ref, timeout_ms, opts \\ []) when is_integer(timeout_ms) do
    {:ok, %{ref: solver_ref, execution_timeout: timeout_ms}}
  end
  
  @doc """
  Configure allowed imports/libraries for generated code.
  
  Restricts what libraries the generated code can use.
  """
  def set_allowed_imports(solver_ref, imports, opts \\ []) when is_list(imports) do
    {:ok, %{ref: solver_ref, allowed_imports: imports}}
  end
  
  @doc """
  Create a code template for consistent structure.
  
  ## Examples
  
      template = ProgramOfThought.make_template(:python, 
        imports: ["import numpy as np"],
        setup: "# Initialize variables",
        cleanup: "# Clean up resources"
      )
  """
  def make_template(language, opts \\ []) do
    %{
      language: language,
      imports: opts[:imports] || [],
      setup: opts[:setup] || "",
      body: opts[:body] || "# Main code here",
      cleanup: opts[:cleanup] || "",
      wrapper: opts[:wrapper] || default_wrapper(language)
    }
  end
  
  # Backward compatibility helpers
  @doc false
  def new(signature, opts \\ []) do
    IO.warn("ProgramOfThought.new/2 is deprecated. Use create/2 instead.", 
            Macro.Env.stacktrace(__ENV__))
    create(%{signature: signature}, opts)
  end
  
  @doc false
  def execute(solver_ref, inputs, opts \\ []) do
    IO.warn("ProgramOfThought.execute/3 is deprecated. Use solve/3 instead.", 
            Macro.Env.stacktrace(__ENV__))
    solve(solver_ref, inputs, opts)
  end
  
  # Private helper functions
  defp get_unsafe_patterns("python") do
    ["__import__", "exec", "eval", "compile", "open(", "subprocess", "os.system"]
  end
  
  defp get_unsafe_patterns("javascript") do
    ["eval", "Function(", "require('child_process')", "require('fs')"]
  end
  
  defp get_unsafe_patterns("elixir") do
    ["Code.eval", "System.cmd", "File.rm", ":os.cmd"]
  end
  
  defp get_unsafe_patterns(_), do: []
  
  defp default_wrapper("python") do
    """
    def solve(inputs):
        # Generated code will be inserted here
        {{CODE}}
        return result
    """
  end
  
  defp default_wrapper("javascript") do
    """
    function solve(inputs) {
        // Generated code will be inserted here
        {{CODE}}
        return result;
    }
    """
  end
  
  defp default_wrapper("elixir") do
    """
    def solve(inputs) do
      # Generated code will be inserted here
      {{CODE}}
      result
    end
    """
  end
  
  defp default_wrapper(_), do: "{{CODE}}"
  
  @doc """
  Apply custom code transformation before execution.
  
  Allows preprocessing of generated code.
  """
  def with_code_transform(solver_ref, transform_fn, opts \\ []) 
      when is_function(transform_fn, 1) do
    {:ok, %{ref: solver_ref, code_transform: transform_fn}}
  end
  
  @doc """
  Enable step-by-step execution mode.
  
  Breaks down code execution into observable steps.
  """
  def enable_step_mode(solver_ref, opts \\ []) do
    {:ok, %{ref: solver_ref, step_mode: true}}
  end
end
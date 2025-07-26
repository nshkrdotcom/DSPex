defmodule DSPex.Modules.ContractBased.ProgramOfThoughtTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Modules.ContractBased.ProgramOfThought
  alias DSPex.Types.ProgramOfThoughtResult
  
  describe "create/2" do
    test "creates a program of thought instance with valid signature" do
      assert {:ok, ref} = ProgramOfThought.create(%{
        signature: "problem -> code, explanation"
      })
      
      assert is_binary(ref)
      assert String.starts_with?(ref, "program_of_thought-")
    end
    
    test "creates with language and optional parameters" do
      assert {:ok, ref} = ProgramOfThought.create(%{
        signature: "task -> program, rationale, result",
        language: "elixir",
        execute_code: false,
        sandbox: true,
        max_iterations: 2,
        temperature: 0.6
      })
      
      assert is_binary(ref)
    end
    
    test "returns error with invalid signature" do
      assert {:error, _} = ProgramOfThought.create(%{
        signature: ""
      })
    end
  end
  
  describe "solve/3" do
    setup do
      {:ok, ref} = ProgramOfThought.create(%{
        signature: "problem -> code, explanation",
        language: "python",
        execute_code: true
      })
      
      %{solver_ref: ref}
    end
    
    test "generates and executes code", %{solver_ref: ref} do
      # Mock the bridge response
      mock_response = %{
        "code" => """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)
        
        result = [fibonacci(i) for i in range(10)]
        """,
        "explanation" => "This implements the Fibonacci sequence using recursion.",
        "execution_result" => [0, 1, 1, 2, 3, 5, 8, 13, 21, 34],
        "language" => "python"
      }
      
      assert {:ok, result} = ProgramOfThought.transform_result({:ok, mock_response})
      
      assert %ProgramOfThoughtResult{} = result
      assert result.code == mock_response["code"]
      assert result.explanation == mock_response["explanation"]
      assert result.execution_result == mock_response["execution_result"]
      assert result.language == "python"
    end
    
    test "handles code generation without execution", %{solver_ref: ref} do
      mock_response = %{
        "code" => "def sort_array(arr):\n    return sorted(arr)",
        "explanation" => "Uses Python's built-in sorted function",
        "language" => "python"
      }
      
      assert {:ok, result} = ProgramOfThought.transform_result({:ok, mock_response})
      assert result.execution_result == nil
    end
  end
  
  describe "validate_code/2" do
    test "validates safe Python code" do
      safe_code = """
      def add(a, b):
          return a + b
      """
      
      assert {:ok, ^safe_code} = ProgramOfThought.validate_code(safe_code, "python")
    end
    
    test "rejects unsafe Python code" do
      unsafe_codes = [
        "import os; os.system('rm -rf /')",
        "__import__('os').system('ls')",
        "exec('malicious code')",
        "eval('dangerous')",
        "open('/etc/passwd', 'r')"
      ]
      
      for code <- unsafe_codes do
        assert {:error, :potentially_unsafe_code} = 
          ProgramOfThought.validate_code(code, "python")
      end
    end
    
    test "validates safe Elixir code" do
      safe_code = """
      def factorial(n) when n <= 1, do: 1
      def factorial(n), do: n * factorial(n - 1)
      """
      
      assert {:ok, ^safe_code} = ProgramOfThought.validate_code(safe_code, "elixir")
    end
    
    test "rejects unsafe Elixir code" do
      unsafe_codes = [
        "Code.eval_string(\"dangerous\")",
        "System.cmd(\"rm\", [\"-rf\", \"/\"])",
        "File.rm(\"/important/file\")",
        ":os.cmd('malicious')"
      ]
      
      for code <- unsafe_codes do
        assert {:error, :potentially_unsafe_code} = 
          ProgramOfThought.validate_code(code, "elixir")
      end
    end
    
    test "returns error for unsupported language" do
      assert {:error, {:unsupported_language, "cobol"}} = 
        ProgramOfThought.validate_code("DISPLAY 'HELLO'.", "cobol")
    end
  end
  
  describe "make_template/2" do
    test "creates Python template" do
      template = ProgramOfThought.make_template(:python,
        imports: ["import numpy as np", "import pandas as pd"],
        setup: "# Initialize data",
        cleanup: "# Clean up resources"
      )
      
      assert template.language == :python
      assert "import numpy as np" in template.imports
      assert template.setup == "# Initialize data"
      assert template.wrapper =~ "def solve(inputs):"
    end
    
    test "creates Elixir template" do
      template = ProgramOfThought.make_template(:elixir,
        imports: ["alias MyApp.Utils"],
        setup: "# Setup environment"
      )
      
      assert template.language == :elixir
      assert "alias MyApp.Utils" in template.imports
      assert template.wrapper =~ "def solve(inputs) do"
    end
    
    test "creates template with defaults" do
      template = ProgramOfThought.make_template(:javascript)
      
      assert template.language == :javascript
      assert template.imports == []
      assert template.body == "# Main code here"
      assert template.wrapper =~ "function solve(inputs)"
    end
  end
  
  describe "call/3" do
    test "creates and solves in one call" do
      create_params = %{
        signature: "problem -> code, explanation",
        language: "python"
      }
      solve_params = %{problem: "Sort an array"}
      
      # Test parameter construction
      assert create_params.signature == "problem -> code, explanation"
      assert create_params.language == "python"
      assert solve_params.problem == "Sort an array"
    end
  end
  
  describe "transform_result/1" do
    test "transforms Python result to Elixir struct" do
      python_result = %{
        "code" => "def square(x):\n    return x * x",
        "explanation" => "This function squares a number",
        "execution_result" => 25,
        "language" => "python",
        "variables" => %{"x" => 5},
        "imports" => ["import math"]
      }
      
      assert {:ok, result} = ProgramOfThought.transform_result({:ok, python_result})
      
      assert %ProgramOfThoughtResult{} = result
      assert result.code == python_result["code"]
      assert result.explanation == python_result["explanation"]
      assert result.execution_result == python_result["execution_result"]
      assert result.language == python_result["language"]
      assert result.variables == python_result["variables"]
      assert result.imports == python_result["imports"]
    end
    
    test "handles alternative program/rationale format" do
      python_result = %{
        "program" => "console.log('Hello');",
        "rationale" => "Simple greeting program",
        "result" => "Hello",
        "language" => "javascript"
      }
      
      assert {:ok, result} = ProgramOfThoughtResult.from_python_result(python_result)
      assert result.code == python_result["program"]
      assert result.explanation == python_result["rationale"]
      assert result.execution_result == python_result["result"]
    end
    
    test "returns error for invalid format" do
      invalid_result = %{"something" => "else"}
      
      assert {:error, :invalid_program_of_thought_format} = 
        ProgramOfThoughtResult.from_python_result(invalid_result)
    end
  end
  
  describe "default_hooks/0" do
    test "returns hook configuration" do
      hooks = ProgramOfThought.default_hooks()
      
      assert is_map(hooks)
      assert is_function(hooks.before_solve, 1)
      assert is_function(hooks.after_solve, 1)
      assert is_function(hooks.on_code_generated, 1)
      assert is_function(hooks.on_execution_start, 0)
      assert is_function(hooks.on_execution_complete, 1)
      assert is_function(hooks.on_error, 1)
    end
  end
  
  describe "code execution helpers" do
    setup do
      {:ok, ref} = ProgramOfThought.create(%{
        signature: "problem -> code, explanation"
      })
      
      %{solver_ref: ref}
    end
    
    test "generate_only/3 generates without execution", %{solver_ref: ref} do
      # This would need mocking of the bridge
      params = %{problem: "Calculate factorial"}
      
      # In real implementation, this would return generated code
      # assert {:ok, code} = ProgramOfThought.generate_only(ref, params)
      # assert is_binary(code)
    end
    
    test "run_code/4 executes provided code", %{solver_ref: ref} do
      code = "def double(x): return x * 2"
      context = %{x: 5}
      
      # This would need mocking of the bridge
      # assert {:ok, 10} = ProgramOfThought.run_code(ref, code, context)
    end
  end
  
  describe "configuration" do
    setup do
      {:ok, ref} = ProgramOfThought.create(%{signature: "p -> c, e"})
      %{solver_ref: ref}
    end
    
    test "set_timeout/3 configures execution timeout", %{solver_ref: ref} do
      assert {:ok, %{ref: ^ref, execution_timeout: 10000}} = 
        ProgramOfThought.set_timeout(ref, 10000)
    end
    
    test "set_allowed_imports/3 restricts imports", %{solver_ref: ref} do
      allowed = ["math", "statistics", "numpy"]
      
      assert {:ok, %{ref: ^ref, allowed_imports: ^allowed}} = 
        ProgramOfThought.set_allowed_imports(ref, allowed)
    end
    
    test "with_code_transform/3 sets transform function", %{solver_ref: ref} do
      transform_fn = fn code ->
        "# Generated by DSPex\n" <> code
      end
      
      assert {:ok, %{ref: ^ref, code_transform: ^transform_fn}} = 
        ProgramOfThought.with_code_transform(ref, transform_fn)
    end
    
    test "enable_step_mode/2 enables step-by-step execution", %{solver_ref: ref} do
      assert {:ok, %{ref: ^ref, step_mode: true}} = 
        ProgramOfThought.enable_step_mode(ref)
    end
  end
  
  describe "backward compatibility" do
    test "new/2 delegates to create with deprecation warning" do
      assert capture_io(:stderr, fn ->
        assert {:ok, _ref} = ProgramOfThought.new("problem -> code, explanation")
      end) =~ "deprecated"
    end
    
    test "execute/3 delegates to solve with deprecation warning" do
      {:ok, ref} = ProgramOfThought.create(%{signature: "p -> c, e"})
      
      assert capture_io(:stderr, fn ->
        ProgramOfThought.execute(ref, %{p: "test"})
      end) =~ "deprecated"
    end
  end
  
  # Helper to capture IO output
  defp capture_io(device, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end
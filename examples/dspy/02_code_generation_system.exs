# Code Generation System - Demonstrates ProgramOfThought, ReAct, and Retry modules
# Run with: mix run examples/dspy/02_code_generation_system.exs

# Configure Snakepit for pooling
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :wire_protocol, :auto)
Application.put_env(:snakepit, :pool_config, %{pool_size: 4})

# Stop and restart applications if already started
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Configure Gemini 2.0 Flash as default language model
api_key = System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
if api_key do
  IO.puts("Configuring Gemini 2.0 Flash for code generation...")
  DSPex.LM.configure("gemini/gemini-2.0-flash", api_key: api_key)
else
  IO.puts("WARNING: No Gemini API key found!")
  IO.puts("Set GOOGLE_API_KEY or GEMINI_API_KEY environment variable.")
  IO.puts("Running in mock mode...")
  DSPex.LM.configure("mock/gemini")
end

defmodule CodeGenerationSystem do
  @moduledoc """
  Advanced code generation system demonstrating:
  - ProgramOfThought: Code-based problem solving
  - ReAct: Tool usage for testing and validation
  - Retry: Self-refinement of generated code
  - MIPRO: Advanced optimization
  - Settings: Configuration management
  """
  
  def run do
    IO.puts("\n=== Code Generation System Demo ===\n")
    
    # 1. Program of Thought for algorithmic problems
    demo_program_of_thought()
    
    # 2. ReAct for interactive development
    demo_react()
    
    # 3. Retry for code refinement
    demo_retry()
    
    # 4. MIPRO optimization
    demo_mipro()
    
    # 5. Settings and configuration
    demo_settings()
  end
  
  defp demo_program_of_thought do
    IO.puts("1. Program of Thought - Algorithmic Problem Solving")
    IO.puts("--------------------------------------------------")
    
    {:ok, pot} = DSPex.Modules.ProgramOfThought.create(
      "problem: str -> code: str, explanation: str, result: str"
    )
    
    problems = [
      "Write a function to find the nth Fibonacci number",
      "Create a function that checks if a string is a palindrome",
      "Implement a function to find all prime numbers up to n"
    ]
    
    for problem <- problems do
      {:ok, solution} = DSPex.Modules.ProgramOfThought.execute(pot, %{problem: problem})
      
      IO.puts("\nProblem: #{problem}")
      IO.puts("\nGenerated Code:")
      IO.puts("```")
      # Extract fields safely - from result.prediction_data
      code = get_in(solution, ["result", "prediction_data", "code"]) || "No code field"
      explanation = get_in(solution, ["result", "prediction_data", "explanation"]) || "No explanation field" 
      result_text = get_in(solution, ["result", "prediction_data", "result"]) || "No result field"
      
      IO.puts(code)
      IO.puts("```")
      IO.puts("\nExplanation: #{explanation}")
      IO.puts("Result: #{result_text}")
      IO.puts("\n" <> String.duplicate("-", 50))
    end
  end
  
  defp demo_react do
    IO.puts("\n\n2. ReAct - Interactive Development with Tools")
    IO.puts("---------------------------------------------")
    
    # Define mock tools for code development
    tools = [
      %{
        name: "run_code",
        description: "Execute Python code and return the output",
        func: &mock_run_code/1
      },
      %{
        name: "run_tests",
        description: "Run unit tests on the code",
        func: &mock_run_tests/1
      },
      %{
        name: "analyze_complexity",
        description: "Analyze time and space complexity",
        func: &mock_analyze_complexity/1
      }
    ]
    
    {:ok, react} = DSPex.Modules.ReAct.create(
      "task: str -> code: str, test_results: str, final_code: str",
      tools
    )
    
    task = "Create a function to merge two sorted arrays efficiently"
    
    {:ok, result} = DSPex.Modules.ReAct.execute(react, %{task: task})
    
    IO.puts("Task: #{task}")
    IO.puts("\nDevelopment Process:")
    IO.puts("Initial Code: #{String.slice(get_in(result, ["result", "prediction_data", "code"]) || "No initial code", 0, 100)}...")
    IO.puts("Test Results: #{get_in(result, ["result", "prediction_data", "test_results"]) || "No test results"}")
    IO.puts("\nFinal Code:")
    IO.puts("```")
    IO.puts(get_in(result, ["result", "prediction_data", "final_code"]) || "No final code")
    IO.puts("```")
  end
  
  defp demo_retry do
    IO.puts("\n\n3. Retry - Self-Refinement of Code")
    IO.puts("-----------------------------------")
    
    {:ok, retry} = DSPex.Modules.Retry.create(
      "specification: str -> code: str, quality_score: float",
      max_attempts: 3
    )
    
    spec = "Write a function that efficiently finds the longest common subsequence of two strings"
    
    {:ok, result} = DSPex.Modules.Retry.execute(retry, %{specification: spec})
    
    IO.puts("Specification: #{spec}")
    IO.puts("\nRefined Code (after retries):")
    IO.puts("```")
    IO.puts(get_in(result, ["result", "prediction_data", "code"]) || "No code field")
    IO.puts("```")
    IO.puts("\nQuality Score: #{get_in(result, ["result", "prediction_data", "quality_score"]) || "N/A"}/10")
  end
  
  defp demo_mipro do
    IO.puts("\n\n4. MIPRO - Advanced Code Generation Optimization")
    IO.puts("------------------------------------------------")
    
    # Create a code generation predictor
    {:ok, code_gen} = DSPex.Modules.Predict.create(
      "problem: str, constraints: str -> solution: str"
    )
    
    # Training dataset for code generation
    trainset = [
      %{
        problem: "Sort an array",
        constraints: "O(n log n) time complexity",
        solution: "def quicksort(arr):\n    if len(arr) <= 1:\n        return arr\n    pivot = arr[len(arr) // 2]\n    left = [x for x in arr if x < pivot]\n    middle = [x for x in arr if x == pivot]\n    right = [x for x in arr if x > pivot]\n    return quicksort(left) + middle + quicksort(right)"
      },
      %{
        problem: "Find duplicates in array",
        constraints: "O(n) time, O(1) space if possible",
        solution: "def find_duplicates(nums):\n    duplicates = []\n    for num in nums:\n        index = abs(num) - 1\n        if nums[index] < 0:\n            duplicates.append(abs(num))\n        else:\n            nums[index] = -nums[index]\n    return duplicates"
      },
      %{
        problem: "Reverse a linked list",
        constraints: "Iterative approach",
        solution: "def reverse_list(head):\n    prev = None\n    current = head\n    while current:\n        next_node = current.next\n        current.next = prev\n        prev = current\n        current = next_node\n    return prev"
      }
    ]
    
    IO.puts("Training MIPRO optimizer with #{length(trainset)} examples...")
    
    {:ok, mipro_result} = DSPex.Optimizers.MIPRO.optimize(
      code_gen,
      trainset,
      num_candidates: 5,
      init_temperature: 0.7
    )
    
    IO.puts("MIPRO optimization complete!")
    
    # Test the optimized code generator
    test_problem = %{
      problem: "Implement binary search",
      constraints: "Recursive approach, handle edge cases"
    }
    
    {:ok, generated} = DSPex.Modules.Predict.execute(
      mipro_result.optimized_program_id,
      test_problem
    )
    
    IO.puts("\nTest Problem: #{test_problem.problem}")
    IO.puts("Constraints: #{test_problem.constraints}")
    IO.puts("\nMIPRO-Optimized Solution:")
    IO.puts("```")
    IO.puts(get_in(generated, ["result", "prediction_data", "solution"]) || "No solution generated")
    IO.puts("```")
  end
  
  defp demo_settings do
    IO.puts("\n\n5. Settings and Configuration Management")
    IO.puts("----------------------------------------")
    
    # Get current settings
    {:ok, current_settings} = DSPex.Settings.get_settings()
    IO.puts("Current Settings: #{inspect(current_settings)}")
    
    # Configure caching
    DSPex.Settings.configure_cache(
      enabled: true,
      cache_dir: ".dspex_cache",
      max_size: 1000
    )
    
    IO.puts("\nCache configured for better performance")
    
    # Use temporary settings for experimentation
    IO.puts("\nRunning with experimental settings...")
    
    result = DSPex.Settings.with_settings([temperature: 1.5], fn ->
      {:ok, creative} = DSPex.Modules.Predict.create("topic -> creative_code: str")
      {:ok, output} = DSPex.Modules.Predict.execute(creative, %{
        topic: "a function that generates ASCII art"
      })
      output
    end)
    
    IO.puts("Creative output with high temperature:")
    IO.puts(get_in(result, ["result", "prediction_data", "creative_code"]) || "No creative code generated")
  end
  
  # Mock tool functions
  defp mock_run_code(_code) do
    "Code executed successfully. Output: [1, 2, 3, 4, 5]"
  end
  
  defp mock_run_tests(_code) do
    "All tests passed (5/5)"
  end
  
  defp mock_analyze_complexity(_code) do
    "Time: O(n), Space: O(1)"
  end
end

# Run the system
CodeGenerationSystem.run()

IO.puts("\n\n=== Code Generation System Complete ===")
IO.puts("To use with real code generation:")
IO.puts("1. Set your Gemini API key: export GOOGLE_API_KEY=your-key")
IO.puts("2. Run again for actual code generation results")
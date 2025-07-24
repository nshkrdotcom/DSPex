# Code Generation System - Demonstrates ProgramOfThought, ReAct, and Retry modules
# Run with: mix run examples/dspy/02_code_generation_system.exs

# Configure Snakepit for pooling BEFORE starting
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 4,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Stop and restart applications if already started
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Check DSPy availability using new integration
case Snakepit.execute_in_session("code_gen_session", "check_dspy", %{}) do
  {:ok, %{"available" => true}} -> 
    IO.puts("✓ DSPy available")
  {:error, error} -> 
    IO.puts("✗ DSPy check failed: #{inspect(error)}")
    System.halt(1)
end

# Load config and configure Gemini as default language model
config_path = Path.join(__DIR__, "../config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  IO.puts("\n✓ Configuring Gemini...")
  IO.puts("  API Key: #{String.slice(api_key, 0..5)}...#{String.slice(api_key, -4..-1)}")
  
  # Configure Gemini using the gRPC bridge  
  case Snakepit.execute_in_session("code_gen_session", "configure_lm", %{
    "model_type" => "gemini", 
    "api_key" => api_key,
    "model" => config_data.model
  }) do
    {:ok, %{"success" => true}} -> IO.puts("  Successfully configured!")
    {:ok, %{"success" => false, "error" => error}} -> IO.puts("  Configuration error: #{error}")
    {:error, error} -> IO.puts("  Configuration error: #{inspect(error)}")
  end
else
  IO.puts("\n⚠️  WARNING: No Gemini API key found!")
  IO.puts("  Set GOOGLE_API_KEY or GEMINI_API_KEY environment variable.")
  IO.puts("  Get your free API key at: https://makersuite.google.com/app/apikey")
  IO.puts("  ")
  IO.puts("  Example: export GOOGLE_API_KEY=your-gemini-api-key")
  IO.puts("  ")
  IO.puts("  Running without LLM - examples will show expected errors...")
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
    
    case DSPex.Modules.Predict.create("problem -> code, explanation", session_id: "code_gen_session") do
      {:ok, predictor_ref} ->
        IO.puts("✓ Created Program of Thought predictor: #{inspect(predictor_ref)}")
        
        problems = [
          "Write a Python function to find the nth Fibonacci number",
          "Create a Python function that checks if a string is a palindrome", 
          "Implement a Python function to find all prime numbers up to n"
        ]
        
        for problem <- problems do
          case DSPex.Modules.Predict.execute(predictor_ref, %{"problem" => problem}) do
            {:ok, result} ->
              IO.puts("\nProblem: #{problem}")
              IO.puts("\nGenerated Code:")
              IO.puts("```")
              
              case result do
                %{"success" => true, "result" => %{"prediction_data" => prediction_data}} ->
                  code = prediction_data["code"] || prediction_data["answer"] || "No code generated"
                  explanation = prediction_data["explanation"] || "No explanation provided"
                  IO.puts(code)
                  IO.puts("```")
                  if explanation != "No explanation provided" do
                    IO.puts("\nExplanation: #{explanation}")
                  end
                %{"code" => code, "explanation" => explanation} ->
                  IO.puts(code)
                  IO.puts("```")
                  IO.puts("\nExplanation: #{explanation}")
                %{"answer" => answer_text} ->
                  IO.puts(answer_text)
                  IO.puts("```")
                _ ->
                  IO.puts("Generated response: #{inspect(result)}")
                  IO.puts("```")
              end
              
              IO.puts("\n" <> String.duplicate("-", 50))
            {:error, error} ->
              IO.puts("\nProblem: #{problem}")
              IO.puts("Error: #{error}")
              IO.puts("(Check that Gemini API key is configured properly)")
              IO.puts("\n" <> String.duplicate("-", 50))
          end
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create Program of Thought predictor: #{error}")
        IO.puts("(This likely means the LM is not configured properly)")
    end
  end
  
  defp demo_react do
    IO.puts("\n\n2. ReAct - Interactive Development with Tools")
    IO.puts("---------------------------------------------")
    
    task = "Create a function to merge two sorted arrays efficiently"
    IO.puts("Task: #{task}")
    
    # Try to create a DSPy ReAct instance using the schema bridge
    case DSPex.Bridge.create_instance("dspy.ReAct", %{"signature" => "task -> thought, action, observation, answer"}, session_id: "code_gen_session") do
      {:ok, react_ref} ->
        IO.puts("✓ Created ReAct instance: #{inspect(react_ref)}")
        
        case DSPex.Bridge.call_method(react_ref, "__call__", %{"task" => task}) do
          {:ok, %{"result" => result}} ->
            IO.puts("\nReAct Processing:")
            case result do
              %{"thought" => thought, "action" => action, "observation" => observation, "answer" => answer} ->
                IO.puts("💭 Thought: #{thought}")
                IO.puts("🎯 Action: #{action}")
                IO.puts("👁️  Observation: #{observation}")
                IO.puts("✅ Answer: #{answer}")
              %{"answer" => answer} ->
                IO.puts("✅ Answer: #{answer}")
              _ ->
                IO.puts("Result: #{inspect(result)}")
            end
          {:error, error} ->
            IO.puts("✗ ReAct execution failed: #{error}")
            show_react_mock()
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create ReAct instance: #{error}")
        IO.puts("(This might mean DSPy ReAct isn't available or needs different parameters)")
        show_react_mock()
    end
  end
  
  defp show_react_mock do
    IO.puts("\nMock ReAct Process (for reference):")
    IO.puts("1. Thought: I need to create a merge function for sorted arrays")
    IO.puts("2. Action: run_code(draft_merge_function)")
    IO.puts("3. Observation: Code works but can be optimized")
    IO.puts("4. Thought: Let me improve the efficiency")
    IO.puts("5. Action: run_tests(optimized_function)")
    IO.puts("6. Observation: All tests pass!")
    IO.puts("\nFinal Code: [Would contain optimized merge function]")
  end
  
  defp demo_retry do
    IO.puts("\n\n3. Retry - Self-Refinement of Code")
    IO.puts("-----------------------------------")
    
    spec = "Write a function that efficiently finds the longest common subsequence of two strings"
    IO.puts("Specification: #{spec}")
    
    # Try to use ChainOfThought for iterative refinement since Retry might not be directly available
    case DSPex.Modules.ChainOfThought.create("specification, previous_attempt -> reasoning, improved_code", session_id: "code_gen_session") do
      {:ok, refiner_ref} ->
        IO.puts("✓ Created code refiner: #{inspect(refiner_ref)}")
        
        previous_attempt = "Basic recursive approach without optimization"
        
        case DSPex.Modules.ChainOfThought.execute(refiner_ref, %{
          "specification" => spec,
          "previous_attempt" => previous_attempt
        }) do
          {:ok, result} ->
            IO.puts("\nCode Refinement Process:")
            case result do
              %{"success" => true, "result" => %{"prediction_data" => prediction_data}} ->
                reasoning = prediction_data["reasoning"] || "No reasoning provided"
                improved_code = prediction_data["improved_code"] || prediction_data["answer"] || "No improved code"
                
                IO.puts("🔄 Reasoning: #{reasoning}")
                IO.puts("\n💡 Improved Code:")
                IO.puts("```")
                IO.puts(improved_code)
                IO.puts("```")
              _ ->
                IO.puts("Result: #{inspect(result)}")
            end
          {:error, error} ->
            IO.puts("✗ Code refinement failed: #{error}")
            show_retry_mock()
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create code refiner: #{error}")
        show_retry_mock()
    end
  end
  
  defp show_retry_mock do
    IO.puts("\nMock Retry Process (for reference):")
    IO.puts("Attempt 1: Basic recursive solution (Quality: 6/10)")
    IO.puts("Attempt 2: Added memoization (Quality: 8/10)")
    IO.puts("Attempt 3: Optimized space complexity (Quality: 9/10)")
    IO.puts("\nFinal Code: [Would contain optimized LCS function]")
  end
  
  defp demo_mipro do
    IO.puts("\n\n4. MIPRO - Advanced Code Generation Optimization")
    IO.puts("------------------------------------------------")
    
    # Training dataset for code generation
    trainset = [
      %{
        problem: "Sort an array",
        constraints: "O(n log n) time complexity", 
        solution: "def quicksort(arr): ..."
      },
      %{
        problem: "Find duplicates in array",
        constraints: "O(n) time, O(1) space if possible",
        solution: "def find_duplicates(nums): ..."
      },
      %{
        problem: "Reverse a linked list", 
        constraints: "Iterative approach",
        solution: "def reverse_list(head): ..."
      }
    ]
    
    IO.puts("Training dataset: #{length(trainset)} examples")
    
    # First, discover what optimization modules are available in DSPy
    case DSPex.Bridge.discover_schema("dspy", session_id: "code_gen_session") do
      {:ok, schema} ->
        optimization_modules = schema
        |> Enum.filter(fn {name, info} ->
          info["type"] == "class" and 
          (String.contains?(String.downcase(name), "optim") or 
           String.contains?(String.downcase(name), "mipro") or
           String.contains?(String.downcase(name), "bootstrap"))
        end)
        |> Enum.map(fn {name, _info} -> name end)
        
        if length(optimization_modules) > 0 do
          IO.puts("\n✓ Found optimization modules: #{Enum.join(optimization_modules, ", ")}")
          
          # Try to use BootstrapFewShot as an example optimizer
          if "BootstrapFewShot" in optimization_modules do
            IO.puts("\n🔧 Attempting to use BootstrapFewShot optimizer...")
            
            case DSPex.Bridge.create_instance("dspy.BootstrapFewShot", %{
              "metric" => "accuracy",
              "max_bootstrapped_demos" => 3
            }, session_id: "code_gen_session") do
              {:ok, optimizer_ref} ->
                IO.puts("✓ Created BootstrapFewShot optimizer: #{inspect(optimizer_ref)}")
                IO.puts("(Full optimization would require a complete training pipeline)")
              {:error, error} ->
                IO.puts("✗ Failed to create optimizer: #{error}")
            end
          end
        else
          IO.puts("\n⚠️ No optimization modules found in current DSPy schema")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to discover DSPy schema: #{error}")
    end
    
    show_mipro_mock()
  end
  
  defp show_mipro_mock do
    IO.puts("\nMIPRO Process (conceptual):")
    IO.puts("1. Generated 5 candidate prompt variations")
    IO.puts("2. Evaluated each on training set")  
    IO.puts("3. Selected best performing prompts")
    IO.puts("4. Combined and refined instructions")
    IO.puts("\nOptimized Code Generator: [Would show improved performance]")
  end
  
  defp demo_settings do
    IO.puts("\n\n5. Settings and Configuration Management")
    IO.puts("----------------------------------------")
    
    # Get current DSPy settings through the bridge
    case Snakepit.execute_in_session("code_gen_session", "get_settings", %{}) do
      {:ok, settings} ->
        IO.puts("Current DSPy Settings:")
        IO.puts("- Language Model: #{settings["lm"] || "Not configured"}")
        IO.puts("- Retrieval Model: #{settings["rm"] || "Not configured"}")
        IO.puts("- Trace enabled: #{settings["trace"] || false}")
      {:error, error} ->
        IO.puts("Could not retrieve settings: #{inspect(error)}")
    end
    
    # Get stats
    case Snakepit.execute_in_session("code_gen_session", "get_stats", %{}) do
      {:ok, %{"success" => true, "stats" => stats}} ->
        IO.puts("\nDSPy Statistics:")
        IO.puts("- Programs created: #{stats["programs_count"]}")
        IO.puts("- Has configured LM: #{stats["has_configured_lm"]}")
        IO.puts("- DSPy version: #{stats["dspy_version"] || "unknown"}")
      {:error, error} ->
        IO.puts("Could not retrieve stats: #{inspect(error)}")
    end
    
    IO.puts("\nAdvanced settings management would include:")
    IO.puts("- Caching configuration")
    IO.puts("- Temperature and sampling settings")
    IO.puts("- Experimental feature toggles")
    IO.puts("- Performance optimization settings")
    IO.puts("\n(Settings module needs additional integration work)")
  end
  
end

# Run the system with proper cleanup
Snakepit.run_as_script(fn ->
  CodeGenerationSystem.run()
  IO.puts("\n\n=== Code Generation System Complete ===")
  IO.puts("To use with real code generation:")
  IO.puts("1. Set your Gemini API key: export GOOGLE_API_KEY=your-key")
  IO.puts("2. Run again for actual code generation results")
end)
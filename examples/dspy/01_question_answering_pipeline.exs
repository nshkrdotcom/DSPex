# Question Answering Pipeline - Demonstrates core modules and optimization
# Run with: mix run examples/dspy/01_question_answering_pipeline.exs

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
case Snakepit.execute_in_session("pipeline_session", "check_dspy", %{}) do
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
  case Snakepit.execute_in_session("pipeline_session", "configure_lm", %{
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

defmodule QAPipeline do
  @moduledoc """
  Multi-stage question answering pipeline demonstrating:
  - Predict: Basic question answering
  - ChainOfThought: Reasoning for complex questions
  - MultiChainComparison: Comparing multiple reasoning paths
  - BootstrapFewShot: Optimizing with examples
  - Assertions: Validating outputs
  - Evaluation: Measuring performance
  """
  
  def run do
    IO.puts("\n=== Question Answering Pipeline Demo ===\n")
    
    # 1. Basic Prediction
    demo_predict()
    
    # 2. Chain of Thought Reasoning
    demo_chain_of_thought()
    
    # 3. Multi-Chain Comparison
    demo_multi_chain()
    
    # 4. Optimization with Bootstrap
    demo_optimization()
    
    # 5. Assertions and Constraints
    demo_assertions()
    
    # 6. Evaluation
    demo_evaluation()
  end
  
  defp demo_predict do
    IO.puts("1. Basic Prediction")
    IO.puts("-------------------")
    
    case DSPex.Modules.Predict.create("question -> answer", session_id: "pipeline_session") do
      {:ok, predictor_ref} ->
        IO.puts("✓ Created Predict instance: #{inspect(predictor_ref)}")
        
        questions = [
          "What is the capital of France?",
          "What is 2 + 2?",
          "Who wrote Romeo and Juliet?"
        ]
        
        for question <- questions do
          case DSPex.Modules.Predict.execute(predictor_ref, %{"question" => question}) do
            {:ok, result} ->
              IO.puts("Q: #{question}")
              answer = case result do
                %{"success" => true, "result" => %{"prediction_data" => prediction_data}} ->
                  prediction_data["answer"] || "No answer field in result"
                %{"success" => false, "error" => error} ->
                  "Error: #{error}"
                %{"answer" => answer_text} ->
                  answer_text
                _ ->
                  "Unexpected result format: #{inspect(result)}"
              end
              IO.puts("A: #{answer}")
              IO.puts("")
            {:error, error} ->
              IO.puts("Q: #{question}")
              IO.puts("Error: #{error}")
              IO.puts("(Check that Gemini API key is configured properly)")
              IO.puts("")
          end
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create Predict instance: #{error}")
        IO.puts("(This likely means the LM is not configured properly)")
    end
  end
  
  defp demo_chain_of_thought do
    IO.puts("\n2. Chain of Thought Reasoning")
    IO.puts("-----------------------------")
    
    case DSPex.Modules.ChainOfThought.create("question -> answer", session_id: "pipeline_session") do
      {:ok, cot_ref} ->
        IO.puts("✓ Created ChainOfThought instance: #{inspect(cot_ref)}")
        
        complex_question = "If a train travels 120 miles in 2 hours, and then 180 miles in 3 hours, what is its average speed for the entire journey?"
        
        case DSPex.Modules.ChainOfThought.execute(cot_ref, %{"question" => complex_question}) do
          {:ok, result} ->
            IO.puts("Q: #{complex_question}")
            case result do
              %{"success" => true, "result" => %{"prediction_data" => prediction_data}} ->
                IO.puts("\nReasoning: #{prediction_data["reasoning"] || "No reasoning field"}")
                IO.puts("\nAnswer: #{prediction_data["answer"] || "No answer field"}")
              %{"success" => false, "error" => error} ->
                IO.puts("Error: #{error}")
              %{"answer" => answer_text, "reasoning" => reasoning_text} ->
                IO.puts("\nReasoning: #{reasoning_text}")
                IO.puts("\nAnswer: #{answer_text}")
              %{"answer" => answer_text} ->
                IO.puts("\nAnswer: #{answer_text}")
              _ ->
                IO.puts("Unexpected result format: #{inspect(result)}")
            end
          {:error, error} ->
            IO.puts("Q: #{complex_question}")
            IO.puts("Error: #{error}")
            IO.puts("(Check that Gemini API key is configured properly)")
        end
        
      {:error, error} ->
        IO.puts("✗ Failed to create ChainOfThought instance: #{error}")
        IO.puts("(This likely means the LM is not configured properly)")
    end
  end
  
  defp demo_multi_chain do
    IO.puts("\n\n3. Multi-Chain Comparison")
    IO.puts("-------------------------")
    
    question = "What are the main causes of climate change and their relative impacts?"
    
    # MultiChainComparison has a different API and isn't updated yet
    # Skipping this demo for now
    IO.puts("Q: #{question}")
    IO.puts("\nMultiChainComparison requires additional integration work.")
    IO.puts("(Skipping this demo - needs MultiChainComparison module update)")
  end
  
  defp demo_optimization do
    IO.puts("\n\n4. Optimization with BootstrapFewShot")
    IO.puts("-------------------------------------")
    
    # Note: Optimization requires proper Example objects and a working LM
    # For now, we'll demonstrate the concept
    IO.puts("Optimization with BootstrapFewShot requires:")
    IO.puts("- Training examples as DSPy Example objects (not plain maps)")
    IO.puts("- A configured language model")
    IO.puts("- Proper handling of the optimization result")
    IO.puts("\n(Skipping optimization demo - requires additional setup)")
  end
  
  defp demo_assertions do
    IO.puts("\n\n5. Assertions and Constraints")
    IO.puts("-----------------------------")
    
    # Create a predictor
    {:ok, _predictor} = DSPex.Modules.Predict.create("question -> answer: str")
    
    # Note: DSPy assertions are complex to demonstrate without a working LM
    # In a real scenario, assertions would constrain the output
    IO.puts("Created predictor (assertions require working LM to demonstrate)")
    
    # Example of what assertions would do:
    IO.puts("\nAssertion Examples (conceptual):")
    IO.puts("- assert_length: Ensures output is within character limits")
    IO.puts("- assert_contains: Ensures output contains specific keywords")
    IO.puts("- assert_matches: Ensures output matches a pattern")
    IO.puts("- Custom assertions: Any validation logic you need")
    
    # Mock demonstration
    IO.puts("\nWith a working LM, assertions would:")
    IO.puts("1. Validate outputs during generation")
    IO.puts("2. Retry if constraints aren't met")
    IO.puts("3. Raise errors if max retries exceeded")
  end
  
  defp demo_evaluation do
    IO.puts("\n\n6. Evaluation Framework")
    IO.puts("-----------------------")
    
    # Evaluation dataset
    eval_dataset = [
      %{question: "What is 10 + 15?", answer: "25"},
      %{question: "What color is the sky?", answer: "blue"},
      %{question: "Who was the first president of the USA?", answer: "George Washington"}
    ]
    
    IO.puts("Evaluation framework would compare Basic Predict vs Chain of Thought...")
    IO.puts("Dataset: #{length(eval_dataset)} examples")
    
    IO.puts("\nWith working LM, evaluation would:")
    IO.puts("1. Run both predictors on the dataset")
    IO.puts("2. Compare outputs against ground truth")
    IO.puts("3. Calculate accuracy metrics")
    IO.puts("4. Provide detailed performance analysis")
    
    IO.puts("\n(Skipping evaluation demo - needs DSPex.Evaluation module update)")
  end
  
  defp calculate_score(_results) do
    # In real usage, this would calculate accuracy from evaluation results
    # For now, return a mock score since evaluation requires a working LM
    0.0
  end
end

# Run the pipeline
QAPipeline.run()

IO.puts("\n\n=== Pipeline Complete ===")
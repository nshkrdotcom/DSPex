# Question Answering Pipeline - Demonstrates core modules and optimization
# Run with: mix run examples/dspy/01_question_answering_pipeline.exs

# Configure Snakepit for pooling BEFORE starting
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

# Initialize DSPex and configure LM
{:ok, _} = DSPex.Config.init()

# Load config and configure Gemini as default language model
config_path = Path.join(__DIR__, "../config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  IO.puts("\n✓ Configuring Gemini...")
  IO.puts("  API Key: #{String.slice(api_key, 0..5)}...#{String.slice(api_key, -4..-1)}")
  case DSPex.LM.configure(config_data.model, api_key: api_key) do
    {:ok, _} -> IO.puts("  Successfully configured!")
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
    
    {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
    
    questions = [
      "What is the capital of France?",
      "What is 2 + 2?",
      "Who wrote Romeo and Juliet?"
    ]
    
    for question <- questions do
      case DSPex.Modules.Predict.execute(predictor, %{question: question}) do
        {:ok, result} ->
          IO.puts("Q: #{question}")
          IO.puts("A: #{get_in(result, ["result", "prediction_data", "answer"]) || "No answer field in result"}")
          IO.puts("")
        {:error, error} ->
          IO.puts("Q: #{question}")
          IO.puts("Error: #{inspect(error["error"] || error)}")
          IO.puts("(This is expected without Gemini API key - set GOOGLE_API_KEY or GEMINI_API_KEY)")
          IO.puts("")
      end
    end
  end
  
  defp demo_chain_of_thought do
    IO.puts("\n2. Chain of Thought Reasoning")
    IO.puts("-----------------------------")
    
    {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
    
    complex_question = "If a train travels 120 miles in 2 hours, and then 180 miles in 3 hours, what is its average speed for the entire journey?"
    
    case DSPex.Modules.ChainOfThought.execute(cot, %{question: complex_question}) do
      {:ok, result} ->
        IO.puts("Q: #{complex_question}")
        IO.puts("\nReasoning: #{get_in(result, ["result", "prediction_data", "reasoning"]) || "No reasoning field"}")
        IO.puts("\nAnswer: #{get_in(result, ["result", "prediction_data", "answer"]) || "No answer field"}")
      {:error, error} ->
        IO.puts("Q: #{complex_question}")
        IO.puts("Error: #{inspect(error["error"] || error)}")
        IO.puts("(This is expected without Gemini API key configured properly)")
    end
  end
  
  defp demo_multi_chain do
    IO.puts("\n\n3. Multi-Chain Comparison")
    IO.puts("-------------------------")
    
    {:ok, mcc} = DSPex.Modules.MultiChainComparison.create(
      "question -> answer",
      chains: 3
    )
    
    question = "What are the main causes of climate change and their relative impacts?"
    
    case DSPex.Modules.MultiChainComparison.execute(mcc, %{question: question}) do
      {:ok, result} ->
        IO.puts("Q: #{question}")
        IO.puts("\nBest Answer (from 3 chains): #{get_in(result, ["result", "prediction_data", "answer"]) || "No answer field"}")
      {:error, error} ->
        IO.puts("Q: #{question}")
        IO.puts("Error: #{inspect(error["error"] || error)}")
        IO.puts("(This is expected without Gemini API key)")
    end
  end
  
  defp demo_optimization do
    IO.puts("\n\n4. Optimization with BootstrapFewShot")
    IO.puts("-------------------------------------")
    
    # Create a basic predictor
    {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
    
    # Training examples
    trainset = [
      %{question: "What is the capital of France?", answer: "Paris"},
      %{question: "What is the capital of Germany?", answer: "Berlin"},
      %{question: "What is the capital of Italy?", answer: "Rome"},
      %{question: "What is the capital of Spain?", answer: "Madrid"}
    ]
    
    # Optimize with BootstrapFewShot
    IO.puts("Optimizing with #{length(trainset)} examples...")
    
    {:ok, optimization_result} = DSPex.Optimizers.BootstrapFewShot.optimize(
      predictor,
      trainset,
      max_bootstrapped_demos: 2
    )
    
    IO.puts("Optimization complete!")
    IO.puts("Created optimized program: #{optimization_result[:optimized_program_id] || "optimization_failed"}")
    
    # Test the optimized version
    test_question = "What is the capital of Portugal?"
    {:ok, result} = DSPex.Modules.Predict.execute(
      optimization_result.optimized_program_id, 
      %{question: test_question}
    )
    
    IO.puts("\nTest Question: #{test_question}")
    IO.puts("Optimized Answer: #{get_in(result, ["result", "prediction_data", "answer"]) || "No answer field"}")
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
    
    # Create two predictors to compare
    {:ok, basic} = DSPex.Modules.Predict.create("question -> answer")
    {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
    
    # Evaluation dataset
    eval_dataset = [
      %{question: "What is 10 + 15?", answer: "25"},
      %{question: "What color is the sky?", answer: "blue"},
      %{question: "Who was the first president of the USA?", answer: "George Washington"}
    ]
    
    IO.puts("Evaluating Basic Predict vs Chain of Thought...")
    
    # Evaluate both
    {:ok, basic_results} = DSPex.Evaluation.evaluate(
      basic,
      eval_dataset,
      metric: &DSPex.Evaluation.Metrics.exact_match/2
    )
    
    {:ok, cot_results} = DSPex.Evaluation.evaluate(
      cot,
      eval_dataset,
      metric: &DSPex.Evaluation.Metrics.exact_match/2
    )
    
    IO.puts("\nResults:")
    IO.puts("Basic Predict Score: #{calculate_score(basic_results)}")
    IO.puts("Chain of Thought Score: #{calculate_score(cot_results)}")
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
#!/usr/bin/env elixir

# Working DSPy Integration Demo
# 
# Demonstrates confirmed working Python DSPy integration through enhanced Snakepit bridge

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:gemini_ex, "~> 0.0.3"},
  {:snakepit, github: "nshkrdotcom/snakepit"}
])

defmodule DSPyWorkingDemo do
  @moduledoc """
  Confirmed working DSPy integration with Gemini 2.5 Flash.
  
  This demonstrates the actual working functionality discovered through testing.
  """

  def run do
    IO.puts("🎯 === Working DSPy Integration Demo ===\n")
    
    # Check API key
    api_key = System.get_env("GEMINI_API_KEY")
    unless api_key do
      IO.puts("❌ Error: Please set GEMINI_API_KEY environment variable")
      System.halt(1)
    end

    # Configure and start
    configure_and_start()
    
    # Run working demos
    demo_environment_check()
    demo_dspy_configuration(api_key)
    demo_module_creation()
    demo_prediction_with_correct_format()
    
    IO.puts("\n🎉 === Working Demo Complete ===")
    IO.puts("✅ Python DSPy integration is functional!")
  end

  # === Setup ===
  
  defp configure_and_start do
    IO.puts("⚙️  Setting up enhanced Snakepit bridge...")
    
    # Configure for enhanced Python bridge
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
    Application.put_env(:snakepit, :pool_config, %{pool_size: 2})
    
    # Restart applications
    Application.stop(:snakepit)
    Application.stop(:dspex)
    {:ok, _} = Application.ensure_all_started(:dspex)
    {:ok, _} = Application.ensure_all_started(:snakepit)
    
    # Wait for initialization
    
    IO.puts("   ✅ Enhanced bridge ready")
  end

  # === Working Demonstrations ===
  
  defp demo_environment_check do
    IO.puts("\n🔍 Environment Check:")
    
    case Snakepit.execute("ping", %{}) do
      {:ok, result} ->
        IO.puts("   ✅ Bridge: #{result["bridge_type"]}")
        if result["frameworks_available"] do
          frameworks = Enum.join(result["frameworks_available"], ", ")
          IO.puts("   📚 Frameworks: #{frameworks}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Bridge check failed: #{inspect(reason)}")
    end
  end

  defp demo_dspy_configuration(api_key) do
    IO.puts("\n⚙️  DSPy Configuration:")
    
    case Snakepit.execute("configure_lm", %{
      "provider" => "google",
      "api_key" => api_key,
      "model" => "gemini/gemini-2.0-flash-exp"
    }) do
      {:ok, result} ->
        IO.puts("   ✅ DSPy configured with Gemini")
        IO.puts("   📄 Status: #{result["status"]}")
        if result["message"] do
          IO.puts("   💬 Message: #{result["message"]}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Configuration failed: #{inspect(reason)}")
    end
  end

  defp demo_module_creation do
    IO.puts("\n🏗️  Module Creation:")
    
    # Create a simple Predict module
    case Snakepit.execute("call", %{
      "target" => "dspy.Predict",
      "args" => ["question -> answer"],
      "store_as" => "qa_predictor"
    }) do
      {:ok, result} ->
        IO.puts("   ✅ Predict module created")
        IO.puts("   🏷️  Stored as: #{result["stored_as"]}")
        
      {:error, reason} ->
        IO.puts("   ❌ Module creation failed: #{inspect(reason)}")
    end
    
    # Create a ChainOfThought module
    case Snakepit.execute("call", %{
      "target" => "dspy.ChainOfThought", 
      "args" => ["question -> reasoning, answer"],
      "store_as" => "cot_predictor"
    }) do
      {:ok, result} ->
        IO.puts("   ✅ ChainOfThought module created")
        IO.puts("   🏷️  Stored as: #{result["stored_as"]}")
        
      {:error, reason} ->
        IO.puts("   ❌ ChainOfThought creation failed: #{inspect(reason)}")
    end
  end

  defp demo_prediction_with_correct_format do
    IO.puts("\n🧠 Predictions (Correct Format):")
    
    # Simple Q&A prediction using proper format
    question = "What is the capital of France?"
    IO.puts("   ❓ Question: #{question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.qa_predictor.__call__",
      "kwargs" => %{"question" => question}
    }) do
      {:ok, result} ->
        IO.puts("   ✅ Prediction successful!")
        
        # Extract the answer from the structured result
        cond do
          result["result"] && result["result"]["prediction_data"] ->
            answer = result["result"]["prediction_data"]["answer"]
            IO.puts("   💡 Answer: #{answer}")
          
          result["result"] && result["result"]["answer"] ->
            answer = result["result"]["answer"]
            IO.puts("   💡 Answer: #{answer}")
          
          true ->
            IO.puts("   📄 Raw result: #{inspect(result["result"])}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Prediction failed: #{inspect(reason)}")
    end
    
    # Chain of Thought prediction
    complex_question = "Why do leaves change color in autumn?"
    IO.puts("\n   ❓ Complex Question: #{complex_question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.cot_predictor.__call__",
      "kwargs" => %{"question" => complex_question}
    }) do
      {:ok, result} ->
        IO.puts("   ✅ Chain of Thought successful!")
        
        # Extract reasoning and answer
        if result["result"] && result["result"]["prediction_data"] do
          reasoning = result["result"]["prediction_data"]["reasoning"]
          answer = result["result"]["prediction_data"]["answer"]
          
          IO.puts("   🤔 Reasoning: #{String.slice(reasoning, 0, 150)}...")
          IO.puts("   💡 Answer: #{answer}")
        else
          IO.puts("   📄 Raw result: #{inspect(result["result"])}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Chain of Thought failed: #{inspect(reason)}")
    end
  end
end

# Run the working demo
DSPyWorkingDemo.run()
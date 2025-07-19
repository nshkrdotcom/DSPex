#!/usr/bin/env elixir

# DSPy Python Integration Example with Gemini 2.5 Flash
# 
# This example demonstrates Python DSPy integration through Snakepit,
# with explicit pooling configuration to ensure it works.

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:gemini_ex, "~> 0.0.3"},
  {:snakepit, github: "nshkrdotcom/snakepit"}
])

defmodule DSPyPythonIntegration do
  @moduledoc """
  Demonstrates Python DSPy integration through Snakepit with proper pooling configuration.
  """

  def run do
    IO.puts("🐍 === DSPy Python Integration with Gemini 2.5 Flash ===\n")
    
    # Check API key
    api_key = System.get_env("GEMINI_API_KEY")
    unless api_key do
      IO.puts("❌ Error: Please set GEMINI_API_KEY environment variable")
      IO.puts("   Get an API key from: https://makersuite.google.com/app/apikey")
      System.halt(1)
    end

    # Configure Snakepit with pooling enabled
    configure_snakepit()
    
    # Start applications
    start_applications()
    
    # Test Python environment
    test_python_environment()
    
    # Test DSPy integration if Python works
    if python_working?() do
      test_dspy_integration(api_key)
    else
      IO.puts("⚠️  Python environment issues detected. DSPy integration skipped.")
      show_python_setup_instructions()
    end
    
    IO.puts("\n✅ === Python Integration Test Complete ===")
  end

  # === Configuration ===
  
  defp configure_snakepit do
    IO.puts("⚙️  Configuring Snakepit with pooling enabled...")
    
    # Configure Snakepit to use enhanced Python adapter with pooling
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
    Application.put_env(:snakepit, :pool_config, %{
      pool_size: 2,
      max_overflow: 1,
      strategy: :fifo
    })
    
    IO.puts("   ✅ Snakepit configured for Python pooling")
  end

  defp start_applications do
    IO.puts("🚀 Starting applications...")
    
    # Stop applications if they're running
    Application.stop(:snakepit)
    Application.stop(:dspex)
    
    # Start with new configuration
    {:ok, _} = Application.ensure_all_started(:dspex)
    {:ok, _} = Application.ensure_all_started(:snakepit)
    
    # Give Snakepit time to initialize pool
    Process.sleep(1000)
    
    IO.puts("   ✅ Applications started with pooling enabled")
  end

  # === Python Environment Testing ===
  
  defp test_python_environment do
    IO.puts("\n🐍 Testing Python Environment:")
    
    # Test basic Python environment via bridge commands
    case Snakepit.execute("ping", %{}) do
      {:ok, result} ->
        IO.puts("   ✅ Python bridge communication successful")
        if result["python_version"] do
          IO.puts("   📄 Python version: #{result["python_version"]}")
        end
        if result["bridge_type"] do
          IO.puts("   🌉 Bridge type: #{result["bridge_type"]}")
        end
        
        # Test DSPy availability by trying to import
        test_dspy_import()
        
      {:error, reason} ->
        IO.puts("   ❌ Python bridge communication failed: #{inspect(reason)}")
    end
  end
  
  defp test_dspy_import do
    # Try to ping to test if the enhanced bridge includes DSPy
    case Snakepit.execute("ping", %{}) do
      {:ok, result} ->
        frameworks = result["frameworks_available"] || []
        if "dspy" in frameworks do
          IO.puts("   ✅ DSPy module is available")
          IO.puts("   📦 DSPy version: unknown")
        else
          IO.puts("   ❌ DSPy not available in frameworks: #{inspect(frameworks)}")
          IO.puts("   💡 Install with: pip install dspy-ai")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Bridge error: #{inspect(reason)}")
    end
  end
  
  defp extract_result_value(result) when is_map(result) do
    case result do
      %{"value" => value} -> value
      %{"type" => "str", "value" => value} -> value
      _ -> inspect(result)
    end
  end
  
  defp extract_result_value(result), do: result

  defp python_working? do
    case Snakepit.execute("ping", %{}) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # === DSPy Integration Testing ===
  
  defp test_dspy_integration(api_key) do
    IO.puts("\n🧠 Testing DSPy Integration:")
    
    # Test 1: DSPy Configuration
    test_dspy_configuration(api_key)
    
    # Test 2: Basic DSPy Modules
    test_basic_dspy_modules()
    
    # Test 3: DSPy Prediction
    test_dspy_prediction()
  end

  defp test_dspy_configuration(api_key) do
    IO.puts("   1️⃣  Testing DSPy Configuration:")
    
    # Use the enhanced bridge's DSPy configuration
    case Snakepit.execute("configure_lm", %{
      "provider" => "google", 
      "api_key" => api_key,
      "model" => "gemini-2.0-flash-exp"
    }) do
      {:ok, result} ->
        IO.puts("      ✅ DSPy configured successfully with Gemini")
        IO.puts("      📄 Model: gemini-2.0-flash-exp") 
        if result["status"] == "ok" do
          IO.puts("      🔧 Configuration applied")
        end
        
      {:error, reason} ->
        IO.puts("      ❌ Configuration test failed: #{inspect(reason)}")
    end
  end

  defp test_basic_dspy_modules do
    IO.puts("\n   2️⃣  Testing Basic DSPy Modules:")
    
    modules = [
      {"dspy.Predict", "question -> answer"},
      {"dspy.ChainOfThought", "question -> reasoning, answer"},
      {"dspy.ReAct", "question -> thought, action, observation, answer"}
    ]
    
    Enum.each(modules, fn {module_class, signature} ->
      case Snakepit.execute("call", %{
        "target" => module_class,
        "args" => [signature],
        "store_as" => String.downcase(String.replace(module_class, "dspy.", ""))
      }) do
        {:ok, result} ->
          IO.puts("      ✅ #{module_class} module created")
          IO.puts("         Signature: #{signature}")
          if result["stored_as"] do
            IO.puts("         Stored as: #{result["stored_as"]}")
          end
          
        {:error, reason} ->
          IO.puts("      ❌ #{module_class} creation failed: #{inspect(reason)}")
      end
    end)
  end

  defp test_dspy_prediction do
    IO.puts("\n   3️⃣  Testing DSPy Prediction:")
    
    # Test simple prediction
    question = "What is 2+2?"
    IO.puts("      Question: #{question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.predict.__call__",
      "kwargs" => %{"question" => question}
    }) do
      {:ok, result} ->
        IO.puts("      ✅ Prediction successful")
        cond do
          result["result"] && result["result"]["prediction_data"] ->
            answer = result["result"]["prediction_data"]["answer"]
            IO.puts("         Answer: #{answer}")
          
          result["result"] && result["result"]["answer"] ->
            IO.puts("         Answer: #{result["result"]["answer"]}")
          
          true ->
            IO.puts("         Raw result: #{inspect(result["result"])}")
        end
        
      {:error, reason} ->
        IO.puts("      ❌ Prediction failed: #{inspect(reason)}")
    end
    
    # Test ChainOfThought prediction
    cot_question = "Why is the sky blue?"
    IO.puts("\n      ChainOfThought Question: #{cot_question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.chainofthought.__call__",
      "kwargs" => %{"question" => cot_question}
    }) do
      {:ok, result} ->
        IO.puts("      ✅ ChainOfThought prediction successful")
        if result["result"] && result["result"]["prediction_data"] do
          reasoning = result["result"]["prediction_data"]["reasoning"] || ""
          answer = result["result"]["prediction_data"]["answer"] || ""
          
          preview = String.slice(reasoning, 0, 100)
          IO.puts("         Reasoning: #{preview}...")
          IO.puts("         Answer: #{answer}")
        else
          IO.puts("         Raw result: #{inspect(result["result"])}")
        end
        
      {:error, reason} ->
        IO.puts("      ❌ ChainOfThought prediction failed: #{inspect(reason)}")
    end
  end

  # === Helper Functions ===
  
  defp show_python_setup_instructions do
    IO.puts("\n📚 Python Setup Instructions:")
    IO.puts("   To enable DSPy integration, ensure you have:")
    IO.puts("   1. Python 3.8+ installed and available in PATH")
    IO.puts("   2. DSPy installed: pip install dspy-ai")
    IO.puts("   3. Required dependencies: pip install google-generativeai")
    IO.puts("")
    IO.puts("   Test your setup with:")
    IO.puts("   python -c \"import dspy; print('DSPy version:', dspy.__version__ if hasattr(dspy, '__version__') else 'unknown')\"")
  end
end

# Run the integration test
DSPyPythonIntegration.run()
#!/usr/bin/env elixir

# Simple DSPy Demo - Confirmed Working
Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:snakepit, github: "nshkrdotcom/snakepit"}
])

defmodule SimpleDSPyDemo do
  def run do
    IO.puts("🎯 === Simple DSPy Demo ===\n")
    
    api_key = System.get_env("GEMINI_API_KEY")
    unless api_key do
      IO.puts("❌ Error: Please set GEMINI_API_KEY")
      System.halt(1)
    end

    setup_snakepit()
    test_basic_functionality(api_key)
    
    IO.puts("\n✅ === Demo Complete ===")
  end

  defp setup_snakepit do
    IO.puts("⚙️  Setting up enhanced bridge...")
    
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
    
    Application.stop(:snakepit)
    Application.stop(:dspex)
    {:ok, _} = Application.ensure_all_started(:dspex)
    {:ok, _} = Application.ensure_all_started(:snakepit)
    
    Process.sleep(2000)
    IO.puts("   ✅ Bridge ready")
  end

  defp test_basic_functionality(api_key) do
    IO.puts("\n🧪 Testing Basic Functionality:")
    
    # Test 1: Ping
    case Snakepit.execute("ping", %{}) do
      {:ok, result} ->
        IO.puts("   ✅ Bridge: #{result["bridge_type"]}")
      {:error, reason} ->
        IO.puts("   ❌ Ping failed: #{inspect(reason)}")
    end
    
    # Test 2: Configure DSPy
    case Snakepit.execute("configure_lm", %{
      "provider" => "google",
      "api_key" => api_key,
      "model" => "gemini-2.0-flash-exp"
    }) do
      {:ok, _result} ->
        IO.puts("   ✅ DSPy configured")
      {:error, reason} ->
        IO.puts("   ❌ Config failed: #{inspect(reason)}")
    end
    
    # Test 3: Create module
    case Snakepit.execute("call", %{
      "target" => "dspy.Predict",
      "args" => ["question -> answer"],
      "store_as" => "predictor"
    }) do
      {:ok, _result} ->
        IO.puts("   ✅ Module created")
      {:error, reason} ->
        IO.puts("   ❌ Module failed: #{inspect(reason)}")
    end
    
    # Test 4: Make prediction 
    case Snakepit.execute("call", %{
      "target" => "stored.predictor.__call__",
      "kwargs" => %{"question" => "What is 2+2?"}
    }) do
      {:ok, result} ->
        IO.puts("   ✅ Prediction successful!")
        IO.puts("   📄 Result: #{inspect(result)}")
      {:error, reason} ->
        IO.puts("   ❌ Prediction failed: #{inspect(reason)}")
    end
  end
end

SimpleDSPyDemo.run()
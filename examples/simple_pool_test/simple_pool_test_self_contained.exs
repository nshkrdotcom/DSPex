#!/usr/bin/env elixir

# Test the CORRECT self-contained API that already exists
defmodule SimplePoolTestSelfContained do
  
  def main do
    IO.puts("🚀 Self-Contained Pool Test - Using Proper Stateless API")
    IO.puts("============================================================")
    
    IO.puts("\n📋 STEP 1: Starting DSPex application and pools...")
    start_everything()
    IO.puts("✅ Everything started")
    
    IO.puts("\n⏳ STEP 2: Waiting for pool warmup...")
    Process.sleep(5000)
    IO.puts("✅ Pool warmed up")
    
    # Step 3: Test concurrent operations using self-contained API
    IO.puts("\n🔥 STEP 3: Running 3 concurrent operations with self-contained API...")
    test_concurrent()
  end

  defp start_everything do
    # Stop any running application first
    Application.stop(:dspex)
    
    # Enable pooling BEFORE starting the application
    Application.put_env(:dspex, :pooling_enabled, true)
    Application.put_env(:dspex, :adapter, :python_pool)
    IO.puts("  🔧 Set pooling_enabled = #{Application.get_env(:dspex, :pooling_enabled)}")
    
    # Now start with pooling enabled
    Application.ensure_all_started(:dspex)
    
    api_key = System.get_env("GEMINI_API_KEY")
    DSPex.set_lm("gemini-1.5-flash", api_key: api_key)
  end

  defp test_concurrent do
    # Define a simple signature
    signature = %{
      name: "QA",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    # Use the CORRECT self-contained API that already exists!
    # This uses temporary programs that are created and cleaned up automatically
    tasks = [
      Task.async(fn -> 
        IO.puts("🔧 Task 1: Executing with self-contained signature")
        result = DSPex.Adapters.Factory.execute_with_signature_validation(
          :python_pool, 
          signature,
          %{question: "What is 2 + 2?"}
        )
        IO.puts("🔧 Task 1: Completed")
        result
      end),
      Task.async(fn -> 
        IO.puts("🔧 Task 2: Executing with self-contained signature")
        result = DSPex.Adapters.Factory.execute_with_signature_validation(
          :python_pool,
          signature, 
          %{question: "What color is the sky?"}
        )
        IO.puts("🔧 Task 2: Completed")
        result
      end),
      Task.async(fn -> 
        IO.puts("🔧 Task 3: Executing with self-contained signature")
        result = DSPex.Adapters.Factory.execute_with_signature_validation(
          :python_pool,
          signature,
          %{question: "What is the capital of France?"}
        )
        IO.puts("🔧 Task 3: Completed")
        result
      end)
    ]
    
    results = Task.await_many(tasks, 75_000)
    
    IO.puts("Results:")
    Enum.with_index(results, 1) |> Enum.each(fn {result, idx} ->
      case result do
        {:ok, output} ->
          IO.puts("  #{idx}. ✅ #{inspect(output)}")
        {:error, error} ->
          IO.puts("  #{idx}. ❌ #{inspect(error)}")
      end
    end)
  end
end

SimplePoolTestSelfContained.main()
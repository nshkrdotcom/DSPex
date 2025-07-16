#!/usr/bin/env elixir

# Test using the ACTUAL minimal pool API: execute_anonymous
defmodule SimplePoolTestExecuteAnonymous do
  
  def main do
    IO.puts("🚀 Execute Anonymous Pool Test - Using ACTUAL Minimal Pool API")
    IO.puts("============================================================")
    
    IO.puts("\n📋 STEP 1: Starting DSPex application and pools...")
    start_everything()
    IO.puts("✅ Everything started")
    
    IO.puts("\n⏳ STEP 2: Waiting for pool warmup...")
    Process.sleep(5000)
    IO.puts("✅ Pool warmed up")
    
    # Step 3: Test concurrent operations using execute_anonymous
    IO.puts("\n🔥 STEP 3: Running 3 concurrent operations with execute_anonymous...")
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
    # Use execute_anonymous directly - this is the ACTUAL minimal pool API!
    tasks = [
      Task.async(fn -> 
        IO.puts("🔧 Task 1: Using execute_anonymous")
        result = DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
          :predict,
          %{
            signature: %{
              name: "QA",
              inputs: [%{name: "question", type: "string"}],
              outputs: [%{name: "answer", type: "string"}]
            },
            inputs: %{question: "What is 2 + 2?"}
          }
        )
        IO.puts("🔧 Task 1: Completed")
        result
      end),
      Task.async(fn -> 
        IO.puts("🔧 Task 2: Using execute_anonymous")
        result = DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
          :predict,
          %{
            signature: %{
              name: "QA",
              inputs: [%{name: "question", type: "string"}],
              outputs: [%{name: "answer", type: "string"}]
            },
            inputs: %{question: "What color is the sky?"}
          }
        )
        IO.puts("🔧 Task 2: Completed")
        result
      end),
      Task.async(fn -> 
        IO.puts("🔧 Task 3: Using execute_anonymous")
        result = DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
          :predict,
          %{
            signature: %{
              name: "QA",
              inputs: [%{name: "question", type: "string"}],
              outputs: [%{name: "answer", type: "string"}]
            },
            inputs: %{question: "What is the capital of France?"}
          }
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

SimplePoolTestExecuteAnonymous.main()
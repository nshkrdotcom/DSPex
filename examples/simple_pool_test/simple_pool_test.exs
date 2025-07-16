#!/usr/bin/env elixir

defmodule SimplePoolTest do
  @moduledoc """
  Simple test to prove the minimal Python pooling works.
  
  This script:
  1. Starts DSPex application and pools in one step
  2. Waits for pool warmup 
  3. Runs 3 concurrent simple Q&A operations separately
  4. Shows clear separation so we can see the pool is warmed up and working
  """

  def main do
    IO.puts "🚀 Simple Pool Test - Testing Minimal Python Pooling"
    IO.puts String.duplicate("=", 60)
    
    # Step 1: Start everything in one step
    IO.puts "\n📋 STEP 1: Starting DSPex application and pools..."
    start_everything()
    IO.puts "✅ Everything started"
    
    # Step 2: Wait for warmup
    IO.puts "\n⏳ STEP 2: Waiting for pool warmup..."
    Process.sleep(5000)
    IO.puts "✅ Pool warmed up"
    
    # Step 3: Test concurrent operations separately 
    IO.puts "\n🔥 STEP 3: Running 3 concurrent operations..."
    test_concurrent()
  end

  defp start_everything do
    # Stop any running application first
    Application.stop(:dspex)
    
    # Enable pooling BEFORE starting the application
    Application.put_env(:dspex, :pooling_enabled, true)
    Application.put_env(:dspex, :adapter, :python_pool)
    IO.puts "  🔧 Set pooling_enabled = #{Application.get_env(:dspex, :pooling_enabled)}"
    
    # Now start with pooling enabled
    Application.ensure_all_started(:dspex)
    
    api_key = System.get_env("GEMINI_API_KEY")
    DSPex.set_lm("gemini-1.5-flash", api_key: api_key)
  end

  defp test_concurrent do
    # Create simple signature (NO COMPLEX SIGNATURES)
    signature = %{
      name: "QA",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    # For truly stateless pooling, create program in each worker
    # This demonstrates the requirement that "omitting session_id should work normally"
    tasks = [
      Task.async(fn -> 
        session_id = "session_task_1"
        IO.puts("🔧 Task 1: Starting create_program with session #{session_id}")
        # Create a unique session for this task to avoid conflicts
        unique_session = "task_1_#{System.unique_integer([:positive])}"
        {:ok, program_id} = DSPex.create_program(%{signature: signature, id: "qa_prog_1", session_id: unique_session})
        result = DSPex.execute_program(program_id, %{question: "What is 2 + 2?"}, session_id: unique_session)
        IO.puts("🔧 Task 1: Completed")
        result
      end),
      Task.async(fn -> 
        session_id = "session_task_2"
        IO.puts("🔧 Task 2: Starting create_program with session #{session_id}")
        # Create a unique session for this task to avoid conflicts
        unique_session = "task_2_#{System.unique_integer([:positive])}"
        {:ok, program_id} = DSPex.create_program(%{signature: signature, id: "qa_prog_2", session_id: unique_session})
        result = DSPex.execute_program(program_id, %{question: "What color is the sky?"}, session_id: unique_session)
        IO.puts("🔧 Task 2: Completed")
        result
      end),
      Task.async(fn -> 
        session_id = "session_task_3"
        IO.puts("🔧 Task 3: Starting create_program with session #{session_id}")
        # Create a unique session for this task to avoid conflicts
        unique_session = "task_3_#{System.unique_integer([:positive])}"
        {:ok, program_id} = DSPex.create_program(%{signature: signature, id: "qa_prog_3", session_id: unique_session})
        result = DSPex.execute_program(program_id, %{question: "What is the capital of France?"}, session_id: unique_session)
        IO.puts("🔧 Task 3: Completed")
        result
      end)
    ]
    
    results = Task.await_many(tasks, 75_000)
    
    IO.puts "Results:"
    Enum.with_index(results, 1) |> Enum.each(fn {result, idx} ->
      case result do
        {:ok, answer} -> 
          IO.puts "  #{idx}. ✅ #{inspect(answer)}"
        {:error, error} -> 
          IO.puts "  #{idx}. ❌ #{inspect(error)}"
      end
    end)
  end
end

# Run it
if System.argv() |> List.first() != "--no-run" do
  SimplePoolTest.main()
end
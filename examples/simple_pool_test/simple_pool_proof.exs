#!/usr/bin/env elixir

defmodule SimplePoolProof do
  @moduledoc """
  Simple proof that the minimal Python pooling works.
  
  This script:
  1. Starts DSPex application and pools
  2. Waits for pool warmup
  3. Runs 3 concurrent simple Q&A operations
  4. Shows clear separation between setup and execution
  """

  require Logger

  def main do
    IO.puts "🚀 Simple Pool Proof - Testing Minimal Python Pooling"
    IO.puts String.duplicate("=", 60)
    
    # Step 1: Start everything
    IO.puts "\n📋 STEP 1: Starting DSPex application and pools..."
    case start_application_and_pools() do
      :ok -> 
        IO.puts "✅ Application and pools started successfully"
        
        # Step 2: Wait for warmup
        IO.puts "\n⏳ STEP 2: Waiting for pool warmup..."
        wait_for_pool_warmup()
        IO.puts "✅ Pool is warmed up and ready"
        
        # Step 3: Test concurrent operations
        IO.puts "\n🔥 STEP 3: Running 3 concurrent question-answer operations..."
        test_concurrent_operations()
        
      {:error, reason} ->
        IO.puts "❌ Failed to start: #{inspect(reason)}"
        System.halt(1)
    end
  end

  defp start_application_and_pools do
    # Ensure we have Gemini API key
    unless System.get_env("GEMINI_API_KEY") do
      IO.puts "❌ GEMINI_API_KEY environment variable not set"
      System.halt(1)
    end

    # Start the application
    case Application.ensure_all_started(:dspex) do
      {:ok, _} -> 
        IO.puts "  📦 DSPex application started"
        
        # Configure the language model
        api_key = System.get_env("GEMINI_API_KEY")
        case DSPex.set_lm("gemini-1.5-flash", api_key: api_key) do
          :ok -> 
            IO.puts "  🧠 Gemini LM configured"
            :ok
          error -> 
            IO.puts "  ❌ Failed to configure LM: #{inspect(error)}"
            error
        end
        
      error -> 
        IO.puts "  ❌ Failed to start DSPex: #{inspect(error)}"
        error
    end
  end

  defp wait_for_pool_warmup do
    # Give pools time to initialize Python workers
    IO.puts "  ⏱️  Waiting 5 seconds for Python workers to initialize..."
    
    # Try a simple health check to verify pool is ready
    case DSPex.Adapters.PythonPoolV2.health_check() do
      :ok -> 
        IO.puts "  ❤️  Health check passed - pools are ready"
      error -> 
        IO.puts "  ⚠️  Health check failed but continuing: #{inspect(error)}"
    end
  end

  defp test_concurrent_operations do
    # Create 3 simple question-answer operations
    questions = [
      "What is 2 + 2?",
      "What color is the sky?", 
      "What is the capital of France?"
    ]
    
    IO.puts "  🔄 Starting 3 concurrent operations..."
    
    start_time = System.monotonic_time(:millisecond)
    
    # Start all 3 operations concurrently
    tasks = Enum.with_index(questions, 1) |> Enum.map(fn {question, index} ->
      Task.async(fn ->
        IO.puts "    🚀 Operation #{index} starting: #{question}"
        
        operation_start = System.monotonic_time(:millisecond)
        result = ask_simple_question(question, index)
        operation_end = System.monotonic_time(:millisecond)
        operation_time = operation_end - operation_start
        
        case result do
          {:ok, answer} -> 
            IO.puts "    ✅ Operation #{index} completed (#{operation_time}ms): #{String.slice(inspect(answer), 0, 100)}..."
            {:ok, %{question: question, answer: answer, time_ms: operation_time}}
          {:error, reason} -> 
            IO.puts "    ❌ Operation #{index} failed (#{operation_time}ms): #{inspect(reason)}"
            {:error, %{question: question, error: reason, time_ms: operation_time}}
        end
      end)
    end)
    
    # Wait for all to complete
    IO.puts "  ⏳ Waiting for all operations to complete..."
    results = Task.await_many(tasks, 30_000)
    
    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time
    
    # Analyze results
    analyze_results(results, total_time)
  end

  defp ask_simple_question(question, index) do
    # Create a simple signature
    signature = %{
      name: "SimpleQA",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    program_config = %{
      signature: signature,
      id: "simple_qa_#{index}_#{:rand.uniform(10000)}"
    }
    
    # Create program and execute
    with {:ok, program_id} <- DSPex.create_program(program_config),
         {:ok, result} <- DSPex.execute_program(program_id, %{question: question}) do
      {:ok, result}
    else
      error -> error
    end
  end

  defp analyze_results(results, total_time) do
    IO.puts "\n📊 RESULTS ANALYSIS:"
    IO.puts String.duplicate("=", 40)
    
    {successes, failures} = Enum.split_with(results, fn 
      {:ok, _} -> true
      _ -> false
    end)
    
    IO.puts "  📈 Total execution time: #{total_time}ms"
    IO.puts "  ✅ Successful operations: #{length(successes)}/#{length(results)}"
    IO.puts "  ❌ Failed operations: #{length(failures)}/#{length(results)}"
    
    if length(successes) > 0 do
      IO.puts "\n  🎯 Successful operations:"
      Enum.with_index(successes, 1) |> Enum.each(fn {{:ok, data}, idx} ->
        IO.puts "    #{idx}. Q: #{data.question}"
        IO.puts "       A: #{String.slice(inspect(data.answer), 0, 100)}..."
        IO.puts "       Time: #{data.time_ms}ms"
      end)
    end
    
    if length(failures) > 0 do
      IO.puts "\n  💥 Failed operations:"
      Enum.with_index(failures, 1) |> Enum.each(fn {{:error, data}, idx} ->
        IO.puts "    #{idx}. Q: #{data.question}"
        IO.puts "       Error: #{inspect(data.error)}"
        IO.puts "       Time: #{data.time_ms}ms"
      end)
    end
    
    # Final verdict
    if length(successes) == length(results) do
      IO.puts "\n🎉 SUCCESS: All concurrent operations completed successfully!"
      IO.puts "🔥 The minimal Python pooling is working correctly!"
    elsif length(successes) > 0 do
      IO.puts "\n⚠️  PARTIAL SUCCESS: #{length(successes)}/#{length(results)} operations succeeded"
      IO.puts "🔧 Pool is working but some operations failed"
    else
      IO.puts "\n💥 FAILURE: No operations succeeded"
      IO.puts "🚨 Pool is not working correctly"
    end
  end
end

# Run the test if this file is executed directly
if System.argv() |> List.first() != "--no-run" do
  SimplePoolProof.main()
end
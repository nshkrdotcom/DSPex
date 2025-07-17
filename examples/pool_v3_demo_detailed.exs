#!/usr/bin/env elixir

# DSPex V3 Pool Demo with Detailed Input/Output Logging
# Run with: elixir examples/pool_v3_demo_detailed.exs

# Configure pooling BEFORE loading DSPex to prevent standalone bridge from starting
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 8
})

Mix.install([
  {:dspex, path: "."},
  {:benchee, "~> 1.0"}
])

# Configure logging to reduce verbosity and clean test mode
Logger.configure(level: :info)

# Set clean test mode to avoid interference
System.put_env("TEST_MODE", "mock_adapter")

defmodule PoolV3DetailedDemo do
  require Logger

  def run do
    IO.puts("\n🚀 DSPex Pool V3 Demo - Detailed Input/Output Logging")
    IO.puts("=" |> String.duplicate(60))
    
    # Use DemoRunner for automatic cleanup
    DSPex.Python.DemoRunner.with_pool([size: 8], fn ->
      IO.puts("\n✅ V3 Pool started with global cleanup guarantees")
      
      # Demo operations with detailed logging
      demo_detailed_operations()
      
      # Demo concurrent execution with sample inputs/outputs
      demo_concurrent_with_details()
      
      # Show pool stats
      show_pool_stats()
      
      IO.puts("\n✨ Demo operations completed!")
    end)
    
    IO.puts("\n✅ Demo complete - all Python processes have been terminated!")
  end
  
  
  defp demo_detailed_operations do
    IO.puts("\n🔍 Detailed Operations Demo")
    IO.puts("-" |> String.duplicate(40))
    
    # 1. Simple ping with detailed logging
    IO.puts("\n📤 REQUEST 1: Simple Ping")
    ping_input = %{test: true, timestamp: System.os_time(:millisecond)}
    IO.puts("   Input: #{inspect(ping_input, pretty: true)}")
    
    case DSPex.Python.Pool.execute("ping", ping_input) do
      {:ok, result} -> 
        IO.puts("📥 RESPONSE 1:")
        IO.puts("   Output: #{inspect(result, pretty: true)}")
        IO.puts("   ✅ Status: #{result["status"]}")
      {:error, reason} ->
        IO.puts("📥 RESPONSE 1:")
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end
    
    # 2. Create program with detailed logging
    session_id = "demo_session_#{:erlang.unique_integer([:positive])}"
    
    IO.puts("\n📤 REQUEST 2: Create Program")
    program_input = %{
      id: "qa_program",
      signature: %{
        inputs: [%{name: "question", type: "str", description: "The question to answer"}],
        outputs: [%{name: "answer", type: "str", description: "The answer to the question"}]
      },
      instructions: "Answer questions about DSPy and Elixir concisely and accurately"
    }
    IO.puts("   Session ID: #{session_id}")
    IO.puts("   Input: #{inspect(program_input, pretty: true)}")
    
    case DSPex.Python.Pool.execute_in_session(session_id, "create_program", program_input) do
      {:ok, program_result} ->
        IO.puts("📥 RESPONSE 2:")
        IO.puts("   Output: #{inspect(program_result, pretty: true)}")
        IO.puts("   ✅ Program created successfully")
        
        # 3. Execute program with various inputs
        demo_program_executions(session_id)
        
      {:error, reason} ->
        IO.puts("📥 RESPONSE 2:")
        IO.puts("   ❌ Program creation failed: #{inspect(reason)}")
    end
  end
  
  defp demo_program_executions(session_id) do
    questions = [
      "What is DSPy?",
      "How does Elixir handle concurrency?",
      "What are the benefits of using a pool pattern?",
      "How does DSPex integrate DSPy with Elixir?"
    ]
    
    questions
    |> Enum.with_index(3)
    |> Enum.each(fn {question, request_num} ->
      IO.puts("\n📤 REQUEST #{request_num}: Execute Program")
      
      execution_input = %{
        program_id: "qa_program",
        inputs: %{question: question}
      }
      
      IO.puts("   Session ID: #{session_id}")
      IO.puts("   Input: #{inspect(execution_input, pretty: true)}")
      
      case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", execution_input) do
        {:ok, response} ->
          IO.puts("📥 RESPONSE #{request_num}:")
          IO.puts("   Output: #{inspect(response, pretty: true)}")
          
          # Extract and display the answer if available
          if is_map(response) and Map.has_key?(response, "answer") do
            IO.puts("   💬 Answer: \"#{response["answer"]}\"")
          end
          
          IO.puts("   ✅ Execution successful")
          
        {:error, reason} ->
          IO.puts("📥 RESPONSE #{request_num}:")
          IO.puts("   ❌ Execution failed: #{inspect(reason)}")
      end
      
      # Small delay to see the flow clearly
      Process.sleep(100)
    end)
  end
  
  defp demo_concurrent_with_details do
    IO.puts("\n⚡ Concurrent Execution with Sample Details")
    IO.puts("-" |> String.duplicate(50))
    IO.puts("   Sending 20 requests across 8 workers...")
    IO.puts("   (Showing first 5 request/response pairs)")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Fire 20 concurrent requests (smaller number to see details)
    tasks = for i <- 1..20 do
      Task.async(fn ->
        input = %{
          id: i,
          timestamp: System.os_time(:millisecond),
          worker_test: "concurrent_#{i}",
          data: "Sample data for request #{i}"
        }
        
        # Log first 5 requests
        if i <= 5 do
          IO.puts("\n📤 CONCURRENT REQUEST #{i}:")
          IO.puts("   Input: #{inspect(input, pretty: true)}")
        end
        
        result = DSPex.Python.Pool.execute("ping", input)
        
        # Log first 5 responses
        if i <= 5 do
          case result do
            {:ok, response} ->
              IO.puts("📥 CONCURRENT RESPONSE #{i}:")
              IO.puts("   Output: #{inspect(response, pretty: true)}")
            {:error, reason} ->
              IO.puts("📥 CONCURRENT RESPONSE #{i}:")
              IO.puts("   ❌ Error: #{inspect(reason)}")
          end
        end
        
        result
      end)
    end
    
    # Collect results
    results = Task.await_many(tasks, 30_000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    IO.puts("\n📊 Concurrent Execution Summary:")
    IO.puts("   ✅ Processed #{success_count}/20 requests in #{elapsed}ms")
    IO.puts("   📈 Throughput: #{Float.round(20_000 / elapsed, 1)} req/s")
    IO.puts("   💡 (Only showing details for first 5 requests)")
  end
  
  defp show_pool_stats do
    IO.puts("\n📊 Pool Statistics:")
    
    stats = DSPex.Python.Pool.get_stats()
    
    IO.puts("   Workers: #{stats.workers}")
    IO.puts("   Available: #{stats.available}")
    IO.puts("   Busy: #{stats.busy}")
    IO.puts("   Total Requests: #{stats.requests}")
    IO.puts("   Errors: #{stats.errors}")
    IO.puts("   Queue Timeouts: #{stats.queue_timeouts}")
  end
end

# Run the demo
PoolV3DetailedDemo.run()
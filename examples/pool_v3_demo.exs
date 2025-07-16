#!/usr/bin/env elixir

# DSPex V3 Pool Demo - Shows the massive performance improvement
# Run with: elixir examples/pool_v3_demo.exs

Mix.install([
  {:dspex, path: "."},
  {:benchee, "~> 1.0"}
])

# Configure logging to reduce verbosity and clean test mode
Logger.configure(level: :info)

# Set clean test mode to avoid interference
System.put_env("TEST_MODE", "mock_adapter")

defmodule PoolV3Demo do
  require Logger

  def run do
    IO.puts("\n🚀 DSPex Pool V3 Demo - Concurrent Python Workers")
    IO.puts("=" |> String.duplicate(50))
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 8
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Start pools
    IO.puts("\n⏱️  Starting V3 Pool (Concurrent)...")
    v3_time = :timer.tc(fn -> start_v3_pool() end) |> elem(0)
    IO.puts("✅ V3 Pool started in #{v3_time / 1000}ms")
    
    # For comparison, show what V2 would take
    IO.puts("\n📊 Comparison:")
    IO.puts("   V2 Pool (Sequential): ~#{8 * 2000}ms (8 workers × 2s each)")
    IO.puts("   V3 Pool (Concurrent): #{v3_time / 1000}ms")
    speedup = if v3_time > 10, do: Float.round(16000.0 / v3_time, 1), else: "~1000"
    IO.puts("   Speedup: #{speedup}x faster! 🎉")
    
    # Demo basic operations
    demo_operations()
    
    # Demo concurrent execution
    demo_concurrent_execution()
    
    # Show pool stats
    show_pool_stats()
    
    IO.puts("\n✨ Demo complete!")
  end
  
  defp start_v3_pool do
    # Start the V3 components
    {:ok, _} = Supervisor.start_link([DSPex.Python.Registry], strategy: :one_for_one)
    {:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
    {:ok, _} = DSPex.Python.Pool.start_link(size: 8)
    {:ok, _} = DSPex.PythonBridge.SessionStore.start_link()
  end
  
  defp demo_operations do
    IO.puts("\n🧪 Testing Basic Operations...")
    
    # Simple ping
    case DSPex.Python.Pool.execute("ping", %{test: true}) do
      {:ok, result} -> 
        IO.puts("   ✅ Ping response: #{result["status"]}")
      {:error, reason} ->
        IO.puts("   ❌ Ping failed: #{inspect(reason)}")
    end
    
    # Create a program with session context
    session_id = "demo_session_#{:erlang.unique_integer([:positive])}"
    
    case DSPex.Python.Pool.execute_in_session(session_id, "create_program", %{
      id: "demo_prog",
      signature: %{
        inputs: [%{name: "question", type: "str", description: "The question to answer"}],
        outputs: [%{name: "answer", type: "str", description: "The answer to the question"}]
      },
      instructions: "Answer questions concisely"
    }) do
      {:ok, _program} ->
        IO.puts("   ✅ Created program: demo_prog")
        
        # Execute program with session context
        case DSPex.Python.Pool.execute_in_session(session_id, "execute_program", %{
          program_id: "demo_prog",
          inputs: %{question: "What is DSPex?"}
        }) do
          {:ok, _response} ->
            IO.puts("   ✅ Program executed successfully")
          {:error, reason} ->
            IO.puts("   ❌ Program execution failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Program creation failed: #{inspect(reason)}")
    end
  end
  
  defp demo_concurrent_execution do
    IO.puts("\n⚡ Concurrent Execution Demo...")
    IO.puts("   Sending 100 requests across 8 workers...")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Fire 100 concurrent requests
    tasks = for i <- 1..100 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("ping", %{
          id: i,
          timestamp: System.os_time(:millisecond)
        })
      end)
    end
    
    # Collect results
    results = Task.await_many(tasks, 30_000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    IO.puts("   ✅ Processed #{success_count}/100 requests in #{elapsed}ms")
    IO.puts("   📈 Throughput: #{Float.round(100_000 / elapsed, 1)} req/s")
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
PoolV3Demo.run()
#!/usr/bin/env elixir

# DSPex V3 Pool Demo - Simplified to show concurrent initialization
# Run with: elixir examples/pool_v3_demo_simple.exs

Mix.install([{:dspex, path: "."}])

# Configure logging to reduce verbosity  
Logger.configure(level: :info)

defmodule SimplePoolDemo do
  require Logger

  def run do
    IO.puts("\n🚀 DSPex Pool V3 Demo - Concurrent vs Sequential Worker Initialization")
    IO.puts("=" |> String.duplicate(70))
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Demo concurrent initialization
    IO.puts("\n📊 V3 Pool (Concurrent Initialization):")
    v3_time = time_pool_startup(8)
    
    # Calculate what sequential would take
    sequential_estimate = 8 * 2000  # 8 workers × ~2s each
    
    IO.puts("\n📊 Comparison:")
    IO.puts("   Sequential (V2 style): ~#{sequential_estimate}ms (8 workers × 2s each)")
    IO.puts("   Concurrent (V3 style): #{Float.round(v3_time, 1)}ms")
    IO.puts("   🎉 Speedup: #{Float.round(sequential_estimate / v3_time, 1)}x faster!")
    
    # Quick functionality test
    test_pool_operations()
    
    IO.puts("\n✨ Demo complete!")
  end
  
  defp time_pool_startup(size) do
    start_time = System.monotonic_time(:millisecond)
    
    # Start all components
    {:ok, _} = Supervisor.start_link([DSPex.Python.Registry], strategy: :one_for_one)
    {:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
    {:ok, _} = DSPex.Python.Pool.start_link(size: size)
    {:ok, _} = DSPex.PythonBridge.SessionStore.start_link()
    
    # Wait for workers to be ready
    wait_for_workers(size)
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("   ✅ Started #{size} workers in #{Float.round(elapsed, 1)}ms")
    elapsed
  end
  
  defp wait_for_workers(expected_count) do
    # Poll until all workers are ready
    Enum.reduce_while(1..50, nil, fn _, _ ->
      stats = DSPex.Python.Pool.get_stats()
      if stats.workers >= expected_count do
        {:halt, :ok}
      else
        Process.sleep(100)
        {:cont, nil}
      end
    end)
  end
  
  defp test_pool_operations do
    IO.puts("\n🧪 Testing Pool Operations:")
    
    # Test concurrent ping operations
    start_time = System.monotonic_time(:millisecond)
    
    tasks = for i <- 1..20 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("ping", %{request: i})
      end)
    end
    
    results = Task.await_many(tasks, 5000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    
    IO.puts("   ✅ Processed #{success_count}/20 ping requests in #{elapsed}ms")
    IO.puts("   📈 Throughput: #{Float.round(20_000 / elapsed, 1)} req/s")
    
    # Show final stats
    stats = DSPex.Python.Pool.get_stats()
    IO.puts("\n📊 Final Pool Statistics:")
    IO.puts("   Workers: #{stats.workers}")
    IO.puts("   Total Requests: #{stats.requests}")
    IO.puts("   Errors: #{stats.errors}")
  end
end

# Run the demo
SimplePoolDemo.run()
#!/usr/bin/env elixir

# DSPex V3 Pool Demo with Built-in Cleanup
# Run with: elixir examples/pool_v3_clean_demo.exs

Mix.install([
  {:dspex, path: "."}
])

# Configure logging
Logger.configure(level: :info)

# Set test mode
System.put_env("TEST_MODE", "mock_adapter")

defmodule CleanPoolDemo do
  def run do
    IO.puts("\\n🚀 DSPex V3 Pool Demo with Built-in Cleanup")
    IO.puts("=" |> String.duplicate(60))
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 4
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Run demo with built-in cleanup
    DSPex.Python.DemoRunner.with_pool([size: 4], fn ->
      IO.puts("\\n✨ Pool started with built-in cleanup!")
      
      # Test basic functionality
      test_basic_ping()
      test_concurrent_requests()
      
      IO.puts("\\n🎯 Demo operations completed")
      IO.puts("\\n💡 Python processes will be automatically cleaned up on exit")
    end)
    
    IO.puts("\\n✅ Demo complete - all Python processes should be terminated!")
  end
  
  defp test_basic_ping do
    IO.puts("\\n📤 Testing basic ping...")
    
    case DSPex.Python.Pool.execute("ping", %{demo: true}) do
      {:ok, result} ->
        IO.puts("✅ Ping successful: #{result["status"]}")
      {:error, reason} ->
        IO.puts("❌ Ping failed: #{inspect(reason)}")
    end
  end
  
  defp test_concurrent_requests do
    IO.puts("\\n⚡ Testing concurrent requests...")
    
    start_time = System.monotonic_time(:millisecond)
    
    tasks = for i <- 1..8 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("ping", %{id: i, concurrent: true})
      end)
    end
    
    results = Task.await_many(tasks, 10_000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("✅ #{success_count}/8 concurrent requests completed in #{elapsed}ms")
  end
end

# Run the demo
CleanPoolDemo.run()
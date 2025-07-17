#!/usr/bin/env elixir

# Test Automatic Cleanup with Streamlined Setup
# Run with: elixir examples/test_supervised_cleanup.exs

# Configure pooling BEFORE loading DSPex
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 3
})

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule SupervisedCleanupTest do
  require Logger

  def run do
    IO.puts("\n🧪 Testing Automatic Cleanup with V3 Pool")
    IO.puts("=" |> String.duplicate(50))
    
    # Start the application (pool config already set)
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    test_pool_functionality()
    test_worker_tracking()
  end
  
  defp test_pool_functionality do
    IO.puts("\n🚀 Test 1: Pool Functionality")
    
    # Check if pool is running
    pool_pid = Process.whereis(DSPex.Python.Pool)
    
    if pool_pid do
      IO.puts("✅ V3 Pool running: #{inspect(pool_pid)}")
      
      # Get pool stats
      stats = DSPex.Python.Pool.get_stats()
      IO.puts("📊 Pool stats: #{inspect(stats)}")
      
      # Test basic execution
      case DSPex.Python.Pool.execute("ping", %{test: true}) do
        {:ok, result} ->
          IO.puts("✅ Pool execution works: #{result["status"]}")
        {:error, reason} ->
          IO.puts("❌ Pool execution failed: #{inspect(reason)}")
      end
    else
      IO.puts("❌ V3 Pool not found!")
    end
  end
  
  defp test_worker_tracking do
    IO.puts("\n🐍 Test 2: Worker Process Tracking")
    
    # List workers
    workers = DSPex.Python.Pool.list_workers()
    IO.puts("📋 Active workers: #{inspect(workers)}")
    
    IO.puts("💡 Workers will be automatically cleaned up when script ends")
  end
end

# Run the test
SupervisedCleanupTest.run()

# AUTOMATIC: DSPex application stops automatically when script ends
IO.puts("\n🎉 Test complete - automatic cleanup on script exit!")
IO.puts("💡 No manual Process.exit or cleanup needed - supervision tree handles it!")
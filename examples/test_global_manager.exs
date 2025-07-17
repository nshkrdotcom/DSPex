#!/usr/bin/env elixir

# GlobalPoolManager Integration Test with Streamlined Setup  
# Run with: elixir examples/test_global_manager.exs

# Configure pooling BEFORE loading DSPex
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 4
})

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule GlobalManagerTest do
  require Logger

  def run do
    IO.puts("\n🧪 Testing GlobalPoolManager Integration")
    IO.puts("=" |> String.duplicate(50))
    
    # Start the application (pool config already set)
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    test_global_pool_startup()
    test_global_status()
    test_manual_cleanup()
    
    IO.puts("\n✅ GlobalPoolManager integration test completed!")
  end
  
  defp test_global_pool_startup do
    IO.puts("\n🚀 Test 1: Global Pool Startup")
    
    case DSPex.Python.GlobalPoolManager.start_global_pool(size: 4) do
      {:ok, pool_pid, cleanup_report} ->
        IO.puts("✅ Pool started successfully: #{inspect(pool_pid)}")
        IO.puts("📊 Cleanup report: #{inspect(cleanup_report)}")
        
        # Quick test to ensure pool works
        case DSPex.Python.Pool.execute("ping", %{test: true}) do
          {:ok, result} ->
            IO.puts("✅ Pool execution works: #{result["status"]}")
          {:error, reason} ->
            IO.puts("❌ Pool execution failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to start pool: #{inspect(reason)}")
    end
  end
  
  defp test_global_status do
    IO.puts("\n📊 Test 2: Global Status")
    
    status = DSPex.Python.GlobalPoolManager.get_global_status()
    IO.puts("Global status: #{inspect(status, pretty: true)}")
  end
  
  defp test_manual_cleanup do
    IO.puts("\n🧹 Test 3: Manual Global Cleanup")
    
    cleanup_report = DSPex.Python.GlobalPoolManager.manual_global_cleanup()
    IO.puts("Manual cleanup report: #{inspect(cleanup_report)}")
  end
end

# Run the test
GlobalManagerTest.run()

# AUTOMATIC: DSPex application stops automatically when script ends
IO.puts("\n🎉 Test complete - automatic cleanup on script exit!")
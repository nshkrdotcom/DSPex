#!/usr/bin/env elixir

# Cross-application test - App 1
# This simulates the first Elixir application that creates some workers
# Run this first, then run cross_app_test_2.exs to see global cleanup in action

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule CrossAppTest1 do
  require Logger

  def run do
    IO.puts("\n🌍 Cross-Application Test - App 1")
    IO.puts("=" |> String.duplicate(50))
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 3
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    IO.puts("🚀 App 1: Starting global pool with 3 workers")
    
    case DSPex.Python.GlobalPoolManager.start_global_pool(size: 3, pool_id: "cross_app_test_1") do
      {:ok, pool_pid, cleanup_report} ->
        IO.puts("✅ App 1: Pool started successfully")
        IO.puts("📊 App 1: Cleanup report: #{inspect(cleanup_report)}")
        
        # Show global status
        status = DSPex.Python.GlobalPoolManager.get_global_status()
        IO.puts("🌍 App 1: Global status: #{status.total_pools} pools, #{status.total_python_processes} processes")
        
        # Keep the app running for a bit
        IO.puts("⏳ App 1: Keeping pool alive for 30 seconds...")
        IO.puts("   (Run cross_app_test_2.exs in another terminal now)")
        
        # Simulate some work
        for i <- 1..5 do
          case DSPex.Python.Pool.execute("ping", %{app: "app1", request: i}) do
            {:ok, result} ->
              IO.puts("✅ App 1: Request #{i} successful: #{result["status"]}")
            {:error, reason} ->
              IO.puts("❌ App 1: Request #{i} failed: #{inspect(reason)}")
          end
          Process.sleep(2000)
        end
        
        IO.puts("🛑 App 1: Exiting (workers should become orphaned)")
        
      {:error, reason} ->
        IO.puts("❌ App 1: Failed to start pool: #{inspect(reason)}")
    end
  end
end

# Run the test
CrossAppTest1.run()
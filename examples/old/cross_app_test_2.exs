#!/usr/bin/env elixir

# Cross-application test - App 2  
# This simulates a second Elixir application that should detect and clean up
# orphaned processes from App 1. Run this AFTER cross_app_test_1.exs

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule CrossAppTest2 do
  require Logger

  def run do
    IO.puts("\n🌍 Cross-Application Test - App 2")
    IO.puts("=" |> String.duplicate(50))
    
    # Wait a moment for user to see
    Process.sleep(2000)
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 2
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    IO.puts("🔍 App 2: Checking global status before cleanup...")
    
    # Show what orphaned processes exist
    status_before = DSPex.Python.GlobalPoolManager.get_global_status()
    IO.puts("📊 App 2: Before cleanup: #{status_before.total_pools} pools, #{status_before.total_python_processes} processes")
    IO.puts("     - Alive pools: #{status_before.alive_pools}")
    IO.puts("     - Dead pools: #{status_before.dead_pools}")  
    IO.puts("     - Orphaned processes: #{status_before.orphaned_processes}")
    
    if status_before.orphaned_processes > 0 do
      IO.puts("🎯 App 2: Found #{status_before.orphaned_processes} orphaned processes - they should be cleaned up!")
    else
      IO.puts("ℹ️  App 2: No orphaned processes found (App 1 may still be running)")
    end
    
    IO.puts("\n🚀 App 2: Starting global pool (this should trigger cleanup)")
    
    case DSPex.Python.GlobalPoolManager.start_global_pool(size: 2, pool_id: "cross_app_test_2") do
      {:ok, pool_pid, cleanup_report} ->
        IO.puts("✅ App 2: Pool started successfully")
        IO.puts("📊 App 2: Cleanup report: #{inspect(cleanup_report)}")
        
        # Show global status after cleanup
        status_after = DSPex.Python.GlobalPoolManager.get_global_status()
        IO.puts("\n🌍 App 2: Global status after cleanup:")
        IO.puts("     - Total pools: #{status_after.total_pools}")
        IO.puts("     - Total processes: #{status_after.total_python_processes}")
        IO.puts("     - Alive pools: #{status_after.alive_pools}")
        IO.puts("     - Dead pools: #{status_after.dead_pools}")
        IO.puts("     - Orphaned processes: #{status_after.orphaned_processes}")
        
        # Verify cleanup worked
        if cleanup_report.cleanup_processes_killed > 0 or cleanup_report.killed_processes > 0 do
          total_killed = cleanup_report.cleanup_processes_killed + cleanup_report.killed_processes
          IO.puts("\n🎉 SUCCESS: Cross-application cleanup worked! Killed #{total_killed} orphaned processes")
        else
          IO.puts("\nℹ️  No orphaned processes were killed (this is normal if App 1 exited cleanly)")
        end
        
        # Test that our pool works
        case DSPex.Python.Pool.execute("ping", %{app: "app2", test: "cross_app"}) do
          {:ok, result} ->
            IO.puts("✅ App 2: Pool execution successful: #{result["status"]}")
          {:error, reason} ->
            IO.puts("❌ App 2: Pool execution failed: #{inspect(reason)}")
        end
        
        IO.puts("\n✨ App 2: Cross-application test completed!")
        
      {:error, reason} ->
        IO.puts("❌ App 2: Failed to start pool: #{inspect(reason)}")
    end
  end
end

# Run the test
CrossAppTest2.run()
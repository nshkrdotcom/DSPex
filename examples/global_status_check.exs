#!/usr/bin/env elixir

# Global Status Check
# Simple utility to check the global registry status and manually trigger cleanup

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule GlobalStatusCheck do
  require Logger

  def run do
    IO.puts("\n🔍 Global Registry Status Check")
    IO.puts("=" |> String.duplicate(40))
    
    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Check raw global status
    status = DSPex.Python.GlobalRegistry.get_global_status()
    
    IO.puts("\n📊 Global Registry Status:")
    IO.puts("   Registry Directory: #{status.registry_dir}")
    IO.puts("   Total Pools: #{status.total_pools}")
    IO.puts("   Alive Pools: #{status.alive_pools}")
    IO.puts("   Dead Pools: #{status.dead_pools}")
    IO.puts("   Total Python Processes: #{status.total_python_processes}")
    IO.puts("   Registered Processes: #{status.registered_processes}")
    IO.puts("   Orphaned Processes: #{status.orphaned_processes}")
    
    if length(status.orphaned_pids) > 0 do
      IO.puts("\n🚨 Orphaned Process PIDs: #{inspect(status.orphaned_pids)}")
    end
    
    if length(status.pools) > 0 do
      IO.puts("\n📋 Pool Details:")
      Enum.each(status.pools, fn pool ->
        IO.puts("   - Pool #{pool.pool_id}: #{pool.status} (#{length(pool.processes || [])} processes)")
      end)
    end
    
    # Check system processes
    IO.puts("\n🔍 System Process Check:")
    case System.cmd("pgrep", ["-f", "dspy_bridge.py"], stderr_to_stdout: true) do
      {output, 0} ->
        pids = output |> String.split("\n", trim: true)
        IO.puts("   Found #{length(pids)} dspy_bridge processes: #{inspect(pids)}")
      {_output, _} ->
        IO.puts("   No dspy_bridge processes found")
    end
    
    # Offer manual cleanup
    if status.orphaned_processes > 0 do
      IO.puts("\n🧹 Manual Cleanup Available:")
      IO.puts("   Run this to clean up orphaned processes:")
      IO.puts("   DSPex.Python.GlobalRegistry.cleanup_orphaned_globally()")
      
      # Actually do the cleanup
      IO.puts("\n🚀 Performing cleanup now...")
      {cleaned_pools, killed_processes} = DSPex.Python.GlobalRegistry.cleanup_orphaned_globally()
      IO.puts("✅ Cleanup completed: cleaned #{cleaned_pools} pools, killed #{killed_processes} processes")
    else
      IO.puts("\n✅ No orphaned processes found - system is clean!")
    end
    
    IO.puts("\n✨ Status check completed!")
  end
end

# Run the check
GlobalStatusCheck.run()
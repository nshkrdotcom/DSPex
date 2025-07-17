#!/usr/bin/env elixir

# Test our supervised worker manager with hard cleanup guarantees
# Run with: elixir examples/test_supervised_cleanup.exs

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

defmodule SupervisedCleanupTest do
  require Logger

  def run do
    IO.puts("\n🧪 Testing Supervised Worker Manager with Hard Cleanup Guarantees")
    IO.puts("=" |> String.duplicate(70))
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 4
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Start only essential dependencies
    {:ok, _} = Application.ensure_all_started(:logger)
    {:ok, _} = Application.ensure_all_started(:jason)
    
    test_supervised_workers()
  end
  
  defp test_supervised_workers do
    IO.puts("\n🚀 Test 1: Starting Supervised Worker Manager")
    
    # Start the supervised worker manager
    case DSPex.Python.SupervisedWorkerManager.start_link(size: 3) do
      {:ok, sup_pid} ->
        IO.puts("✅ Supervisor started: #{inspect(sup_pid)}")
        
        # Give workers time to initialize
        Process.sleep(2000)
        
        # Check if workers are alive
        workers = Supervisor.which_children(DSPex.Python.SupervisedWorkerManager)
        IO.puts("📊 Workers: #{length(workers)} started")
        
        # Get Python PIDs
        python_pids = DSPex.Python.SupervisedWorkerManager.get_all_python_pids()
        IO.puts("🐍 Python processes: #{inspect(python_pids)}")
        
        if length(python_pids) > 0 do
          test_hard_cleanup(sup_pid, python_pids)
        else
          IO.puts("⚠️ No Python processes found - workers may have failed to start")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to start supervisor: #{inspect(reason)}")
    end
  end
  
  defp test_hard_cleanup(sup_pid, python_pids) do
    IO.puts("\n🔥 Test 2: Hard Cleanup Guarantee")
    
    IO.puts("Before cleanup - checking if Python processes exist:")
    check_processes_alive(python_pids)
    
    # Test graceful shutdown
    IO.puts("\n🛑 Initiating graceful shutdown...")
    DSPex.Python.SupervisedWorkerManager.graceful_shutdown(2000)
    
    Process.sleep(1000)
    
    IO.puts("\nAfter cleanup - checking if Python processes still exist:")
    check_processes_alive(python_pids)
    
    # Verify supervisor is still alive or properly terminated
    if Process.alive?(sup_pid) do
      IO.puts("📊 Supervisor still alive - stopping it")
      Process.exit(sup_pid, :shutdown)
    else
      IO.puts("📊 Supervisor properly terminated")
    end
    
    Process.sleep(500)
    IO.puts("\nFinal check - ensuring all processes are gone:")
    check_processes_alive(python_pids)
  end
  
  defp check_processes_alive(python_pids) do
    alive_count = Enum.count(python_pids, fn pid ->
      case System.cmd("kill", ["-0", "#{pid}"], stderr_to_stdout: true) do
        {_output, 0} -> true
        {_output, _} -> false
      end
    end)
    
    if alive_count == 0 do
      IO.puts("✅ All #{length(python_pids)} Python processes are dead")
    else
      IO.puts("⚠️ #{alive_count}/#{length(python_pids)} Python processes still alive")
      
      # Show which ones are still alive
      Enum.each(python_pids, fn pid ->
        case System.cmd("kill", ["-0", "#{pid}"], stderr_to_stdout: true) do
          {_output, 0} -> IO.puts("   - PID #{pid}: ALIVE")
          {_output, _} -> IO.puts("   - PID #{pid}: DEAD")
        end
      end)
    end
  end
end

# Run the test
SupervisedCleanupTest.run()
defmodule DSPex.Python.OrphanDetector do
  @moduledoc """
  Detects and manages orphaned Python dspy_bridge processes.
  
  This module provides robust mechanisms to:
  - Identify orphaned Python processes that are no longer managed by active workers
  - Validate process ancestry and fingerprints
  - Safely terminate orphaned processes while preserving active workers
  - Provide detailed reporting on orphaned process cleanup
  """
  
  require Logger
  
  @doc """
  Finds all orphaned dspy_bridge.py processes.
  
  Returns a list of PIDs that are:
  1. Running dspy_bridge.py
  2. Not registered with any active worker
  3. Validated as actual orphans through multiple checks
  """
  def find_orphaned_processes() do
    active_pids = DSPex.Python.ProcessRegistry.get_active_python_pids()
    all_dspy_pids = get_all_dspy_bridge_pids()
    
    Logger.debug("Active worker PIDs: #{inspect(active_pids)}")
    Logger.debug("All dspy_bridge PIDs: #{inspect(all_dspy_pids)}")
    
    # Find PIDs that are in all_dspy_pids but not in active_pids
    orphaned_candidates = all_dspy_pids -- active_pids
    
    # Additional validation to ensure they're actually orphans
    validated_orphans = 
      orphaned_candidates
      |> Enum.filter(&validate_orphan/1)
      |> Enum.map(&enhance_orphan_info/1)
    
    Logger.info("Found #{length(validated_orphans)} orphaned Python processes")
    validated_orphans
  end
  
  @doc """
  Safely terminates orphaned processes with graceful shutdown.
  
  Returns a report of the cleanup operation.
  """
  def cleanup_orphaned_processes(orphans \\ nil) do
    orphans = orphans || find_orphaned_processes()
    
    if Enum.empty?(orphans) do
      Logger.info("No orphaned processes found to clean up")
      %{
        found: 0,
        terminated: 0,
        errors: 0,
        preserved_active: length(DSPex.Python.ProcessRegistry.get_active_python_pids())
      }
    else
      Logger.info("Attempting to clean up #{length(orphans)} orphaned processes")
      
      results = 
        orphans
        |> Enum.map(fn %{pid: pid} = orphan -> 
          terminate_orphan_process(pid, orphan) 
        end)
      
      terminated = Enum.count(results, fn {status, _} -> status == :ok end)
      errors = Enum.count(results, fn {status, _} -> status == :error end)
      
      Logger.info("Cleanup complete: #{terminated} terminated, #{errors} errors")
      
      %{
        found: length(orphans),
        terminated: terminated,
        errors: errors,
        preserved_active: length(DSPex.Python.ProcessRegistry.get_active_python_pids()),
        details: Enum.zip(orphans, results)
      }
    end
  end
  
  @doc """
  Gets comprehensive system status including orphan detection.
  """
  def get_system_status() do
    registry_stats = DSPex.Python.ProcessRegistry.get_stats()
    orphans = find_orphaned_processes()
    all_dspy_pids = get_all_dspy_bridge_pids()
    
    %{
      registry: registry_stats,
      orphaned_processes: length(orphans),
      total_dspy_processes: length(all_dspy_pids),
      orphan_details: orphans,
      system_health: calculate_system_health(registry_stats, orphans)
    }
  end
  
  @doc """
  Validates that the orphan detection system is working correctly.
  """
  def validate_detection_system() do
    try do
      # Test process enumeration
      all_pids = get_all_dspy_bridge_pids()
      active_pids = DSPex.Python.ProcessRegistry.get_active_python_pids()
      
      # Test validation functions
      validation_results = 
        all_pids
        |> Enum.take(3)  # Test first 3 processes
        |> Enum.map(fn pid ->
          {pid, validate_orphan(pid)}
        end)
      
      %{
        status: :ok,
        all_dspy_processes: length(all_pids),
        active_workers: length(active_pids),
        validation_test: validation_results,
        system_commands: test_system_commands()
      }
    rescue
      e -> 
        Logger.error("OrphanDetector validation failed: #{inspect(e)}")
        %{status: :error, error: inspect(e)}
    end
  end
  
  # Private Functions
  
  defp get_all_dspy_bridge_pids() do
    case System.cmd("pgrep", ["-f", "dspy_bridge.py"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.to_integer/1)
        |> Enum.filter(&process_exists?/1)
        
      {_output, _exit_code} ->
        # No processes found or pgrep error
        []
    end
  end
  
  defp validate_orphan(pid) do
    with true <- process_exists?(pid),
         true <- is_dspy_bridge_process?(pid),
         true <- not_zombie_process?(pid) do
      true
    else
      _ -> false
    end
  end
  
  defp process_exists?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
  
  defp is_dspy_bridge_process?(pid) do
    case File.read("/proc/#{pid}/cmdline") do
      {:ok, cmdline} ->
        # cmdline uses null bytes as separators
        cmdline
        |> String.replace(<<0>>, " ")
        |> String.contains?("dspy_bridge.py")
        
      {:error, _} -> 
        false
    end
  end
  
  defp not_zombie_process?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat_content} ->
        # Third field in /proc/pid/stat is the process state
        stat_parts = String.split(stat_content, " ")
        case Enum.at(stat_parts, 2) do
          "Z" -> false  # Zombie process
          _ -> true     # Living process
        end
        
      {:error, _} -> 
        false
    end
  end
  
  defp enhance_orphan_info(pid) do
    cmdline = case File.read("/proc/#{pid}/cmdline") do
      {:ok, content} -> String.replace(content, <<0>>, " ")
      {:error, _} -> "unknown"
    end
    
    start_time = case File.read("/proc/#{pid}/stat") do
      {:ok, stat_content} ->
        # 22nd field is start time in clock ticks since boot
        stat_parts = String.split(stat_content, " ")
        Enum.at(stat_parts, 21, "unknown")
      {:error, _} -> "unknown"
    end
    
    %{
      pid: pid,
      cmdline: cmdline,
      start_time: start_time,
      detected_at: System.system_time(:second)
    }
  end
  
  defp terminate_orphan_process(pid, orphan_info) do
    Logger.info("Terminating orphaned process #{pid}: #{orphan_info.cmdline}")
    
    try do
      # Try graceful termination first (SIGTERM)
      case System.cmd("kill", ["-TERM", "#{pid}"], stderr_to_stdout: true) do
        {_output, 0} ->
          # Wait a moment for graceful shutdown
          Process.sleep(1000)
          
          # Check if process is still alive
          if process_exists?(pid) do
            # Force kill if still alive (SIGKILL)
            case System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) do
              {_output, 0} -> 
                Logger.info("Force-killed orphaned process #{pid}")
                {:ok, :force_killed}
              {error, _} -> 
                Logger.error("Failed to force-kill process #{pid}: #{error}")
                {:error, :force_kill_failed}
            end
          else
            Logger.info("Gracefully terminated orphaned process #{pid}")
            {:ok, :graceful}
          end
          
        {error, _} ->
          Logger.error("Failed to terminate process #{pid}: #{error}")
          {:error, :term_failed}
      end
    rescue
      e ->
        Logger.error("Exception terminating process #{pid}: #{inspect(e)}")
        {:error, :exception}
    end
  end
  
  defp calculate_system_health(registry_stats, orphans) do
    total_processes = registry_stats.total_registered + length(orphans)
    
    cond do
      length(orphans) == 0 -> :healthy
      length(orphans) / max(total_processes, 1) < 0.1 -> :good
      length(orphans) / max(total_processes, 1) < 0.3 -> :degraded
      true -> :critical
    end
  end
  
  defp test_system_commands() do
    %{
      pgrep_available: system_command_available?("pgrep"),
      kill_available: system_command_available?("kill"),
      proc_filesystem: File.dir?("/proc")
    }
  end
  
  defp system_command_available?(command) do
    case System.find_executable(command) do
      nil -> false
      _ -> true
    end
  end
end
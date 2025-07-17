defmodule DSPex.Python.GlobalRegistry do
  @moduledoc """
  Machine-wide registry for DSPex Python processes using directory-based atomic operations.
  
  This registry solves the fundamental problem of orphaned Python processes accumulating
  across different Elixir nodes, applications, and restarts on the same machine.
  
  ## Architecture
  
  - **Registry Directory**: `/tmp/dspex_global_processes/`
  - **Atomic Operations**: Uses temp file + rename for race-condition-free updates
  - **Self-Healing**: Dead pools automatically cleaned up on next startup
  - **Cross-Application**: Works across different Elixir apps on same machine
  
  ## Usage
  
      # On every pool startup - automatic global cleanup
      DSPex.Python.GlobalRegistry.startup_cleanup_and_register(pool_id, processes)
      
      # Manual global status check
      DSPex.Python.GlobalRegistry.get_global_status()
  """
  
  require Logger
  
  @registry_dir "/tmp/dspex_global_processes"
  
  @derive Jason.Encoder
  defstruct [
    :pool_id,
    :elixir_node,
    :elixir_pid,
    :os_pid,
    :processes,
    :started_at,
    :last_heartbeat
  ]
  
  @doc """
  Performs global cleanup and registers a new pool atomically.
  
  This is the main entry point that should be called by every pool startup.
  It ensures no orphaned processes exist before starting new ones.
  """
  def startup_cleanup_and_register(pool_id, python_processes) do
    Logger.info("🌍 Starting global registry cleanup and registration for pool #{pool_id}")
    
    ensure_registry_dir()
    
    # 1. Global cleanup first
    {cleaned_pools, killed_processes} = cleanup_orphaned_globally()
    
    # 2. Register current pool
    register_pool_atomically(pool_id, python_processes)
    
    Logger.info("✅ Global registry: cleaned #{cleaned_pools} dead pools, killed #{killed_processes} orphaned processes")
    
    %{
      cleaned_pools: cleaned_pools,
      killed_processes: killed_processes,
      registered_pool: pool_id,
      registered_processes: length(python_processes)
    }
  end
  
  @doc """
  Registers a pool with its Python processes atomically.
  
  Uses temp file + atomic rename to avoid race conditions.
  """
  def register_pool_atomically(pool_id, python_processes) do
    ensure_registry_dir()
    
    # Convert PIDs in process list to strings for JSON serialization
    serializable_processes = Enum.map(python_processes, fn process ->
      Map.update!(process, :elixir_pid, &inspect/1)
    end)
    
    pool_data = %__MODULE__{
      pool_id: pool_id,
      elixir_node: Atom.to_string(node()),  # Convert atom to string for JSON serialization
      elixir_pid: inspect(self()),  # Convert PID to string for JSON serialization
      os_pid: List.to_integer(:os.getpid()),  # Convert charlist to integer
      processes: serializable_processes,
      started_at: System.system_time(:second),
      last_heartbeat: System.system_time(:second)
    }
    
    pool_file = pool_filename(pool_id)
    temp_file = "#{pool_file}.tmp.#{:rand.uniform(999999)}"
    
    try do
      # Convert struct to plain map for JSON encoding
      json_data = Map.from_struct(pool_data)
      
      # Write to temp file
      content = Jason.encode!(json_data)
      File.write!(temp_file, content)
      
      # Atomic rename
      File.rename!(temp_file, pool_file)
      
      Logger.debug("Registered pool #{pool_id} with #{length(python_processes)} processes")
      :ok
    rescue
      e ->
        # Cleanup temp file on error
        File.rm(temp_file)
        {:error, "Failed to register pool: #{inspect(e)}"}
    end
  end
  
  @doc """
  Unregisters a pool from the global registry.
  """
  def unregister_pool(pool_id) do
    pool_file = pool_filename(pool_id)
    
    case File.rm(pool_file) do
      :ok -> 
        Logger.debug("Unregistered pool #{pool_id}")
        :ok
      {:error, :enoent} -> 
        :ok  # Already removed
      error -> 
        error
    end
  end
  
  @doc """
  Performs global cleanup of orphaned processes and dead pool files.
  
  Returns {pools_cleaned, processes_killed}
  """
  def cleanup_orphaned_globally do
    ensure_registry_dir()
    
    _pools_cleaned = 0
    _processes_killed = 0
    
    # Get all pool files
    pool_files = list_pool_files()
    
    {pools_cleaned, processes_killed} = 
      Enum.reduce(pool_files, {0, 0}, fn filename, {pools_acc, procs_acc} ->
        case validate_and_cleanup_pool_file(filename) do
          {:cleaned, killed_count} -> {pools_acc + 1, procs_acc + killed_count}
          :alive -> {pools_acc, procs_acc}
        end
      end)
    
    # Also cleanup any unregistered Python processes
    additional_killed = cleanup_unregistered_python_processes()
    
    {pools_cleaned, processes_killed + additional_killed}
  end
  
  @doc """
  Gets comprehensive global status of all registered pools and processes.
  """
  def get_global_status do
    ensure_registry_dir()
    
    pool_files = list_pool_files()
    
    pools = 
      Enum.map(pool_files, fn filename ->
        case read_pool_file(filename) do
          {:ok, pool_data} -> 
            Map.put(pool_data, :status, if(pool_alive?(pool_data), do: :alive, else: :dead))
          {:error, reason} -> 
            %{filename: filename, status: :corrupted, error: reason}
        end
      end)
    
    all_python_pids = get_all_dspy_bridge_pids()
    registered_pids = get_all_registered_python_pids(pools)
    orphaned_pids = all_python_pids -- registered_pids
    
    %{
      registry_dir: @registry_dir,
      total_pools: length(pools),
      alive_pools: Enum.count(pools, &(Map.get(&1, :status) == :alive)),
      dead_pools: Enum.count(pools, &(Map.get(&1, :status) == :dead)),
      total_python_processes: length(all_python_pids),
      registered_processes: length(registered_pids),
      orphaned_processes: length(orphaned_pids),
      pools: pools,
      orphaned_pids: orphaned_pids
    }
  end
  
  @doc """
  Updates heartbeat for a pool to indicate it's still alive.
  """
  def update_heartbeat(pool_id) do
    pool_file = pool_filename(pool_id)
    
    case read_pool_file_by_path(pool_file) do
      {:ok, pool_data} ->
        updated_data = Map.put(pool_data, :last_heartbeat, System.system_time(:second))
        
        temp_file = "#{pool_file}.tmp.#{:rand.uniform(999999)}"
        content = Jason.encode!(updated_data)
        File.write!(temp_file, content)
        File.rename!(temp_file, pool_file)
        
        :ok
        
      error -> 
        error
    end
  end
  
  # Private Functions
  
  defp ensure_registry_dir do
    File.mkdir_p!(@registry_dir)
  end
  
  defp pool_filename(pool_id) do
    # Include OS PID and Elixir PID for uniqueness across restarts
    os_pid = List.to_integer(:os.getpid())
    elixir_pid = self() |> inspect() |> String.replace(["#", "<", ">", "."], "_")
    
    filename = "pool_#{pool_id}_#{os_pid}_#{elixir_pid}.json"
    Path.join(@registry_dir, filename)
  end
  
  defp list_pool_files do
    case File.ls(@registry_dir) do
      {:ok, files} -> 
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&String.contains?(&1, ".tmp"))
      {:error, _} -> 
        []
    end
  end
  
  defp validate_and_cleanup_pool_file(filename) do
    pool_file = Path.join(@registry_dir, filename)
    
    case read_pool_file_by_path(pool_file) do
      {:ok, pool_data} ->
        if pool_alive?(pool_data) do
          :alive
        else
          # Pool is dead - kill its processes and remove file
          killed_count = kill_pool_processes(pool_data.processes)
          File.rm(pool_file)
          
          Logger.info("🧹 Cleaned dead pool #{pool_data.pool_id}, killed #{killed_count} processes")
          {:cleaned, killed_count}
        end
        
      {:error, _reason} ->
        # Corrupted or unreadable file - remove it
        File.rm(pool_file)
        Logger.warning("🗑️ Removed corrupted pool file: #{filename}")
        {:cleaned, 0}
    end
  end
  
  defp read_pool_file(filename) do
    pool_file = Path.join(@registry_dir, filename)
    read_pool_file_by_path(pool_file)
  end
  
  defp read_pool_file_by_path(pool_file) do
    case File.read(pool_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, struct(__MODULE__, atomize_keys(data))}
          error -> {:error, "JSON decode failed: #{inspect(error)}"}
        end
      error -> 
        {:error, "File read failed: #{inspect(error)}"}
    end
  end
  
  defp pool_alive?(pool_data) do
    # Check if the Elixir process is still alive
    elixir_pid_alive?(pool_data.elixir_pid) and os_pid_alive?(pool_data.os_pid)
  end
  
  defp elixir_pid_alive?(pid) when is_pid(pid) do
    Process.alive?(pid)
  end
  
  defp elixir_pid_alive?(pid_string) when is_binary(pid_string) do
    # PID stored as string, can't check if alive across nodes
    # Just check if OS process is alive as fallback
    true
  end
  
  defp elixir_pid_alive?(_), do: false
  
  defp os_pid_alive?(os_pid) when is_integer(os_pid) do
    case System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, 1} -> false
      _ -> false
    end
  rescue
    _ -> false
  end
  
  defp kill_pool_processes(processes) when is_list(processes) do
    Enum.reduce(processes, 0, fn process_info, acc ->
      case kill_python_process(process_info) do
        :ok -> acc + 1
        :error -> acc
      end
    end)
  end
  
  defp kill_python_process(%{"python_pid" => pid}) when is_integer(pid) do
    kill_python_process(pid)
  end
  
  defp kill_python_process(%{python_pid: pid}) when is_integer(pid) do
    kill_python_process(pid)
  end
  
  defp kill_python_process(pid) when is_integer(pid) do
    try do
      case System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) do
        {_output, 0} -> 
          Logger.debug("Killed orphaned Python process #{pid}")
          :ok
        {_error, _} -> 
          Logger.debug("Failed to kill Python process #{pid} (may already be dead)")
          :error
      end
    rescue
      _ -> :error
    end
  end
  
  defp kill_python_process(_), do: :error
  
  defp cleanup_unregistered_python_processes do
    all_python_pids = get_all_dspy_bridge_pids()
    registered_pids = get_all_registered_python_pids()
    
    orphaned_pids = all_python_pids -- registered_pids
    
    Enum.reduce(orphaned_pids, 0, fn pid, acc ->
      case kill_python_process(pid) do
        :ok -> 
          Logger.info("🔥 Killed unregistered Python process #{pid}")
          acc + 1
        :error -> 
          acc
      end
    end)
  end
  
  defp get_all_dspy_bridge_pids do
    case System.cmd("pgrep", ["-f", "dspy_bridge.py.*pool-worker"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.to_integer/1)
      _ -> 
        []
    end
  end
  
  defp get_all_registered_python_pids(pools \\ nil) do
    pools = pools || 
      (list_pool_files()
       |> Enum.map(&read_pool_file/1)
       |> Enum.filter(&match?({:ok, _}, &1))
       |> Enum.map(&elem(&1, 1)))
    
    pools
    |> Enum.filter(&pool_alive?/1)
    |> Enum.flat_map(fn pool -> 
      Enum.map(pool.processes, fn 
        %{"python_pid" => pid} when is_integer(pid) -> pid
        %{python_pid: pid} when is_integer(pid) -> pid
        _ -> nil
      end)
    end)
    |> Enum.filter(& &1 != nil)
  end
  
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn 
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), atomize_keys(value)}
      {key, value} -> {key, atomize_keys(value)}
    end)
  rescue
    ArgumentError -> map  # Fallback for unknown atoms
  end
  
  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end
  
  defp atomize_keys(value), do: value
end
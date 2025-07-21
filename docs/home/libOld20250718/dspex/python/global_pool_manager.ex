defmodule DSPex.Python.GlobalPoolManager do
  @moduledoc """
  Global pool manager that ensures machine-wide process cleanup before starting pools.
  
  This module integrates with DSPex.Python.GlobalRegistry to provide automatic
  orphaned process cleanup across all Elixir applications on the same machine.
  
  ## Key Features
  
  - **Automatic Global Cleanup**: Kills orphaned processes before starting new pools
  - **Cross-Application Safety**: Works across different Elixir apps on same machine  
  - **Race-Condition Free**: Uses atomic directory operations
  - **Self-Healing**: Dead pools automatically cleaned up
  - **Zero Configuration**: Works out of the box
  
  ## Usage
  
  Instead of calling `DSPex.Python.Pool.start_link/1` directly, use:
  
      {:ok, pool_pid} = DSPex.Python.GlobalPoolManager.start_global_pool(size: 8)
  
  This ensures global cleanup happens before your pool starts.
  """
  
  require Logger
  
  @doc """
  Starts a V3 pool with global orphaned process cleanup.
  
  This is the main entry point that should replace direct Pool.start_link calls.
  It performs machine-wide cleanup before starting the pool.
  
  ## Options
  
  - `:size` - Number of workers (default: 8)
  - `:pool_id` - Unique pool identifier (default: auto-generated)
  - `:cleanup_timeout` - Time to wait for cleanup (default: 5000ms)
  - All other options are passed to `DSPex.Python.Pool.start_link/1`
  
  ## Returns
  
  `{:ok, pool_pid, cleanup_report}` on success, where cleanup_report contains:
  - `:cleaned_pools` - Number of dead pools removed
  - `:killed_processes` - Number of orphaned processes killed
  - `:registered_pool` - The pool ID that was registered
  """
  def start_global_pool(opts \\ []) do
    size = Keyword.get(opts, :size, 8)
    pool_id = Keyword.get(opts, :pool_id, generate_pool_id())
    cleanup_timeout = Keyword.get(opts, :cleanup_timeout, 5000)
    
    Logger.info("🌍 Starting global pool #{pool_id} with size #{size}")
    
    try do
      # 1. Perform global cleanup BEFORE starting anything
      cleanup_start = System.monotonic_time(:millisecond)
      {cleaned_pools, killed_processes} = DSPex.Python.GlobalRegistry.cleanup_orphaned_globally()
      cleanup_time = System.monotonic_time(:millisecond) - cleanup_start
      
      Logger.info("✅ Global cleanup completed in #{cleanup_time}ms: cleaned #{cleaned_pools} pools, killed #{killed_processes} processes")
      
      # 2. Start the pool infrastructure
      pool_start = System.monotonic_time(:millisecond)
      {:ok, pool_pid} = start_pool_infrastructure(opts)
      
      # 3. Wait for workers to initialize and collect their Python PIDs
      python_processes = collect_worker_processes(pool_pid, size, cleanup_timeout)
      pool_time = System.monotonic_time(:millisecond) - pool_start
      
      Logger.info("🚀 Pool started in #{pool_time}ms with #{length(python_processes)} Python processes")
      
      # 4. Register the pool globally (without additional cleanup since we already did it)
      case DSPex.Python.GlobalRegistry.register_pool_atomically(pool_id, python_processes) do
        :ok ->
          Logger.info("✅ Global registry: registered pool #{pool_id} with #{length(python_processes)} processes")
        {:error, reason} ->
          Logger.warning("⚠️ Failed to register pool globally: #{inspect(reason)}")
      end
      
      # 5. Set up heartbeat monitoring
      start_heartbeat_monitor(pool_id, pool_pid)
      
      final_report = %{
        cleanup_pools_cleaned: cleaned_pools,
        cleanup_processes_killed: killed_processes,
        pool_startup_time_ms: pool_time,
        cleanup_time_ms: cleanup_time,
        registered_processes: length(python_processes),
        registered_pool: pool_id
      }
      
      {:ok, pool_pid, final_report}
      
    rescue
      e ->
        Logger.error("❌ Failed to start global pool: #{inspect(e)}")
        {:error, {:global_pool_startup_failed, e}}
    end
  end
  
  @doc """
  Starts a complete V3 pool system with all required components.
  
  This creates a supervision tree with all necessary components:
  - Registry
  - ProcessRegistry  
  - WorkerSupervisor
  - Pool
  - SessionStore
  """
  def start_complete_v3_system(opts \\ []) do
    size = Keyword.get(opts, :size, 8)
    pool_id = Keyword.get(opts, :pool_id, generate_pool_id())
    
    Logger.info("🔧 Starting complete V3 system for pool #{pool_id}")
    
    children = [
      {Registry, keys: :unique, name: DSPex.Python.Registry},
      DSPex.Python.ProcessRegistry,
      DSPex.Python.WorkerSupervisor,
      {DSPex.Python.Pool, [size: size, name: DSPex.Python.Pool]},
      DSPex.PythonBridge.SessionStore
    ]
    
    case Supervisor.start_link(children, strategy: :one_for_one) do
      {:ok, sup_pid} ->
        # Wait for pool to be ready then register globally
        Process.sleep(1000)  # Allow pool to initialize
        
        pool_pid = case GenServer.whereis(DSPex.Python.Pool) do
          nil -> {:error, :pool_not_found}
          pid -> pid
        end
        
        if is_pid(pool_pid) do
          python_processes = collect_worker_processes(pool_pid, size, 5000)
          registration_report = DSPex.Python.GlobalRegistry.startup_cleanup_and_register(pool_id, python_processes)
          start_heartbeat_monitor(pool_id, pool_pid)
          
          {:ok, sup_pid, pool_pid, registration_report}
        else
          {:error, :pool_startup_failed}
        end
        
      error ->
        error
    end
  end
  
  @doc """
  Stops a global pool and unregisters it.
  """
  def stop_global_pool(pool_pid, pool_id \\ nil) do
    Logger.info("🛑 Stopping global pool #{inspect(pool_pid)}")
    
    # Stop heartbeat monitor
    stop_heartbeat_monitor(pool_pid)
    
    # Unregister from global registry
    if pool_id do
      DSPex.Python.GlobalRegistry.unregister_pool(pool_id)
    end
    
    # Stop the pool
    case pool_pid do
      pid when is_pid(pid) -> 
        Process.exit(pid, :shutdown)
        :ok
      _ -> 
        {:error, :invalid_pool_pid}
    end
  end
  
  @doc """
  Gets comprehensive status of all global pools.
  """
  def get_global_status do
    DSPex.Python.GlobalRegistry.get_global_status()
  end
  
  @doc """
  Performs manual global cleanup (useful for maintenance).
  """
  def manual_global_cleanup do
    Logger.info("🧹 Performing manual global cleanup")
    DSPex.Python.GlobalRegistry.cleanup_orphaned_globally()
  end
  
  # Private Functions
  
  defp generate_pool_id do
    timestamp = System.system_time(:second)
    random = :rand.uniform(999999)
    node_name = node() |> to_string() |> String.replace("@", "_")
    "pool_#{node_name}_#{timestamp}_#{random}"
  end
  
  defp start_pool_infrastructure(opts) do
    size = Keyword.get(opts, :size, 8)
    pool_name = Keyword.get(opts, :name, DSPex.Python.Pool)
    
    # Ensure required components are available
    ensure_registry_started()
    ensure_process_registry_started()
    ensure_worker_supervisor_started()
    ensure_session_store_started()
    ensure_application_cleanup_started()
    
    # Start the pool
    DSPex.Python.Pool.start_link([size: size, name: pool_name])
  end
  
  defp collect_worker_processes(pool_pid, expected_size, timeout) do
    Logger.debug("🔍 Collecting Python process information for #{expected_size} workers")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Wait for workers to initialize
    wait_for_workers_ready(pool_pid, expected_size, timeout)
    
    # Get worker information from ProcessRegistry
    case DSPex.Python.ProcessRegistry.list_all_workers() do
      [] ->
        Logger.warning("⚠️ No workers found in ProcessRegistry")
        []
        
      workers ->
        processes = Enum.map(workers, fn {worker_id, worker_info} ->
          %{
            worker_id: worker_id,
            python_pid: worker_info.python_pid,
            fingerprint: worker_info.fingerprint,
            elixir_pid: worker_info.elixir_pid,
            registered_at: worker_info.registered_at
          }
        end)
        
        elapsed = System.monotonic_time(:millisecond) - start_time
        Logger.debug("✅ Collected #{length(processes)} worker processes in #{elapsed}ms")
        processes
    end
  end
  
  defp wait_for_workers_ready(pool_pid, expected_size, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_loop = fn wait_fn ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      
      if elapsed > timeout do
        Logger.warning("⚠️ Timeout waiting for workers to be ready")
        :timeout
      else
        try do
          stats = DSPex.Python.Pool.get_stats(pool_pid)
          
          if stats.workers >= expected_size do
            Logger.debug("✅ All #{expected_size} workers are ready")
            :ready
          else
            Process.sleep(100)
            wait_fn.(wait_fn)
          end
        rescue
          _ ->
            Process.sleep(100)
            wait_fn.(wait_fn)
        end
      end
    end
    
    wait_loop.(wait_loop)
  end
  
  defp start_heartbeat_monitor(pool_id, pool_pid) do
    # Start a process to update heartbeat every 30 seconds
    spawn_link(fn ->
      heartbeat_loop(pool_id, pool_pid)
    end)
  end
  
  defp heartbeat_loop(pool_id, pool_pid) do
    if Process.alive?(pool_pid) do
      DSPex.Python.GlobalRegistry.update_heartbeat(pool_id)
      Process.sleep(30_000)  # 30 seconds
      heartbeat_loop(pool_id, pool_pid)
    else
      Logger.debug("Pool #{pool_id} died, stopping heartbeat")
      DSPex.Python.GlobalRegistry.unregister_pool(pool_id)
    end
  end
  
  defp stop_heartbeat_monitor(_pool_pid) do
    # Heartbeat monitors are linked and will die with the pool
    :ok
  end
  
  defp ensure_registry_started do
    case GenServer.whereis(DSPex.Python.Registry) do
      nil -> 
        {:ok, _} = Registry.start_link(keys: :unique, name: DSPex.Python.Registry)
      _ -> 
        :ok
    end
  end
  
  defp ensure_process_registry_started do
    case GenServer.whereis(DSPex.Python.ProcessRegistry) do
      nil -> 
        {:ok, _} = DSPex.Python.ProcessRegistry.start_link()
      _ -> 
        :ok
    end
  end
  
  defp ensure_worker_supervisor_started do
    case GenServer.whereis(DSPex.Python.WorkerSupervisor) do
      nil -> 
        {:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
      _ -> 
        :ok
    end
  end
  
  defp ensure_session_store_started do
    case GenServer.whereis(DSPex.PythonBridge.SessionStore) do
      nil -> 
        {:ok, _} = DSPex.PythonBridge.SessionStore.start_link()
      _ -> 
        :ok
    end
  end
  
  defp ensure_application_cleanup_started do
    case GenServer.whereis(DSPex.Python.ApplicationCleanup) do
      nil -> 
        {:ok, _} = DSPex.Python.ApplicationCleanup.start_link()
      _ -> 
        :ok
    end
  end
end
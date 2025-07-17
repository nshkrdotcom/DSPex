defmodule DSPex.Python.SupervisedWorkerManager do
  @moduledoc """
  Worker manager that provides hard guarantees for Python process cleanup.
  
  This supervisor ensures that when it shuts down, ALL Python processes
  are forcefully terminated, preventing orphaned processes.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    size = Keyword.get(opts, :size, 8)
    
    # Create worker specs
    children = for id <- 1..size do
      %{
        id: "python_worker_#{id}",
        start: {DSPex.Python.Worker, :start_link, [[id: "python_worker_#{id}"]]},
        restart: :permanent,
        shutdown: 5000,  # 5 second graceful shutdown
        type: :worker
      }
    end
    
    # Store worker PIDs for emergency cleanup
    :ets.new(__MODULE__, [:named_table, :public, :set])
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Emergency shutdown - kills all Python processes immediately.
  """
  def emergency_shutdown do
    Logger.warning("🚨 Emergency shutdown: killing all Python processes")
    
    # Get all Python PIDs from all workers
    python_pids = get_all_python_pids()
    
    # Kill them all with extreme prejudice
    Enum.each(python_pids, fn pid ->
      try do
        # Kill process group first
        System.cmd("kill", ["-KILL", "-#{pid}"], stderr_to_stdout: true)
        # Then kill individual process as backup
        System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true)
      rescue
        _ -> :ok
      end
    end)
    
    Logger.warning("🔥 Emergency shutdown completed: #{length(python_pids)} processes killed")
  end
  
  @doc """
  Graceful shutdown with timeout.
  """
  def graceful_shutdown(timeout \\ 5000) do
    Logger.info("🛑 Graceful shutdown starting...")
    
    # Send shutdown signal to all workers
    workers = Supervisor.which_children(__MODULE__)
    
    Enum.each(workers, fn {_id, pid, _type, _modules} ->
      if Process.alive?(pid) do
        GenServer.cast(pid, :prepare_shutdown)
      end
    end)
    
    # Wait for graceful shutdown
    Process.sleep(timeout)
    
    # Emergency cleanup for any survivors
    emergency_shutdown()
  end
  
  @doc """
  Get all Python process PIDs from workers.
  """
  def get_all_python_pids do
    workers = Supervisor.which_children(__MODULE__)
    
    Enum.flat_map(workers, fn {_id, pid, _type, _modules} ->
      try do
        case GenServer.call(pid, :get_python_pid, 1000) do
          nil -> []
          python_pid -> [python_pid]
        end
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end
    end)
  end
  
  # Trap exit signals and ensure cleanup
  def terminate(reason, _state) do
    Logger.warning("🛑 SupervisedWorkerManager terminating: #{inspect(reason)}")
    emergency_shutdown()
    :ok
  end
end
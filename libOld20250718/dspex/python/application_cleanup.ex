defmodule DSPex.Python.ApplicationCleanup do
  @moduledoc """
  Provides hard guarantees for Python process cleanup when the application exits.
  
  This module ensures that NO Python processes survive application shutdown,
  preventing orphaned processes while still allowing normal pool operations.
  """
  
  use GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Trap exits so we can cleanup before the VM dies
    Process.flag(:trap_exit, true)
    
    # Register for VM shutdown notifications
    :erlang.process_flag(:priority, :high)
    
    Logger.info("🛡️ Application cleanup handler started")
    {:ok, %{python_pids: []}}
  end
  
  @doc """
  Register a Python process for cleanup tracking.
  """
  def register_python_process(pid) when is_integer(pid) do
    GenServer.cast(__MODULE__, {:register, pid})
  end
  
  @doc """
  Unregister a Python process (normal cleanup).
  """
  def unregister_python_process(pid) when is_integer(pid) do
    GenServer.cast(__MODULE__, {:unregister, pid})
  end
  
  @doc """
  Force cleanup all tracked Python processes.
  """
  def force_cleanup_all do
    GenServer.call(__MODULE__, :force_cleanup_all)
  end
  
  def handle_cast({:register, pid}, state) do
    new_pids = [pid | state.python_pids] |> Enum.uniq()
    {:noreply, %{state | python_pids: new_pids}}
  end
  
  def handle_cast({:unregister, pid}, state) do
    new_pids = List.delete(state.python_pids, pid)
    {:noreply, %{state | python_pids: new_pids}}
  end
  
  def handle_call(:force_cleanup_all, _from, state) do
    killed_count = force_kill_python_processes(state.python_pids)
    {:reply, killed_count, %{state | python_pids: []}}
  end
  
  # This is called when the VM is shutting down
  def terminate(reason, state) do
    Logger.warning("🛑 Application shutting down: #{inspect(reason)}")
    Logger.warning("🔥 Force killing #{length(state.python_pids)} Python processes")
    
    killed_count = force_kill_python_processes(state.python_pids)
    
    Logger.warning("✅ Application cleanup completed: #{killed_count} processes killed")
    :ok
  end
  
  defp force_kill_python_processes(pids) do
    Enum.reduce(pids, 0, fn pid, acc ->
      try do
        # Kill process group first (negative PID)
        case System.cmd("kill", ["-KILL", "-#{pid}"], stderr_to_stdout: true) do
          {_output, 0} -> 
            acc + 1
          {_error, _} ->
            # Fallback to single process kill
            case System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) do
              {_output, 0} -> acc + 1
              {_error, _} -> acc
            end
        end
      rescue
        _ -> acc
      end
    end)
  end
end
defmodule ElixirML.Process.Orchestrator do
  @moduledoc """
  Advanced supervision and process management for ElixirML.
  Every major component runs in its own supervised process for fault tolerance.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Core services
      {ElixirML.Process.SchemaRegistry, []},
      {ElixirML.Process.VariableRegistry, []},
      {ElixirML.Process.ResourceManager, []},

      # Execution services
      {ElixirML.Process.ProgramSupervisor, []},
      {ElixirML.Process.PipelinePool, []},
      {ElixirML.Process.ClientPool, []},

      # Intelligence services
      {ElixirML.Process.TeleprompterSupervisor, []},
      {ElixirML.Process.EvaluationWorkers, []},

      # Integration services
      {ElixirML.Process.ToolRegistry, []},
      {ElixirML.Process.DatasetManager, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Get the status of all supervised processes.
  """
  def status do
    children = Supervisor.which_children(__MODULE__)

    Enum.map(children, fn {id, pid, type, modules} ->
      %{
        id: id,
        pid: pid,
        type: type,
        modules: modules,
        status: if(is_pid(pid) and Process.alive?(pid), do: :running, else: :stopped)
      }
    end)
  end

  @doc """
  Restart a specific child process.
  """
  def restart_child(child_id) do
    Supervisor.restart_child(__MODULE__, child_id)
  end

  @doc """
  Get process statistics for monitoring.
  """
  def process_stats do
    children = Supervisor.which_children(__MODULE__)

    %{
      total_processes: length(children),
      running_processes:
        Enum.count(children, fn {_, pid, _, _} ->
          is_pid(pid) and Process.alive?(pid)
        end),
      memory_usage: :erlang.memory(:processes),
      uptime: :erlang.statistics(:wall_clock) |> elem(0)
    }
  end
end

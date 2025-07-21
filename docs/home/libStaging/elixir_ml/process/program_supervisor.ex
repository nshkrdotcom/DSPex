defmodule ElixirML.Process.ProgramSupervisor do
  @moduledoc """
  Dynamic supervisor for managing program execution processes.
  Each program runs in its own supervised process for isolation and fault tolerance.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new program execution process.
  """
  def start_program(program, opts \\ []) do
    child_spec = {ElixirML.Process.ProgramWorker, [program: program] ++ opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop a program execution process.
  """
  def stop_program(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  List all active program processes.
  """
  def list_programs do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case GenServer.call(pid, :get_program_info, 1000) do
        {:ok, info} -> {:ok, info}
        _ -> {:error, :unavailable}
      end
    end)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, info} -> info end)
  end

  @doc """
  Get program execution statistics.
  """
  def execution_stats do
    children = DynamicSupervisor.which_children(__MODULE__)

    running_count =
      Enum.count(children, fn {_, pid, _, _} ->
        is_pid(pid) and Process.alive?(pid)
      end)

    %{
      total_programs: length(children),
      running_programs: running_count,
      supervisor_memory: Process.info(self(), :memory) |> elem(1)
    }
  end
end

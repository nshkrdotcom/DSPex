defmodule ElixirML.Process.TeleprompterSupervisor do
  @moduledoc """
  Supervisor for teleprompter (optimization) processes.
  Manages SIMBA and other optimization algorithm instances.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new optimization process.
  """
  def start_optimization(algorithm, program, training_data, opts \\ []) do
    child_spec =
      {ElixirML.Process.OptimizationWorker,
       [
         algorithm: algorithm,
         program: program,
         training_data: training_data
       ] ++ opts}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop an optimization process.
  """
  def stop_optimization(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  List all active optimization processes.
  """
  def list_optimizations do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case GenServer.call(pid, :get_status, 1000) do
        {:ok, status} -> {:ok, status}
        _ -> {:error, :unavailable}
      end
    end)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, status} -> status end)
  end
end

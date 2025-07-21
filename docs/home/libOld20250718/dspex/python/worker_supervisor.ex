defmodule DSPex.Python.WorkerSupervisor do
  @moduledoc """
  DynamicSupervisor for Python worker processes.

  This supervisor manages the lifecycle of Python workers:
  - Starts workers on demand
  - Handles crashes with automatic restarts
  - Provides clean shutdown of workers
  """

  use DynamicSupervisor
  require Logger

  @doc """
  Starts the worker supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: []
    )
  end

  @doc """
  Starts a new Python worker with the given ID.

  ## Examples

      iex> DSPex.Python.WorkerSupervisor.start_worker("worker_123")
      {:ok, #PID<0.123.0>}
  """
  def start_worker(worker_id) when is_binary(worker_id) do
    child_spec = {
      DSPex.Python.Worker,
      id: worker_id
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started Python worker #{worker_id} with PID #{inspect(pid)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Worker #{worker_id} already running with PID #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start worker #{worker_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops a worker gracefully.
  """
  def stop_worker(worker_id) do
    case DSPex.Python.Registry.get_worker_pid(worker_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      {:error, :not_found} ->
        {:error, :worker_not_found}
    end
  end

  @doc """
  Lists all supervised workers.
  """
  def list_workers do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&Process.alive?/1)
  end

  @doc """
  Returns the count of active workers.
  """
  def worker_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  Restarts a worker by ID.
  """
  def restart_worker(worker_id) do
    with {:ok, _} <- stop_worker(worker_id),
         :ok <- Process.sleep(100),
         {:ok, pid} <- start_worker(worker_id) do
      {:ok, pid}
    end
  end
end

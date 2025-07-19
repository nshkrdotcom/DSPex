defmodule DSPex.Python.Registry do
  @moduledoc """
  Registry for Python worker processes.

  This is a thin wrapper around Elixir's Registry that provides:
  - Consistent naming for worker processes
  - Easy migration path to distributed registry (Horde)
  - Helper functions for worker lookup
  """

  @registry_name __MODULE__

  @doc """
  Returns the child spec for the registry.
  """
  def child_spec(_opts) do
    Registry.child_spec(
      keys: :unique,
      name: @registry_name
    )
  end

  @doc """
  Returns a via tuple for registering/looking up a worker process.

  ## Examples

      iex> DSPex.Python.Registry.via_tuple("worker_123")
      {:via, Registry, {DSPex.Python.Registry, "worker_123"}}
  """
  def via_tuple(worker_id) when is_binary(worker_id) do
    {:via, Registry, {@registry_name, worker_id}}
  end

  @doc """
  Lists all registered worker IDs.
  """
  def list_workers do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Checks if a worker is registered.
  """
  def worker_exists?(worker_id) do
    case Registry.lookup(@registry_name, worker_id) do
      [] -> false
      _ -> true
    end
  end

  @doc """
  Gets the PID for a worker ID.
  """
  def get_worker_pid(worker_id) do
    case Registry.lookup(@registry_name, worker_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Counts the number of registered workers.
  """
  def worker_count do
    Registry.count(@registry_name)
  end
end

defmodule DSPex.PythonBridge.ConcurrentPoolInitializer do
  @moduledoc """
  Handles concurrent initialization of Python workers for the pool.
  This module pre-creates workers in parallel before handing them to NimblePool.
  """
  
  require Logger
  alias DSPex.PythonBridge.{PythonPort, PoolWorkerV2}
  
  @doc """
  Pre-initialize workers concurrently and return them ready for NimblePool.
  """
  def initialize_workers_concurrently(count) do
    Logger.info("🚀 Starting concurrent initialization of #{count} workers...")
    start_time = System.monotonic_time(:millisecond)
    
    # Start all workers in parallel
    tasks = for i <- 1..count do
      Task.async(fn ->
        worker_id = "worker_#{:erlang.system_time(:microsecond)}_#{i}"
        case start_worker(worker_id) do
          {:ok, worker} ->
            Logger.info("✅ Worker #{i}/#{count} ready: #{worker_id}")
            {:ok, worker}
          {:error, reason} ->
            Logger.error("❌ Worker #{i}/#{count} failed: #{inspect(reason)}")
            {:error, reason}
        end
      end)
    end
    
    # Collect results with timeout
    results = Task.await_many(tasks, 30_000)
    
    successful = Enum.filter(results, fn
      {:ok, _} -> true
      _ -> false
    end)
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.info("🎉 Initialized #{length(successful)}/#{count} workers in #{elapsed}ms")
    
    # Return successful workers
    Enum.map(successful, fn {:ok, worker} -> worker end)
  end
  
  defp start_worker(worker_id) do
    env_info = %{
      python_path: System.find_executable("python3"),
      script_path: Path.join(:code.priv_dir(:dspex), "python/dspy_bridge.py")
    }
    
    case PythonPort.start_link(env_info, pooling: true) do
      {:ok, port} ->
        # Send initialization ping
        init_request = %{
          "command" => "ping",
          "args" => %{
            "worker_id" => worker_id,
            "initialization" => true
          },
          "id" => 0,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        case PythonPort.call(port, init_request, 10_000) do
          {:ok, %{"status" => "success", "worker_id" => ^worker_id}} ->
            {:ok, %{
              port: port,
              id: worker_id,
              initialized_at: DateTime.utc_now()
            }}
          error ->
            Process.exit(port, :kill)
            {:error, {:init_failed, error}}
        end
      error ->
        {:error, {:start_failed, error}}
    end
  end
end
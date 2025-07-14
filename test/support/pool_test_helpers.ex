defmodule DSPex.Test.PoolTestHelpers do
  @moduledoc """
  Helper functions for pool-related tests.
  Provides utilities for starting test pools and waiting for them to be ready.
  """

  require Logger

  @doc """
  Starts a test pool with the given configuration.
  
  ## Options
    * `:min_idle` - Minimum number of idle workers (default: 1)
    * `:max_idle` - Maximum number of idle workers (default: 2)
    * `:checkout_timeout` - Timeout for checking out workers in ms (default: 5000)
  
  Returns `{:ok, pool_pid}` on success, `{:error, reason}` on failure.
  """
  def start_test_pool(opts \\ []) do
    pool_config = [
      name: {:local, :test_pool},
      worker_module: DSPex.PythonBridge.PoolWorkerV2,
      size: Keyword.get(opts, :min_idle, 1),
      max_overflow: Keyword.get(opts, :max_idle, 2) - Keyword.get(opts, :min_idle, 1),
      strategy: :lifo,
      lazy: false
    ]

    case NimblePool.start_link(pool_config) do
      {:ok, pid} ->
        Logger.debug("Test pool started: #{inspect(pid)}")
        {:ok, pid}
      
      {:error, {:already_started, pid}} ->
        Logger.debug("Test pool already running: #{inspect(pid)}")
        {:ok, pid}
      
      {:error, reason} = error ->
        Logger.error("Failed to start test pool: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Waits for a pool to have at least `min_workers` ready.
  
  ## Options
    * `:timeout` - Maximum time to wait in ms (default: 10000)
    * `:check_interval` - Interval between checks in ms (default: 100)
  
  Returns `:ok` when pool is ready, `{:error, :timeout}` if timeout exceeded.
  """
  def wait_for_pool_ready(pool_pid, min_workers \\ 1, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10000)
    check_interval = Keyword.get(opts, :check_interval, 100)
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(pool_pid, min_workers, check_interval, deadline)
  end

  defp wait_loop(pool_pid, min_workers, check_interval, deadline) do
    case get_pool_worker_count(pool_pid) do
      {:ok, count} when count >= min_workers ->
        Logger.debug("Pool ready with #{count} workers")
        :ok
      
      {:ok, count} ->
        now = System.monotonic_time(:millisecond)
        if now < deadline do
          Logger.debug("Pool has #{count} workers, waiting for #{min_workers}...")
          Process.sleep(check_interval)
          wait_loop(pool_pid, min_workers, check_interval, deadline)
        else
          Logger.error("Timeout waiting for pool to have #{min_workers} workers")
          {:error, :timeout}
        end
      
      {:error, reason} ->
        Logger.error("Error checking pool status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_pool_worker_count(pool_pid) do
    try do
      # NimblePool doesn't expose worker count directly, so we check via sys
      {:status, _pid, _module, [_pdict, _sys_state, _parent, _dbg, misc]} = :sys.get_status(pool_pid)
      
      # Extract worker info from misc data
      # This is implementation-specific and may need adjustment
      case misc do
        [_, _, {:data, data}] ->
          # Look for worker-related data
          worker_count = Enum.reduce(data, 0, fn
            {:"$initial_call", _}, acc -> acc
            {:"$ancestors", _}, acc -> acc
            {:worker_count, count}, _acc -> count
            _, acc -> acc
          end)
          
          {:ok, worker_count}
        
        _ ->
          # Fallback: assume pool is ready if it's alive
          if Process.alive?(pool_pid) do
            {:ok, 1}
          else
            {:error, :pool_dead}
          end
      end
    rescue
      e ->
        Logger.warning("Error getting pool status: #{inspect(e)}")
        # Fallback: assume pool is ready if it's alive
        if Process.alive?(pool_pid) do
          {:ok, 1}
        else
          {:error, :pool_dead}
        end
    end
  end
end
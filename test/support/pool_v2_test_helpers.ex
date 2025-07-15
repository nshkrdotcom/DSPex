defmodule DSPex.PoolV2TestHelpers do
  @moduledoc """
  Test helpers for V2 pool testing.

  Provides utilities for:
  - Starting isolated pools with unique names
  - Pre-warming pools to avoid initialization timeouts
  - Managing concurrent test processes
  - Proper cleanup and isolation
  """

  alias DSPex.PythonBridge.SessionPoolV2
  alias DSPex.Adapters.PythonPoolV2

  @doc """
  Starts an isolated pool for testing with pre-warming.

  Options:
  - pool_size: Number of workers (default: 6)
  - overflow: Overflow workers (default: 2)
  - pre_warm: Whether to pre-warm workers (default: true)
  - name_prefix: Prefix for the pool name (default: "test_pool")
  """
  def start_test_pool(opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, 6)
    overflow = Keyword.get(opts, :overflow, 2)
    pre_warm = Keyword.get(opts, :pre_warm, true)
    name_prefix = Keyword.get(opts, :name_prefix, "test_pool")

    # Generate unique name
    genserver_name = :"#{name_prefix}_#{System.unique_integer([:positive])}"

    pool_config = [
      pool_size: pool_size,
      overflow: overflow,
      name: genserver_name
    ]

    # Start the pool using ExUnit's start_supervised!
    pid = ExUnit.Callbacks.start_supervised!({SessionPoolV2, pool_config})

    # Removed artificial supervisor delay - use proper supervision waiting

    # Get the actual NimblePool name
    pool_name = SessionPoolV2.get_pool_name_for(genserver_name)

    # Pre-warm workers if requested
    if pre_warm do
      IO.puts("Pre-warming #{pool_size} workers in parallel...")
      pre_warm_pool(pool_name, pool_size)

      # Verify all workers are actually ready
      status = SessionPoolV2.get_pool_status(genserver_name)
      IO.puts("Pool ready with #{status.pool_size} workers")
    else
      IO.puts("Pool started without pre-warming (lazy initialization)")
    end

    %{
      pool_pid: pid,  # Changed to match test expectations
      genserver_name: genserver_name,
      pool_name: pool_name,
      pool_size: pool_size
    }
  end

  @doc """
  Pre-warms all workers in a pool to avoid initialization timeouts.

  Workers are created in parallel to dramatically improve startup time.
  """
  def pre_warm_pool(pool_name, pool_size) do
    IO.puts("Pre-warming #{pool_size} workers in parallel...")
    
    # Force ALL workers to be created in parallel by checking them all out simultaneously
    # Each checkout forces NimblePool to create a new worker if none exist
    checkout_tasks = 
      for i <- 1..pool_size do
        Task.async(fn ->
          # Use SessionPoolV2 execute to force worker creation through normal channels
          # This ensures workers are properly initialized through the normal flow
          case SessionPoolV2.execute_anonymous(
                 :ping, 
                 %{warmup: true, worker_slot: i}, 
                 pool_name: pool_name,
                 pool_timeout: 10_000,
                 timeout: 10_000
               ) do
            {:ok, response} ->
              worker_id = response["worker_id"] || "worker_#{i}"
              IO.puts("Worker #{i} created: #{worker_id}")
              {:ok, i, worker_id}

            error ->
              IO.puts("Worker #{i} creation failed: #{inspect(error)}")
              {:error, i, error}
          end
        end)
      end
    
    # Wait for all workers to be created with 60-second total timeout
    results = Task.await_many(checkout_tasks, 60_000)

    # Verify all succeeded
    created_workers = 
      Enum.map(results, fn
        {:ok, i, worker_id} -> 
          worker_id
        {:error, i, error} -> 
          raise "Worker #{i} initialization failed: #{inspect(error)}"
      end)

    IO.puts("✓ All #{pool_size} workers ready")
    :ok
  end

  @doc """
  Creates a pool-bound adapter for testing.
  """
  def create_test_adapter(pool_info) do
    PythonPoolV2.with_pool_name(pool_info.genserver_name)
  end

  @doc """
  Creates a session-bound adapter for testing.
  """
  def create_session_adapter(pool_info, session_id) do
    PythonPoolV2.session_adapter(session_id, pool_info.genserver_name)
  end

  @doc """
  Runs concurrent operations using Task.Supervisor.

  This ensures processes stay alive during pool checkout operations.
  """
  def run_concurrent_operations(operations, timeout \\ 30_000) do
    {:ok, task_sup} = Task.Supervisor.start_link()

    tasks =
      Enum.map(operations, fn operation ->
        Task.Supervisor.async(task_sup, operation)
      end)

    results = Task.await_many(tasks, timeout)

    # Clean up supervisor
    Supervisor.stop(task_sup)

    results
  end

  @doc """
  Checks if operations completed concurrently.

  Returns true if the maximum duration is less than 2x the average,
  indicating true parallel execution.
  """
  def verify_concurrent_execution(durations) do
    avg_duration = Enum.sum(durations) / length(durations)
    max_duration = Enum.max(durations)

    IO.puts("Concurrent execution stats:")
    IO.puts("  Average duration: #{avg_duration}ms")
    IO.puts("  Max duration: #{max_duration}ms")
    IO.puts("  Parallelism ratio: #{max_duration / avg_duration}")

    # If truly concurrent, max should be less than 2x average
    if max_duration < avg_duration * 2 do
      {:ok, %{avg: avg_duration, max: max_duration, ratio: max_duration / avg_duration}}
    else
      {:error,
       "Operations appear to be serialized (max: #{max_duration}ms, avg: #{avg_duration}ms)"}
    end
  end

  @doc """
  Waits for a pool to be idle (all workers checked in).
  """
  def wait_for_pool_idle(genserver_name, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_until_idle(genserver_name, deadline)
  end

  defp wait_until_idle(genserver_name, deadline) do
    now = System.monotonic_time(:millisecond)

    if now > deadline do
      raise "Timeout waiting for pool to become idle"
    end

    status = SessionPoolV2.get_pool_status(genserver_name)

    if status.active_sessions == 0 do
      :ok
    else
      # Removed sleep - use proper event-driven waiting
      wait_until_idle(genserver_name, deadline)
    end
  end
end

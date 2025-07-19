defmodule PoolV2SimpleTest do
  use ExUnit.Case, async: false
  require Logger

  alias DSPex.PythonBridge.SessionPoolV2

  @moduletag :layer_3
  @moduletag :pool_v2_simple

  test "basic pool initialization without pre-warming" do
    # Create a pool with a unique name
    pool_name = :"simple_test_pool_#{System.unique_integer([:positive])}"

    # Start pool with minimal configuration
    pool_config = [
      # Just one worker
      pool_size: 1,
      overflow: 0,
      name: pool_name
    ]

    # Start the pool
    {:ok, pid} = start_supervised({SessionPoolV2, pool_config})
    assert Process.alive?(pid)

    IO.puts("Pool started: #{inspect(pool_name)}")

    # Get pool status
    status = SessionPoolV2.get_pool_status(pool_name)
    assert status.pool_size == 1

    # Try a simple ping without pre-warming
    nimble_pool_name = SessionPoolV2.get_pool_name_for(pool_name)

    result =
      SessionPoolV2.execute_anonymous(
        :ping,
        %{test: "simple"},
        pool_name: nimble_pool_name,
        pool_timeout: 30_000
      )

    assert {:ok, response} = result
    assert response["status"] == "ok"

    IO.puts("Ping successful!")
  end

  test "concurrent operations with minimal pool" do
    # Create a pool with a unique name
    pool_name = :"concurrent_test_pool_#{System.unique_integer([:positive])}"

    # Start pool with 2 workers
    pool_config = [
      pool_size: 2,
      overflow: 0,
      name: pool_name
    ]

    {:ok, _pid} = start_supervised({SessionPoolV2, pool_config})

    nimble_pool_name = SessionPoolV2.get_pool_name_for(pool_name)

    # Pre-warm just the first worker
    IO.puts("Pre-warming first worker...")

    {:ok, _} =
      SessionPoolV2.execute_anonymous(
        :ping,
        %{warm: true},
        pool_name: nimble_pool_name,
        pool_timeout: 30_000
      )

    # Now try 2 concurrent operations
    IO.puts("Running concurrent operations...")
    {:ok, task_sup} = Task.Supervisor.start_link()

    tasks =
      for i <- 1..2 do
        Task.Supervisor.async(task_sup, fn ->
          SessionPoolV2.execute_anonymous(
            :ping,
            %{task: i},
            pool_name: nimble_pool_name,
            pool_timeout: 30_000
          )
        end)
      end

    results = Task.await_many(tasks, 60_000)
    Supervisor.stop(task_sup)

    # Both should succeed
    assert length(results) == 2

    for result <- results do
      assert {:ok, _} = result
    end

    IO.puts("Concurrent operations successful!")
  end
end

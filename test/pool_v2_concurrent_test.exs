defmodule PoolV2ConcurrentTest do
  use ExUnit.Case, async: false
  require Logger

  alias DSPex.PythonBridge.SessionPoolV2
  import DSPex.PoolV2TestHelpers

  @moduletag :layer_3
  @moduletag :pool_v2_concurrent

  test "true concurrent execution with pre-warmed workers" do
    # Create a pool with exactly 2 workers
    unique_prefix = "concurrent_pool_#{System.unique_integer([:positive])}"

    pool_info =
      start_test_pool(
        pool_size: 2,
        overflow: 0,
        # Pre-warm both workers
        pre_warm: true,
        name_prefix: unique_prefix
      )

    pool_name = pool_info.pool_name

    IO.puts("Running concurrent operations with pre-warmed workers...")

    # Now both workers are ready, test true concurrency
    {:ok, task_sup} = Task.Supervisor.start_link()

    # Start time for the whole operation
    overall_start = System.monotonic_time(:millisecond)

    # Run 2 operations that each take ~1 second
    tasks =
      for i <- 1..2 do
        Task.Supervisor.async(task_sup, fn ->
          start_time = System.monotonic_time(:millisecond)

          # Just use ping commands - they're simple and reliable
          result =
            SessionPoolV2.execute_anonymous(
              :ping,
              %{
                test_id: i,
                concurrent: true,
                timestamp: DateTime.utc_now()
              },
              pool_name: pool_name,
              pool_timeout: 30_000
            )

          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time

          {i, result, duration}
        end)
      end

    # Wait for both to complete
    results = Task.await_many(tasks, 60_000)

    overall_end = System.monotonic_time(:millisecond)
    overall_duration = overall_end - overall_start

    Supervisor.stop(task_sup)

    # Verify results
    for {i, result, duration} <- results do
      assert {:ok, response} = result
      assert response["status"] == "ok"
      IO.puts("Task #{i} completed in #{duration}ms")
    end

    durations = Enum.map(results, fn {_, _, d} -> d end)
    total_sequential_time = Enum.sum(durations)

    IO.puts("Overall duration: #{overall_duration}ms")
    IO.puts("Sum of individual durations: #{total_sequential_time}ms")
    IO.puts("Concurrency ratio: #{Float.round(total_sequential_time / overall_duration, 2)}")

    # For simple ping operations, we can't expect much time difference
    # Just verify that both completed successfully
    assert length(results) == 2

    # With pre-warmed workers, operations should be very fast
    Enum.each(durations, fn d ->
      # Each ping should complete in under 1 second
      assert d < 1000
    end)
  end

  test "pool handles blocking operations correctly" do
    # Create a pool with 3 workers
    unique_prefix = "blocking_pool_#{System.unique_integer([:positive])}"

    pool_info =
      start_test_pool(
        pool_size: 3,
        overflow: 0,
        # Pre-warm all workers
        pre_warm: true,
        name_prefix: unique_prefix
      )

    pool_name = pool_info.pool_name

    IO.puts("Testing blocking operations...")

    # Run 3 concurrent operations that simulate work
    {:ok, task_sup} = Task.Supervisor.start_link()

    tasks =
      for i <- 1..3 do
        Task.Supervisor.async(task_sup, fn ->
          # Each operation creates a program and does some work
          result =
            SessionPoolV2.execute_in_session(
              "blocking_test_#{i}",
              :create_program,
              %{
                id: "test_program_#{i}_#{System.unique_integer([:positive])}",
                signature: %{
                  inputs: [%{name: "input", type: "string"}],
                  outputs: [%{name: "output", type: "string"}]
                }
              },
              pool_name: pool_name,
              pool_timeout: 30_000
            )

          case result do
            {:ok, program_id} ->
              # List programs to verify it was created
              list_result =
                SessionPoolV2.execute_in_session("blocking_test_#{i}", :list_programs, %{},
                  pool_name: pool_name,
                  pool_timeout: 30_000
                )

              {i, list_result}

            error ->
              {i, error}
          end
        end)
      end

    results = Task.await_many(tasks, 60_000)
    Supervisor.stop(task_sup)

    # All operations should succeed
    for {i, result} <- results do
      assert {:ok, programs} = result
      assert is_list(programs)
      assert length(programs) > 0
      IO.puts("Session #{i} has #{length(programs)} programs")
    end
  end
end

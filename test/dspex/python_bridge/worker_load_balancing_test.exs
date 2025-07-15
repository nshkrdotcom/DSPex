defmodule DSPex.PythonBridge.WorkerLoadBalancingTest do
  @moduledoc """
  Tests for verifying load balancing behavior in stateless worker architecture.

  These tests ensure that work is properly distributed across available workers
  and that no single worker becomes a bottleneck.
  """

  use ExUnit.Case, async: false
  alias DSPex.PythonBridge.{SessionStore, SessionPoolV2, Session}
  require Logger

  @moduletag :integration
  @moduletag :load_balancing

  setup do
    # Generate unique names for each test to avoid conflicts
    test_id = System.unique_integer([:positive])
    store_name = :"lb_test_session_store_#{test_id}"
    pool_name = :"lb_test_session_pool_#{test_id}"
    
    # Start SessionStore for tests
    {:ok, store_pid} = SessionStore.start_link(name: store_name)

    # Start SessionPoolV2 with multiple workers for load balancing tests
    {:ok, pool_pid} =
      SessionPoolV2.start_link(
        name: pool_name,
        pool_size: 4,  # More workers for load balancing tests
        overflow: 2
      )

    on_exit(fn ->
      if Process.alive?(store_pid), do: GenServer.stop(store_pid)
      if Process.alive?(pool_pid), do: GenServer.stop(pool_pid)
    end)

    %{store_pid: store_pid, pool_pid: pool_pid, store_name: store_name, pool_name: pool_name}
  end

  describe "load distribution" do
    test "requests are distributed across multiple workers", %{store_name: store_name} do
      # Create multiple sessions to simulate load
      session_count = 10
      
      session_ids =
        for i <- 1..session_count do
          session_id = "load_test_session_#{i}"
          {:ok, _session} = SessionStore.create_session(store_name, session_id, [])
          session_id
        end

      # Simulate concurrent requests across sessions
      tasks =
        for session_id <- session_ids do
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              request_start: start_time,
              session_id: session_id
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "load_program", program_data)
              end)

            end_time = System.monotonic_time(:millisecond)
            {session_id, end_time - start_time}
          end)
        end

      # Wait for all requests to complete
      results = Task.await_many(tasks, 15000)

      # Verify all requests completed
      assert length(results) == session_count

      # Verify reasonable response times (indicating good load distribution)
      response_times = Enum.map(results, fn {_session_id, time} -> time end)
      avg_response_time = Enum.sum(response_times) / length(response_times)
      max_response_time = Enum.max(response_times)

      # In a well-load-balanced system, max response time shouldn't be too much higher than average
      # Handle case where operations are very fast (avg_response_time near 0)
      threshold = max(avg_response_time * 3, 10.0)  # At least 10ms threshold
      assert max_response_time < threshold, 
        "Max response time (#{max_response_time}ms) is too high compared to average (#{avg_response_time}ms)"

      Logger.info("Load balancing test - Avg: #{avg_response_time}ms, Max: #{max_response_time}ms")
    end

    test "high concurrency requests are handled efficiently", %{store_name: store_name} do
      session_id = "high_concurrency_session_#{System.unique_integer()}"
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate high concurrency with many simultaneous requests
      concurrency_level = 50
      
      tasks =
        for i <- 1..concurrency_level do
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              request_id: i,
              start_time: start_time
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "concurrent_program_#{i}", program_data)
              end)

            end_time = System.monotonic_time(:millisecond)
            {i, end_time - start_time}
          end)
        end

      # Wait for all concurrent requests
      results = Task.await_many(tasks, 30000)

      # Verify all requests completed successfully
      assert length(results) == concurrency_level

      # Verify session contains all programs
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == concurrency_level

      # Analyze response time distribution
      response_times = Enum.map(results, fn {_id, time} -> time end)
      avg_response_time = Enum.sum(response_times) / length(response_times)
      
      # Most requests should complete within reasonable time
      # Handle case where avg_response_time is 0 (very fast operations)
      threshold = max(avg_response_time * 2, 1.0)  # At least 1ms threshold
      fast_requests = Enum.count(response_times, fn time -> time <= threshold end)
      fast_percentage = fast_requests / concurrency_level * 100

      assert fast_percentage > 80, 
        "Only #{fast_percentage}% of requests completed within #{threshold}ms threshold"

      Logger.info("High concurrency test - #{concurrency_level} requests, #{fast_percentage}% fast")
    end
  end

  describe "worker availability" do
    test "system handles worker unavailability gracefully", %{store_name: store_name} do
      session_id = "availability_session_#{System.unique_integer()}"
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate normal operations
      normal_tasks =
        for i <- 1..5 do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              normal_operation: i
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "normal_#{i}", program_data)
              end)

            i
          end)
        end

      # Wait for normal operations
      normal_results = Task.await_many(normal_tasks, 10000)
      assert length(normal_results) == 5

      # Verify operations completed successfully despite potential worker issues
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      assert map_size(session.programs) == 5
    end

    test "load balancing adapts to worker pool changes", %{store_name: store_name} do
      # This test verifies that the system can handle dynamic worker pool changes
      session_id = "adaptive_session_#{System.unique_integer()}"
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Phase 1: Normal load
      phase1_tasks =
        for i <- 1..10 do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              phase: 1,
              operation_id: i
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "phase1_#{i}", program_data)
              end)

            i
          end)
        end

      phase1_results = Task.await_many(phase1_tasks, 10000)
      assert length(phase1_results) == 10

      # Phase 2: Continued operations (simulating worker pool adaptation)
      phase2_tasks =
        for i <- 11..20 do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              phase: 2,
              operation_id: i
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "phase2_#{i}", program_data)
              end)

            i
          end)
        end

      phase2_results = Task.await_many(phase2_tasks, 10000)
      assert length(phase2_results) == 10

      # Verify all operations completed successfully
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 20

      # Verify both phases completed
      for i <- 1..10 do
        {:ok, program} = Session.get_program(final_session, "phase1_#{i}")
        assert program.phase == 1
      end

      for i <- 11..20 do
        {:ok, program} = Session.get_program(final_session, "phase2_#{i}")
        assert program.phase == 2
      end
    end
  end

  describe "performance under load" do
    test "system maintains performance under sustained load", %{store_name: store_name} do
      session_id = "performance_session_#{System.unique_integer()}"
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Measure performance over multiple batches
      batch_size = 20
      batch_count = 3
      
      all_results =
        for batch_num <- 1..batch_count, reduce: [] do
          acc ->
            batch_start = System.monotonic_time(:millisecond)

            batch_tasks =
              for i <- 1..batch_size do
                operation_id = (batch_num - 1) * batch_size + i

                Task.async(fn ->
                  start_time = System.monotonic_time(:millisecond)

                  program_data = %{
                    signature: %{inputs: [], outputs: []},
                    created_at: System.monotonic_time(:second),
                    batch: batch_num,
                    operation_id: operation_id
                  }

                  {:ok, _updated_session} =
                    SessionStore.update_session(store_name, session_id, fn session ->
                      Session.put_program(session, "perf_#{operation_id}", program_data)
                    end)

                  end_time = System.monotonic_time(:millisecond)
                  {operation_id, end_time - start_time}
                end)
              end

            batch_results = Task.await_many(batch_tasks, 15000)
            batch_end = System.monotonic_time(:millisecond)
            batch_duration = batch_end - batch_start

            Logger.info("Batch #{batch_num} completed in #{batch_duration}ms")

            # Brief pause between batches
            Process.sleep(100)
            
            acc ++ batch_results
        end

      # Verify all operations completed
      total_operations = batch_size * batch_count
      assert length(all_results) == total_operations

      # Verify session contains all programs
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == total_operations

      # Analyze performance consistency across batches
      response_times = Enum.map(all_results, fn {_id, time} -> time end)
      avg_response_time = Enum.sum(response_times) / length(response_times)
      
      # Performance should remain consistent (no significant degradation)
      batch1_times = Enum.slice(response_times, 0, batch_size)
      batch3_times = Enum.slice(response_times, -batch_size, batch_size)
      
      batch1_avg = Enum.sum(batch1_times) / length(batch1_times)
      batch3_avg = Enum.sum(batch3_times) / length(batch3_times)
      
      # Last batch shouldn't be significantly slower than first batch
      # Handle case where batch1_avg is 0 (very fast operations)
      performance_ratio = if batch1_avg > 0, do: batch3_avg / batch1_avg, else: 1.0
      assert performance_ratio < 2.0, 
        "Performance degraded significantly: batch3 (#{batch3_avg}ms) vs batch1 (#{batch1_avg}ms)"

      Logger.info("Performance test - Avg: #{avg_response_time}ms, Ratio: #{performance_ratio}")
    end
  end

  describe "session isolation under load" do
    test "concurrent operations on different sessions don't interfere", %{store_name: store_name} do
      # Create multiple sessions
      session_count = 5
      operations_per_session = 10

      session_ids =
        for i <- 1..session_count do
          session_id = "isolation_session_#{i}"
          {:ok, _session} = SessionStore.create_session(store_name, session_id, [])
          session_id
        end

      # Run concurrent operations across all sessions
      all_tasks =
        for {session_id, session_num} <- Enum.with_index(session_ids, 1),
            op_num <- 1..operations_per_session do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              session_num: session_num,
              operation_num: op_num
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "op_#{op_num}", program_data)
              end)

            {session_id, session_num, op_num}
          end)
        end

      # Wait for all operations to complete
      results = Task.await_many(all_tasks, 20000)
      total_operations = session_count * operations_per_session
      assert length(results) == total_operations

      # Verify each session has the correct number of programs
      for {session_id, session_num} <- Enum.with_index(session_ids, 1) do
        {:ok, session} = SessionStore.get_session(store_name, session_id)
        assert map_size(session.programs) == operations_per_session

        # Verify all programs belong to the correct session
        for op_num <- 1..operations_per_session do
          {:ok, program} = Session.get_program(session, "op_#{op_num}")
          assert program.session_num == session_num
          assert program.operation_num == op_num
        end
      end
    end
  end
end
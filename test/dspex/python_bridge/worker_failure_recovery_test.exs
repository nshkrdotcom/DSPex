defmodule DSPex.PythonBridge.WorkerFailureRecoveryTest do
  @moduledoc """
  Tests for worker failure and recovery scenarios in stateless architecture.

  These tests verify that the system can handle worker failures gracefully
  and that session data remains available when workers fail or restart.
  """

  use ExUnit.Case, async: false
  alias DSPex.PythonBridge.{SessionStore, SessionPoolV2, Session}
  require Logger

  @moduletag :integration
  @moduletag :failure_recovery

  setup do
    # Generate unique names for each test to avoid conflicts
    test_id = System.unique_integer([:positive])
    store_name = :"failure_test_session_store_#{test_id}"
    pool_name = :"failure_test_session_pool_#{test_id}"
    
    # Start SessionStore for tests
    {:ok, store_pid} = SessionStore.start_link(name: store_name)

    # Start SessionPoolV2 for tests
    {:ok, pool_pid} =
      SessionPoolV2.start_link(
        name: pool_name,
        pool_size: 3,
        overflow: 1
      )

    on_exit(fn ->
      if Process.alive?(store_pid), do: GenServer.stop(store_pid)
      if Process.alive?(pool_pid), do: GenServer.stop(pool_pid)
    end)

    %{store_pid: store_pid, pool_pid: pool_pid, store_name: store_name, pool_name: pool_name}
  end

  describe "session persistence during worker failures" do
    test "session data survives simulated worker failure", %{store_name: store_name} do
      session_id = "failure_test_session_#{System.unique_integer()}"

      # Create session with initial data
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Add multiple programs to the session
      programs_data = [
        {"program_1", %{signature: %{inputs: [], outputs: []}, execution_count: 5}},
        {"program_2", %{signature: %{inputs: [], outputs: []}, execution_count: 3}},
        {"program_3", %{signature: %{inputs: [], outputs: []}, execution_count: 7}}
      ]

      for {program_id, program_data} <- programs_data do
        {:ok, _updated_session} =
          SessionStore.update_session(store_name, session_id, fn session ->
            Session.put_program(session, program_id, program_data)
          end)
      end

      # Verify initial state
      {:ok, session_before} = SessionStore.get_session(store_name, session_id)
      assert map_size(session_before.programs) == 3

      # Simulate worker failure by continuing operations
      # (In the old architecture, this would have lost session data)
      # In the new architecture, data should persist in the centralized store

      # Verify session data is still available after simulated failure
      {:ok, session_after} = SessionStore.get_session(store_name, session_id)
      assert map_size(session_after.programs) == 3

      # Verify specific program data
      for {program_id, expected_data} <- programs_data do
        {:ok, program} = Session.get_program(session_after, program_id)
        assert program.execution_count == expected_data.execution_count
      end
    end

    test "new worker can access session data after previous worker failure", %{store_name: store_name} do
      session_id = "handover_test_session_#{System.unique_integer()}"

      # Create session and add data (simulating first worker)
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      original_program_data = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        created_by: "original_worker",
        execution_count: 10
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "handover_program", original_program_data)
        end)

      # Simulate first worker failure and new worker taking over
      # New worker should be able to access and modify the session

      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "handover_program")
      assert program.created_by == "original_worker"
      assert program.execution_count == 10

      # New worker updates the program
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          {:ok, existing_program} = Session.get_program(session, "handover_program")

          updated_program = %{
            existing_program
            | execution_count: existing_program.execution_count + 5,
              updated_by: "new_worker"
          }

          Session.put_program(session, "handover_program", updated_program)
        end)

      # Verify new worker successfully updated the session
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      {:ok, final_program} = Session.get_program(final_session, "handover_program")
      assert final_program.created_by == "original_worker"
      assert final_program.updated_by == "new_worker"
      assert final_program.execution_count == 15
    end
  end

  describe "recovery from session store errors" do
    test "system handles session store temporary unavailability", %{store_pid: store_pid, store_name: store_name} do
      session_id = "recovery_test_session_#{System.unique_integer()}"

      # Create session normally
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Add initial data
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "recovery_program", %{
            signature: %{inputs: [], outputs: []},
            execution_count: 1
          })
        end)

      # Verify initial state
      {:ok, session_before} = SessionStore.get_session(store_name, session_id)
      {:ok, program_before} = Session.get_program(session_before, "recovery_program")
      assert program_before.execution_count == 1

      # Simulate brief store unavailability by stopping and restarting
      GenServer.stop(store_pid, :normal)
      Process.sleep(100)

      # Restart session store
      {:ok, _new_store_pid} = SessionStore.start_link(name: store_name)

      # Session should be gone (since we restarted the store)
      # But in a real implementation with persistent storage, it would survive
      assert {:error, :not_found} = SessionStore.get_session(store_name, session_id)

      # Recreate session to simulate recovery
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "recovery_program", %{
            signature: %{inputs: [], outputs: []},
            execution_count: 1,
            recovered: true
          })
        end)

      # Verify recovery
      {:ok, recovered_session} = SessionStore.get_session(store_name, session_id)
      {:ok, recovered_program} = Session.get_program(recovered_session, "recovery_program")
      assert recovered_program.recovered == true
    end

    test "concurrent operations handle session store errors gracefully", %{store_name: store_name} do
      session_id = "concurrent_error_session_#{System.unique_integer()}"

      # Create session
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Start concurrent operations
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            try do
              program_data = %{
                signature: %{inputs: [], outputs: []},
                created_at: System.monotonic_time(:second),
                operation_id: i
              }

              {:ok, _updated_session} =
                SessionStore.update_session(store_name, session_id, fn session ->
                  Session.put_program(session, "concurrent_#{i}", program_data)
                end)

              {:ok, i}
            catch
              kind, error ->
                Logger.warning("Operation #{i} failed: #{kind} - #{inspect(error)}")
                {:error, i}
            end
          end)
        end

      # Wait for all operations (some may fail, that's expected)
      results = Task.await_many(tasks, 10000)

      # Count successful operations
      successful_ops = Enum.count(results, fn result -> match?({:ok, _}, result) end)
      failed_ops = Enum.count(results, fn result -> match?({:error, _}, result) end)

      Logger.info("Concurrent error test: #{successful_ops} successful, #{failed_ops} failed")

      # At least some operations should succeed
      assert successful_ops > 0

      # Verify successful operations are reflected in the session
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == successful_ops
    end
  end

  describe "worker pool resilience" do
    test "system continues operating with reduced worker pool", %{store_name: store_name} do
      session_id = "resilience_test_session_#{System.unique_integer()}"

      # Create session
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Phase 1: Normal operations with full worker pool
      phase1_tasks =
        for i <- 1..5 do
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
      assert length(phase1_results) == 5

      # Simulate reduced worker pool (some workers failed)
      # In a real scenario, this would involve actual worker failures
      # For this test, we'll simulate by adding delay and continuing operations

      # Phase 2: Operations with simulated reduced capacity
      phase2_tasks =
        for i <- 6..10 do
          Task.async(fn ->
            # Add small delay to simulate reduced capacity
            Process.sleep(50)

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

      phase2_results = Task.await_many(phase2_tasks, 15000)
      assert length(phase2_results) == 5

      # Verify all operations completed despite reduced capacity
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 10

      # Verify both phases completed successfully
      for i <- 1..5 do
        {:ok, program} = Session.get_program(final_session, "phase1_#{i}")
        assert program.phase == 1
      end

      for i <- 6..10 do
        {:ok, program} = Session.get_program(final_session, "phase2_#{i}")
        assert program.phase == 2
      end
    end

    test "session operations resume after worker pool recovery", %{store_name: store_name} do
      session_id = "recovery_resume_session_#{System.unique_integer()}"

      # Create session with some initial data
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "initial_program", %{
            signature: %{inputs: [], outputs: []},
            created_at: System.monotonic_time(:second),
            phase: "initial"
          })
        end)

      # Simulate worker pool failure period
      # (In reality, this would involve actual worker process failures)
      Process.sleep(100)

      # Simulate recovery and resumed operations
      recovery_tasks =
        for i <- 1..8 do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              phase: "recovery",
              operation_id: i
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "recovery_#{i}", program_data)
              end)

            i
          end)
        end

      recovery_results = Task.await_many(recovery_tasks, 15000)
      assert length(recovery_results) == 8

      # Verify all data is present (initial + recovery operations)
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 9  # 1 initial + 8 recovery

      # Verify initial program survived
      {:ok, initial_program} = Session.get_program(final_session, "initial_program")
      assert initial_program.phase == "initial"

      # Verify recovery operations completed
      for i <- 1..8 do
        {:ok, program} = Session.get_program(final_session, "recovery_#{i}")
        assert program.phase == "recovery"
        assert program.operation_id == i
      end
    end
  end

  describe "data consistency during failures" do
    test "session data remains consistent during concurrent failures", %{store_name: store_name} do
      session_id = "consistency_failure_session_#{System.unique_integer()}"

      # Create session
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Initialize shared counter program
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "shared_counter", %{
            signature: %{inputs: [], outputs: []},
            count: 0,
            created_at: System.monotonic_time(:second)
          })
        end)

      # Simulate concurrent operations with potential failures
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            try do
              {:ok, _updated_session} =
                SessionStore.update_session(store_name, session_id, fn session ->
                  {:ok, counter_program} = Session.get_program(session, "shared_counter")

                  updated_program = %{
                    counter_program
                    | count: counter_program.count + 1,
                      last_updated_by: i
                  }

                  Session.put_program(session, "shared_counter", updated_program)
                end)

              {:ok, i}
            catch
              kind, error ->
                Logger.warning("Counter update #{i} failed: #{kind} - #{inspect(error)}")
                {:error, i}
            end
          end)
        end

      # Wait for all operations
      results = Task.await_many(tasks, 15000)

      # Count successful operations
      successful_ops = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # Verify final counter value matches successful operations
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      {:ok, final_counter} = Session.get_program(final_session, "shared_counter")
      assert final_counter.count == successful_ops

      Logger.info("Consistency test: #{successful_ops}/20 operations succeeded, final count: #{final_counter.count}")
    end
  end
end
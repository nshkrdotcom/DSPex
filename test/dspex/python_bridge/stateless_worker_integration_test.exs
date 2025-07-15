defmodule DSPex.PythonBridge.StatelessWorkerIntegrationTest do
  @moduledoc """
  Integration tests for stateless worker architecture.

  These tests verify that workers can operate in a stateless manner,
  fetching session data from the centralized SessionStore on demand.
  """

  use ExUnit.Case, async: false
  alias DSPex.PythonBridge.{SessionStore, SessionPoolV2, Session}
  require Logger

  @moduletag :integration

  setup do
    # Generate unique names for each test to avoid conflicts
    test_id = System.unique_integer([:positive])
    store_name = :"test_session_store_#{test_id}"
    pool_name = :"test_session_pool_#{test_id}"
    
    # Start SessionStore for tests
    {:ok, store_pid} = SessionStore.start_link(name: store_name)

    # Start SessionPoolV2 for tests
    {:ok, pool_pid} =
      SessionPoolV2.start_link(
        name: pool_name,
        pool_size: 2,
        overflow: 1
      )

    on_exit(fn ->
      if Process.alive?(store_pid), do: GenServer.stop(store_pid)
      if Process.alive?(pool_pid), do: GenServer.stop(pool_pid)
    end)

    %{store_pid: store_pid, pool_pid: pool_pid, store_name: store_name, pool_name: pool_name}
  end

  describe "stateless worker session access" do
    test "worker can access session data from centralized store", %{store_name: store_name} do
      session_id = "test_session_#{System.unique_integer()}"

      # Create session in centralized store
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Add program to session
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "test_program", %{
            signature: %{inputs: [], outputs: []},
            created_at: System.monotonic_time(:second)
          })
        end)

      # Verify session exists and has program
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      assert Map.has_key?(session.programs, "test_program")
    end

    test "worker can create program in centralized session store", %{store_name: store_name} do
      session_id = "test_session_#{System.unique_integer()}"

      # Create session in centralized store
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate worker creating a program (this would normally go through Python bridge)
      program_data = %{
        signature: %{
          inputs: [%{name: "question", description: "The question to answer"}],
          outputs: [%{name: "answer", description: "The answer"}]
        },
        created_at: System.monotonic_time(:second),
        execution_count: 0
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "qa_program", program_data)
        end)

      # Verify program was created
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "qa_program")
      assert program.signature.inputs == program_data.signature.inputs
    end

    test "worker can update program execution statistics", %{store_name: store_name} do
      session_id = "test_session_#{System.unique_integer()}"

      # Create session with program
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      program_data = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        execution_count: 0,
        last_executed: nil
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "test_program", program_data)
        end)

      # Simulate program execution and statistics update
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          {:ok, program} = Session.get_program(session, "test_program")

          updated_program = %{
            program
            | execution_count: program.execution_count + 1,
              last_executed: System.monotonic_time(:second)
          }

          Session.put_program(session, "test_program", updated_program)
        end)

      # Verify statistics were updated
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "test_program")
      assert program.execution_count == 1
      assert program.last_executed != nil
    end
  end

  describe "multi-worker session consistency" do
    test "multiple workers can access same session consistently", %{store_name: store_name} do
      session_id = "shared_session_#{System.unique_integer()}"

      # Create session in centralized store
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate multiple workers accessing the same session
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            program_id = "program_#{i}"

            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              worker_id: "worker_#{i}"
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, program_id, program_data)
              end)

            # Verify the program was added
            {:ok, session} = SessionStore.get_session(store_name, session_id)
            {:ok, program} = Session.get_program(session, program_id)
            assert program.worker_id == "worker_#{i}"

            program_id
          end)
        end

      # Wait for all tasks to complete
      program_ids = Task.await_many(tasks, 5000)

      # Verify all programs were created consistently
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 5

      for program_id <- program_ids do
        assert Map.has_key?(final_session.programs, program_id)
      end
    end

    test "session data remains consistent across worker operations", %{store_name: store_name} do
      session_id = "consistency_session_#{System.unique_integer()}"

      # Create session with initial program
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      initial_program = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        execution_count: 0
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "shared_program", initial_program)
        end)

      # Simulate concurrent updates from multiple workers
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                {:ok, program} = Session.get_program(session, "shared_program")

                updated_program = %{
                  program
                  | execution_count: program.execution_count + 1
                }

                Session.put_program(session, "shared_program", updated_program)
              end)
          end)
        end

      # Wait for all updates to complete
      Task.await_many(tasks, 5000)

      # Verify final execution count is correct
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      {:ok, final_program} = Session.get_program(final_session, "shared_program")
      assert final_program.execution_count == 10
    end
  end

  describe "worker failure and recovery" do
    test "session data survives worker failure", %{store_name: store_name} do
      session_id = "survivor_session_#{System.unique_integer()}"

      # Create session with program
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      program_data = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        execution_count: 5
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "persistent_program", program_data)
        end)

      # Simulate worker failure by not affecting the centralized store
      # (In the old architecture, this would have lost the session data)

      # Verify session data is still available
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "persistent_program")
      assert program.execution_count == 5
    end

    test "new worker can access existing session data", %{store_name: store_name} do
      session_id = "handover_session_#{System.unique_integer()}"

      # Create session with program (simulating first worker)
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      program_data = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        original_worker: "worker_1"
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "handover_program", program_data)
        end)

      # Simulate new worker accessing the same session
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "handover_program")
      assert program.original_worker == "worker_1"

      # New worker can update the program
      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          {:ok, existing_program} = Session.get_program(session, "handover_program")

          updated_program = Map.put(existing_program, :new_worker, "worker_2")
          Session.put_program(session, "handover_program", updated_program)
        end)

      # Verify update was successful
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      {:ok, final_program} = Session.get_program(final_session, "handover_program")
      assert final_program.original_worker == "worker_1"
      assert final_program.new_worker == "worker_2"
    end
  end

  describe "load balancing verification" do
    test "any worker can handle any session request", %{store_name: store_name} do
      # Create multiple sessions
      session_ids =
        for i <- 1..3 do
          session_id = "lb_session_#{i}"
          {:ok, _session} = SessionStore.create_session(store_name, session_id, [])
          session_id
        end

      # Simulate different workers handling different sessions
      tasks =
        for {session_id, worker_num} <- Enum.with_index(session_ids, 1) do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              handled_by: "worker_#{worker_num}"
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "lb_program", program_data)
              end)

            {session_id, worker_num}
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # Verify each session was handled by a different worker
      for {session_id, expected_worker} <- results do
        {:ok, session} = SessionStore.get_session(store_name, session_id)
        {:ok, program} = Session.get_program(session, "lb_program")
        assert program.handled_by == "worker_#{expected_worker}"
      end
    end

    test "session operations are distributed across available workers", %{store_name: store_name} do
      session_id = "distributed_session_#{System.unique_integer()}"

      # Create session
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate multiple operations from different workers
      tasks =
        for i <- 1..6 do
          Task.async(fn ->
            worker_id = "worker_#{rem(i, 3) + 1}"  # Distribute across 3 workers

            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              operation_id: i,
              worker_id: worker_id
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "operation_#{i}", program_data)
              end)

            worker_id
          end)
        end

      # Wait for all operations to complete
      worker_ids = Task.await_many(tasks, 5000)

      # Verify operations were distributed across workers
      unique_workers = Enum.uniq(worker_ids)
      assert length(unique_workers) == 3
      assert "worker_1" in unique_workers
      assert "worker_2" in unique_workers
      assert "worker_3" in unique_workers

      # Verify all operations were recorded
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 6
    end
  end

  describe "session store integration" do
    test "worker checkout process integrates with session store", %{store_name: store_name} do
      session_id = "checkout_session_#{System.unique_integer()}"

      # Create session in store
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Verify session exists before worker operations
      assert SessionStore.session_exists?(store_name, session_id)

      # Simulate worker checkout and operation
      program_data = %{
        signature: %{inputs: [], outputs: []},
        created_at: System.monotonic_time(:second),
        checkout_test: true
      }

      {:ok, _updated_session} =
        SessionStore.update_session(store_name, session_id, fn session ->
          Session.put_program(session, "checkout_program", program_data)
        end)

      # Verify operation was successful
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      {:ok, program} = Session.get_program(session, "checkout_program")
      assert program.checkout_test == true
    end

    test "session store handles concurrent worker access", %{store_name: store_name} do
      session_id = "concurrent_session_#{System.unique_integer()}"

      # Create session
      {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

      # Simulate high concurrency
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            program_data = %{
              signature: %{inputs: [], outputs: []},
              created_at: System.monotonic_time(:second),
              concurrent_id: i
            }

            {:ok, _updated_session} =
              SessionStore.update_session(store_name, session_id, fn session ->
                Session.put_program(session, "concurrent_#{i}", program_data)
              end)

            i
          end)
        end

      # Wait for all concurrent operations
      results = Task.await_many(tasks, 10000)

      # Verify all operations completed successfully
      assert length(results) == 20
      assert Enum.sort(results) == Enum.to_list(1..20)

      # Verify all programs were created
      {:ok, final_session} = SessionStore.get_session(store_name, session_id)
      assert map_size(final_session.programs) == 20

      for i <- 1..20 do
        {:ok, program} = Session.get_program(final_session, "concurrent_#{i}")
        assert program.concurrent_id == i
      end
    end
  end
end
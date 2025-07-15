defmodule DSPex.PythonBridge.PoolWorkerV2Test do
  use ExUnit.Case, async: false
  require Logger

  alias DSPex.PythonBridge.PoolWorkerV2
  alias DSPex.PythonBridge.Protocol

  @moduletag :core_pool

  describe "worker initialization" do
    test "init_worker/1 successfully initializes a worker with health verification" do
      Logger.configure(level: :info)

      # Initialize worker
      result = PoolWorkerV2.init_worker({})

      assert {:ok, worker_state, pool_state} = result
      assert worker_state.health_status == :healthy
      assert is_binary(worker_state.worker_id)
      assert is_port(worker_state.port)
      assert worker_state.current_session == nil
      assert is_map(worker_state.stats)
      assert pool_state == {}

      # Cleanup
      Port.close(worker_state.port)
    end

    test "init_worker/1 fails gracefully when Python environment is invalid" do
      # Mock environment check to fail by setting an invalid script path
      original_env = Application.get_env(:dspex, :python_bridge, %{})

      # Convert keyword list to map if needed
      original_map = if is_list(original_env), do: Map.new(original_env), else: original_env

      Application.put_env(
        :dspex,
        :python_bridge,
        Map.put(original_map, :script_path, "nonexistent/script.py")
      )

      assert_raise RuntimeError, ~r/Failed to validate Python environment/, fn ->
        PoolWorkerV2.init_worker({})
      end

      # Restore original environment
      Application.put_env(:dspex, :python_bridge, original_env)
    end

    test "worker generates unique worker IDs" do
      # Initialize multiple workers and verify unique IDs
      workers =
        for _ <- 1..3 do
          {:ok, worker_state, _} = PoolWorkerV2.init_worker({})
          worker_state
        end

      worker_ids = Enum.map(workers, & &1.worker_id)
      assert length(Enum.uniq(worker_ids)) == 3

      # Cleanup
      Enum.each(workers, fn worker -> Port.close(worker.port) end)
    end
  end

  describe "direct port communication" do
    setup do
      {:ok, worker_state, pool_state} = PoolWorkerV2.init_worker({})

      on_exit(fn ->
        if Process.alive?(self()) and Port.info(worker_state.port) do
          Port.close(worker_state.port)
        end
      end)

      %{worker_state: worker_state, pool_state: pool_state}
    end

    test "handle_checkout/4 connects port to client process for session checkout", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      client_pid = self()
      from = {client_pid, make_ref()}

      result =
        PoolWorkerV2.handle_checkout({:session, "test_session"}, from, worker_state, pool_state)

      assert {:ok, updated_worker, client_state, ^pool_state} = result
      assert updated_worker.stats.checkouts == 1
      assert client_state == updated_worker

      # Verify port is connected to client
      port_info = Port.info(worker_state.port)
      assert port_info[:connected] == client_pid
    end

    test "handle_checkout/4 connects port to client process for any_worker checkout", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      client_pid = self()
      from = {client_pid, make_ref()}

      result = PoolWorkerV2.handle_checkout(:any_worker, from, worker_state, pool_state)

      assert {:ok, updated_worker, client_state, ^pool_state} = result
      assert updated_worker.stats.checkouts == 1
      assert client_state == updated_worker

      # Verify port is connected to client
      port_info = Port.info(worker_state.port)
      assert port_info[:connected] == client_pid
    end

    test "handle_checkout/4 connects port to client process for anonymous checkout", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      client_pid = self()
      from = {client_pid, make_ref()}

      result = PoolWorkerV2.handle_checkout(:anonymous, from, worker_state, pool_state)

      assert {:ok, updated_worker, client_state, ^pool_state} = result
      assert updated_worker.stats.checkouts == 1
      assert client_state == updated_worker

      # Verify port is connected to client
      port_info = Port.info(worker_state.port)
      assert port_info[:connected] == client_pid
    end

    test "handle_checkout/4 fails gracefully with invalid checkout type", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      client_pid = self()
      from = {client_pid, make_ref()}

      result = PoolWorkerV2.handle_checkout(:invalid_type, from, worker_state, pool_state)

      assert {:remove, {:invalid_checkout_type, :invalid_type}, ^pool_state} = result
    end

    test "handle_checkout/4 fails when client process is not alive", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      # Create a process and kill it
      dead_pid = spawn(fn -> :ok end)
      Process.exit(dead_pid, :kill)
      # Ensure process is dead
      :timer.sleep(10)

      from = {dead_pid, make_ref()}

      result = PoolWorkerV2.handle_checkout(:any_worker, from, worker_state, pool_state)

      assert {:remove, {:checkout_failed, :process_not_alive}, ^pool_state} = result
    end
  end

  describe "worker lifecycle" do
    setup do
      {:ok, worker_state, pool_state} = PoolWorkerV2.init_worker({})

      on_exit(fn ->
        if Process.alive?(self()) and Port.info(worker_state.port) do
          Port.close(worker_state.port)
        end
      end)

      %{worker_state: worker_state, pool_state: pool_state}
    end

    test "handle_checkin/4 updates stats for successful checkin", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      from = {self(), make_ref()}

      result = PoolWorkerV2.handle_checkin(:ok, from, worker_state, pool_state)

      assert {:ok, updated_worker, ^pool_state} = result
      assert updated_worker.stats.successful_checkins == 1
      assert updated_worker.stats.last_activity > worker_state.stats.last_activity
    end

    test "handle_checkin/4 updates stats for error checkin", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      from = {self(), make_ref()}

      result = PoolWorkerV2.handle_checkin({:error, :timeout}, from, worker_state, pool_state)

      assert {:ok, updated_worker, ^pool_state} = result
      assert updated_worker.stats.error_checkins == 1
      assert updated_worker.stats.last_activity > worker_state.stats.last_activity
    end

    test "handle_checkin/4 removes worker on close checkin", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      from = {self(), make_ref()}

      result = PoolWorkerV2.handle_checkin(:close, from, worker_state, pool_state)

      assert {:remove, :closed, ^pool_state} = result
    end

    test "handle_info/2 removes worker when port exits", %{worker_state: worker_state} do
      port = worker_state.port

      result = PoolWorkerV2.handle_info({port, {:exit_status, 1}}, worker_state)

      assert {:remove, :port_exited} = result
    end

    test "handle_info/2 ignores unrelated messages", %{worker_state: worker_state} do
      result = PoolWorkerV2.handle_info(:unrelated_message, worker_state)

      assert {:ok, ^worker_state} = result
    end

    test "terminate_worker/3 gracefully shuts down Python process", %{
      worker_state: worker_state,
      pool_state: pool_state
    } do
      result = PoolWorkerV2.terminate_worker(:normal, worker_state, pool_state)

      assert {:ok, ^pool_state} = result

      # Port should be closed after termination
      refute Port.info(worker_state.port)
    end
  end

  describe "health verification" do
    test "ping command verification during initialization" do
      # This test verifies that the ping command works correctly
      # by checking the initialization process
      {:ok, worker_state, _} = PoolWorkerV2.init_worker({})

      assert worker_state.health_status == :healthy

      # Cleanup
      Port.close(worker_state.port)
    end

    test "worker can communicate with Python process after initialization" do
      {:ok, worker_state, _} = PoolWorkerV2.init_worker({})

      # Send a direct ping command to verify communication
      request_id = 1
      request = Protocol.encode_request(request_id, :ping, %{test: true})

      # Connect port to current process for testing
      Port.connect(worker_state.port, self())
      Port.command(worker_state.port, request)

      # Wait for response
      port = worker_state.port
      assert_receive {^port, {:data, response_data}}, 5000

      {:ok, ^request_id, response} = Protocol.decode_response(response_data)
      assert response["status"] == "ok"
      assert response["dspy_available"] == true
      assert response["mode"] == "pool-worker"
      assert response["worker_id"] == worker_state.worker_id

      # Cleanup
      Port.close(worker_state.port)
    end
  end

  describe "worker information and monitoring" do
    test "get_worker_info/1 returns comprehensive worker information" do
      {:ok, worker_state, _} = PoolWorkerV2.init_worker({})

      info = PoolWorkerV2.get_worker_info(worker_state)

      assert info.worker_id == worker_state.worker_id
      assert info.current_session == nil
      assert info.health_status == :healthy
      assert is_map(info.stats)
      assert is_integer(info.uptime_ms)
      assert info.uptime_ms >= 0

      # Cleanup
      Port.close(worker_state.port)
    end

    test "worker stats are properly initialized" do
      {:ok, worker_state, _} = PoolWorkerV2.init_worker({})

      stats = worker_state.stats
      assert stats.checkouts == 0
      assert stats.successful_checkins == 0
      assert stats.error_checkins == 0
      assert is_integer(stats.last_activity)

      # Cleanup
      Port.close(worker_state.port)
    end
  end

  describe "stateless architecture compliance" do
    test "worker does not maintain session binding" do
      {:ok, worker_state, pool_state} = PoolWorkerV2.init_worker({})

      # Checkout with session should not bind session to worker
      from = {self(), make_ref()}

      {:ok, updated_worker, _, _} =
        PoolWorkerV2.handle_checkout({:session, "test_session"}, from, worker_state, pool_state)

      # current_session should remain nil (stateless)
      assert updated_worker.current_session == nil

      # Cleanup
      Port.close(worker_state.port)
    end

    test "any worker can handle any session" do
      {:ok, worker_state, pool_state} = PoolWorkerV2.init_worker({})

      # Worker should handle different sessions without binding
      sessions = ["session_1", "session_2", "session_3"]

      Enum.each(sessions, fn session_id ->
        from = {self(), make_ref()}

        {:ok, updated_worker, _, _} =
          PoolWorkerV2.handle_checkout({:session, session_id}, from, worker_state, pool_state)

        assert updated_worker.current_session == nil
      end)

      # Cleanup
      Port.close(worker_state.port)
    end
  end

  describe "error handling and recovery" do
    test "worker handles port connection failures gracefully" do
      {:ok, worker_state, pool_state} = PoolWorkerV2.init_worker({})

      # Close the port to simulate failure
      Port.close(worker_state.port)

      # Attempt checkout should fail gracefully
      from = {self(), make_ref()}
      result = PoolWorkerV2.handle_checkout(:any_worker, from, worker_state, pool_state)

      assert {:remove, {:checkout_failed, _reason}, ^pool_state} = result
    end

    test "worker initialization fails with proper error when Python process fails" do
      # This test would require mocking the Python process startup
      # For now, we verify the error handling structure exists
      assert function_exported?(PoolWorkerV2, :init_worker, 1)
      assert function_exported?(PoolWorkerV2, :terminate_worker, 3)
    end
  end
end

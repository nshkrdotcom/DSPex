defmodule DSPex.PythonBridge.PoolWorkerUnitTest do
  use ExUnit.Case, async: true

  alias DSPex.Test.PoolWorkerHelpers

  describe "worker state management" do
    setup do
      worker = PoolWorkerHelpers.mock_worker_state()
      {:ok, worker: worker}
    end

    @tag :unit
    test "initializes with correct default values", %{worker: worker} do
      assert worker.worker_id != nil
      assert worker.current_session == nil
      assert worker.request_id == 0
      assert worker.pending_requests == %{}
      assert worker.health_status == :ready
      assert is_map(worker.stats)
      assert worker.stats.requests_handled == 0
      assert worker.stats.errors == 0
    end
  end

  describe "checkout behavior simulation" do
    setup do
      worker = PoolWorkerHelpers.mock_worker_state()
      {:ok, worker: worker}
    end

    @tag :unit
    test "session checkout binds to session", %{worker: worker} do
      checkout_type = {:session, "user_123"}
      from = {self(), make_ref()}

      {:ok, _, updated_state, _} =
        PoolWorkerHelpers.simulate_checkout(
          checkout_type,
          from,
          worker,
          %{}
        )

      assert updated_state.current_session == "user_123"
      assert updated_state.stats.checkouts == 1
    end

    @tag :unit
    test "anonymous checkout doesn't bind session", %{worker: worker} do
      checkout_type = :anonymous
      from = {self(), make_ref()}

      {:ok, _, updated_state, _} =
        PoolWorkerHelpers.simulate_checkout(
          checkout_type,
          from,
          worker,
          %{}
        )

      assert updated_state.current_session == nil
      assert updated_state.stats.checkouts == 1
    end

    @tag :unit
    test "invalid checkout type returns error" do
      worker = PoolWorkerHelpers.mock_worker_state()

      assert {:error, {:invalid_checkout_type, :invalid}} =
               PoolWorkerHelpers.simulate_checkout(:invalid, {self(), make_ref()}, worker, %{})
    end
  end

  describe "checkin behavior simulation" do
    setup do
      worker =
        PoolWorkerHelpers.mock_worker_state(
          current_session: "test_session",
          stats: PoolWorkerHelpers.init_stats()
        )

      {:ok, worker: worker}
    end

    @tag :unit
    test "successful checkin updates stats", %{worker: worker} do
      {:ok, updated_state, _} =
        PoolWorkerHelpers.simulate_checkin(
          :ok,
          {self(), make_ref()},
          worker,
          %{}
        )

      assert updated_state.stats.requests_handled == 1
      # Session maintained
      assert updated_state.current_session == "test_session"
    end

    @tag :unit
    test "error checkin increments error count", %{worker: worker} do
      {:ok, updated_state, _} =
        PoolWorkerHelpers.simulate_checkin(
          {:error, :command_failed},
          {self(), make_ref()},
          worker,
          %{}
        )

      assert updated_state.stats.errors == 1
    end

    @tag :unit
    test "session cleanup clears session", %{worker: worker} do
      {:ok, updated_state, _} =
        PoolWorkerHelpers.simulate_checkin(
          :session_cleanup,
          {self(), make_ref()},
          worker,
          %{}
        )

      assert updated_state.current_session == nil
    end

    @tag :unit
    test "close checkin removes worker", %{worker: worker} do
      assert {:remove, :closed, %{}} =
               PoolWorkerHelpers.simulate_checkin(
                 :close,
                 {self(), make_ref()},
                 worker,
                 %{}
               )
    end
  end

  describe "stats tracking" do
    @tag :unit
    test "tracks multiple checkouts" do
      worker = PoolWorkerHelpers.mock_worker_state()

      # First checkout
      {:ok, _, worker, _} =
        PoolWorkerHelpers.simulate_checkout(
          {:session, "user_1"},
          {self(), make_ref()},
          worker,
          %{}
        )

      # Second checkout (after checkin)
      {:ok, worker, _} =
        PoolWorkerHelpers.simulate_checkin(
          :ok,
          {self(), make_ref()},
          worker,
          %{}
        )

      {:ok, _, worker, _} =
        PoolWorkerHelpers.simulate_checkout(
          {:session, "user_2"},
          {self(), make_ref()},
          worker,
          %{}
        )

      assert worker.stats.checkouts == 2
      assert worker.stats.requests_handled == 1
    end
  end

  describe "session affinity" do
    @tag :unit
    test "maintains session across operations" do
      worker = PoolWorkerHelpers.mock_worker_state()

      # Checkout with session
      {:ok, _, worker, _} =
        PoolWorkerHelpers.simulate_checkout(
          {:session, "persistent_session"},
          {self(), make_ref()},
          worker,
          %{}
        )

      assert worker.current_session == "persistent_session"

      # Checkin doesn't clear session (for affinity)
      {:ok, worker, _} =
        PoolWorkerHelpers.simulate_checkin(
          :ok,
          {self(), make_ref()},
          worker,
          %{}
        )

      # Session should still be bound
      assert worker.current_session == "persistent_session"

      # Only session_cleanup clears it
      {:ok, worker, _} =
        PoolWorkerHelpers.simulate_checkin(
          :session_cleanup,
          {self(), make_ref()},
          worker,
          %{}
        )

      assert worker.current_session == nil
    end
  end
end

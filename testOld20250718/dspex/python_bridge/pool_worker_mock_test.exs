defmodule DSPex.PythonBridge.PoolWorkerMockTest do
  use ExUnit.Case, async: true

  import DSPex.Test.PoolWorkerHelpers

  describe "handle_checkout with mocks" do
    setup do
      worker = mock_worker_state(current_session: nil)
      {:ok, worker: worker}
    end

    @tag :unit
    test "session checkout behavior", %{worker: worker} do
      {:ok, _, updated, _} =
        simulate_checkout({:session, "user_123"}, {self(), make_ref()}, worker, %{})

      assert updated.current_session == "user_123"
      assert updated.stats.checkouts == 1
    end

    @tag :unit
    test "anonymous checkout behavior", %{worker: worker} do
      {:ok, _, updated, _} = simulate_checkout(:anonymous, {self(), make_ref()}, worker, %{})

      assert updated.current_session == nil
      assert updated.stats.checkouts == 1
    end

    @tag :unit
    test "maintains session affinity", %{worker: worker} do
      # First checkout
      {:ok, _, worker, _} =
        simulate_checkout({:session, "user_123"}, {self(), make_ref()}, worker, %{})

      # Checkin
      {:ok, worker, _} = simulate_checkin(:ok, {self(), make_ref()}, worker, %{})

      # Second checkout - session should be maintained
      {:ok, _, updated, _} =
        simulate_checkout({:session, "user_123"}, {self(), make_ref()}, worker, %{})

      assert updated.current_session == "user_123"
      assert updated.stats.checkouts == 2
    end
  end

  describe "handle_checkin with mocks" do
    setup do
      worker =
        mock_worker_state(
          current_session: "active_session",
          stats: init_stats()
        )

      {:ok, worker: worker}
    end

    @tag :unit
    test "successful checkin", %{worker: worker} do
      {:ok, updated, _} = simulate_checkin(:ok, {self(), make_ref()}, worker, %{})

      assert updated.stats.requests_handled == 1
      assert updated.current_session == "active_session"
    end

    @tag :unit
    test "error checkin", %{worker: worker} do
      {:ok, updated, _} =
        simulate_checkin({:error, :command_failed}, {self(), make_ref()}, worker, %{})

      assert updated.stats.errors == 1
    end
  end

  describe "checkin stats behavior" do
    @tag :unit
    test "stats are properly updated on checkin" do
      worker = mock_worker_state()

      # Test successful operation through simulate_checkin
      {:ok, updated, _} = simulate_checkin(:ok, {self(), make_ref()}, worker, %{})
      assert updated.stats.requests_handled == 1

      # Test error operation
      {:ok, updated, _} = simulate_checkin({:error, :test}, {self(), make_ref()}, updated, %{})
      assert updated.stats.errors == 1
    end
  end
end

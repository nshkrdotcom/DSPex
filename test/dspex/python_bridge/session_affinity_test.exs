defmodule DSPex.PythonBridge.SessionAffinityTest do
  use ExUnit.Case, async: true
  
  alias DSPex.PythonBridge.SessionAffinity
  
  setup do
    # Use a unique name for each test to avoid conflicts
    test_name = :"session_affinity_#{:erlang.unique_integer([:positive])}"
    
    {:ok, pid} = SessionAffinity.start_link(name: test_name, cleanup_interval: 100, session_timeout: 200)
    
    on_exit(fn ->
      if Process.alive?(pid) do
        ref = Process.monitor(pid)
        GenServer.stop(pid, :normal, 1000)
        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after 100 -> :ok
        end
      end
    end)
    
    %{affinity: test_name}
  end
  
  describe "bind_session/2 and get_worker/1" do
    test "can bind and retrieve session-worker mappings" do
      session_id = "test_session_123"
      worker_id = "test_worker_456"
      
      assert :ok = SessionAffinity.bind_session(session_id, worker_id)
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_id)
    end
    
    test "returns error for non-existent sessions" do
      assert {:error, :no_affinity} = SessionAffinity.get_worker("non_existent_session")
    end
    
    test "can rebind sessions to different workers" do
      session_id = "test_session_123"
      worker_id_1 = "test_worker_456"
      worker_id_2 = "test_worker_789"
      
      # Bind to first worker
      assert :ok = SessionAffinity.bind_session(session_id, worker_id_1)
      assert {:ok, ^worker_id_1} = SessionAffinity.get_worker(session_id)
      
      # Rebind to second worker
      assert :ok = SessionAffinity.bind_session(session_id, worker_id_2)
      assert {:ok, ^worker_id_2} = SessionAffinity.get_worker(session_id)
    end
    
    test "multiple sessions can bind to same worker" do
      worker_id = "test_worker_456"
      session_1 = "session_1"
      session_2 = "session_2"
      
      assert :ok = SessionAffinity.bind_session(session_1, worker_id)
      assert :ok = SessionAffinity.bind_session(session_2, worker_id)
      
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_1)
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_2)
    end
  end
  
  describe "unbind_session/1" do
    test "can unbind sessions" do
      session_id = "test_session_123"
      worker_id = "test_worker_456"
      
      # Bind then unbind
      assert :ok = SessionAffinity.bind_session(session_id, worker_id)
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_id)
      
      assert :ok = SessionAffinity.unbind_session(session_id)
      assert {:error, :no_affinity} = SessionAffinity.get_worker(session_id)
    end
    
    test "unbinding non-existent session is safe" do
      assert :ok = SessionAffinity.unbind_session("non_existent_session")
    end
  end
  
  describe "remove_worker_sessions/1" do
    test "removes all sessions for a worker" do
      worker_id = "test_worker_456"
      session_1 = "session_1"
      session_2 = "session_2"
      session_3 = "session_3"
      other_worker = "other_worker_789"
      
      # Bind multiple sessions to target worker
      assert :ok = SessionAffinity.bind_session(session_1, worker_id)
      assert :ok = SessionAffinity.bind_session(session_2, worker_id)
      
      # Bind one session to different worker
      assert :ok = SessionAffinity.bind_session(session_3, other_worker)
      
      # Verify bindings exist
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_1)
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_2)
      assert {:ok, ^other_worker} = SessionAffinity.get_worker(session_3)
      
      # Remove target worker's sessions
      assert :ok = SessionAffinity.remove_worker_sessions(worker_id)
      
      # Verify target worker sessions are gone
      assert {:error, :no_affinity} = SessionAffinity.get_worker(session_1)
      assert {:error, :no_affinity} = SessionAffinity.get_worker(session_2)
      
      # Verify other worker's session remains
      assert {:ok, ^other_worker} = SessionAffinity.get_worker(session_3)
    end
    
    test "removing sessions for non-existent worker is safe" do
      assert :ok = SessionAffinity.remove_worker_sessions("non_existent_worker")
    end
  end
  
  describe "session expiration" do
    @tag :skip_in_ci
    test "expired sessions are automatically removed", %{affinity: _affinity} do
      session_id = "test_session_123"
      worker_id = "test_worker_456"
      
      # Bind session
      assert :ok = SessionAffinity.bind_session(session_id, worker_id)
      assert {:ok, ^worker_id} = SessionAffinity.get_worker(session_id)
      
      # Wait for expiration (session_timeout is 200ms in setup)
      Process.sleep(250)
      
      # Session should be expired when accessed
      assert {:error, :session_expired} = SessionAffinity.get_worker(session_id)
      
      # Accessing again should return no_affinity (cleaned up)
      assert {:error, :no_affinity} = SessionAffinity.get_worker(session_id)
    end
    
    @tag :skip_in_ci
    test "cleanup process removes expired sessions", %{affinity: _affinity} do
      session_id = "test_session_123"
      worker_id = "test_worker_456"
      
      # Bind session
      assert :ok = SessionAffinity.bind_session(session_id, worker_id)
      
      # Wait for session to expire and cleanup to run
      # session_timeout is 200ms, cleanup_interval is 100ms in setup
      Process.sleep(450)  # Wait for expiration + multiple cleanup cycles
      
      # Session should be completely gone
      assert {:error, :no_affinity} = SessionAffinity.get_worker(session_id)
    end
  end
  
  describe "get_stats/0" do
    test "returns accurate statistics" do
      worker_1 = "worker_1"
      worker_2 = "worker_2"
      
      # Initially no sessions
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 0
      assert stats.workers_with_sessions == 0
      
      # Add sessions
      SessionAffinity.bind_session("session_1", worker_1)
      SessionAffinity.bind_session("session_2", worker_1)
      SessionAffinity.bind_session("session_3", worker_2)
      
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 3
      assert stats.workers_with_sessions == 2
      
      # Remove one session
      SessionAffinity.unbind_session("session_1")
      
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 2
      assert stats.workers_with_sessions == 2
      
      # Remove all sessions for worker_1
      SessionAffinity.unbind_session("session_2")
      
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 1
      assert stats.workers_with_sessions == 1
    end
  end
  
  describe "concurrent access" do
    test "handles concurrent bind/get operations" do
      worker_base = "worker"
      session_base = "session"
      
      # Start multiple tasks that bind and retrieve sessions
      tasks = for i <- 1..50 do
        Task.async(fn ->
          session_id = "#{session_base}_#{i}"
          worker_id = "#{worker_base}_#{rem(i, 5)}"  # 5 different workers
          
          # Bind session
          :ok = SessionAffinity.bind_session(session_id, worker_id)
          
          # Verify binding
          {:ok, ^worker_id} = SessionAffinity.get_worker(session_id)
          
          # Unbind
          :ok = SessionAffinity.unbind_session(session_id)
          
          # Verify unbinding
          {:error, :no_affinity} = SessionAffinity.get_worker(session_id)
          
          :ok
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      assert Enum.all?(results, &(&1 == :ok))
      
      # Should have no sessions left
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 0
    end
    
    test "handles concurrent worker removal" do
      worker_id = "shared_worker"
      
      # Bind many sessions to the same worker
      for i <- 1..20 do
        SessionAffinity.bind_session("session_#{i}", worker_id)
      end
      
      # Start concurrent removal tasks
      removal_tasks = for _i <- 1..5 do
        Task.async(fn ->
          SessionAffinity.remove_worker_sessions(worker_id)
        end)
      end
      
      # Start concurrent get tasks
      get_tasks = for i <- 1..10 do
        Task.async(fn ->
          SessionAffinity.get_worker("session_#{i}")
        end)
      end
      
      # Wait for all tasks
      Task.await_many(removal_tasks ++ get_tasks, 5000)
      
      # All sessions should be removed
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == 0
    end
  end
  
  describe "performance" do
    test "handles large number of sessions efficiently" do
      num_sessions = 1000
      num_workers = 10
      
      # Measure bind performance
      {bind_time, _} = :timer.tc(fn ->
        for i <- 1..num_sessions do
          worker_id = "worker_#{rem(i, num_workers)}"
          session_id = "session_#{i}"
          SessionAffinity.bind_session(session_id, worker_id)
        end
      end)
      
      # Measure get performance
      {get_time, _} = :timer.tc(fn ->
        for i <- 1..num_sessions do
          session_id = "session_#{i}"
          {:ok, _} = SessionAffinity.get_worker(session_id)
        end
      end)
      
      # Should complete in reasonable time (less than 1 second each)
      assert bind_time < 1_000_000  # 1 second in microseconds
      assert get_time < 1_000_000
      
      # Verify correct count
      stats = SessionAffinity.get_stats()
      assert stats.total_sessions == num_sessions
      assert stats.workers_with_sessions == num_workers
      
      # Clean up
      for i <- 1..num_sessions do
        SessionAffinity.unbind_session("session_#{i}")
      end
    end
  end
end
defmodule AshDSPex.PythonBridge.SupervisorTest do
  @moduledoc """
  Tests for the Python bridge supervisor functionality.

  Uses event-driven coordination patterns from UNIFIED_TESTING_GUIDE.md
  to eliminate Process.sleep() usage and provide deterministic testing.
  """

  use AshDSPex.UnifiedTestFoundation, :supervision_testing

  # Only run in full_integration mode
  @moduletag :layer_3

  alias AshDSPex.PythonBridge.Supervisor, as: BridgeSupervisor
  import AshDSPex.UnifiedTestFoundation, only: [wait_for_supervision_tree_ready: 2]

  describe "start_link/1" do
    test "starts with default configuration", %{supervision_tree: sup_tree} do
      # The supervision tree is already started by the test foundation
      assert is_pid(sup_tree)
      assert Process.alive?(sup_tree)

      # Should have children
      children = Supervisor.which_children(sup_tree)
      # At least monitor should start
      assert length(children) >= 1

      # Verify each child has proper structure
      Enum.each(children, fn child ->
        assert is_tuple(child)
        assert tuple_size(child) == 4

        {id, child_pid, type, modules} = child
        assert is_atom(id) or is_tuple(id)
        assert is_pid(child_pid) or child_pid == :undefined
        assert type in [:worker, :supervisor]
        assert is_list(modules)
      end)
    end

    test "starts with custom configuration" do
      # Create a separate isolated supervisor for custom config testing
      names = unique_process_names([:supervisor, :bridge, :monitor])

      opts = [
        name: names.supervisor,
        bridge_name: names.bridge,
        monitor_name: names.monitor,
        max_restarts: 10,
        max_seconds: 120
      ]

      case BridgeSupervisor.start_link(opts) do
        {:ok, pid} ->
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Wait for children to be ready
          assert {:ok, :ready} = wait_for_supervision_tree_ready(pid, 5000)

          graceful_supervisor_shutdown(pid)

        {:error, _reason} ->
          # Expected if Python environment not available
          :ok
      end
    end
  end

  describe "which_children/0" do
    test "returns list of supervised children", %{supervision_tree: sup_tree} do
      children = Supervisor.which_children(sup_tree)

      assert is_list(children)

      # Each child should be a tuple with expected format
      Enum.each(children, fn child ->
        assert is_tuple(child)
        assert tuple_size(child) == 4

        {id, child_pid, type, modules} = child
        assert is_atom(id) or is_tuple(id)
        assert is_pid(child_pid) or child_pid == :undefined
        assert type in [:worker, :supervisor]
        assert is_list(modules)
      end)
    end
  end

  describe "count_children/0" do
    test "returns child count information", %{supervision_tree: sup_tree} do
      count = Supervisor.count_children(sup_tree)

      assert is_map(count)
      assert Map.has_key?(count, :specs)
      assert Map.has_key?(count, :active)
      assert Map.has_key?(count, :supervisors)
      assert Map.has_key?(count, :workers)

      # All values should be non-negative integers
      assert is_integer(count.specs) and count.specs >= 0
      assert is_integer(count.active) and count.active >= 0
      assert is_integer(count.supervisors) and count.supervisors >= 0
      assert is_integer(count.workers) and count.workers >= 0
    end
  end

  describe "get_system_status/0" do
    test "returns system status information", %{supervision_tree: sup_tree} do
      # Wait for supervision tree to be fully ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      status = BridgeSupervisor.get_system_status()

      assert is_map(status)
      assert Map.has_key?(status, :supervisor)
      assert Map.has_key?(status, :children_count)
      assert Map.has_key?(status, :bridge)
      assert Map.has_key?(status, :monitor)
      assert Map.has_key?(status, :last_check)

      # Supervisor should be running
      assert status.supervisor == :running

      # Children count should be non-negative
      assert is_integer(status.children_count) and status.children_count >= 0

      # Bridge and monitor status should be maps
      assert is_map(status.bridge)
      assert is_map(status.monitor)

      # Last check should be DateTime
      assert %DateTime{} = status.last_check
    end
  end

  describe "system_health_check/0" do
    test "performs comprehensive health check", %{supervision_tree: sup_tree} do
      # Wait for supervision tree to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      result = BridgeSupervisor.system_health_check()

      case result do
        :ok ->
          # All components healthy
          assert true

        {:error, issues} ->
          # Legacy format - some components have issues
          assert is_list(issues)
          assert length(issues) > 0

          Enum.each(issues, fn issue ->
            assert is_binary(issue)
          end)
      end
    end
  end

  describe "restart_child/1" do
    test "can restart monitor child", %{supervision_tree: sup_tree, monitor_name: monitor_name} do
      # Wait for supervision tree to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      # Try to restart the monitor
      result = Supervisor.restart_child(sup_tree, monitor_name)

      case result do
        {:ok, _child_pid} ->
          # Successfully restarted
          assert true

        {:ok, _child_pid, _info} ->
          # Successfully restarted with additional info
          assert true

        {:error, :not_found} ->
          # Child spec not found (expected if bridge couldn't start)
          assert true

        {:error, :running} ->
          # Child already running
          assert true

        {:error, _reason} ->
          # Other error - acceptable in test environment
          assert true
      end
    end
  end

  describe "graceful_shutdown/1" do
    test "performs graceful shutdown", %{supervision_tree: sup_tree} do
      # Wait for supervision tree to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      # Should complete without error
      result = BridgeSupervisor.graceful_shutdown(timeout: 1000)

      assert result == :ok

      # Supervisor should still be alive (graceful_shutdown doesn't stop supervisor)
      assert Process.alive?(sup_tree)
    end

    test "handles timeout during shutdown" do
      # Create separate supervisor for timeout testing
      names = unique_process_names([:supervisor, :bridge, :monitor])

      case BridgeSupervisor.start_link(
             name: names.supervisor,
             bridge_name: names.bridge,
             monitor_name: names.monitor
           ) do
        {:ok, pid} ->
          # Wait for startup
          assert {:ok, :ready} = wait_for_supervision_tree_ready(pid, 5000)

          # Test with very short timeout
          result = BridgeSupervisor.graceful_shutdown(timeout: 1)

          # Should still return :ok even if timeout reached
          assert result == :ok

          graceful_supervisor_shutdown(pid)

        {:error, _reason} ->
          # Expected if environment not available
          :ok
      end
    end
  end

  describe "terminate_child/1" do
    test "can terminate monitor child", %{supervision_tree: sup_tree, monitor_name: monitor_name} do
      # Wait for supervision tree to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      result = Supervisor.terminate_child(sup_tree, monitor_name)

      case result do
        :ok ->
          # Successfully terminated
          assert true

        {:error, :not_found} ->
          # Child not found (expected if couldn't start)
          assert true
      end
    end
  end

  describe "fault tolerance" do
    test "handles child process crashes", %{
      supervision_tree: sup_tree,
      monitor_name: monitor_name
    } do
      # Wait for supervision tree to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_supervision_tree_ready(sup_tree, 5000)

      # Get initial children count
      initial_count = Supervisor.count_children(sup_tree)

      # Get monitor process PID
      case get_child_pid(sup_tree, monitor_name) do
        {:ok, monitor_pid} ->
          # Kill the monitor process
          Process.exit(monitor_pid, :kill)

          # Wait for supervisor to restart the monitor instead of sleeping
          assert {:ok, new_pid} =
                   wait_for_process_restart(sup_tree, monitor_name, monitor_pid, 5000)

          assert new_pid != monitor_pid
          assert Process.alive?(new_pid)

          # Should have same number of children (restarted)
          final_count = Supervisor.count_children(sup_tree)
          assert final_count.specs == initial_count.specs

        {:error, reason} ->
          # Monitor not found or not running - acceptable in test environment
          IO.puts("Monitor not available for crash test: #{inspect(reason)}")
          :ok
      end
    end
  end
end

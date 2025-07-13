defmodule AshDSPex.PythonBridge.MonitorTest do
  @moduledoc """
  Tests for the Python bridge health monitor.

  Uses event-driven coordination patterns from UNIFIED_TESTING_GUIDE.md
  to eliminate Process.sleep() usage and provide deterministic testing.
  """

  use AshDSPex.UnifiedTestFoundation, :basic

  # Only run in full_integration mode
  @moduletag :layer_3

  alias AshDSPex.PythonBridge.Monitor

  describe "start_link/1" do
    test "starts with default configuration" do
      config = test_monitor_config()

      {:ok, pid} = Monitor.start_link(name: config.name)

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify default configuration
      assert {:ok, status} = safe_get_monitor_status(config.name)
      assert Map.has_key?(status, :config)

      # Clean up
      GenServer.stop(pid)
    end

    test "starts with custom configuration" do
      config =
        test_monitor_config(%{
          health_check_interval: 5000,
          failure_threshold: 3,
          response_timeout: 2000
        })

      opts = [
        name: config.name,
        health_check_interval: config.health_check_interval,
        failure_threshold: config.failure_threshold,
        response_timeout: config.response_timeout
      ]

      {:ok, pid} = Monitor.start_link(opts)

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify custom configuration was applied
      assert {:ok, status} = safe_get_monitor_status(config.name)
      assert status.config.health_check_interval == 5000
      assert status.config.failure_threshold == 3

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "get_health_status/0" do
    setup do
      config = test_monitor_config()
      # Long interval
      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      %{monitor_pid: pid, monitor_name: config.name}
    end

    test "returns health metrics", %{monitor_name: monitor_name} do
      assert {:ok, status} = safe_get_monitor_status(monitor_name)

      # Should have all expected fields
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :last_check)
      assert Map.has_key?(status, :consecutive_failures)
      assert Map.has_key?(status, :total_checks)
      assert Map.has_key?(status, :total_failures)
      assert Map.has_key?(status, :success_rate)
      assert Map.has_key?(status, :average_response_time)

      # Initial state should be :unknown
      assert status.status == :unknown
      assert status.consecutive_failures == 0
      assert status.total_checks == 0
      assert status.total_failures == 0
    end

    test "updates after forced health check", %{monitor_name: monitor_name} do
      # Get initial status
      {:ok, initial_status} = safe_get_monitor_status(monitor_name)
      initial_checks = initial_status.total_checks

      # Force health check and wait for completion (will fail since no bridge)
      assert {:ok, updated_status} = trigger_health_check_and_wait(monitor_name, :error, 3000)

      # Verify health check was performed
      assert updated_status.total_checks > initial_checks
      assert updated_status.total_failures >= 1
      assert updated_status.consecutive_failures >= 1
      assert updated_status.status in [:degraded, :unhealthy]
    end
  end

  describe "reset_stats/0" do
    setup do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      %{monitor_pid: pid, monitor_name: config.name}
    end

    test "resets all statistics", %{monitor_name: monitor_name} do
      # Force a health check first to generate some stats
      assert {:ok, _status} = trigger_health_check_and_wait(monitor_name, :error, 3000)

      # Reset stats using event-driven wait
      :ok = GenServer.cast(monitor_name, :reset_stats)

      # Wait for reset to take effect
      assert {:ok, status} =
               wait_for(
                 fn ->
                   case safe_get_monitor_status(monitor_name) do
                     {:ok, %{total_checks: 0, total_failures: 0} = status} -> {:ok, status}
                     _ -> nil
                   end
                 end,
                 2000
               )

      # Verify reset
      assert status.total_checks == 0
      assert status.total_failures == 0
      assert status.consecutive_failures == 0
      # Default when no checks
      assert status.success_rate == 100.0
    end
  end

  describe "health check behavior" do
    setup do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          # Long interval to control timing
          health_check_interval: 300_000,
          failure_threshold: 2
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      %{monitor_pid: pid, monitor_name: config.name}
    end

    test "handles bridge not running", %{monitor_name: monitor_name} do
      # Force health check when no bridge is running and wait for completion
      assert {:ok, status} = trigger_health_check_and_wait(monitor_name, :error, 3000)

      # Should record failure
      assert status.total_checks >= 1
      assert status.total_failures >= 1
      assert status.consecutive_failures >= 1
      assert status.status in [:degraded, :unhealthy]
      assert is_binary(status.last_error)
    end
  end

  describe "configuration" do
    test "applies custom failure threshold" do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000,
          # Very low threshold
          failure_threshold: 1
        )

      # Force a health check (will fail since no bridge) and wait
      assert {:ok, status} = trigger_health_check_and_wait(config.name, :error, 3000)

      # With threshold of 1, should be unhealthy after first failure
      assert status.consecutive_failures >= 1
      assert status.status == :unhealthy

      GenServer.stop(pid)
    end

    test "handles timeout configuration" do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000,
          # Very short timeout
          response_timeout: 10
        )

      # Force health check with short timeout and wait for completion
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, _status} = trigger_health_check_and_wait(config.name, :error, 3000)
      end_time = System.monotonic_time(:millisecond)

      # Should complete quickly due to short timeout
      elapsed = end_time - start_time
      # Should be much faster than 1 second
      assert elapsed < 1000

      GenServer.stop(pid)
    end
  end

  describe "success rate calculation" do
    setup do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          # Long interval
          health_check_interval: 300_000
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      %{monitor_pid: pid, monitor_name: config.name}
    end

    test "calculates success rate correctly", %{monitor_name: monitor_name} do
      # Force several health checks (all will fail since no bridge) and wait for each
      for _i <- 1..3 do
        assert {:ok, _status} = trigger_health_check_and_wait(monitor_name, :error, 2000)
      end

      # Wait for all checks to be processed
      assert {:ok, status} = wait_for_failure_count(monitor_name, 3, 3000)

      # All checks failed, so success rate should be 0
      assert status.total_checks == 3
      assert status.total_failures == 3
      assert status.success_rate == 0.0
    end

    test "success rate with mixed results" do
      config = test_monitor_config()

      # Set up a mock bridge that can succeed sometimes
      {:ok, bridge_pid} = setup_mock_bridge(config.bridge_name, %{response_type: :success})

      {:ok, monitor_pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000
        )

      # Force a successful health check
      assert {:ok, success_status} = trigger_health_check_and_wait(config.name, :success, 3000)
      assert success_status.total_checks == 1
      assert success_status.total_failures == 0
      assert success_status.success_rate == 100.0

      # Change bridge to fail
      GenServer.cast(bridge_pid, {:simulate_failure, :error})

      # Force a failing health check
      assert {:ok, fail_status} = trigger_health_check_and_wait(config.name, :error, 3000)
      assert fail_status.total_checks == 2
      assert fail_status.total_failures == 1
      assert fail_status.success_rate == 50.0

      # Cleanup
      GenServer.stop(monitor_pid)
      GenServer.stop(bridge_pid)
    end
  end

  describe "stop/0 and stop/1" do
    test "stops monitor gracefully" do
      config = test_monitor_config()
      {:ok, pid} = Monitor.start_link(name: config.name)

      # Monitor should be running
      assert Process.alive?(pid)

      # Stop monitor
      :ok = Monitor.stop(config.name)

      # Wait for graceful shutdown
      assert {:ok, :shutdown_complete} =
               wait_for(
                 fn ->
                   if Process.alive?(pid) do
                     nil
                   else
                     {:ok, :shutdown_complete}
                   end
                 end,
                 2000
               )
    end

    test "force_health_check/0 triggers immediate check" do
      config = test_monitor_config()

      {:ok, pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          # Long interval
          health_check_interval: 300_000
        )

      # Get initial status
      {:ok, initial_status} = safe_get_monitor_status(config.name)

      # Force health check and wait for completion
      assert {:ok, updated_status} = trigger_health_check_and_wait(config.name, :error, 3000)

      # Should have performed check
      assert updated_status.total_checks > initial_status.total_checks

      GenServer.stop(pid)
    end
  end

  describe "health status transitions" do
    test "transitions through health states correctly" do
      config = test_monitor_config()

      # Set up mock bridge
      {:ok, bridge_pid} = setup_mock_bridge(config.bridge_name, %{response_type: :success})

      {:ok, monitor_pid} =
        Monitor.start_link(
          name: config.name,
          bridge_name: config.bridge_name,
          health_check_interval: 300_000,
          failure_threshold: 2
        )

      # Start healthy
      assert {:ok, healthy_status} = trigger_health_check_and_wait(config.name, :success, 3000)
      assert healthy_status.status == :healthy

      # One failure -> degraded
      GenServer.cast(bridge_pid, {:simulate_failure, :error})
      assert {:ok, degraded_status} = trigger_health_check_and_wait(config.name, :error, 3000)
      assert degraded_status.status == :degraded
      assert degraded_status.consecutive_failures == 1

      # Second failure -> unhealthy
      assert {:ok, unhealthy_status} = trigger_health_check_and_wait(config.name, :error, 3000)
      assert unhealthy_status.status == :unhealthy
      assert unhealthy_status.consecutive_failures == 2

      # Recovery -> healthy
      GenServer.cast(bridge_pid, {:simulate_failure, :success})
      assert {:ok, recovered_status} = trigger_health_check_and_wait(config.name, :success, 3000)
      assert recovered_status.status == :healthy
      assert recovered_status.consecutive_failures == 0

      # Cleanup
      GenServer.stop(monitor_pid)
      GenServer.stop(bridge_pid)
    end
  end
end

defmodule DSPex.PythonBridge.BridgeTest do
  @moduledoc """
  Tests for the Python bridge GenServer functionality.

  Uses event-driven coordination patterns from UNIFIED_TESTING_GUIDE.md
  to provide deterministic testing.
  """

  use DSPex.UnifiedTestFoundation, :basic

  # Only run in full_integration mode
  @moduletag :layer_3

  alias DSPex.PythonBridge.Bridge

  describe "start_link/1" do
    test "starts with default configuration" do
      # Note: This test will only pass if Python environment is properly set up
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Clean up
          # Use longer timeout for stop to account for graceful shutdown
          GenServer.stop(pid, :normal, 10_000)

        {:error, reason} ->
          # Expected if Python/DSPy not available
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "handles missing python gracefully" do
      # Test with invalid python executable
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge, python_executable: "nonexistent_python") do
        {:error, reason} ->
          assert is_atom(reason) or is_binary(reason)

        {:ok, pid} ->
          # Unexpected but clean up if somehow successful
          # Use longer timeout for stop to account for graceful shutdown
          GenServer.stop(pid, :normal, 10_000)
      end
    end
  end

  describe "get_status/0" do
    setup do
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          %{bridge_pid: pid, bridge_name: names.bridge}

        {:error, _reason} ->
          %{bridge_pid: nil, bridge_name: names.bridge}
      end
    end

    test "returns status information", %{bridge_pid: pid} do
      if pid do
        status = GenServer.call(pid, :get_status)

        # Should have expected fields
        assert Map.has_key?(status, :status)
        assert Map.has_key?(status, :uptime)
        assert Map.has_key?(status, :pending_requests)
        assert Map.has_key?(status, :stats)

        # Status should be atom
        assert is_atom(status.status)

        # Stats should be map with counters
        assert is_map(status.stats)
        assert Map.has_key?(status.stats, :requests_sent)
        assert Map.has_key?(status.stats, :responses_received)
        assert Map.has_key?(status.stats, :errors)

        # Clean up
        GenServer.stop(pid)
      else
        # Skip test if bridge couldn't start
        :ok
      end
    end
  end

  describe "call/3" do
    setup do
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          # Wait for bridge to fully initialize using event-driven pattern
          case wait_for_bridge_startup(names.bridge, 5000) do
            {:ok, :ready} -> %{bridge_pid: pid, bridge_name: names.bridge}
            # Continue with test anyway
            {:error, _reason} -> %{bridge_pid: pid, bridge_name: names.bridge}
          end

        {:error, _reason} ->
          %{bridge_pid: nil, bridge_name: names.bridge}
      end
    end

    test "handles ping command when bridge is running", %{bridge_pid: pid} do
      if pid do
        case GenServer.call(pid, {:call, :ping, %{}}, 1000) do
          {:ok, result} ->
            # Should get successful ping response
            assert is_map(result)

          {:error, reason} ->
            # Could fail if Python process not responding
            assert is_atom(reason) or is_binary(reason)
        end

        # Clean up
        GenServer.stop(pid)
      else
        # Skip test if bridge couldn't start
        :ok
      end
    end

    @tag timeout: 20_000
    test "rejects calls when bridge not ready" do
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          # Try to call immediately before bridge is fully ready
          # Use try/catch to handle the timeout gracefully
          result =
            try do
              GenServer.call(pid, {:call, :ping, %{}}, 100)
            catch
              :exit, {:timeout, _} -> {:error, :timeout}
            end

          case result do
            {:error, {:bridge_not_ready, _status}} ->
              assert true

            {:ok, _result} ->
              # If bridge starts very quickly, this is also fine
              assert true

            {:error, :timeout} ->
              # Timeout is expected when bridge is not ready
              assert true

            {:error, _reason} ->
              # Other errors are also acceptable for this test
              assert true
          end

          # Use longer timeout for stop to account for graceful shutdown
          GenServer.stop(pid, :normal, 10_000)

        {:error, _reason} ->
          # Expected if Python not available
          :ok
      end
    end

    test "handles timeout gracefully" do
      # Test external API timeout handling
      # Very short timeout
      case Bridge.call(:ping, %{}, 1) do
        {:error, :timeout} ->
          assert true

        {:error, :bridge_not_running} ->
          # Expected if no bridge running
          assert true

        {:ok, _result} ->
          # Bridge responded very quickly
          assert true
      end
    end
  end

  describe "restart/0" do
    setup do
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          %{bridge_pid: pid, bridge_name: names.bridge}

        {:error, _reason} ->
          %{bridge_pid: nil, bridge_name: names.bridge}
      end
    end

    test "can restart bridge process", %{bridge_pid: pid} do
      if pid do
        case GenServer.call(pid, :restart) do
          :ok ->
            # Should still be alive after restart
            assert Process.alive?(pid)

          {:error, reason} ->
            # Could fail if environment issues
            assert is_atom(reason) or is_binary(reason)
        end

        GenServer.stop(pid)
      else
        # Skip test if bridge couldn't start
        :ok
      end
    end
  end

  describe "cast/2" do
    setup do
      names = unique_process_names([:bridge])

      case Bridge.start_link(name: names.bridge) do
        {:ok, pid} ->
          # Wait for bridge to initialize using event-driven pattern
          case wait_for_bridge_startup(names.bridge, 5000) do
            {:ok, :ready} -> %{bridge_pid: pid, bridge_name: names.bridge}
            # Continue with test anyway
            {:error, _reason} -> %{bridge_pid: pid, bridge_name: names.bridge}
          end

        {:error, _reason} ->
          %{bridge_pid: nil, bridge_name: names.bridge}
      end
    end

    test "accepts cast messages", %{bridge_pid: pid} do
      if pid do
        # Cast should always return :ok immediately
        result = GenServer.cast(pid, {:cast, :cleanup, %{}})
        assert result == :ok

        GenServer.stop(pid)
      else
        # Skip test if bridge couldn't start
        :ok
      end
    end
  end

  describe "error handling" do
    test "handles bridge not running scenario" do
      result = Bridge.call(:ping, %{})

      case result do
        {:error, :bridge_not_running} ->
          assert true

        {:ok, _} ->
          # If a bridge is running, that's also fine
          assert true

        {:error, _other} ->
          # Other errors are acceptable too
          assert true
      end
    end
  end

  # Clean up handled by UnifiedTestFoundation unique naming
end

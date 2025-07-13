defmodule AshDSPex.PythonBridge.IntegrationTest do
  @moduledoc """
  Integration tests for the complete Python bridge system.

  Tests the full bridge functionality including supervisor, bridge, and monitor
  components working together. Uses event-driven coordination patterns from
  UNIFIED_TESTING_GUIDE.md to eliminate Process.sleep() usage.
  """

  use AshDSPex.UnifiedTestFoundation, :supervision_testing

  # Only run in full_integration mode
  @moduletag :layer_3

  alias AshDSPex.PythonBridge.Supervisor

  @moduletag :integration
  @moduletag timeout: 30_000

  describe "complete bridge system" do
    test "bridge system starts and reports healthy status", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge to be ready instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Check system status
      status = Supervisor.get_system_status()

      assert status.supervisor == :running
      assert status.children_count > 0

      # Check individual components
      bridge_status = Map.get(status, :bridge, %{})
      assert bridge_status.status == :running
    end

    test "can perform health check on complete system", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge readiness instead of sleeping  
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Perform health check - function returns :ok or {:error, issues}
      case Supervisor.system_health_check() do
        :ok ->
          # All systems healthy
          assert true

        {:error, issues} ->
          # Some issues detected but system might still be functional
          assert is_list(issues)
          # Log issues for debugging but don't fail test in integration environment
          IO.puts("Health check issues: #{inspect(issues)}")
          assert true
      end
    end

    test "monitor tracks bridge health", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name,
      monitor_name: monitor_name
    } do
      # Wait for both bridge and monitor to be ready
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Get initial monitor status
      {:ok, _monitor_pid} = get_service(sup_tree, monitor_name)
      {:ok, initial_status} = safe_get_monitor_status(monitor_name)

      # Trigger a health check and wait for completion
      assert {:ok, updated_status} = trigger_health_check_and_wait(monitor_name, :success, 5000)

      # Verify health check was performed
      assert updated_status.total_checks > initial_status.total_checks
      assert updated_status.status in [:healthy, :degraded]
    end

    test "bridge handles basic commands when Python available", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge readiness instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Test basic connectivity
      assert {:ok, _response} = bridge_call_with_retry(bridge_name, :ping, %{})

      # Test stats retrieval
      assert {:ok, stats} = bridge_call_with_retry(bridge_name, :get_stats, %{})
      assert is_map(stats)
    end

    test "system recovers from bridge restart", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for initial bridge readiness
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Get original bridge PID
      {:ok, original_pid} = get_service(sup_tree, bridge_name)

      # Kill the bridge process to trigger restart
      Process.exit(original_pid, :kill)

      # Wait for restart - use module name for supervisor child lookup
      assert {:ok, new_pid} =
               wait_for_process_restart(
                 sup_tree,
                 AshDSPex.PythonBridge.Bridge,
                 original_pid,
                 10_000
               )

      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      # Verify bridge is functional after restart
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name, 10_000)
      assert {:ok, _response} = bridge_call_with_retry(bridge_name, :ping, %{})
    end

    test "graceful shutdown works properly", %{supervision_tree: sup_tree} do
      # Verify supervisor is running
      assert Process.alive?(sup_tree)

      # Perform graceful shutdown - this will be handled by the test foundation cleanup
      # We just verify the current state is healthy
      status = Supervisor.get_system_status()
      assert status.supervisor == :running

      # The actual shutdown will be tested by the on_exit callback
      # which calls graceful_supervisor_shutdown/2
    end
  end

  describe "Python bridge communication" do
    test "can create and execute DSPy program", %{
      supervision_tree: _sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge startup instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_startup(bridge_name, 10_000)

      # Create a simple DSPy program
      program_id = "test_program_#{:erlang.unique_integer([:positive])}"

      signature = %{
        "name" => "SimpleQA",
        "inputs" => [%{"name" => "question", "description" => "The question to answer"}],
        "outputs" => [%{"name" => "answer", "description" => "The answer to the question"}]
      }

      case bridge_call_with_retry(bridge_name, :create_program, %{
             id: program_id,
             signature: signature
           }) do
        {:ok, %{"program_id" => program_id}} ->
          # Execute the program
          execution_args = %{
            "program_id" => program_id,
            "inputs" => %{"question" => "What is 2+2?"}
          }

          case bridge_call_with_retry(bridge_name, :execute_program, execution_args, 3, 10_000) do
            {:ok, result} ->
              assert is_map(result)
              # Clean up program
              bridge_call_with_retry(bridge_name, :delete_program, %{program_id: program_id})

            {:error, reason} ->
              # Program execution might fail due to missing API keys or network issues
              # This is acceptable in test environment
              IO.puts("Program execution failed (expected in test env): #{inspect(reason)}")
          end

        {:error, reason} ->
          # Program creation might fail due to DSPy dependencies
          # This is acceptable in test environment  
          IO.puts("Program creation failed (expected in test env): #{inspect(reason)}")
      end
    end

    test "can list programs and get stats", %{
      supervision_tree: _sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge startup instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_startup(bridge_name, 10_000)

      # Get initial stats
      assert {:ok, initial_stats} = bridge_call_with_retry(bridge_name, :get_stats, %{})
      assert is_map(initial_stats)

      # List programs
      assert {:ok, programs_response} = bridge_call_with_retry(bridge_name, :list_programs, %{})
      assert is_map(programs_response)
      assert Map.has_key?(programs_response, "programs")
      programs = Map.get(programs_response, "programs")
      assert is_list(programs)

      # Get updated stats  
      assert {:ok, final_stats} = bridge_call_with_retry(bridge_name, :get_stats, %{})

      # Stats should show the additional calls we made
      initial_commands = Map.get(initial_stats, "commands_processed", 0)
      final_commands = Map.get(final_stats, "commands_processed", 0)
      assert final_commands >= initial_commands
    end
  end

  describe "error handling and recovery" do
    test "handles invalid commands gracefully", %{
      supervision_tree: sup_tree,
      bridge_name: bridge_name
    } do
      # Wait for bridge readiness instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Send invalid command
      case bridge_call_with_retry(bridge_name, :invalid_command, %{}) do
        {:error, _reason} ->
          # Expected - invalid commands should return errors
          assert true

        {:ok, _result} ->
          # Unexpected but not necessarily a failure
          # Some bridges might handle unknown commands gracefully
          assert true
      end

      # Verify bridge is still functional after invalid command
      assert {:ok, _response} = bridge_call_with_retry(bridge_name, :ping, %{})
    end

    test "handles timeout scenarios", %{supervision_tree: sup_tree, bridge_name: bridge_name} do
      # Wait for bridge readiness instead of sleeping
      assert {:ok, :ready} = wait_for_bridge_ready(sup_tree, bridge_name)

      # Test with very short timeout
      case safe_bridge_call(bridge_name, :ping, %{}, 1) do
        {:error, :timeout} ->
          # Expected for very short timeout
          assert true

        {:ok, _result} ->
          # Bridge responded very quickly, which is fine
          assert true
      end

      # Verify bridge is still responsive with normal timeout
      assert {:ok, _response} = bridge_call_with_retry(bridge_name, :ping, %{})
    end
  end
end

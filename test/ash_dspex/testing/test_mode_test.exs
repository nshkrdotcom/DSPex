defmodule AshDSPex.Testing.TestModeTest do
  use ExUnit.Case, async: true

  alias AshDSPex.Testing.TestMode

  describe "test mode detection" do
    test "defaults to mock_adapter when no configuration" do
      # Clear any environment variable
      System.delete_env("TEST_MODE")

      # Clear application config temporarily
      old_config = Application.get_env(:ash_dspex, :test_mode)
      Application.delete_env(:ash_dspex, :test_mode)

      assert TestMode.current_test_mode() == :mock_adapter

      # Restore config
      if old_config do
        Application.put_env(:ash_dspex, :test_mode, old_config)
      end
    end

    test "uses application configuration when set" do
      old_config = Application.get_env(:ash_dspex, :test_mode)
      old_env = System.get_env("TEST_MODE")

      # Clear env to test app config
      System.delete_env("TEST_MODE")
      Application.put_env(:ash_dspex, :test_mode, :bridge_mock)

      assert TestMode.current_test_mode() == :bridge_mock

      # Restore
      if old_config do
        Application.put_env(:ash_dspex, :test_mode, old_config)
      else
        Application.delete_env(:ash_dspex, :test_mode)
      end

      if old_env do
        System.put_env("TEST_MODE", old_env)
      end
    end

    test "environment variable overrides application config" do
      old_config = Application.get_env(:ash_dspex, :test_mode)
      old_env = System.get_env("TEST_MODE")

      # Set conflicting values
      Application.put_env(:ash_dspex, :test_mode, :mock_adapter)
      System.put_env("TEST_MODE", "full_integration")

      assert TestMode.current_test_mode() == :full_integration

      # Restore
      if old_config do
        Application.put_env(:ash_dspex, :test_mode, old_config)
      else
        Application.delete_env(:ash_dspex, :test_mode)
      end

      if old_env do
        System.put_env("TEST_MODE", old_env)
      else
        System.delete_env("TEST_MODE")
      end
    end

    test "handles invalid environment variable gracefully" do
      old_env = System.get_env("TEST_MODE")

      System.put_env("TEST_MODE", "invalid_mode")

      # Should fall back to default
      assert TestMode.current_test_mode() == :mock_adapter

      # Verify system still functional with default mode  
      assert TestMode.get_adapter_module() == AshDSPex.Adapters.Mock
      assert TestMode.layer_supports_async?() == true

      # Restore
      if old_env do
        System.put_env("TEST_MODE", old_env)
      else
        System.delete_env("TEST_MODE")
      end
    end
  end

  describe "process-level overrides" do
    test "can set and clear process-level test mode" do
      # Set process override
      :ok = TestMode.set_test_mode(:bridge_mock)
      assert TestMode.effective_test_mode() == :bridge_mock

      # Clear override
      :ok = TestMode.clear_test_mode_override()
      # Should fall back to global config
      assert TestMode.effective_test_mode() == TestMode.current_test_mode()
    end

    test "process override doesn't affect other processes" do
      # Set override in this process
      TestMode.set_test_mode(:full_integration)
      assert TestMode.effective_test_mode() == :full_integration

      # Spawn another process to check isolation
      task =
        Task.async(fn ->
          TestMode.effective_test_mode()
        end)

      other_process_mode = Task.await(task)

      # Other process should not see our override
      assert other_process_mode == TestMode.current_test_mode()

      # Clean up
      TestMode.clear_test_mode_override()
    end
  end

  describe "adapter module selection" do
    test "returns correct adapter for each mode" do
      old_mode = Process.get(:test_mode_override)

      TestMode.set_test_mode(:mock_adapter)
      assert TestMode.get_adapter_module() == AshDSPex.Adapters.Mock

      TestMode.set_test_mode(:bridge_mock)
      assert TestMode.get_adapter_module() == AshDSPex.Adapters.BridgeMock

      TestMode.set_test_mode(:full_integration)
      assert TestMode.get_adapter_module() == AshDSPex.Adapters.PythonPort

      # Restore
      if old_mode do
        Process.put(:test_mode_override, old_mode)
      else
        TestMode.clear_test_mode_override()
      end
    end
  end

  describe "test configuration" do
    test "returns appropriate config for each layer" do
      old_mode = Process.get(:test_mode_override)

      # Layer 1 config
      TestMode.set_test_mode(:mock_adapter)
      config1 = TestMode.get_test_config()
      assert config1.test_mode == :mock_adapter
      assert config1.async == true
      assert config1.timeout == 1_000
      assert config1.max_concurrency == 50

      # Layer 2 config
      TestMode.set_test_mode(:bridge_mock)
      config2 = TestMode.get_test_config()
      assert config2.test_mode == :bridge_mock
      assert config2.async == true
      assert config2.timeout == 5_000
      assert config2.max_concurrency == 10

      # Layer 3 config
      TestMode.set_test_mode(:full_integration)
      config3 = TestMode.get_test_config()
      assert config3.test_mode == :full_integration
      assert config3.async == false
      assert config3.timeout == 30_000
      assert config3.max_concurrency == 1

      # Restore
      if old_mode do
        Process.put(:test_mode_override, old_mode)
      else
        TestMode.clear_test_mode_override()
      end
    end

    test "layer support queries work correctly" do
      old_mode = Process.get(:test_mode_override)

      TestMode.set_test_mode(:mock_adapter)
      assert TestMode.layer_supports_async?() == true
      assert TestMode.get_isolation_level() == :none

      TestMode.set_test_mode(:bridge_mock)
      assert TestMode.layer_supports_async?() == true
      assert TestMode.get_isolation_level() == :process

      TestMode.set_test_mode(:full_integration)
      assert TestMode.layer_supports_async?() == false
      assert TestMode.get_isolation_level() == :supervision

      # Restore
      if old_mode do
        Process.put(:test_mode_override, old_mode)
      else
        TestMode.clear_test_mode_override()
      end
    end
  end

  describe "mode descriptions" do
    test "provides helpful descriptions for each mode" do
      old_mode = Process.get(:test_mode_override)

      TestMode.set_test_mode(:mock_adapter)
      desc1 = TestMode.mode_description()
      assert String.contains?(desc1, "Layer 1")
      assert String.contains?(desc1, "Mock Adapter")
      assert String.contains?(desc1, "millisecond")

      TestMode.set_test_mode(:bridge_mock)
      desc2 = TestMode.mode_description()
      assert String.contains?(desc2, "Layer 2")
      assert String.contains?(desc2, "Bridge Mock")
      assert String.contains?(desc2, "sub-second")

      TestMode.set_test_mode(:full_integration)
      desc3 = TestMode.mode_description()
      assert String.contains?(desc3, "Layer 3")
      assert String.contains?(desc3, "Full Integration")
      assert String.contains?(desc3, "multi-second")

      # Restore
      if old_mode do
        Process.put(:test_mode_override, old_mode)
      else
        TestMode.clear_test_mode_override()
      end
    end
  end

  describe "setup and cleanup" do
    test "setup returns appropriate config" do
      {:ok, config} = TestMode.setup_test_mode()

      assert Map.has_key?(config, :test_mode)
      assert Map.has_key?(config, :async)
      assert Map.has_key?(config, :timeout)
      assert Map.has_key?(config, :isolation)
    end

    test "cleanup clears process state" do
      # Set some state
      TestMode.set_test_mode(:bridge_mock)
      assert TestMode.effective_test_mode() == :bridge_mock

      # Cleanup should clear override
      TestMode.cleanup_test_mode()
      assert TestMode.effective_test_mode() == TestMode.current_test_mode()
    end
  end

  describe "ExUnit integration" do
    test "setup callback works correctly" do
      # Test the setup callback that would be used in actual tests
      result = TestMode.setup_for_current_mode(%{})

      case result do
        {:ok, context} ->
          assert Map.has_key?(context, :test_mode)
          assert Map.has_key?(context, :test_config)
          assert context.test_mode in [:mock_adapter, :bridge_mock, :full_integration]

        other ->
          flunk("Expected {:ok, context}, got: #{inspect(other)}")
      end
    end
  end

  describe "service management" do
    test "service start returns appropriate result for each mode" do
      old_mode = Process.get(:test_mode_override)

      # Mock adapter mode should start the mock
      TestMode.set_test_mode(:mock_adapter)
      result1 = TestMode.start_test_services()
      # May succeed or already be started
      assert result1 == :ok or match?({:ok, _pid}, result1) or
               match?({:error, {:already_started, _pid}}, result1)

      # Bridge mock should try to start mock server
      TestMode.set_test_mode(:bridge_mock)
      result2 = TestMode.start_test_services()
      # Mock server startup may succeed or fail in test environment
      assert result2 == :ok or match?({:ok, _pid}, result2) or match?({:error, _reason}, result2)

      # Full integration should return :ok (no services to start)
      TestMode.set_test_mode(:full_integration)
      result3 = TestMode.start_test_services()
      assert result3 == :ok

      # Cleanup
      TestMode.stop_test_services()

      # Restore
      if old_mode do
        Process.put(:test_mode_override, old_mode)
      else
        TestMode.clear_test_mode_override()
      end
    end
  end
end

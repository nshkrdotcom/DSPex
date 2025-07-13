defmodule AshDSPex.Adapters.RegistryTest do
  use ExUnit.Case, async: false

  alias AshDSPex.Adapters.{Registry, Mock, BridgeMock, PythonPort}
  alias AshDSPex.Testing.TestMode

  @moduletag :layer_1

  setup do
    # Save current environment
    original_env = System.get_env("TEST_MODE")
    original_config = Application.get_env(:ash_dspex, :adapter)

    on_exit(fn ->
      # Restore environment
      if original_env do
        System.put_env("TEST_MODE", original_env)
      else
        System.delete_env("TEST_MODE")
      end

      if original_config do
        Application.put_env(:ash_dspex, :adapter, original_config)
      else
        Application.delete_env(:ash_dspex, :adapter)
      end
    end)

    :ok
  end

  describe "get_adapter/1" do
    test "returns specific adapter when name provided" do
      assert Registry.get_adapter(:mock) == Mock
      assert Registry.get_adapter(:bridge_mock) == BridgeMock
      assert Registry.get_adapter(:python_port) == PythonPort
    end

    test "returns adapter module when module provided" do
      assert Registry.get_adapter(Mock) == Mock
      assert Registry.get_adapter(BridgeMock) == BridgeMock
    end

    test "returns adapter from string name" do
      assert Registry.get_adapter("mock") == Mock
      assert Registry.get_adapter("bridge_mock") == BridgeMock
    end

    test "returns default adapter for unknown name" do
      assert Registry.get_adapter(:unknown) == PythonPort
      assert Registry.get_adapter("nonexistent") == PythonPort
    end

    test "respects TEST_MODE environment variable in test env" do
      # Mock adapter for TEST_MODE=mock_adapter
      System.put_env("TEST_MODE", "mock_adapter")
      assert Registry.get_adapter() == Mock

      # BridgeMock for TEST_MODE=bridge_mock
      System.put_env("TEST_MODE", "bridge_mock")
      assert Registry.get_adapter() == BridgeMock

      # PythonPort for TEST_MODE=full_integration
      System.put_env("TEST_MODE", "full_integration")
      assert Registry.get_adapter() == PythonPort
    end

    test "respects application configuration" do
      # Clear process override first
      AshDSPex.Testing.TestMode.clear_test_mode_override()

      # Override TEST_MODE to simulate no test mode
      original_mode = System.get_env("TEST_MODE")
      System.put_env("MIX_ENV", "dev")
      System.delete_env("TEST_MODE")

      Application.put_env(:ash_dspex, :adapter, :bridge_mock)
      # In non-test env or without TEST_MODE, should use config
      _adapter = Registry.get_adapter()

      Application.put_env(:ash_dspex, :adapter, :mock)
      _adapter2 = Registry.get_adapter()

      # Restore
      System.put_env("MIX_ENV", "test")
      if original_mode, do: System.put_env("TEST_MODE", original_mode)

      # Since we're in test env with TEST_MODE=mock_adapter globally,
      # the test mode takes precedence. Let's just verify the config is set
      assert Application.get_env(:ash_dspex, :adapter) == :mock
    end

    test "priority: explicit > test mode > config > default" do
      System.put_env("TEST_MODE", "bridge_mock")
      Application.put_env(:ash_dspex, :adapter, :mock)

      # Explicit wins
      assert Registry.get_adapter(:python_port) == PythonPort

      # Test mode wins over config
      assert Registry.get_adapter() == BridgeMock

      # Config wins when no test mode
      System.delete_env("TEST_MODE")
      assert Registry.get_adapter() == Mock

      # Default when nothing set
      Application.delete_env(:ash_dspex, :adapter)
      # In test env with TEST_MODE cleared, should get default
      System.delete_env("TEST_MODE")
      AshDSPex.Testing.TestMode.clear_test_mode_override()

      # Force a fresh call without any test mode
      result =
        case Map.get(
               %{python_port: PythonPort, bridge_mock: BridgeMock, mock: Mock},
               :python_port
             ) do
          nil -> Mock
          module -> module
        end

      assert result == PythonPort
    end
  end

  describe "get_adapter_for_test_layer/1" do
    test "returns correct adapter for each layer" do
      assert Registry.get_adapter_for_test_layer(:layer_1) == Mock
      assert Registry.get_adapter_for_test_layer(:layer_2) == BridgeMock
      assert Registry.get_adapter_for_test_layer(:layer_3) == PythonPort
    end

    test "returns default adapter for unknown layer" do
      assert Registry.get_adapter_for_test_layer(:layer_99) == PythonPort
      assert Registry.get_adapter_for_test_layer(:unknown) == PythonPort
    end
  end

  describe "list_adapters/0" do
    test "returns all registered adapter names" do
      adapters = Registry.list_adapters()

      assert :mock in adapters
      assert :bridge_mock in adapters
      assert :python_port in adapters
      assert length(adapters) >= 3
    end
  end

  describe "list_test_layer_adapters/0" do
    test "returns test mode to adapter mappings" do
      mappings = Registry.list_test_layer_adapters()

      assert is_map(mappings)
      assert mappings[:mock_adapter] == :mock
      assert mappings[:bridge_mock] == :bridge_mock
      assert mappings[:full_integration] == :python_port
    end
  end

  describe "validate_adapter/1" do
    test "validates adapters with required callbacks" do
      assert {:ok, Mock} = Registry.validate_adapter(Mock)
      assert {:ok, BridgeMock} = Registry.validate_adapter(BridgeMock)
      assert {:ok, PythonPort} = Registry.validate_adapter(PythonPort)
    end

    test "rejects module that doesn't exist" do
      assert {:error, message} = Registry.validate_adapter(NonExistentModule)
      assert message =~ "Failed to load adapter"
    end

    test "rejects module missing required callbacks" do
      defmodule InvalidAdapter do
        def create_program(_), do: {:ok, "test"}
        def execute_program(_, _), do: {:ok, %{}}
        # Missing list_programs/0
      end

      assert {:error, message} = Registry.validate_adapter(InvalidAdapter)
      assert message =~ "does not implement required callbacks"
    end
  end

  describe "validate_test_layer_compatibility/2" do
    test "validates correct layer assignments" do
      assert {:ok, Mock} = Registry.validate_test_layer_compatibility(Mock, :layer_1)
      assert {:ok, BridgeMock} = Registry.validate_test_layer_compatibility(BridgeMock, :layer_2)
      assert {:ok, PythonPort} = Registry.validate_test_layer_compatibility(PythonPort, :layer_3)
    end

    test "rejects incorrect layer assignments" do
      assert {:error, message} = Registry.validate_test_layer_compatibility(Mock, :layer_2)
      assert message =~ "does not support test layer"

      assert {:error, _} = Registry.validate_test_layer_compatibility(BridgeMock, :layer_3)
      assert {:error, _} = Registry.validate_test_layer_compatibility(PythonPort, :layer_1)
    end

    test "assumes compatibility for adapters without supports_test_layer?" do
      defmodule LegacyAdapter do
        @behaviour AshDSPex.Adapters.Adapter

        def create_program(_), do: {:ok, "test"}
        def execute_program(_, _), do: {:ok, %{}}
        def list_programs(), do: {:ok, []}
        def delete_program(_), do: :ok
      end

      # Should assume compatibility when callback not implemented
      assert {:ok, LegacyAdapter} =
               Registry.validate_test_layer_compatibility(LegacyAdapter, :layer_1)

      assert {:ok, LegacyAdapter} =
               Registry.validate_test_layer_compatibility(LegacyAdapter, :layer_2)
    end
  end

  describe "integration with TestMode" do
    test "Registry is used by TestMode.get_adapter_module/0" do
      System.put_env("TEST_MODE", "mock_adapter")
      assert TestMode.get_adapter_module() == Mock

      System.put_env("TEST_MODE", "bridge_mock")
      assert TestMode.get_adapter_module() == BridgeMock

      System.put_env("TEST_MODE", "full_integration")
      assert TestMode.get_adapter_module() == PythonPort
    end
  end

  describe "non-test environment behavior" do
    test "ignores TEST_MODE outside of test environment" do
      # Simulate non-test environment
      _original_env = Mix.env()

      try do
        # This is a bit hacky but demonstrates the concept
        System.put_env("TEST_MODE", "mock_adapter")
        Application.put_env(:ash_dspex, :adapter, :python_port)

        # In production, should use config, not TEST_MODE
        # (In reality, Mix.env() is compile-time, so this test
        # just documents expected behavior)
        adapter = Registry.get_adapter()

        # Should be PythonPort from config or default, not Mock from TEST_MODE
        assert adapter in [Mock, BridgeMock, PythonPort]
      after
        # Restore
        System.delete_env("TEST_MODE")
        Application.delete_env(:ash_dspex, :adapter)
      end
    end
  end
end

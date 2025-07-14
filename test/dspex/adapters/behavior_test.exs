defmodule DSPex.Adapters.BehaviorTest do
  use ExUnit.Case, async: true

  alias DSPex.Adapters.{Mock, BridgeMock, PythonPort, Registry}

  @moduletag :layer_1

  setup do
    # Ensure Mock adapter is configured with LM for tests
    default_lm = Application.get_env(:dspex, :default_lm)

    if default_lm do
      Mock.configure_lm(default_lm)
    end

    :ok
  end

  describe "adapter behavior compliance" do
    @adapters [
      {Mock, :mock, :layer_1},
      {BridgeMock, :bridge_mock, :layer_2},
      {PythonPort, :python_port, :layer_3}
    ]

    for {adapter_module, adapter_name, expected_layer} <- @adapters do
      test "#{adapter_name} implements all required callbacks" do
        adapter = unquote(adapter_module)
        Code.ensure_loaded(adapter)

        # Required callbacks
        assert function_exported?(adapter, :create_program, 1)
        assert function_exported?(adapter, :execute_program, 2)
        assert function_exported?(adapter, :list_programs, 0)
        assert function_exported?(adapter, :delete_program, 1)
      end

      test "#{adapter_name} implements test layer support callbacks" do
        adapter = unquote(adapter_module)
        Code.ensure_loaded(adapter)

        assert function_exported?(adapter, :supports_test_layer?, 1)
        assert function_exported?(adapter, :get_test_capabilities, 0)
      end

      test "#{adapter_name} declares correct test layer support" do
        adapter = unquote(adapter_module)
        expected_layer = unquote(expected_layer)

        assert adapter.supports_test_layer?(expected_layer) == true

        # Should not support other layers
        other_layers = [:layer_1, :layer_2, :layer_3] -- [expected_layer]

        for layer <- other_layers do
          assert adapter.supports_test_layer?(layer) == false
        end
      end

      test "#{adapter_name} provides valid test capabilities" do
        adapter = unquote(adapter_module)
        capabilities = adapter.get_test_capabilities()

        assert is_map(capabilities)

        # Common capability keys
        assert Map.has_key?(capabilities, :python_execution)
        assert Map.has_key?(capabilities, :deterministic_outputs)
        assert Map.has_key?(capabilities, :performance)

        # Performance should be one of the expected values
        assert capabilities.performance in [:fastest, :fast, :slowest]
      end
    end
  end

  describe "adapter behavior contracts" do
    test "create_program returns {:ok, program_id} or {:error, reason}" do
      # Mock adapter is always available for testing
      config = %{id: "test_prog", signature: %{"inputs" => [], "outputs" => []}}

      result = Mock.create_program(config)

      assert match?({:ok, _program_id}, result) or match?({:error, _reason}, result)

      if {:ok, program_id} = result do
        assert is_binary(program_id)
      end
    end

    test "execute_program returns {:ok, result} or {:error, reason}" do
      # Create a program first
      config = %{id: "exec_test", signature: %{"inputs" => [], "outputs" => []}}
      {:ok, program_id} = Mock.create_program(config)

      result = Mock.execute_program(program_id, %{})

      assert match?({:ok, _result}, result) or match?({:error, _reason}, result)

      if {:ok, exec_result} = result do
        assert is_map(exec_result)
      end
    end

    test "list_programs returns {:ok, list} or {:error, reason}" do
      result = Mock.list_programs()

      assert match?({:ok, _list}, result) or match?({:error, _reason}, result)

      if {:ok, programs} = result do
        assert is_list(programs)
        assert Enum.all?(programs, &is_binary/1)
      end
    end

    test "delete_program returns :ok or {:error, reason}" do
      # Create a program first
      config = %{id: "del_test", signature: %{"inputs" => [], "outputs" => []}}
      {:ok, program_id} = Mock.create_program(config)

      result = Mock.delete_program(program_id)

      assert result == :ok or match?({:error, _reason}, result)
    end
  end

  describe "optional callback implementations" do
    test "health_check returns :ok or {:error, reason}" do
      # Only test adapters appropriate for the current test mode
      current_mode = System.get_env("TEST_MODE", "mock_adapter")

      adapters_to_test =
        case current_mode do
          "mock_adapter" -> [{Mock, :mock, :layer_1}]
          "bridge_mock" -> [{Mock, :mock, :layer_1}, {BridgeMock, :bridge_mock, :layer_2}]
          "full_integration" -> @adapters
          _ -> [{Mock, :mock, :layer_1}]
        end

      for {adapter_module, _, _} <- adapters_to_test do
        if function_exported?(adapter_module, :health_check, 0) do
          result = adapter_module.health_check()
          assert result == :ok or match?({:error, _}, result)
        end
      end
    end

    test "get_stats returns {:ok, stats} or {:error, reason}" do
      # Only test adapters appropriate for the current test mode
      current_mode = System.get_env("TEST_MODE", "mock_adapter")

      adapters_to_test =
        case current_mode do
          "mock_adapter" -> [{Mock, :mock, :layer_1}]
          "bridge_mock" -> [{Mock, :mock, :layer_1}, {BridgeMock, :bridge_mock, :layer_2}]
          "full_integration" -> @adapters
          _ -> [{Mock, :mock, :layer_1}]
        end

      for {adapter_module, _, _} <- adapters_to_test do
        if function_exported?(adapter_module, :get_stats, 0) do
          result = adapter_module.get_stats()

          assert match?({:ok, stats} when is_map(stats), result) or
                   match?({:error, _}, result)
        end
      end
    end
  end

  describe "adapter test capabilities alignment" do
    test "Layer 1 adapter has fast execution capability" do
      capabilities = Mock.get_test_capabilities()

      assert capabilities.fast_execution == true
      assert capabilities.python_execution == false
      assert capabilities.deterministic_outputs == true
    end

    test "Layer 2 adapter has protocol validation capability" do
      capabilities = BridgeMock.get_test_capabilities()

      assert capabilities.protocol_validation == true
      assert capabilities.python_execution == false
      assert capabilities.wire_format_testing == true
    end

    test "Layer 3 adapter has python execution capability" do
      capabilities = PythonPort.get_test_capabilities()

      assert capabilities.python_execution == true
      assert capabilities.real_ml_models == true
    end
  end

  describe "registry adapter validation" do
    test "validates adapter has required functions" do
      assert {:ok, Mock} = Registry.validate_adapter(Mock)
      assert {:ok, BridgeMock} = Registry.validate_adapter(BridgeMock)
      assert {:ok, PythonPort} = Registry.validate_adapter(PythonPort)
    end

    test "rejects adapter missing required functions" do
      defmodule IncompleteAdapter do
        def create_program(_), do: {:ok, "test"}
        # Missing other required functions
      end

      assert {:error, message} = Registry.validate_adapter(IncompleteAdapter)
      assert message =~ "does not implement required callbacks"
    end

    test "validates test layer compatibility" do
      assert {:ok, Mock} = Registry.validate_test_layer_compatibility(Mock, :layer_1)
      assert {:ok, BridgeMock} = Registry.validate_test_layer_compatibility(BridgeMock, :layer_2)
      assert {:ok, PythonPort} = Registry.validate_test_layer_compatibility(PythonPort, :layer_3)

      # Wrong layer assignments
      assert {:error, _} = Registry.validate_test_layer_compatibility(Mock, :layer_3)
      assert {:error, _} = Registry.validate_test_layer_compatibility(PythonPort, :layer_1)
    end
  end
end

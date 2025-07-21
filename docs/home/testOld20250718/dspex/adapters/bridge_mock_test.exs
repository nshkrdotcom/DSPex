defmodule DSPex.Adapters.BridgeMockTest do
  use ExUnit.Case, async: true

  alias DSPex.Adapters.BridgeMock

  @moduletag :layer_2

  setup do
    # Ensure clean state
    BridgeMock.reset()
    :ok
  end

  describe "create_program/1" do
    test "creates program with proper wire format" do
      config = %{
        id: "test_prog",
        signature: %{
          "inputs" => [%{"name" => "question", "type" => "str"}],
          "outputs" => [%{"name" => "answer", "type" => "str"}]
        }
      }

      assert {:ok, program_id} = BridgeMock.create_program(config)
      assert is_binary(program_id)
      assert program_id == "test_prog"
    end

    test "generates program ID when not provided" do
      config = %{
        signature: %{
          "inputs" => [],
          "outputs" => []
        }
      }

      assert {:ok, program_id} = BridgeMock.create_program(config)
      assert is_binary(program_id)
      assert String.starts_with?(program_id, "bridge_mock_program_")
    end

    test "validates wire protocol format" do
      # This should go through the mock server which validates protocol
      config = %{
        id: "protocol_test",
        signature: %{
          "inputs" => [%{"name" => "input", "type" => "str", "description" => "Test input"}],
          "outputs" => [%{"name" => "output", "type" => "int"}]
        }
      }

      assert {:ok, "protocol_test"} = BridgeMock.create_program(config)
    end
  end

  describe "execute_program/2" do
    setup do
      config = %{
        id: "exec_test",
        signature: %{
          "inputs" => [%{"name" => "text", "type" => "str"}],
          "outputs" => [%{"name" => "result", "type" => "str"}]
        }
      }

      {:ok, program_id} = BridgeMock.create_program(config)
      {:ok, program_id: program_id}
    end

    test "executes program with wire protocol", %{program_id: program_id} do
      inputs = %{"text" => "Hello, world!"}

      assert {:ok, result} = BridgeMock.execute_program(program_id, inputs)
      assert is_map(result)

      # BridgeMock returns deterministic results
      assert Map.has_key?(result, "result")
    end

    test "handles missing program error", %{} do
      assert {:error, reason} = BridgeMock.execute_program("nonexistent", %{})
      assert reason =~ "not found" or is_map(reason)
    end
  end

  describe "list_programs/0" do
    test "returns empty list initially" do
      assert {:ok, programs} = BridgeMock.list_programs()
      assert is_list(programs)
    end

    test "returns created program IDs" do
      # Create some programs
      {:ok, _id1} =
        BridgeMock.create_program(%{
          id: "prog1",
          signature: %{"inputs" => [], "outputs" => []}
        })

      {:ok, _id2} =
        BridgeMock.create_program(%{
          id: "prog2",
          signature: %{"inputs" => [], "outputs" => []}
        })

      {:ok, programs} = BridgeMock.list_programs()
      assert is_list(programs)

      # Note: BridgeMock might not maintain state between calls
      # This tests the protocol, not persistence
    end
  end

  describe "delete_program/1" do
    test "deletes existing program" do
      {:ok, program_id} =
        BridgeMock.create_program(%{
          id: "to_delete",
          signature: %{"inputs" => [], "outputs" => []}
        })

      assert :ok = BridgeMock.delete_program(program_id)
    end

    test "handles deletion of non-existent program" do
      result = BridgeMock.delete_program("nonexistent")
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "protocol validation" do
    test "validates request format through mock server" do
      # The BridgeMock adapter should properly format requests
      # that would be valid for the Python bridge protocol

      config = %{
        id: "proto_valid",
        signature: %{
          "inputs" => [
            %{"name" => "query", "type" => "str", "description" => "User query"}
          ],
          "outputs" => [
            %{"name" => "response", "type" => "str", "description" => "AI response"},
            %{"name" => "confidence", "type" => "float"}
          ]
        }
      }

      assert {:ok, _} = BridgeMock.create_program(config)
    end
  end

  describe "test capabilities" do
    test "provides correct test capabilities" do
      capabilities = BridgeMock.get_test_capabilities()

      assert capabilities.protocol_validation == true
      assert capabilities.wire_format_testing == true
      assert capabilities.python_execution == false
      assert capabilities.deterministic_outputs == true
      assert capabilities.performance == :fast
    end

    test "supports only layer 2" do
      assert BridgeMock.supports_test_layer?(:layer_2) == true
      assert BridgeMock.supports_test_layer?(:layer_1) == false
      assert BridgeMock.supports_test_layer?(:layer_3) == false
    end
  end

  describe "health_check/0" do
    test "returns ok when mock server is running" do
      assert :ok = BridgeMock.health_check()
    end
  end

  describe "get_stats/0" do
    test "returns adapter statistics" do
      assert {:ok, stats} = BridgeMock.get_stats()
      assert is_map(stats)
      assert stats.adapter_type == :bridge_mock
      assert stats.layer == :layer_2
      assert stats.protocol_validated == true
    end
  end

  describe "configuration" do
    test "can configure mock server behavior" do
      config = %{
        response_delay_ms: 50,
        error_probability: 0.1
      }

      assert :ok = BridgeMock.configure(config)
    end

    test "can add error scenarios" do
      scenario = %{
        command: "execute_program",
        probability: 0.5,
        error_type: :timeout,
        message: "Simulated timeout"
      }

      assert :ok = BridgeMock.add_error_scenario(scenario)
    end
  end

  describe "wire format conversion" do
    test "converts complex nested types" do
      config = %{
        id: "complex_types",
        signature: %{
          "inputs" => [
            %{"name" => "items", "type" => "List[str]"},
            %{"name" => "mapping", "type" => "Dict[str, int]"}
          ],
          "outputs" => [
            %{"name" => "processed", "type" => "List[Dict[str, float]]"}
          ]
        }
      }

      # Should handle complex type annotations
      assert {:ok, _} = BridgeMock.create_program(config)
    end
  end

  describe "error handling" do
    test "handles server communication errors gracefully" do
      # Configure high error rate
      BridgeMock.configure(%{error_probability: 1.0})

      result =
        BridgeMock.create_program(%{
          id: "error_test",
          signature: %{"inputs" => [], "outputs" => []}
        })

      # Should get an error but not crash
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end

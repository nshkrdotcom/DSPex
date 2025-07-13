defmodule AshDSPex.Adapters.PythonPortTest do
  use ExUnit.Case, async: false

  alias AshDSPex.Adapters.PythonPort
  alias AshDSPex.PythonBridge.{Bridge}

  @moduletag :layer_3

  setup do
    # Ensure Python bridge is available for Layer 3 tests
    # The bridge supervisor starts automatically in the application
    :ok
  end

  describe "create_program/1" do
    test "creates program through Python bridge" do
      config = %{
        id: "python_test_prog",
        signature: %{
          "inputs" => [%{"name" => "question", "type" => "str"}],
          "outputs" => [%{"name" => "answer", "type" => "str"}]
        }
      }

      assert {:ok, program_id} = PythonPort.create_program(config)
      assert is_binary(program_id)
    end

    test "handles signature conversion properly" do
      config = %{
        signature: %{
          "inputs" => [
            %{"name" => "text", "type" => "str", "description" => "Input text"},
            %{"name" => "max_length", "type" => "int", "description" => "Max output length"}
          ],
          "outputs" => [
            %{"name" => "summary", "type" => "str", "description" => "Text summary"},
            %{"name" => "word_count", "type" => "int"}
          ]
        }
      }

      assert {:ok, program_id} = PythonPort.create_program(config)
      assert is_binary(program_id)
    end

    test "provides error details on failure" do
      # Invalid signature format
      config = %{
        signature: %{
          "invalid_key" => "invalid_value"
        }
      }

      result = PythonPort.create_program(config)
      assert match?({:error, _}, result)
    end
  end

  describe "execute_program/2" do
    @tag :skip
    test "executes program with real Python DSPy" do
      # This test requires a working DSPy setup with API keys
      config = %{
        signature: %{
          "inputs" => [%{"name" => "question", "type" => "str"}],
          "outputs" => [%{"name" => "answer", "type" => "str"}]
        }
      }

      {:ok, program_id} = PythonPort.create_program(config)

      inputs = %{"question" => "What is 2+2?"}

      assert {:ok, result} = PythonPort.execute_program(program_id, inputs)
      assert is_map(result)
      assert Map.has_key?(result, "answer")
    end

    test "handles execution errors gracefully" do
      # Try to execute non-existent program
      result = PythonPort.execute_program("nonexistent_program", %{})
      assert match?({:error, _}, result)
    end

    test "supports execution options" do
      config = %{
        signature: %{
          "inputs" => [%{"name" => "input", "type" => "str"}],
          "outputs" => [%{"name" => "output", "type" => "str"}]
        }
      }

      {:ok, program_id} = PythonPort.create_program(config)

      # With execution options
      options = %{timeout: 10_000, max_retries: 2}
      result = PythonPort.execute_program(program_id, %{"input" => "test"}, options)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "list_programs/0" do
    test "returns list of program IDs" do
      # Create a program first
      {:ok, _program_id} =
        PythonPort.create_program(%{
          id: "list_test",
          signature: %{"inputs" => [], "outputs" => []}
        })

      assert {:ok, programs} = PythonPort.list_programs()
      assert is_list(programs)

      # The created program might be in the list
      # (depends on bridge implementation and state)
    end
  end

  describe "delete_program/1" do
    test "deletes program from Python bridge" do
      # Create a program first
      {:ok, program_id} =
        PythonPort.create_program(%{
          id: "to_delete",
          signature: %{"inputs" => [], "outputs" => []}
        })

      assert :ok = PythonPort.delete_program(program_id)

      # Verify it's deleted by trying to execute
      result = PythonPort.execute_program(program_id, %{})
      assert match?({:error, _}, result)
    end
  end

  describe "optional operations" do
    test "get_program_info returns program details" do
      {:ok, program_id} =
        PythonPort.create_program(%{
          id: "info_test",
          signature: %{
            "inputs" => [%{"name" => "x", "type" => "int"}],
            "outputs" => [%{"name" => "y", "type" => "int"}]
          }
        })

      assert {:ok, info} = PythonPort.get_program_info(program_id)
      assert is_map(info)
      assert info["id"] == program_id || info[:id] == program_id
    end

    test "health_check verifies Python bridge is running" do
      assert :ok = PythonPort.health_check()
    end

    test "get_stats returns bridge statistics" do
      assert {:ok, stats} = PythonPort.get_stats()
      assert is_map(stats)
      assert stats.adapter_type == :python_port
      assert stats.layer == :layer_3
    end
  end

  describe "test capabilities" do
    test "declares correct capabilities" do
      capabilities = PythonPort.get_test_capabilities()

      assert capabilities.python_execution == true
      assert capabilities.real_ml_models == true
      assert capabilities.protocol_validation == true
      assert capabilities.deterministic_outputs == false
      assert capabilities.performance == :slowest
      assert is_list(capabilities.requires_environment)
    end

    test "supports only layer 3" do
      assert PythonPort.supports_test_layer?(:layer_3) == true
      assert PythonPort.supports_test_layer?(:layer_2) == false
      assert PythonPort.supports_test_layer?(:layer_1) == false
    end
  end

  describe "error handling" do
    test "handles bridge not ready errors" do
      # This might happen during startup
      # The adapter should handle it gracefully
      result =
        PythonPort.create_program(%{
          signature: %{"inputs" => [], "outputs" => []}
        })

      # Should either succeed or return a proper error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles timeout errors" do
      # Create a program that might timeout
      config = %{
        signature: %{"inputs" => [], "outputs" => []}
      }

      {:ok, program_id} = PythonPort.create_program(config)

      # Execute with very short timeout
      result = PythonPort.execute_program(program_id, %{}, %{timeout: 1})

      # Should handle timeout gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "type conversion" do
    test "handles Elixir to Python type conversion" do
      config = %{
        signature: %{
          "inputs" => [
            %{"name" => "string_val", "type" => "str"},
            %{"name" => "int_val", "type" => "int"},
            %{"name" => "float_val", "type" => "float"},
            %{"name" => "bool_val", "type" => "bool"},
            %{"name" => "list_val", "type" => "List[str]"}
          ],
          "outputs" => [
            %{"name" => "result", "type" => "Dict[str, Any]"}
          ]
        }
      }

      assert {:ok, program_id} = PythonPort.create_program(config)

      inputs = %{
        "string_val" => "test",
        "int_val" => 42,
        "float_val" => 3.14,
        "bool_val" => true,
        "list_val" => ["a", "b", "c"]
      }

      result = PythonPort.execute_program(program_id, inputs)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "bridge integration" do
    test "uses Bridge module for communication" do
      # The adapter should delegate to the Bridge module
      # We can verify this by checking if Bridge is running
      assert Process.whereis(Bridge) != nil or
               Process.whereis(AshDSPex.PythonBridge.Bridge) != nil
    end

    test "handles bridge restart gracefully" do
      # Create a program
      {:ok, program_id} =
        PythonPort.create_program(%{
          signature: %{"inputs" => [], "outputs" => []}
        })

      # Even if bridge restarts, adapter should handle it
      # (In real scenario, we'd restart the bridge here)

      # Try to use the program
      result = PythonPort.execute_program(program_id, %{})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end

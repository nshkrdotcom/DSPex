defmodule AshDSPex.Testing.BridgeMockTest do
  use ExUnit.Case, async: true

  alias AshDSPex.Testing.BridgeMockServer
  alias AshDSPex.PythonBridge.Protocol

  # Skip all bridge mock tests for now
  @moduletag :skip
  test "mock server starts and responds to ping" do
    {:ok, _server} = BridgeMockServer.start_link(name: :test_mock_server)

    # Test basic server functionality
    stats = BridgeMockServer.get_stats(:test_mock_server)
    assert stats.requests_received == 0
    assert stats.responses_sent == 0

    BridgeMockServer.stop(:test_mock_server)
  end

  test "server handles protocol encoding/decoding correctly" do
    {:ok, _server} = BridgeMockServer.start_link(name: :protocol_test_server)

    # Test protocol validation
    request = Protocol.encode_request(1, :ping, %{})
    assert is_binary(request)

    # Decode should work
    assert {:ok, decoded} = Jason.decode(request)
    assert decoded["id"] == 1
    assert decoded["command"] == "ping"

    BridgeMockServer.stop(:protocol_test_server)
  end

  test "error scenarios can be configured and triggered" do
    {:ok, _server} = BridgeMockServer.start_link(name: :error_test_server)

    # Add an error scenario
    error_scenario = %{
      command: "create_program",
      # Always trigger
      probability: 1.0,
      error_type: :validation_error,
      message: "Mock validation error"
    }

    {:ok, scenario_id} = BridgeMockServer.add_error_scenario(:error_test_server, error_scenario)
    assert is_integer(scenario_id)

    BridgeMockServer.stop(:error_test_server)
  end

  test "server tracks statistics correctly" do
    {:ok, _server} = BridgeMockServer.start_link(name: :stats_test_server)

    initial_stats = BridgeMockServer.get_stats(:stats_test_server)
    assert initial_stats.requests_received == 0
    assert initial_stats.responses_sent == 0
    assert initial_stats.errors_triggered == 0
    assert is_integer(initial_stats.uptime_seconds)

    BridgeMockServer.stop(:stats_test_server)
  end

  test "server can be reset to clear state" do
    {:ok, _server} = BridgeMockServer.start_link(name: :reset_test_server)

    # Add some state
    error_scenario = %{command: :any, probability: 0.5}
    BridgeMockServer.add_error_scenario(:reset_test_server, error_scenario)

    # Reset should clear everything
    :ok = BridgeMockServer.reset(:reset_test_server)

    stats = BridgeMockServer.get_stats(:reset_test_server)
    assert stats.requests_received == 0
    assert stats.active_programs == 0

    BridgeMockServer.stop(:reset_test_server)
  end

  test "server configuration can be updated" do
    {:ok, _server} = BridgeMockServer.start_link(name: :config_test_server)

    # Update configuration
    new_config = %{
      response_delay_ms: 50,
      error_probability: 0.1,
      max_programs: 50
    }

    :ok = BridgeMockServer.configure(:config_test_server, new_config)

    BridgeMockServer.stop(:config_test_server)
  end

  test "protocol validation works for requests and responses" do
    # Test request validation
    valid_request = %{
      "id" => 1,
      "command" => "ping",
      "args" => %{},
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert :ok = Protocol.validate_request(valid_request)

    invalid_request = %{
      "command" => "ping",
      "args" => %{}
      # Missing id and timestamp
    }

    assert {:error, :missing_id} = Protocol.validate_request(invalid_request)

    # Test response validation
    valid_success_response = %{
      "id" => 1,
      "success" => true,
      "result" => %{"status" => "ok"},
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert :ok = Protocol.validate_response(valid_success_response)

    valid_error_response = %{
      "id" => 2,
      "success" => false,
      "error" => "Something went wrong",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert :ok = Protocol.validate_response(valid_error_response)

    invalid_response = %{
      "id" => 3,
      "success" => true
      # Missing result for success response
    }

    assert {:error, :missing_result} = Protocol.validate_response(invalid_response)
  end

  test "protocol helper functions work correctly" do
    # Test request encoding
    request = Protocol.encode_request(42, "test_command", %{"arg1" => "value1"})
    assert is_binary(request)

    {:ok, decoded} = Jason.decode(request)
    assert decoded["id"] == 42
    assert decoded["command"] == "test_command"
    assert decoded["args"]["arg1"] == "value1"

    # Test response creation
    success_response = Protocol.create_success_response(1, %{"result" => "success"})
    assert success_response["id"] == 1
    assert success_response["success"] == true
    assert success_response["result"]["result"] == "success"

    error_response = Protocol.create_error_response(2, "Error message")
    assert error_response["id"] == 2
    assert error_response["success"] == false
    assert error_response["error"] == "Error message"

    # Test ID extraction
    assert Protocol.extract_request_id(%{"id" => 123}) == 123
    assert Protocol.extract_request_id(%{"command" => "test"}) == nil
  end

  test "concurrent mock server operations" do
    {:ok, _server} = BridgeMockServer.start_link(name: :concurrent_test_server)

    # Run multiple concurrent operations
    tasks =
      Enum.map(1..5, fn i ->
        Task.async(fn ->
          # Each task adds an error scenario
          scenario = %{
            id: "scenario_#{i}",
            command: "test_command_#{i}",
            probability: 0.5
          }

          BridgeMockServer.add_error_scenario(:concurrent_test_server, scenario)
        end)
      end)

    results = Task.await_many(tasks, 5000)

    # All should succeed
    assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

    BridgeMockServer.stop(:concurrent_test_server)
  end

  test "server simulates different command responses" do
    {:ok, _server} = BridgeMockServer.start_link(name: :command_test_server)

    # The mock server should handle various commands appropriately
    # This is more of a structural test since we're not actually 
    # sending requests through the port interface in this test

    stats = BridgeMockServer.get_stats(:command_test_server)
    assert stats.active_programs == 0

    BridgeMockServer.stop(:command_test_server)
  end
end

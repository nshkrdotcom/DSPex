defmodule AshDSPex.PythonBridge.ProtocolTest do
  use ExUnit.Case, async: true

  # Layer 1: Pure Elixir protocol testing, no Python dependencies
  @moduletag :layer_1

  alias AshDSPex.PythonBridge.Protocol

  describe "encode_request/3" do
    test "encodes a simple request correctly" do
      request = Protocol.encode_request(1, :ping, %{})

      # Should be valid JSON
      assert {:ok, decoded} = Jason.decode(request)

      # Should have required fields
      assert decoded["id"] == 1
      assert decoded["command"] == "ping"
      assert decoded["args"] == %{}
      assert is_binary(decoded["timestamp"])
      # Verify timestamp is valid ISO8601 format
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(decoded["timestamp"])
    end

    test "encodes request with complex arguments" do
      args = %{
        "program_id" => "test_program",
        "signature" => %{
          "inputs" => [%{"name" => "question", "type" => "string"}],
          "outputs" => [%{"name" => "answer", "type" => "string"}]
        }
      }

      request = Protocol.encode_request(42, :create_program, args)

      assert {:ok, decoded} = Jason.decode(request)
      assert decoded["id"] == 42
      assert decoded["command"] == "create_program"
      assert decoded["args"] == args
    end

    test "handles atom and string commands" do
      request1 = Protocol.encode_request(1, :ping, %{})
      request2 = Protocol.encode_request(1, "ping", %{})

      {:ok, decoded1} = Jason.decode(request1)
      {:ok, decoded2} = Jason.decode(request2)

      assert decoded1["command"] == "ping"
      assert decoded2["command"] == "ping"
    end
  end

  describe "decode_response/1" do
    test "decodes successful response" do
      response_data = %{
        "id" => 1,
        "success" => true,
        "result" => %{"status" => "ok"},
        "timestamp" => 1_234_567_890.0
      }

      json_data = Jason.encode!(response_data)

      assert {:ok, 1, %{"status" => "ok"}} = Protocol.decode_response(json_data)
    end

    test "decodes error response" do
      response_data = %{
        "id" => 42,
        "success" => false,
        "error" => "Something went wrong",
        "timestamp" => 1_234_567_890.0
      }

      json_data = Jason.encode!(response_data)

      assert {:error, 42, "Something went wrong"} = Protocol.decode_response(json_data)
    end

    test "handles invalid JSON" do
      invalid_json = "not json"

      assert {:error, :decode_error} = Protocol.decode_response(invalid_json)
    end

    test "handles missing required fields" do
      incomplete_response = %{"id" => 1}
      json_data = Jason.encode!(incomplete_response)

      # Our improved error handling now returns the request ID for better correlation
      assert {:error, 1, "Malformed response structure"} = Protocol.decode_response(json_data)
    end

    test "handles binary data" do
      response_data = %{
        "id" => 1,
        "success" => true,
        "result" => %{"status" => "ok"},
        "timestamp" => 1_234_567_890.0
      }

      json_binary = Jason.encode!(response_data) |> :erlang.term_to_binary()

      # Our improved error handling now decodes Erlang terms containing JSON
      assert {:ok, 1, %{"status" => "ok"}} = Protocol.decode_response(json_binary)
    end
  end

  describe "validate_request/1" do
    test "validates correct request structure" do
      request = %{
        "id" => 1,
        "command" => "ping",
        "args" => %{},
        "timestamp" => 1_234_567_890.0
      }

      assert :ok = Protocol.validate_request(request)
    end

    test "rejects request with missing id" do
      request = %{
        "command" => "ping",
        "args" => %{},
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :missing_id} = Protocol.validate_request(request)
    end

    test "rejects request with missing command" do
      request = %{
        "id" => 1,
        "args" => %{},
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :missing_command} = Protocol.validate_request(request)
    end

    test "accepts request with missing args (defaults to empty map)" do
      request = %{
        "id" => 1,
        "command" => "ping",
        "timestamp" => 1_234_567_890.0
      }

      assert :ok = Protocol.validate_request(request)
    end

    test "rejects request with invalid id type" do
      request = %{
        "id" => "not_a_number",
        "command" => "ping",
        "args" => %{},
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :invalid_id} = Protocol.validate_request(request)
    end
  end

  describe "validate_response/1" do
    test "validates successful response" do
      response = %{
        "id" => 1,
        "success" => true,
        "result" => %{"data" => "test"},
        "timestamp" => 1_234_567_890.0
      }

      assert :ok = Protocol.validate_response(response)
    end

    test "validates error response" do
      response = %{
        "id" => 1,
        "success" => false,
        "error" => "Error message",
        "timestamp" => 1_234_567_890.0
      }

      assert :ok = Protocol.validate_response(response)
    end

    test "rejects response with missing required fields" do
      response = %{
        "id" => 1,
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :missing_success} = Protocol.validate_response(response)
    end

    test "rejects successful response without result" do
      response = %{
        "id" => 1,
        "success" => true,
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :missing_result} = Protocol.validate_response(response)
    end

    test "rejects error response without error message" do
      response = %{
        "id" => 1,
        "success" => false,
        "timestamp" => 1_234_567_890.0
      }

      assert {:error, :missing_error} = Protocol.validate_response(response)
    end
  end
end

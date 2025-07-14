defmodule PortCommunicationTest do
  use ExUnit.Case
  require Logger

  @moduletag :port_test

  test "direct port communication with Port.command/2" do
    # Get Python environment
    {:ok, env_info} = DSPex.PythonBridge.EnvironmentCheck.validate_environment()

    python_path = env_info.python_path
    script_path = env_info.script_path

    # Start Python process in pool-worker mode
    # Note: Don't use :stderr_to_stdout with packet mode as it corrupts the packet stream
    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4},
      {:args, [script_path, "--mode", "pool-worker", "--worker-id", "test123"]}
    ]

    Logger.info("Starting Python process...")
    port = Port.open({:spawn_executable, python_path}, port_opts)
    Logger.info("Port opened: #{inspect(port)}")

    # Create a ping request using Protocol to add packet header
    request = DSPex.PythonBridge.Protocol.encode_request(
      0,
      :ping,
      %{initialization: true, worker_id: "test123"}
    )

    Logger.info("Request with packet header: #{inspect(request)}")
    Logger.info("Request byte size: #{byte_size(request)}")

    # Send using Port.command/2
    result = Port.command(port, request)
    Logger.info("Port.command/2 result: #{inspect(result)}")

    # Wait for response
    receive do
      {^port, {:data, data}} ->
        Logger.info("Received data from port!")
        Logger.info("Raw data: #{inspect(data, limit: :infinity)}")
        Logger.info("Data byte size: #{byte_size(data)}")

        # Try to decode using Protocol
        case DSPex.PythonBridge.Protocol.decode_response(data) do
          {:ok, request_id, response} ->
            Logger.info("Decoded response for request #{request_id}: #{inspect(response, pretty: true)}")
            assert request_id == 0
            assert response["status"] == "ok"

          {:error, reason} ->
            Logger.error("Failed to decode: #{inspect(reason)}")
            flunk("Protocol decode failed")
        end

      {^port, {:exit_status, status}} ->
        Logger.error("Port exited with status: #{status}")
        flunk("Port exited unexpectedly")

      other ->
        Logger.error("Unexpected message: #{inspect(other)}")
        flunk("Received unexpected message")
    after
      5000 ->
        port_info = Port.info(port)
        Logger.error("Timeout! Port info: #{inspect(port_info)}")
        flunk("No response received within 5 seconds")
    end

    # Cleanup
    Port.close(port)
  end
end

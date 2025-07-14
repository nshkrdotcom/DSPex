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
    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4},
      :stderr_to_stdout,
      {:args, [script_path, "--mode", "pool-worker", "--worker-id", "test123"]}
    ]

    Logger.info("Starting Python process...")
    port = Port.open({:spawn_executable, python_path}, port_opts)
    Logger.info("Port opened: #{inspect(port)}")

    # Create a ping request
    request =
      Jason.encode!(%{
        "id" => 0,
        "command" => "ping",
        "args" => %{"initialization" => true, "worker_id" => "test123"},
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Logger.info("Request JSON: #{request}")
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

        # Try to decode
        case Jason.decode(data) do
          {:ok, decoded} ->
            Logger.info("Decoded response: #{inspect(decoded, pretty: true)}")
            assert decoded["success"] == true

          {:error, reason} ->
            Logger.error("Failed to decode: #{inspect(reason)}")
            flunk("JSON decode failed")
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

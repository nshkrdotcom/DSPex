defmodule SimplePortTest do
  use ExUnit.Case
  require Logger

  @moduletag :simple_port_test

  test "test port communication with debug script" do
    python_path = System.find_executable("python3")
    script_path = Path.join(:code.priv_dir(:dspex), "python/test_port_communication.py")

    # Start the test script
    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4}
      # Don't use :stderr_to_stdout with packet mode
    ]

    Logger.info("Starting test script...")

    port =
      Port.open({:spawn_executable, python_path}, [
        {:args, [script_path]} | port_opts
      ])

    # Send test message
    message = Jason.encode!(%{"id" => 1, "command" => "test"})
    Logger.info("Sending message: #{message}")

    result = Port.command(port, message)
    Logger.info("Port.command result: #{result}")

    # Wait for response or debug output
    receive do
      {^port, {:data, data}} ->
        Logger.info("Received data: #{inspect(data)}")

        # Try to parse as JSON
        case Jason.decode(data) do
          {:ok, decoded} ->
            Logger.info("Decoded JSON: #{inspect(decoded)}")
            assert decoded["success"] == true

          {:error, _} ->
            # Might be stderr output
            Logger.info("Raw output: #{data}")
        end

      other ->
        Logger.error("Unexpected: #{inspect(other)}")
    after
      5000 ->
        Logger.error("Timeout!")
        flunk("No response")
    end

    Port.close(port)
  end
end

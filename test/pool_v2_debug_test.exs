defmodule PoolV2DebugTest do
  use ExUnit.Case
  require Logger

  @moduletag :debug_test

  test "debug pool checkout and communication" do
    Logger.configure(level: :debug)

    # Start minimal pool
    {:ok, pool_pid} =
      NimblePool.start_link(
        worker: {DSPex.PythonBridge.PoolWorkerV2, []},
        pool_size: 1,
        # Create worker immediately
        lazy: false
      )

    Logger.info("Pool started: #{inspect(pool_pid)}")
    # Give worker time to initialize
    Process.sleep(5000)

    # Try checkout
    result =
      NimblePool.checkout!(
        pool_pid,
        :anonymous,
        fn _from, worker_state ->
          Logger.info("Checked out worker: #{inspect(worker_state.worker_id)}")
          Logger.info("Port: #{inspect(worker_state.port)}")

          # Try to send a ping
          request =
            Jason.encode!(%{
              "id" => 123,
              "command" => "ping",
              "args" => %{},
              "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
            })

          Logger.info("Sending ping request...")
          cmd_result = Port.command(worker_state.port, request)
          Logger.info("Port.command result: #{inspect(cmd_result)}")

          # Wait for response
          receive do
            {port, {:data, data}} when port == worker_state.port ->
              Logger.info("Received response: #{inspect(data)}")
              {{:ok, data}, :ok}

            other ->
              Logger.error("Unexpected message: #{inspect(other)}")
              {{:error, :unexpected}, :ok}
          after
            5000 ->
              Logger.error("Timeout waiting for response")
              {{:error, :timeout}, :ok}
          end
        end,
        10_000
      )

    Logger.info("Checkout result: #{inspect(result)}")

    # Cleanup
    NimblePool.stop(pool_pid)
  end
end

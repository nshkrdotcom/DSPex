defmodule PoolWorkerV2InitTest do
  use ExUnit.Case
  require Logger

  alias DSPex.PythonBridge.PoolWorkerV2

  @moduletag :worker_init_test

  test "worker initialization with direct init_worker call" do
    Logger.configure(level: :debug)

    # Call init_worker directly
    Logger.info("Calling PoolWorkerV2.init_worker/1...")

    result = PoolWorkerV2.init_worker({})

    Logger.info("init_worker result: #{inspect(result)}")

    case result do
      {:ok, worker_state, pool_state} ->
        Logger.info("Worker initialized successfully!")
        Logger.info("Worker ID: #{worker_state.worker_id}")
        Logger.info("Health status: #{worker_state.health_status}")

        # Cleanup
        if worker_state.port do
          Port.close(worker_state.port)
        end

      error ->
        Logger.error("Worker initialization failed: #{inspect(error)}")
        flunk("Init worker failed")
    end
  end
end

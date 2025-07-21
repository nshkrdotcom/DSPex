defmodule DSPex.Test.PoolWorkerHelpers do
  @moduledoc """
  Helper functions for testing PoolWorker without actual Python processes.
  """

  alias DSPex.PythonBridge.PoolWorker

  @doc """
  Creates a mock worker state with all required fields.
  """
  def mock_worker_state(opts \\ []) do
    %PoolWorker{
      # Use a ref instead of self()
      port: Keyword.get(opts, :port, make_ref()),
      python_path: Keyword.get(opts, :python_path, "/usr/bin/python3"),
      script_path: Keyword.get(opts, :script_path, "test/script.py"),
      worker_id:
        Keyword.get(opts, :worker_id, "test_worker_#{System.unique_integer([:positive])}"),
      current_session: Keyword.get(opts, :current_session, nil),
      request_id: Keyword.get(opts, :request_id, 0),
      pending_requests: Keyword.get(opts, :pending_requests, %{}),
      stats: Keyword.get(opts, :stats, init_stats()),
      health_status: Keyword.get(opts, :health_status, :ready),
      started_at: Keyword.get(opts, :started_at, System.monotonic_time(:millisecond))
    }
  end

  @doc """
  Creates the initial stats map.
  """
  def init_stats do
    %{
      requests_handled: 0,
      errors: 0,
      sessions_served: 0,
      uptime_ms: 0,
      last_activity: System.monotonic_time(:millisecond),
      checkouts: 0
    }
  end

  @doc """
  Simulates a successful checkout without port operations.
  """
  def simulate_checkout(checkout_type, _from, worker_state, pool_state) do
    case checkout_type do
      {:session, session_id} ->
        updated_state = %{
          worker_state
          | current_session: session_id,
            stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
        }

        {:ok, nil, updated_state, pool_state}

      :anonymous ->
        updated_state = %{
          worker_state
          | stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
        }

        {:ok, nil, updated_state, pool_state}

      _ ->
        {:error, {:invalid_checkout_type, checkout_type}}
    end
  end

  @doc """
  Simulates a successful checkin without port operations.
  """
  def simulate_checkin(checkin_type, _from, worker_state, pool_state) do
    case checkin_type do
      :ok ->
        updated_state = %{
          worker_state
          | stats: Map.update(worker_state.stats, :requests_handled, 1, &(&1 + 1))
        }

        {:ok, updated_state, pool_state}

      {:error, _reason} ->
        updated_state = %{
          worker_state
          | stats: Map.update(worker_state.stats, :errors, 1, &(&1 + 1))
        }

        {:ok, updated_state, pool_state}

      :session_cleanup ->
        updated_state = %{worker_state | current_session: nil}
        {:ok, updated_state, pool_state}

      :close ->
        {:remove, :closed, pool_state}

      _ ->
        {:ok, worker_state, pool_state}
    end
  end
end

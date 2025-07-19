defmodule ElixirML.Process.ClientWorker do
  @moduledoc """
  Individual client worker for making HTTP requests.
  Handles rate limiting, retries, and connection management.
  """

  use GenServer

  defstruct [
    :client_id,
    :rate_limiter,
    :request_count,
    :last_request_time,
    :connection_pool
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    state = %__MODULE__{
      client_id: generate_client_id(),
      rate_limiter: %{requests_per_second: 10, current_window: 0, window_start: nil},
      request_count: 0,
      last_request_time: nil,
      connection_pool: nil
    }

    {:ok, state}
  end

  @doc """
  Make an HTTP request through this client.
  """
  def request(pid, method, url, headers \\ [], body \\ "", opts \\ []) do
    GenServer.call(pid, {:request, method, url, headers, body, opts}, 30_000)
  end

  @doc """
  Get client statistics.
  """
  def get_stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  # Server callbacks

  def handle_call({:request, method, url, headers, body, opts}, _from, state) do
    # Check rate limiting
    case check_rate_limit(state.rate_limiter) do
      {:ok, new_rate_limiter} ->
        # Execute the request
        result = execute_request(method, url, headers, body, opts)

        new_state = %{
          state
          | rate_limiter: new_rate_limiter,
            request_count: state.request_count + 1,
            last_request_time: System.monotonic_time(:millisecond)
        }

        {:reply, result, new_state}

      {:error, :rate_limited} ->
        {:reply, {:error, :rate_limited}, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      client_id: state.client_id,
      request_count: state.request_count,
      last_request_time: state.last_request_time,
      rate_limiter_status: state.rate_limiter
    }

    {:reply, stats, state}
  end

  # Private functions

  defp generate_client_id do
    "client_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp check_rate_limit(rate_limiter) do
    now = System.monotonic_time(:millisecond)
    # 1 second in milliseconds
    window_duration = 1000

    case rate_limiter.window_start do
      nil ->
        # First request
        new_rate_limiter = %{rate_limiter | current_window: 1, window_start: now}
        {:ok, new_rate_limiter}

      window_start ->
        if now - window_start >= window_duration do
          # New window
          new_rate_limiter = %{rate_limiter | current_window: 1, window_start: now}
          {:ok, new_rate_limiter}
        else
          # Same window
          if rate_limiter.current_window < rate_limiter.requests_per_second do
            new_rate_limiter = %{rate_limiter | current_window: rate_limiter.current_window + 1}
            {:ok, new_rate_limiter}
          else
            {:error, :rate_limited}
          end
        end
    end
  end

  defp execute_request(method, url, _headers, body, _opts) do
    # This is a mock implementation
    # In a real implementation, this would use Finch, HTTPoison, or similar

    try do
      # Simulate request processing time
      Process.sleep(Enum.random(10..100))

      # Mock response based on method and URL
      response =
        case method do
          :get ->
            %{
              status: 200,
              headers: [{"content-type", "application/json"}],
              body: Jason.encode!(%{status: "success", url: url})
            }

          :post ->
            %{
              status: 201,
              headers: [{"content-type", "application/json"}],
              body: Jason.encode!(%{status: "created", data: body})
            }

          _ ->
            %{
              status: 405,
              headers: [{"content-type", "application/json"}],
              body: Jason.encode!(%{error: "Method not allowed"})
            }
        end

      {:ok, response}
    rescue
      error ->
        {:error, error}
    end
  end
end

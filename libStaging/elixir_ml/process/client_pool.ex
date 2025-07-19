defmodule ElixirML.Process.ClientPool do
  @moduledoc """
  Pool of client processes for external API calls.
  Manages HTTP clients, rate limiting, and connection pooling.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 10)

    state = %{
      pool_size: pool_size,
      available_clients: [],
      busy_clients: %{},
      waiting_requests: :queue.new()
    }

    # Start initial client processes
    clients =
      Enum.map(1..pool_size, fn _i ->
        {:ok, pid} = start_client()
        pid
      end)

    {:ok, %{state | available_clients: clients}}
  end

  @doc """
  Get a client from the pool for making requests.
  """
  def checkout_client(timeout \\ 5000) do
    GenServer.call(__MODULE__, :checkout_client, timeout)
  end

  @doc """
  Return a client to the pool after use.
  """
  def checkin_client(client_pid) do
    GenServer.cast(__MODULE__, {:checkin_client, client_pid})
  end

  @doc """
  Get pool statistics.
  """
  def pool_stats do
    GenServer.call(__MODULE__, :pool_stats)
  end

  # Server callbacks

  def handle_call(:checkout_client, from, state) do
    case state.available_clients do
      [client | rest] ->
        # Client available, assign it
        busy_clients = Map.put(state.busy_clients, client, from)
        new_state = %{state | available_clients: rest, busy_clients: busy_clients}

        {:reply, {:ok, client}, new_state}

      [] ->
        # No clients available, queue the request
        waiting_requests = :queue.in(from, state.waiting_requests)
        new_state = %{state | waiting_requests: waiting_requests}

        {:noreply, new_state}
    end
  end

  def handle_call(:pool_stats, _from, state) do
    stats = %{
      pool_size: state.pool_size,
      available_clients: length(state.available_clients),
      busy_clients: map_size(state.busy_clients),
      waiting_requests: :queue.len(state.waiting_requests)
    }

    {:reply, stats, state}
  end

  def handle_cast({:checkin_client, client_pid}, state) do
    # Remove from busy clients
    busy_clients = Map.delete(state.busy_clients, client_pid)

    # Check if there are waiting requests
    case :queue.out(state.waiting_requests) do
      {{:value, waiting_from}, new_queue} ->
        # Assign client to waiting request
        GenServer.reply(waiting_from, {:ok, client_pid})
        new_busy_clients = Map.put(busy_clients, client_pid, waiting_from)

        new_state = %{state | busy_clients: new_busy_clients, waiting_requests: new_queue}

        {:noreply, new_state}

      {:empty, _} ->
        # No waiting requests, return client to available pool
        available_clients = [client_pid | state.available_clients]

        new_state = %{state | available_clients: available_clients, busy_clients: busy_clients}

        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Client process died, remove from tracking and start a new one
    busy_clients = Map.delete(state.busy_clients, pid)
    available_clients = List.delete(state.available_clients, pid)

    # Start replacement client
    {:ok, new_client} = start_client()

    new_state = %{
      state
      | available_clients: [new_client | available_clients],
        busy_clients: busy_clients
    }

    {:noreply, new_state}
  end

  # Private functions

  defp start_client do
    # This would start an actual HTTP client process
    # For now, we'll use a simple GenServer as a placeholder
    GenServer.start_link(ElixirML.Process.ClientWorker, [])
  end
end

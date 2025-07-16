defmodule DSPex.PythonBridge.ConcurrentSessionPool do
  @moduledoc """
  A session pool with truly concurrent worker initialization.
  Workers are pre-created in parallel before being managed by NimblePool.
  """
  
  use GenServer
  require Logger
  
  alias DSPex.PythonBridge.{
    ConcurrentPoolInitializer,
    PoolWorkerV2,
    SessionStore
  }
  
  defstruct [:pool, :workers, :pool_size, :name]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def execute_in_session(session_id, command, args, opts \\ []) do
    pool_name = opts[:pool_name] || __MODULE__
    GenServer.call(pool_name, {:execute_in_session, session_id, command, args, opts}, 
                   opts[:timeout] || 60_000)
  end
  
  def execute_anonymous(command, args, opts \\ []) do
    pool_name = opts[:pool_name] || __MODULE__
    GenServer.call(pool_name, {:execute_anonymous, command, args, opts},
                   opts[:timeout] || 60_000)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    pool_size = opts[:pool_size] || 4
    
    # Start SessionStore if needed
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    # Initialize all workers concurrently
    workers = ConcurrentPoolInitializer.initialize_workers_concurrently(pool_size)
    
    if length(workers) < pool_size do
      Logger.warning("Only #{length(workers)}/#{pool_size} workers initialized successfully")
    end
    
    # Create a simple pool to manage the pre-initialized workers
    {:ok, %__MODULE__{
      workers: :queue.from_list(workers),
      pool_size: length(workers),
      name: opts[:name] || __MODULE__
    }}
  end
  
  @impl true
  def handle_call({:execute_in_session, session_id, command, args, opts}, from, state) do
    case checkout_worker(state) do
      {:ok, worker, new_state} ->
        # Execute asynchronously
        Task.start(fn ->
          result = execute_on_worker(worker, session_id, command, args, opts)
          GenServer.reply(from, result)
          GenServer.cast(self(), {:checkin_worker, worker})
        end)
        {:noreply, new_state}
        
      {:error, :no_workers} ->
        {:reply, {:error, :no_available_workers}, state}
    end
  end
  
  @impl true
  def handle_call({:execute_anonymous, command, args, opts}, from, state) do
    session_id = "anon_#{:erlang.unique_integer([:positive])}"
    handle_call({:execute_in_session, session_id, command, args, opts}, from, state)
  end
  
  @impl true
  def handle_cast({:checkin_worker, worker}, state) do
    new_workers = :queue.in(worker, state.workers)
    {:noreply, %{state | workers: new_workers}}
  end
  
  # Private functions
  
  defp checkout_worker(state) do
    case :queue.out(state.workers) do
      {{:value, worker}, new_queue} ->
        {:ok, worker, %{state | workers: new_queue}}
      {:empty, _} ->
        {:error, :no_workers}
    end
  end
  
  defp execute_on_worker(worker, session_id, command, args, opts) do
    # Store session affinity
    SessionStore.store_worker_session(session_id, worker.id)
    
    # Execute command
    request = build_request(session_id, command, args)
    timeout = opts[:timeout] || 60_000
    
    case DSPex.PythonBridge.PythonPort.call(worker.port, request, timeout) do
      {:ok, response} ->
        process_response(response, session_id)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp build_request(session_id, command, args) do
    %{
      "command" => to_string(command),
      "args" => args,
      "session_id" => session_id,
      "id" => :erlang.unique_integer([:positive]),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
  
  defp process_response(%{"status" => "success"} = response, _session_id) do
    {:ok, response["result"]}
  end
  
  defp process_response(%{"status" => "error"} = response, _session_id) do
    {:error, {response["error_type"] || "unknown", response["message"]}}
  end
  
  defp process_response(response, _session_id) do
    {:ok, response}
  end
end
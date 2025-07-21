defmodule ElixirML.Process.PipelinePool do
  @moduledoc """
  Pool manager for pipeline execution workers.
  Manages concurrent pipeline executions with load balancing.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 5)

    state = %{
      pool_size: pool_size,
      workers: %{},
      queue: :queue.new(),
      stats: %{completed: 0, failed: 0, active: 0}
    }

    # Start worker processes
    workers =
      Enum.reduce(1..pool_size, %{}, fn i, acc ->
        {:ok, pid} = start_pipeline_worker()
        Map.put(acc, pid, %{id: i, status: :idle, current_pipeline: nil})
      end)

    {:ok, %{state | workers: workers}}
  end

  @doc """
  Submit a pipeline for execution.
  """
  def execute_pipeline(pipeline, inputs, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_pipeline, pipeline, inputs, opts}, 30_000)
  end

  @doc """
  Get pool statistics.
  """
  def pool_stats do
    GenServer.call(__MODULE__, :pool_stats)
  end

  # Server callbacks

  def handle_call({:execute_pipeline, pipeline, inputs, opts}, from, state) do
    case find_idle_worker(state.workers) do
      {:ok, worker_pid} ->
        # Execute immediately
        Task.start(fn ->
          result = execute_on_worker(worker_pid, pipeline, inputs, opts)
          GenServer.cast(__MODULE__, {:execution_complete, worker_pid, result})
          GenServer.reply(from, result)
        end)

        # Update worker status
        workers = put_in(state.workers[worker_pid].status, :busy)
        workers = put_in(workers[worker_pid].current_pipeline, pipeline.id)

        stats = %{state.stats | active: state.stats.active + 1}

        {:noreply, %{state | workers: workers, stats: stats}}

      :no_idle_workers ->
        # Queue the request
        queue_item = {from, pipeline, inputs, opts}
        new_queue = :queue.in(queue_item, state.queue)

        {:noreply, %{state | queue: new_queue}}
    end
  end

  def handle_call(:pool_stats, _from, state) do
    worker_stats =
      Enum.map(state.workers, fn {pid, worker_info} ->
        %{
          pid: pid,
          id: worker_info.id,
          status: worker_info.status,
          current_pipeline: worker_info.current_pipeline
        }
      end)

    stats = %{
      pool_size: state.pool_size,
      active_workers: count_active_workers(state.workers),
      idle_workers: count_idle_workers(state.workers),
      queued_requests: :queue.len(state.queue),
      execution_stats: state.stats,
      workers: worker_stats
    }

    {:reply, stats, state}
  end

  def handle_cast({:execution_complete, worker_pid, result}, state) do
    # Update worker status
    workers = put_in(state.workers[worker_pid].status, :idle)
    workers = put_in(workers[worker_pid].current_pipeline, nil)

    # Update stats
    stats =
      case result do
        {:ok, _} ->
          %{state.stats | completed: state.stats.completed + 1, active: state.stats.active - 1}

        {:error, _} ->
          %{state.stats | failed: state.stats.failed + 1, active: state.stats.active - 1}
      end

    # Process queued requests
    new_state = %{state | workers: workers, stats: stats}

    case :queue.out(state.queue) do
      {{:value, {from, pipeline, inputs, opts}}, new_queue} ->
        # Execute queued request
        Task.start(fn ->
          result = execute_on_worker(worker_pid, pipeline, inputs, opts)
          GenServer.cast(__MODULE__, {:execution_complete, worker_pid, result})
          GenServer.reply(from, result)
        end)

        workers = put_in(new_state.workers[worker_pid].status, :busy)
        workers = put_in(workers[worker_pid].current_pipeline, pipeline.id)
        stats = %{new_state.stats | active: new_state.stats.active + 1}

        {:noreply, %{new_state | workers: workers, stats: stats, queue: new_queue}}

      {:empty, _} ->
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Worker died, remove from pool and start replacement
    case Map.get(state.workers, pid) do
      nil ->
        {:noreply, state}

      worker_info ->
        # Start replacement worker
        {:ok, new_pid} = start_pipeline_worker()

        workers =
          state.workers
          |> Map.delete(pid)
          |> Map.put(new_pid, %{worker_info | status: :idle, current_pipeline: nil})

        {:noreply, %{state | workers: workers}}
    end
  end

  # Private functions

  defp start_pipeline_worker do
    # Start a simple worker process
    # In practice, this might be a more sophisticated pipeline execution process
    {:ok, spawn_link(fn -> pipeline_worker_loop() end)}
  end

  defp pipeline_worker_loop do
    receive do
      {:execute, pipeline, inputs, opts, reply_to} ->
        result = ElixirML.Process.Pipeline.execute(pipeline, inputs, opts)
        send(reply_to, {:result, result})
        pipeline_worker_loop()

      :stop ->
        :ok
    end
  end

  defp find_idle_worker(workers) do
    case Enum.find(workers, fn {_pid, worker_info} ->
           worker_info.status == :idle
         end) do
      {pid, _} -> {:ok, pid}
      nil -> :no_idle_workers
    end
  end

  defp execute_on_worker(worker_pid, pipeline, inputs, opts) do
    send(worker_pid, {:execute, pipeline, inputs, opts, self()})

    receive do
      {:result, result} -> result
    after
      30_000 -> {:error, :timeout}
    end
  end

  defp count_active_workers(workers) do
    Enum.count(workers, fn {_pid, worker_info} ->
      worker_info.status == :busy
    end)
  end

  defp count_idle_workers(workers) do
    Enum.count(workers, fn {_pid, worker_info} ->
      worker_info.status == :idle
    end)
  end
end

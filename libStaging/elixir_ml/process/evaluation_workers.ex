defmodule ElixirML.Process.EvaluationWorkers do
  @moduledoc """
  Pool of workers for evaluating ML model performance.
  Handles batch evaluation, metrics calculation, and result aggregation.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    worker_count = Keyword.get(opts, :worker_count, 3)

    state = %{
      worker_count: worker_count,
      workers: %{},
      evaluation_queue: :queue.new(),
      completed_evaluations: []
    }

    # Start evaluation workers
    workers =
      Enum.reduce(1..worker_count, %{}, fn i, acc ->
        {:ok, pid} = start_evaluation_worker()
        Map.put(acc, pid, %{id: i, status: :idle})
      end)

    {:ok, %{state | workers: workers}}
  end

  @doc """
  Submit a configuration for evaluation.
  """
  def evaluate_configuration(configuration, evaluation_data, opts \\ []) do
    GenServer.call(__MODULE__, {:evaluate, configuration, evaluation_data, opts})
  end

  @doc """
  Get evaluation results for a configuration.
  """
  def get_evaluation_results(configuration_id) do
    GenServer.call(__MODULE__, {:get_results, configuration_id})
  end

  @doc """
  Get worker pool statistics.
  """
  def worker_stats do
    GenServer.call(__MODULE__, :worker_stats)
  end

  # Server callbacks

  def handle_call({:evaluate, configuration, evaluation_data, opts}, from, state) do
    evaluation_id = generate_evaluation_id()

    case find_idle_worker(state.workers) do
      {:ok, worker_pid} ->
        # Assign to worker
        Task.start(fn ->
          result = perform_evaluation(worker_pid, configuration, evaluation_data, opts)
          GenServer.cast(__MODULE__, {:evaluation_complete, worker_pid, evaluation_id, result})
          GenServer.reply(from, {:ok, evaluation_id, result})
        end)

        workers = put_in(state.workers[worker_pid].status, :busy)
        {:noreply, %{state | workers: workers}}

      :no_idle_workers ->
        # Queue the evaluation
        queue_item = {from, evaluation_id, configuration, evaluation_data, opts}
        new_queue = :queue.in(queue_item, state.evaluation_queue)

        {:noreply, %{state | evaluation_queue: new_queue}}
    end
  end

  def handle_call({:get_results, configuration_id}, _from, state) do
    result =
      Enum.find(state.completed_evaluations, fn eval ->
        eval.configuration_id == configuration_id
      end)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      evaluation -> {:reply, {:ok, evaluation.result}, state}
    end
  end

  def handle_call(:worker_stats, _from, state) do
    stats = %{
      total_workers: state.worker_count,
      idle_workers: count_idle_workers(state.workers),
      busy_workers: count_busy_workers(state.workers),
      queued_evaluations: :queue.len(state.evaluation_queue),
      completed_evaluations: length(state.completed_evaluations)
    }

    {:reply, stats, state}
  end

  def handle_cast({:evaluation_complete, worker_pid, evaluation_id, result}, state) do
    # Mark worker as idle
    workers = put_in(state.workers[worker_pid].status, :idle)

    # Store completed evaluation
    completed_eval = %{
      id: evaluation_id,
      result: result,
      completed_at: System.monotonic_time(:millisecond)
    }

    completed_evaluations =
      [completed_eval | state.completed_evaluations]
      # Keep last 100 evaluations
      |> Enum.take(100)

    new_state = %{state | workers: workers, completed_evaluations: completed_evaluations}

    # Process queued evaluations
    case :queue.out(state.evaluation_queue) do
      {{:value, {from, queued_id, config, eval_data, opts}}, new_queue} ->
        # Process queued evaluation
        Task.start(fn ->
          result = perform_evaluation(worker_pid, config, eval_data, opts)
          GenServer.cast(__MODULE__, {:evaluation_complete, worker_pid, queued_id, result})
          GenServer.reply(from, {:ok, queued_id, result})
        end)

        workers = put_in(new_state.workers[worker_pid].status, :busy)

        {:noreply, %{new_state | workers: workers, evaluation_queue: new_queue}}

      {:empty, _} ->
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Worker died, replace it
    case Map.get(state.workers, pid) do
      nil ->
        {:noreply, state}

      worker_info ->
        {:ok, new_pid} = start_evaluation_worker()

        workers =
          state.workers
          |> Map.delete(pid)
          |> Map.put(new_pid, %{worker_info | status: :idle})

        {:noreply, %{state | workers: workers}}
    end
  end

  # Private functions

  defp start_evaluation_worker do
    {:ok, spawn_link(fn -> evaluation_worker_loop() end)}
  end

  defp evaluation_worker_loop do
    receive do
      {:evaluate, config, eval_data, opts, reply_to} ->
        result = mock_evaluation(config, eval_data, opts)
        send(reply_to, {:evaluation_result, result})
        evaluation_worker_loop()

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

  defp perform_evaluation(worker_pid, configuration, evaluation_data, opts) do
    send(worker_pid, {:evaluate, configuration, evaluation_data, opts, self()})

    receive do
      {:evaluation_result, result} -> result
    after
      30_000 -> {:error, :timeout}
    end
  end

  defp mock_evaluation(_configuration, _evaluation_data, _opts) do
    # Mock evaluation - in practice this would run actual ML evaluation
    # Simulate evaluation time
    Process.sleep(Enum.random(100..500))

    %{
      accuracy: :rand.uniform(),
      precision: :rand.uniform(),
      recall: :rand.uniform(),
      f1_score: :rand.uniform(),
      latency_ms: Enum.random(50..200),
      cost_estimate: :rand.uniform() * 0.01
    }
  end

  defp count_idle_workers(workers) do
    Enum.count(workers, fn {_pid, worker_info} ->
      worker_info.status == :idle
    end)
  end

  defp count_busy_workers(workers) do
    Enum.count(workers, fn {_pid, worker_info} ->
      worker_info.status == :busy
    end)
  end

  defp generate_evaluation_id do
    "eval_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end

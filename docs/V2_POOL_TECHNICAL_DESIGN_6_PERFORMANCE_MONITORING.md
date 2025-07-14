# V2 Pool Technical Design Series: Document 6 - Performance Optimization and Monitoring

## Overview

This document details the performance optimization strategies and comprehensive monitoring system for Phase 5. It covers pool configuration tuning, pre-warming strategies, telemetry integration, and operational dashboards to achieve production-ready performance.

## Performance Goals

### Target Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Operation Latency (p50) | <50ms | End-to-end pool operation |
| Operation Latency (p99) | <100ms | Including retries |
| Throughput | >1000 ops/sec | Per pool instance |
| Pool Utilization | 60-80% | Worker busy time |
| Error Rate | <0.1% | Excluding client errors |
| Recovery Time | <500ms | Worker failure to recovery |
| Memory per Worker | <50MB | Python process RSS |
| CPU per Worker | <10% | Average during operation |

## Pool Configuration Optimization

### Dynamic Pool Sizing

**File:** `lib/dspex/python_bridge/pool_optimizer.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.PoolOptimizer do
  @moduledoc """
  Dynamically optimizes pool configuration based on workload patterns.
  """
  
  use GenServer
  require Logger
  
  @optimization_interval 60_000  # 1 minute
  @history_window 300_000       # 5 minutes
  
  defstruct [
    :pool_name,
    :current_config,
    :metrics_history,
    :optimization_enabled,
    :last_optimization
  ]
  
  def start_link(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    GenServer.start_link(__MODULE__, opts, name: :"optimizer_#{pool_name}")
  end
  
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    
    state = %__MODULE__{
      pool_name: pool_name,
      current_config: load_initial_config(pool_name),
      metrics_history: :queue.new(),
      optimization_enabled: Keyword.get(opts, :enabled, true),
      last_optimization: System.monotonic_time(:millisecond)
    }
    
    if state.optimization_enabled do
      schedule_optimization()
    end
    
    {:ok, state}
  end
  
  @doc "Gets optimized pool configuration"
  def get_optimized_config(pool_name) do
    GenServer.call(:"optimizer_#{pool_name}", :get_config)
  end
  
  @doc "Records pool metrics for optimization"
  def record_metrics(pool_name, metrics) do
    GenServer.cast(:"optimizer_#{pool_name}", {:record_metrics, metrics})
  end
  
  # Server callbacks
  
  def handle_call(:get_config, _from, state) do
    {:reply, state.current_config, state}
  end
  
  def handle_cast({:record_metrics, metrics}, state) do
    timestamped_metrics = Map.put(metrics, :timestamp, System.monotonic_time(:millisecond))
    
    # Add to history, removing old entries
    updated_history = add_to_history(state.metrics_history, timestamped_metrics, @history_window)
    
    {:noreply, %{state | metrics_history: updated_history}}
  end
  
  def handle_info(:optimize, state) do
    if state.optimization_enabled do
      new_state = perform_optimization(state)
      schedule_optimization()
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  # Optimization logic
  
  defp perform_optimization(state) do
    metrics = analyze_metrics(state.metrics_history)
    
    case determine_optimal_config(metrics, state.current_config) do
      {:ok, new_config} when new_config != state.current_config ->
        apply_config_changes(state.pool_name, new_config)
        
        Logger.info("Pool #{state.pool_name} optimized: #{inspect(new_config)}")
        
        %{state | 
          current_config: new_config,
          last_optimization: System.monotonic_time(:millisecond)
        }
        
      _ ->
        state
    end
  end
  
  defp analyze_metrics(history) do
    metrics_list = :queue.to_list(history)
    
    if length(metrics_list) < 10 do
      # Not enough data
      %{}
    else
      %{
        avg_queue_depth: average(metrics_list, & &1.queue_depth),
        avg_utilization: average(metrics_list, & &1.utilization),
        avg_wait_time: average(metrics_list, & &1.avg_wait_time),
        peak_demand: Enum.max_by(metrics_list, & &1.active_checkouts).active_checkouts,
        error_rate: average(metrics_list, & &1.error_rate),
        throughput: average(metrics_list, & &1.throughput)
      }
    end
  end
  
  defp determine_optimal_config(metrics, current_config) do
    cond do
      # High utilization and queue depth - need more workers
      metrics[:avg_utilization] > 0.9 and metrics[:avg_queue_depth] > 0 ->
        scale_up(current_config, metrics)
        
      # Low utilization - can reduce workers
      metrics[:avg_utilization] < 0.3 and current_config.pool_size > current_config.min_pool_size ->
        scale_down(current_config, metrics)
        
      # High wait times - need overflow
      metrics[:avg_wait_time] > 100 and metrics[:avg_queue_depth] > 0 ->
        increase_overflow(current_config, metrics)
        
      # Everything is fine
      true ->
        {:ok, current_config}
    end
  end
  
  defp scale_up(config, metrics) do
    new_size = min(
      config.pool_size + calculate_scale_step(metrics),
      config.max_pool_size
    )
    
    {:ok, %{config | pool_size: new_size}}
  end
  
  defp scale_down(config, metrics) do
    new_size = max(
      config.pool_size - 1,
      config.min_pool_size
    )
    
    {:ok, %{config | pool_size: new_size}}
  end
  
  defp increase_overflow(config, metrics) do
    new_overflow = min(
      config.max_overflow + 1,
      config.pool_size  # Don't exceed base pool size
    )
    
    {:ok, %{config | max_overflow: new_overflow}}
  end
  
  defp calculate_scale_step(metrics) do
    # Scale more aggressively with higher queue depth
    base_step = 1
    queue_factor = min(metrics[:avg_queue_depth] / 5, 3)
    
    round(base_step * (1 + queue_factor))
  end
  
  defp apply_config_changes(pool_name, new_config) do
    # This would integrate with pool supervisor to adjust worker count
    send(pool_name, {:update_config, new_config})
  end
  
  defp add_to_history(queue, item, max_age) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - max_age
    
    # Remove old items and add new one
    queue
    |> :queue.to_list()
    |> Enum.filter(& &1.timestamp > cutoff)
    |> :queue.from_list()
    |> :queue.in(item)
  end
  
  defp average(list, fun) do
    values = Enum.map(list, fun)
    Enum.sum(values) / length(values)
  end
  
  defp load_initial_config(pool_name) do
    %{
      pool_size: 5,
      min_pool_size: 2,
      max_pool_size: 20,
      max_overflow: 5,
      strategy: :lifo
    }
  end
  
  defp schedule_optimization do
    Process.send_after(self(), :optimize, @optimization_interval)
  end
end
```

### Pre-warming Strategies

**File:** `lib/dspex/python_bridge/pool_warmer.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.PoolWarmer do
  @moduledoc """
  Pre-warms pool workers for optimal performance.
  """
  
  require Logger
  
  @warm_up_commands [
    # Load core modules
    {:execute_code, "import dspy; import json; import sys"},
    
    # Initialize common objects
    {:execute_code, "lm = dspy.OpenAI(model='gpt-3.5-turbo')"},
    
    # Pre-compile common signatures
    {:create_program, %{
      "signature" => %{
        "inputs" => [%{"name" => "question", "type" => "string"}],
        "outputs" => [%{"name" => "answer", "type" => "string"}]
      }
    }},
    
    # Warm JIT caches
    {:execute_code, "dspy.ChainOfThought('question -> answer')"}
  ]
  
  @doc """
  Warms up a pool by executing initialization commands on all workers.
  """
  def warm_pool(pool_name, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :parallel)
    commands = Keyword.get(opts, :commands, @warm_up_commands)
    
    Logger.info("Starting pool warm-up for #{pool_name} with strategy: #{strategy}")
    
    start_time = System.monotonic_time(:millisecond)
    
    result = case strategy do
      :parallel -> warm_parallel(pool_name, commands)
      :sequential -> warm_sequential(pool_name, commands)
      :staged -> warm_staged(pool_name, commands)
    end
    
    duration = System.monotonic_time(:millisecond) - start_time
    
    Logger.info("Pool warm-up completed in #{duration}ms")
    
    emit_warmup_metrics(pool_name, strategy, duration, result)
    
    result
  end
  
  defp warm_parallel(pool_name, commands) do
    # Get pool stats to know how many workers to warm
    {:ok, stats} = get_pool_stats(pool_name)
    worker_count = stats.pool_size
    
    # Create tasks for each worker
    tasks = for worker_index <- 0..(worker_count - 1) do
      Task.async(fn ->
        warm_worker(pool_name, worker_index, commands)
      end)
    end
    
    # Wait for all to complete
    results = Task.await_many(tasks, 30_000)
    
    aggregate_results(results)
  end
  
  defp warm_sequential(pool_name, commands) do
    {:ok, stats} = get_pool_stats(pool_name)
    
    results = for worker_index <- 0..(stats.pool_size - 1) do
      warm_worker(pool_name, worker_index, commands)
    end
    
    aggregate_results(results)
  end
  
  defp warm_staged(pool_name, commands) do
    # Warm workers in stages to avoid overload
    {:ok, stats} = get_pool_stats(pool_name)
    batch_size = max(1, div(stats.pool_size, 3))
    
    stats.pool_size
    |> Range.new(0)
    |> Enum.chunk_every(batch_size)
    |> Enum.map(fn batch ->
      tasks = Enum.map(batch, fn worker_index ->
        Task.async(fn -> warm_worker(pool_name, worker_index, commands) end)
      end)
      
      Task.await_many(tasks, 15_000)
    end)
    |> List.flatten()
    |> aggregate_results()
  end
  
  defp warm_worker(pool_name, worker_index, commands) do
    session_id = "warmup_worker_#{worker_index}"
    
    results = Enum.map(commands, fn {command, args} ->
      start = System.monotonic_time(:microsecond)
      
      result = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
        session_id,
        command,
        args,
        pool_name: pool_name,
        timeout: 10_000
      )
      
      duration = System.monotonic_time(:microsecond) - start
      
      {command, result, duration}
    end)
    
    %{
      worker_index: worker_index,
      results: results,
      success: Enum.all?(results, fn {_, result, _} -> match?({:ok, _}, result) end)
    }
  end
  
  defp aggregate_results(worker_results) do
    total_workers = length(worker_results)
    successful_workers = Enum.count(worker_results, & &1.success)
    
    command_stats = worker_results
    |> Enum.flat_map(& &1.results)
    |> Enum.group_by(fn {command, _, _} -> command end)
    |> Enum.map(fn {command, results} ->
      durations = Enum.map(results, fn {_, _, duration} -> duration end)
      failures = Enum.count(results, fn {_, result, _} -> match?({:error, _}, result) end)
      
      {command, %{
        avg_duration_us: Enum.sum(durations) / length(durations),
        max_duration_us: Enum.max(durations),
        failure_count: failures
      }}
    end)
    |> Enum.into(%{})
    
    %{
      total_workers: total_workers,
      successful_workers: successful_workers,
      success_rate: successful_workers / total_workers,
      command_stats: command_stats
    }
  end
  
  defp get_pool_stats(pool_name) do
    # Get stats from pool monitor
    {:ok, %{pool_size: 5}}  # Placeholder
  end
  
  defp emit_warmup_metrics(pool_name, strategy, duration, result) do
    :telemetry.execute(
      [:dspex, :pool, :warmup],
      %{
        duration_ms: duration,
        success_rate: result.success_rate
      },
      %{
        pool_name: pool_name,
        strategy: strategy,
        worker_count: result.total_workers
      }
    )
  end
end
```

## Telemetry Integration

**File:** `lib/dspex/python_bridge/telemetry.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.Telemetry do
  @moduledoc """
  Telemetry event definitions and handlers for pool monitoring.
  """
  
  require Logger
  
  @events [
    # Pool lifecycle events
    [:dspex, :pool, :init],
    [:dspex, :pool, :terminate],
    
    # Worker events
    [:dspex, :pool, :worker, :init],
    [:dspex, :pool, :worker, :checkout],
    [:dspex, :pool, :worker, :checkin],
    [:dspex, :pool, :worker, :terminate],
    [:dspex, :pool, :worker, :health_check],
    
    # Operation events
    [:dspex, :pool, :operation, :start],
    [:dspex, :pool, :operation, :stop],
    [:dspex, :pool, :operation, :exception],
    
    # Performance events
    [:dspex, :pool, :queue, :depth],
    [:dspex, :pool, :utilization],
    
    # Error events
    [:dspex, :pool, :error],
    [:dspex, :pool, :recovery]
  ]
  
  @doc "Returns all telemetry event names"
  def events, do: @events
  
  @doc "Attaches default handlers for logging and metrics"
  def attach_default_handlers do
    attach_logger_handler()
    attach_metrics_handler()
    attach_reporter_handler()
  end
  
  defp attach_logger_handler do
    :telemetry.attach_many(
      "dspex-pool-logger",
      [
        [:dspex, :pool, :worker, :init],
        [:dspex, :pool, :worker, :terminate],
        [:dspex, :pool, :error]
      ],
      &handle_log_event/4,
      nil
    )
  end
  
  defp attach_metrics_handler do
    :telemetry.attach_many(
      "dspex-pool-metrics",
      events(),
      &handle_metrics_event/4,
      nil
    )
  end
  
  defp attach_reporter_handler do
    :telemetry.attach(
      "dspex-pool-reporter",
      [:dspex, :pool, :operation, :stop],
      &handle_reporter_event/4,
      %{reporter: DSPex.PythonBridge.MetricsReporter}
    )
  end
  
  # Event handlers
  
  defp handle_log_event([:dspex, :pool, :worker, :init], measurements, metadata, _config) do
    Logger.info("Worker initialized", 
      worker_id: metadata.worker_id,
      duration_ms: measurements.duration
    )
  end
  
  defp handle_log_event([:dspex, :pool, :worker, :terminate], _measurements, metadata, _config) do
    Logger.info("Worker terminated",
      worker_id: metadata.worker_id,
      reason: metadata.reason
    )
  end
  
  defp handle_log_event([:dspex, :pool, :error], _measurements, metadata, _config) do
    Logger.error("Pool error: #{metadata.error_type}",
      error: metadata.error,
      context: metadata.context
    )
  end
  
  defp handle_metrics_event(event, measurements, metadata, _config) do
    # Store metrics in ETS or external system
    store_metric(event, measurements, metadata)
  end
  
  defp handle_reporter_event([:dspex, :pool, :operation, :stop], measurements, metadata, config) do
    config.reporter.report_operation(
      metadata.operation,
      measurements.duration,
      metadata
    )
  end
  
  defp store_metric(event, measurements, metadata) do
    # Implementation would store in ETS, StatsD, Prometheus, etc.
    :ok
  end
  
  @doc "Helper to emit operation events with timing"
  def span(event_prefix, metadata, fun) do
    start_time = System.monotonic_time()
    start_metadata = Map.put(metadata, :start_time, System.os_time())
    
    :telemetry.execute(event_prefix ++ [:start], %{}, start_metadata)
    
    try do
      result = fun.()
      
      duration = System.monotonic_time() - start_time
      
      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: duration},
        Map.put(start_metadata, :result, :ok)
      )
      
      result
    catch
      kind, reason ->
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: duration},
          Map.merge(start_metadata, %{
            kind: kind,
            reason: reason,
            stacktrace: __STACKTRACE__
          })
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
end
```

### Metrics Collection

**File:** `lib/dspex/python_bridge/metrics_collector.ex` (new file)

```elixir
defmodule DSPex.PythonBridge.MetricsCollector do
  @moduledoc """
  Collects and aggregates pool metrics for monitoring.
  """
  
  use GenServer
  require Logger
  
  @collection_interval 1_000  # 1 second
  @aggregation_window 60_000  # 1 minute
  
  defstruct [
    :pool_name,
    :metrics_table,
    :current_metrics,
    :collection_enabled
  ]
  
  def start_link(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    GenServer.start_link(__MODULE__, opts, name: :"metrics_#{pool_name}")
  end
  
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    
    # Create ETS table for metrics
    table = :ets.new(:"metrics_#{pool_name}", [
      :set,
      :public,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])
    
    state = %__MODULE__{
      pool_name: pool_name,
      metrics_table: table,
      current_metrics: init_metrics(),
      collection_enabled: true
    }
    
    # Subscribe to telemetry events
    subscribe_to_events(pool_name)
    
    # Start collection timer
    schedule_collection()
    
    {:ok, state}
  end
  
  @doc "Gets current metrics snapshot"
  def get_metrics(pool_name) do
    GenServer.call(:"metrics_#{pool_name}", :get_metrics)
  end
  
  @doc "Gets metrics history"
  def get_history(pool_name, duration \\ 300_000) do
    GenServer.call(:"metrics_#{pool_name}", {:get_history, duration})
  end
  
  # Server callbacks
  
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_current_metrics(state)
    {:reply, metrics, state}
  end
  
  def handle_call({:get_history, duration}, _from, state) do
    history = get_metrics_history(state.metrics_table, duration)
    {:reply, history, state}
  end
  
  def handle_info(:collect, state) do
    if state.collection_enabled do
      new_state = collect_metrics(state)
      schedule_collection()
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_info({:telemetry_event, event, measurements, metadata}, state) do
    new_state = update_metrics(state, event, measurements, metadata)
    {:noreply, new_state}
  end
  
  # Metric collection
  
  defp collect_metrics(state) do
    # Get pool stats
    pool_stats = get_pool_stats(state.pool_name)
    
    # Calculate derived metrics
    metrics = %{
      timestamp: System.os_time(:millisecond),
      pool_size: pool_stats.pool_size,
      active_workers: pool_stats.active_workers,
      idle_workers: pool_stats.idle_workers,
      queue_depth: pool_stats.queue_depth,
      utilization: calculate_utilization(pool_stats),
      throughput: calculate_throughput(state.current_metrics),
      avg_latency: calculate_avg_latency(state.current_metrics),
      p99_latency: calculate_percentile(state.current_metrics.latencies, 99),
      error_rate: calculate_error_rate(state.current_metrics),
      health_score: calculate_health_score(pool_stats, state.current_metrics)
    }
    
    # Store in ETS
    :ets.insert(state.metrics_table, {metrics.timestamp, metrics})
    
    # Clean old entries
    cleanup_old_metrics(state.metrics_table)
    
    # Reset current counters
    %{state | current_metrics: reset_counters(state.current_metrics)}
  end
  
  defp update_metrics(state, event, measurements, metadata) do
    case event do
      [:dspex, :pool, :operation, :stop] ->
        update_operation_metrics(state, measurements, metadata)
        
      [:dspex, :pool, :worker, :checkout] ->
        update_checkout_metrics(state, measurements, metadata)
        
      [:dspex, :pool, :worker, :checkin] ->
        update_checkin_metrics(state, measurements, metadata)
        
      [:dspex, :pool, :error] ->
        update_error_metrics(state, measurements, metadata)
        
      _ ->
        state
    end
  end
  
  defp update_operation_metrics(state, measurements, metadata) do
    latency = measurements.duration / 1_000  # Convert to ms
    
    updated_metrics = state.current_metrics
    |> Map.update!(:total_operations, &(&1 + 1))
    |> Map.update!(:latencies, &([latency | &1]))
    
    %{state | current_metrics: updated_metrics}
  end
  
  defp update_checkout_metrics(state, measurements, _metadata) do
    wait_time = measurements.wait_time / 1_000  # Convert to ms
    
    updated_metrics = state.current_metrics
    |> Map.update!(:total_checkouts, &(&1 + 1))
    |> Map.update!(:checkout_wait_times, &([wait_time | &1]))
    
    %{state | current_metrics: updated_metrics}
  end
  
  defp update_checkin_metrics(state, _measurements, metadata) do
    updated_metrics = case metadata.result do
      :ok ->
        Map.update!(state.current_metrics, :successful_operations, &(&1 + 1))
        
      {:error, _} ->
        Map.update!(state.current_metrics, :failed_operations, &(&1 + 1))
    end
    
    %{state | current_metrics: updated_metrics}
  end
  
  defp update_error_metrics(state, _measurements, metadata) do
    updated_metrics = state.current_metrics
    |> Map.update!(:errors, &Map.update(&1, metadata.error_type, 1, fn c -> c + 1 end))
    
    %{state | current_metrics: updated_metrics}
  end
  
  # Metric calculations
  
  defp calculate_utilization(pool_stats) do
    total_workers = pool_stats.pool_size
    
    if total_workers > 0 do
      pool_stats.active_workers / total_workers
    else
      0.0
    end
  end
  
  defp calculate_throughput(metrics) do
    # Operations per second
    metrics.total_operations
  end
  
  defp calculate_avg_latency(metrics) do
    if length(metrics.latencies) > 0 do
      Enum.sum(metrics.latencies) / length(metrics.latencies)
    else
      0.0
    end
  end
  
  defp calculate_percentile(values, percentile) when length(values) > 0 do
    sorted = Enum.sort(values)
    index = round(length(sorted) * percentile / 100) - 1
    Enum.at(sorted, max(0, index), 0.0)
  end
  defp calculate_percentile(_, _), do: 0.0
  
  defp calculate_error_rate(metrics) do
    total = metrics.total_operations
    
    if total > 0 do
      metrics.failed_operations / total
    else
      0.0
    end
  end
  
  defp calculate_health_score(pool_stats, metrics) do
    # Composite health score (0-100)
    utilization_score = min(100, pool_stats.utilization * 100)
    error_score = max(0, 100 - calculate_error_rate(metrics) * 100)
    latency_score = max(0, 100 - metrics.avg_latency)
    
    (utilization_score * 0.3 + error_score * 0.5 + latency_score * 0.2)
  end
  
  # Helper functions
  
  defp init_metrics do
    %{
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      total_checkouts: 0,
      latencies: [],
      checkout_wait_times: [],
      errors: %{}
    }
  end
  
  defp reset_counters(metrics) do
    %{metrics |
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      total_checkouts: 0,
      latencies: [],
      checkout_wait_times: []
    }
  end
  
  defp get_pool_stats(pool_name) do
    # Get from pool monitor
    %{
      pool_size: 5,
      active_workers: 3,
      idle_workers: 2,
      queue_depth: 0,
      utilization: 0.6
    }
  end
  
  defp get_metrics_history(table, duration) do
    cutoff = System.os_time(:millisecond) - duration
    
    :ets.select(table, [
      {{:"$1", :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}
    ])
  end
  
  defp cleanup_old_metrics(table) do
    cutoff = System.os_time(:millisecond) - @aggregation_window * 5
    
    :ets.select_delete(table, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
  
  defp subscribe_to_events(pool_name) do
    events = [
      [:dspex, :pool, :operation, :stop],
      [:dspex, :pool, :worker, :checkout],
      [:dspex, :pool, :worker, :checkin],
      [:dspex, :pool, :error]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "metrics-#{pool_name}-#{Enum.join(event, "-")}",
        event,
        fn e, m, md, _config ->
          send(self(), {:telemetry_event, e, m, md})
        end,
        nil
      )
    end)
  end
  
  defp schedule_collection do
    Process.send_after(self(), :collect, @collection_interval)
  end
end
```

## Operational Dashboard

**File:** `lib/dspex_web/live/pool_dashboard_live.ex` (example)

```elixir
defmodule DSPexWeb.PoolDashboardLive do
  @moduledoc """
  LiveView dashboard for pool monitoring.
  """
  
  use Phoenix.LiveView
  
  @refresh_interval 1_000
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end
    
    pools = get_active_pools()
    
    socket = socket
    |> assign(:pools, pools)
    |> assign(:selected_pool, List.first(pools))
    |> assign(:metrics, %{})
    |> assign(:history_duration, 300_000)  # 5 minutes
    |> load_metrics()
    
    {:ok, socket}
  end
  
  def handle_info(:refresh, socket) do
    {:noreply, load_metrics(socket)}
  end
  
  def handle_event("select_pool", %{"pool" => pool_name}, socket) do
    socket = socket
    |> assign(:selected_pool, String.to_atom(pool_name))
    |> load_metrics()
    
    {:noreply, socket}
  end
  
  def handle_event("change_duration", %{"duration" => duration}, socket) do
    socket = socket
    |> assign(:history_duration, String.to_integer(duration))
    |> load_metrics()
    
    {:noreply, socket}
  end
  
  defp load_metrics(socket) do
    pool = socket.assigns.selected_pool
    
    if pool do
      metrics = DSPex.PythonBridge.MetricsCollector.get_metrics(pool)
      history = DSPex.PythonBridge.MetricsCollector.get_history(
        pool, 
        socket.assigns.history_duration
      )
      
      socket
      |> assign(:metrics, metrics)
      |> assign(:history, history)
      |> assign(:chart_data, prepare_chart_data(history))
    else
      socket
    end
  end
  
  defp prepare_chart_data(history) do
    %{
      latency: prepare_time_series(history, :avg_latency),
      throughput: prepare_time_series(history, :throughput),
      utilization: prepare_time_series(history, :utilization),
      errors: prepare_time_series(history, :error_rate)
    }
  end
  
  defp prepare_time_series(history, field) do
    history
    |> Enum.map(fn metrics ->
      %{
        time: metrics.timestamp,
        value: Map.get(metrics, field, 0)
      }
    end)
    |> Jason.encode!()
  end
  
  defp get_active_pools do
    # Get list of active pools
    [:pool_1, :pool_2, :pool_3]
  end
  
  def render(assigns) do
    ~H"""
    <div class="pool-dashboard">
      <h1>Pool Monitoring Dashboard</h1>
      
      <div class="controls">
        <select phx-change="select_pool">
          <%= for pool <- @pools do %>
            <option value={pool} selected={pool == @selected_pool}>
              <%= pool %>
            </option>
          <% end %>
        </select>
        
        <select phx-change="change_duration">
          <option value="60000">1 minute</option>
          <option value="300000" selected>5 minutes</option>
          <option value="900000">15 minutes</option>
          <option value="3600000">1 hour</option>
        </select>
      </div>
      
      <div class="metrics-grid">
        <div class="metric-card">
          <h3>Utilization</h3>
          <div class="metric-value"><%= format_percent(@metrics[:utilization]) %></div>
          <div class="metric-chart" phx-hook="Chart" data-chart-type="gauge" data-chart-data={@metrics[:utilization]}></div>
        </div>
        
        <div class="metric-card">
          <h3>Throughput</h3>
          <div class="metric-value"><%= @metrics[:throughput] %> ops/sec</div>
          <div class="metric-chart" phx-hook="Chart" data-chart-type="line" data-chart-data={@chart_data[:throughput]}></div>
        </div>
        
        <div class="metric-card">
          <h3>Average Latency</h3>
          <div class="metric-value"><%= format_ms(@metrics[:avg_latency]) %></div>
          <div class="metric-chart" phx-hook="Chart" data-chart-type="line" data-chart-data={@chart_data[:latency]}></div>
        </div>
        
        <div class="metric-card">
          <h3>Error Rate</h3>
          <div class="metric-value"><%= format_percent(@metrics[:error_rate]) %></div>
          <div class="metric-chart" phx-hook="Chart" data-chart-type="line" data-chart-data={@chart_data[:errors]}></div>
        </div>
      </div>
      
      <div class="pool-details">
        <h2>Pool Details</h2>
        <table>
          <tr>
            <td>Pool Size:</td>
            <td><%= @metrics[:pool_size] %></td>
          </tr>
          <tr>
            <td>Active Workers:</td>
            <td><%= @metrics[:active_workers] %></td>
          </tr>
          <tr>
            <td>Queue Depth:</td>
            <td><%= @metrics[:queue_depth] %></td>
          </tr>
          <tr>
            <td>Health Score:</td>
            <td><%= format_health_score(@metrics[:health_score]) %></td>
          </tr>
        </table>
      </div>
    </div>
    """
  end
  
  defp format_percent(nil), do: "0%"
  defp format_percent(value), do: "#{round(value * 100)}%"
  
  defp format_ms(nil), do: "0ms"
  defp format_ms(value), do: "#{round(value)}ms"
  
  defp format_health_score(nil), do: "N/A"
  defp format_health_score(score) do
    color = cond do
      score >= 80 -> "green"
      score >= 60 -> "yellow"
      true -> "red"
    end
    
    ~s(<span class="health-score #{color}">#{round(score)}</span>)
  end
end
```

## Performance Tuning Guide

### Configuration Parameters

```elixir
# config/prod.exs
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  # Pool sizing
  pool_size: System.get_env("POOL_SIZE", "10") |> String.to_integer(),
  min_pool_size: 5,
  max_pool_size: 50,
  max_overflow: 10,
  
  # Timeouts
  init_timeout: 30_000,      # Worker initialization
  checkout_timeout: 5_000,   # Getting worker from pool
  operation_timeout: 60_000, # Command execution
  
  # Strategy
  strategy: :lifo,           # LIFO for better cache locality
  lazy: false,               # Pre-warm workers
  
  # Health checks
  health_check_interval: 30_000,
  max_health_failures: 3,
  
  # Optimization
  enable_optimizer: true,
  optimization_interval: 60_000,
  
  # Monitoring
  enable_metrics: true,
  metrics_interval: 1_000
```

### Deployment Checklist

1. **Pre-deployment**
   - [ ] Run performance benchmarks
   - [ ] Verify pool configuration
   - [ ] Test warmup strategy
   - [ ] Configure monitoring

2. **Deployment**
   - [ ] Deploy with gradual rollout
   - [ ] Monitor key metrics
   - [ ] Verify health checks
   - [ ] Check error rates

3. **Post-deployment**
   - [ ] Analyze performance data
   - [ ] Tune configuration
   - [ ] Update alerts
   - [ ] Document changes

## Next Steps

Proceed to Document 7: "Migration and Deployment Plan" for production rollout strategy.
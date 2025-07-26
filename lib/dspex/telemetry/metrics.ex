defmodule DSPex.Telemetry.Metrics do
  @moduledoc """
  Metrics collection and aggregation for DSPex.
  
  This module tracks performance metrics and provides:
  - Real-time metric collection
  - Time-windowed aggregations
  - Percentile calculations
  - Rate calculations
  - Error tracking
  
  ## Metrics Tracked
  
  - Bridge operation latencies (p50, p95, p99)
  - Tool execution times
  - Error rates by operation
  - Session lifetimes
  - Worker pool health
  """
  
  use GenServer
  require Logger
  
  @window_size_ms 60_000  # 1 minute windows
  @max_samples 10_000     # Maximum samples per metric
  
  defmodule MetricWindow do
    @moduledoc false
    defstruct [
      :name,
      :start_time,
      samples: [],
      count: 0,
      sum: 0,
      errors: 0,
      max: 0,
      min: nil
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current metrics summary.
  """
  def get_summary do
    GenServer.call(__MODULE__, :get_summary)
  end
  
  @doc """
  Get metrics for a specific operation.
  """
  def get_metric(metric_name) do
    GenServer.call(__MODULE__, {:get_metric, metric_name})
  end
  
  @doc """
  Export metrics in Prometheus format.
  """
  def export_prometheus do
    GenServer.call(__MODULE__, :export_prometheus)
  end
  
  @doc """
  Attach this module as a telemetry handler.
  """
  def attach do
    events = [
      [:dspex, :bridge, :create_instance, :stop],
      [:dspex, :bridge, :create_instance, :exception],
      [:dspex, :bridge, :call_method, :stop],
      [:dspex, :bridge, :call_method, :exception],
      [:dspex, :bridge, :call, :stop],
      [:dspex, :bridge, :call, :exception],
      [:dspex, :tools, :execute, :stop],
      [:dspex, :tools, :execute, :exception],
      [:dspex, :contract, :validate, :stop],
      [:dspex, :contract, :validate, :exception],
      [:dspex, :types, :cast, :stop],
      [:dspex, :types, :cast, :exception],
      [:dspex, :session, :expired],
      [:snakepit, :pool, :queue_time],
      [:snakepit, :worker, :died]
    ]
    
    :telemetry.attach_many(
      "dspex-metrics",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      metrics: %{},
      opts: opts,
      start_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_summary, _from, state) do
    summary = build_summary(state.metrics)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_call({:get_metric, metric_name}, _from, state) do
    metric = Map.get(state.metrics, metric_name)
    
    result = if metric do
      calculate_metric_stats(metric)
    else
      nil
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:export_prometheus, _from, state) do
    prometheus_output = export_to_prometheus(state.metrics)
    {:reply, prometheus_output, state}
  end
  
  @impl true
  def handle_cast({:record_metric, name, value, error?}, state) do
    now = System.monotonic_time(:millisecond)
    
    metric = Map.get(state.metrics, name, %MetricWindow{
      name: name,
      start_time: now
    })
    
    # Add sample (limited to max_samples)
    samples = if length(metric.samples) >= @max_samples do
      [value | Enum.take(metric.samples, @max_samples - 1)]
    else
      [value | metric.samples]
    end
    
    # Update aggregations
    metric = %{metric |
      samples: samples,
      count: metric.count + 1,
      sum: metric.sum + value,
      errors: if(error?, do: metric.errors + 1, else: metric.errors),
      max: max(metric.max, value),
      min: if(metric.min, do: min(metric.min, value), else: value)
    }
    
    state = put_in(state.metrics[name], metric)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    
    # Remove old metric windows
    metrics = state.metrics
    |> Enum.filter(fn {_name, metric} ->
      now - metric.start_time < @window_size_ms * 2
    end)
    |> Enum.into(%{})
    
    schedule_cleanup()
    {:noreply, %{state | metrics: metrics}}
  end
  
  # Telemetry handler
  
  @doc false
  def handle_event(event, measurements, metadata, _config) do
    case event do
      [:dspex, :bridge, operation, :stop] ->
        metric_name = "dspex.bridge.#{operation}.duration"
        duration = measurements[:duration] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, false})
        
      [:dspex, :bridge, operation, :exception] ->
        metric_name = "dspex.bridge.#{operation}.duration"
        duration = measurements[:duration] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, true})
        
      [:dspex, :tools, :execute, :stop] ->
        metric_name = "dspex.tools.#{metadata.tool_name}.duration"
        duration = measurements[:duration] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, false})
        
      [:dspex, :tools, :execute, :exception] ->
        metric_name = "dspex.tools.#{metadata.tool_name}.duration"
        duration = measurements[:duration] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, true})
        
      [:dspex, :contract, :validate, result] ->
        metric_name = "dspex.contract.validate.duration"
        duration = measurements[:duration] || 0
        error? = result == :exception
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, error?})
        
      [:dspex, :types, :cast, result] ->
        metric_name = "dspex.types.cast.duration"
        duration = measurements[:duration] || 0
        error? = result == :exception
        GenServer.cast(__MODULE__, {:record_metric, metric_name, duration, error?})
        
      [:dspex, :session, :expired] ->
        metric_name = "dspex.session.lifetime"
        lifetime = measurements[:lifetime_ms] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, lifetime, false})
        
      [:snakepit, :pool, :queue_time] ->
        metric_name = "snakepit.pool.queue_time"
        wait_time_ms = measurements[:wait_time_us] / 1_000
        GenServer.cast(__MODULE__, {:record_metric, metric_name, wait_time_ms, false})
        
      [:snakepit, :worker, :died] ->
        metric_name = "snakepit.worker.lifetime"
        lifetime = measurements[:lifetime_ms] || 0
        GenServer.cast(__MODULE__, {:record_metric, metric_name, lifetime, false})
        
      _ ->
        :ok
    end
  end
  
  # Private functions
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @window_size_ms)
  end
  
  defp build_summary(metrics) do
    metrics
    |> Enum.map(fn {name, metric} ->
      stats = calculate_metric_stats(metric)
      {name, stats}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_metric_stats(%MetricWindow{} = metric) do
    sorted_samples = Enum.sort(metric.samples)
    
    %{
      count: metric.count,
      sum: metric.sum,
      mean: if(metric.count > 0, do: metric.sum / metric.count, else: 0),
      min: metric.min || 0,
      max: metric.max,
      error_count: metric.errors,
      error_rate: if(metric.count > 0, do: metric.errors / metric.count, else: 0),
      p50: percentile(sorted_samples, 0.50),
      p95: percentile(sorted_samples, 0.95),
      p99: percentile(sorted_samples, 0.99)
    }
  end
  
  defp percentile([], _p), do: 0
  defp percentile(sorted_samples, p) do
    index = round(p * (length(sorted_samples) - 1))
    Enum.at(sorted_samples, index, 0)
  end
  
  defp export_to_prometheus(metrics) do
    lines = metrics
    |> Enum.flat_map(fn {name, metric} ->
      stats = calculate_metric_stats(metric)
      safe_name = String.replace(name, ".", "_")
      
      [
        "# TYPE #{safe_name}_count counter",
        "#{safe_name}_count #{stats.count}",
        "# TYPE #{safe_name}_sum counter",
        "#{safe_name}_sum #{stats.sum}",
        "# TYPE #{safe_name}_errors counter",
        "#{safe_name}_errors #{stats.error_count}",
        "# TYPE #{safe_name}_histogram histogram",
        "#{safe_name}_bucket{le=\"#{stats.p50}\"} #{round(stats.count * 0.5)}",
        "#{safe_name}_bucket{le=\"#{stats.p95}\"} #{round(stats.count * 0.95)}",
        "#{safe_name}_bucket{le=\"#{stats.p99}\"} #{round(stats.count * 0.99)}",
        "#{safe_name}_bucket{le=\"+Inf\"} #{stats.count}"
      ]
    end)
    
    Enum.join(lines, "\n")
  end
end
# Stage 4.4: Analytics and Monitoring Implementation

## Context

You are implementing the Analytics and Monitoring system for the DSPex BridgedState backend. This component provides comprehensive visibility into system performance, usage patterns, and operational health through metrics collection, aggregation, and real-time dashboards.

## Requirements

The Analytics system must:

1. **Metric Collection**: Capture all relevant operational metrics
2. **Real-time Aggregation**: Provide instant visibility into system state
3. **Historical Analysis**: Store and query historical performance data
4. **Performance Dashboards**: Generate actionable insights
5. **Minimal Overhead**: Not impact system performance

## Implementation Guide

### 1. Create the Analytics Module

Create `lib/dspex/bridge/analytics.ex`:

```elixir
defmodule DSPex.Bridge.Analytics do
  @moduledoc """
  Performance analytics and monitoring for the bridge.
  
  Uses ETS for high-performance metric storage and provides
  real-time dashboards for operational visibility.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :ets_table,
    :aggregation_interval,
    :retention_period,
    :metrics_buffer,
    :aggregations
  ]
end
```

### 2. Metric Types

Define comprehensive metrics:

```elixir
@metric_types %{
  # Variable operations
  variable_read: :counter,
  variable_write: :counter,
  variable_delete: :counter,
  
  # Latency metrics
  read_latency_us: :histogram,
  write_latency_us: :histogram,
  grpc_latency_us: :histogram,
  
  # Cache metrics
  cache_hit: :counter,
  cache_miss: :counter,
  cache_eviction: :counter,
  
  # Optimization metrics
  optimization_started: :counter,
  optimization_completed: :counter,
  optimization_failed: :counter,
  optimization_duration_ms: :histogram,
  optimization_improvement: :gauge,
  
  # Session metrics
  active_sessions: :gauge,
  session_created: :counter,
  session_terminated: :counter,
  
  # Error metrics
  operation_error: :counter,
  grpc_error: :counter,
  timeout_error: :counter,
  
  # Resource metrics
  memory_usage_mb: :gauge,
  process_count: :gauge,
  ets_memory_mb: :gauge
}
```

### 3. Metric Storage

Use ETS for efficient storage:

```elixir
def init(opts) do
  # Create ETS table with write concurrency
  table = :ets.new(:bridge_analytics, [
    :set,
    :public,
    :named_table,
    {:write_concurrency, true},
    {:read_concurrency, true},
    {:decentralized_counters, true}  # For Erlang/OTP 23+
  ])
  
  # Create index tables for fast queries
  :ets.new(:analytics_time_index, [:ordered_set, :public])
  :ets.new(:analytics_aggregates, [:set, :public])
  
  state = %__MODULE__{
    ets_table: table,
    aggregation_interval: opts[:aggregation_interval] || 60_000,
    retention_period: opts[:retention_period] || 86_400_000,
    metrics_buffer: [],
    aggregations: %{}
  }
  
  # Schedule aggregation
  schedule_aggregation(state)
  
  {:ok, state}
end
```

### 4. High-Performance Recording

Implement lock-free metric recording:

```elixir
def record_metric(metric_type, value, metadata \\ %{}) do
  timestamp = System.monotonic_time(:microsecond)
  
  # Use decentralized counters for counters
  case @metric_types[metric_type] do
    :counter ->
      key = {metric_type, :counter, make_bucket(timestamp)}
      :ets.update_counter(:bridge_analytics, key, {2, value}, {key, 0})
    
    :histogram ->
      record_histogram(metric_type, value, timestamp, metadata)
    
    :gauge ->
      record_gauge(metric_type, value, timestamp, metadata)
  end
end

defp record_histogram(metric_type, value, timestamp, metadata) do
  # Store raw value for percentile calculations
  key = {metric_type, timestamp, :erlang.unique_integer()}
  :ets.insert(:bridge_analytics, {key, value, metadata})
  
  # Update time index
  :ets.insert(:analytics_time_index, {{timestamp, metric_type}, key})
end

# Bucket timestamps for efficient aggregation
defp make_bucket(timestamp, interval \\ 60_000_000) do
  div(timestamp, interval) * interval
end
```

### 5. Real-time Aggregation

Implement streaming aggregation:

```elixir
defmodule DSPex.Bridge.Analytics.Aggregator do
  @moduledoc """
  Real-time metric aggregation using Erlang's optimized algorithms.
  """
  
  defstruct [:sum, :count, :min, :max, :sum_of_squares]
  
  def new do
    %__MODULE__{sum: 0, count: 0, min: nil, max: nil, sum_of_squares: 0}
  end
  
  def add(%__MODULE__{} = agg, value) do
    %{agg |
      sum: agg.sum + value,
      count: agg.count + 1,
      min: min(agg.min || value, value),
      max: max(agg.max || value, value),
      sum_of_squares: agg.sum_of_squares + value * value
    }
  end
  
  def merge(agg1, agg2) do
    %__MODULE__{
      sum: agg1.sum + agg2.sum,
      count: agg1.count + agg2.count,
      min: min(agg1.min || agg2.min, agg2.min || agg1.min),
      max: max(agg1.max || agg2.max, agg2.max || agg1.max),
      sum_of_squares: agg1.sum_of_squares + agg2.sum_of_squares
    }
  end
  
  def stats(%__MODULE__{count: 0}), do: nil
  def stats(%__MODULE__{} = agg) do
    mean = agg.sum / agg.count
    variance = (agg.sum_of_squares / agg.count) - (mean * mean)
    
    %{
      count: agg.count,
      sum: agg.sum,
      mean: mean,
      min: agg.min,
      max: agg.max,
      stddev: :math.sqrt(max(0, variance))
    }
  end
end
```

### 6. Dashboard Generation

Create comprehensive dashboards:

```elixir
def get_dashboard(time_range \\ :last_minute) do
  now = System.monotonic_time(:microsecond)
  {start_time, bucket_size} = get_time_range(time_range, now)
  
  %{
    timestamp: DateTime.utc_now(),
    time_range: time_range,
    
    # Operation metrics
    operations: %{
      reads_per_second: calculate_rate(:variable_read, start_time, now),
      writes_per_second: calculate_rate(:variable_write, start_time, now),
      total_operations: count_in_range(:all_operations, start_time, now)
    },
    
    # Performance metrics
    performance: %{
      read_latency_p50: percentile(:read_latency_us, start_time, now, 0.50),
      read_latency_p95: percentile(:read_latency_us, start_time, now, 0.95),
      read_latency_p99: percentile(:read_latency_us, start_time, now, 0.99),
      write_latency_p50: percentile(:write_latency_us, start_time, now, 0.50),
      write_latency_p95: percentile(:write_latency_us, start_time, now, 0.95),
      write_latency_p99: percentile(:write_latency_us, start_time, now, 0.99)
    },
    
    # Cache metrics
    cache: %{
      hit_rate: calculate_cache_hit_rate(start_time, now),
      total_hits: count_in_range(:cache_hit, start_time, now),
      total_misses: count_in_range(:cache_miss, start_time, now),
      evictions: count_in_range(:cache_eviction, start_time, now)
    },
    
    # Optimization metrics
    optimizations: %{
      active: count_active_optimizations(),
      completed: count_in_range(:optimization_completed, start_time, now),
      failed: count_in_range(:optimization_failed, start_time, now),
      success_rate: calculate_optimization_success_rate(start_time, now),
      avg_duration_ms: average(:optimization_duration_ms, start_time, now)
    },
    
    # System health
    health: %{
      error_rate: calculate_error_rate(start_time, now),
      active_sessions: get_gauge_value(:active_sessions),
      memory_usage_mb: get_system_memory(),
      process_count: System.process_count()
    }
  }
end
```

### 7. Percentile Calculations

Implement efficient percentile calculations:

```elixir
defp percentile(metric_type, start_time, end_time, p) do
  # Get all values in range
  values = get_histogram_values(metric_type, start_time, end_time)
  
  case values do
    [] -> nil
    values ->
      # Use quickselect for O(n) percentile
      sorted = Enum.sort(values)
      index = round(p * length(sorted))
      Enum.at(sorted, max(0, index - 1))
  end
end

# Optimized for large datasets
defp streaming_percentile(metric_type, start_time, end_time, p) do
  # Use T-Digest algorithm for approximate percentiles
  digest = TDigest.new()
  
  stream_histogram_values(metric_type, start_time, end_time)
  |> Enum.reduce(digest, &TDigest.add(&2, &1))
  |> TDigest.percentile(p)
end
```

### 8. Time Series Queries

Support flexible time-based queries:

```elixir
def query_time_series(metric_type, start_time, end_time, opts \\ []) do
  interval = opts[:interval] || 60_000_000  # 1 minute default
  aggregation = opts[:aggregation] || :avg
  
  # Generate time buckets
  buckets = generate_time_buckets(start_time, end_time, interval)
  
  # Aggregate data per bucket
  Enum.map(buckets, fn {bucket_start, bucket_end} ->
    values = get_metric_values(metric_type, bucket_start, bucket_end)
    
    %{
      timestamp: bucket_start,
      value: aggregate_values(values, aggregation),
      count: length(values)
    }
  end)
end
```

### 9. Telemetry Integration

Set up telemetry handlers:

```elixir
def setup_telemetry_handlers do
  events = [
    # Variable events
    [:dspex, :bridge, :variable, :read],
    [:dspex, :bridge, :variable, :write],
    [:dspex, :bridge, :variable, :delete],
    
    # Cache events
    [:dspex, :bridge, :cache, :hit],
    [:dspex, :bridge, :cache, :miss],
    [:dspex, :bridge, :cache, :eviction],
    
    # Optimization events
    [:dspex, :optimization, :started],
    [:dspex, :optimization, :progress],
    [:dspex, :optimization, :completed],
    [:dspex, :optimization, :failed],
    
    # System events
    [:dspex, :bridge, :session, :created],
    [:dspex, :bridge, :session, :terminated],
    [:dspex, :bridge, :error]
  ]
  
  :telemetry.attach_many(
    "bridge-analytics",
    events,
    &__MODULE__.handle_telemetry_event/4,
    nil
  )
end

def handle_telemetry_event(event, measurements, metadata, _config) do
  metric_type = event_to_metric_type(event)
  
  case metric_type do
    {:counter, name} ->
      record_metric(name, 1, metadata)
    
    {:histogram, name, value_key} ->
      value = Map.get(measurements, value_key)
      record_metric(name, value, metadata)
    
    {:gauge, name, value_key} ->
      value = Map.get(measurements, value_key)
      record_metric(name, value, metadata)
  end
end
```

### 10. Export Formats

Support various export formats:

```elixir
def export_metrics(format, time_range \\ :last_hour) do
  case format do
    :prometheus ->
      export_prometheus_format(time_range)
    
    :json ->
      export_json_format(time_range)
    
    :csv ->
      export_csv_format(time_range)
    
    :statsd ->
      export_statsd_format(time_range)
  end
end

defp export_prometheus_format(time_range) do
  metrics = get_all_metrics(time_range)
  
  Enum.map(metrics, fn {name, type, value} ->
    [
      "# TYPE #{name} #{prometheus_type(type)}\n",
      "#{name} #{format_value(value)} #{System.os_time(:millisecond)}\n"
    ]
  end)
  |> IO.iodata_to_binary()
end
```

### 11. Alerting Integration

Support alerting on metrics:

```elixir
defmodule DSPex.Bridge.Analytics.Alerts do
  def check_alerts(metrics) do
    alert_rules()
    |> Enum.filter(fn rule ->
      evaluate_alert_rule(rule, metrics)
    end)
    |> Enum.each(&trigger_alert/1)
  end
  
  defp alert_rules do
    [
      %{
        name: "high_error_rate",
        condition: fn m -> m.health.error_rate > 0.05 end,
        severity: :critical
      },
      %{
        name: "slow_reads",
        condition: fn m -> m.performance.read_latency_p95 > 10_000 end,
        severity: :warning
      },
      %{
        name: "low_cache_hit_rate",
        condition: fn m -> m.cache.hit_rate < 0.8 end,
        severity: :info
      }
    ]
  end
end
```

### 12. Testing Scenarios

Test comprehensive analytics:

1. **Metric Recording**:
   - High-frequency counter updates
   - Histogram accuracy
   - Gauge consistency

2. **Aggregation**:
   - Time bucket accuracy
   - Percentile calculations
   - Rate calculations

3. **Performance**:
   - Recording overhead
   - Query latency
   - Memory usage

4. **Accuracy**:
   - No metric loss
   - Correct aggregations
   - Time precision

## Implementation Checklist

- [ ] Create Analytics GenServer with ETS storage
- [ ] Implement metric type system
- [ ] Add high-performance recording
- [ ] Create real-time aggregation
- [ ] Implement percentile calculations
- [ ] Add dashboard generation
- [ ] Create time series queries
- [ ] Integrate telemetry handlers
- [ ] Add export formats
- [ ] Implement alerting hooks
- [ ] Write performance tests
- [ ] Add accuracy tests
- [ ] Create load tests
- [ ] Document metric definitions

## Success Criteria

1. **Performance**: < 1μs metric recording overhead
2. **Accuracy**: No metric loss under load
3. **Scalability**: Handle millions of metrics/minute
4. **Usability**: Instant dashboard generation
5. **Flexibility**: Support custom queries
6. **Integration**: Export to standard formats
# Telemetry and Observability Specification

## From "Cognitive" to Observable

Instead of vague promises about "cognitive capabilities," we implement comprehensive observability that provides real insights into system behavior.

## Core Telemetry Events

### 1. Bridge Operations

Every bridge operation emits structured telemetry:

```elixir
# Event: [:dspex, :bridge, :create_instance, :start]
# Measurements: %{system_time: integer()}
# Metadata: %{python_class: string(), args_size: integer()}

# Event: [:dspex, :bridge, :create_instance, :stop]  
# Measurements: %{duration: integer()}
# Metadata: %{python_class: string(), success: boolean(), ref: string() | nil}

# Event: [:dspex, :bridge, :create_instance, :exception]
# Measurements: %{duration: integer()}
# Metadata: %{python_class: string(), kind: atom(), reason: term(), stacktrace: list()}
```

### 2. Method Calls

Track every Python method invocation:

```elixir
# Event: [:dspex, :bridge, :call_method, :start]
# Measurements: %{system_time: integer()}
# Metadata: %{
#   ref: string(),
#   method: string(),
#   args_size: integer(),
#   session_id: string() | nil
# }

# Event: [:dspex, :bridge, :call_method, :stop]
# Measurements: %{duration: integer(), result_size: integer()}
# Metadata: %{
#   ref: string(),
#   method: string(),
#   success: boolean(),
#   cached: boolean()
# }
```

### 3. Session Management

Track session lifecycle and variable usage:

```elixir
# Event: [:dspex, :session, :created]
# Measurements: %{system_time: integer()}
# Metadata: %{session_id: string(), initial_vars: map()}

# Event: [:dspex, :session, :variable, :set]
# Measurements: %{size: integer()}
# Metadata: %{session_id: string(), var_name: string(), var_type: string()}

# Event: [:dspex, :session, :variable, :get]
# Measurements: %{size: integer()}
# Metadata: %{session_id: string(), var_name: string(), found: boolean()}

# Event: [:dspex, :session, :expired]
# Measurements: %{lifetime_ms: integer(), total_operations: integer()}
# Metadata: %{session_id: string(), reason: atom()}
```

### 4. Bidirectional Communication

Track Python → Elixir tool calls:

```elixir
# Event: [:dspex, :tools, :call, :start]
# Measurements: %{system_time: integer()}
# Metadata: %{
#   tool_name: string(),
#   session_id: string(),
#   args_size: integer(),
#   caller: :python | :elixir
# }

# Event: [:dspex, :tools, :call, :stop]
# Measurements: %{duration: integer()}
# Metadata: %{
#   tool_name: string(),
#   success: boolean(),
#   result_size: integer()
# }
```

### 5. Worker Pool Health

Monitor Python worker performance:

```elixir
# Event: [:snakepit, :worker, :spawned]
# Measurements: %{startup_time: integer()}
# Metadata: %{worker_id: string(), python_version: string()}

# Event: [:snakepit, :worker, :died]
# Measurements: %{lifetime_ms: integer(), operations_handled: integer()}
# Metadata: %{worker_id: string(), reason: term()}

# Event: [:snakepit, :pool, :queue_time]
# Measurements: %{wait_time_us: integer()}
# Metadata: %{worker_id: string(), command: string()}
```

## Telemetry Handlers

### 1. Performance Monitor

Track performance trends and anomalies:

```elixir
defmodule SnakepitGrpcBridge.Telemetry.PerformanceMonitor do
  use GenServer
  require Logger
  
  @window_size_ms 60_000  # 1 minute windows
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Attach to telemetry events
    :telemetry.attach_many(
      "performance-monitor",
      [
        [:dspex, :bridge, :call_method, :stop],
        [:dspex, :bridge, :call_method, :exception],
        [:snakepit, :pool, :queue_time]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
    
    # Schedule periodic reporting
    schedule_report()
    
    {:ok, %{
      operations: %{},
      current_window_start: System.monotonic_time(:millisecond)
    }}
  end
  
  def handle_event([:dspex, :bridge, :call_method, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:operation_completed, measurements, metadata})
  end
  
  def handle_event([:dspex, :bridge, :call_method, :exception], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:operation_failed, measurements, metadata})
  end
  
  def handle_event([:snakepit, :pool, :queue_time], measurements, _metadata, _config) do
    if measurements.wait_time_us > 5_000_000 do  # 5 seconds
      Logger.warning("High queue time detected: #{measurements.wait_time_us / 1_000}ms")
    end
  end
  
  def handle_cast({:operation_completed, measurements, metadata}, state) do
    key = {metadata.method, metadata.python_class}
    
    stats = Map.get(state.operations, key, %{
      count: 0,
      total_duration: 0,
      max_duration: 0,
      errors: 0
    })
    
    updated_stats = %{
      stats |
      count: stats.count + 1,
      total_duration: stats.total_duration + measurements.duration,
      max_duration: max(stats.max_duration, measurements.duration)
    }
    
    {:noreply, put_in(state.operations[key], updated_stats)}
  end
  
  def handle_info(:report, state) do
    # Generate performance report
    report = generate_report(state)
    Logger.info("Performance Report: #{inspect(report)}")
    
    # Emit aggregated metrics
    Enum.each(report, fn {{method, class}, stats} ->
      :telemetry.execute(
        [:dspex, :performance, :summary],
        %{
          avg_duration_us: stats.avg_duration,
          max_duration_us: stats.max_duration,
          error_rate: stats.error_rate
        },
        %{method: method, python_class: class}
      )
    end)
    
    # Reset for next window
    schedule_report()
    {:noreply, %{state | operations: %{}, current_window_start: System.monotonic_time(:millisecond)}}
  end
  
  defp generate_report(state) do
    Map.new(state.operations, fn {key, stats} ->
      avg_duration = if stats.count > 0, do: stats.total_duration / stats.count, else: 0
      error_rate = if stats.count > 0, do: stats.errors / stats.count, else: 0
      
      {key, %{
        count: stats.count,
        avg_duration: round(avg_duration),
        max_duration: stats.max_duration,
        error_rate: Float.round(error_rate, 3)
      }}
    end)
  end
  
  defp schedule_report do
    Process.send_after(self(), :report, @window_size_ms)
  end
end
```

### 2. Error Pattern Analyzer

Identify and alert on error patterns:

```elixir
defmodule SnakepitGrpcBridge.Telemetry.ErrorAnalyzer do
  use GenServer
  require Logger
  
  @error_threshold 5  # errors in window
  @window_size_ms 10_000  # 10 seconds
  
  def init(_opts) do
    :telemetry.attach(
      "error-analyzer",
      [:dspex, :bridge, :call_method, :exception],
      &__MODULE__.handle_error/4,
      nil
    )
    
    {:ok, %{
      error_windows: %{},  # method -> list of timestamps
      alerts_sent: MapSet.new()
    }}
  end
  
  def handle_error(_event, _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:error_occurred, metadata})
  end
  
  def handle_cast({:error_occurred, metadata}, state) do
    now = System.monotonic_time(:millisecond)
    method_key = {metadata.method, metadata.python_class}
    
    # Add error timestamp to window
    timestamps = Map.get(state.error_windows, method_key, [])
    updated_timestamps = [now | timestamps]
      |> Enum.filter(&(&1 > now - @window_size_ms))  # Keep only recent
    
    # Check if we exceeded threshold
    if length(updated_timestamps) >= @error_threshold do
      alert_key = {method_key, div(now, @window_size_ms)}
      
      unless MapSet.member?(state.alerts_sent, alert_key) do
        Logger.error("""
        Error spike detected for #{elem(method_key, 1)}.#{elem(method_key, 0)}
        #{length(updated_timestamps)} errors in last #{@window_size_ms}ms
        """)
        
        :telemetry.execute(
          [:dspex, :alerts, :error_spike],
          %{error_count: length(updated_timestamps)},
          %{method: elem(method_key, 0), python_class: elem(method_key, 1)}
        )
        
        state = put_in(state.alerts_sent, MapSet.put(state.alerts_sent, alert_key))
      end
    end
    
    {:noreply, put_in(state.error_windows[method_key], updated_timestamps)}
  end
end
```

### 3. Usage Analytics

Track feature usage for informed decisions:

```elixir
defmodule SnakepitGrpcBridge.Telemetry.UsageAnalytics do
  use GenServer
  
  def init(_opts) do
    :telemetry.attach_many(
      "usage-analytics",
      [
        [:dspex, :bridge, :create_instance, :stop],
        [:dspex, :tools, :call, :stop],
        [:dspex, :session, :variable, :set]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
    
    # Load previous state from persistent storage
    {:ok, load_state()}
  end
  
  def handle_event([:dspex, :bridge, :create_instance, :stop], _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:class_used, metadata.python_class})
  end
  
  def handle_event([:dspex, :tools, :call, :stop], _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:tool_used, metadata.tool_name})
  end
  
  def handle_event([:dspex, :session, :variable, :set], _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:variable_used, metadata.var_name})
  end
  
  def handle_cast({:class_used, class}, state) do
    state = update_in(state.classes[class], &((&1 || 0) + 1))
    {:noreply, state}
  end
  
  def handle_cast({:tool_used, tool}, state) do
    state = update_in(state.tools[tool], &((&1 || 0) + 1))
    {:noreply, state}
  end
  
  def get_usage_report do
    GenServer.call(__MODULE__, :get_report)
  end
  
  def handle_call(:get_report, _from, state) do
    report = %{
      most_used_classes: state.classes |> Enum.sort_by(fn {_, count} -> -count end) |> Enum.take(10),
      most_used_tools: state.tools |> Enum.sort_by(fn {_, count} -> -count end) |> Enum.take(10),
      total_operations: Enum.sum(Map.values(state.classes))
    }
    
    {:reply, report, state}
  end
end
```

## Metrics Dashboards

### 1. Grafana Dashboard Configuration

```json
{
  "dashboard": {
    "title": "DSPex Bridge Observability",
    "panels": [
      {
        "title": "Operation Latency (p50, p95, p99)",
        "targets": [
          {
            "expr": "histogram_quantile(0.5, dspex_bridge_call_method_duration_bucket)",
            "legendFormat": "p50"
          },
          {
            "expr": "histogram_quantile(0.95, dspex_bridge_call_method_duration_bucket)",
            "legendFormat": "p95"
          },
          {
            "expr": "histogram_quantile(0.99, dspex_bridge_call_method_duration_bucket)",
            "legendFormat": "p99"
          }
        ]
      },
      {
        "title": "Error Rate by Method",
        "targets": [
          {
            "expr": "rate(dspex_bridge_call_method_exception_total[5m])"
          }
        ]
      },
      {
        "title": "Python Worker Pool Health",
        "targets": [
          {
            "expr": "snakepit_worker_pool_size",
            "legendFormat": "Pool Size"
          },
          {
            "expr": "rate(snakepit_worker_died_total[5m])",
            "legendFormat": "Worker Death Rate"
          }
        ]
      },
      {
        "title": "Bidirectional Tool Usage",
        "targets": [
          {
            "expr": "rate(dspex_tools_call_total[5m])",
            "legendFormat": "{{tool_name}}"
          }
        ]
      }
    ]
  }
}
```

### 2. Alerting Rules

```yaml
groups:
  - name: dspex_bridge_alerts
    rules:
      - alert: HighErrorRate
        expr: rate(dspex_bridge_call_method_exception_total[5m]) > 0.05
        for: 5m
        annotations:
          summary: "High error rate for bridge operations"
          description: "Error rate is {{ $value }} for {{ $labels.method }}"
          
      - alert: HighLatency
        expr: histogram_quantile(0.99, dspex_bridge_call_method_duration_bucket) > 1000000
        for: 10m
        annotations:
          summary: "High p99 latency detected"
          description: "p99 latency is {{ $value }}μs for {{ $labels.method }}"
          
      - alert: WorkerPoolUnhealthy
        expr: rate(snakepit_worker_died_total[5m]) > 0.1
        for: 5m
        annotations:
          summary: "Python workers dying frequently"
          description: "Worker death rate is {{ $value }} per second"
```

## Custom Telemetry Integration

### For Library Users

```elixir
# Attach to events
:telemetry.attach(
  "my-app-monitor",
  [:dspex, :bridge, :call_method, :stop],
  fn _event, measurements, metadata, _config ->
    MyApp.Metrics.record_latency(
      metadata.method,
      measurements.duration
    )
  end,
  nil
)

# Create custom handlers
defmodule MyApp.BridgeMonitor do
  def attach do
    events = [
      [:dspex, :bridge, :call_method, :start],
      [:dspex, :bridge, :call_method, :stop],
      [:dspex, :bridge, :call_method, :exception]
    ]
    
    :telemetry.attach_many("my-app", events, &handle_event/4, %{})
  end
  
  def handle_event(event, measurements, metadata, config) do
    case event do
      [:dspex, :bridge, :call_method, :start] ->
        Logger.debug("Starting #{metadata.method}")
        
      [:dspex, :bridge, :call_method, :stop] ->
        Logger.debug("Completed #{metadata.method} in #{measurements.duration}μs")
        
      [:dspex, :bridge, :call_method, :exception] ->
        Logger.error("Failed #{metadata.method}: #{inspect(metadata.reason)}")
    end
  end
end
```

## Performance Optimization Using Telemetry

### 1. Intelligent Routing

```elixir
defmodule SnakepitGrpcBridge.Routing.PerformanceRouter do
  @moduledoc """
  Routes requests based on observed performance.
  """
  
  use GenServer
  
  def route_request(command, args) do
    GenServer.call(__MODULE__, {:route, command, args})
  end
  
  def handle_call({:route, command, _args}, _from, state) do
    # Get performance stats for this command
    worker_stats = state.performance_by_worker[command] || %{}
    
    # Find worker with best recent performance
    best_worker = worker_stats
      |> Enum.min_by(fn {_worker_id, stats} -> stats.avg_latency end, fn -> nil end)
      
    worker_id = case best_worker do
      {id, _stats} -> id
      nil -> select_random_worker()
    end
    
    {:reply, {:ok, worker_id}, state}
  end
end
```

### 2. Adaptive Caching

```elixir
defmodule SnakepitGrpcBridge.Caching.AdaptiveCache do
  @moduledoc """
  Caches frequently accessed results based on usage patterns.
  """
  
  def maybe_cache(method, args, result, metadata) do
    # Cache if this method is called frequently
    if metadata.call_count > 100 and metadata.cache_hit_rate > 0.3 do
      cache_key = generate_cache_key(method, args)
      Cache.put(cache_key, result, ttl: calculate_ttl(metadata))
    end
  end
  
  defp calculate_ttl(metadata) do
    # Longer TTL for stable, frequently accessed data
    base_ttl = 60_000  # 1 minute
    
    stability_factor = 1 - metadata.result_variance
    frequency_factor = min(metadata.call_count / 1000, 2.0)
    
    round(base_ttl * stability_factor * frequency_factor)
  end
end
```

## Summary

This observability implementation provides:

1. **Comprehensive Telemetry**: Every operation is measured
2. **Actionable Insights**: Real patterns, not speculation
3. **Performance Optimization**: Data-driven improvements
4. **Error Detection**: Catch problems early
5. **Usage Analytics**: Understand what's actually used

No "cognitive" magic - just solid engineering telemetry that helps you run a reliable, performant system.
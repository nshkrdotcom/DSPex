# DSPex Telemetry and Performance Monitoring

Comprehensive telemetry and observability for the DSPex system, providing real-time insights into performance, errors, and system health.

## Overview

The DSPex telemetry system provides:

- **Real-time Performance Monitoring**: Track latency, throughput, and resource usage
- **Distributed Tracing**: Correlation IDs and request tracing across the bridge
- **Error Tracking**: Automatic error detection and alerting
- **Resource Monitoring**: Python worker pool health and queue depths
- **Custom Metrics**: Extensible metric collection and reporting

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    DSPex Application                          │
├─────────────────────────────────────────────────────────────┤
│  Bridge Operations │ Tool Execution │ Session Management     │
│  Contract Validation │ Type Casting │ Worker Pool            │
└────────────┬───────────────────────┬────────────────────────┘
             │                       │
             ▼                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Telemetry Events                            │
│  [:dspex, :bridge, :call, :start/stop/exception]           │
│  [:dspex, :tools, :execute, :start/stop/exception]         │
│  [:dspex, :session, :variable, :set/get]                   │
│  [:dspex, :contract, :validate, :start/stop/exception]     │
└────────────┬───────────────────────┬────────────────────────┘
             │                       │
             ▼                       ▼
┌─────────────────────────────────────────────────────────────┐
│               Telemetry Handlers                             │
├─────────────────┬──────────────┬──────────────┬────────────┤
│ Central Handler │ Metrics      │ Reporter     │ Alerts     │
│                 │ Aggregation  │ (StatsD,     │ (Thresholds,│
│                 │ (p50,p95,p99)│ Prometheus)  │ Webhooks)  │
└─────────────────┴──────────────┴──────────────┴────────────┘
```

## Quick Start

### 1. Basic Setup

The telemetry system starts automatically with the DSPex application:

```elixir
# In your application supervision tree
children = [
  DSPex.Application
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### 2. Configuration

Configure telemetry in your `config.exs`:

```elixir
config :dspex, :telemetry,
  handlers: [
    {DSPex.Telemetry.Metrics, []},
    {DSPex.Telemetry.Reporter, []},
    {DSPex.Telemetry.Alerts, []}
  ]

# Performance alerts
config :dspex, DSPex.Telemetry.Alerts,
  thresholds: [
    bridge_call_p99_ms: 1000,      # Alert if p99 > 1 second
    tool_execution_p99_ms: 500,    # Alert if tool p99 > 500ms
    error_rate_percent: 5,         # Alert if error rate > 5%
    queue_time_ms: 5000           # Alert if queue time > 5 seconds
  ],
  alert_handlers: [
    {DSPex.Telemetry.Alerts.LogHandler, level: :error},
    {DSPex.Telemetry.Alerts.WebhookHandler, url: "https://alerts.example.com"}
  ]

# Metric reporting backends
config :dspex, DSPex.Telemetry.Reporter,
  backends: [
    {:statsd, host: "localhost", port: 8125},
    {:prometheus, push_gateway: "http://localhost:9091"},
    {:opentelemetry, enabled: true}
  ],
  reporting_interval: 30_000  # 30 seconds
```

### 3. Using Correlation IDs

Track requests across the system:

```elixir
# Start a new trace
correlation_id = DSPex.Telemetry.Correlation.start_trace()

# All operations within this block are correlated
DSPex.Telemetry.Correlation.with_correlation(correlation_id, fn ->
  # Create predictor
  {:ok, predictor} = DSPex.Predict.new("question -> answer")
  
  # Execute prediction - automatically correlated
  {:ok, result} = DSPex.Predict.execute(predictor, %{
    question: "What is telemetry?"
  })
end)
```

### 4. Custom Metrics

Add custom metrics to your operations:

```elixir
# Record a custom metric
:telemetry.execute(
  [:myapp, :custom, :operation],
  %{duration: 100, count: 5},
  %{operation: "data_processing", user_id: "123"}
)

# Attach a handler
:telemetry.attach(
  "myapp-custom",
  [:myapp, :custom, :operation],
  fn event, measurements, metadata, _config ->
    Logger.info("Custom operation: #{metadata.operation} took #{measurements.duration}ms")
  end,
  nil
)
```

## Telemetry Events

### Bridge Operations

```elixir
# Bridge call events
[:dspex, :bridge, :call, :start]
[:dspex, :bridge, :call, :stop]
[:dspex, :bridge, :call, :exception]

# Measurements: duration (nanoseconds), system_time
# Metadata: module, function, args, session_id, success, error
```

### Tool Execution

```elixir
# Tool execution events
[:dspex, :tools, :execute, :start]
[:dspex, :tools, :execute, :stop]
[:dspex, :tools, :execute, :exception]

# Measurements: duration, system_time
# Metadata: tool_name, session_id, caller, result_type
```

### Session Operations

```elixir
# Session lifecycle
[:dspex, :session, :created]
[:dspex, :session, :expired]

# Variable operations
[:dspex, :session, :variable, :set]
[:dspex, :session, :variable, :get]

# Measurements: size, lifetime_ms
# Metadata: session_id, var_name, var_type, found
```

## Monitoring Dashboards

### Grafana Integration

Import the provided dashboard configuration:

```bash
cp telemetry/grafana_dashboard.json /var/lib/grafana/dashboards/
```

Key panels include:
- Bridge call latency (p50, p95, p99)
- Tool execution performance
- Error rates by operation
- Python worker pool health
- Active sessions and lifetime
- Request tracing table

### Prometheus Metrics

Access metrics at `/metrics` endpoint:

```
# Bridge operations
dspex_bridge_call_method_duration_bucket
dspex_bridge_call_method_count
dspex_bridge_call_method_errors

# Tool executions
dspex_tools_execute_duration_bucket
dspex_tools_execute_count

# Session metrics
dspex_session_created_total
dspex_session_lifetime_bucket
dspex_session_variable_operations_total
```

## Performance Benchmarks

Run performance benchmarks:

```bash
# Telemetry overhead benchmarks
mix bench bench/telemetry_bench.exs

# Bridge performance benchmarks
mix bench bench/bridge_performance_bench.exs

# Full system benchmarks
mix bench bench/three_layer_bench.exs
```

## Alert Configuration

### Built-in Alert Types

1. **Performance Degradation**
   - Triggered when p99 latency exceeds threshold
   - Includes degradation factor

2. **Error Spike**
   - Triggered when error rate exceeds threshold
   - Tracks error count and rate

3. **Resource Exhaustion**
   - Worker pool exhaustion
   - High queue times

### Custom Alert Handlers

Create custom alert handlers:

```elixir
defmodule MyApp.SlackAlertHandler do
  @behaviour DSPex.Telemetry.Alerts
  
  @impl true
  def handle_alert(alert, config) do
    webhook_url = config[:webhook_url]
    
    payload = %{
      text: alert.message,
      attachments: [
        %{
          color: severity_color(alert.severity),
          fields: [
            %{title: "Type", value: alert.type},
            %{title: "Severity", value: alert.severity},
            %{title: "Details", value: inspect(alert.details)}
          ]
        }
      ]
    }
    
    # Send to Slack
    HTTPoison.post!(webhook_url, Jason.encode!(payload))
    
    :ok
  end
  
  defp severity_color(:critical), do: "danger"
  defp severity_color(:high), do: "warning"
  defp severity_color(_), do: "good"
end
```

## OpenTelemetry Integration

### Setup

Add OpenTelemetry to your dependencies:

```elixir
def deps do
  [
    {:opentelemetry, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.6"},
    {:opentelemetry_api, "~> 1.2"}
  ]
end
```

### Configuration

```elixir
config :opentelemetry, :resource,
  service: [
    name: "dspex",
    version: "1.0.0"
  ]

config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:otel_exporter_otlp, 
      endpoint: "http://localhost:4317",
      headers: [{"x-api-key", "your-api-key"}]
    }
  }
```

### Distributed Tracing

Traces automatically propagate through:
- Bridge calls
- Tool executions
- Session operations
- Contract validations

## Best Practices

### 1. Correlation IDs

Always use correlation IDs for user-facing operations:

```elixir
defmodule MyApp.API do
  plug :assign_correlation_id
  
  defp assign_correlation_id(conn, _opts) do
    correlation_id = get_req_header(conn, "x-correlation-id") 
                    |> List.first() 
                    |> Kernel.||( DSPex.Telemetry.Correlation.generate_correlation_id())
    
    DSPex.Telemetry.Correlation.start_trace(correlation_id)
    
    conn
    |> put_resp_header("x-correlation-id", correlation_id)
    |> assign(:correlation_id, correlation_id)
  end
end
```

### 2. Performance Monitoring

Monitor key business operations:

```elixir
defmodule MyApp.BusinessLogic do
  def process_request(data) do
    DSPex.Telemetry.Correlation.with_span("business.process_request", fn ->
      # Your business logic here
      
      # Add custom attributes
      DSPex.Telemetry.OpenTelemetry.set_attributes(%{
        "business.data_size" => byte_size(data),
        "business.user_id" => get_user_id()
      })
      
      result = do_processing(data)
      
      # Record custom metric
      :telemetry.execute(
        [:myapp, :business, :processed],
        %{items_count: length(result.items)},
        %{success: true}
      )
      
      result
    end)
  end
end
```

### 3. Error Tracking

Enhance error tracking with context:

```elixir
def handle_error(error, context) do
  DSPex.Telemetry.Correlation.add_baggage("error.context", context)
  
  :telemetry.execute(
    [:myapp, :error, :handled],
    %{count: 1},
    %{
      error_type: error.__struct__,
      error_message: Exception.message(error),
      context: context
    }
  )
  
  # Re-raise or handle as appropriate
  raise error
end
```

## Troubleshooting

### High Memory Usage

If telemetry is consuming too much memory:

1. Reduce metric window size
2. Increase reporting frequency
3. Limit samples per metric

```elixir
config :dspex, DSPex.Telemetry.Metrics,
  window_size_ms: 30_000,    # Reduce from 60s to 30s
  max_samples: 5_000         # Reduce from 10k to 5k
```

### Missing Metrics

If metrics aren't appearing:

1. Check handler attachment
2. Verify event names
3. Enable debug logging

```elixir
# Enable telemetry debug logging
config :logger, :console,
  level: :debug,
  metadata: [:correlation_id, :trace_id, :span_id]
```

### Alert Fatigue

Reduce alert noise:

1. Adjust thresholds based on baseline
2. Use occurrence counting
3. Implement alert suppression

```elixir
config :dspex, DSPex.Telemetry.Alerts,
  suppression: [
    min_interval_ms: 300_000,  # 5 minutes between similar alerts
    occurrence_threshold: 5     # Only alert after 5 occurrences
  ]
```

## Contributing

When adding new telemetry:

1. Follow naming conventions: `[:dspex, :component, :operation, :phase]`
2. Include meaningful metadata
3. Document measurements and units
4. Add to dashboard configuration
5. Update this README

Example:

```elixir
:telemetry.span(
  [:dspex, :my_component, :operation],
  %{request_id: request_id},
  fn ->
    result = do_operation()
    
    # Return result and metadata
    {result, %{
      items_processed: length(result.items),
      cache_hit: result.from_cache?
    }}
  end
)
```
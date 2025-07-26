defmodule DSPex.Telemetry.Reporter do
  @moduledoc """
  Reporting telemetry data to external systems.
  
  This module provides integrations with:
  - StatsD/DogStatsD
  - Prometheus (push gateway)
  - OpenTelemetry
  - Custom webhooks
  
  ## Configuration
  
      config :dspex, DSPex.Telemetry.Reporter,
        backends: [
          {:statsd, host: "localhost", port: 8125},
          {:prometheus, push_gateway: "http://localhost:9091"},
          {:opentelemetry, enabled: true}
        ],
        reporting_interval: 30_000  # 30 seconds
  """
  
  use GenServer
  require Logger
  
  @default_interval 30_000  # 30 seconds
  
  defmodule Backend do
    @moduledoc false
    @callback send_metrics(metrics :: map()) :: :ok | {:error, term()}
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Manually trigger metric reporting.
  """
  def report_now do
    GenServer.cast(__MODULE__, :report_now)
  end
  
  @doc """
  Add a custom backend.
  """
  def add_backend(backend_type, config) do
    GenServer.call(__MODULE__, {:add_backend, backend_type, config})
  end
  
  @doc """
  Remove a backend.
  """
  def remove_backend(backend_type) do
    GenServer.call(__MODULE__, {:remove_backend, backend_type})
  end
  
  @doc """
  Attach this module as a telemetry handler.
  """
  def attach do
    # For real-time critical metrics
    critical_events = [
      [:dspex, :alerts, :error_spike],
      [:dspex, :performance, :degradation],
      [:snakepit, :pool, :exhausted]
    ]
    
    :telemetry.attach_many(
      "dspex-reporter",
      critical_events,
      &__MODULE__.handle_critical_event/4,
      nil
    )
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    config = Application.get_env(:dspex, __MODULE__, [])
    backends = initialize_backends(config[:backends] || [])
    interval = config[:reporting_interval] || @default_interval
    
    # Schedule first report
    schedule_report(interval)
    
    state = %{
      backends: backends,
      interval: interval,
      last_report: System.monotonic_time(:millisecond),
      opts: opts
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:add_backend, backend_type, config}, _from, state) do
    case initialize_backend({backend_type, config}) do
      {:ok, backend} ->
        backends = Map.put(state.backends, backend_type, backend)
        {:reply, :ok, %{state | backends: backends}}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:remove_backend, backend_type}, _from, state) do
    backends = Map.delete(state.backends, backend_type)
    {:reply, :ok, %{state | backends: backends}}
  end
  
  @impl true
  def handle_cast(:report_now, state) do
    report_metrics(state)
    {:noreply, %{state | last_report: System.monotonic_time(:millisecond)}}
  end
  
  @impl true
  def handle_info(:scheduled_report, state) do
    report_metrics(state)
    schedule_report(state.interval)
    {:noreply, %{state | last_report: System.monotonic_time(:millisecond)}}
  end
  
  # Critical event handler
  
  @doc false
  def handle_critical_event(event, measurements, metadata, _config) do
    case event do
      [:dspex, :alerts, :error_spike] ->
        Logger.alert("""
        Error spike detected!
        Method: #{metadata.method}
        Class: #{metadata.python_class}
        Error count: #{measurements.error_count}
        """)
        
        # Send immediate alert through backends
        GenServer.cast(__MODULE__, :report_now)
        
      [:dspex, :performance, :degradation] ->
        Logger.warning("""
        Performance degradation detected!
        Metric: #{metadata.metric}
        Current: #{measurements.current_value}
        Threshold: #{measurements.threshold}
        """)
        
      [:snakepit, :pool, :exhausted] ->
        Logger.critical("""
        Worker pool exhausted!
        Queue depth: #{measurements.queue_depth}
        Active workers: #{measurements.active_workers}
        """)
        
      _ ->
        :ok
    end
  end
  
  # Private functions
  
  defp initialize_backends(backend_configs) do
    backend_configs
    |> Enum.map(&initialize_backend/1)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, backend} -> backend end)
    |> Enum.into(%{})
  end
  
  defp initialize_backend({:statsd, config}) do
    backend = %{
      type: :statsd,
      config: config,
      connection: connect_statsd(config)
    }
    {:ok, {:statsd, backend}}
  end
  
  defp initialize_backend({:prometheus, config}) do
    backend = %{
      type: :prometheus,
      config: config,
      push_gateway: config[:push_gateway]
    }
    {:ok, {:prometheus, backend}}
  end
  
  defp initialize_backend({:opentelemetry, config}) do
    if config[:enabled] do
      backend = %{
        type: :opentelemetry,
        config: config
      }
      {:ok, {:opentelemetry, backend}}
    else
      {:error, :disabled}
    end
  end
  
  defp initialize_backend({:webhook, config}) do
    backend = %{
      type: :webhook,
      config: config,
      url: config[:url]
    }
    {:ok, {:webhook, backend}}
  end
  
  defp initialize_backend({type, _config}) do
    Logger.warning("Unknown backend type: #{type}")
    {:error, :unknown_backend}
  end
  
  defp connect_statsd(config) do
    # This would connect to actual StatsD server
    # For now, we'll just store the config
    %{
      host: config[:host] || "localhost",
      port: config[:port] || 8125
    }
  end
  
  defp schedule_report(interval) do
    Process.send_after(self(), :scheduled_report, interval)
  end
  
  defp report_metrics(state) do
    # Get metrics from the metrics module
    metrics = DSPex.Telemetry.Metrics.get_summary()
    
    # Send to each backend
    Enum.each(state.backends, fn {_type, backend} ->
      try do
        send_to_backend(backend, metrics)
      rescue
        error ->
          Logger.error("Failed to send metrics to #{backend.type}: #{inspect(error)}")
      end
    end)
  end
  
  defp send_to_backend(%{type: :statsd} = backend, metrics) do
    # Format and send metrics to StatsD
    Enum.each(metrics, fn {name, stats} ->
      statsd_name = String.replace(name, ".", "_")
      
      # Send gauge metrics
      send_statsd_metric(backend.connection, "#{statsd_name}.count", stats.count, :counter)
      send_statsd_metric(backend.connection, "#{statsd_name}.mean", stats.mean, :gauge)
      send_statsd_metric(backend.connection, "#{statsd_name}.p50", stats.p50, :gauge)
      send_statsd_metric(backend.connection, "#{statsd_name}.p95", stats.p95, :gauge)
      send_statsd_metric(backend.connection, "#{statsd_name}.p99", stats.p99, :gauge)
      send_statsd_metric(backend.connection, "#{statsd_name}.error_rate", stats.error_rate, :gauge)
    end)
  end
  
  defp send_to_backend(%{type: :prometheus} = backend, metrics) do
    # Convert metrics to Prometheus format
    prometheus_data = DSPex.Telemetry.Metrics.export_prometheus()
    
    # Push to gateway
    push_to_prometheus(backend.push_gateway, prometheus_data)
  end
  
  defp send_to_backend(%{type: :opentelemetry} = _backend, metrics) do
    # Send metrics via OpenTelemetry
    Enum.each(metrics, fn {name, stats} ->
      # This would use actual OpenTelemetry API
      :telemetry.execute(
        [:opentelemetry, :metrics, :record],
        %{
          value: stats.mean,
          attributes: %{
            metric_name: name,
            p50: stats.p50,
            p95: stats.p95,
            p99: stats.p99,
            error_rate: stats.error_rate
          }
        },
        %{}
      )
    end)
  end
  
  defp send_to_backend(%{type: :webhook} = backend, metrics) do
    # Send metrics via webhook
    payload = %{
      timestamp: DateTime.utc_now(),
      metrics: metrics
    }
    
    send_webhook(backend.url, payload)
  end
  
  defp send_statsd_metric(connection, name, value, type) do
    # This would actually send to StatsD server
    # For now, just log
    Logger.debug("StatsD #{type} #{name}: #{value}")
  end
  
  defp push_to_prometheus(gateway_url, data) do
    # This would actually push to Prometheus gateway
    # For now, just log
    Logger.debug("Pushing to Prometheus gateway: #{gateway_url}")
  end
  
  defp send_webhook(url, payload) do
    # This would actually send HTTP request
    # For now, just log
    Logger.debug("Sending webhook to: #{url}")
  end
end
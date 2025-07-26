defmodule DSPex.Telemetry.Alerts do
  @moduledoc """
  Performance alerts and threshold monitoring.
  
  This module monitors telemetry events and triggers alerts when:
  - Response times exceed thresholds
  - Error rates spike
  - Resource usage is high
  - System performance degrades
  
  ## Configuration
  
      config :dspex, DSPex.Telemetry.Alerts,
        thresholds: [
          bridge_call_p99_ms: 1000,
          tool_execution_p99_ms: 500,
          error_rate_percent: 5,
          queue_time_ms: 5000
        ],
        alert_handlers: [
          {DSPex.Telemetry.Alerts.LogHandler, level: :error},
          {DSPex.Telemetry.Alerts.WebhookHandler, url: "https://alerts.example.com"}
        ]
  """
  
  use GenServer
  require Logger
  
  @default_thresholds %{
    bridge_call_p99_ms: 1000,
    tool_execution_p99_ms: 500,
    error_rate_percent: 5,
    queue_time_ms: 5000,
    session_lifetime_ms: 3600_000  # 1 hour
  }
  
  @check_interval 10_000  # 10 seconds
  
  defmodule Alert do
    @moduledoc false
    defstruct [
      :id,
      :type,
      :severity,
      :message,
      :details,
      :triggered_at,
      :resolved_at,
      :occurrence_count
    ]
  end
  
  # Alert handler behaviour
  @callback handle_alert(Alert.t()) :: :ok | {:error, term()}
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Manually trigger an alert.
  """
  def trigger_alert(type, message, details \\ %{}) do
    GenServer.cast(__MODULE__, {:trigger_alert, type, message, details})
  end
  
  @doc """
  Get current active alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc """
  Acknowledge an alert.
  """
  def acknowledge_alert(alert_id) do
    GenServer.call(__MODULE__, {:acknowledge_alert, alert_id})
  end
  
  @doc """
  Attach this module as a telemetry handler.
  """
  def attach do
    # Real-time alert events
    events = [
      [:dspex, :alerts, :error_spike],
      [:dspex, :performance, :degradation],
      [:snakepit, :pool, :exhausted]
    ]
    
    :telemetry.attach_many(
      "dspex-alerts",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    config = Application.get_env(:dspex, __MODULE__, [])
    thresholds = Map.merge(@default_thresholds, Map.new(config[:thresholds] || []))
    handlers = initialize_handlers(config[:alert_handlers] || [])
    
    # Schedule periodic checks
    schedule_check()
    
    state = %{
      thresholds: thresholds,
      handlers: handlers,
      active_alerts: %{},
      alert_history: [],
      metrics_window: [],
      opts: opts
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:trigger_alert, type, message, details}, state) do
    alert = create_alert(type, message, details)
    state = handle_new_alert(alert, state)
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    alerts = Map.values(state.active_alerts)
    {:reply, alerts, state}
  end
  
  @impl true
  def handle_call({:acknowledge_alert, alert_id}, _from, state) do
    case Map.get(state.active_alerts, alert_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      alert ->
        resolved_alert = %{alert | resolved_at: DateTime.utc_now()}
        
        state = state
        |> update_in([:active_alerts], &Map.delete(&1, alert_id))
        |> update_in([:alert_history], &[resolved_alert | &1])
        
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_info(:check_thresholds, state) do
    # Get current metrics
    metrics = DSPex.Telemetry.Metrics.get_summary()
    
    # Check each threshold
    state = check_performance_thresholds(metrics, state)
    
    # Schedule next check
    schedule_check()
    
    {:noreply, state}
  end
  
  # Telemetry handler
  
  @doc false
  def handle_event([:dspex, :alerts, :error_spike], measurements, metadata, _config) do
    trigger_alert(
      :error_spike,
      "Error spike detected for #{metadata.python_class}.#{metadata.method}",
      Map.merge(measurements, metadata)
    )
  end
  
  def handle_event([:snakepit, :pool, :exhausted], measurements, metadata, _config) do
    trigger_alert(
      :pool_exhausted,
      "Worker pool exhausted - queue depth: #{measurements.queue_depth}",
      Map.merge(measurements, metadata)
    )
  end
  
  def handle_event(_event, _measurements, _metadata, _config), do: :ok
  
  # Private functions
  
  defp initialize_handlers(handler_configs) do
    handler_configs
    |> Enum.map(fn
      {module, config} when is_atom(module) ->
        {module, config}
        
      module when is_atom(module) ->
        {module, []}
    end)
    |> Enum.into(%{})
  end
  
  defp schedule_check do
    Process.send_after(self(), :check_thresholds, @check_interval)
  end
  
  defp create_alert(type, message, details) do
    %Alert{
      id: generate_alert_id(),
      type: type,
      severity: determine_severity(type, details),
      message: message,
      details: details,
      triggered_at: DateTime.utc_now(),
      resolved_at: nil,
      occurrence_count: 1
    }
  end
  
  defp generate_alert_id do
    "alert-#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp determine_severity(type, details) do
    cond do
      type == :pool_exhausted -> :critical
      type == :error_spike && details[:error_count] > 100 -> :critical
      type == :performance_degradation && details[:degradation_factor] > 10 -> :high
      type == :error_spike -> :high
      true -> :medium
    end
  end
  
  defp handle_new_alert(alert, state) do
    # Check if similar alert already exists
    existing_key = {alert.type, alert.message}
    
    state = case find_similar_alert(existing_key, state.active_alerts) do
      nil ->
        # New alert
        send_alert_to_handlers(alert, state.handlers)
        put_in(state.active_alerts[alert.id], alert)
        
      {existing_id, existing_alert} ->
        # Update existing alert
        updated_alert = %{existing_alert | 
          occurrence_count: existing_alert.occurrence_count + 1,
          details: Map.merge(existing_alert.details, alert.details)
        }
        
        # Send update if occurrence count crosses threshold
        if rem(updated_alert.occurrence_count, 10) == 0 do
          send_alert_to_handlers(updated_alert, state.handlers)
        end
        
        put_in(state.active_alerts[existing_id], updated_alert)
    end
    
    state
  end
  
  defp find_similar_alert(key, active_alerts) do
    active_alerts
    |> Enum.find(fn {_id, alert} ->
      {alert.type, alert.message} == key &&
      DateTime.diff(DateTime.utc_now(), alert.triggered_at, :minute) < 5
    end)
  end
  
  defp send_alert_to_handlers(alert, handlers) do
    Enum.each(handlers, fn {module, config} ->
      Task.start(fn ->
        try do
          apply(module, :handle_alert, [alert, config])
        rescue
          error ->
            Logger.error("Alert handler #{module} failed: #{inspect(error)}")
        end
      end)
    end)
  end
  
  defp check_performance_thresholds(metrics, state) do
    # Check bridge call latency
    state = check_latency_threshold(
      metrics,
      "dspex.bridge.call_method.duration",
      state.thresholds.bridge_call_p99_ms,
      "Bridge call latency",
      state
    )
    
    # Check tool execution latency
    state = check_latency_threshold(
      metrics,
      "dspex.tools.execute.duration",
      state.thresholds.tool_execution_p99_ms,
      "Tool execution latency",
      state
    )
    
    # Check error rates
    state = check_error_rate(metrics, state)
    
    # Check queue times
    state = check_queue_time(metrics, state)
    
    state
  end
  
  defp check_latency_threshold(metrics, metric_name, threshold_ms, description, state) do
    case Map.get(metrics, metric_name) do
      %{p99: p99} when p99 > threshold_ms * 1000 ->  # Convert to microseconds
        trigger_alert(
          :performance_degradation,
          "#{description} exceeds threshold",
          %{
            metric: metric_name,
            p99_ms: div(p99, 1000),
            threshold_ms: threshold_ms,
            degradation_factor: p99 / (threshold_ms * 1000)
          }
        )
        state
        
      _ ->
        state
    end
  end
  
  defp check_error_rate(metrics, state) do
    error_rates = metrics
    |> Enum.filter(fn {name, _} -> String.contains?(name, "bridge") || String.contains?(name, "tools") end)
    |> Enum.map(fn {name, stats} -> {name, stats[:error_rate] || 0} end)
    |> Enum.filter(fn {_, rate} -> rate > state.thresholds.error_rate_percent / 100 end)
    
    Enum.reduce(error_rates, state, fn {metric_name, error_rate}, acc ->
      trigger_alert(
        :high_error_rate,
        "High error rate for #{metric_name}",
        %{
          metric: metric_name,
          error_rate_percent: error_rate * 100,
          threshold_percent: state.thresholds.error_rate_percent
        }
      )
      acc
    end)
  end
  
  defp check_queue_time(metrics, state) do
    case Map.get(metrics, "snakepit.pool.queue_time") do
      %{p95: p95} when p95 > state.thresholds.queue_time_ms ->
        trigger_alert(
          :high_queue_time,
          "Worker pool queue time is high",
          %{
            p95_ms: p95,
            threshold_ms: state.thresholds.queue_time_ms
          }
        )
        state
        
      _ ->
        state
    end
  end
end

# Default alert handlers

defmodule DSPex.Telemetry.Alerts.LogHandler do
  @moduledoc """
  Logs alerts to the application logger.
  """
  
  @behaviour DSPex.Telemetry.Alerts
  
  @impl true
  def handle_alert(alert, config) do
    level = Keyword.get(config, :level, :error)
    
    Logger.log(level, """
    ALERT: #{alert.message}
    Type: #{alert.type}
    Severity: #{alert.severity}
    Details: #{inspect(alert.details)}
    Triggered: #{alert.triggered_at}
    Occurrences: #{alert.occurrence_count}
    """)
    
    :ok
  end
end

defmodule DSPex.Telemetry.Alerts.WebhookHandler do
  @moduledoc """
  Sends alerts to a webhook endpoint.
  """
  
  @behaviour DSPex.Telemetry.Alerts
  
  @impl true
  def handle_alert(alert, config) do
    url = Keyword.fetch!(config, :url)
    
    payload = %{
      alert: %{
        id: alert.id,
        type: alert.type,
        severity: alert.severity,
        message: alert.message,
        details: alert.details,
        triggered_at: alert.triggered_at,
        occurrence_count: alert.occurrence_count
      },
      metadata: %{
        application: "dspex",
        environment: config[:environment] || "production",
        host: node()
      }
    }
    
    # In a real implementation, this would make an HTTP request
    # For now, just log it
    Logger.info("Would send alert to webhook: #{url}")
    
    :ok
  end
end
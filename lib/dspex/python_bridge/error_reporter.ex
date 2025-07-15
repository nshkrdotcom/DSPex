defmodule DSPex.PythonBridge.ErrorReporter do
  @moduledoc """
  Centralizes error reporting and monitoring for pool operations.

  This module provides comprehensive error reporting capabilities including:
  - Telemetry event aggregation and analysis
  - Error rate monitoring and alerting
  - Circuit breaker event tracking
  - Recovery operation monitoring
  - Configurable alert thresholds

  ## Features

  - Automatic telemetry subscription for all error events
  - Configurable alert thresholds based on error rates and patterns
  - Error categorization and severity-based reporting
  - Integration with external monitoring systems
  - Historical error analysis and trending

  ## Configuration

  Configure alert thresholds and reporting destinations:

      config :dspex, DSPex.PythonBridge.ErrorReporter,
        error_rate_threshold: 0.1,     # 10% error rate
        alert_window_ms: 60_000,       # 1 minute window
        min_events_for_alert: 10,      # Minimum events before alerting
        monitoring_enabled: true,
        alert_destinations: [:logger, :telemetry]

  ## Usage

      # Start the error reporter
      ErrorReporter.start_link()
      
      # Get current error statistics
      ErrorReporter.get_error_stats()
      
      # Get circuit breaker status
      ErrorReporter.get_circuit_status()
      
      # Send test alert
      ErrorReporter.send_test_alert()
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :event_window,
    :error_counts,
    :circuit_states,
    :alert_history,
    :last_cleanup
  ]

  @type error_stats :: %{
          total_errors: non_neg_integer(),
          error_rate: float(),
          categories: map(),
          severities: map(),
          recent_errors: list()
        }

  @type circuit_status :: %{
          name: atom(),
          state: atom(),
          failure_count: non_neg_integer(),
          last_failure: integer() | nil
        }

  @type circuit_opened_alert :: %{
          type: :circuit_opened,
          message: binary(),
          timestamp: integer(),
          metadata: map(),
          circuit: term()
        }

  @type high_error_rate_alert :: %{
          type: :high_error_rate,
          message: binary(),
          timestamp: integer(),
          metadata: map(),
          error_rate: float(),
          error_count: non_neg_integer(),
          total_count: non_neg_integer()
        }

  @type multiple_circuits_alert :: %{
          type: :multiple_circuits_open,
          message: binary(),
          timestamp: integer(),
          metadata: map(),
          open_count: non_neg_integer()
        }

  @type test_alert :: %{
          type: :test_alert,
          message: binary(),
          timestamp: integer(),
          metadata: map()
        }

  @type alert ::
          circuit_opened_alert()
          | high_error_rate_alert()
          | multiple_circuits_alert()
          | test_alert()

  @default_config %{
    # 10% error rate triggers alert
    error_rate_threshold: 0.1,
    # Alert after 3 circuits open
    circuit_open_threshold: 3,
    # 1 minute sliding window
    alert_window_ms: 60_000,
    # Minimum events before calculating rates
    min_events_for_alert: 10,
    # Maximum events to keep in memory
    max_window_events: 1000,
    # 5 minutes
    cleanup_interval: 300_000,
    monitoring_enabled: true,
    alert_destinations: [:logger],
    # 5 minute cooldown between same alerts
    alert_cooldown_ms: 300_000
  }

  ## Public API

  @doc """
  Starts the error reporter GenServer.

  ## Options

  - `:name` - Process name (default: __MODULE__)
  - `:config` - Custom configuration map
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets current error statistics.

  ## Returns

  Map with error counts, rates, and categorization.
  """
  @spec get_error_stats() :: error_stats()
  def get_error_stats do
    GenServer.call(__MODULE__, :get_error_stats)
  end

  @doc """
  Gets current circuit breaker status for all circuits.

  ## Returns

  List of circuit status maps.
  """
  @spec get_circuit_status() :: [circuit_status()]
  def get_circuit_status do
    GenServer.call(__MODULE__, :get_circuit_status)
  end

  @doc """
  Gets alert history for analysis.

  ## Returns

  List of recent alerts with timestamps and details.
  """
  @spec get_alert_history() :: [alert()]
  def get_alert_history do
    GenServer.call(__MODULE__, :get_alert_history)
  end

  @doc """
  Manually sends a test alert to verify alert routing.

  ## Returns

  `:ok` if alert was sent successfully.
  """
  @spec send_test_alert() :: :ok
  def send_test_alert do
    GenServer.call(__MODULE__, :send_test_alert)
  end

  @doc """
  Resets error statistics and alert history.

  Useful for testing or after resolving systemic issues.
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    if config.monitoring_enabled do
      attach_telemetry_handlers()

      Logger.info(
        "ErrorReporter monitoring enabled with #{length(config.alert_destinations)} alert destinations"
      )
    else
      Logger.info("ErrorReporter started in passive mode (monitoring disabled)")
    end

    state = %__MODULE__{
      config: config,
      event_window: :queue.new(),
      error_counts: %{},
      circuit_states: %{},
      alert_history: :queue.new(),
      last_cleanup: System.monotonic_time(:millisecond)
    }

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, config.cleanup_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_error_stats, _from, state) do
    stats = calculate_error_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_circuit_status, _from, state) do
    circuits = Map.values(state.circuit_states)
    {:reply, circuits, state}
  end

  @impl true
  def handle_call(:get_alert_history, _from, state) do
    alerts = :queue.to_list(state.alert_history)
    {:reply, alerts, state}
  end

  @impl true
  def handle_call(:send_test_alert, _from, state) do
    alert = %{
      type: :test_alert,
      message: "Test alert from ErrorReporter",
      timestamp: System.os_time(:millisecond),
      metadata: %{test: true}
    }

    send_alert(alert, state.config)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    new_state = %{
      state
      | event_window: :queue.new(),
        error_counts: %{},
        alert_history: :queue.new(),
        last_cleanup: System.monotonic_time(:millisecond)
    }

    Logger.info("ErrorReporter statistics reset")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    new_state = handle_telemetry_event(event_name, measurements, metadata, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_old_events(state)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, state.config.cleanup_interval)

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    try do
      _result = :telemetry.detach("error-reporter")
    rescue
      _ -> :ok
    end

    Logger.info("ErrorReporter stopped")
    :ok
  end

  ## Private Functions

  @spec build_config(keyword()) :: %{
          alert_cooldown_ms: non_neg_integer(),
          alert_destinations: list(),
          alert_window_ms: non_neg_integer(),
          circuit_open_threshold: non_neg_integer(),
          cleanup_interval: non_neg_integer(),
          error_rate_threshold: float(),
          max_window_events: non_neg_integer(),
          min_events_for_alert: non_neg_integer(),
          monitoring_enabled: boolean()
        }
  defp build_config(opts) do
    custom_config = Keyword.get(opts, :config, %{})
    app_config = Application.get_env(:dspex, __MODULE__, %{})

    @default_config
    |> Map.merge(app_config)
    |> Map.merge(custom_config)
  end

  @spec attach_telemetry_handlers() :: :ok
  defp attach_telemetry_handlers do
    events = [
      [:dspex, :pool, :error],
      [:dspex, :circuit_breaker, :opened],
      [:dspex, :circuit_breaker, :closed],
      [:dspex, :circuit_breaker, :failure],
      [:dspex, :circuit_breaker, :success],
      [:dspex, :recovery, :complete],
      [:dspex, :retry, :exhausted]
    ]

    try do
      _result =
        :telemetry.attach_many(
          "error-reporter",
          events,
          fn event_name, measurements, metadata, _config ->
            send(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
          end,
          nil
        )
    rescue
      error ->
        Logger.error("Failed to attach telemetry handlers: #{inspect(error)}")
    end

    :ok
  end

  @spec handle_telemetry_event(list(atom()), map(), map(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_telemetry_event(event_name, measurements, metadata, state) do
    now = System.monotonic_time(:millisecond)

    case event_name do
      [:dspex, :pool, :error] ->
        handle_pool_error_event(measurements, metadata, now, state)

      [:dspex, :circuit_breaker, :opened] ->
        handle_circuit_opened_event(metadata, now, state)

      [:dspex, :circuit_breaker, :closed] ->
        handle_circuit_closed_event(metadata, now, state)

      [:dspex, :recovery, :complete] ->
        handle_recovery_event(measurements, metadata, now, state)

      [:dspex, :retry, :exhausted] ->
        handle_retry_exhausted_event(measurements, metadata, now, state)

      _ ->
        # Log unknown events for debugging
        Logger.debug("Unknown telemetry event: #{inspect(event_name)}")
        state
    end
  end

  @spec handle_pool_error_event(map(), map(), integer(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_pool_error_event(measurements, metadata, timestamp, state) do
    error_event = %{
      type: :pool_error,
      category: metadata[:error_category],
      severity: metadata[:severity],
      worker_id: metadata[:worker_id],
      duration: measurements[:duration],
      timestamp: timestamp,
      metadata: metadata
    }

    # Add to event window
    new_window = add_to_window(state.event_window, error_event, state.config.max_window_events)

    # Update error counts
    category = metadata[:error_category] || :unknown
    severity = metadata[:severity] || :unknown

    new_counts =
      state.error_counts
      |> update_in([:categories, category], &((&1 || 0) + 1))
      |> update_in([:severities, severity], &((&1 || 0) + 1))
      |> update_in([:total], &((&1 || 0) + 1))

    new_state = %{state | event_window: new_window, error_counts: new_counts}

    # Check if alert thresholds are met
    check_and_send_alerts(new_state)
  end

  @spec handle_circuit_opened_event(map(), integer(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_circuit_opened_event(metadata, timestamp, state) do
    circuit_name = metadata[:circuit]

    # Update circuit state
    circuit_info = %{
      name: circuit_name,
      state: :open,
      last_state_change: timestamp,
      failure_count: Map.get(metadata, :failure_count, 0)
    }

    new_circuits = Map.put(state.circuit_states, circuit_name, circuit_info)
    new_state = %{state | circuit_states: new_circuits}

    # Send immediate alert for circuit breaker opening
    alert = %{
      type: :circuit_opened,
      message:
        "Circuit breaker '#{circuit_name}' opened after #{circuit_info.failure_count} failures",
      circuit: circuit_name,
      timestamp: timestamp,
      metadata: metadata
    }

    send_alert(alert, state.config)

    # Add to alert history
    new_alert_history = add_to_queue(state.alert_history, alert, 50)

    %{new_state | alert_history: new_alert_history}
  end

  @spec handle_circuit_closed_event(map(), integer(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_circuit_closed_event(metadata, timestamp, state) do
    circuit_name = metadata[:circuit]

    # Update circuit state
    circuit_info = %{
      name: circuit_name,
      state: :closed,
      last_state_change: timestamp,
      failure_count: 0
    }

    new_circuits = Map.put(state.circuit_states, circuit_name, circuit_info)

    Logger.info("Circuit breaker '#{circuit_name}' closed after recovery")

    %{state | circuit_states: new_circuits}
  end

  @spec handle_recovery_event(map(), map(), integer(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_recovery_event(measurements, metadata, _timestamp, state) do
    result = metadata[:result]
    duration = measurements[:duration]

    case result do
      :ok ->
        Logger.info("Recovery #{metadata[:recovery_id]} succeeded in #{duration}ms")

      _ ->
        Logger.warning("Recovery #{metadata[:recovery_id]} failed: #{result}")
    end

    state
  end

  @spec handle_retry_exhausted_event(map(), map(), integer(), %__MODULE__{}) :: %__MODULE__{}
  defp handle_retry_exhausted_event(measurements, metadata, _timestamp, state) do
    final_attempt = measurements[:final_attempt]
    max_attempts = measurements[:max_attempts]

    Logger.error(
      "Retry attempts exhausted: #{final_attempt}/#{max_attempts} for #{inspect(metadata[:error])}"
    )

    # This could trigger an alert if retry exhaustion rate is high
    state
  end

  @spec check_and_send_alerts(%__MODULE__{}) :: %__MODULE__{}
  defp check_and_send_alerts(state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - state.config.alert_window_ms

    # Get events in alert window
    recent_events =
      :queue.to_list(state.event_window)
      |> Enum.filter(&(&1.timestamp >= window_start))

    total_events = length(recent_events)
    error_events = Enum.count(recent_events, &(&1.type == :pool_error))

    # Check error rate threshold
    state =
      if total_events >= state.config.min_events_for_alert do
        error_rate = error_events / total_events

        if error_rate >= state.config.error_rate_threshold do
          alert = %{
            type: :high_error_rate,
            message:
              "High error rate detected: #{Float.round(error_rate * 100, 1)}% (#{error_events}/#{total_events} in last #{div(state.config.alert_window_ms, 1000)}s)",
            error_rate: error_rate,
            error_count: error_events,
            total_count: total_events,
            timestamp: now,
            metadata: %{window_ms: state.config.alert_window_ms}
          }

          if should_send_alert(alert, state) do
            send_alert(alert, state.config)
            new_alert_history = add_to_queue(state.alert_history, alert, 50)
            %{state | alert_history: new_alert_history}
          else
            state
          end
        else
          state
        end
      else
        state
      end

    # Check circuit breaker threshold
    open_circuits =
      state.circuit_states
      |> Map.values()
      |> Enum.count(&(&1.state == :open))

    if open_circuits >= state.config.circuit_open_threshold do
      alert = %{
        type: :multiple_circuits_open,
        message: "Multiple circuit breakers open: #{open_circuits} circuits",
        open_count: open_circuits,
        timestamp: now,
        metadata: %{circuits: Map.keys(state.circuit_states)}
      }

      if should_send_alert(alert, state) do
        send_alert(alert, state.config)
        new_alert_history = add_to_queue(state.alert_history, alert, 50)
        %{state | alert_history: new_alert_history}
      else
        state
      end
    else
      state
    end
  end

  @spec should_send_alert(map(), %__MODULE__{}) :: boolean()
  defp should_send_alert(alert, state) do
    # Check alert cooldown to prevent spam
    cooldown_start = System.monotonic_time(:millisecond) - state.config.alert_cooldown_ms

    recent_alerts =
      :queue.to_list(state.alert_history)
      |> Enum.filter(&(&1.timestamp >= cooldown_start))
      |> Enum.filter(&(&1.type == alert.type))

    length(recent_alerts) == 0
  end

  @spec send_alert(map(), map()) :: :ok
  defp send_alert(alert, config) do
    Enum.each(config.alert_destinations, fn destination ->
      case destination do
        :logger ->
          send_logger_alert(alert)

        :telemetry ->
          send_telemetry_alert(alert)

        {module, function} ->
          apply(module, function, [alert])

        _ ->
          Logger.warning("Unknown alert destination: #{inspect(destination)}")
      end
    end)
  end

  @spec send_logger_alert(alert()) :: :ok
  defp send_logger_alert(alert) do
    case alert.type do
      :circuit_opened ->
        Logger.error("🚨 ALERT: #{alert.message}")

      :high_error_rate ->
        Logger.error("📊 ALERT: #{alert.message}")

      :multiple_circuits_open ->
        Logger.error("⚠️  ALERT: #{alert.message}")

      _ ->
        Logger.warning("🔔 ALERT: #{alert.message}")
    end
  end

  @spec send_telemetry_alert(alert()) :: :ok
  defp send_telemetry_alert(alert) do
    try do
      :telemetry.execute(
        [:dspex, :error_reporter, :alert],
        %{timestamp: alert.timestamp},
        alert
      )
    rescue
      _ ->
        Logger.warning("Failed to send telemetry alert")
    end

    :ok
  end

  @spec calculate_error_stats(%__MODULE__{}) :: error_stats()
  defp calculate_error_stats(state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - state.config.alert_window_ms

    recent_events =
      :queue.to_list(state.event_window)
      |> Enum.filter(&(&1.timestamp >= window_start))

    total_events = length(recent_events)
    error_events = Enum.filter(recent_events, &(&1.type == :pool_error))
    error_count = length(error_events)

    error_rate = if total_events > 0, do: error_count / total_events, else: 0.0

    %{
      total_errors: Map.get(state.error_counts, :total, 0),
      error_rate: error_rate,
      categories: Map.get(state.error_counts, :categories, %{}),
      severities: Map.get(state.error_counts, :severities, %{}),
      recent_errors: Enum.take(error_events, 10)
    }
  end

  @spec cleanup_old_events(%__MODULE__{}) :: %__MODULE__{}
  defp cleanup_old_events(state) do
    now = System.monotonic_time(:millisecond)
    # Keep 2x window for analysis
    cutoff = now - state.config.alert_window_ms * 2

    # Clean event window
    new_window =
      :queue.to_list(state.event_window)
      |> Enum.filter(&(&1.timestamp >= cutoff))
      |> :queue.from_list()

    # Clean alert history (keep last 100)
    new_alert_history =
      :queue.to_list(state.alert_history)
      |> Enum.take(-100)
      |> :queue.from_list()

    %{state | event_window: new_window, alert_history: new_alert_history, last_cleanup: now}
  end

  @spec add_to_window(:queue.queue(), map(), pos_integer()) :: :queue.queue()
  defp add_to_window(queue, event, max_size) do
    new_queue = :queue.in(event, queue)

    if :queue.len(new_queue) > max_size do
      {_, trimmed_queue} = :queue.out(new_queue)
      trimmed_queue
    else
      new_queue
    end
  end

  @spec add_to_queue(:queue.queue(term()), alert(), pos_integer()) :: :queue.queue(term())
  defp add_to_queue(queue, item, max_size) do
    new_queue = :queue.in(item, queue)

    if :queue.len(new_queue) > max_size do
      {_, trimmed_queue} = :queue.out(new_queue)
      trimmed_queue
    else
      new_queue
    end
  end
end

defmodule DSPex.PythonBridge.WorkerMetrics do
  @moduledoc """
  Tracks worker lifecycle metrics using telemetry events.

  This module provides a standardized interface for recording metrics
  about worker state transitions, health checks, session affinity,
  and performance. It's designed to be telemetry-agnostic but uses
  telemetry events when available.

  ## Event Types

  - `[:dspex, :pool, :worker, :transition]` - State transitions
  - `[:dspex, :pool, :worker, :health_check]` - Health check results
  - `[:dspex, :pool, :session, :affinity]` - Session affinity hits/misses
  - `[:dspex, :pool, :worker, :operation]` - Operation timings
  - `[:dspex, :pool, :worker, :lifecycle]` - Worker lifecycle events

  ## Measurements

  All timing measurements are in milliseconds. Counts are positive integers.

  ## Metadata

  Each event includes relevant metadata for filtering and aggregation.
  """

  require Logger

  @telemetry_available Code.ensure_loaded?(:telemetry)

  @doc """
  Records a worker state transition.

  ## Parameters

  - `worker_id` - Unique worker identifier
  - `from_state` - Previous state
  - `to_state` - New state
  - `duration_ms` - Time spent in previous state
  - `metadata` - Additional context (optional)

  ## Examples

      WorkerMetrics.record_transition("worker_123", :ready, :busy, 45_000)
      WorkerMetrics.record_transition("worker_123", :busy, :ready, 1_500, %{session_id: "sess_456"})
  """
  @spec record_transition(String.t(), atom(), atom(), non_neg_integer(), map()) :: :ok
  def record_transition(worker_id, from_state, to_state, duration_ms, metadata \\ %{}) do
    measurements = %{duration: duration_ms}

    event_metadata =
      Map.merge(metadata, %{
        worker_id: worker_id,
        from_state: from_state,
        to_state: to_state,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :worker, :transition], measurements, event_metadata)

    Logger.debug("Worker transition recorded",
      worker_id: worker_id,
      transition: "#{from_state} -> #{to_state}",
      duration_ms: duration_ms
    )

    :ok
  end

  @doc """
  Records a health check result.

  ## Parameters

  - `worker_id` - Unique worker identifier
  - `result` - Health check result (`:success`, `:failure`, `:timeout`, etc.)
  - `duration_ms` - Time taken for health check
  - `metadata` - Additional context (optional)

  ## Examples

      WorkerMetrics.record_health_check("worker_123", :success, 250)
      WorkerMetrics.record_health_check("worker_123", :failure, 5000, %{error: :timeout})
  """
  @spec record_health_check(String.t(), atom(), non_neg_integer(), map()) :: :ok
  def record_health_check(worker_id, result, duration_ms, metadata \\ %{}) do
    measurements = %{duration: duration_ms}

    event_metadata =
      Map.merge(metadata, %{
        worker_id: worker_id,
        result: result,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :worker, :health_check], measurements, event_metadata)

    log_level = if result == :success, do: :debug, else: :warning

    Logger.log(log_level, "Worker health check recorded",
      worker_id: worker_id,
      result: result,
      duration_ms: duration_ms
    )

    :ok
  end

  @doc """
  Records session affinity cache hit or miss.

  ## Parameters

  - `session_id` - Session identifier
  - `worker_id` - Worker identifier (if found)
  - `hit_or_miss` - `:hit` if worker found, `:miss` if not found
  - `metadata` - Additional context (optional)

  ## Examples

      WorkerMetrics.record_session_affinity("sess_123", "worker_456", :hit)
      WorkerMetrics.record_session_affinity("sess_789", nil, :miss)
  """
  @spec record_session_affinity(String.t(), String.t() | nil, :hit | :miss, map()) :: :ok
  def record_session_affinity(session_id, worker_id, hit_or_miss, metadata \\ %{}) do
    measurements = %{count: 1}

    event_metadata =
      Map.merge(metadata, %{
        session_id: session_id,
        worker_id: worker_id,
        result: hit_or_miss,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :session, :affinity], measurements, event_metadata)

    Logger.debug("Session affinity recorded",
      session_id: session_id,
      worker_id: worker_id,
      result: hit_or_miss
    )

    :ok
  end

  @doc """
  Records a worker operation timing.

  ## Parameters

  - `worker_id` - Unique worker identifier
  - `operation` - Operation name (e.g., `:execute`, `:checkout`, `:checkin`)
  - `duration_ms` - Operation duration
  - `result` - Operation result (`:success`, `:error`, `:timeout`)
  - `metadata` - Additional context (optional)

  ## Examples

      WorkerMetrics.record_operation("worker_123", :execute, 1500, :success)
      WorkerMetrics.record_operation("worker_123", :checkout, 50, :error, %{reason: :port_closed})
  """
  @spec record_operation(String.t(), atom(), non_neg_integer(), atom(), map()) :: :ok
  def record_operation(worker_id, operation, duration_ms, result, metadata \\ %{}) do
    measurements = %{duration: duration_ms}

    event_metadata =
      Map.merge(metadata, %{
        worker_id: worker_id,
        operation: operation,
        result: result,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :worker, :operation], measurements, event_metadata)

    log_level = if result == :success, do: :debug, else: :info

    Logger.log(log_level, "Worker operation recorded",
      worker_id: worker_id,
      operation: operation,
      result: result,
      duration_ms: duration_ms
    )

    :ok
  end

  @doc """
  Records worker lifecycle events.

  ## Parameters

  - `worker_id` - Unique worker identifier
  - `event` - Lifecycle event (`:created`, `:started`, `:removed`, `:replaced`)
  - `metadata` - Additional context (optional)

  ## Examples

      WorkerMetrics.record_lifecycle("worker_123", :created)
      WorkerMetrics.record_lifecycle("worker_123", :removed, %{reason: :health_failure})
  """
  @spec record_lifecycle(String.t(), atom(), map()) :: :ok
  def record_lifecycle(worker_id, event, metadata \\ %{}) do
    measurements = %{count: 1}

    event_metadata =
      Map.merge(metadata, %{
        worker_id: worker_id,
        event: event,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :worker, :lifecycle], measurements, event_metadata)

    Logger.info("Worker lifecycle event recorded",
      worker_id: worker_id,
      event: event,
      metadata: metadata
    )

    :ok
  end

  @doc """
  Records pool-level metrics.

  ## Parameters

  - `pool_name` - Pool identifier
  - `metric_type` - Type of metric (`:worker_count`, `:session_count`, etc.)
  - `value` - Metric value
  - `metadata` - Additional context (optional)
  """
  @spec record_pool_metric(atom(), atom(), number(), map()) :: :ok
  def record_pool_metric(pool_name, metric_type, value, metadata \\ %{}) do
    measurements = %{value: value}

    event_metadata =
      Map.merge(metadata, %{
        pool_name: pool_name,
        metric_type: metric_type,
        timestamp: System.os_time(:millisecond)
      })

    emit_event([:dspex, :pool, :metric], measurements, event_metadata)

    Logger.debug("Pool metric recorded",
      pool_name: pool_name,
      metric_type: metric_type,
      value: value
    )

    :ok
  end

  @doc """
  Creates a timing function for measuring operation duration.

  ## Parameters

  - `worker_id` - Unique worker identifier
  - `operation` - Operation name
  - `metadata` - Additional context (optional)

  ## Returns

  A function that, when called with the result, records the timing.

  ## Examples

      timer = WorkerMetrics.start_timing("worker_123", :execute)
      result = perform_operation()
      timer.(if match?({:ok, _}, result), do: :success, else: :error)
  """
  @spec start_timing(String.t(), atom(), map()) :: (atom() -> :ok)
  def start_timing(worker_id, operation, metadata \\ %{}) do
    start_time = System.monotonic_time(:millisecond)

    fn result ->
      duration = System.monotonic_time(:millisecond) - start_time
      record_operation(worker_id, operation, duration, result, metadata)
    end
  end

  @doc """
  Attaches a telemetry handler for worker metrics.

  This is a convenience function for setting up telemetry handlers
  that can aggregate and export metrics to external systems.

  ## Parameters

  - `handler_id` - Unique handler identifier
  - `handler_function` - Function to handle telemetry events
  - `config` - Handler configuration (optional)

  ## Examples

      WorkerMetrics.attach_handler(:my_metrics, &handle_metrics/4)
  """
  @spec attach_handler(atom(), function(), map()) :: :ok | {:error, term()}
  def attach_handler(handler_id, handler_function, config \\ %{})
      when is_function(handler_function, 4) do
    if @telemetry_available do
      events = [
        [:dspex, :pool, :worker, :transition],
        [:dspex, :pool, :worker, :health_check],
        [:dspex, :pool, :session, :affinity],
        [:dspex, :pool, :worker, :operation],
        [:dspex, :pool, :worker, :lifecycle],
        [:dspex, :pool, :metric]
      ]

      :telemetry.attach_many(handler_id, events, handler_function, config)
    else
      Logger.warning("Telemetry not available, handler not attached")
      {:error, :telemetry_not_available}
    end
  end

  @doc """
  Detaches a telemetry handler.

  ## Parameters

  - `handler_id` - Handler identifier to remove
  """
  @spec detach_handler(atom()) :: :ok | {:error, term()}
  def detach_handler(handler_id) do
    if @telemetry_available do
      :telemetry.detach(handler_id)
    else
      {:error, :telemetry_not_available}
    end
  end

  @doc """
  Gets summary statistics for recorded metrics.

  This returns basic statistics from logged metrics. For more comprehensive
  metrics, use a proper telemetry handler with an external metrics system.

  ## Returns

  A map with metric summaries.
  """
  @spec get_summary() :: map()
  def get_summary do
    # This is a placeholder implementation
    # In a real system, you'd aggregate from your metrics backend
    %{
      events_recorded: "See telemetry handlers for detailed metrics",
      telemetry_available: @telemetry_available,
      timestamp: System.os_time(:millisecond)
    }
  end

  ## Private Functions

  defp emit_event(event_name, measurements, metadata) do
    if @telemetry_available do
      :telemetry.execute(event_name, measurements, metadata)
    else
      # Fallback to logging when telemetry is not available
      Logger.debug("Metric event",
        event: event_name,
        measurements: measurements,
        metadata: metadata
      )
    end
  end
end

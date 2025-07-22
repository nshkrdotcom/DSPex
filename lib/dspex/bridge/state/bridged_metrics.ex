defmodule DSPex.Bridge.State.BridgedMetrics do
  @moduledoc """
  Performance metrics for BridgedState operations.

  Integrates with Telemetry for observability:
  - Operation latency
  - Error rates
  - Cache effectiveness (future)
  - Session lifecycle events
  """

  require Logger

  @operations [
    :register_variable,
    :get_variable,
    :set_variable,
    :delete_variable,
    :list_variables,
    :get_variables,
    :update_variables,
    :export_state,
    :import_state
  ]

  @doc """
  Instruments a BridgedState operation with telemetry events.

  Emits:
  - `[:dspex, :bridged_state, operation, :start]`
  - `[:dspex, :bridged_state, operation, :stop]` 
  - `[:dspex, :bridged_state, operation, :exception]`

  ## Example

      instrument(state, :get_variable, fn ->
        SessionStore.get_variable(state.session_id, identifier)
      end)
  """
  def instrument(state, operation, fun) when operation in @operations do
    metadata = %{
      session_id: state.session_id,
      backend: :bridged,
      operation: operation
    }

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :bridged_state, operation, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      status =
        case result do
          {:ok, _} -> :ok
          {:error, :not_found} -> :not_found
          {:error, :session_expired} -> :session_expired
          {:error, _} -> :error
          _ -> :ok
        end

      :telemetry.execute(
        [:dspex, :bridged_state, operation, :stop],
        %{
          duration: duration,
          system_time: System.system_time()
        },
        Map.put(metadata, :status, status)
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:dspex, :bridged_state, operation, :exception],
          %{
            duration: duration,
            system_time: System.system_time()
          },
          Map.merge(metadata, %{
            kind: :error,
            reason: e,
            stacktrace: __STACKTRACE__
          })
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Attaches default telemetry handlers for logging.

  Call this in your application startup to enable metric logging.
  """
  def attach_default_handlers do
    handlers = [
      {
        [:dspex, :bridged_state, :_, :stop],
        &handle_stop_event/4,
        nil
      },
      {
        [:dspex, :bridged_state, :_, :exception],
        &handle_exception_event/4,
        nil
      }
    ]

    Enum.each(handlers, fn {event_pattern, handler, config} ->
      handler_id = "#{__MODULE__}-#{inspect(event_pattern)}"

      :telemetry.attach(
        handler_id,
        event_pattern,
        handler,
        config
      )
    end)
  end

  @doc """
  Returns current metrics summary.

  Requires a metrics collector like TelemetryMetrics to be running.
  """
  def get_metrics_summary do
    %{
      operations: @operations,
      info: """
      Metrics are emitted via Telemetry. To collect them:

      1. Add telemetry_metrics to your dependencies
      2. Configure a reporter (Console, StatsD, Prometheus, etc.)
      3. Define metrics like:

          Telemetry.Metrics.summary("dspex.bridged_state.get_variable.duration",
            unit: {:native, :millisecond}
          )
      """
    }
  end

  # Private handlers

  defp handle_stop_event(_event_name, measurements, metadata, _config) do
    operation = metadata.operation
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    status = metadata.status

    if duration_ms > slow_operation_threshold(operation) do
      Logger.warning("""
      Slow BridgedState operation detected:
        Operation: #{operation}
        Duration: #{duration_ms}ms
        Session: #{metadata.session_id}
        Status: #{status}
      """)
    end
  end

  defp handle_exception_event(_event_name, measurements, metadata, _config) do
    operation = metadata.operation
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error("""
    BridgedState operation failed:
      Operation: #{operation}
      Duration: #{duration_ms}ms
      Session: #{metadata.session_id}
      Error: #{inspect(metadata.reason)}
    """)
  end

  defp slow_operation_threshold(:get_variable), do: 5
  defp slow_operation_threshold(:set_variable), do: 10
  defp slow_operation_threshold(:get_variables), do: 20
  defp slow_operation_threshold(:update_variables), do: 30
  defp slow_operation_threshold(:list_variables), do: 50
  defp slow_operation_threshold(_), do: 20
end

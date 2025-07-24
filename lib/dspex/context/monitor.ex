defmodule DSPex.Context.Monitor do
  @moduledoc """
  Monitoring and debugging utilities for DSPex.Context.

  Provides:
  - Telemetry event handlers
  - Context inspection tools
  - Performance monitoring
  - Debug helpers
  """

  require Logger

  @doc """
  Attaches telemetry handlers for context events.

  Call this in your application startup to enable monitoring:

      DSPex.Context.Monitor.attach_handlers()

  Events monitored:
  - Backend switches
  - Variable operations
  - Errors
  """
  def attach_handlers do
    events = [
      [:dspex, :context, :backend_switch],
      [:dspex, :context, :variable_operation],
      [:dspex, :context, :error]
    ]

    :telemetry.attach_many(
      "dspex-context-monitor",
      events,
      &handle_event/4,
      nil
    )
  end

  @doc """
  Detaches the telemetry handlers.
  """
  def detach_handlers do
    :telemetry.detach("dspex-context-monitor")
  end

  # Telemetry event handlers

  defp handle_event([:dspex, :context, :backend_switch], measurements, metadata, _) do
    Logger.info("""
    Context backend switch:
      Context: #{metadata.context_id}
      From: #{inspect(metadata.from)}
      To: #{inspect(metadata.to)}
      Duration: #{measurements.duration_ms}ms
    """)

    if measurements.duration_ms > 50 do
      Logger.warning("Backend switch took longer than expected: #{measurements.duration_ms}ms")
    end
  end

  defp handle_event([:dspex, :context, :variable_operation], measurements, metadata, _) do
    if measurements.duration_ms > 100 do
      Logger.warning("""
      Slow variable operation:
        Context: #{metadata.context_id}
        Operation: #{metadata.operation}
        Duration: #{measurements.duration_ms}ms
        Backend: #{inspect(metadata.backend)}
      """)
    end
  end

  defp handle_event([:dspex, :context, :error], _measurements, metadata, _) do
    Logger.error("""
    Context error:
      Context: #{metadata.context_id}
      Operation: #{metadata.operation}
      Error: #{inspect(metadata.error)}
      Backend: #{inspect(metadata.backend)}
    """)
  end

  @doc """
  Gets detailed context information for debugging.

  ## Example

      DSPex.Context.Monitor.inspect_context(ctx)
  """
  def inspect_context(context) do
    info = DSPex.Context.get_info(context)
    session_id = DSPex.Context.get_session_id(context)

    IO.puts("""

    DSPex Context Inspection
    ========================
    Session ID: #{session_id}
    Programs: #{info.program_count}
    Backend: #{info.metadata.backend}
    Created: #{info.metadata.created_at}
    """)

    # Try to get variable count
    case DSPex.Context.list_variables(context) do
      {:ok, vars} ->
        IO.puts("\nVariables: #{length(vars)}")

        if length(vars) > 0 do
          IO.puts("Recent variables:")

          vars
          |> Enum.take(5)
          |> Enum.each(fn var ->
            IO.puts("  - #{var.name} (#{var.type}): #{inspect(var.value, limit: 50)}")
          end)
        end

      _ ->
        IO.puts("\nVariables: Unable to retrieve")
    end

    :ok
  end

  @doc """
  Monitors a context and logs all operations.

  Useful for debugging. Returns a reference that can be used to stop monitoring.

  ## Example

      ref = DSPex.Context.Monitor.trace(ctx)
      # ... do operations ...
      DSPex.Context.Monitor.stop_trace(ref)
  """
  def trace(context) do
    ref = make_ref()

    # This would require modifying Context to support operation hooks
    # For now, we'll document the intended behavior
    Logger.info("Tracing context #{inspect(context)} - ref: #{inspect(ref)}")
    Logger.warning("Full tracing not yet implemented - use telemetry events instead")

    ref
  end

  @doc """
  Stops tracing a context.
  """
  def stop_trace(ref) do
    Logger.info("Stopping trace #{inspect(ref)}")
    :ok
  end

  @doc """
  Benchmarks variable operations on a context.

  Useful for comparing backend performance.
  """
  def benchmark_operations(context, iterations \\ 100) do
    IO.puts("\nBenchmarking context operations (#{iterations} iterations)...")

    # Get operation
    get_times =
      for _ <- 1..iterations do
        {time, _} =
          :timer.tc(fn ->
            DSPex.Context.get_variable(context, :benchmark_test)
          end)

        time
      end

    # Set operation
    set_times =
      for i <- 1..iterations do
        {time, _} =
          :timer.tc(fn ->
            DSPex.Context.set_variable(context, :benchmark_test, i, %{})
          end)

        time
      end

    # Report results
    info = DSPex.Context.get_info(context)

    IO.puts("""

    Backend: #{inspect(info.module)} (#{info.type})

    Get Variable:
      Average: #{format_time(Enum.sum(get_times) / iterations)}
      Min: #{format_time(Enum.min(get_times))}
      Max: #{format_time(Enum.max(get_times))}

    Set Variable:
      Average: #{format_time(Enum.sum(set_times) / iterations)}
      Min: #{format_time(Enum.min(set_times))}
      Max: #{format_time(Enum.max(set_times))}
    """)
  end

  @doc """
  Watches for backend switches and logs them.

  Returns a process that monitors the context.
  """
  def watch_switches(context) do
    spawn_link(fn ->
      initial = DSPex.Context.get_info(context)
      watch_loop(context, initial.switches)
    end)
  end

  # Private helpers


  defp format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)} μs"
  end

  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end

  defp watch_loop(context, last_switches) do
    Process.sleep(1000)

    case DSPex.Context.get_info(context) do
      %{switches: ^last_switches} ->
        # No change
        watch_loop(context, last_switches)

      %{switches: new_switches} = info ->
        Logger.info(
          "Context #{DSPex.Context.get_session_id(context)} switched backends! Now using #{inspect(info.metadata.backend)}"
        )

        watch_loop(context, new_switches)

      _ ->
        # Context might be dead
        :ok
    end
  end
end

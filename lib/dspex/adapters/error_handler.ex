defmodule DSPex.Adapters.ErrorHandler do
  @moduledoc """
  Centralized error handling for the adapter system.

  Provides standardized error handling, classification, recovery strategies,
  and user-friendly error messages across all adapter implementations.
  Supports error tracking, metrics, and debugging context.
  """

  require Logger

  @type error_context :: %{
          adapter: module(),
          operation: atom(),
          args: list() | map(),
          metadata: map()
        }

  @type error_classification ::
          :configuration_error
          | :connection_error
          | :timeout_error
          | :validation_error
          | :execution_error
          | :resource_error
          | :unknown_error

  @type recovery_strategy ::
          :retry
          | :retry_with_backoff
          | :failover
          | :log_and_continue
          | :immediate_failure

  @type enriched_error :: %{
          error: term(),
          adapter: module(),
          operation: atom() | nil,
          timestamp: DateTime.t(),
          formatted_message: String.t(),
          classification: error_classification(),
          recovery_strategy: recovery_strategy(),
          metadata: map()
        }

  @doc """
  Handles adapter-specific errors with appropriate recovery strategies.

  ## Examples

      ErrorHandler.handle_adapter_error(MockAdapter, {:program_not_found, "prog_123"})
      # => {:error, {:not_found, "Program 'prog_123' not found"}}
  """
  @spec handle_adapter_error(module(), term()) :: {:error, enriched_error()}
  def handle_adapter_error(adapter, error) do
    context = %{
      adapter: adapter,
      operation: :unknown,
      args: [],
      metadata: %{}
    }

    case classify_error(error) do
      :configuration_error ->
        handle_configuration_error(error, context)

      :connection_error ->
        handle_connection_error(error, context)

      :timeout_error ->
        handle_timeout_error_internal(error, context)

      :validation_error ->
        handle_validation_error(error, context)

      :execution_error ->
        handle_execution_error(error, context)

      :resource_error ->
        handle_resource_error(error, context)

      _ ->
        handle_unknown_error(error, context)
    end
  end

  @doc """
  Handles timeout errors with context-aware messaging.
  """
  @spec handle_timeout_error(module(), pos_integer()) :: {:error, term()}
  def handle_timeout_error(adapter, timeout_ms) do
    Logger.error("Adapter operation timed out",
      adapter: adapter,
      timeout_ms: timeout_ms
    )

    {:error, {:timeout, "Operation timed out after #{timeout_ms}ms"}}
  end

  @doc """
  Handles unexpected errors with full context capture.
  """
  @spec handle_unexpected_error(module(), atom(), term(), list()) :: {:error, term()}
  def handle_unexpected_error(adapter, kind, reason, stacktrace) do
    Logger.error("Unexpected error in adapter",
      adapter: adapter,
      kind: kind,
      reason: inspect(reason),
      stacktrace: Exception.format_stacktrace(stacktrace)
    )

    {:error, {:unexpected_error, format_unexpected_error(kind, reason)}}
  end

  @doc """
  Wraps an operation with comprehensive error handling.

  ## Examples

      ErrorHandler.with_error_handling(MockAdapter, :execute_program, fn ->
        # operation that might fail
      end)
  """
  @spec with_error_handling(module(), atom(), function()) :: {:ok, any()} | {:error, term()}
  def with_error_handling(adapter, operation, fun) do
    try do
      case fun.() do
        {:ok, _} = success -> success
        {:error, _} = error -> handle_adapter_error(adapter, error)
        result -> {:ok, result}
      end
    rescue
      exception ->
        handle_exception(adapter, operation, exception, __STACKTRACE__)
    catch
      kind, reason ->
        handle_unexpected_error(adapter, kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Provides a recovery strategy for a given error classification.

  ## Examples

      ErrorHandler.suggest_recovery(:connection_error)
      # => :retry_with_backoff
  """
  @spec suggest_recovery(error_classification()) :: recovery_strategy()
  def suggest_recovery(classification) do
    case classification do
      :configuration_error -> :immediate_failure
      :connection_error -> :retry_with_backoff
      :timeout_error -> :retry
      :validation_error -> :immediate_failure
      :execution_error -> :log_and_continue
      :resource_error -> :failover
      _ -> :log_and_continue
    end
  end

  @doc """
  Formats error for user-friendly display.

  Converts internal error representations to clear, actionable messages
  for end users while preserving technical details for debugging.
  """
  @spec format_error(term()) :: String.t()
  def format_error({:configuration_error, details}) do
    "Configuration error: #{details}. Please check your adapter settings."
  end

  def format_error({:connection_error, details}) do
    "Connection error: #{details}. Please ensure the service is running and accessible."
  end

  def format_error({:timeout, details}) do
    "Operation timed out: #{details}. Consider increasing the timeout or checking system load."
  end

  def format_error({:validation_error, field, reason}) do
    "Validation error for #{field}: #{reason}"
  end

  def format_error({:not_found, resource}) do
    "Resource not found: #{resource}"
  end

  def format_error({:permission_denied, resource}) do
    "Permission denied for: #{resource}"
  end

  def format_error(error) when is_binary(error) do
    error
  end

  def format_error(error) do
    "An error occurred: #{inspect(error)}"
  end

  @doc """
  Enriches error with additional context for debugging.

  Adds metadata, timestamps, and adapter information to errors
  for improved troubleshooting.
  """
  @spec enrich_error(term(), error_context()) :: enriched_error()
  def enrich_error(error, context) do
    %{
      error: error,
      adapter: context.adapter,
      operation: Map.get(context, :operation),
      timestamp: DateTime.utc_now(),
      formatted_message: format_error(error),
      classification: classify_error(error),
      recovery_strategy: suggest_recovery(classify_error(error)),
      metadata: Map.get(context, :metadata, %{})
    }
  end

  @doc """
  Tracks error metrics for monitoring and alerting.
  """
  @spec track_error(term(), error_context()) :: :ok
  def track_error(error, context) do
    classification = classify_error(error)

    # Telemetry integration would go here if :telemetry is available
    # :telemetry.execute(
    #   [:dspex, :adapter, :error],
    #   %{count: 1},
    #   %{
    #     adapter: context.adapter,
    #     classification: classification,
    #     operation: Map.get(context, :operation)
    #   }
    # )

    Logger.warning("Adapter error tracked",
      adapter: context.adapter,
      classification: classification,
      error: inspect(error)
    )

    :ok
  end

  # Private Functions

  defp classify_error({:configuration_error, _}), do: :configuration_error
  defp classify_error({:connection_refused, _}), do: :connection_error
  defp classify_error({:nxdomain, _}), do: :connection_error
  defp classify_error({:timeout, _}), do: :timeout_error
  defp classify_error(:timeout), do: :timeout_error
  defp classify_error({:validation_error, _, _}), do: :validation_error
  defp classify_error({:invalid_input, _}), do: :validation_error
  defp classify_error({:execution_failed, _}), do: :execution_error
  defp classify_error({:program_not_found, _}), do: :resource_error
  defp classify_error({:not_found, _}), do: :resource_error
  defp classify_error(_), do: :unknown_error

  defp handle_configuration_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.error("Configuration error in adapter",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_connection_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.error("Connection error in adapter",
      adapter: context.adapter,
      error: inspect(error),
      recovery: :retry_with_backoff
    )

    {:error, enriched}
  end

  defp handle_timeout_error_internal(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.warning("Timeout in adapter operation",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_validation_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.warning("Validation error in adapter",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_execution_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.error("Execution error in adapter",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_resource_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.warning("Resource error in adapter",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_unknown_error(error, context) do
    track_error(error, context)
    enriched = enrich_error(error, context)

    Logger.error("Unknown error in adapter",
      adapter: context.adapter,
      error: inspect(error)
    )

    {:error, enriched}
  end

  defp handle_exception(adapter, operation, exception, stacktrace) do
    Logger.error("Exception in adapter operation",
      adapter: adapter,
      operation: operation,
      exception: Exception.format(:error, exception),
      stacktrace: Exception.format_stacktrace(stacktrace)
    )

    error_type = exception.__struct__ |> Module.split() |> List.last() |> String.to_atom()

    {:error, {error_type, Exception.message(exception)}}
  end

  defp format_unexpected_error(:throw, reason) do
    "Unexpected throw: #{inspect(reason)}"
  end

  defp format_unexpected_error(:exit, reason) do
    "Process exited: #{inspect(reason)}"
  end

  defp format_unexpected_error(kind, reason) do
    "Unexpected #{kind}: #{inspect(reason)}"
  end
end

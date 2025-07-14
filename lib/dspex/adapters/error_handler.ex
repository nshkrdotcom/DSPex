defmodule DSPex.Adapters.ErrorHandler do
  @moduledoc """
  Standardized error handling for adapter operations with test layer awareness.
  """

  defstruct [:type, :message, :context, :recoverable, :retry_after, :test_layer]

  @type adapter_error :: %__MODULE__{
          type: atom(),
          message: String.t(),
          context: map(),
          recoverable: boolean(),
          retry_after: pos_integer() | nil,
          test_layer: atom() | nil
        }

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
  Wrap error with context and test layer awareness.
  """
  @spec wrap_error(term(), map()) :: adapter_error()
  def wrap_error(error, context \\ %{}) do
    test_layer = get_test_layer()

    case error do
      {:error, :timeout} ->
        %__MODULE__{
          type: :timeout,
          message: "Operation timed out",
          context: context,
          recoverable: true,
          retry_after: get_retry_delay(:timeout, test_layer),
          test_layer: test_layer
        }

      {:error, :connection_failed} ->
        %__MODULE__{
          type: :connection_failed,
          message: "Failed to connect to adapter backend",
          context: context,
          recoverable: should_retry_connection?(test_layer),
          retry_after: get_retry_delay(:connection_failed, test_layer),
          test_layer: test_layer
        }

      {:error, {:validation_failed, details}} ->
        %__MODULE__{
          type: :validation_failed,
          message: "Input validation failed: #{details}",
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }

      {:error, {:program_not_found, program_id}} ->
        %__MODULE__{
          type: :program_not_found,
          message: "Program not found: #{program_id}",
          context: Map.put(context, :program_id, program_id),
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }

      {:error, {:bridge_error, bridge_details}} ->
        %__MODULE__{
          type: :bridge_error,
          message: "Python bridge error: #{inspect(bridge_details)}",
          context: Map.put(context, :bridge_details, bridge_details),
          recoverable: should_retry_bridge_error?(bridge_details, test_layer),
          retry_after: get_retry_delay(:bridge_error, test_layer),
          test_layer: test_layer
        }

      {:error, reason} when is_binary(reason) ->
        %__MODULE__{
          type: :unknown,
          message: reason,
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }

      other ->
        %__MODULE__{
          type: :unexpected,
          message: "Unexpected error: #{inspect(other)}",
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }
    end
  end

  @spec should_retry?(adapter_error()) :: boolean()
  def should_retry?(%__MODULE__{recoverable: recoverable}), do: recoverable

  @spec get_retry_delay(adapter_error()) :: pos_integer() | nil
  def get_retry_delay(%__MODULE__{retry_after: delay}), do: delay

  @spec get_error_context(adapter_error()) :: map()
  def get_error_context(%__MODULE__{context: context}), do: context

  @spec is_test_error?(adapter_error()) :: boolean()
  def is_test_error?(%__MODULE__{test_layer: test_layer}) do
    test_layer in [:layer_1, :layer_2, :layer_3]
  end

  @doc """
  Format error for logging with test context.
  """
  @spec format_error(adapter_error()) :: String.t()
  def format_error(%__MODULE__{} = error) do
    base_msg = "#{error.type}: #{error.message}"

    case error.test_layer do
      nil -> base_msg
      layer -> "#{base_msg} [#{layer}]"
    end
  end

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

  # Test layer specific retry delays
  # Fast for mock tests
  defp get_retry_delay(:timeout, :layer_1), do: 100
  # Medium for protocol tests  
  defp get_retry_delay(:timeout, :layer_2), do: 500
  # Slower for integration tests
  defp get_retry_delay(:timeout, :layer_3), do: 5000
  defp get_retry_delay(:timeout, _), do: 5000

  defp get_retry_delay(:connection_failed, :layer_1), do: 100
  defp get_retry_delay(:connection_failed, :layer_2), do: 1000
  defp get_retry_delay(:connection_failed, :layer_3), do: 10000
  defp get_retry_delay(:connection_failed, _), do: 10000

  defp get_retry_delay(:bridge_error, test_layer) do
    get_retry_delay(:connection_failed, test_layer)
  end

  # Test layer specific retry logic
  # Mock should never fail connection
  defp should_retry_connection?(:layer_1), do: false
  # Protocol tests may need retries
  defp should_retry_connection?(:layer_2), do: true
  # Integration tests definitely need retries
  defp should_retry_connection?(:layer_3), do: true

  # No bridge in mock
  defp should_retry_bridge_error?(_details, :layer_1), do: false

  defp should_retry_bridge_error?(details, :layer_2) do
    # Protocol layer retries specific bridge protocol errors
    case details do
      %{type: :protocol_error} -> false
      %{type: :timeout} -> true
      _ -> false
    end
  end

  defp should_retry_bridge_error?(details, :layer_3) do
    # Full integration retries most bridge errors
    case details do
      %{type: :validation_error} -> false
      _ -> true
    end
  end

  defp get_test_layer do
    # Try to get test layer from environment or process
    case System.get_env("TEST_MODE") do
      "mock_adapter" -> :layer_1
      "bridge_mock" -> :layer_2
      "full_integration" -> :layer_3
      _ -> :layer_3
    end
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

defmodule DSPex.PythonBridge.PoolErrorHandler do
  @moduledoc """
  Comprehensive error handling for pool operations with recovery strategies.

  This module extends the base ErrorHandler with pool-specific error classification,
  severity assessment, and recovery strategy determination. It provides context-aware
  error handling that considers worker state, session information, and operational context.

  ## Error Categories

  - `:initialization_error` - Worker startup failures
  - `:connection_error` - Port/process connection issues  
  - `:communication_error` - Protocol/encoding errors
  - `:timeout_error` - Operation timeouts
  - `:resource_error` - Resource exhaustion
  - `:health_check_error` - Health monitoring failures
  - `:session_error` - Session management issues
  - `:python_error` - Python-side exceptions
  - `:system_error` - System-level failures

  ## Recovery Strategies

  - `:immediate_retry` - Retry immediately with minimal delay
  - `:backoff_retry` - Retry with exponential backoff
  - `:circuit_break` - Use circuit breaker protection
  - `:failover` - Switch to fallback adapter
  - `:abandon` - Don't retry, fail immediately
  """

  alias DSPex.Adapters.ErrorHandler
  require Logger

  defstruct [
    :type,
    :message,
    :context,
    :recoverable,
    :retry_after,
    :test_layer,
    :pool_error,
    :error_category,
    :severity,
    :recovery_strategy
  ]

  @type t :: %__MODULE__{
          type: atom(),
          message: binary(),
          context: map(),
          recoverable: boolean(),
          retry_after: nil | 100 | 500 | 1000 | 5000 | 10000,
          test_layer: :layer_1 | :layer_2 | :layer_3,
          pool_error: true,
          error_category: error_category(),
          severity: error_severity(),
          recovery_strategy: recovery_strategy()
        }

  @type error_category ::
          :initialization_error
          | :connection_error
          | :communication_error
          | :timeout_error
          | :resource_error
          | :health_check_error
          | :session_error
          | :python_error
          | :system_error

  @type error_severity :: :critical | :major | :minor | :warning

  @type recovery_strategy ::
          :immediate_retry | :backoff_retry | :circuit_break | :failover | :abandon

  @type error_context :: %{
          error_category: error_category(),
          severity: error_severity(),
          worker_id: String.t() | nil,
          session_id: String.t() | nil,
          operation: atom(),
          attempt: non_neg_integer(),
          metadata: map()
        }

  @retry_delays %{
    immediate_retry: [0, 100, 200],
    backoff_retry: [1_000, 2_000, 4_000, 8_000, 16_000],
    exponential: [1_000, 3_000, 9_000, 27_000]
  }

  @doc """
  Wraps pool-specific errors with context and recovery information.

  ## Parameters

  - `error` - The raw error to be wrapped
  - `context` - Additional context about the operation and environment

  ## Returns

  Enhanced error structure with pool-specific classification and recovery strategy.

  ## Examples

      context = %{
        worker_id: "worker_123",
        session_id: "session_456", 
        operation: :execute_command,
        attempt: 1
      }
      
      wrapped = PoolErrorHandler.wrap_pool_error({:port_exited, 1}, context)
      # => %{error_category: :connection_error, severity: :major, ...}
  """
  @spec wrap_pool_error(term(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:severity) => error_severity(),
          optional(:affecting_all_workers) => boolean(),
          optional(:user_facing) => boolean(),
          optional(:metadata) => map(),
          optional(:circuit) => atom(),
          optional(:time_until_retry) => non_neg_integer(),
          optional(:failure_count) => non_neg_integer(),
          optional(:concurrent_requests) => non_neg_integer(),
          optional(atom()) => term()
        }) :: t()
  def wrap_pool_error(error, context) do
    category = categorize_error(error)
    severity = determine_severity(category, context)
    strategy = determine_recovery_strategy(category, severity, context)

    enhanced_context =
      Map.merge(context, %{
        error_category: category,
        severity: severity,
        recovery_strategy: strategy,
        timestamp: System.os_time(:millisecond)
      })

    # Use base ErrorHandler for consistent structure
    wrapped = ErrorHandler.wrap_error(error, enhanced_context)

    # Create pool-specific struct
    %__MODULE__{
      type: wrapped.type,
      message: wrapped.message,
      context: wrapped.context,
      recoverable: wrapped.recoverable,
      retry_after: wrapped.retry_after,
      test_layer: wrapped.test_layer,
      pool_error: true,
      error_category: category,
      severity: severity,
      recovery_strategy: strategy
    }
  end

  @doc """
  Determines if an error should trigger a retry based on pool-specific rules.

  ## Parameters

  - `wrapped_error` - Error wrapped by `wrap_pool_error/2`
  - `attempt` - Current attempt number (default: 1)

  ## Returns

  Boolean indicating if retry should be attempted.
  """
  @spec should_retry?(t(), non_neg_integer()) :: boolean()
  def should_retry?(wrapped_error, attempt \\ 1) do
    case wrapped_error.recovery_strategy do
      :immediate_retry -> attempt <= 3
      :backoff_retry -> attempt <= 5
      # Let circuit breaker handle
      :circuit_break -> false
      :failover -> attempt == 1
      :abandon -> false
      _ -> ErrorHandler.should_retry?(wrapped_error)
    end
  end

  @doc """
  Calculates retry delay based on strategy and attempt number.

  ## Parameters

  - `wrapped_error` - Error with recovery strategy
  - `attempt` - Current attempt number

  ## Returns

  Delay in milliseconds before next retry attempt.
  """
  @spec get_retry_delay(t(), non_neg_integer()) :: non_neg_integer()
  def get_retry_delay(wrapped_error, attempt) do
    strategy = wrapped_error.recovery_strategy
    delays = Map.get(@retry_delays, strategy, [1_000])

    # Get delay for attempt, or last delay if beyond array
    Enum.at(delays, attempt - 1, List.last(delays))
  end

  @doc """
  Formats error for comprehensive logging with full context.

  ## Parameters

  - `wrapped_error` - Pool error with full context

  ## Returns

  Multi-line formatted string suitable for logging.
  """
  @spec format_for_logging(t()) :: String.t()
  def format_for_logging(wrapped_error) do
    """
    Pool Error: #{wrapped_error.message}
    Category: #{wrapped_error.error_category}
    Severity: #{wrapped_error.severity}
    Recovery: #{wrapped_error.recovery_strategy}
    Worker: #{wrapped_error.context[:worker_id] || "N/A"}
    Session: #{wrapped_error.context[:session_id] || "N/A"}
    Attempt: #{wrapped_error.context[:attempt] || 1}
    Context: #{inspect(wrapped_error.context, pretty: true)}
    """
  end

  ## Private Functions

  @spec categorize_error(term()) :: error_category()
  defp categorize_error(error) do
    case error do
      # Connection-related errors
      {:port_exited, _} -> :connection_error
      {:connect_failed, _} -> :connection_error
      {:checkout_failed, _} -> :resource_error
      # Timeout errors
      {:timeout, _} -> :timeout_error
      :timeout -> :timeout_error
      # Communication errors
      {:encode_error, _} -> :communication_error
      {:decode_error, _} -> :communication_error
      {:protocol_error, _} -> :communication_error
      # Health check errors
      {:health_check_failed, _} -> :health_check_error
      {:health_check_timeout, _} -> :health_check_error
      # Python-side errors
      {:python_exception, _} -> :python_error
      {:bridge_error, _} -> :python_error
      # Initialization errors
      {:init_failed, _} -> :initialization_error
      {:worker_init_failed, _} -> :initialization_error
      # Session errors
      {:session_not_found, _} -> :session_error
      {:session_expired, _} -> :session_error
      # Resource errors
      {:pool_exhausted, _} -> :resource_error
      {:resource_unavailable, _} -> :resource_error
      # Direct resource error tuples
      {:resource_error, _} -> :resource_error
      # Connection errors
      # Direct connection error tuples
      {:connection_error, _} -> :connection_error
      # Communication errors  
      # Direct communication error tuples
      {:communication_error, _} -> :communication_error
      # Python errors
      # Direct python error tuples
      {:python_error, _} -> :python_error
      # Generic error patterns
      {:error, inner} -> categorize_error(inner)
      # Common retryable errors
      # Make simple errors retryable
      {:simple_error, _} -> :communication_error
      {:retryable_error, _} -> :communication_error
      # String errors are often retryable
      error when is_binary(error) -> :communication_error
      # System-level failures
      _ -> :system_error
    end
  end

  @spec determine_severity(error_category(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:severity) => error_severity(),
          optional(:affecting_all_workers) => boolean(),
          optional(:user_facing) => boolean(),
          optional(:metadata) => map(),
          optional(atom()) => term()
        }) :: error_severity()
  defp determine_severity(category, context) do
    # Use provided severity if available, otherwise determine from category
    case Map.get(context, :severity) do
      severity when severity in [:critical, :major, :minor, :warning] ->
        severity

      _ ->
        determine_base_severity(category, context)
    end
  end

  @spec determine_base_severity(error_category(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:severity) => error_severity(),
          optional(:affecting_all_workers) => boolean(),
          optional(:user_facing) => boolean(),
          optional(:metadata) => map(),
          optional(atom()) => term()
        }) :: error_severity()
  defp determine_base_severity(category, context) do
    base_severity =
      case category do
        :initialization_error -> :critical
        :resource_error -> :critical
        :system_error -> :critical
        :connection_error -> :major
        :communication_error -> :major
        :timeout_error -> :major
        :python_error -> :major
        :health_check_error -> :minor
        :session_error -> :minor
      end

    # Adjust severity based on context
    cond do
      context[:attempt] && context[:attempt] > 3 -> upgrade_severity(base_severity)
      context[:affecting_all_workers] -> :critical
      context[:user_facing] && base_severity == :minor -> :major
      true -> base_severity
    end
  end

  @spec upgrade_severity(:minor | :major | :critical) :: :major | :critical
  defp upgrade_severity(:minor), do: :major
  defp upgrade_severity(:major), do: :critical
  defp upgrade_severity(:critical), do: :critical

  @spec determine_recovery_strategy(error_category(), error_severity(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:severity) => error_severity(),
          optional(:affecting_all_workers) => boolean(),
          optional(:user_facing) => boolean(),
          optional(:metadata) => map(),
          optional(atom()) => term()
        }) :: recovery_strategy()
  defp determine_recovery_strategy(category, severity, context) do
    # Check for abandonment conditions first
    cond do
      severity == :critical and Map.get(context, :attempt, 1) > 2 -> :abandon
      true -> determine_strategy_by_category(category, severity, context)
    end
  end

  @spec determine_strategy_by_category(error_category(), error_severity(), %{
          optional(:worker_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:operation) => atom(),
          optional(:attempt) => non_neg_integer(),
          optional(:severity) => error_severity(),
          optional(:affecting_all_workers) => boolean(),
          optional(:user_facing) => boolean(),
          optional(:metadata) => map(),
          optional(atom()) => term()
        }) :: recovery_strategy()
  defp determine_strategy_by_category(category, severity, _context) do
    case {category, severity} do
      # Resource errors - critical uses circuit breaker, major uses failover
      {:resource_error, :critical} -> :circuit_break
      {:resource_error, :major} -> :failover
      {:initialization_error, _} -> :circuit_break
      # Connection errors - critical severity uses circuit breaker
      {:connection_error, :critical} -> :circuit_break
      {:connection_error, _} -> :backoff_retry
      {:timeout_error, _} -> :backoff_retry
      # Communication errors retry immediately (likely transient)
      {:communication_error, :major} -> :immediate_retry
      {:communication_error, _} -> :immediate_retry
      # Health check errors use backoff
      {:health_check_error, _} -> :backoff_retry
      # Session errors retry immediately
      {:session_error, _} -> :immediate_retry
      # Python errors attempt failover
      {:python_error, _} -> :failover
      # System errors are generally not recoverable
      {:system_error, _} -> :abandon
      # Default to abandoning unknown patterns
      _ -> :abandon
    end
  end
end

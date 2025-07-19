defmodule DSPex.PythonBridge.Constants do
  @moduledoc """
  Constants and configuration values for the minimal Python pooling system.

  This module centralizes important constants used throughout the Golden Path
  architecture to ensure consistency and easy maintenance.
  """

  @doc """
  Default pool configuration values.
  """
  @default_pool_size System.schedulers_online()
  @default_overflow 2
  @default_checkout_timeout 5_000
  @default_operation_timeout 30_000

  def default_pool_size, do: @default_pool_size
  def default_overflow, do: @default_overflow
  def default_checkout_timeout, do: @default_checkout_timeout
  def default_operation_timeout, do: @default_operation_timeout

  @doc """
  Python process configuration.
  """
  @default_python_executable "python3"
  @default_script_path "priv/python/dspy_bridge.py"
  @python_startup_timeout 10_000
  @python_shutdown_timeout 5_000

  def default_python_executable, do: @default_python_executable
  def default_script_path, do: @default_script_path
  def python_startup_timeout, do: @python_startup_timeout
  def python_shutdown_timeout, do: @python_shutdown_timeout

  @doc """
  Protocol and communication constants.
  """
  @protocol_version "1.0"
  @message_delimiter "\n"
  # 1MB
  @max_message_size 1_048_576
  @ping_command "ping"
  @pong_response "pong"

  def protocol_version, do: @protocol_version
  def message_delimiter, do: @message_delimiter
  def max_message_size, do: @max_message_size
  def ping_command, do: @ping_command
  def pong_response, do: @pong_response

  @doc """
  Session tracking constants.
  """
  @session_table_name :dspex_sessions
  # 5 minutes
  @session_cleanup_interval 300_000
  # 30 minutes
  @session_timeout 1_800_000
  @max_sessions_per_cleanup 1000

  def session_table_name, do: @session_table_name
  def session_cleanup_interval, do: @session_cleanup_interval
  def session_timeout, do: @session_timeout
  def max_sessions_per_cleanup, do: @max_sessions_per_cleanup

  @doc """
  Health monitoring constants.
  """
  # 1 minute
  @health_check_interval 60_000
  # 5 seconds
  @health_check_timeout 5_000
  @failure_threshold 3
  # 5 seconds
  @recovery_delay 5_000
  @max_consecutive_failures 10

  def health_check_interval, do: @health_check_interval
  def health_check_timeout, do: @health_check_timeout
  def failure_threshold, do: @failure_threshold
  def recovery_delay, do: @recovery_delay
  def max_consecutive_failures, do: @max_consecutive_failures

  @doc """
  Supervision and restart constants.
  """
  @max_restarts 5
  @max_seconds 60
  @restart_strategy :one_for_one
  @worker_restart_type :permanent
  @supervisor_shutdown_timeout 10_000

  def max_restarts, do: @max_restarts
  def max_seconds, do: @max_seconds
  def restart_strategy, do: @restart_strategy
  def worker_restart_type, do: @worker_restart_type
  def supervisor_shutdown_timeout, do: @supervisor_shutdown_timeout

  @doc """
  Telemetry and logging constants.
  """
  @telemetry_prefix [:dspex, :python_bridge, :minimal_pool]
  @log_level :info
  # 10 seconds
  @metrics_collection_interval 10_000

  def telemetry_prefix, do: @telemetry_prefix
  def log_level, do: @log_level
  def metrics_collection_interval, do: @metrics_collection_interval

  @doc """
  Error handling constants.
  """
  @max_error_context_size 1000
  @error_retry_delay 1_000
  @max_error_retries 3

  def max_error_context_size, do: @max_error_context_size
  def error_retry_delay, do: @error_retry_delay
  def max_error_retries, do: @max_error_retries

  @doc """
  Test-specific constants.
  """
  @test_pool_size 2
  @test_overflow 1
  @test_timeout 10_000
  @test_session_prefix "test_session"

  def test_pool_size, do: @test_pool_size
  def test_overflow, do: @test_overflow
  def test_timeout, do: @test_timeout
  def test_session_prefix, do: @test_session_prefix

  @doc """
  Gets all constants as a map for inspection.
  """
  @spec all_constants() :: map()
  def all_constants do
    %{
      pool: %{
        default_pool_size: default_pool_size(),
        default_overflow: default_overflow(),
        default_checkout_timeout: default_checkout_timeout(),
        default_operation_timeout: default_operation_timeout()
      },
      python: %{
        default_executable: default_python_executable(),
        default_script_path: default_script_path(),
        startup_timeout: python_startup_timeout(),
        shutdown_timeout: python_shutdown_timeout()
      },
      protocol: %{
        version: protocol_version(),
        delimiter: message_delimiter(),
        max_message_size: max_message_size(),
        ping_command: ping_command(),
        pong_response: pong_response()
      },
      session: %{
        table_name: session_table_name(),
        cleanup_interval: session_cleanup_interval(),
        timeout: session_timeout(),
        max_cleanup_batch: max_sessions_per_cleanup()
      },
      health: %{
        check_interval: health_check_interval(),
        check_timeout: health_check_timeout(),
        failure_threshold: failure_threshold(),
        recovery_delay: recovery_delay(),
        max_consecutive_failures: max_consecutive_failures()
      },
      supervision: %{
        max_restarts: max_restarts(),
        max_seconds: max_seconds(),
        restart_strategy: restart_strategy(),
        worker_restart_type: worker_restart_type(),
        shutdown_timeout: supervisor_shutdown_timeout()
      },
      telemetry: %{
        prefix: telemetry_prefix(),
        log_level: log_level(),
        metrics_interval: metrics_collection_interval()
      },
      errors: %{
        max_context_size: max_error_context_size(),
        retry_delay: error_retry_delay(),
        max_retries: max_error_retries()
      },
      test: %{
        pool_size: test_pool_size(),
        overflow: test_overflow(),
        timeout: test_timeout(),
        session_prefix: test_session_prefix()
      }
    }
  end

  @doc """
  Validates that all constants are within reasonable ranges.
  """
  @spec validate_constants() :: :ok | {:error, [String.t()]}
  def validate_constants do
    issues = []

    # Validate timeouts are positive
    issues =
      validate_positive_integer(default_checkout_timeout(), "default_checkout_timeout", issues)

    issues =
      validate_positive_integer(default_operation_timeout(), "default_operation_timeout", issues)

    issues = validate_positive_integer(python_startup_timeout(), "python_startup_timeout", issues)

    issues =
      validate_positive_integer(python_shutdown_timeout(), "python_shutdown_timeout", issues)

    # Validate pool sizes are positive
    issues = validate_positive_integer(default_pool_size(), "default_pool_size", issues)
    issues = validate_non_negative_integer(default_overflow(), "default_overflow", issues)

    # Validate thresholds are positive
    issues = validate_positive_integer(failure_threshold(), "failure_threshold", issues)

    issues =
      validate_positive_integer(max_consecutive_failures(), "max_consecutive_failures", issues)

    case issues do
      [] -> :ok
      problems -> {:error, Enum.reverse(problems)}
    end
  end

  # Private helper functions
  defp validate_positive_integer(value, _name, issues) when is_integer(value) and value > 0,
    do: issues

  defp validate_positive_integer(value, name, issues),
    do: ["#{name} must be a positive integer, got: #{inspect(value)}" | issues]

  defp validate_non_negative_integer(value, _name, issues) when is_integer(value) and value >= 0,
    do: issues

  defp validate_non_negative_integer(value, name, issues),
    do: ["#{name} must be a non-negative integer, got: #{inspect(value)}" | issues]
end

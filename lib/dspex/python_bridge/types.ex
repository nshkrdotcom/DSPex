defmodule DSPex.PythonBridge.Types do
  @moduledoc """
  Core data types and structures for the minimal Python pooling system.

  This module defines the essential data structures used throughout the
  Golden Path architecture, focusing on simplicity and stateless operations.
  """

  @typedoc """
  Worker state structure for PoolWorkerV2.

  Maintains essential worker information without complex state management.
  The current_session field is always nil in the stateless architecture.
  """
  @type worker_state :: %{
          port: port() | nil,
          python_path: String.t(),
          script_path: String.t(),
          worker_id: String.t(),
          current_session: nil,
          stats: worker_stats(),
          health_status: health_status(),
          started_at: integer()
        }

  @typedoc """
  Worker statistics for monitoring and observability.
  """
  @type worker_stats :: %{
          checkouts: non_neg_integer(),
          successful_checkins: non_neg_integer(),
          error_checkins: non_neg_integer(),
          last_activity: integer()
        }

  @typedoc """
  Health status of a worker process.
  """
  @type health_status :: :healthy | :initializing | :unhealthy

  @typedoc """
  Pool configuration structure for minimal pooling.
  """
  @type pool_config :: %{
          pool_size: pos_integer(),
          overflow: non_neg_integer(),
          checkout_timeout: pos_integer(),
          operation_timeout: pos_integer(),
          python_executable: String.t(),
          script_path: String.t(),
          health_check_enabled: boolean(),
          session_tracking_enabled: boolean()
        }

  @typedoc """
  Session tracking information stored in ETS.
  Used for monitoring and observability only, not for stateful routing.
  """
  @type session_info :: %{
          session_id: String.t(),
          started_at: integer(),
          last_activity: integer(),
          operations: non_neg_integer()
        }

  @typedoc """
  Structured error response format.
  """
  @type error_response :: {:error, {error_category(), error_type(), String.t(), map()}}

  @typedoc """
  Error categories for structured error handling.
  """
  @type error_category :: :timeout_error | :resource_error | :communication_error | :system_error

  @typedoc """
  Specific error types within each category.
  """
  @type error_type ::
          :checkout_timeout
          | :operation_timeout
          | :pool_unavailable
          | :worker_init_failed
          | :port_closed
          | :protocol_error
          | :supervisor_crash
          | :worker_crash

  @typedoc """
  Pool status information for monitoring.
  """
  @type pool_status :: %{
          pool_size: pos_integer(),
          available_workers: non_neg_integer(),
          checked_out_workers: non_neg_integer(),
          overflow_workers: non_neg_integer(),
          total_checkouts: non_neg_integer(),
          total_checkins: non_neg_integer(),
          health_status: :healthy | :degraded | :unhealthy
        }

  @typedoc """
  Command execution options.
  """
  @type execution_options :: %{
          timeout: pos_integer(),
          session_id: String.t() | nil,
          metadata: map()
        }

  @doc """
  Creates a new worker state structure with default values.
  """
  @spec new_worker_state(String.t(), String.t(), String.t()) :: worker_state()
  def new_worker_state(worker_id, python_path, script_path) do
    %{
      port: nil,
      python_path: python_path,
      script_path: script_path,
      worker_id: worker_id,
      current_session: nil,
      stats: %{
        checkouts: 0,
        successful_checkins: 0,
        error_checkins: 0,
        last_activity: System.system_time(:millisecond)
      },
      health_status: :initializing,
      started_at: System.system_time(:millisecond)
    }
  end

  @doc """
  Creates a new session info structure.
  """
  @spec new_session_info(String.t()) :: session_info()
  def new_session_info(session_id) do
    now = System.system_time(:millisecond)

    %{
      session_id: session_id,
      started_at: now,
      last_activity: now,
      operations: 0
    }
  end

  @doc """
  Creates a structured error response.
  """
  @spec error(error_category(), error_type(), String.t(), map()) :: error_response()
  def error(category, type, message, context \\ %{}) do
    {:error, {category, type, message, context}}
  end

  @doc """
  Updates worker statistics after a successful operation.
  """
  @spec update_worker_stats_success(worker_state()) :: worker_state()
  def update_worker_stats_success(worker_state) do
    %{
      worker_state
      | stats: %{
          worker_state.stats
          | successful_checkins: worker_state.stats.successful_checkins + 1,
            last_activity: System.system_time(:millisecond)
        }
    }
  end

  @doc """
  Updates worker statistics after a failed operation.
  """
  @spec update_worker_stats_error(worker_state()) :: worker_state()
  def update_worker_stats_error(worker_state) do
    %{
      worker_state
      | stats: %{
          worker_state.stats
          | error_checkins: worker_state.stats.error_checkins + 1,
            last_activity: System.system_time(:millisecond)
        }
    }
  end

  @doc """
  Updates worker statistics after checkout.
  """
  @spec update_worker_stats_checkout(worker_state()) :: worker_state()
  def update_worker_stats_checkout(worker_state) do
    %{
      worker_state
      | stats: %{
          worker_state.stats
          | checkouts: worker_state.stats.checkouts + 1,
            last_activity: System.system_time(:millisecond)
        }
    }
  end

  @doc """
  Updates session info after an operation.
  """
  @spec update_session_info(session_info()) :: session_info()
  def update_session_info(session_info) do
    %{
      session_info
      | last_activity: System.system_time(:millisecond),
        operations: session_info.operations + 1
    }
  end
end

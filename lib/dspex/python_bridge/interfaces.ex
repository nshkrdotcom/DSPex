defmodule DSPex.PythonBridge.Interfaces do
  @moduledoc """
  Core interfaces and behavior contracts for the minimal Python pooling system.

  This module defines the essential behaviors that components in the Golden Path
  architecture must implement, focusing on simplicity and clear contracts.
  """

  alias DSPex.PythonBridge.Types

  @doc """
  Behavior for pool adapters that provide the public API.

  Pool adapters are responsible for providing a simple, consistent interface
  to clients while delegating to the underlying pool management layer.
  """
  @callback execute_program(String.t(), map(), map()) ::
              {:ok, term()} | Types.error_response()

  @callback health_check(map()) ::
              :ok | Types.error_response()

  @callback get_stats(map()) ::
              {:ok, Types.pool_status()} | Types.error_response()

  @doc """
  Behavior for pool managers that handle worker lifecycle and operations.

  Pool managers coordinate between the public API and the actual worker pool,
  handling session tracking and operation routing.
  """
  @callback execute_in_session(String.t(), atom(), map(), keyword()) ::
              {:ok, term()} | Types.error_response()

  @callback execute_anonymous(atom(), map(), keyword()) ::
              {:ok, term()} | Types.error_response()

  @callback get_pool_status(keyword()) ::
              {:ok, Types.pool_status()} | Types.error_response()

  @doc """
  Behavior for worker processes that manage individual Python processes.

  Workers implement the NimblePool callbacks and handle direct communication
  with Python processes through ports.
  """
  @callback init_worker(map()) ::
              {:ok, Types.worker_state()} | {:error, term()}

  @callback handle_checkout(term(), term(), Types.worker_state(), keyword()) ::
              {:ok, term(), Types.worker_state()} | {:error, term()}

  @callback handle_checkin(term(), term(), Types.worker_state(), keyword()) ::
              {:ok, Types.worker_state()} | {:error, term()}

  @callback terminate_worker(term(), Types.worker_state(), keyword()) ::
              :ok

  @doc """
  Behavior for session tracking components.

  Session trackers provide observability and monitoring capabilities
  without enforcing stateful routing or affinity.
  """
  @callback track_session(String.t()) :: :ok | {:error, term()}

  @callback update_session_activity(String.t()) :: :ok | {:error, term()}

  @callback get_session_info(String.t()) ::
              {:ok, Types.session_info()} | {:error, :not_found}

  @callback cleanup_expired_sessions(pos_integer()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Behavior for protocol handlers that manage communication with Python processes.

  Protocol handlers encode/decode messages and manage the communication
  protocol between Elixir and Python processes.
  """
  @callback encode_message(atom(), map()) ::
              {:ok, binary()} | {:error, term()}

  @callback decode_response(binary()) ::
              {:ok, map()} | {:error, term()}

  @callback validate_message(map()) ::
              :ok | {:error, String.t()}

  @doc """
  Behavior for health monitors that track pool and worker health.

  Health monitors provide non-intrusive monitoring and alerting
  without interfering with the core request path.
  """
  @callback check_pool_health() ::
              {:ok, :healthy | :degraded | :unhealthy} | {:error, term()}

  @callback check_worker_health(String.t()) ::
              {:ok, Types.health_status()} | {:error, term()}

  @callback get_health_metrics() ::
              {:ok, map()} | {:error, term()}

  @doc """
  Validates execution options and provides defaults.
  """
  @spec validate_execution_options(map()) ::
          {:ok, Types.execution_options()} | {:error, String.t()}
  def validate_execution_options(options) when is_map(options) do
    config = DSPex.Config.get(:minimal_python_pool)

    validated_options = %{
      timeout: Map.get(options, :timeout, config.operation_timeout),
      session_id: Map.get(options, :session_id),
      metadata: Map.get(options, :metadata, %{})
    }

    case validated_options do
      %{timeout: timeout} when is_integer(timeout) and timeout > 0 ->
        {:ok, validated_options}

      %{timeout: invalid_timeout} ->
        {:error, "Invalid timeout value: #{inspect(invalid_timeout)}"}

      _ ->
        {:error, "Invalid options structure"}
    end
  end

  def validate_execution_options(_), do: {:error, "Options must be a map"}

  @doc """
  Generates a unique worker ID.
  """
  @spec generate_worker_id() :: String.t()
  def generate_worker_id do
    "worker_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  @doc """
  Generates a unique session ID if none is provided.
  """
  @spec ensure_session_id(String.t() | nil) :: String.t()
  def ensure_session_id(nil) do
    "session_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  def ensure_session_id(session_id) when is_binary(session_id), do: session_id

  @doc """
  Creates a timeout error response.
  """
  @spec timeout_error(Types.error_type(), String.t(), map()) :: Types.error_response()
  def timeout_error(type, message, context \\ %{}) do
    Types.error(:timeout_error, type, message, context)
  end

  @doc """
  Creates a resource error response.
  """
  @spec resource_error(Types.error_type(), String.t(), map()) :: Types.error_response()
  def resource_error(type, message, context \\ %{}) do
    Types.error(:resource_error, type, message, context)
  end

  @doc """
  Creates a communication error response.
  """
  @spec communication_error(Types.error_type(), String.t(), map()) :: Types.error_response()
  def communication_error(type, message, context \\ %{}) do
    Types.error(:communication_error, type, message, context)
  end

  @doc """
  Creates a system error response.
  """
  @spec system_error(Types.error_type(), String.t(), map()) :: Types.error_response()
  def system_error(type, message, context \\ %{}) do
    Types.error(:system_error, type, message, context)
  end

  @doc """
  Validates that a module implements the required behavior.
  """
  @spec validate_behavior_implementation(module(), module()) :: :ok | {:error, String.t()}
  def validate_behavior_implementation(module, behavior) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        behaviors = module.module_info(:attributes)[:behaviour] || []

        if behavior in behaviors do
          :ok
        else
          {:error, "Module #{inspect(module)} does not implement behavior #{inspect(behavior)}"}
        end

      {:error, reason} ->
        {:error, "Could not load module #{inspect(module)}: #{inspect(reason)}"}
    end
  end
end

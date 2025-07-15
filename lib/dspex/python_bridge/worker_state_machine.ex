defmodule DSPex.PythonBridge.WorkerStateMachine do
  @moduledoc """
  Implements a state machine for pool worker lifecycle management.

  This module provides a formal state machine that tracks worker states,
  validates transitions, and maintains history for monitoring and debugging.

  ## Worker States

  - `:initializing` - Worker is starting up
  - `:ready` - Worker is available for work
  - `:busy` - Worker is processing a request
  - `:degraded` - Worker is functional but experiencing issues
  - `:terminating` - Worker is shutting down
  - `:terminated` - Worker has completed shutdown

  ## Health States

  - `:healthy` - Worker is operating normally
  - `:unhealthy` - Worker has health issues but may recover
  - `:unknown` - Health status has not been determined
  """

  require Logger

  @type state :: :initializing | :ready | :busy | :degraded | :terminating | :terminated
  @type health :: :healthy | :unhealthy | :unknown
  @type transition_reason ::
          :init_complete
          | :checkout
          | :checkin_success
          | :checkin_error
          | :health_check_failed
          | :health_check_passed
          | :health_restored
          | :shutdown
          | :terminate
          | :error
          | :timeout
          | :recovery_degrade

  @type t :: %__MODULE__{
          state: state(),
          health: health(),
          worker_id: String.t(),
          metadata: map(),
          transition_history: list(),
          entered_state_at: integer()
        }

  defstruct [
    :state,
    :health,
    :worker_id,
    :metadata,
    :transition_history,
    :entered_state_at
  ]

  @valid_transitions %{
    initializing: [:ready, :terminated],
    ready: [:busy, :degraded, :terminating],
    busy: [:ready, :degraded, :terminating],
    degraded: [:ready, :terminating],
    terminating: [:terminated],
    terminated: []
  }

  @doc """
  Creates a new state machine for a worker.

  ## Parameters

  - `worker_id` - Unique identifier for the worker

  ## Returns

  A new state machine instance in the `:initializing` state with `:unknown` health.
  """
  @spec new(String.t()) :: t()
  def new(worker_id) do
    %__MODULE__{
      state: :initializing,
      health: :unknown,
      worker_id: worker_id,
      metadata: %{},
      transition_history: [],
      entered_state_at: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Attempts to transition to a new state.

  ## Parameters

  - `machine` - The current state machine
  - `new_state` - The target state
  - `reason` - The reason for the transition
  - `metadata` - Additional metadata for the transition (optional)

  ## Returns

  - `{:ok, updated_machine}` if transition is valid
  - `{:error, {:invalid_transition, current_state, new_state}}` if invalid
  """
  @spec transition(t(), state(), transition_reason(), map()) ::
          {:ok, t()} | {:error, {:invalid_transition, state(), state()}}
  def transition(%__MODULE__{state: current} = machine, new_state, reason, metadata \\ %{}) do
    valid_transitions = Map.get(@valid_transitions, current, [])

    if new_state in valid_transitions do
      {:ok, do_transition(machine, new_state, reason, metadata)}
    else
      {:error, {:invalid_transition, current, new_state}}
    end
  end

  @doc """
  Checks if worker can accept work.

  Returns `true` only if state is `:ready` and health is `:healthy`.
  """
  @spec can_accept_work?(t()) :: boolean()
  def can_accept_work?(%__MODULE__{state: :ready, health: :healthy}), do: true
  def can_accept_work?(_), do: false

  @doc """
  Checks if worker should be removed from pool.

  Returns `true` if state is `:terminating` or `:terminated`.
  """
  @spec should_remove?(t()) :: boolean()
  def should_remove?(%__MODULE__{state: state}) when state in [:terminating, :terminated],
    do: true

  def should_remove?(_), do: false

  @doc """
  Updates health status.

  ## Parameters

  - `machine` - The current state machine
  - `health` - New health status (`:healthy`, `:unhealthy`, or `:unknown`)

  ## Returns

  Updated state machine with new health status.
  """
  @spec update_health(t(), health()) :: t()
  def update_health(%__MODULE__{} = machine, health)
      when health in [:healthy, :unhealthy, :unknown] do
    %{machine | health: health}
  end

  # Private Functions

  defp do_transition(machine, new_state, reason, metadata) do
    now = System.monotonic_time(:millisecond)
    duration = now - machine.entered_state_at

    history_entry = %{
      from: machine.state,
      to: new_state,
      reason: reason,
      duration_ms: duration,
      timestamp: System.os_time(:millisecond),
      metadata: metadata
    }

    Logger.info(
      "Worker #{machine.worker_id} transitioning #{machine.state} -> #{new_state} (reason: #{reason})"
    )

    # Record metrics for state transition
    try do
      alias DSPex.PythonBridge.WorkerMetrics

      WorkerMetrics.record_transition(
        machine.worker_id,
        machine.state,
        new_state,
        duration,
        metadata
      )
    rescue
      # Don't fail transitions due to metrics issues
      _ -> :ok
    end

    %{
      machine
      | state: new_state,
        entered_state_at: now,
        transition_history: [history_entry | machine.transition_history],
        metadata: Map.merge(machine.metadata, metadata)
    }
  end
end

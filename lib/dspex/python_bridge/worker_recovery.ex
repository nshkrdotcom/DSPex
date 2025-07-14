defmodule DSPex.PythonBridge.WorkerRecovery do
  @moduledoc """
  Implements recovery strategies for failed workers.
  
  This module analyzes worker failures and determines the appropriate recovery
  strategy based on the failure type, worker state, and context. It integrates
  with the existing ErrorHandler for consistent error classification and retry logic.
  
  ## Recovery Actions
  
  - `:retry` - Retry the operation after a delay
  - `:degrade` - Mark worker as degraded but keep it running
  - `:remove` - Remove the worker from the pool
  - `:replace` - Remove worker and request immediate replacement
  
  ## Decision Factors
  
  - Type of failure (port exit, health check, timeout, etc.)
  - Worker's current state and health
  - Number of previous failures
  - Context of the operation that failed
  """
  
  alias DSPex.Adapters.ErrorHandler
  alias DSPex.PythonBridge.{WorkerStateMachine, SessionAffinity}
  require Logger
  
  @type recovery_action :: :retry | :degrade | :remove | :replace
  @type recovery_strategy :: %{
    action: recovery_action(),
    delay: non_neg_integer(),
    metadata: map()
  }
  
  @doc """
  Determines recovery strategy based on failure context.
  
  ## Parameters
  
  - `failure_reason` - The reason for the failure
  - `worker_state` - Current worker state containing state machine and stats
  - `context` - Additional context about the failure (optional)
  
  ## Returns
  
  A recovery strategy map with action, delay, and metadata.
  
  ## Examples
  
      # Port failure - immediate removal
      determine_strategy({:port_exited, 1}, worker_state)
      # => %{action: :remove, delay: 0, metadata: %{reason: :port_failure}}
      
      # Health check failure - progressive degradation
      determine_strategy({:health_check_failed, :timeout}, worker_state)
      # => %{action: :degrade, delay: 5_000, metadata: %{reason: :health_degraded}}
  """
  @spec determine_strategy(term(), map(), map()) :: recovery_strategy()
  def determine_strategy(failure_reason, worker_state, context \\ %{}) do
    # Wrap error with ErrorHandler for consistent classification
    wrapped_error = ErrorHandler.wrap_error(
      {:error, failure_reason},
      Map.merge(context, %{
        worker_id: worker_state.worker_id,
        worker_state: worker_state.state_machine.state,
        health_status: worker_state.state_machine.health,
        failure_count: Map.get(worker_state, :health_check_failures, 0)
      })
    )
    
    Logger.debug("Determining recovery strategy for worker #{worker_state.worker_id}, failure: #{inspect(failure_reason)}")
    
    cond do
      # Port-related failures - immediate removal
      match?({:port_exited, _}, failure_reason) ->
        Logger.warning("Worker #{worker_state.worker_id} port exited, removing immediately")
        %{action: :remove, delay: 0, metadata: %{reason: :port_failure, exit_status: elem(failure_reason, 1)}}
        
      # Port connection failures during checkout
      match?({:checkout_failed, _}, failure_reason) ->
        Logger.warning("Worker #{worker_state.worker_id} checkout failed, removing")
        %{action: :remove, delay: 0, metadata: %{reason: :checkout_failure, details: elem(failure_reason, 1)}}
        
      # Health check failures - progressive degradation
      match?({:health_check_failed, _}, failure_reason) ->
        determine_health_failure_strategy(worker_state, failure_reason, wrapped_error)
        
      # Timeout during operations
      match?({:timeout, _}, failure_reason) ->
        determine_timeout_strategy(worker_state, failure_reason, wrapped_error)
        
      # Max failures exceeded
      match?({:max_failures_exceeded, _}, failure_reason) ->
        Logger.error("Worker #{worker_state.worker_id} exceeded max failures, removing")
        %{action: :remove, delay: 0, metadata: %{reason: :max_failures, details: elem(failure_reason, 1)}}
        
      # Worker not ready for checkout
      match?({:worker_not_ready, _}, failure_reason) ->
        Logger.warning("Worker #{worker_state.worker_id} not ready, removing")
        %{action: :remove, delay: 0, metadata: %{reason: :not_ready, state: elem(failure_reason, 1)}}
        
      # Generic errors - check if recoverable
      ErrorHandler.should_retry?(wrapped_error) ->
        retry_delay = ErrorHandler.get_retry_delay(wrapped_error) || 1_000
        Logger.info("Worker #{worker_state.worker_id} error is recoverable, retrying after #{retry_delay}ms")
        %{action: :retry, delay: retry_delay, metadata: %{error_type: wrapped_error.type}}
        
      # Non-recoverable errors
      true ->
        Logger.error("Worker #{worker_state.worker_id} non-recoverable error, removing")
        %{action: :remove, delay: 0, metadata: %{reason: :non_recoverable, error_type: wrapped_error.type}}
    end
  end
  
  @doc """
  Executes recovery action based on strategy.
  
  ## Parameters
  
  - `strategy` - Recovery strategy from `determine_strategy/3`
  - `worker_state` - Current worker state
  - `pool_state` - Current pool state
  
  ## Returns
  
  Appropriate NimblePool response tuple based on the action.
  """
  @spec execute_recovery(recovery_strategy(), map(), term()) :: 
    {:retry, non_neg_integer()} | 
    {:ok, map()} | 
    {:remove, term(), term()}
  def execute_recovery(strategy, worker_state, pool_state) do
    case strategy.action do
      :retry ->
        Logger.info("Retrying worker #{worker_state.worker_id} operation after #{strategy.delay}ms")
        {:retry, strategy.delay}
        
      :degrade ->
        degrade_worker(worker_state, pool_state, strategy.metadata)
        
      :remove ->
        remove_worker(worker_state, pool_state, strategy.metadata)
        
      :replace ->
        replace_worker(worker_state, pool_state, strategy.metadata)
    end
  end
  
  @doc """
  Checks if a failure reason indicates a recoverable error.
  
  ## Examples
  
      is_recoverable?({:health_check_failed, :timeout})
      # => true
      
      is_recoverable?({:port_exited, 1})
      # => false
  """
  @spec is_recoverable?(term()) :: boolean()
  def is_recoverable?(failure_reason) do
    case failure_reason do
      {:health_check_failed, _} -> true
      {:timeout, _} -> true
      {:temporary_failure, _} -> true
      {:port_exited, _} -> false
      {:checkout_failed, _} -> false
      {:max_failures_exceeded, _} -> false
      {:worker_not_ready, _} -> false
      _ -> false
    end
  end
  
  @doc """
  Gets appropriate delay for a given failure type.
  
  ## Examples
  
      get_failure_delay({:health_check_failed, :timeout})
      # => 5_000
      
      get_failure_delay({:timeout, "Operation timeout"})
      # => 3_000
  """
  @spec get_failure_delay(term()) :: non_neg_integer()
  def get_failure_delay(failure_reason) do
    case failure_reason do
      {:health_check_failed, _} -> 5_000
      {:timeout, _} -> 3_000
      {:temporary_failure, _} -> 1_000
      {:connection_failed, _} -> 10_000
      _ -> 1_000
    end
  end
  
  ## Private Functions
  
  defp determine_health_failure_strategy(worker_state, _failure_reason, wrapped_error) do
    failures = Map.get(worker_state, :health_check_failures, 0) + 1
    max_failures = 3  # This should match the constant in enhanced worker
    
    if failures >= max_failures do
      Logger.error("Worker #{worker_state.worker_id} health check failures exceeded limit (#{failures}/#{max_failures})")
      %{action: :remove, delay: 0, metadata: %{reason: :health_check_limit, failure_count: failures}}
    else
      Logger.warning("Worker #{worker_state.worker_id} health check failed (#{failures}/#{max_failures}), degrading")
      delay = ErrorHandler.get_retry_delay(wrapped_error) || 5_000
      %{action: :degrade, delay: delay, metadata: %{reason: :health_degraded, failure_count: failures}}
    end
  end
  
  defp determine_timeout_strategy(worker_state, failure_reason, wrapped_error) do
    if ErrorHandler.should_retry?(wrapped_error) do
      delay = ErrorHandler.get_retry_delay(wrapped_error) || 3_000
      Logger.info("Worker #{worker_state.worker_id} timeout is recoverable, retrying after #{delay}ms")
      %{action: :retry, delay: delay, metadata: %{reason: :timeout_retry}}
    else
      Logger.warning("Worker #{worker_state.worker_id} timeout not recoverable, removing")
      %{action: :remove, delay: 0, metadata: %{reason: :timeout_limit, details: failure_reason}}
    end
  end
  
  defp degrade_worker(worker_state, pool_state, metadata) do
    Logger.warning("Degrading worker #{worker_state.worker_id}: #{inspect(metadata)}")
    
    case WorkerStateMachine.transition(
      worker_state.state_machine,
      :degraded,
      :recovery_degrade,
      metadata
    ) do
      {:ok, new_state_machine} ->
        updated_worker = %{worker_state | 
          state_machine: WorkerStateMachine.update_health(new_state_machine, :unhealthy)
        }
        
        {:ok, updated_worker, pool_state}
        
      {:error, reason} ->
        Logger.error("Failed to transition worker #{worker_state.worker_id} to degraded state: #{inspect(reason)}")
        {:remove, {:state_transition_failed, reason}, pool_state}
    end
  end
  
  defp remove_worker(worker_state, pool_state, metadata) do
    Logger.info("Removing worker #{worker_state.worker_id}: #{inspect(metadata)}")
    
    # Clean up session affinity if SessionAffinity is running
    try do
      SessionAffinity.remove_worker_sessions(worker_state.worker_id)
    rescue
      _ -> 
        # SessionAffinity might not be running, that's ok
        :ok
    end
    
    # Record metrics if available
    record_worker_removal(worker_state, metadata)
    
    {:remove, {:recovery_removal, metadata}, pool_state}
  end
  
  defp replace_worker(worker_state, pool_state, metadata) do
    Logger.info("Replacing worker #{worker_state.worker_id}: #{inspect(metadata)}")
    
    # Clean up session affinity
    try do
      SessionAffinity.remove_worker_sessions(worker_state.worker_id)
    rescue
      _ -> :ok
    end
    
    # Signal pool manager to create replacement if it supports it
    if is_pid(pool_state) do
      send(pool_state, {:replace_worker, worker_state.worker_id, metadata})
    end
    
    record_worker_replacement(worker_state, metadata)
    
    {:remove, {:replaced, metadata}, pool_state}
  end
  
  defp record_worker_removal(worker_state, metadata) do
    Logger.info("Worker #{worker_state.worker_id} removed",
      reason: Map.get(metadata, :reason),
      uptime_ms: System.monotonic_time(:millisecond) - Map.get(worker_state, :started_at, 0),
      checkouts: get_in(worker_state, [:stats, :checkouts]) || 0,
      health_failures: Map.get(worker_state, :health_check_failures, 0)
    )
    
    # TODO: Add telemetry when available
    # :telemetry.execute(
    #   [:dspex, :pool, :worker, :removed],
    #   %{count: 1},
    #   %{
    #     worker_id: worker_state.worker_id,
    #     reason: Map.get(metadata, :reason),
    #     state: worker_state.state_machine.state
    #   }
    # )
  end
  
  defp record_worker_replacement(worker_state, metadata) do
    Logger.info("Worker #{worker_state.worker_id} replaced",
      reason: Map.get(metadata, :reason),
      uptime_ms: System.monotonic_time(:millisecond) - Map.get(worker_state, :started_at, 0)
    )
    
    # TODO: Add telemetry when available
    # :telemetry.execute(
    #   [:dspex, :pool, :worker, :replaced],
    #   %{count: 1},
    #   %{
    #     worker_id: worker_state.worker_id,
    #     reason: Map.get(metadata, :reason)
    #   }
    # )
  end
end
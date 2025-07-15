defmodule DSPex.PythonBridge.RetryLogic do
  @moduledoc """
  Implements sophisticated retry logic with various backoff strategies.

  This module provides flexible retry mechanisms that can be used standalone
  or integrated with circuit breakers. It supports multiple backoff strategies
  to handle different failure patterns effectively.

  ## Backoff Strategies

  - `:linear` - Linear increase: delay = attempt * base_delay
  - `:exponential` - Exponential backoff: delay = base_delay * 2^(attempt-1)
  - `:fibonacci` - Fibonacci sequence: delay = fib(attempt) * base_delay
  - `:decorrelated_jitter` - AWS-style decorrelated jitter for distributed systems
  - Custom function - Provide your own delay calculation function

  ## Features

  - Configurable max attempts and delays
  - Circuit breaker integration
  - Comprehensive error handling
  - Telemetry support
  - Context preservation across retries

  ## Usage

      # Simple retry with exponential backoff
      RetryLogic.with_retry(fn ->
        risky_operation()
      end, max_attempts: 3, backoff: :exponential)
      
      # With circuit breaker protection
      RetryLogic.with_retry(fn ->
        database_query()
      end, circuit: :database_operations)
      
      # Custom backoff function
      custom_backoff = fn attempt -> attempt * 1000 + :rand.uniform(500) end
      RetryLogic.with_retry(operation, backoff: custom_backoff)
  """

  alias DSPex.PythonBridge.{PoolErrorHandler, CircuitBreaker}
  require Logger

  @type backoff_strategy ::
          :linear | :exponential | :fibonacci | :decorrelated_jitter | function()

  @type retry_options :: [
          max_attempts: pos_integer(),
          backoff: backoff_strategy(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          circuit: atom() | nil,
          jitter: boolean(),
          context: map()
        ]

  @doc """
  Executes a function with retry logic based on error handling rules.

  ## Parameters

  - `fun` - Function to execute (should return {:ok, result} or {:error, reason})
  - `opts` - Retry configuration options

  ## Options

  - `:max_attempts` - Maximum retry attempts (default: 3)
  - `:backoff` - Backoff strategy (default: :exponential)
  - `:base_delay` - Base delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay cap in milliseconds (default: 30000)
  - `:circuit` - Circuit breaker name for protection (default: nil)
  - `:jitter` - Add random jitter to delays (default: true)
  - `:context` - Additional context for error handling (default: %{})

  ## Returns

  `{:ok, result}` on success or `{:error, final_error}` after all retries exhausted.

  ## Examples

      # Basic retry with defaults
      RetryLogic.with_retry(fn -> fetch_data() end)
      
      # Custom configuration
      RetryLogic.with_retry(
        fn -> unreliable_api_call() end,
        max_attempts: 5,
        backoff: :fibonacci,
        base_delay: 500,
        max_delay: 10_000,
        circuit: :api_circuit
      )
  """
  @spec with_retry(function(), retry_options()) :: {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    backoff = Keyword.get(opts, :backoff, :exponential)
    base_delay = Keyword.get(opts, :base_delay, 1_000)
    max_delay = Keyword.get(opts, :max_delay, 30_000)
    circuit = Keyword.get(opts, :circuit, nil)
    jitter = Keyword.get(opts, :jitter, true)
    context = Keyword.get(opts, :context, %{})

    do_retry(fun, 1, max_attempts, backoff, base_delay, max_delay, circuit, jitter, context, nil)
  end

  @doc """
  Calculates delay for a given attempt using specified strategy.

  This function is exposed for testing and custom retry implementations.

  ## Parameters

  - `attempt` - Current attempt number (1-based)
  - `strategy` - Backoff strategy
  - `base_delay` - Base delay in milliseconds
  - `max_delay` - Maximum delay cap
  - `jitter` - Whether to add random jitter

  ## Returns

  Delay in milliseconds, capped at max_delay.
  """
  @spec calculate_delay(
          pos_integer(),
          backoff_strategy(),
          pos_integer(),
          pos_integer(),
          boolean()
        ) :: non_neg_integer()
  def calculate_delay(attempt, strategy, base_delay, max_delay, jitter \\ true) do
    delay =
      case strategy do
        :linear ->
          attempt * base_delay

        :exponential ->
          round(:math.pow(2, attempt - 1) * base_delay)

        :fibonacci ->
          fib(attempt) * base_delay

        :decorrelated_jitter ->
          calculate_decorrelated_jitter(attempt, base_delay, max_delay)

        custom when is_function(custom, 1) ->
          try do
            custom.(attempt)
          rescue
            _ ->
              # Fall back to exponential if custom function fails
              round(:math.pow(2, attempt - 1) * base_delay)
          end

        _ ->
          # Default to exponential
          round(:math.pow(2, attempt - 1) * base_delay)
      end

    capped_delay = min(delay, max_delay)

    final_delay =
      if jitter and strategy != :decorrelated_jitter do
        add_jitter(capped_delay)
      else
        capped_delay
      end

    # Ensure delay is never negative
    max(0, final_delay)
  end

  ## Private Functions

  @spec do_retry(
          function(),
          pos_integer(),
          pos_integer(),
          backoff_strategy(),
          pos_integer(),
          pos_integer(),
          atom() | nil,
          boolean(),
          map(),
          term()
        ) :: {:ok, term()} | {:error, term()}
  defp do_retry(
         fun,
         attempt,
         max_attempts,
         backoff,
         base_delay,
         max_delay,
         circuit,
         jitter,
         context,
         _last_error
       ) do
    # Execute through circuit breaker if configured and available
    result =
      if circuit && circuit_breaker_available?() do
        CircuitBreaker.with_circuit(circuit, fun)
      else
        try do
          case fun.() do
            {:ok, _} = success -> success
            {:error, _} = error -> error
            # Treat non-tuple returns as success
            other -> {:ok, other}
          end
        catch
          kind, error -> {:error, {kind, error}}
        end
      end

    case result do
      {:ok, value} ->
        if attempt > 1 do
          Logger.info("Retry succeeded on attempt #{attempt}/#{max_attempts}")

          emit_telemetry(
            :retry_success,
            %{attempt: attempt, total_attempts: max_attempts},
            context
          )
        end

        {:ok, value}

      {:error, error} ->
        wrapped_error = wrap_error(error, attempt, context)

        if attempt < max_attempts and should_retry?(wrapped_error, attempt) do
          delay = calculate_delay(attempt, backoff, base_delay, max_delay, jitter)

          Logger.warning(
            "Retry attempt #{attempt}/#{max_attempts} failed, retrying in #{delay}ms: #{inspect(error)}"
          )

          emit_telemetry(
            :retry_attempt,
            %{attempt: attempt, delay: delay},
            Map.merge(context, %{error: error})
          )

          Process.sleep(delay)

          do_retry(
            fun,
            attempt + 1,
            max_attempts,
            backoff,
            base_delay,
            max_delay,
            circuit,
            jitter,
            context,
            wrapped_error
          )
        else
          Logger.error(
            "All retry attempts exhausted (#{attempt}/#{max_attempts}): #{inspect(error)}"
          )

          emit_telemetry(
            :retry_exhausted,
            %{final_attempt: attempt, max_attempts: max_attempts},
            Map.merge(context, %{error: error})
          )

          {:error, wrapped_error}
        end
    end
  end

  @spec wrap_error(term(), pos_integer(), map()) :: map()
  defp wrap_error(error, attempt, context) do
    case error do
      %{pool_error: true} = wrapped ->
        # Already wrapped, update attempt
        %{wrapped | context: Map.put(wrapped.context, :attempt, attempt)}

      _ ->
        # Wrap the error with retry context
        enhanced_context =
          Map.merge(context, %{
            attempt: attempt,
            retry_context: true
          })

        PoolErrorHandler.wrap_pool_error(error, enhanced_context)
    end
  end

  @spec should_retry?(PoolErrorHandler.t(), pos_integer()) :: boolean()
  defp should_retry?(wrapped_error, attempt) do
    # Check if the error is retryable based on its recovery strategy
    case Map.get(wrapped_error, :recovery_strategy) do
      :abandon -> false
      # Let circuit breaker handle
      :circuit_break -> false
      _ -> PoolErrorHandler.should_retry?(wrapped_error, attempt)
    end
  end

  # Fibonacci calculation with memoization for efficiency
  @spec fib(pos_integer()) :: pos_integer()
  defp fib(n) when n <= 2, do: 1

  defp fib(n) do
    # Use process dictionary for simple memoization
    case Process.get({:fib, n}) do
      nil ->
        result = fib(n - 1) + fib(n - 2)
        Process.put({:fib, n}, result)
        result

      cached ->
        cached
    end
  end

  @spec calculate_decorrelated_jitter(pos_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer() | float()
  defp calculate_decorrelated_jitter(_attempt, base_delay, max_delay) do
    # AWS-style decorrelated jitter
    # See: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/

    last_delay =
      case Process.get(:last_retry_delay) do
        nil -> base_delay
        delay -> delay
      end

    # Random value between base_delay and min(max_delay, last_delay * 3)
    upper_bound = min(max_delay, last_delay * 3)
    new_delay = base_delay + round(:rand.uniform() * (upper_bound - base_delay))

    Process.put(:last_retry_delay, new_delay)
    new_delay
  end

  @spec add_jitter(non_neg_integer()) :: non_neg_integer()
  defp add_jitter(delay) do
    # Add ±25% jitter to break up thundering herd
    # 25% of delay
    jitter_range = div(delay, 4)
    jitter = :rand.uniform(jitter_range * 2) - jitter_range
    max(0, delay + jitter)
  end

  @spec circuit_breaker_available?() :: boolean()
  defp circuit_breaker_available? do
    case Process.whereis(CircuitBreaker) do
      nil -> false
      _pid -> true
    end
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    try do
      :telemetry.execute(
        [:dspex, :retry, event],
        measurements,
        metadata
      )
    rescue
      _ ->
        # Telemetry not available, log instead
        Logger.debug("Retry #{event}: #{inspect(measurements)} - #{inspect(metadata)}")
    end

    :ok
  end
end

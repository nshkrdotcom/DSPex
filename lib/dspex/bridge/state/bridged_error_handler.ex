defmodule DSPex.Bridge.State.BridgedErrorHandler do
  @moduledoc """
  Error handling utilities for BridgedState.

  Provides helpers for:
  - Session error handling
  - Retry logic with exponential backoff
  - Error categorization
  """

  require Logger

  @doc """
  Wraps SessionStore calls with proper error handling.

  Categorizes errors as:
  - `:session_expired` - Session no longer exists
  - `:temporary` - Transient errors that can be retried
  - `:permanent` - Errors that won't resolve with retry
  """
  defmacro with_session(_session_id, do: block) do
    quote do
      try do
        unquote(block)
      rescue
        e in [RuntimeError, ArgumentError] ->
          message = Exception.message(e)

          cond do
            String.contains?(message, "session") or
                String.contains?(message, "not found") ->
              {:error, :session_expired}

            String.contains?(message, "timeout") or
                String.contains?(message, "unavailable") ->
              {:error, {:temporary, e}}

            true ->
              reraise e, __STACKTRACE__
          end
      catch
        :exit, {:timeout, _} ->
          {:error, {:temporary, :timeout}}

        :exit, {:noproc, _} ->
          {:error, :session_expired}
      end
    end
  end

  @doc """
  Retries an operation with exponential backoff.

  Options:
  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:base_delay` - Initial delay in ms (default: 100)
  - `:max_delay` - Maximum delay in ms (default: 5000)
  - `:jitter` - Add randomness to delays (default: true)
  """
  def retry_with_backoff(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay = Keyword.get(opts, :base_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 5000)
    jitter = Keyword.get(opts, :jitter, true)

    do_retry(fun, 0, max_retries, base_delay, max_delay, jitter)
  end

  @doc """
  Categorizes an error as temporary or permanent.
  """
  def categorize_error({:error, :session_expired}), do: :permanent
  def categorize_error({:error, :not_found}), do: :permanent
  def categorize_error({:error, {:temporary, _}}), do: :temporary
  def categorize_error({:error, :timeout}), do: :temporary
  def categorize_error({:error, {:validation_failed, _}}), do: :permanent
  def categorize_error({:error, {:already_exists, _}}), do: :permanent
  def categorize_error(_), do: :unknown

  # Private helpers

  defp do_retry(fun, attempt, max_attempts, base_delay, max_delay, jitter) do
    case fun.() do
      {:error, _} = error when attempt < max_attempts ->
        case categorize_error(error) do
          :temporary ->
            delay = calculate_delay(attempt, base_delay, max_delay, jitter)
            Logger.debug("Retrying after #{delay}ms (attempt #{attempt + 1}/#{max_attempts})")
            Process.sleep(delay)
            do_retry(fun, attempt + 1, max_attempts, base_delay, max_delay, jitter)

          :permanent ->
            # Don't retry permanent errors
            error

          :unknown ->
            # Retry unknown errors cautiously
            if attempt < div(max_attempts, 2) do
              delay = calculate_delay(attempt, base_delay, max_delay, jitter)
              Process.sleep(delay)
              do_retry(fun, attempt + 1, max_attempts, base_delay, max_delay, jitter)
            else
              error
            end
        end

      result ->
        result
    end
  end

  defp calculate_delay(attempt, base_delay, max_delay, jitter) do
    # Exponential backoff: base * 2^attempt
    delay = min(base_delay * :math.pow(2, attempt), max_delay) |> round()

    if jitter do
      # Add ±25% jitter
      jitter_amount = round(delay * 0.25)
      delay + :rand.uniform(jitter_amount * 2) - jitter_amount
    else
      delay
    end
  end
end

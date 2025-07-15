defmodule DSPex.PythonBridge.Utils do
  @moduledoc """
  Utility functions for the minimal Python pooling system.

  This module provides common helper functions used throughout the Golden Path
  architecture, focusing on simplicity and reusability.
  """

  require Logger
  alias DSPex.PythonBridge.{Types, Constants}

  @doc """
  Generates a unique identifier with a prefix.
  """
  @spec generate_id(String.t()) :: String.t()
  def generate_id(prefix) when is_binary(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end

  @doc """
  Gets the current timestamp in milliseconds.
  """
  @spec current_timestamp() :: integer()
  def current_timestamp do
    System.system_time(:millisecond)
  end

  @doc """
  Calculates the elapsed time since a given timestamp.
  """
  @spec elapsed_time(integer()) :: integer()
  def elapsed_time(start_time) when is_integer(start_time) do
    current_timestamp() - start_time
  end

  @doc """
  Checks if a timeout has been exceeded.
  """
  @spec timeout_exceeded?(integer(), integer()) :: boolean()
  def timeout_exceeded?(start_time, timeout_ms)
      when is_integer(start_time) and is_integer(timeout_ms) do
    elapsed_time(start_time) > timeout_ms
  end

  @doc """
  Safely converts a term to a string for logging.
  """
  @spec safe_inspect(term(), keyword()) :: String.t()
  def safe_inspect(term, opts \\ []) do
    max_length = Keyword.get(opts, :limit, Constants.max_error_context_size())

    try do
      inspected = inspect(term, limit: max_length, printable_limit: max_length)

      if String.length(inspected) > max_length do
        String.slice(inspected, 0, max_length) <> "..."
      else
        inspected
      end
    rescue
      _ -> "<uninspectable>"
    end
  end

  @doc """
  Logs a message with structured context.
  """
  @spec log_with_context(atom(), String.t(), map()) :: :ok
  def log_with_context(level, message, context \\ %{}) do
    context_str =
      if map_size(context) > 0 do
        " [#{safe_inspect(context)}]"
      else
        ""
      end

    Logger.log(level, "#{message}#{context_str}")
  end

  @doc """
  Creates a standardized log context map.
  """
  @spec log_context(keyword()) :: map()
  def log_context(opts \\ []) do
    base_context = %{
      timestamp: current_timestamp(),
      node: Node.self()
    }

    Enum.reduce(opts, base_context, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Validates that a value is within expected bounds.
  """
  @spec validate_bounds(number(), number(), number()) :: :ok | {:error, String.t()}
  def validate_bounds(value, min, max)
      when is_number(value) and is_number(min) and is_number(max) do
    cond do
      value < min -> {:error, "Value #{value} is below minimum #{min}"}
      value > max -> {:error, "Value #{value} is above maximum #{max}"}
      true -> :ok
    end
  end

  @doc """
  Safely executes a function with a timeout.
  """
  @spec with_timeout(function(), integer()) :: {:ok, term()} | {:error, :timeout}
  def with_timeout(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @doc """
  Retries a function with exponential backoff.
  """
  @spec retry_with_backoff(function(), integer(), integer()) :: {:ok, term()} | {:error, term()}
  def retry_with_backoff(fun, max_retries \\ 3, base_delay \\ 1000) when is_function(fun, 0) do
    retry_with_backoff(fun, max_retries, base_delay, 0, nil)
  end

  defp retry_with_backoff(_fun, max_retries, _base_delay, attempt, last_error)
       when attempt >= max_retries do
    {:error, last_error || :max_retries_exceeded}
  end

  defp retry_with_backoff(fun, max_retries, base_delay, attempt, _last_error) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        if attempt < max_retries - 1 do
          delay = base_delay * :math.pow(2, attempt)
          :timer.sleep(trunc(delay))
        end

        retry_with_backoff(fun, max_retries, base_delay, attempt + 1, error)

      other ->
        {:error, {:unexpected_return, other}}
    end
  end

  @doc """
  Merges two maps deeply, with the second map taking precedence.
  """
  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      if is_map(left_val) and is_map(right_val) do
        deep_merge(left_val, right_val)
      else
        right_val
      end
    end)
  end

  @doc """
  Converts a keyword list to a map with atom keys.
  """
  @spec keyword_to_map(keyword()) :: map()
  def keyword_to_map(keyword_list) when is_list(keyword_list) do
    Enum.into(keyword_list, %{})
  end

  @doc """
  Sanitizes a map by removing nil values and limiting size.
  """
  @spec sanitize_map(map(), integer()) :: map()
  def sanitize_map(map, max_size \\ 50) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.take(max_size)
    |> Enum.into(%{})
  end

  @doc """
  Formats a duration in milliseconds to a human-readable string.
  """
  @spec format_duration(integer()) :: String.t()
  def format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1_000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1_000, 1)}s"
      ms < 3_600_000 -> "#{Float.round(ms / 60_000, 1)}m"
      true -> "#{Float.round(ms / 3_600_000, 1)}h"
    end
  end

  @doc """
  Checks if a process is alive and responsive.
  """
  @spec process_alive?(pid()) :: boolean()
  def process_alive?(pid) when is_pid(pid) do
    Process.alive?(pid) and
      case Process.info(pid, :status) do
        {:status, :running} -> true
        {:status, :runnable} -> true
        {:status, :waiting} -> true
        _ -> false
      end
  end

  def process_alive?(_), do: false

  @doc """
  Gets system information relevant to pool operations.
  """
  @spec system_info() :: map()
  def system_info do
    %{
      schedulers: System.schedulers_online(),
      memory: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      node: Node.self(),
      otp_release: :erlang.system_info(:otp_release),
      timestamp: current_timestamp()
    }
  end

  @doc """
  Creates a structured error context map.
  """
  @spec error_context(keyword()) :: map()
  def error_context(opts \\ []) do
    base_context = %{
      timestamp: current_timestamp(),
      node: Node.self(),
      process: self()
    }

    context =
      Enum.reduce(opts, base_context, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)

    sanitize_map(context, 20)
  end

  @doc """
  Validates that required keys are present in a map.
  """
  @spec validate_required_keys(map(), [atom()]) :: :ok | {:error, [atom()]}
  def validate_required_keys(map, required_keys) when is_map(map) and is_list(required_keys) do
    missing_keys = Enum.reject(required_keys, &Map.has_key?(map, &1))

    case missing_keys do
      [] -> :ok
      missing -> {:error, missing}
    end
  end

  @doc """
  Truncates a string to a maximum length.
  """
  @spec truncate_string(String.t(), integer()) :: String.t()
  def truncate_string(string, max_length) when is_binary(string) and is_integer(max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - 3) <> "..."
    else
      string
    end
  end

  @doc """
  Converts an error tuple to a standardized format.
  """
  @spec normalize_error(term()) :: Types.error_response()
  def normalize_error({:error, {category, type, message, context}})
      when is_atom(category) and is_atom(type) and is_binary(message) and is_map(context) do
    {:error, {category, type, message, context}}
  end

  def normalize_error({:error, reason}) do
    Types.error(:system_error, :unknown_error, safe_inspect(reason), error_context())
  end

  def normalize_error(other) do
    Types.error(:system_error, :unexpected_error, safe_inspect(other), error_context())
  end

  @doc """
  Checks if an error is retryable based on its type.
  """
  @spec retryable_error?(Types.error_response()) :: boolean()
  def retryable_error?({:error, {category, type, _message, _context}}) do
    case {category, type} do
      {:timeout_error, :checkout_timeout} -> true
      {:communication_error, :port_closed} -> false
      {:resource_error, :pool_unavailable} -> true
      {:resource_error, :worker_init_failed} -> false
      {:system_error, _} -> false
      _ -> false
    end
  end

  def retryable_error?(_), do: false
end

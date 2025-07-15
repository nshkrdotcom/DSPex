defmodule DSPex.Adapters.PythonPoolV2 do
  @moduledoc """
  Python pool adapter using refactored SessionPoolV2 with proper NimblePool pattern.

  This version uses the corrected SessionPoolV2 that allows true concurrent execution
  by moving blocking I/O operations to client processes.

  Key differences from V1:
  - Uses SessionPoolV2 which doesn't block the pool manager
  - Calls execute_in_session/4 directly as a public function
  - True concurrent execution of Python operations
  """

  @behaviour DSPex.Adapters.Adapter

  alias DSPex.PythonBridge.SessionPoolV2
  alias DSPex.PythonBridge.PoolErrorHandler

  require Logger

  # Default session for anonymous operations
  @default_session "anonymous"

  ## Adapter Callbacks

  @impl true
  def create_program(config) do
    session_id = get_session_id(config)

    # Convert config for Python bridge
    python_config = convert_config(config)

    # Extract pool options if present
    pool_opts = get_pool_opts(config)

    # This now runs in the client process, not the pool manager
    case SessionPoolV2.execute_in_session(session_id, :create_program, python_config, pool_opts) do
      {:ok, response} ->
        program_id = extract_program_id(response)
        {:ok, program_id}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    execute_program(program_id, inputs, %{})
  end

  @impl true
  def execute_program(program_id, inputs, options) do
    session_id = get_session_id(options)

    args = %{
      program_id: program_id,
      inputs: inputs,
      options: Map.delete(options, :session_id)
    }

    # Extract pool options
    pool_opts = get_pool_opts(options)

    # Direct execution in client process
    case SessionPoolV2.execute_in_session(session_id, :execute_program, args, pool_opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def list_programs do
    list_programs(%{})
  end

  def list_programs(options) do
    session_id = get_session_id(options)
    pool_opts = get_pool_opts(options)

    case SessionPoolV2.execute_in_session(session_id, :list_programs, %{}, pool_opts) do
      {:ok, %{"programs" => programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}

      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, &extract_program_id/1)
        {:ok, program_ids}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def delete_program(program_id) do
    delete_program(program_id, %{})
  end

  def delete_program(program_id, options) do
    session_id = get_session_id(options)
    pool_opts = get_pool_opts(options)

    case SessionPoolV2.execute_in_session(
           session_id,
           :delete_program,
           %{program_id: program_id},
           pool_opts
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> handle_pool_error(reason)
    end
  end

  @impl true
  def get_program_info(program_id) do
    get_program_info(program_id, %{})
  end

  def get_program_info(program_id, options) do
    session_id = get_session_id(options)
    pool_opts = get_pool_opts(options)

    case SessionPoolV2.execute_in_session(
           session_id,
           :get_program_info,
           %{program_id: program_id},
           pool_opts
         ) do
      {:ok, info} ->
        enhanced_info =
          Map.merge(info, %{
            "id" => program_id,
            :id => program_id,
            :session_id => session_id
          })

        {:ok, enhanced_info}

      {:error, reason} ->
        handle_pool_error(reason)
    end
  end

  @impl true
  def health_check do
    health_check(%{})
  end

  def health_check(options) do
    # Anonymous operation doesn't need session
    case SessionPoolV2.execute_anonymous(:ping, %{}, options) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{status: "ok"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unhealthy}
    end
  end

  @impl true
  def get_stats do
    get_stats(%{})
  end

  def get_stats(options) do
    session_id = get_session_id(options)
    pool_name = Map.get(options, :pool_name)
    pool_opts = get_pool_opts(options)

    # Get pool-level stats from the GenServer
    pool_status =
      if pool_name do
        SessionPoolV2.get_pool_status(pool_name)
      else
        SessionPoolV2.get_pool_status()
      end

    # Get session-specific stats if requested
    session_stats =
      if session_id != @default_session do
        case SessionPoolV2.execute_in_session(session_id, :get_stats, %{}, pool_opts) do
          {:ok, stats} -> stats
          _ -> %{}
        end
      else
        %{}
      end

    # Combine stats
    {:ok,
     %{
       adapter_type: :python_pool_v2,
       layer: :production,
       pool_status: pool_status,
       session_stats: session_stats,
       python_execution: true,
       concurrent_sessions: true,
       # Key difference from V1
       true_concurrency: true
     }}
  end

  @impl true
  def configure_lm(config) do
    configure_lm(config, %{})
  end

  def configure_lm(config, options) do
    # Configure LM globally (all workers will use it)
    case SessionPoolV2.execute_anonymous(:configure_lm, config, options) do
      {:ok, %{"status" => "configured"}} -> :ok
      {:ok, %{status: "configured"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :configuration_failed}
    end
  end

  @impl true
  def supports_test_layer?(layer), do: layer == :production

  @impl true
  def get_test_capabilities do
    %{
      python_execution: true,
      real_ml_models: true,
      protocol_validation: true,
      deterministic_outputs: false,
      # Better than V1
      performance: :highly_optimized,
      requires_environment: [:python, :dspy, :nimble_pool],
      concurrent_execution: true,
      # Key difference
      true_concurrent_execution: true,
      session_isolation: true,
      production_ready: true
    }
  end

  ## Session Management

  @doc """
  Starts a new session for isolated operations.
  """
  def start_session(session_id, _opts \\ []) do
    # Session tracking happens in ETS on first use
    Logger.debug("Starting session: #{session_id}")
    {:ok, session_id}
  end

  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    SessionPoolV2.end_session(session_id)
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    SessionPoolV2.get_session_info()
  end

  @doc """
  Creates a session-bound adapter instance.
  """
  def session_adapter(session_id, pool_name \\ nil) do
    opts = if pool_name, do: %{pool_name: pool_name}, else: %{}

    %{
      create_program: fn config ->
        create_program(Map.merge(config, Map.put(opts, :session_id, session_id)))
      end,
      execute_program: fn program_id, inputs, extra_opts ->
        merged_opts = Map.merge(extra_opts || %{}, Map.put(opts, :session_id, session_id))
        execute_program(program_id, inputs, merged_opts)
      end,
      list_programs: fn ->
        list_programs(Map.put(opts, :session_id, session_id))
      end,
      delete_program: fn program_id ->
        delete_program(program_id, Map.put(opts, :session_id, session_id))
      end,
      get_program_info: fn program_id ->
        get_program_info(program_id, Map.put(opts, :session_id, session_id))
      end,
      get_stats: fn ->
        get_stats(Map.put(opts, :session_id, session_id))
      end,
      health_check: fn ->
        health_check(opts)
      end,
      session_id: session_id
    }
  end

  @doc """
  Creates an adapter instance bound to a specific pool.
  """
  def with_pool_name(pool_name) do
    %{
      create_program: fn config ->
        create_program(Map.put(config, :pool_name, pool_name))
      end,
      execute_program: fn program_id, inputs, opts ->
        execute_program(program_id, inputs, Map.put(opts || %{}, :pool_name, pool_name))
      end,
      list_programs: fn ->
        list_programs(%{pool_name: pool_name})
      end,
      delete_program: fn program_id ->
        delete_program(program_id, %{pool_name: pool_name})
      end,
      get_program_info: fn program_id ->
        get_program_info(program_id, %{pool_name: pool_name})
      end,
      get_stats: fn ->
        get_stats(%{pool_name: pool_name})
      end,
      health_check: fn ->
        health_check(%{pool_name: pool_name})
      end,
      configure_lm: fn config ->
        configure_lm(config, %{pool_name: pool_name})
      end,
      session_adapter: fn session_id ->
        session_adapter(session_id, pool_name)
      end
    }
  end

  ## Private Functions

  defp get_session_id(config_or_options) do
    Map.get(config_or_options, :session_id, @default_session)
  end

  defp convert_config(config) do
    config
    |> Map.new(fn
      {:id, value} -> {"id", value}
      {"id", value} -> {"id", value}
      {:signature, value} -> {"signature", convert_signature(value)}
      {"signature", value} -> {"signature", convert_signature(value)}
      # Keep session_id as atom
      {:session_id, value} -> {:session_id, value}
      {key, value} -> {to_string(key), value}
    end)
    |> ensure_program_id()
  end

  defp convert_signature(signature) when is_atom(signature) do
    DSPex.Adapters.TypeConverter.convert_signature_to_format(signature, :python)
  end

  defp convert_signature(signature) when is_map(signature) do
    signature
    |> Map.new(fn
      {:inputs, value} -> {"inputs", convert_io_list(value)}
      {"inputs", value} -> {"inputs", convert_io_list(value)}
      {:outputs, value} -> {"outputs", convert_io_list(value)}
      {"outputs", value} -> {"outputs", convert_io_list(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp convert_signature(signature), do: signature

  defp convert_io_list(io_list) when is_list(io_list) do
    Enum.map(io_list, fn item ->
      Map.new(item, fn
        {:name, value} -> {"name", value}
        {"name", value} -> {"name", value}
        {:type, value} -> {"type", value}
        {"type", value} -> {"type", value}
        {key, value} -> {to_string(key), value}
      end)
    end)
  end

  defp convert_io_list(io_list), do: io_list

  defp ensure_program_id(config) do
    case Map.get(config, "id") do
      nil -> Map.put(config, "id", generate_program_id())
      "" -> Map.put(config, "id", generate_program_id())
      _id -> config
    end
  end

  defp extract_program_id(response) when is_map(response) do
    Map.get(response, "program_id") ||
      Map.get(response, :program_id) ||
      Map.get(response, "id") ||
      Map.get(response, :id)
  end

  defp extract_program_id(id) when is_binary(id), do: id

  defp generate_program_id do
    "pool_#{:erlang.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end

  defp handle_pool_error(%PoolErrorHandler{error_category: :timeout_error} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(%PoolErrorHandler{error_category: :resource_error} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(%PoolErrorHandler{error_category: :communication_error} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(%PoolErrorHandler{type: :response_mismatch} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(%PoolErrorHandler{type: :malformed_response} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(%PoolErrorHandler{} = error) do
    {:error, PoolErrorHandler.format_for_logging(error)}
  end

  defp handle_pool_error(reason) do
    {:error, reason}
  end

  defp get_pool_opts(options) do
    case Map.get(options, :pool_name) do
      nil -> []
      pool_name -> [pool_name: pool_name]
    end
  end
end

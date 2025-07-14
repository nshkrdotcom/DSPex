defmodule DSPex.Adapters.PythonPool do
  @moduledoc """
  Python pool adapter using NimblePool for concurrent session isolation.

  This adapter provides a production-ready implementation with:
  - Process pool management
  - Session-based isolation
  - Automatic load balancing
  - Health monitoring
  - Resource cleanup

  ## Features

  - **Concurrent Execution**: Multiple isolated Python processes
  - **Session Isolation**: Each session has its own program namespace
  - **Scalability**: Pool size based on system resources
  - **Fault Tolerance**: Automatic worker restart on failure
  - **Performance**: Reuses processes across sessions

  ## Configuration

      config :dspex, DSPex.Adapters.PythonPool,
        pool_size: System.schedulers_online() * 2,
        overflow: 2,
        checkout_timeout: 5_000,
        operation_timeout: 30_000

  ## Usage

      # Create a session-aware adapter
      {:ok, adapter} = DSPex.Adapters.PythonPool.start_session("user_123")
      
      # Use within session
      {:ok, program_id} = adapter.create_program(%{signature: %{...}})
      {:ok, result} = adapter.execute_program(program_id, %{input: "test"})
      
      # End session
      :ok = DSPex.Adapters.PythonPool.end_session("user_123")
  """

  @behaviour DSPex.Adapters.Adapter

  alias DSPex.PythonBridge.SessionPool

  require Logger

  # Default session for anonymous operations
  @default_session "anonymous"

  ## Adapter Callbacks

  @impl true
  def create_program(config) do
    session_id = get_session_id(config)

    # Convert config for Python bridge
    python_config = convert_config(config)

    case SessionPool.execute_in_session(session_id, :create_program, python_config) do
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

    case SessionPool.execute_in_session(session_id, :execute_program, args, options) do
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

    case SessionPool.execute_in_session(session_id, :list_programs, %{}) do
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

    case SessionPool.execute_in_session(session_id, :delete_program, %{program_id: program_id}) do
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

    case SessionPool.execute_in_session(session_id, :get_program_info, %{program_id: program_id}) do
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
    case SessionPool.execute_anonymous(:ping, %{}) do
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

    # Get pool-level stats
    pool_status = SessionPool.get_pool_status()

    # Get session-specific stats if requested
    session_stats =
      if session_id != @default_session do
        case SessionPool.execute_in_session(session_id, :get_stats, %{}) do
          {:ok, stats} -> stats
          _ -> %{}
        end
      else
        %{}
      end

    # Combine stats
    {:ok,
     %{
       adapter_type: :python_pool,
       layer: :production,
       pool_status: pool_status,
       session_stats: session_stats,
       python_execution: true,
       concurrent_sessions: true
     }}
  end

  @impl true
  def configure_lm(config) do
    # Configure LM globally (all workers will use it)
    case SessionPool.execute_anonymous(:configure_lm, config) do
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
      performance: :optimized,
      requires_environment: [:python, :dspy, :nimble_pool],
      concurrent_execution: true,
      session_isolation: true,
      production_ready: true
    }
  end

  ## Session Management

  @doc """
  Starts a new session for isolated operations.

  ## Examples

      {:ok, session_id} = PythonPool.start_session("user_123")
  """
  def start_session(session_id, _opts \\ []) do
    # Session will be created on first use
    Logger.debug("Starting session: #{session_id}")
    {:ok, session_id}
  end

  @doc """
  Ends a session and cleans up resources.

  ## Examples

      :ok = PythonPool.end_session("user_123")
  """
  def end_session(session_id) do
    SessionPool.end_session(session_id)
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    SessionPool.get_session_info()
  end

  @doc """
  Creates a session-bound adapter instance.

  This returns a map with all adapter functions bound to a specific session.

  ## Examples

      adapter = PythonPool.session_adapter("user_123")
      {:ok, program_id} = adapter.create_program(%{...})
  """
  def session_adapter(session_id) do
    %{
      create_program: fn config ->
        create_program(Map.put(config, :session_id, session_id))
      end,
      execute_program: fn program_id, inputs, opts ->
        execute_program(program_id, inputs, Map.put(opts || %{}, :session_id, session_id))
      end,
      list_programs: fn ->
        list_programs(%{session_id: session_id})
      end,
      delete_program: fn program_id ->
        delete_program(program_id, %{session_id: session_id})
      end,
      get_program_info: fn program_id ->
        get_program_info(program_id, %{session_id: session_id})
      end,
      get_stats: fn ->
        get_stats(%{session_id: session_id})
      end,
      health_check: &health_check/0,
      session_id: session_id
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
    # TypeConverter.convert_signature_to_format returns the converted signature directly
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

  defp handle_pool_error(:pool_timeout) do
    {:error, "Pool timeout - all workers busy"}
  end

  defp handle_pool_error({:pool_error, reason}) do
    {:error, "Pool error: #{inspect(reason)}"}
  end

  defp handle_pool_error(reason) do
    {:error, reason}
  end
end

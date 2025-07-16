defmodule DSPex.Python.SessionAdapter do
  @moduledoc """
  Adapter to provide session-aware execution on top of the stateless V3 pool.

  This module bridges the gap between:
  - V2's session-affinity model (workers maintain session state)
  - V3's stateless model (all state in centralized SessionStore)

  It allows existing code to work unchanged while using the new pool.
  """

  alias DSPex.PythonBridge.SessionStore
  alias DSPex.Python.Pool

  @doc """
  Executes a command in the context of a session.

  The session data is retrieved from SessionStore and added to the command args
  before execution on any available worker.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    # Enhance args with session data if needed
    enhanced_args = enhance_args_with_session(session_id, command, args)

    # Add session_id to args for tracking
    final_args = Map.put(enhanced_args, :session_id, session_id)

    # Execute on any available worker
    case Pool.execute(command, final_args, opts) do
      {:ok, result} ->
        # Update session store if needed
        maybe_update_session(session_id, command, result)
        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Executes a command without session context (anonymous).
  """
  def execute_anonymous(command, args, opts \\ []) do
    # Generate temporary session ID for tracking
    temp_session_id = "anon_#{:erlang.unique_integer([:positive])}"
    args_with_session = Map.put(args, :session_id, temp_session_id)

    Pool.execute(command, args_with_session, opts)
  end

  @doc """
  Ensures a session exists in the store.
  """
  def ensure_session(session_id) do
    case SessionStore.get_session(session_id) do
      {:ok, _session} ->
        :ok

      {:error, :not_found} ->
        SessionStore.create_session(session_id)
        :ok
    end
  end

  # Private Functions

  defp enhance_args_with_session(session_id, command, args) do
    case command do
      :execute_program ->
        enhance_program_execution(session_id, args)

      :get_program ->
        enhance_program_fetch(session_id, args)

      _ ->
        # Most commands don't need session enhancement
        args
    end
  end

  defp enhance_program_execution(session_id, args) do
    program_id = Map.get(args, :program_id)

    case get_program_from_session(session_id, program_id) do
      {:ok, program_data} ->
        # Add full program data to args
        args
        |> Map.put(:program_data, program_data)
        |> Map.put(:from_session, true)

      {:error, :not_found} ->
        # Program might be global or needs to be loaded
        case get_global_program(program_id) do
          {:ok, program_data} ->
            Map.put(args, :program_data, program_data)

          _ ->
            args
        end
    end
  end

  defp enhance_program_fetch(session_id, args) do
    program_id = Map.get(args, :program_id)

    # Check session first, then global
    case get_program_from_session(session_id, program_id) do
      {:ok, _} ->
        Map.put(args, :search_session, true)

      _ ->
        Map.put(args, :search_global, true)
    end
  end

  defp get_program_from_session(session_id, program_id) do
    case SessionStore.get_session(session_id) do
      {:ok, session} ->
        case Map.get(session.programs, program_id) do
          nil -> {:error, :not_found}
          program_data -> {:ok, program_data}
        end

      _ ->
        {:error, :session_not_found}
    end
  end

  defp get_global_program(program_id) do
    SessionStore.get_global_program(program_id)
  end

  defp maybe_update_session(session_id, command, result) do
    case command do
      :create_program ->
        # Store new program in session
        case result do
          %{"program_id" => program_id} = program_data ->
            SessionStore.store_program(session_id, program_id, program_data)

          _ ->
            :ok
        end

      :compile_program ->
        # Update compiled program in session
        case result do
          %{"program_id" => program_id, "compiled" => true} = data ->
            SessionStore.update_program(session_id, program_id, data)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end
end

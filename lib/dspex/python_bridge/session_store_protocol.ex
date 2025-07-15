defmodule DSPex.PythonBridge.SessionStoreProtocol do
  @moduledoc """
  Protocol for communication between Python workers and the centralized SessionStore.

  This module provides functions for Python workers to interact with the
  centralized SessionStore, enabling stateless worker architecture.
  """

  alias DSPex.PythonBridge.{SessionStore, Session, Protocol}
  require Logger

  @doc """
  Handles session store requests from Python workers.

  This function processes requests from Python workers to interact with
  the centralized SessionStore.

  ## Parameters

  - `command` - The session store command (:get_session, :update_session, etc.)
  - `args` - Command arguments
  - `worker_state` - Current worker state (optional, for logging)

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on failure.
  """
  @spec handle_session_request(atom(), map(), map() | nil) ::
          {:ok, term()} | {:error, term()}
  def handle_session_request(command, args, worker_state \\ nil)

  def handle_session_request(:get_session, %{"session_id" => session_id}, worker_state) do
    Logger.debug("Getting session #{session_id} for worker #{get_worker_id(worker_state)}")

    case SessionStore.get_session(session_id) do
      {:ok, session} ->
        # Convert session struct to map for JSON serialization
        session_data = %{
          "id" => session.id,
          "programs" => session.programs,
          "metadata" => session.metadata,
          "created_at" => session.created_at,
          "last_accessed" => session.last_accessed,
          "ttl" => session.ttl
        }

        {:ok, session_data}

      {:error, :not_found} ->
        Logger.debug("Session #{session_id} not found")
        {:error, :session_not_found}

      {:error, reason} ->
        Logger.error("Error getting session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_session_request(:update_session, args, worker_state) do
    session_id = Map.get(args, "session_id")
    operation = Map.get(args, "operation")
    key = Map.get(args, "key")
    value = Map.get(args, "value")

    Logger.debug(
      "Updating session #{session_id} for worker #{get_worker_id(worker_state)}: #{operation}/#{key}"
    )

    case operation do
      "programs" ->
        update_session_program(session_id, key, value)

      "metadata" ->
        update_session_metadata(session_id, key, value)

      "delete_program" ->
        delete_session_program(session_id, key)

      _ ->
        Logger.error("Unknown session update operation: #{operation}")
        {:error, :unknown_operation}
    end
  end

  def handle_session_request(:create_session, args, worker_state) do
    session_id = Map.get(args, "session_id")
    opts = Map.get(args, "opts", [])

    Logger.debug("Creating session #{session_id} for worker #{get_worker_id(worker_state)}")

    # Convert map opts to keyword list
    keyword_opts =
      case opts do
        opts when is_map(opts) -> Map.to_list(opts)
        opts when is_list(opts) -> opts
        _ -> []
      end

    case SessionStore.create_session(session_id, keyword_opts) do
      {:ok, session} ->
        session_data = %{
          "id" => session.id,
          "programs" => session.programs,
          "metadata" => session.metadata,
          "created_at" => session.created_at,
          "last_accessed" => session.last_accessed,
          "ttl" => session.ttl
        }

        {:ok, session_data}

      {:error, reason} ->
        Logger.error("Error creating session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_session_request(:delete_session, %{"session_id" => session_id}, worker_state) do
    Logger.debug("Deleting session #{session_id} for worker #{get_worker_id(worker_state)}")

    SessionStore.delete_session(session_id)
    {:ok, %{"status" => "deleted"}}
  end

  def handle_session_request(command, _args, worker_state) do
    Logger.error("Unknown session store command: #{command} from worker #{get_worker_id(worker_state)}")
    {:error, :unknown_command}
  end

  ## Private Functions

  defp update_session_program(session_id, program_id, program_data) do
    case SessionStore.update_session(session_id, fn session ->
           Session.put_program(session, program_id, program_data)
         end) do
      {:ok, _updated_session} ->
        {:ok, %{"status" => "updated"}}

      {:error, :not_found} ->
        # Session doesn't exist, create it first
        case SessionStore.create_session(session_id) do
          {:ok, session} ->
            updated_session = Session.put_program(session, program_id, program_data)

            case SessionStore.update_session(session_id, fn _session -> updated_session end) do
              {:ok, _} -> {:ok, %{"status" => "created_and_updated"}}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_session_metadata(session_id, key, value) do
    case SessionStore.update_session(session_id, fn session ->
           Session.put_metadata(session, key, value)
         end) do
      {:ok, _updated_session} ->
        {:ok, %{"status" => "updated"}}

      {:error, :not_found} ->
        # Session doesn't exist, create it first
        case SessionStore.create_session(session_id) do
          {:ok, session} ->
            updated_session = Session.put_metadata(session, key, value)

            case SessionStore.update_session(session_id, fn _session -> updated_session end) do
              {:ok, _} -> {:ok, %{"status" => "created_and_updated"}}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_session_program(session_id, program_id) do
    case SessionStore.update_session(session_id, fn session ->
           Session.delete_program(session, program_id)
         end) do
      {:ok, _updated_session} ->
        {:ok, %{"status" => "deleted"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_worker_id(nil), do: "unknown"
  defp get_worker_id(%{worker_id: worker_id}), do: worker_id
  defp get_worker_id(_), do: "unknown"

  @doc """
  Sends a session store request to a Python worker and waits for response.

  This function is used when Elixir needs to communicate session store
  operations to Python workers.

  ## Parameters

  - `port` - The port connected to the Python worker
  - `command` - The session store command
  - `args` - Command arguments
  - `timeout` - Request timeout (default: 5000ms)

  ## Returns

  `{:ok, response}` on success, `{:error, reason}` on failure.
  """
  @spec send_session_request(port(), atom(), map(), pos_integer()) ::
          {:ok, term()} | {:error, term()}
  def send_session_request(port, command, args, timeout \\ 5000) do
    request_id = System.unique_integer([:positive, :monotonic])

    request_payload = Protocol.encode_request(request_id, command, args)

    try do
      Port.command(port, request_payload)

      receive do
        {^port, {:data, data}} ->
          case Protocol.decode_response(data) do
            {:ok, ^request_id, response} ->
              {:ok, response}

            {:ok, other_id, _response} ->
              {:error, {:response_mismatch, request_id, other_id}}

            {:error, _id, reason} ->
              {:error, {:python_error, reason}}

            {:error, reason} ->
              {:error, {:decode_error, reason}}
          end

        {^port, {:exit_status, status}} ->
          {:error, {:port_exited, status}}
      after
        timeout ->
          {:error, :timeout}
      end
    catch
      :error, :badarg ->
        {:error, :port_closed}

      kind, error ->
        {:error, {kind, error}}
    end
  end

  @doc """
  Handles session store communication errors with appropriate logging and recovery.

  ## Parameters

  - `error` - The error that occurred
  - `context` - Additional context for error handling

  ## Returns

  A standardized error response.
  """
  @spec handle_session_error(term(), map()) :: {:error, term()}
  def handle_session_error(error, context \\ %{}) do
    case error do
      :session_not_found ->
        Logger.debug("Session not found: #{inspect(context)}")
        {:error, :session_not_found}

      :timeout ->
        Logger.warning("Session store request timeout: #{inspect(context)}")
        {:error, :session_store_timeout}

      {:port_exited, status} ->
        Logger.error("Python worker exited during session operation (status: #{status}): #{inspect(context)}")
        {:error, :worker_unavailable}

      {:python_error, reason} ->
        Logger.error("Python worker error during session operation: #{reason}, context: #{inspect(context)}")
        {:error, {:python_error, reason}}

      {:decode_error, reason} ->
        Logger.error("Protocol decode error during session operation: #{reason}, context: #{inspect(context)}")
        {:error, {:protocol_error, reason}}

      other ->
        Logger.error("Unexpected session store error: #{inspect(other)}, context: #{inspect(context)}")
        {:error, {:unexpected_error, other}}
    end
  end
end
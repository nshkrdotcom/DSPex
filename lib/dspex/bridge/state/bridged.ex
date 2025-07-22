defmodule DSPex.Bridge.State.Bridged do
  @moduledoc """
  State provider that delegates to SessionStore and gRPC bridge.

  This backend is automatically activated when Python components are detected.
  It provides:
  - Full Python interoperability
  - Cross-process state sharing
  - Millisecond latency (acceptable for LLM operations)
  - Seamless migration from LocalState

  ## Architecture

  BridgedState acts as an adapter between the StateProvider behaviour
  and the SessionStore + gRPC infrastructure from Stage 1:

      DSPex.Context
           ↓
      BridgedState
           ↓
      SessionStore ←→ gRPC ←→ Python

  ## Performance Characteristics

  - Get operation: ~1-2ms (includes gRPC overhead)
  - Set operation: ~2-5ms (includes validation)
  - Batch operations: Amortized cost per operation
  - Network overhead: ~0.5-1ms per round trip
  """

  @behaviour DSPex.Bridge.StateProvider

  require Logger
  alias Snakepit.Bridge.SessionStore

  defstruct [
    :session_id,
    :metadata
  ]

  ## StateProvider Implementation

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    # Ensure SessionStore is running
    ensure_session_store!()

    # Create or get session
    case create_or_get_session(session_id) do
      :ok ->
        state = %__MODULE__{
          session_id: session_id,
          metadata: %{
            created_at: DateTime.utc_now(),
            backend: :bridged
          }
        }

        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil ->
            {:ok, state}

          exported ->
            case import_state(state, exported) do
              {:ok, state} ->
                Logger.info("BridgedState: Imported state for session #{session_id}")
                {:ok, state}

              error ->
                # Cleanup on import failure
                SessionStore.delete_session(session_id)
                error
            end
        end

      {:error, reason} ->
        {:error, {:session_creation_failed, reason}}
    end
  end

  @impl true
  def register_variable(state, name, type, initial_value, opts) do
    # Use SessionStore's register_variable API directly
    case SessionStore.register_variable(
           state.session_id,
           name,
           type,
           initial_value,
           opts
         ) do
      {:ok, var_id} ->
        Logger.debug("BridgedState: Registered variable #{name} (#{var_id})")
        {:ok, {var_id, state}}

      {:error, {:already_exists, _}} ->
        {:error, {:already_exists, name}}

      {:error, reason} ->
        Logger.warning("BridgedState: Failed to register variable #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_variable(state, identifier) do
    case SessionStore.get_variable(state.session_id, identifier) do
      {:ok, variable} ->
        {:ok, variable.value}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    case SessionStore.update_variable(state.session_id, identifier, new_value, metadata) do
      :ok ->
        {:ok, state}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, {:validation_failed, reason}} ->
        {:error, {:validation_failed, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_variables(state) do
    case SessionStore.list_variables(state.session_id) do
      {:ok, variables} ->
        # Convert to the expected format
        exported = Enum.map(variables, &export_variable/1)
        {:ok, exported}

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_variables(state, identifiers) do
    case SessionStore.get_variables(state.session_id, identifiers) do
      {:ok, %{found: found}} ->
        # Convert found map to identifier => value map
        values =
          Map.new(found, fn {id, variable} ->
            {to_string(id), variable.value}
          end)

        {:ok, values}

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def update_variables(state, updates, metadata) do
    opts = [
      # BridgedState doesn't support atomic updates yet
      atomic: false,
      metadata: metadata
    ]

    case SessionStore.update_variables(state.session_id, updates, opts) do
      {:ok, results} ->
        # Check if any updates failed
        errors =
          Enum.reduce(results, %{}, fn {id, result}, acc ->
            case result do
              :ok -> acc
              {:error, reason} -> Map.put(acc, id, reason)
            end
          end)

        if map_size(errors) == 0 do
          {:ok, state}
        else
          {:error, {:partial_failure, errors}}
        end

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_variable(state, identifier) do
    case SessionStore.delete_variable(state.session_id, identifier) do
      :ok ->
        {:ok, state}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :session_not_found} ->
        {:error, :session_expired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def export_state(state) do
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        # Build the same structure as LocalState exports
        variable_map =
          Map.new(session.variables, fn {var_id, variable} ->
            {var_id, export_variable(variable)}
          end)

        variable_index =
          Map.new(session.variables, fn {_var_id, variable} ->
            {to_string(variable.name), variable.id}
          end)

        exported = %{
          session_id: state.session_id,
          variables: variable_map,
          variable_index: variable_index,
          metadata:
            Map.merge(state.metadata, %{
              exported_at: DateTime.utc_now(),
              backend: :bridged
            })
        }

        {:ok, exported}

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def import_state(state, exported_state) do
    # Validate exported state structure
    if not is_map(exported_state) or not Map.has_key?(exported_state, :variables) do
      {:error, :invalid_export_format}
    else
      variables = Map.get(exported_state, :variables, %{})
      Logger.info("BridgedState: Importing #{map_size(variables)} variables")

      # Import variables one by one
      results =
        Enum.map(exported_state.variables, fn {_var_id, var_data} ->
          import_variable(state, var_data)
        end)

      failures =
        Enum.filter(results, fn
          {:ok, _} -> false
          _ -> true
        end)

      if failures == [] do
        Logger.info("BridgedState: Successfully imported all variables")
        {:ok, state}
      else
        Logger.error("BridgedState: Failed to import #{length(failures)} variables")
        {:error, {:import_failed, failures}}
      end
    end
  end

  @impl true
  def requires_bridge?, do: true

  @impl true
  def capabilities do
    %{
      # SessionStore doesn't support atomic updates yet
      atomic_updates: false,
      # Will be added in Stage 3
      streaming: false,
      # Survives process restarts
      persistent: true,
      # Works across nodes via gRPC
      distributed: true
    }
  end

  @impl true
  def cleanup(state) do
    # SessionStore handles session cleanup via TTL
    # We just log for debugging
    Logger.debug("BridgedState: Cleanup called for session #{state.session_id}")
    :ok
  end

  ## Private Helpers

  defp ensure_session_store! do
    case Process.whereis(SessionStore) do
      nil ->
        # Try to start it
        case SessionStore.start_link() do
          {:ok, _} ->
            :ok

          {:error, {:already_started, _}} ->
            :ok

          {:error, reason} ->
            raise "Failed to start SessionStore: #{inspect(reason)}"
        end

      pid when is_pid(pid) ->
        :ok
    end
  end

  defp create_or_get_session(session_id) do
    case SessionStore.create_session(session_id) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      error -> error
    end
  end

  defp generate_session_id do
    "bridged_session_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp export_variable(variable) do
    %{
      id: variable.id,
      name: variable.name,
      type: variable.type,
      value: variable.value,
      constraints: variable.constraints,
      metadata: variable.metadata,
      version: variable.version,
      created_at: variable.created_at,
      last_updated_at: variable.last_updated_at
    }
  end

  defp import_variable(state, var_data) do
    # Import using our register_variable implementation
    case register_variable(
           state,
           var_data.name,
           var_data.type,
           var_data.value,
           constraints: var_data.constraints,
           metadata:
             Map.merge(var_data.metadata || %{}, %{
               "migrated_from" => Map.get(var_data.metadata || %{}, "backend", "local"),
               "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
             })
         ) do
      {:ok, {_var_id, _state}} -> {:ok, var_data.name}
      error -> error
    end
  end
end

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
  alias Snakepit.Bridge.{SessionStore, Session}

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
    # Generate a unique variable ID
    var_id = "var_#{name}_#{System.unique_integer([:positive, :monotonic])}"

    # Build variable data structure
    metadata = Keyword.get(opts, :metadata, %{})

    metadata =
      if desc = Keyword.get(opts, :description) do
        Map.put(metadata, "description", desc)
      else
        metadata
      end

    variable_data = %{
      "id" => var_id,
      "name" => to_string(name),
      "type" => to_string(type),
      "value" => initial_value,
      "constraints" => Keyword.get(opts, :constraints, %{}),
      "metadata" => metadata,
      "version" => 0,
      "created_at" => System.system_time(:second),
      "last_updated_at" => System.system_time(:second)
    }

    # Store variable in session's programs map under a variables namespace
    variables_key = "__variables__"

    case SessionStore.update_session(state.session_id, fn session ->
           variables = Map.get(session.programs, variables_key, %{})

           # Check if variable already exists
           if Map.has_key?(variables, to_string(name)) do
             raise "Variable #{name} already exists"
           end

           # Add variable
           updated_variables = Map.put(variables, to_string(name), variable_data)
           Session.put_program(session, variables_key, updated_variables)
         end) do
      {:ok, _session} ->
        Logger.debug("BridgedState: Registered variable #{name} (#{var_id})")
        {:ok, {var_id, state}}

      {:error, reason} ->
        Logger.warning("BridgedState: Failed to register variable #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    _e in RuntimeError ->
      {:error, {:already_exists, name}}
  end

  @impl true
  def get_variable(state, identifier) do
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        variables_key = "__variables__"

        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            # Try to find by name or ID
            key = to_string(identifier)

            case find_variable(variables, key) do
              {:ok, variable} ->
                {:ok, variable["value"]}

              :error ->
                {:error, :not_found}
            end

          {:error, :not_found} ->
            # No variables stored yet
            {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    variables_key = "__variables__"

    case SessionStore.get_session(state.session_id) do
      {:ok, _session} ->
        case SessionStore.update_session(state.session_id, fn session ->
               case Session.get_program(session, variables_key) do
                 {:ok, variables} ->
                   key = to_string(identifier)

                   case find_variable(variables, key) do
                     {:ok, variable} ->
                       # Validate type and constraints
                       case validate_value(variable["type"], new_value, variable["constraints"]) do
                         :ok ->
                           # Update variable
                           updated_variable =
                             variable
                             |> Map.put("value", new_value)
                             |> Map.put("version", variable["version"] + 1)
                             |> Map.put("last_updated_at", System.system_time(:second))
                             |> Map.update("metadata", metadata, &Map.merge(&1, metadata))

                           var_name = variable["name"]
                           updated_variables = Map.put(variables, var_name, updated_variable)
                           Session.put_program(session, variables_key, updated_variables)

                         {:error, reason} ->
                           raise "Validation failed: #{inspect(reason)}"
                       end

                     :error ->
                       raise "Variable not found: #{identifier}"
                   end

                 {:error, :not_found} ->
                   raise "No variables found in session"
               end
             end) do
          {:ok, _session} ->
            {:ok, state}

          {:error, reason} ->
            Logger.error("BridgedState: Failed to set variable: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  rescue
    e in RuntimeError ->
      if String.contains?(e.message, "not found") do
        {:error, :not_found}
      else
        {:error, String.to_atom(e.message)}
      end
  end

  @impl true
  def list_variables(state) do
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        variables_key = "__variables__"

        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            # Convert to list of exported variables
            exported =
              variables
              |> Map.values()
              |> Enum.map(&export_variable_data/1)

            {:ok, exported}

          {:error, :not_found} ->
            # No variables yet
            {:ok, []}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def get_variables(state, identifiers) do
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        variables_key = "__variables__"

        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            # Get values for each identifier
            values =
              identifiers
              |> Enum.reduce(%{}, fn identifier, acc ->
                key = to_string(identifier)

                case find_variable(variables, key) do
                  {:ok, variable} ->
                    Map.put(acc, key, variable["value"])

                  :error ->
                    acc
                end
              end)

            {:ok, values}

          {:error, :not_found} ->
            # No variables yet
            {:ok, %{}}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def update_variables(state, updates, metadata) do
    variables_key = "__variables__"

    # First get the session to check it exists
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        # Get current variables
        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            # Process each update
            {updated_vars, errors} =
              Enum.reduce(updates, {variables, %{}}, fn {identifier, new_value}, {vars, errs} ->
                key = to_string(identifier)

                case find_variable(vars, key) do
                  {:ok, variable} ->
                    # Validate
                    case validate_value(variable["type"], new_value, variable["constraints"]) do
                      :ok ->
                        # Update variable
                        updated_var =
                          variable
                          |> Map.put("value", new_value)
                          |> Map.put("version", variable["version"] + 1)
                          |> Map.put("last_updated_at", System.system_time(:second))
                          |> Map.update("metadata", metadata, &Map.merge(&1, metadata))

                        updated_vars = Map.put(vars, variable["name"], updated_var)
                        {updated_vars, errs}

                      {:error, reason} ->
                        {vars, Map.put(errs, identifier, reason)}
                    end

                  :error ->
                    {vars, Map.put(errs, identifier, :not_found)}
                end
              end)

            # Always apply the successful updates
            if map_size(errors) < map_size(updates) do
              # At least some updates succeeded - update session with successful changes
              case SessionStore.update_session(state.session_id, fn session ->
                     Session.put_program(session, variables_key, updated_vars)
                   end) do
                {:ok, _session} ->
                  if map_size(errors) == 0 do
                    {:ok, state}
                  else
                    {:error, {:partial_failure, errors}}
                  end

                {:error, reason} ->
                  {:error, reason}
              end
            else
              # All updates failed - don't modify session
              {:error, {:partial_failure, errors}}
            end

          {:error, :not_found} ->
            # No variables yet - all updates fail
            errors = Map.new(updates, fn {k, _v} -> {k, :not_found} end)
            {:error, {:partial_failure, errors}}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def delete_variable(state, identifier) do
    variables_key = "__variables__"

    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            key = to_string(identifier)

            case find_variable(variables, key) do
              {:ok, variable} ->
                # Remove variable
                updated_variables = Map.delete(variables, variable["name"])

                case SessionStore.update_session(state.session_id, fn session ->
                       Session.put_program(session, variables_key, updated_variables)
                     end) do
                  {:ok, _session} -> {:ok, state}
                  {:error, reason} -> {:error, reason}
                end

              :error ->
                {:error, :not_found}
            end

          {:error, :not_found} ->
            # No variables in session
            {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :session_expired}
    end
  end

  @impl true
  def export_state(state) do
    case SessionStore.get_session(state.session_id) do
      {:ok, session} ->
        variables_key = "__variables__"

        case Session.get_program(session, variables_key) do
          {:ok, variables} ->
            # Build the same structure as LocalState exports
            variable_map =
              Map.new(variables, fn {_name, var} ->
                {var["id"], export_variable_data(var)}
              end)

            variable_index =
              Map.new(variables, fn {name, var} ->
                {name, var["id"]}
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
            # No variables yet - return empty export
            {:ok,
             %{
               session_id: state.session_id,
               variables: %{},
               variable_index: %{},
               metadata:
                 Map.merge(state.metadata, %{
                   exported_at: DateTime.utc_now(),
                   backend: :bridged
                 })
             }}
        end

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
      # Future optimization: Add batch import to SessionStore
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
      # SessionStore doesn't support yet
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

  defp export_variable_data(var) when is_map(var) do
    # Handle both string and atom keys
    name = var["name"] || var[:name]
    type_val = var["type"] || var[:type]

    %{
      id: var["id"] || var[:id],
      name: if(is_atom(name), do: name, else: String.to_atom(name)),
      type: if(is_atom(type_val), do: type_val, else: String.to_atom(type_val)),
      value: var["value"] || var[:value],
      constraints: var["constraints"] || var[:constraints] || %{},
      metadata: var["metadata"] || var[:metadata] || %{},
      version: var["version"] || var[:version] || 0,
      created_at: var["created_at"] || var[:created_at],
      last_updated_at: var["last_updated_at"] || var[:last_updated_at]
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

  defp find_variable(variables, identifier) do
    # Try to find by name or ID
    key = to_string(identifier)

    # First try direct name lookup
    case Map.get(variables, key) do
      nil ->
        # Try to find by ID
        Enum.find_value(variables, :error, fn {_name, var} ->
          if var["id"] == key do
            {:ok, var}
          else
            nil
          end
        end)

      var ->
        {:ok, var}
    end
  end

  defp validate_value(type_str, value, constraints) do
    type = String.to_atom(type_str)

    # Basic type validation
    valid_type? =
      case {type, value} do
        {:string, v} when is_binary(v) -> true
        {:integer, v} when is_integer(v) -> true
        {:float, v} when is_float(v) or is_integer(v) -> true
        {:boolean, v} when is_boolean(v) -> true
        _ -> false
      end

    unless valid_type? do
      {:error, "value must be #{type_str_article(type_str)} #{type_str}"}
    else
      # Check constraints
      case type do
        :integer ->
          check_numeric_constraints(value, constraints, "integer")

        :float ->
          check_numeric_constraints(value, constraints, "float")

        :string ->
          check_string_constraints(value, constraints)

        _ ->
          :ok
      end
    end
  end

  defp type_str_article(type_str) do
    if type_str in ["integer"] do
      "an"
    else
      "a"
    end
  end

  defp check_numeric_constraints(value, constraints, _type_name) do
    cond do
      min = constraints["min"] || constraints[:min] ->
        if value < min do
          {:error, "value #{value} is below minimum #{min}"}
        else
          check_numeric_max(value, constraints)
        end

      true ->
        check_numeric_max(value, constraints)
    end
  end

  defp check_numeric_max(value, constraints) do
    if max = constraints["max"] || constraints[:max] do
      if value > max do
        {:error, "value #{value} is above maximum #{max}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_string_constraints(value, constraints) do
    if enum = constraints["enum"] || constraints[:enum] do
      if value in enum do
        :ok
      else
        {:error, "value must be one of: #{inspect(enum)}"}
      end
    else
      :ok
    end
  end
end

defmodule DSPex.Bridge.State.Local do
  @moduledoc """
  In-process state provider using an Agent.

  This is the default backend for pure Elixir workflows. It provides:
  - Sub-microsecond latency
  - No serialization overhead
  - No network calls
  - Perfect for LLM-free DSPex programs

  ## Performance Characteristics

  - Get operation: ~0.5-1 microseconds
  - Set operation: ~2-5 microseconds
  - List operation: ~1-2 microseconds per variable
  - No network overhead
  - No serialization cost

  ## Storage Structure

  The Agent maintains state with:
  - `variables`: Map of var_id => variable data
  - `variable_index`: Map of name => var_id for fast lookups
  - `metadata`: Session-level metadata
  - `stats`: Performance statistics
  """

  @behaviour DSPex.Bridge.StateProvider

  require Logger
  # Use local type modules to avoid dependency on Snakepit
  alias __MODULE__.Types

  defstruct [
    :agent_pid,
    :session_id
  ]

  ## StateProvider Implementation

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    case Agent.start_link(fn -> initial_state(session_id) end) do
      {:ok, pid} ->
        state = %__MODULE__{agent_pid: pid, session_id: session_id}

        # Import existing state if provided
        case Keyword.get(opts, :existing_state) do
          nil ->
            {:ok, state}

          exported ->
            case import_state(state, exported) do
              {:ok, state} ->
                {:ok, state}

              error ->
                # Cleanup on import failure
                Agent.stop(pid)
                error
            end
        end

      error ->
        error
    end
  end

  @impl true
  def register_variable(state, name, type, initial_value, opts) do
    name_str = to_string(name)

    # Check if name already exists
    existing_id =
      Agent.get(state.agent_pid, fn agent_state ->
        Map.get(agent_state.variable_index, name_str)
      end)

    if existing_id do
      {:error, {:already_exists, name}}
    else
      with {:ok, type_module} <- get_type_module(type),
           {:ok, validated_value} <- type_module.validate(initial_value),
           constraints = Keyword.get(opts, :constraints, %{}),
           :ok <- type_module.validate_constraints(validated_value, constraints) do
        var_id = generate_var_id(name)
        now = System.monotonic_time(:millisecond)

        variable = %{
          id: var_id,
          name: name,
          type: type,
          value: validated_value,
          constraints: constraints,
          metadata: build_metadata(opts),
          version: 0,
          created_at: now,
          last_updated_at: now
        }

        Agent.update(state.agent_pid, fn agent_state ->
          agent_state
          |> put_in([:variables, var_id], variable)
          |> put_in([:variable_index, name_str], var_id)
          |> update_in([:stats, :variable_count], &(&1 + 1))
          |> update_in([:stats, :total_operations], &(&1 + 1))
        end)

        Logger.debug("LocalState: Registered variable #{name} (#{var_id})")

        {:ok, {var_id, state}}
      end
    end
  end

  @impl true
  def get_variable(state, identifier) do
    {microseconds, result} =
      :timer.tc(fn ->
        Agent.get(state.agent_pid, fn agent_state ->
          var_id = resolve_identifier(agent_state, identifier)

          case get_in(agent_state, [:variables, var_id]) do
            nil -> {:error, :not_found}
            variable -> {:ok, variable.value}
          end
        end)
      end)

    # Update stats
    Agent.update(state.agent_pid, fn agent_state ->
      agent_state
      |> update_in([:stats, :total_operations], &(&1 + 1))
      |> update_in([:stats, :total_get_microseconds], &(&1 + microseconds))
    end)

    result
  end

  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    result =
      Agent.get_and_update(state.agent_pid, fn agent_state ->
        var_id = resolve_identifier(agent_state, identifier)

        case get_in(agent_state, [:variables, var_id]) do
          nil ->
            {{:error, :not_found}, agent_state}

          variable ->
            with {:ok, type_module} <- get_type_module(variable.type),
                 {:ok, validated_value} <- type_module.validate(new_value),
                 :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
              updated_variable = %{
                variable
                | value: validated_value,
                  version: variable.version + 1,
                  last_updated_at: System.monotonic_time(:millisecond),
                  metadata: Map.merge(variable.metadata, metadata)
              }

              new_state =
                agent_state
                |> put_in([:variables, var_id], updated_variable)
                |> update_in([:stats, :total_operations], &(&1 + 1))
                |> update_in([:stats, :total_updates], &(&1 + 1))

              {:ok, new_state}
            else
              error -> {error, agent_state}
            end
        end
      end)

    case result do
      :ok -> {:ok, state}
      error -> error
    end
  end

  @impl true
  def list_variables(state) do
    variables =
      Agent.get(state.agent_pid, fn agent_state ->
        agent_state.variables
        |> Map.values()
        |> Enum.sort_by(& &1.created_at)
        |> Enum.map(&export_variable/1)
      end)

    {:ok, variables}
  end

  @impl true
  def get_variables(state, identifiers) do
    result =
      Agent.get(state.agent_pid, fn agent_state ->
        Enum.reduce(identifiers, %{}, fn identifier, acc ->
          var_id = resolve_identifier(agent_state, identifier)

          case get_in(agent_state, [:variables, var_id]) do
            # Skip missing
            nil -> acc
            variable -> Map.put(acc, to_string(identifier), variable.value)
          end
        end)
      end)

    # Update stats
    Agent.update(state.agent_pid, fn agent_state ->
      update_in(agent_state, [:stats, :total_operations], &(&1 + length(identifiers)))
    end)

    {:ok, result}
  end

  @impl true
  def update_variables(state, updates, metadata) do
    # LocalState doesn't support true atomic updates
    # We'll do best-effort sequential updates
    errors =
      Enum.reduce(updates, %{}, fn {identifier, value}, acc ->
        case set_variable(state, identifier, value, metadata) do
          {:ok, _} -> acc
          {:error, reason} -> Map.put(acc, to_string(identifier), reason)
        end
      end)

    if map_size(errors) == 0 do
      {:ok, state}
    else
      {:error, {:partial_failure, errors}}
    end
  end

  @impl true
  def delete_variable(state, identifier) do
    result =
      Agent.get_and_update(state.agent_pid, fn agent_state ->
        var_id = resolve_identifier(agent_state, identifier)

        case get_in(agent_state, [:variables, var_id]) do
          nil ->
            {{:error, :not_found}, agent_state}

          variable ->
            name_str = to_string(variable.name)

            new_state =
              agent_state
              |> update_in([:variables], &Map.delete(&1, var_id))
              |> update_in([:variable_index], &Map.delete(&1, name_str))
              |> update_in([:stats, :variable_count], &(&1 - 1))
              |> update_in([:stats, :total_operations], &(&1 + 1))

            {:ok, new_state}
        end
      end)

    case result do
      :ok -> {:ok, state}
      error -> error
    end
  end

  @impl true
  def export_state(state) do
    exported =
      Agent.get(state.agent_pid, fn agent_state ->
        %{
          session_id: state.session_id,
          variables: agent_state.variables,
          variable_index: agent_state.variable_index,
          metadata: agent_state.metadata,
          stats: agent_state.stats
        }
      end)

    {:ok, exported}
  end

  @impl true
  def import_state(state, exported_state) do
    # Validate exported state structure
    required_keys = [:session_id, :variables, :variable_index]
    missing_keys = required_keys -- Map.keys(exported_state)

    if missing_keys != [] do
      {:error, {:invalid_export, {:missing_keys, missing_keys}}}
    else
      # Import into agent
      Agent.update(state.agent_pid, fn agent_state ->
        %{
          agent_state
          | variables: exported_state.variables,
            variable_index: exported_state.variable_index,
            metadata: Map.merge(agent_state.metadata, exported_state[:metadata] || %{}),
            stats:
              Map.merge(agent_state.stats, %{
                variable_count: map_size(exported_state.variables),
                imported_at: System.monotonic_time(:millisecond)
              })
        }
      end)

      Logger.info("LocalState: Imported #{map_size(exported_state.variables)} variables")
      {:ok, state}
    end
  end

  @impl true
  def requires_bridge?, do: false

  @impl true
  def capabilities do
    %{
      # Best-effort only
      atomic_updates: false,
      # Could be added via process messaging
      streaming: false,
      # In-memory only
      persistent: false,
      # Local process only
      distributed: false
    }
  end

  @impl true
  def cleanup(state) do
    if Process.alive?(state.agent_pid) do
      # Get final stats for logging
      stats = Agent.get(state.agent_pid, & &1.stats)

      Logger.debug("""
      LocalState cleanup for session #{state.session_id}:
        Variables: #{stats.variable_count}
        Total operations: #{stats.total_operations}
        Total updates: #{stats.total_updates || 0}
        Avg get time: #{avg_get_time(stats)}μs
      """)

      Agent.stop(state.agent_pid)
    end

    :ok
  end

  ## Private Helpers

  defp initial_state(session_id) do
    %{
      session_id: session_id,
      variables: %{},
      variable_index: %{},
      metadata: %{
        created_at: System.monotonic_time(:millisecond),
        backend: :local
      },
      stats: %{
        variable_count: 0,
        total_operations: 0,
        total_updates: 0,
        total_get_microseconds: 0
      }
    }
  end

  defp generate_session_id do
    "local_session_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp generate_var_id(name) do
    "var_#{name}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp resolve_identifier(agent_state, identifier) when is_atom(identifier) do
    resolve_identifier(agent_state, to_string(identifier))
  end

  defp resolve_identifier(agent_state, identifier) when is_binary(identifier) do
    # Check if it's already a var_id
    if Map.has_key?(agent_state.variables, identifier) do
      identifier
    else
      # Try to resolve as name
      Map.get(agent_state.variable_index, identifier)
    end
  end

  defp build_metadata(opts) do
    base = %{
      "source" => "elixir",
      "backend" => "local"
    }

    # Add description if provided
    base =
      case Keyword.get(opts, :description) do
        nil -> base
        desc -> Map.put(base, "description", desc)
      end

    # Merge any additional metadata
    Map.merge(base, Keyword.get(opts, :metadata, %{}))
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

  defp avg_get_time(%{total_operations: 0}), do: 0

  defp avg_get_time(%{total_get_microseconds: total_us, total_operations: ops}) do
    Float.round(total_us / ops, 2)
  end

  # Type system integration
  defp get_type_module(:float), do: {:ok, Types.Float}
  defp get_type_module(:integer), do: {:ok, Types.Integer}
  defp get_type_module(:string), do: {:ok, Types.String}
  defp get_type_module(:boolean), do: {:ok, Types.Boolean}
  defp get_type_module(type), do: {:error, {:unknown_type, type}}
end

# Inline type modules for self-contained implementation
# In production, would use Snakepit.Bridge.Variables.Types

defmodule DSPex.Bridge.State.Local.Types.Float do
  @moduledoc false

  def validate(value) when is_float(value), do: {:ok, value}
  def validate(value) when is_integer(value), do: {:ok, value * 1.0}
  def validate(_), do: {:error, "must be a number"}

  def validate_constraints(value, constraints) do
    with :ok <- check_min(value, Map.get(constraints, :min)),
         :ok <- check_max(value, Map.get(constraints, :max)) do
      :ok
    end
  end

  defp check_min(_value, nil), do: :ok
  defp check_min(value, min) when value >= min, do: :ok
  defp check_min(value, min), do: {:error, "value #{value} is below minimum #{min}"}

  defp check_max(_value, nil), do: :ok
  defp check_max(value, max) when value <= max, do: :ok
  defp check_max(value, max), do: {:error, "value #{value} is above maximum #{max}"}
end

defmodule DSPex.Bridge.State.Local.Types.Integer do
  @moduledoc false

  def validate(value) when is_integer(value), do: {:ok, value}
  def validate(_), do: {:error, "must be an integer"}

  def validate_constraints(value, constraints) do
    with :ok <- check_min(value, Map.get(constraints, :min)),
         :ok <- check_max(value, Map.get(constraints, :max)) do
      :ok
    end
  end

  defp check_min(_value, nil), do: :ok
  defp check_min(value, min) when value >= min, do: :ok
  defp check_min(value, min), do: {:error, "value #{value} is below minimum #{min}"}

  defp check_max(_value, nil), do: :ok
  defp check_max(value, max) when value <= max, do: :ok
  defp check_max(value, max), do: {:error, "value #{value} is above maximum #{max}"}
end

defmodule DSPex.Bridge.State.Local.Types.String do
  @moduledoc false

  def validate(value) when is_binary(value), do: {:ok, value}
  def validate(_), do: {:error, "must be a string"}

  def validate_constraints(value, constraints) do
    with :ok <- check_min_length(value, Map.get(constraints, :min_length)),
         :ok <- check_max_length(value, Map.get(constraints, :max_length)),
         :ok <- check_pattern(value, Map.get(constraints, :pattern)) do
      :ok
    end
  end

  defp check_min_length(_value, nil), do: :ok
  defp check_min_length(value, min) when byte_size(value) >= min, do: :ok

  defp check_min_length(value, min),
    do: {:error, "length #{byte_size(value)} is below minimum #{min}"}

  defp check_max_length(_value, nil), do: :ok
  defp check_max_length(value, max) when byte_size(value) <= max, do: :ok

  defp check_max_length(value, max),
    do: {:error, "length #{byte_size(value)} is above maximum #{max}"}

  defp check_pattern(_value, nil), do: :ok

  defp check_pattern(value, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, value) do
          :ok
        else
          {:error, "does not match pattern #{pattern}"}
        end

      {:error, _} ->
        {:error, "invalid pattern #{pattern}"}
    end
  end
end

defmodule DSPex.Bridge.State.Local.Types.Boolean do
  @moduledoc false

  def validate(value) when is_boolean(value), do: {:ok, value}
  def validate(_), do: {:error, "must be a boolean"}

  def validate_constraints(_value, _constraints), do: :ok
end

defmodule ElixirML.Process.VariableRegistry do
  @moduledoc """
  Registry for managing variable spaces and configurations across the system.
  Provides fast lookup, caching, and conflict resolution for variable operations.
  """

  use GenServer
  require Logger

  defstruct [
    :spaces_table,
    :configs_table,
    :dependencies_table,
    :active_optimizations
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    spaces_table = :ets.new(:variable_spaces, [:named_table, :public, :set])
    configs_table = :ets.new(:variable_configs, [:named_table, :public, :set])
    dependencies_table = :ets.new(:variable_dependencies, [:named_table, :public, :bag])

    state = %__MODULE__{
      spaces_table: spaces_table,
      configs_table: configs_table,
      dependencies_table: dependencies_table,
      active_optimizations: %{}
    }

    {:ok, state}
  end

  @doc """
  Register a variable space.
  """
  def register_space(space_id, variable_space) do
    GenServer.call(__MODULE__, {:register_space, space_id, variable_space})
  end

  @doc """
  Get a registered variable space.
  """
  def get_space(space_id) do
    case :ets.lookup(:variable_spaces, space_id) do
      [{^space_id, space}] -> {:ok, space}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Register a variable configuration.
  """
  def register_configuration(config_id, configuration, space_id) do
    GenServer.call(__MODULE__, {:register_configuration, config_id, configuration, space_id})
  end

  @doc """
  Get a registered configuration.
  """
  def get_configuration(config_id) do
    case :ets.lookup(:variable_configs, config_id) do
      [{^config_id, config, space_id, metadata}] ->
        {:ok, %{config: config, space_id: space_id, metadata: metadata}}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Track an active optimization process.
  """
  def track_optimization(optimization_id, pid, space_id) do
    GenServer.call(__MODULE__, {:track_optimization, optimization_id, pid, space_id})
  end

  @doc """
  Get all active optimizations for a space.
  """
  def get_active_optimizations(space_id) do
    GenServer.call(__MODULE__, {:get_active_optimizations, space_id})
  end

  @doc """
  Find configurations by criteria.
  """
  def find_configurations(criteria) do
    GenServer.call(__MODULE__, {:find_configurations, criteria})
  end

  @doc """
  Get registry statistics.
  """
  def registry_stats do
    GenServer.call(__MODULE__, :registry_stats)
  end

  # Server callbacks

  def handle_call({:register_space, space_id, variable_space}, _from, state) do
    # Validate space before registration
    case ElixirML.Variable.Space.validate_space(variable_space) do
      {:ok, _} ->
        :ets.insert(state.spaces_table, {space_id, variable_space})

        # Extract and cache dependencies
        dependencies = extract_dependencies(variable_space)

        Enum.each(dependencies, fn {var_name, deps} ->
          :ets.insert(state.dependencies_table, {space_id, var_name, deps})
        end)

        {:reply, {:ok, space_id}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:register_configuration, config_id, configuration, space_id}, _from, state) do
    # Validate configuration against space
    case get_space(space_id) do
      {:ok, space} ->
        case ElixirML.Variable.Space.validate_configuration(space, configuration) do
          {:ok, _} ->
            metadata = %{
              registered_at: System.monotonic_time(:millisecond),
              validation_status: :valid,
              performance_metrics: %{}
            }

            :ets.insert(state.configs_table, {config_id, configuration, space_id, metadata})
            {:reply, {:ok, config_id}, state}

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:track_optimization, optimization_id, pid, space_id}, _from, state) do
    # Monitor the optimization process
    Process.monitor(pid)

    new_optimizations =
      Map.put(state.active_optimizations, optimization_id, %{
        pid: pid,
        space_id: space_id,
        started_at: System.monotonic_time(:millisecond),
        status: :running
      })

    new_state = %{state | active_optimizations: new_optimizations}

    {:reply, {:ok, optimization_id}, new_state}
  end

  def handle_call({:get_active_optimizations, space_id}, _from, state) do
    active =
      state.active_optimizations
      |> Enum.filter(fn {_id, info} -> info.space_id == space_id end)
      |> Enum.into(%{})

    {:reply, active, state}
  end

  def handle_call({:find_configurations, criteria}, _from, state) do
    # Simple pattern matching on criteria
    configs = :ets.select(state.configs_table, build_match_spec(criteria))

    results =
      Enum.map(configs, fn {config_id, config, space_id, metadata} ->
        %{
          id: config_id,
          configuration: config,
          space_id: space_id,
          metadata: metadata
        }
      end)

    {:reply, results, state}
  end

  def handle_call(:registry_stats, _from, state) do
    stats = %{
      registered_spaces: :ets.info(state.spaces_table, :size),
      registered_configurations: :ets.info(state.configs_table, :size),
      active_optimizations: map_size(state.active_optimizations),
      memory_usage: %{
        spaces: :ets.info(state.spaces_table, :memory) * :erlang.system_info(:wordsize),
        configs: :ets.info(state.configs_table, :memory) * :erlang.system_info(:wordsize),
        dependencies:
          :ets.info(state.dependencies_table, :memory) * :erlang.system_info(:wordsize)
      }
    }

    {:reply, stats, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Clean up optimization tracking when process dies
    dead_optimizations =
      state.active_optimizations
      |> Enum.filter(fn {_id, info} -> info.pid == pid end)
      |> Enum.map(fn {id, _info} -> id end)

    new_optimizations =
      Enum.reduce(dead_optimizations, state.active_optimizations, fn id, acc ->
        Map.delete(acc, id)
      end)

    # Log the reason if not normal termination
    if reason != :normal do
      Logger.warning("Optimization process #{inspect(pid)} terminated: #{inspect(reason)}")
    end

    new_state = %{state | active_optimizations: new_optimizations}

    {:noreply, new_state}
  end

  # Private functions

  defp extract_dependencies(%ElixirML.Variable.Space{} = space) do
    space.variables
    |> Enum.flat_map(fn {var_name, variable} ->
      case variable.type do
        :composite ->
          deps = variable.config[:dependencies] || []
          [{var_name, deps}]

        _ ->
          []
      end
    end)
  end

  defp build_match_spec(criteria) do
    # Build ETS match specification based on criteria
    # This is a simplified version - could be enhanced for complex queries
    case criteria do
      %{space_id: space_id} ->
        [{{:"$1", :"$2", space_id, :"$4"}, [], [{{:"$1", :"$2", space_id, :"$4"}}]}]

      %{validation_status: status} ->
        guard = {:==, {:map_get, :validation_status, :"$4"}, status}
        [{{:"$1", :"$2", :"$3", :"$4"}, [guard], [{{:"$1", :"$2", :"$3", :"$4"}}]}]

      _ ->
        # Return all if no specific criteria
        [{{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", :"$2", :"$3", :"$4"}}]}]
    end
  end
end

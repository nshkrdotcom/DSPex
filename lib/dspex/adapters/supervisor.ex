defmodule DSPex.Adapters.Supervisor do
  @moduledoc """
  Supervisor for adapter system lifecycle management.

  Manages the startup, shutdown, and fault tolerance of adapter components,
  including adapter-specific services, connection pools, and monitoring processes.
  Supports dynamic adapter loading and test mode integration.
  """

  use Supervisor

  alias DSPex.Adapters.Registry

  require Logger

  @doc """
  Starts the adapter supervisor.

  ## Options

  - `:name` - Supervisor name (default: DSPex.Adapters.Supervisor)
  - `:adapters` - List of adapters to start (default: based on environment)
  - `:test_mode` - Override test mode detection
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts a specific adapter and its dependencies.

  ## Examples

      Supervisor.start_adapter(:python_port)
      Supervisor.start_adapter(:mock, name: :test_mock)
  """
  @spec start_adapter(atom(), keyword()) ::
          {:ok, pid()} | {:ok, :undefined | pid(), term()} | {:error, term()}
  def start_adapter(adapter_name, opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    case Registry.get_adapter(adapter_name) do
      nil ->
        {:error, :adapter_not_found}

      adapter_module ->
        # When we have a valid module, build the spec directly
        child_spec = build_adapter_spec_from_module(adapter_module, adapter_name, opts)
        Supervisor.start_child(supervisor, child_spec)
    end
  end

  @doc """
  Stops a running adapter.

  ## Examples

      Supervisor.stop_adapter(:mock)
  """
  @spec stop_adapter(atom(), keyword()) :: :ok | {:error, term()}
  def stop_adapter(adapter_name, opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)
    adapter_id = adapter_child_id(adapter_name)

    case Supervisor.terminate_child(supervisor, adapter_id) do
      :ok ->
        case Supervisor.delete_child(supervisor, adapter_id) do
          :ok -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Lists all running adapters.
  """
  @spec list_running_adapters(keyword()) :: [atom()]
  def list_running_adapters(opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    supervisor
    |> Supervisor.which_children()
    |> Enum.filter(fn {id, _, _, _} -> is_adapter_child?(id) end)
    |> Enum.map(fn {id, _, _, _} -> adapter_name_from_id(id) end)
  end

  @doc """
  Restarts an adapter with optional new configuration.
  """
  @spec restart_adapter(atom(), keyword()) ::
          {:ok, pid()} | {:ok, :undefined | pid(), term()} | {:error, term()}
  def restart_adapter(adapter_name, opts \\ []) do
    with :ok <- stop_adapter(adapter_name, opts) do
      start_adapter(adapter_name, opts)
    end
  end

  @doc """
  Returns the health status of all adapters.
  """
  @spec adapter_health_status(keyword()) :: %{atom() => map()}
  def adapter_health_status(opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, __MODULE__)

    supervisor
    |> Supervisor.which_children()
    |> Enum.filter(fn {id, _, _, _} -> is_adapter_child?(id) end)
    |> Enum.map(fn {id, pid, type, modules} ->
      adapter_name = adapter_name_from_id(id)
      status = get_adapter_status(adapter_name, pid, type, modules)
      {adapter_name, status}
    end)
    |> Map.new()
  end

  # Supervisor callbacks

  @impl true
  def init(opts) do
    children = build_children(opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private functions

  defp build_children(opts) do
    adapters = determine_adapters_to_start(opts)

    base_children = [
      # Registry is always needed
      {Registry, keys: :unique, name: DSPex.Adapters.ProcessRegistry}
    ]

    adapter_children =
      adapters
      |> Enum.map(fn adapter_name ->
        case build_adapter_spec(adapter_name, opts) do
          {:ok, spec} ->
            spec

          # Dialyzer thinks this can't happen, but user could pass invalid adapter names in opts
          {:error, reason} ->
            Logger.warning("Failed to build spec for adapter #{adapter_name}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    base_children ++ adapter_children
  end

  defp determine_adapters_to_start(opts) do
    cond do
      # Explicit adapter list takes precedence
      adapters = Keyword.get(opts, :adapters) ->
        adapters

      # In test mode, start based on current test layer
      Mix.env() == :test ->
        determine_test_adapters(opts)

      # In production, start configured adapters
      true ->
        determine_production_adapters()
    end
  end

  defp determine_test_adapters(opts) do
    # Use environment variable or explicit test_mode option
    test_mode = Keyword.get(opts, :test_mode) || get_test_mode_from_env()

    case test_mode do
      :mock_adapter -> [:mock]
      :bridge_mock -> [:mock, :bridge_mock]
      :full_integration -> [:mock, :bridge_mock, :python_port]
      # Default to mock for safety
      _ -> [:mock]
    end
  end

  defp get_test_mode_from_env do
    case System.get_env("TEST_MODE") do
      "mock_adapter" -> :mock_adapter
      "bridge_mock" -> :bridge_mock
      "full_integration" -> :full_integration
      _ -> :mock_adapter
    end
  end

  defp determine_production_adapters do
    # Start adapters based on configuration
    configured = Application.get_env(:dspex, :enabled_adapters, [:python_port])

    # Always include mock for fallback
    [:mock | configured] |> Enum.uniq()
  end

  # This function handles adapter modules and always succeeds
  defp build_adapter_spec_from_module(adapter_module, adapter_name, opts) do
    # Check if adapter has its own child_spec
    if function_exported?(adapter_module, :child_spec, 1) do
      spec = adapter_module.child_spec(opts)
      %{spec | id: adapter_child_id(adapter_name)}
    else
      # Build generic spec for adapters
      case build_generic_adapter_spec(adapter_module, adapter_name, opts) do
        {:ok, spec} -> spec
      end
    end
  end

  # This function handles adapter names and can fail
  defp build_adapter_spec(adapter_name, opts) when is_atom(adapter_name) do
    case Registry.get_adapter(adapter_name) do
      nil ->
        {:error, :adapter_not_found}

      module when is_atom(module) ->
        {:ok, build_adapter_spec_from_module(module, adapter_name, opts)}
    end
  end

  defp build_generic_adapter_spec(adapter_module, adapter_name, opts) do
    # Check if adapter needs to be started as a process
    spec =
      cond do
        # GenServer-based adapters
        function_exported?(adapter_module, :start_link, 1) ->
          %{
            id: adapter_child_id(adapter_name),
            start: {adapter_module, :start_link, [opts]},
            type: :worker,
            restart: :permanent
          }

        # Adapters that need services but aren't processes themselves
        function_exported?(adapter_module, :required_services, 0) ->
          build_adapter_services_spec(adapter_module, adapter_name)

        # Stateless adapters don't need supervision
        true ->
          %{
            id: adapter_child_id(adapter_name),
            start: {__MODULE__, :noop_start, [adapter_name]},
            type: :worker,
            restart: :temporary
          }
      end

    {:ok, spec}
  end

  defp build_adapter_services_spec(adapter_module, adapter_name) do
    services = adapter_module.required_services()

    if Enum.empty?(services) do
      # No services needed
      %{
        id: adapter_child_id(adapter_name),
        start: {__MODULE__, :noop_start, [adapter_name]},
        type: :worker,
        restart: :temporary
      }
    else
      # Create a sub-supervisor for adapter services
      %{
        id: adapter_child_id(adapter_name),
        start:
          {Supervisor, :start_link,
           [
             build_service_children(services),
             [strategy: :one_for_all, name: :"#{adapter_name}_services"]
           ]},
        type: :supervisor,
        restart: :permanent
      }
    end
  end

  defp build_service_children(services) do
    Enum.map(services, fn
      {module, opts} -> {module, opts}
      module -> module
    end)
  end

  defp adapter_child_id(adapter_name) do
    :"adapter_#{adapter_name}"
  end

  defp is_adapter_child?(id) do
    case id do
      id when is_atom(id) ->
        id |> to_string() |> String.starts_with?("adapter_")

      _ ->
        false
    end
  end

  defp adapter_name_from_id(id) do
    id
    |> to_string()
    |> String.replace_prefix("adapter_", "")
    |> String.to_atom()
  end

  defp get_adapter_status(adapter_name, pid, type, modules) do
    base_status = %{
      pid: pid,
      type: type,
      modules: modules,
      alive: Process.alive?(pid),
      adapter_name: adapter_name
    }

    # Try to get adapter-specific health info
    adapter_module = List.first(modules)

    if adapter_module && function_exported?(adapter_module, :health_check, 0) do
      case adapter_module.health_check() do
        :ok ->
          Map.put(base_status, :health, :healthy)

        {:error, reason} ->
          Map.merge(base_status, %{health: :unhealthy, error: reason})
      end
    else
      Map.put(base_status, :health, :unknown)
    end
  end

  @doc false
  def noop_start(adapter_name) do
    # For stateless adapters that don't need a process
    {:ok,
     spawn(fn ->
       Process.register(self(), :"#{adapter_name}_placeholder")
       Process.sleep(:infinity)
     end)}
  end
end

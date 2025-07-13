defmodule AshDSPex.Adapters.Registry do
  @moduledoc """
  Registry for DSPy adapters with automatic test mode selection.

  This registry manages the available adapters and provides intelligent
  selection based on the current test mode, explicit configuration, or
  runtime preferences.

  ## Adapter Selection Priority

  1. **Explicit adapter name** - When provided directly to `get_adapter/1`
  2. **Test mode adapter** - Based on `TEST_MODE` environment variable
  3. **Application configuration** - From `:ash_dspex, :adapter`
  4. **Default adapter** - Falls back to `:python_port`

  ## Test Layer Mapping

  The registry automatically maps test modes to appropriate adapters:

  - `:mock_adapter` → `AshDSPex.Adapters.Mock` (Layer 1)
  - `:bridge_mock` → `AshDSPex.Adapters.BridgeMock` (Layer 2)
  - `:full_integration` → `AshDSPex.Adapters.PythonPort` (Layer 3)

  ## Usage

      # Get adapter based on current configuration
      adapter = AshDSPex.Adapters.Registry.get_adapter()

      # Get specific adapter
      adapter = AshDSPex.Adapters.Registry.get_adapter(:mock)

      # Check adapter capabilities
      {:ok, capabilities} = AshDSPex.Adapters.Registry.get_adapter_capabilities(:bridge_mock)
  """

  require Logger

  @adapters %{
    python_port: AshDSPex.Adapters.PythonPort,
    bridge_mock: AshDSPex.Adapters.BridgeMock,
    mock: AshDSPex.Adapters.Mock
  }

  @test_layer_adapters %{
    mock_adapter: :mock,
    bridge_mock: :bridge_mock,
    full_integration: :python_port
  }

  @default_adapter :python_port

  @doc """
  Gets the appropriate adapter module based on priority rules.

  ## Parameters

  - `adapter_name` - Optional explicit adapter name (atom)

  ## Returns

  The adapter module or raises if the adapter is not found.

  ## Examples

      # Get adapter based on current configuration
      AshDSPex.Adapters.Registry.get_adapter()

      # Get specific adapter
      AshDSPex.Adapters.Registry.get_adapter(:mock)
  """
  @spec get_adapter(atom() | nil) :: module()
  def get_adapter(adapter_name \\ nil) do
    resolved_name = resolve_adapter_name(adapter_name)

    case Map.get(@adapters, resolved_name) do
      nil ->
        available = Map.keys(@adapters) |> Enum.join(", ")
        raise ArgumentError, "Unknown adapter: #{resolved_name}. Available: #{available}"

      module ->
        module
    end
  end

  @doc """
  Gets the adapter module if it exists, returns error tuple if not.

  ## Examples

      {:ok, AshDSPex.Adapters.Mock} = AshDSPex.Adapters.Registry.get_adapter_safe(:mock)
      {:error, :not_found} = AshDSPex.Adapters.Registry.get_adapter_safe(:unknown)
  """
  @spec get_adapter_safe(atom() | nil) :: {:ok, module()} | {:error, :not_found}
  def get_adapter_safe(adapter_name \\ nil) do
    resolved_name = resolve_adapter_name(adapter_name)

    case Map.get(@adapters, resolved_name) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Lists all available adapters.

  ## Returns

  A list of tuples with adapter name and module.

  ## Examples

      [
        {:mock, AshDSPex.Adapters.Mock},
        {:bridge_mock, AshDSPex.Adapters.BridgeMock},
        {:python_port, AshDSPex.Adapters.PythonPort}
      ] = AshDSPex.Adapters.Registry.list_adapters()
  """
  @spec list_adapters() :: [{atom(), module()}]
  def list_adapters do
    Enum.to_list(@adapters)
  end

  @doc """
  Gets the capabilities of a specific adapter.

  ## Parameters

  - `adapter_name` - The adapter to query

  ## Returns

  `{:ok, capabilities}` or `{:error, reason}`

  ## Examples

      {:ok, %{python_execution: true, ...}} = 
        AshDSPex.Adapters.Registry.get_adapter_capabilities(:python_port)
  """
  @spec get_adapter_capabilities(atom()) :: {:ok, map()} | {:error, term()}
  def get_adapter_capabilities(adapter_name) do
    case get_adapter_safe(adapter_name) do
      {:ok, module} ->
        try do
          capabilities = module.get_test_capabilities()
          {:ok, capabilities}
        rescue
          e ->
            {:error, {:capability_error, e}}
        end

      {:error, :not_found} ->
        {:error, :adapter_not_found}
    end
  end

  @doc """
  Checks if an adapter supports a specific test layer.

  ## Parameters

  - `adapter_name` - The adapter to check
  - `layer` - The test layer (`:layer_1`, `:layer_2`, `:layer_3`)

  ## Returns

  Boolean indicating support or raises if adapter not found.

  ## Examples

      true = AshDSPex.Adapters.Registry.supports_layer?(:mock, :layer_1)
      false = AshDSPex.Adapters.Registry.supports_layer?(:mock, :layer_3)
  """
  @spec supports_layer?(atom(), atom()) :: boolean()
  def supports_layer?(adapter_name, layer) do
    module = get_adapter(adapter_name)
    module.supports_test_layer?(layer)
  end

  @doc """
  Gets the adapter name that corresponds to a test layer.

  ## Parameters

  - `layer` - The test layer (`:layer_1`, `:layer_2`, `:layer_3`)

  ## Returns

  The adapter name or `nil` if no adapter supports that layer.

  ## Examples

      :mock = AshDSPex.Adapters.Registry.adapter_for_layer(:layer_1)
      :bridge_mock = AshDSPex.Adapters.Registry.adapter_for_layer(:layer_2)
      :python_port = AshDSPex.Adapters.Registry.adapter_for_layer(:layer_3)
  """
  @spec adapter_for_layer(atom()) :: atom() | nil
  def adapter_for_layer(layer) do
    @adapters
    |> Enum.find_value(fn {name, module} ->
      if module.supports_test_layer?(layer), do: name
    end)
  end

  # Private Functions

  defp resolve_adapter_name(nil) do
    # Priority: test mode -> config -> default
    test_adapter = get_test_mode_adapter()
    config_adapter = Application.get_env(:ash_dspex, :adapter)

    resolved = test_adapter || config_adapter || @default_adapter

    Logger.debug("""
    Adapter resolution:
      Explicit: nil
      Test mode: #{inspect(test_adapter)}
      Config: #{inspect(config_adapter)}
      Resolved: #{inspect(resolved)}
    """)

    resolved
  end

  defp resolve_adapter_name(adapter_name) when is_atom(adapter_name) do
    Logger.debug("Using explicit adapter: #{adapter_name}")
    adapter_name
  end

  defp get_test_mode_adapter do
    if Mix.env() == :test do
      case AshDSPex.Testing.TestMode.effective_test_mode() do
        test_mode when is_map_key(@test_layer_adapters, test_mode) ->
          adapter = Map.get(@test_layer_adapters, test_mode)
          Logger.debug("Test mode #{test_mode} maps to adapter #{adapter}")
          adapter

        test_mode ->
          Logger.debug("Test mode #{test_mode} has no adapter mapping")
          nil
      end
    else
      nil
    end
  end
end

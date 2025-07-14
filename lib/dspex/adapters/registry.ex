defmodule DSPex.Adapters.Registry do
  @moduledoc """
  Registry for DSPy adapters with automatic test mode selection.

  This registry manages the available adapters and provides intelligent
  selection based on the current test mode, explicit configuration, or
  runtime preferences.

  ## Adapter Selection Priority

  1. **Explicit adapter name** - When provided directly to `get_adapter/1`
  2. **Test mode adapter** - Based on `TEST_MODE` environment variable
  3. **Application configuration** - From `:dspex, :adapter`
  4. **Default adapter** - Falls back to `:python_port`

  ## Test Layer Mapping

  The registry automatically maps test modes to appropriate adapters:

  - `:mock_adapter` → `DSPex.Adapters.Mock` (Layer 1)
  - `:bridge_mock` → `DSPex.Adapters.BridgeMock` (Layer 2)
  - `:full_integration` → `DSPex.Adapters.PythonPort` (Layer 3)

  ## Usage

      # Get adapter based on current configuration
      adapter = DSPex.Adapters.Registry.get_adapter()

      # Get specific adapter
      adapter = DSPex.Adapters.Registry.get_adapter(:mock)

      # Check adapter capabilities
      {:ok, capabilities} = DSPex.Adapters.Registry.get_adapter_capabilities(:bridge_mock)
  """

  require Logger

  @adapters %{
    python_port: DSPex.Adapters.PythonPort,
    python_pool: DSPex.Adapters.PythonPoolV2,
    bridge_mock: DSPex.Adapters.BridgeMock,
    mock: DSPex.Adapters.Mock
  }

  @test_layer_adapters %{
    mock_adapter: :mock,
    bridge_mock: :bridge_mock,
    # This will be resolved based on pooling config
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
      DSPex.Adapters.Registry.get_adapter()

      # Get specific adapter
      DSPex.Adapters.Registry.get_adapter(:mock)
  """
  @spec get_adapter(atom() | String.t() | module() | nil) :: module()
  def get_adapter(adapter_name \\ nil)

  def get_adapter(nil) do
    resolved_name = resolve_adapter_name(nil)
    Map.get(@adapters, resolved_name)
  end

  def get_adapter(adapter_name) when is_binary(adapter_name) do
    get_adapter(String.to_existing_atom(adapter_name))
  rescue
    ArgumentError -> get_adapter(@default_adapter)
  end

  def get_adapter(adapter_name) when is_atom(adapter_name) do
    # First check if it's an adapter name like :mock
    case Map.get(@adapters, adapter_name) do
      nil ->
        # Not an adapter name, check if it's a module
        # Ensure the module is loaded before checking
        _ = Code.ensure_loaded(adapter_name)

        # Check if this is one of our adapter modules
        cond do
          adapter_name == DSPex.Adapters.Mock -> adapter_name
          adapter_name == DSPex.Adapters.BridgeMock -> adapter_name
          adapter_name == DSPex.Adapters.PythonPort -> adapter_name
          adapter_name == DSPex.Adapters.PythonPool -> adapter_name
          adapter_name == DSPex.Adapters.PythonPoolV2 -> adapter_name
          true -> Map.get(@adapters, @default_adapter)
        end

      module ->
        # It was an adapter name, return the module
        module
    end
  end

  @doc """
  Gets the adapter module if it exists, returns error tuple if not.

  ## Examples

      {:ok, DSPex.Adapters.Mock} = DSPex.Adapters.Registry.get_adapter_safe(:mock)
      {:error, :not_found} = DSPex.Adapters.Registry.get_adapter_safe(:unknown)
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
        {:mock, DSPex.Adapters.Mock},
        {:bridge_mock, DSPex.Adapters.BridgeMock},
        {:python_port, DSPex.Adapters.PythonPort}
      ] = DSPex.Adapters.Registry.list_adapters()
  """
  @spec list_adapters() :: [atom()]
  def list_adapters do
    Map.keys(@adapters)
  end

  @doc """
  Gets the adapter module for a specific test layer.

  ## Examples

      DSPex.Adapters.Registry.get_adapter_for_test_layer(:layer_1)
      # => DSPex.Adapters.Mock
  """
  @spec get_adapter_for_test_layer(atom()) :: module()
  def get_adapter_for_test_layer(layer) do
    case layer do
      :layer_1 -> Map.get(@adapters, :mock)
      :layer_2 -> Map.get(@adapters, :bridge_mock)
      :layer_3 -> Map.get(@adapters, :python_port)
      _ -> Map.get(@adapters, @default_adapter)
    end
  end

  @doc """
  Lists test layer to adapter mappings.

  ## Examples

      DSPex.Adapters.Registry.list_test_layer_adapters()
      # => %{mock_adapter: :mock, bridge_mock: :bridge_mock, full_integration: :python_port}
  """
  @spec list_test_layer_adapters() :: %{
          mock_adapter: :mock,
          bridge_mock: :bridge_mock,
          full_integration: :python_port
        }
  def list_test_layer_adapters do
    @test_layer_adapters
  end

  @doc """
  Validates that an adapter module implements required callbacks.

  ## Examples

      {:ok, DSPex.Adapters.Mock} = DSPex.Adapters.Registry.validate_adapter(DSPex.Adapters.Mock)
      {:error, _} = DSPex.Adapters.Registry.validate_adapter(InvalidModule)
  """
  @spec validate_adapter(module()) :: {:ok, module()} | {:error, String.t()}
  def validate_adapter(adapter_module) do
    case Code.ensure_loaded(adapter_module) do
      {:module, _} ->
        if function_exported?(adapter_module, :create_program, 1) and
             function_exported?(adapter_module, :execute_program, 2) and
             function_exported?(adapter_module, :list_programs, 0) and
             function_exported?(adapter_module, :delete_program, 1) do
          {:ok, adapter_module}
        else
          {:error, "Adapter does not implement required callbacks: #{adapter_module}"}
        end

      {:error, reason} ->
        {:error, "Failed to load adapter #{adapter_module}: #{reason}"}
    end
  end

  @doc """
  Validates test layer compatibility for an adapter.

  ## Examples

      {:ok, _} = DSPex.Adapters.Registry.validate_test_layer_compatibility(DSPex.Adapters.Mock, :layer_1)
      {:error, _} = DSPex.Adapters.Registry.validate_test_layer_compatibility(DSPex.Adapters.Mock, :layer_3)
  """
  @spec validate_test_layer_compatibility(module(), atom()) ::
          {:ok, module()} | {:error, String.t()}
  def validate_test_layer_compatibility(adapter_module, test_layer) do
    # Ensure module is loaded first
    _ = Code.ensure_loaded(adapter_module)

    # Always check if the module implements supports_test_layer? first
    if function_exported?(adapter_module, :supports_test_layer?, 1) do
      case adapter_module.supports_test_layer?(test_layer) do
        true -> {:ok, adapter_module}
        false -> {:error, "Adapter #{adapter_module} does not support test layer #{test_layer}"}
      end
    else
      # Assume compatibility if not implemented
      {:ok, adapter_module}
    end
  end

  @doc """
  Gets the capabilities of a specific adapter.

  ## Parameters

  - `adapter_name` - The adapter to query

  ## Returns

  `{:ok, capabilities}` or `{:error, reason}`

  ## Examples

      {:ok, %{python_execution: true, ...}} = 
        DSPex.Adapters.Registry.get_adapter_capabilities(:python_port)
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

      true = DSPex.Adapters.Registry.supports_layer?(:mock, :layer_1)
      false = DSPex.Adapters.Registry.supports_layer?(:mock, :layer_3)
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

      :mock = DSPex.Adapters.Registry.adapter_for_layer(:layer_1)
      :bridge_mock = DSPex.Adapters.Registry.adapter_for_layer(:layer_2)
      :python_port = DSPex.Adapters.Registry.adapter_for_layer(:layer_3)
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
    config_adapter = Application.get_env(:dspex, :adapter)

    # Check if we should use pooled adapter for layer 3
    resolved =
      case test_adapter do
        :python_port ->
          if Application.get_env(:dspex, :pooling_enabled, false) do
            :python_pool
          else
            :python_port
          end

        other ->
          other || config_adapter || @default_adapter
      end

    Logger.debug("""
    Adapter resolution:
      Explicit: nil
      Test mode: #{inspect(test_adapter)}
      Config: #{inspect(config_adapter)}
      Resolved: #{inspect(resolved)}
    """)

    resolved
  end

  defp get_test_mode_adapter do
    if Mix.env() == :test do
      # Only check TEST_MODE env var directly, not TestMode module
      # to avoid circular dependencies during tests
      case System.get_env("TEST_MODE") do
        nil ->
          nil

        env_mode ->
          test_mode =
            try do
              String.to_existing_atom(env_mode)
            rescue
              ArgumentError -> nil
            end

          case test_mode do
            mode when is_map_key(@test_layer_adapters, mode) ->
              adapter = Map.get(@test_layer_adapters, mode)
              Logger.debug("Test mode #{mode} maps to adapter #{adapter}")
              adapter

            _ ->
              Logger.debug("Test mode #{env_mode} has no adapter mapping")
              nil
          end
      end
    else
      nil
    end
  end
end

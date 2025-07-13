defmodule AshDSPex.Testing.TestMode do
  @moduledoc """
  Test mode configuration system for 3-layer testing architecture.

  This module provides configuration-driven switching between the three testing layers:
  - Layer 1: Mock Adapter (pure Elixir, no bridge)
  - Layer 2: Bridge Mock (protocol testing with mock server)
  - Layer 3: Full Integration (real Python bridge)

  ## Usage

      # In test configuration
      config :ash_dspex, :test_mode, :mock_adapter           # Layer 1 (default)
      config :ash_dspex, :test_mode, :bridge_mock           # Layer 2
      config :ash_dspex, :test_mode, :full_integration      # Layer 3

  ## Environment Variables

      TEST_MODE=mock_adapter mix test      # Layer 1
      TEST_MODE=bridge_mock mix test       # Layer 2  
      TEST_MODE=full_integration mix test  # Layer 3

  ## Test Helpers

      use AshDSPex.Testing.TestMode
      
      test "feature works across all layers" do
        case current_test_mode() do
          :mock_adapter -> 
            # Fast pure Elixir tests
          :bridge_mock -> 
            # Protocol validation tests
          :full_integration -> 
            # Complete E2E tests
        end
      end
  """

  @type test_mode :: :mock_adapter | :bridge_mock | :full_integration

  @default_mode :mock_adapter

  @doc """
  Gets the current test mode from configuration or environment.

  Priority order:
  1. Environment variable TEST_MODE
  2. Application configuration :ash_dspex :test_mode
  3. Default: :mock_adapter
  """
  @spec current_test_mode() :: test_mode()
  def current_test_mode do
    case System.get_env("TEST_MODE") do
      nil ->
        Application.get_env(:ash_dspex, :test_mode, @default_mode)

      env_mode ->
        try do
          case String.to_existing_atom(env_mode) do
            mode when mode in [:mock_adapter, :bridge_mock, :full_integration] ->
              mode

            _ ->
              IO.warn("Invalid TEST_MODE: #{env_mode}, using default: #{@default_mode}")
              @default_mode
          end
        rescue
          ArgumentError ->
            IO.warn("Invalid TEST_MODE: #{env_mode}, using default: #{@default_mode}")
            @default_mode
        end
    end
  end

  @doc """
  Sets the test mode for the current process.

  This overrides the global configuration for the current test process only.
  """
  @spec set_test_mode(test_mode()) :: :ok
  def set_test_mode(mode) when mode in [:mock_adapter, :bridge_mock, :full_integration] do
    Process.put(:test_mode_override, mode)
    :ok
  end

  @doc """
  Gets the effective test mode, considering process-level overrides.
  """
  @spec effective_test_mode() :: test_mode()
  def effective_test_mode do
    case Process.get(:test_mode_override) do
      nil -> current_test_mode()
      mode -> mode
    end
  end

  @doc """
  Clears any process-level test mode override.
  """
  @spec clear_test_mode_override() :: :ok
  def clear_test_mode_override do
    Process.delete(:test_mode_override)
    :ok
  end

  @doc """
  Returns the appropriate adapter module for the current test mode.
  """
  @spec get_adapter_module() ::
          AshDSPex.Adapters.Mock | AshDSPex.Adapters.BridgeMock | AshDSPex.Adapters.PythonBridge
  def get_adapter_module do
    case effective_test_mode() do
      :mock_adapter -> AshDSPex.Adapters.Mock
      :bridge_mock -> AshDSPex.Adapters.BridgeMock
      :full_integration -> AshDSPex.Adapters.PythonBridge
    end
  end

  @doc """
  Starts the appropriate services for the current test mode.

  Returns supervision spec or :ok if no services needed.
  """
  @spec start_test_services() :: {:ok, pid()} | :ok | :ignore | {:error, term()}
  def start_test_services do
    case effective_test_mode() do
      :mock_adapter ->
        # Start mock adapter GenServer
        AshDSPex.Adapters.Mock.start_link()

      :bridge_mock ->
        # Start bridge mock server
        AshDSPex.Testing.BridgeMockServer.start_link()

      :full_integration ->
        # Services will be started by the regular supervision tree
        :ok
    end
  end

  @doc """
  Stops test services if running.
  """
  @spec stop_test_services() :: :ok
  def stop_test_services do
    case effective_test_mode() do
      :mock_adapter ->
        if Process.whereis(AshDSPex.Adapters.Mock) do
          GenServer.stop(AshDSPex.Adapters.Mock)
        end

        :ok

      :bridge_mock ->
        if Process.whereis(AshDSPex.Testing.BridgeMockServer) do
          AshDSPex.Testing.BridgeMockServer.stop()
        end

        :ok

      :full_integration ->
        # Don't stop full integration services automatically
        :ok
    end
  end

  @doc """
  Returns configuration appropriate for the current test mode.
  """
  @spec get_test_config() :: %{
          async: boolean(),
          isolation: :none | :process | :supervision,
          max_concurrency: 1 | 10 | 50,
          setup_time: 10 | 100 | 2000,
          test_mode: :bridge_mock | :full_integration | :mock_adapter,
          timeout: 1000 | 5000 | 30000
        }
  def get_test_config do
    base_config = %{
      test_mode: effective_test_mode(),
      async: layer_supports_async?(),
      isolation: get_isolation_level()
    }

    case effective_test_mode() do
      :mock_adapter ->
        Map.merge(base_config, %{
          # Fast tests
          timeout: 1_000,
          # High concurrency safe
          max_concurrency: 50,
          # Minimal setup
          setup_time: 10
        })

      :bridge_mock ->
        Map.merge(base_config, %{
          # Protocol overhead
          timeout: 5_000,
          # Moderate concurrency
          max_concurrency: 10,
          # Mock server startup
          setup_time: 100
        })

      :full_integration ->
        Map.merge(base_config, %{
          # Python startup time
          timeout: 30_000,
          # Sequential for stability
          max_concurrency: 1,
          # Python bridge startup
          setup_time: 2_000
        })
    end
  end

  @doc """
  Checks if the current test mode supports async testing.
  """
  @spec layer_supports_async?() :: boolean()
  def layer_supports_async? do
    case effective_test_mode() do
      # Pure Elixir, fully concurrent
      :mock_adapter -> true
      # Mock server can handle concurrency
      :bridge_mock -> true
      # Python bridge needs isolation
      :full_integration -> false
    end
  end

  @doc """
  Returns the isolation level required for the current test mode.
  """
  @spec get_isolation_level() :: :none | :process | :supervision
  def get_isolation_level do
    case effective_test_mode() do
      # No isolation needed
      :mock_adapter -> :none
      # Process-level isolation
      :bridge_mock -> :process
      # Full supervision isolation
      :full_integration -> :supervision
    end
  end

  @doc """
  Returns a description of the current test mode for logging.
  """
  @spec mode_description() :: String.t()
  def mode_description do
    case effective_test_mode() do
      :mock_adapter ->
        "Layer 1: Mock Adapter (pure Elixir, millisecond tests)"

      :bridge_mock ->
        "Layer 2: Bridge Mock (protocol testing, sub-second tests)"

      :full_integration ->
        "Layer 3: Full Integration (real Python, multi-second tests)"
    end
  end

  @doc """
  Macro for conditional test execution based on test mode.
  """
  defmacro test_in_mode(modes, test_name, do: block) when is_list(modes) do
    quote do
      if AshDSPex.Testing.TestMode.effective_test_mode() in unquote(modes) do
        test unquote(test_name), do: unquote(block)
      else
        @tag :skip
        test unquote(
               "#{test_name} (skipped in #{AshDSPex.Testing.TestMode.effective_test_mode()} mode)"
             ),
             do: :ok
      end
    end
  end

  defmacro test_in_mode(mode, test_name, do: block) when is_atom(mode) do
    quote do
      test_in_mode([unquote(mode)], unquote(test_name), do: unquote(block))
    end
  end

  @doc """
  Runs a block of code only in specific test modes.
  """
  defmacro only_in_mode(modes, do: block) when is_list(modes) do
    quote do
      if AshDSPex.Testing.TestMode.effective_test_mode() in unquote(modes) do
        unquote(block)
      end
    end
  end

  defmacro only_in_mode(mode, do: block) when is_atom(mode) do
    quote do
      only_in_mode([unquote(mode)], do: unquote(block))
    end
  end

  @doc """
  Helper for setting up tests with appropriate timeouts and configuration.
  """
  def setup_test_mode do
    config = get_test_config()

    # Set appropriate timeouts
    ExUnit.configure(timeout: config.timeout)

    # Start services if needed
    case start_test_services() do
      {:ok, _pid} -> :ok
      :ok -> :ok
      :ignore -> :ok
      {:error, _reason} -> :ok
    end

    # Return config for test use
    {:ok, config}
  end

  @doc """
  Helper for cleaning up after tests in the current mode.
  """
  def cleanup_test_mode do
    clear_test_mode_override()

    # Reset mock states
    case effective_test_mode() do
      :mock_adapter ->
        if Process.whereis(AshDSPex.Adapters.Mock) do
          AshDSPex.Adapters.Mock.reset()
        end

      :bridge_mock ->
        if Process.whereis(AshDSPex.Testing.BridgeMockServer) do
          AshDSPex.Testing.BridgeMockServer.reset()
        end

      :full_integration ->
        # Let supervision handle cleanup
        :ok
    end
  end

  # Convenience functions for use in ExUnit setup callbacks

  @doc """
  ExUnit setup callback that configures the test for the current mode.
  """
  def setup_for_current_mode(_context) do
    {:ok, config} = setup_test_mode()

    # Note: on_exit should be called from the test module, not here
    # Tests using this should call cleanup_test_mode() in their own on_exit

    {:ok, %{test_mode: effective_test_mode(), test_config: config}}
  end

  defmacro __using__(_opts) do
    quote do
      import AshDSPex.Testing.TestMode,
        only: [
          test_in_mode: 3,
          only_in_mode: 2,
          current_test_mode: 0,
          effective_test_mode: 0,
          set_test_mode: 1,
          mode_description: 0
        ]

      setup :setup_for_current_mode
    end
  end
end

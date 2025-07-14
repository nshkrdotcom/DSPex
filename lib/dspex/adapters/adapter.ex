defmodule DSPex.Adapters.Adapter do
  @moduledoc """
  Behavior for DSPy adapters with 3-layer testing support.

  This behavior defines the contract that all DSPy adapters must implement,
  including support for the 3-layer testing architecture:

  - **Layer 1 (Mock Adapter)**: Pure Elixir, deterministic responses
  - **Layer 2 (Bridge Mock)**: Protocol validation with mock server
  - **Layer 3 (Python Port)**: Full Python bridge integration

  ## Core Operations

  All adapters must implement the basic DSPy operations for program
  management and execution.

  ## Test Layer Support

  Adapters declare which test layer they support through the
  `supports_test_layer?/1` callback and provide information about
  their capabilities through `get_test_capabilities/0`.

  ## Example Implementation

      defmodule MyAdapter do
        @behaviour DSPex.Adapters.Adapter

        @impl true
        def create_program(config) do
          # Implementation
        end

        @impl true
        def supports_test_layer?(layer), do: layer == :layer_1

        @impl true
        def get_test_capabilities do
          %{
            deterministic_outputs: true,
            python_execution: false,
            performance: :fast
          }
        end
      end
  """

  @type program_id :: String.t()
  @type config :: map()
  @type inputs :: map()
  @type options :: map()
  @type error :: {:error, term()}

  # Core operations (required)
  @callback create_program(config()) :: {:ok, program_id()} | error()
  @callback execute_program(program_id(), inputs()) :: {:ok, map()} | error()
  @callback list_programs() :: {:ok, list(program_id())} | error()
  @callback delete_program(program_id()) :: :ok | error()

  # Extended operations (optional)
  @callback execute_program(program_id(), inputs(), options()) :: {:ok, map()} | error()
  @callback get_program_info(program_id()) :: {:ok, map()} | error()
  @callback health_check() :: :ok | error()
  @callback get_stats() :: {:ok, map()} | error()

  # Language Model Configuration
  @callback configure_lm(config()) :: :ok | error()

  # Test layer compatibility (required for 3-layer testing)
  @callback supports_test_layer?(atom()) :: boolean()
  @callback get_test_capabilities() :: map()

  @optional_callbacks [
    execute_program: 3,
    get_program_info: 1,
    health_check: 0,
    get_stats: 0
  ]
end

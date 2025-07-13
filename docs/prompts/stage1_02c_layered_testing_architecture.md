● Most Robust Long-Term Option: Multi-Level Testing Architecture

  The Long-Term Reality

  You'll eventually need all three levels of testing as your system grows:

  1. Unit Level: Fast tests for Ash logic without any bridge overhead
  2. Integration Level: Bridge communication testing with mock Python responses
  3. End-to-End Level: Full stack testing with real Python DSPy

  Building only bridge-level testing now = technical debt later.

  Recommended Robust Architecture

  Option: Layered Mock Strategy 🎯

  # Layer 1: Adapter Interface Mock (Bypass everything)
  defmodule AshDSPy.Adapters.Mock do
    @behaviour AshDSPy.Adapters.Adapter
    # Pure Elixir responses, no bridge communication
    # 99% of your unit tests will use this
  end

  # Layer 2: Bridge Mock Server (Test bridge communication)
  defmodule AshDSPy.PythonBridge.MockPythonServer do
    # Simulates Python DSPy process over wire protocol
    # Tests serialization, timeouts, error handling
    # Integration tests use this
  end

  # Layer 3: Real Python Bridge (Full integration)
  defmodule AshDSPy.Adapters.PythonPort do
    # Uses real Python DSPy process
    # End-to-end tests use this
  end

  Why This Is Most Robust Long-Term

  Testing Speed Pyramid:
      E2E Tests (Slow, Comprehensive)
         /\
        /  \
       /    \
  Integration Tests (Medium Speed)
     /        \
    /          \
  Unit Tests (Fast, Focused)

  With layered mocks:
  - Unit tests: Use Mock adapter → milliseconds per test
  - Integration tests: Use MockPythonServer → hundreds of milliseconds
  - E2E tests: Use real Python → seconds per test

  Without layered mocks:
  - All tests: Use bridge with some form of mocking → seconds per test
  - Test suite becomes slow → developers avoid running tests
  - Debugging becomes hard → can't isolate which layer failed

  Implementation Strategy

  Phase 1: Build Both Mocks Now (Stage 1)

  1. Adapter-Level Mock (from my original proposal)
  # lib/ash_dspy/adapters/mock.ex
  defmodule AshDSPy.Adapters.Mock do
    @behaviour AshDSPy.Adapters.Adapter
    # Complete standalone implementation
    # No bridge dependencies
  end

  2. Bridge Mock Server (new addition)
  # lib/ash_dspy/python_bridge/mock_server.ex
  defmodule AshDSPy.PythonBridge.MockServer do
    @moduledoc """
    Mock Python server that speaks the bridge wire protocol.
    Allows testing bridge communication without Python DSPy.
    """

    use GenServer

    def start_link(opts \\ []) do
      port = Keyword.get(opts, :port, find_free_port())
      GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
    end

    def init(%{port: port}) do
      # Start TCP server that responds like Python DSPy
      {:ok, listen_socket} = :gen_tcp.listen(port, [
        :binary,
        packet: 4,  # Same as your bridge
        active: false,
        reuseaddr: true
      ])

      # Accept connections in separate process
      spawn_link(fn -> accept_loop(listen_socket) end)

      {:ok, %{port: port, socket: listen_socket}}
    end

    defp accept_loop(listen_socket) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, socket} ->
          spawn(fn -> handle_client(socket) end)
          accept_loop(listen_socket)

        {:error, reason} ->
          Logger.error("Mock server accept failed: #{reason}")
      end
    end

    defp handle_client(socket) do
      case :gen_tcp.recv(socket, 0) do
        {:ok, data} ->
          response = handle_bridge_request(data)
          :gen_tcp.send(socket, response)
          handle_client(socket)

        {:error, :closed} ->
          :gen_tcp.close(socket)
      end
    end

    defp handle_bridge_request(data) do
      # Parse bridge protocol message
      case Jason.decode(data) do
        {:ok, %{"command" => command, "args" => args, "id" => id}} ->
          result = execute_mock_command(command, args)

          response = %{
            id: id,
            success: true,
            result: result
          }

          Jason.encode!(response)

        {:error, _} ->
          error_response = %{
            id: nil,
            success: false,
            error: "Invalid JSON"
          }

          Jason.encode!(error_response)
      end
    end

    defp execute_mock_command("create_program", args) do
      %{
        "program_id" => args["id"],
        "status" => "created"
      }
    end

    defp execute_mock_command("execute_program", args) do
      # Generate mock response based on inputs
      generate_mock_execution_result(args)
    end

    # ... other command handlers
  end

  3. Enhanced Bridge for Test Mode
  # Enhance your existing bridge
  defmodule AshDSPy.PythonBridge.Bridge do
    def start_link(opts \\ []) do
      case Keyword.get(opts, :mode, :production) do
        :test_mock_server ->
          start_with_mock_server(opts)
        :production ->
          start_with_python_process(opts)
      end
    end

    defp start_with_mock_server(opts) do
      # Start mock server
      {:ok, _} = AshDSPy.PythonBridge.MockServer.start_link()

      # Connect to mock server instead of Python process
      # Everything else works exactly the same
    end
  end

  Phase 2: Configure Test Levels

  # config/test.exs

  # Unit tests: Use adapter mock
  config :ash_dspy, :adapter, AshDSPy.Adapters.Mock

  # Integration tests: Use bridge with mock server
  config :ash_dspy, :bridge_mode, :test_mock_server

  # E2E tests: Use real Python
  config :ash_dspy, :bridge_mode, :production

  Test Configuration:
  defmodule AshDSPy.TestHelpers do
    def setup_unit_testing do
      Application.put_env(:ash_dspy, :adapter, AshDSPy.Adapters.Mock)
      AshDSPy.Adapters.Mock.start_link()
    end

    def setup_integration_testing do
      Application.put_env(:ash_dspy, :bridge_mode, :test_mock_server)
      AshDSPy.PythonBridge.Bridge.start_link(mode: :test_mock_server)
    end

    def setup_e2e_testing do
      Application.put_env(:ash_dspy, :bridge_mode, :production)
      # Requires Python DSPy installation
    end
  end

  Usage in Tests

  # Fast unit tests (99% of tests)
  defmodule AshDSPy.ML.ProgramTest do
    use ExUnit.Case

    setup do
      AshDSPy.TestHelpers.setup_unit_testing()
      :ok
    end

    test "program creation" do
      # Tests Ash resources only
      # Milliseconds per test
    end
  end

  # Integration tests (critical path testing)
  defmodule AshDSPy.BridgeIntegrationTest do
    use ExUnit.Case

    setup do
      AshDSPy.TestHelpers.setup_integration_testing()
      :ok
    end

    test "bridge communication" do
      # Tests bridge + wire protocol + serialization
      # Hundreds of milliseconds per test
    end
  end

  # E2E tests (smoke tests)
  defmodule AshDSPy.E2ETest do
    use ExUnit.Case

    setup do
      AshDSPy.TestHelpers.setup_e2e_testing()
      :ok
    end

    test "full stack" do
      # Tests everything including real Python
      # Seconds per test
    end
  end

  Why This Is Worth Doing Now

  Benefits You Get Immediately:

  1. Fast Development Cycle: Unit tests run in milliseconds
  2. Easy Debugging: Know exactly which layer failed
  3. Parallel Development: Can work on Ash logic while bridge is broken
  4. CI/CD Ready: Fast test suite that doesn't require Python setup

  Benefits You Get Long-Term:

  1. Scales to Large Codebase: Test suite stays fast as you add features
  2. Easy Onboarding: New developers can run tests without Python setup
  3. Flexible Deployment: Can test different configurations easily
  4. Future-Proof: Ready for your Elixir Native DSPy port

  Cost:

  - More upfront work: ~2-3 extra days now
  - More complexity: 3 testing modes instead of 1

  Alternative Cost:

  - Slow test suite: Minutes instead of seconds as you add features
  - Debugging difficulty: Hard to isolate failures
  - Development friction: Developers avoid running tests
  - Technical debt: Will need to refactor testing later anyway

  Bottom Line Recommendation

  Build the layered testing architecture now. It's 2-3 days of extra work that will save you weeks later and make your development experience dramatically better.

  The testing pyramid is a proven pattern for good reason - you'll need it eventually, and it's much easier to build right from the start than to retrofit later.

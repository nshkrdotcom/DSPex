defmodule AshDSPex.Adapters.BridgeMock do
  @moduledoc """
  Bridge mock adapter for Layer 2 testing.

  This adapter wraps the existing `AshDSPex.Testing.BridgeMockServer` to provide
  a standard adapter interface for the 3-layer testing architecture. It enables
  protocol-level testing without requiring a real Python process.

  ## Features

  - Protocol validation with accurate JSON communication
  - Wire format testing for bridge compatibility
  - Configurable response delays and error scenarios
  - Deterministic outputs for reliable testing
  - Fast execution compared to full Python integration

  ## Test Layer Support

  This adapter supports **Layer 2** of the testing architecture, providing:
  - Bridge protocol validation
  - JSON serialization/deserialization testing
  - Error scenario simulation
  - No actual Python execution

  ## Usage

      # Through the registry (recommended)
      adapter = AshDSPex.Adapters.Registry.get_adapter(:bridge_mock)
      {:ok, program_id} = adapter.create_program(%{signature: %{...}})

      # Direct usage
      {:ok, result} = AshDSPex.Adapters.BridgeMock.execute_program("program_id", %{input: "test"})
  """

  @behaviour AshDSPex.Adapters.Adapter

  alias AshDSPex.Testing.BridgeMockServer

  require Logger

  # Core adapter operations

  @impl true
  def create_program(config) do
    _ = ensure_server_started()

    # Convert adapter format to bridge mock format
    args = %{
      "id" => Map.get(config, :id) || Map.get(config, "id") || generate_program_id(),
      "signature" => Map.get(config, :signature) || Map.get(config, "signature")
    }

    # Send through mock server to simulate bridge protocol
    case send_command("create_program", args) do
      {:ok, response} ->
        program_id = Map.get(response, "program_id") || Map.get(response, :program_id)
        {:ok, program_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    _ = ensure_server_started()

    args = %{
      "program_id" => program_id,
      "inputs" => inputs
    }

    case send_command("execute_program", args) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_programs do
    _ = ensure_server_started()

    case send_command("list_programs", %{}) do
      {:ok, %{"programs" => programs}} ->
        program_ids = Enum.map(programs, fn p -> Map.get(p, "id") || Map.get(p, :id) end)
        {:ok, program_ids}

      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, fn p -> Map.get(p, "id") || Map.get(p, :id) end)
        {:ok, program_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_program(program_id) do
    _ = ensure_server_started()

    args = %{"program_id" => program_id}

    case send_command("delete_program", args) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Optional callbacks

  @impl true
  def get_program_info(program_id) do
    _ = ensure_server_started()

    args = %{"program_id" => program_id}

    send_command("get_program_info", args)
  end

  @impl true
  def health_check do
    _ = ensure_server_started()

    case send_command("ping", %{}) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{status: "ok"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unhealthy}
    end
  end

  @impl true
  def get_stats do
    _ = ensure_server_started()

    case send_command("get_stats", %{}) do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  # Test layer support

  @impl true
  def supports_test_layer?(layer), do: layer == :layer_2

  @impl true
  def get_test_capabilities do
    %{
      protocol_validation: true,
      wire_format_testing: true,
      python_execution: false,
      deterministic_outputs: true,
      performance: :fast,
      error_simulation: true,
      request_correlation: true,
      json_serialization: true
    }
  end

  # Configuration and management

  @doc """
  Configures the bridge mock server with specific settings.

  ## Options

  - `:response_delay_ms` - Delay before sending responses (default: 10)
  - `:error_probability` - Probability of random errors (0.0-1.0)
  - `:timeout_probability` - Probability of timeouts (0.0-1.0)

  ## Examples

      AshDSPex.Adapters.BridgeMock.configure(%{
        response_delay_ms: 50,
        error_probability: 0.1
      })
  """
  def configure(config) do
    _ = ensure_server_started()
    BridgeMockServer.configure(config)
  end

  @doc """
  Adds an error scenario to simulate specific failure conditions.

  ## Scenario Options

  - `:command` - Command to trigger on (or `:any`)
  - `:probability` - Probability of triggering (0.0-1.0)
  - `:error_type` - Type of error to return
  - `:message` - Error message

  ## Examples

      AshDSPex.Adapters.BridgeMock.add_error_scenario(%{
        command: "execute_program",
        probability: 0.5,
        error_type: :timeout,
        message: "Simulated timeout"
      })
  """
  def add_error_scenario(scenario) do
    _ = ensure_server_started()

    case BridgeMockServer.add_error_scenario(scenario) do
      {:ok, _scenario_id} -> :ok
      error -> error
    end
  end

  @doc """
  Resets the bridge mock server state.

  Clears all programs, scenarios, and statistics.
  """
  def reset do
    _ = ensure_server_started()
    BridgeMockServer.reset()
  end

  # Private functions

  defp ensure_server_started do
    case Process.whereis(BridgeMockServer) do
      nil ->
        Logger.debug("Starting BridgeMockServer for BridgeMock adapter")

        case BridgeMockServer.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp send_command(command, args) do
    # Simulate sending through the bridge protocol
    # The mock server handles this internally, but we simulate the flow
    request_id = System.unique_integer([:positive])

    # Create a mock port-like interface
    mock_request = %{
      "id" => request_id,
      "command" => command,
      "args" => args
    }

    # Send to the mock server's internal handling
    # This simulates what would happen through the port
    try do
      case GenServer.call(BridgeMockServer, {:mock_request, mock_request}, 5000) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  defp generate_program_id do
    "bridge_mock_program_#{System.unique_integer([:positive])}"
  end
end

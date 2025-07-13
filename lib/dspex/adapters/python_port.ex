defmodule DSPex.Adapters.PythonPort do
  @moduledoc """
  Python port adapter for Layer 3 testing.

  This adapter wraps the existing `DSPex.PythonBridge.Bridge` to provide
  a standard adapter interface for the 3-layer testing architecture. It enables
  full integration testing with real Python DSPy execution.

  ## Features

  - Real Python DSPy execution
  - Full ML model support
  - Complete protocol validation
  - Production-identical behavior
  - Support for all DSPy features

  ## Test Layer Support

  This adapter supports **Layer 3** of the testing architecture, providing:
  - Real Python process execution
  - Actual DSPy library usage
  - Real ML model interactions
  - Full end-to-end testing

  ## Requirements

  - Python 3.8+ installed
  - DSPy library installed (`pip install dspy-ai`)
  - API keys configured for ML providers (if using real models)

  ## Usage

      # Through the registry (recommended)
      adapter = DSPex.Adapters.Registry.get_adapter(:python_port)
      {:ok, program_id} = adapter.create_program(%{signature: %{...}})

      # Direct usage
      {:ok, result} = DSPex.Adapters.PythonPort.execute_program("program_id", %{input: "test"})
  """

  @behaviour DSPex.Adapters.Adapter

  alias DSPex.PythonBridge.Bridge

  require Logger

  # Core adapter operations

  @impl true
  def create_program(config) do
    ensure_bridge_started()

    # Use existing Bridge.call/2 infrastructure
    case Bridge.call(:create_program, convert_config(config)) do
      {:ok, response} ->
        program_id = extract_program_id(response)
        {:ok, program_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    ensure_bridge_started()

    args = %{
      program_id: program_id,
      inputs: inputs
    }

    case Bridge.call(:execute_program, args) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs, options) do
    ensure_bridge_started()

    args = %{
      program_id: program_id,
      inputs: inputs,
      options: options
    }

    case Bridge.call(:execute_program, args) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_programs do
    ensure_bridge_started()

    case Bridge.call(:list_programs, %{}) do
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
    ensure_bridge_started()

    case Bridge.call(:delete_program, %{program_id: program_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Optional callbacks

  @impl true
  def get_program_info(program_id) do
    ensure_bridge_started()

    case Bridge.call(:get_program_info, %{program_id: program_id}) do
      {:ok, info} ->
        # Ensure the program ID is included in the response
        enhanced_info =
          Map.merge(info, %{
            "id" => program_id,
            :id => program_id
          })

        {:ok, enhanced_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def health_check do
    ensure_bridge_started()

    case Bridge.call(:ping, %{}) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, %{status: "ok"}} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unhealthy}
    end
  end

  @impl true
  def get_stats do
    ensure_bridge_started()

    case Bridge.call(:get_stats, %{}) do
      {:ok, bridge_stats} ->
        # Enhance bridge stats with adapter-specific information
        adapter_stats =
          Map.merge(bridge_stats, %{
            adapter_type: :python_port,
            layer: :layer_3,
            python_execution: true
          })

        {:ok, adapter_stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Test layer support

  @impl true
  def supports_test_layer?(layer), do: layer == :layer_3

  @impl true
  def get_test_capabilities do
    %{
      python_execution: true,
      real_ml_models: true,
      protocol_validation: true,
      deterministic_outputs: false,
      performance: :slowest,
      requires_environment: [:python, :dspy, :api_keys],
      full_dspy_features: true,
      production_identical: true
    }
  end

  # Python bridge management

  @doc """
  Gets the current status of the Python bridge.

  Returns detailed information about the bridge state, uptime, and statistics.
  """
  def get_bridge_status do
    ensure_bridge_started()
    Bridge.get_status()
  end

  @doc """
  Restarts the Python bridge process.

  Useful for recovering from errors or applying configuration changes.
  """
  def restart_bridge do
    ensure_bridge_started()
    Bridge.restart()
  end

  # Private functions

  defp ensure_bridge_started do
    # The bridge is managed by the supervision tree in full integration mode
    # We just need to check if it's running
    case Process.whereis(Bridge) do
      nil ->
        # In test mode, the bridge should be started by the supervision tree
        # based on the TEST_MODE configuration
        Logger.error("Python bridge not running - check supervision configuration")
        raise "Python bridge not available"

      _pid ->
        :ok
    end
  end

  defp convert_config(config) do
    # Convert adapter config format to bridge format
    # The bridge expects certain keys in specific formats
    converted =
      config
      |> Map.new(fn
        {:id, value} -> {"id", value}
        {"id", value} -> {"id", value}
        {:signature, value} -> {"signature", convert_signature(value)}
        {"signature", value} -> {"signature", convert_signature(value)}
        {key, value} -> {to_string(key), value}
      end)

    # Ensure program ID is present - generate one if missing
    case Map.get(converted, "id") do
      nil -> Map.put(converted, "id", generate_program_id())
      "" -> Map.put(converted, "id", generate_program_id())
      _id -> converted
    end
  end

  defp convert_signature(signature) when is_map(signature) do
    # Ensure signature format is compatible with Python bridge
    signature
    |> Map.new(fn
      {:inputs, value} -> {"inputs", convert_io_list(value)}
      {"inputs", value} -> {"inputs", convert_io_list(value)}
      {:outputs, value} -> {"outputs", convert_io_list(value)}
      {"outputs", value} -> {"outputs", convert_io_list(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp convert_signature(signature), do: signature

  defp convert_io_list(io_list) when is_list(io_list) do
    Enum.map(io_list, fn item ->
      Map.new(item, fn
        {:name, value} -> {"name", value}
        {"name", value} -> {"name", value}
        {:type, value} -> {"type", value}
        {"type", value} -> {"type", value}
        {key, value} -> {to_string(key), value}
      end)
    end)
  end

  defp convert_io_list(io_list), do: io_list

  defp extract_program_id(response) do
    Map.get(response, "program_id") ||
      Map.get(response, :program_id) ||
      Map.get(response, "id") ||
      Map.get(response, :id)
  end

  defp generate_program_id do
    "python_port_#{:erlang.unique_integer([:positive])}"
  end
end

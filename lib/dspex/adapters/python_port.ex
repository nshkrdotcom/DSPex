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

  alias DSPex.PythonBridge.{Bridge, SessionPoolV2}

  require Logger

  # Core adapter operations

  @impl true
  def create_program(config) do
    case ensure_bridge_started() do
      :ok ->
        # Use appropriate backend based on pooling mode
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          python_config = convert_config(config)
          session_id = Map.get(config, :session_id, "anonymous")
          
          case SessionPoolV2.execute_in_session(session_id, :create_program, python_config) do
            {:ok, response} ->
              program_id = extract_program_id(response)
              {:ok, program_id}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # Use existing Bridge.call/2 infrastructure
          case Bridge.call(:create_program, convert_config(config)) do
            {:ok, response} ->
              program_id = extract_program_id(response)
              {:ok, program_id}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    case ensure_bridge_started() do
      :ok ->
        args = %{
          program_id: program_id,
          inputs: inputs
        }

        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          session_id = Map.get(inputs, :session_id, "anonymous")
          
          case SessionPoolV2.execute_in_session(session_id, :execute_program, args) do
            {:ok, response} ->
              {:ok, response}

            {:error, reason} ->
              {:error, reason}
          end
        else
          case Bridge.call(:execute_program, args) do
            {:ok, response} ->
              {:ok, response}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs, options) do
    case ensure_bridge_started() do
      :ok ->
        args = %{
          program_id: program_id,
          inputs: inputs,
          options: options
        }

        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          session_id = Keyword.get(options, :session_id, Map.get(inputs, :session_id, "anonymous"))
          
          case SessionPoolV2.execute_in_session(session_id, :execute_program, args, options) do
            {:ok, response} ->
              {:ok, response}

            {:error, reason} ->
              {:error, reason}
          end
        else
          case Bridge.call(:execute_program, args) do
            {:ok, response} ->
              {:ok, response}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_programs do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:list_programs, %{}) do
            {:ok, %{"programs" => programs}} ->
              program_ids = Enum.map(programs, fn p -> Map.get(p, "id") || Map.get(p, :id) end)
              {:ok, program_ids}

            {:ok, %{programs: programs}} ->
              program_ids = Enum.map(programs, fn p -> Map.get(p, "id") || Map.get(p, :id) end)
              {:ok, program_ids}

            {:error, reason} ->
              {:error, reason}
          end
        else
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_program(program_id) do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:delete_program, %{program_id: program_id}) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          case Bridge.call(:delete_program, %{program_id: program_id}) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Optional callbacks

  @impl true
  def get_program_info(program_id) do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:get_program_info, %{program_id: program_id}) do
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
        else
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def health_check do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:ping, %{}) do
            {:ok, %{"status" => "ok"}} -> :ok
            {:ok, %{status: "ok"}} -> :ok
            {:error, reason} -> {:error, reason}
            _ -> {:error, :unhealthy}
          end
        else
          case Bridge.call(:ping, %{}) do
            {:ok, %{"status" => "ok"}} -> :ok
            {:ok, %{status: "ok"}} -> :ok
            {:error, reason} -> {:error, reason}
            _ -> {:error, :unhealthy}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_stats do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:get_stats, %{}) do
            {:ok, bridge_stats} ->
              # Enhance bridge stats with adapter-specific information
              adapter_stats =
                Map.merge(bridge_stats, %{
                  adapter_type: :python_port,
                  layer: :layer_3,
                  python_execution: true,
                  pooling_enabled: true
                })

              {:ok, adapter_stats}

            {:error, reason} ->
              {:error, reason}
          end
        else
          case Bridge.call(:get_stats, %{}) do
            {:ok, bridge_stats} ->
              # Enhance bridge stats with adapter-specific information
              adapter_stats =
                Map.merge(bridge_stats, %{
                  adapter_type: :python_port,
                  layer: :layer_3,
                  python_execution: true,
                  pooling_enabled: false
                })

              {:ok, adapter_stats}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def configure_lm(config) do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Use SessionPool for pooled mode
          case SessionPoolV2.execute_anonymous(:configure_lm, config) do
            {:ok, %{"status" => "configured"}} -> :ok
            {:ok, %{status: "configured"}} -> :ok
            {:error, reason} -> {:error, reason}
            _ -> {:error, :configuration_failed}
          end
        else
          case Bridge.call(:configure_lm, config) do
            {:ok, %{"status" => "configured"}} -> :ok
            {:ok, %{status: "configured"}} -> :ok
            {:error, reason} -> {:error, reason}
            other -> 
              Logger.debug("configure_lm unexpected response: #{inspect(other)}")
              {:error, :configuration_failed}
          end
        end

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
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Get pool status instead
          SessionPoolV2.get_pool_status()
        else
          Bridge.get_status()
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restarts the Python bridge process.

  Useful for recovering from errors or applying configuration changes.
  """
  def restart_bridge do
    case ensure_bridge_started() do
      :ok ->
        if Process.get(:use_pool_mode, false) do
          # Cannot restart pool from here
          {:error, "Cannot restart pool - use pool supervisor"}
        else
          Bridge.restart()
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp ensure_bridge_started do
    # Use Process.whereis first (more reliable than Registry)
    pool_pid = Process.whereis(DSPex.PythonBridge.SessionPoolV2)
    bridge_pid = Process.whereis(DSPex.PythonBridge.Bridge)
    
    cond do
      # If pool is running, use it regardless of configuration
      pool_pid != nil and Process.alive?(pool_pid) ->
        Process.put(:use_pool_mode, true)
        Logger.debug("Using Python session pool: #{inspect(pool_pid)}")
        :ok
        
      # If bridge is running, use it
      bridge_pid != nil and Process.alive?(bridge_pid) ->
        Process.put(:use_pool_mode, false)
        Logger.debug("Using Python bridge: #{inspect(bridge_pid)}")
        :ok
        
      # No service available
      true ->
        Logger.error("No Python bridge or pool process found")
        {:error, "Python bridge not available"}
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

  defp convert_signature(signature) when is_atom(signature) do
    # Convert signature module to dictionary format
    case signature.__signature__() do
      %{inputs: inputs, outputs: outputs} ->
        %{
          "inputs" => convert_io_list(inputs),
          "outputs" => convert_io_list(outputs)
        }

      _ ->
        # Fallback to TypeConverter for complex signatures
        DSPex.Adapters.TypeConverter.convert_signature_to_format(signature, :python)
        |> convert_signature()
    end
  rescue
    _ ->
      # If signature module doesn't have __signature__/0, use TypeConverter
      DSPex.Adapters.TypeConverter.convert_signature_to_format(signature, :python)
      |> convert_signature()
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

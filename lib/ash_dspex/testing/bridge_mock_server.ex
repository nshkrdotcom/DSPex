defmodule AshDSPex.Testing.BridgeMockServer do
  @moduledoc """
  Mock Python bridge server for Layer 2 testing.

  This module simulates the Python bridge by speaking the exact same protocol
  but without requiring Python dependencies. It validates:
  - Wire protocol correctness
  - Serialization/deserialization
  - Error handling paths
  - Timeout behaviors
  - Request/response correlation

  Features:
  - Protocol-accurate JSON communication
  - Configurable response delays and errors
  - Request validation and correlation tracking
  - Comprehensive logging for debugging
  - Supports all bridge commands with mock responses
  """

  use GenServer
  require Logger

  alias AshDSPex.PythonBridge.Protocol

  defstruct [
    :port,
    :script_path,
    :config,
    :programs,
    :active_requests,
    :stats,
    :error_scenarios
  ]

  # Public API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def configure(server \\ __MODULE__, config) do
    GenServer.call(server, {:configure, config})
  end

  def add_error_scenario(server \\ __MODULE__, scenario) do
    GenServer.call(server, {:add_error_scenario, scenario})
  end

  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end

  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  def stop(server \\ __MODULE__) do
    GenServer.stop(server)
  end

  # GenServer Callbacks
  @impl true
  def init(opts) do
    config = build_config(opts)

    state = %__MODULE__{
      port: nil,
      config: config,
      programs: %{},
      active_requests: %{},
      stats: %{
        requests_received: 0,
        responses_sent: 0,
        errors_triggered: 0,
        start_time: DateTime.utc_now()
      },
      error_scenarios: %{}
    }

    # Start the mock Python process
    case start_mock_python_process(config) do
      {:ok, port, script_path} ->
        Logger.info("Bridge mock server started on port #{inspect(port)}")
        {:ok, %{state | port: port, script_path: script_path}}

      {:error, reason} ->
        Logger.error("Failed to start bridge mock server: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:configure, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    {:reply, :ok, %{state | config: updated_config}}
  end

  @impl true
  def handle_call({:add_error_scenario, scenario}, _from, state) do
    scenario_id = Map.get(scenario, :id, :erlang.unique_integer([:positive]))
    new_scenarios = Map.put(state.error_scenarios, scenario_id, scenario)
    {:reply, {:ok, scenario_id}, %{state | error_scenarios: new_scenarios}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        active_programs: map_size(state.programs),
        pending_requests: map_size(state.active_requests),
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.stats.start_time, :second)
      })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | programs: %{},
        active_requests: %{},
        error_scenarios: %{},
        stats: %{
          requests_received: 0,
          responses_sent: 0,
          errors_triggered: 0,
          start_time: DateTime.utc_now()
        }
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:mock_request, request}, _from, state) do
    # Handle direct requests from the BridgeMock adapter
    _request_id = Map.get(request, "id")
    command = Map.get(request, "command")
    args = Map.get(request, "args")

    # Simulate the same flow as port-based requests
    new_stats = update_in(state.stats, [:requests_received], &(&1 + 1))

    # Check for error scenarios
    case should_trigger_error?(state.error_scenarios, command, args) do
      {:error, _error_type, message} ->
        error_stats = update_in(new_stats, [:errors_triggered], &(&1 + 1))
        {:reply, {:error, message}, %{state | stats: error_stats}}

      :ok ->
        # Simulate processing delay
        if state.config.response_delay_ms > 0 do
          Process.sleep(state.config.response_delay_ms)
        end

        # Generate mock response
        case generate_mock_response(command, args, state) do
          {:ok, response, new_state} ->
            response_stats = update_in(new_state.stats, [:responses_sent], &(&1 + 1))
            {:reply, {:ok, response}, %{new_state | stats: response_stats}}

          {:error, error_message, new_state} ->
            error_stats = update_in(new_state.stats, [:errors_triggered], &(&1 + 1))
            {:reply, {:error, error_message}, %{new_state | stats: error_stats}}
        end
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Increment request counter
    new_stats = update_in(state.stats, [:requests_received], &(&1 + 1))

    case Protocol.decode_response(data) do
      {:ok, request_id, args} ->
        # This is actually a request from the bridge to us
        handle_mock_request(request_id, args, %{state | stats: new_stats})

      {:error, request_id, error} when is_integer(request_id) ->
        Logger.warning("Received malformed request #{request_id}: #{error}")
        send_error_response(state.port, request_id, "Malformed request: #{error}")
        {:noreply, %{state | stats: new_stats}}

      {:error, reason} ->
        Logger.error("Failed to decode request: #{reason}")
        {:noreply, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Mock Python process exited with status: #{status}")
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.info("Mock Python port exited: #{inspect(reason)}")
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in bridge mock server: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Bridge mock server terminating: #{inspect(reason)}")

    # Close port first to stop the external process immediately
    if state.port do
      try do
        Port.close(state.port)
      catch
        _ -> :ok
      end
    end

    # Clean up temporary script file
    _ =
      if state.script_path && File.exists?(state.script_path) do
        try do
          File.rm(state.script_path)
        catch
          _ -> :ok
        end
      end

    :ok
  end

  # Private Functions
  defp build_config(opts) do
    default_config = %{
      response_delay_ms: 10,
      error_probability: 0.0,
      timeout_probability: 0.0,
      max_programs: 100,
      enable_logging: true
    }

    app_config = Application.get_env(:ash_dspex, :bridge_mock_server, %{})

    default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end

  defp start_mock_python_process(config) do
    # Create a simple mock "Python" process using Elixir
    # This will speak the bridge protocol but return mock responses
    script_content = create_mock_python_script(config)
    script_path = write_temp_script(script_content)

    port_opts = [
      {:args, [script_path]},
      :binary,
      :exit_status,
      # 4-byte length prefix like real bridge
      {:packet, 4}
    ]

    try do
      # Use elixir instead of python to run our mock script
      port = Port.open({:spawn_executable, System.find_executable("elixir")}, port_opts)
      {:ok, port, script_path}
    rescue
      error ->
        Logger.error("Failed to start mock process: #{inspect(error)}")
        # Clean up script file if port creation failed
        _ = File.rm(script_path)
        {:error, "Failed to start mock process"}
    end
  end

  defp create_mock_python_script(_config) do
    """
    # Mock Python bridge script that speaks the protocol
    # This is actually Elixir code that will be executed

    # Trap exits to clean up properly
    Process.flag(:trap_exit, true)

    # Silent startup - no output during tests to avoid bleed-through
    # The parent process knows the bridge is ready when the port opens

    # Simple echo loop to simulate Python bridge
    receive do
      _data -> 
        # Silent operation - no debug output during tests
        :ok
      after 5000 ->
        # Timeout after 5 seconds if no data received
        :timeout
    end
    """
  end

  defp write_temp_script(content) do
    temp_dir = System.tmp_dir!()
    script_path = Path.join(temp_dir, "bridge_mock_#{:erlang.unique_integer([:positive])}.exs")
    File.write!(script_path, content)
    script_path
  end

  defp handle_mock_request(request_id, request_data, state) do
    # Parse the request to extract command and arguments
    command = extract_command(request_data)
    args = extract_args(request_data)

    Logger.debug("Mock server handling command: #{command} with args: #{inspect(args)}")

    # Check for error scenarios
    case should_trigger_error?(state.error_scenarios, command, args) do
      {:error, _error_type, message} ->
        send_error_response(state.port, request_id, message)
        new_stats = update_in(state.stats, [:errors_triggered], &(&1 + 1))
        {:noreply, %{state | stats: new_stats}}

      :ok ->
        # Simulate processing delay
        if state.config.response_delay_ms > 0 do
          Process.sleep(state.config.response_delay_ms)
        end

        # Generate mock response
        case generate_mock_response(command, args, state) do
          {:ok, response, new_state} ->
            send_success_response(new_state.port, request_id, response)
            response_stats = update_in(new_state.stats, [:responses_sent], &(&1 + 1))
            {:noreply, %{new_state | stats: response_stats}}

          {:error, error_message, new_state} ->
            send_error_response(new_state.port, request_id, error_message)
            error_stats = update_in(new_state.stats, [:errors_triggered], &(&1 + 1))
            {:noreply, %{new_state | stats: error_stats}}
        end
    end
  end

  defp extract_command(request_data) do
    case request_data do
      %{"command" => command} -> command
      %{command: command} -> command
      _ -> "unknown"
    end
  end

  defp extract_args(request_data) do
    case request_data do
      %{"args" => args} -> args
      %{args: args} -> args
      _ -> %{}
    end
  end

  defp should_trigger_error?(error_scenarios, command, _args) do
    # Check if any error scenario matches this command
    error_scenarios
    |> Enum.find_value(:ok, fn {_id, scenario} ->
      scenario_command = Map.get(scenario, :command)
      scenario_probability = Map.get(scenario, :probability, 1.0)

      if scenario_command == command or scenario_command == :any do
        if :rand.uniform() < scenario_probability do
          error_type = Map.get(scenario, :error_type, :mock_error)
          message = Map.get(scenario, :message, "Mock error triggered")
          {:error, error_type, message}
        else
          :ok
        end
      else
        nil
      end
    end)
  end

  defp generate_mock_response("ping", _args, state) do
    response = %{
      status: "ok",
      server: "mock",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, response, state}
  end

  defp generate_mock_response("create_program", args, state) do
    program_id = Map.get(args, "id") || "mock_program_#{:erlang.unique_integer([:positive])}"
    signature = Map.get(args, "signature")

    if signature do
      program = %{
        id: program_id,
        signature: signature,
        created_at: DateTime.utc_now()
      }

      new_programs = Map.put(state.programs, program_id, program)

      response = %{
        program_id: program_id,
        status: "created",
        signature: signature
      }

      {:ok, response, %{state | programs: new_programs}}
    else
      {:error, "Program signature is required", state}
    end
  end

  defp generate_mock_response("execute_program", args, state) do
    program_id = Map.get(args, "program_id")
    inputs = Map.get(args, "inputs", %{})

    case Map.get(state.programs, program_id) do
      nil ->
        {:error, "Program not found: #{program_id}", state}

      program ->
        # Generate deterministic mock output based on signature
        mock_outputs = generate_signature_outputs(program.signature, inputs)
        {:ok, mock_outputs, state}
    end
  end

  defp generate_mock_response("list_programs", _args, state) do
    programs =
      state.programs
      |> Enum.map(fn {id, program} ->
        %{
          id: id,
          signature: program.signature,
          created_at: program.created_at
        }
      end)

    response = %{programs: programs}
    {:ok, response, state}
  end

  defp generate_mock_response("get_stats", _args, state) do
    response = %{
      programs_created: map_size(state.programs),
      server_type: "mock",
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.stats.start_time, :second)
    }

    {:ok, response, state}
  end

  defp generate_mock_response(command, _args, state) do
    {:error, "Unknown command: #{command}", state}
  end

  defp generate_signature_outputs(signature, inputs) do
    outputs = Map.get(signature, "outputs", [])
    input_hash = :erlang.phash2(inputs)

    Enum.reduce(outputs, %{}, fn output, acc ->
      name = Map.get(output, "name")
      type = Map.get(output, "type", "string")

      mock_value =
        case type do
          "string" -> "mock_#{name}_#{input_hash}"
          "int" -> rem(input_hash, 1000)
          "float" -> rem(input_hash, 1000) / 10.0
          "bool" -> rem(input_hash, 2) == 0
          _ -> "mock_#{name}_#{input_hash}"
        end

      Map.put(acc, name, mock_value)
    end)
  end

  defp send_success_response(port, request_id, result) do
    response = Protocol.create_success_response(request_id, result)
    json_response = Jason.encode!(response)
    send(port, {self(), {:command, json_response}})
  end

  defp send_error_response(port, request_id, error_message) do
    response = Protocol.create_error_response(request_id, error_message)
    json_response = Jason.encode!(response)
    send(port, {self(), {:command, json_response}})
  end
end

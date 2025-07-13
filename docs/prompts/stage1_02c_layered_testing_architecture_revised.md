● Stage 1 Prompt 2c: Layered Testing Architecture

  OBJECTIVE

  Implement a comprehensive 3-layer testing architecture that enables fast unit testing, thorough integration testing, and complete end-to-end validation while maintaining
  development speed and test reliability. This testing infrastructure must support the current Python bridge development, future Elixir native DSPy port, and provide deterministic
  testing capabilities across all system components.

  COMPLETE IMPLEMENTATION CONTEXT

  LAYERED TESTING ARCHITECTURE OVERVIEW

  From stage1_02_python_bridge.md and future system requirements:

  Testing Architecture Philosophy:
  - Layer 1: Pure Elixir mock for fast unit testing (milliseconds per test)
  - Layer 2: Bridge protocol testing with mock Python server (hundreds of milliseconds)
  - Layer 3: Full stack testing with real Python DSPy (seconds per test)
  - Configurable test modes for different development needs
  - Future-ready for Elixir native DSPy port integration

  Architecture Diagram:
  ┌─────────────────────────────────────────────────────────────┐
  │                 Testing Architecture                        │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
  │  │ Layer 1         │  │ Layer 2         │  │ Layer 3      ││
  │  │ Mock Adapter    │  │ Bridge Mock     │  │ Full E2E     ││
  │  │ - Pure Elixir   │  │ - Wire protocol │  │ - Real Python││
  │  │ - No bridge     │  │ - Serialization │  │ - Complete   ││
  │  │ - Milliseconds  │  │ - Error handling│  │ - Seconds    ││
  │  └─────────────────┘  └─────────────────┘  └──────────────┘│
  │                                                             │
  │  99% Unit Tests         Critical Path         Smoke Tests   │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘

  INTEGRATION WITH CURRENT PYTHON BRIDGE

  From stage1_02_python_bridge.md implementation:

  Bridge Integration Points:
  - Mock adapter bypasses bridge entirely for pure Ash logic testing
  - Bridge mock server validates wire protocol without Python dependencies
  - Test mode configuration integrates with existing bridge GenServer
  - Seamless switching between test modes via configuration
  - Preserves all existing bridge functionality while adding test capabilities

  LAYER 1: ADAPTER-LEVEL MOCK IMPLEMENTATION

  1.1 Core Mock Adapter

  defmodule DSPex.Adapters.Mock do
    @moduledoc """
    Pure Elixir mock adapter for fast unit testing without bridge dependencies.

    Features:
    - Complete adapter behavior implementation
    - Deterministic response generation based on signature types
    - Configurable scenarios for edge case testing
    - Performance simulation with configurable delays
    - Error injection for resilience testing
    - State management for complex workflow testing
    - Thread-safe concurrent operation support
    """

    @behaviour DSPex.Adapters.Adapter
    use GenServer

    require Logger

    defstruct [
      :programs,           # Map of program_id -> program_state
      :executions,         # Map of execution_id -> execution_result
      :scenarios,          # Configured test scenarios
      :config,             # Mock configuration
      :stats,              # Operation statistics
      :error_injection     # Error injection rules
    ]

    # Public API
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def reset do
      GenServer.call(__MODULE__, :reset)
    end

    def configure(config) do
      GenServer.call(__MODULE__, {:configure, config})
    end

    def set_scenario(scenario_name, scenario_config) do
      GenServer.call(__MODULE__, {:set_scenario, scenario_name, scenario_config})
    end

    def inject_error(error_config) do
      GenServer.call(__MODULE__, {:inject_error, error_config})
    end

    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end

    # Adapter Behavior Implementation
    @impl true
    def create_program(config) do
      GenServer.call(__MODULE__, {:create_program, config}, 10_000)
    end

    @impl true
    def execute_program(program_id, inputs) do
      GenServer.call(__MODULE__, {:execute_program, program_id, inputs}, 30_000)
    end

    @impl true
    def optimize_program(program_id, dataset, config) do
      GenServer.call(__MODULE__, {:optimize_program, program_id, dataset, config}, 60_000)
    end

    @impl true
    def list_programs do
      GenServer.call(__MODULE__, :list_programs, 5_000)
    end

    @impl true
    def health_check do
      GenServer.call(__MODULE__, :health_check, 5_000)
    end

    @impl true
    def get_program_info(program_id) do
      GenServer.call(__MODULE__, {:get_program_info, program_id}, 5_000)
    end

    # GenServer Implementation
    @impl true
    def init(opts) do
      config = build_default_config(opts)

      state = %__MODULE__{
        programs: %{},
        executions: %{},
        scenarios: %{},
        config: config,
        stats: initialize_stats(),
        error_injection: %{}
      }

      Logger.info("Mock adapter started with config: #{inspect(config)}")
      {:ok, state}
    end

    @impl true
    def handle_call(:reset, _from, state) do
      new_state = %{state |
        programs: %{},
        executions: %{},
        scenarios: %{},
        error_injection: %{},
        stats: initialize_stats()
      }

      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:configure, config}, _from, state) do
      new_config = Map.merge(state.config, config)
      new_state = %{state | config: new_config}
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:create_program, config}, _from, state) do
      case check_error_injection(:create_program, state) do
        {:error, error} ->
          {:reply, {:error, error}, update_stats(state, :create_program, :error)}

        :continue ->
          handle_create_program(config, state)
      end
    end

    @impl true
    def handle_call({:execute_program, program_id, inputs}, _from, state) do
      case check_error_injection(:execute_program, state) do
        {:error, error} ->
          {:reply, {:error, error}, update_stats(state, :execute_program, :error)}

        :continue ->
          handle_execute_program(program_id, inputs, state)
      end
    end

    # Program Management Handlers
    defp handle_create_program(config, state) do
      simulate_delay(:create_program, state.config)

      program_id = generate_program_id(config)

      case validate_program_config(config) do
        {:ok, validated_config} ->
          program_state = %{
            id: program_id,
            config: validated_config,
            status: :ready,
            created_at: DateTime.utc_now(),
            execution_count: 0,
            last_executed_at: nil
          }

          new_programs = Map.put(state.programs, program_id, program_state)
          new_state = %{state | programs: new_programs}
          |> update_stats(:create_program, :success)

          {:reply, {:ok, program_id}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, update_stats(state, :create_program, :validation_error)}
      end
    end

    defp handle_execute_program(program_id, inputs, state) do
      simulate_delay(:execute_program, state.config)

      case Map.get(state.programs, program_id) do
        nil ->
          {:reply, {:error, "Program not found: #{program_id}"},
           update_stats(state, :execute_program, :not_found)}

        program_state ->
          case validate_execution_inputs(program_state, inputs) do
            {:ok, validated_inputs} ->
              # Generate realistic outputs based on signature
              outputs = generate_program_outputs(program_state, validated_inputs, state.config)

              execution_id = generate_execution_id()
              execution_result = %{
                id: execution_id,
                program_id: program_id,
                inputs: validated_inputs,
                outputs: outputs,
                duration_ms: calculate_execution_duration(state.config),
                executed_at: DateTime.utc_now(),
                status: :completed
              }

              # Update program state
              updated_program = program_state
              |> Map.put(:execution_count, program_state.execution_count + 1)
              |> Map.put(:last_executed_at, DateTime.utc_now())

              new_programs = Map.put(state.programs, program_id, updated_program)
              new_executions = Map.put(state.executions, execution_id, execution_result)

              new_state = %{state |
                programs: new_programs,
                executions: new_executions
              } |> update_stats(:execute_program, :success)

              {:reply, {:ok, outputs}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, update_stats(state, :execute_program, :validation_error)}
          end
      end
    end

    # Response Generation Functions
    defp generate_program_outputs(program_state, inputs, config) do
      signature = program_state.config.signature

      case get_scenario_response(:execute_program, program_state.id, config) do
        {:ok, scenario_response} ->
          scenario_response

        :no_scenario ->
          generate_realistic_outputs(signature, inputs, config)
      end
    end

    defp generate_realistic_outputs(signature, inputs, config) do
      output_fields = case signature do
        %{outputs: outputs} when is_list(outputs) ->
          outputs
        _ ->
          [{:answer, :string, []}]  # Default output
      end

      Enum.reduce(output_fields, %{}, fn {name, type, _constraints}, acc ->
        value = generate_value_for_type(type, inputs, name, config)
        Map.put(acc, name, value)
      end)
    end

    defp generate_value_for_type(:string, inputs, field_name, config) do
      case field_name do
        :answer ->
          question = get_input_value(inputs, [:question, :query, :input], "unknown question")
          generate_answer_for_question(question, config)

        :summary ->
          text = get_input_value(inputs, [:text, :content, :input], "sample text")
          "Mock summary of: #{String.slice(text, 0, 50)}..."

        _ ->
          "Mock #{field_name} response"
      end
    end

    defp generate_value_for_type(:float, _inputs, field_name, _config) do
      case field_name do
        :confidence -> 0.75 + (:rand.uniform() * 0.24)  # 0.75-0.99
        :probability -> :rand.uniform()
        :score -> 0.6 + (:rand.uniform() * 0.4)
        _ -> :rand.uniform() * 100
      end
    end

    defp generate_value_for_type(:integer, _inputs, _field_name, _config) do
      :rand.uniform(1000)
    end

    defp generate_value_for_type(:boolean, _inputs, _field_name, _config) do
      :rand.uniform() > 0.5
    end

    defp generate_value_for_type({:list, inner_type}, inputs, field_name, config) do
      list_size = :rand.uniform(5) + 1
      Enum.map(1..list_size, fn _i ->
        generate_value_for_type(inner_type, inputs, field_name, config)
      end)
    end

    defp generate_value_for_type(_type, _inputs, field_name, _config) do
      "Mock #{field_name} value"
    end

    defp generate_answer_for_question(question, config) do
      responses = config[:predefined_responses] || %{}

      case Map.get(responses, question) do
        nil ->
          cond do
            String.contains?(String.downcase(question), ["what", "define"]) ->
              "Mock definition response for: #{question}"

            String.contains?(String.downcase(question), ["how", "explain"]) ->
              "Mock explanation response for: #{question}"

            true ->
              "Mock response to: #{question}"
          end

        predefined_response ->
          predefined_response
      end
    end

    # Utility Functions
    defp build_default_config(opts) do
      default_config = %{
        base_latency_ms: 1,           # Fast for unit tests
        latency_variance_ms: 0,       # Deterministic
        enable_scenarios: true,
        enable_error_injection: true,
        predefined_responses: %{},
        realistic_delays: false       # Disabled for unit tests
      }

      Enum.reduce(opts, default_config, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
    end

    defp initialize_stats do
      %{
        create_program: %{success: 0, error: 0, validation_error: 0, not_found: 0},
        execute_program: %{success: 0, error: 0, validation_error: 0, not_found: 0},
        optimize_program: %{success: 0, error: 0, validation_error: 0, not_found: 0},
        list_programs: %{success: 0, error: 0},
        health_check: %{success: 0, error: 0},
        total_operations: 0,
        started_at: DateTime.utc_now()
      }
    end

    defp update_stats(state, operation, outcome) do
      current_op_stats = Map.get(state.stats, operation, %{})
      current_count = Map.get(current_op_stats, outcome, 0)

      updated_op_stats = Map.put(current_op_stats, outcome, current_count + 1)
      updated_stats = Map.put(state.stats, operation, updated_op_stats)
      |> Map.put(:total_operations, state.stats.total_operations + 1)

      %{state | stats: updated_stats}
    end

    defp validate_program_config(config) do
      required_fields = [:id, :signature]

      case check_required_fields(config, required_fields) do
        :ok -> {:ok, config}
        {:error, missing_fields} ->
          {:error, "Missing required fields: #{inspect(missing_fields)}"}
      end
    end

    defp validate_execution_inputs(program_state, inputs) do
      signature = program_state.config.signature

      expected_inputs = case signature do
        %{inputs: input_fields} when is_list(input_fields) ->
          Enum.map(input_fields, fn {name, _type, _constraints} -> name end)
        _ -> []
      end

      case validate_input_fields(inputs, expected_inputs) do
        :ok -> {:ok, inputs}
        {:error, reason} -> {:error, reason}
      end
    end

    defp check_required_fields(map, required_fields) do
      missing_fields = required_fields
      |> Enum.filter(fn field -> not Map.has_key?(map, field) end)

      case missing_fields do
        [] -> :ok
        missing -> {:error, missing}
      end
    end

    defp validate_input_fields(inputs, expected_inputs) when is_map(inputs) do
      provided_inputs = Map.keys(inputs)
      missing_inputs = expected_inputs -- provided_inputs

      case missing_inputs do
        [] -> :ok
        missing -> {:error, "Missing required inputs: #{inspect(missing)}"}
      end
    end

    defp validate_input_fields(_, _), do: {:error, "Inputs must be a map"}

    defp get_input_value(inputs, possible_keys, default) do
      possible_keys
      |> Enum.find_value(default, fn key ->
        Map.get(inputs, key) || Map.get(inputs, to_string(key))
      end)
    end

    defp simulate_delay(operation, config) do
      if config.realistic_delays do
        base_latency = case operation do
          :create_program -> config.base_latency_ms * 2
          :execute_program -> config.base_latency_ms
          _ -> config.base_latency_ms
        end

        variance = :rand.uniform(config.latency_variance_ms * 2) - config.latency_variance_ms
        delay = max(base_latency + variance, 1)

        Process.sleep(round(delay))
      end
    end

    defp calculate_execution_duration(config) do
      base = config.base_latency_ms
      variance = :rand.uniform(config.latency_variance_ms * 2) - config.latency_variance_ms
      max(base + variance, 1)
    end

    defp check_error_injection(operation, state) do
      if state.config.enable_error_injection do
        matching_errors = state.error_injection
        |> Enum.filter(fn {_id, error_config} ->
          error_config.operation == operation and should_trigger_error?(error_config)
        end)

        case matching_errors do
          [] -> :continue
          [{_id, error_config} | _] -> {:error, error_config.error}
        end
      else
        :continue
      end
    end

    defp should_trigger_error?(error_config) do
      probability = Map.get(error_config, :probability, 1.0)
      :rand.uniform() <= probability
    end

    defp get_scenario_response(_operation, _program_id, _config) do
      # Scenario system implementation
      :no_scenario
    end

    defp generate_program_id(config) do
      case config do
        %{id: id} when is_binary(id) -> id
        %{id: id} -> to_string(id)
        _ -> "mock_program_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
      end
    end

    defp generate_execution_id do
      "mock_exec_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
    end
  end

  LAYER 2: BRIDGE MOCK SERVER IMPLEMENTATION

  2.1 Mock Python Server

  defmodule DSPex.PythonBridge.MockServer do
    @moduledoc """
    Mock Python server that implements the bridge wire protocol for testing
    bridge communication without requiring Python DSPy installation.

    Features:
    - Full wire protocol implementation
    - Realistic request/response handling
    - Configurable response scenarios
    - Error injection for connection testing
    - Performance simulation with delays
    - Request logging and debugging support
    """

    use GenServer
    require Logger

    defstruct [
      :port,
      :listen_socket,
      :clients,
      :config,
      :request_handlers,
      :stats
    ]

    # Public API
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def stop do
      GenServer.stop(__MODULE__)
    end

    def configure(config) do
      GenServer.call(__MODULE__, {:configure, config})
    end

    def set_response_scenario(command, scenario) do
      GenServer.call(__MODULE__, {:set_response_scenario, command, scenario})
    end

    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end

    def reset_stats do
      GenServer.call(__MODULE__, :reset_stats)
    end

    # GenServer Implementation
    @impl true
    def init(opts) do
      port = Keyword.get(opts, :port, find_free_port())
      config = build_default_server_config(opts)

      case start_tcp_server(port) do
        {:ok, listen_socket} ->
          # Start accepting connections
          spawn_link(fn -> accept_connections(listen_socket) end)

          state = %__MODULE__{
            port: port,
            listen_socket: listen_socket,
            clients: %{},
            config: config,
            request_handlers: build_default_handlers(),
            stats: initialize_server_stats()
          }

          Logger.info("Mock Python server started on port #{port}")
          {:ok, state}

        {:error, reason} ->
          Logger.error("Failed to start mock Python server: #{reason}")
          {:stop, reason}
      end
    end

    @impl true
    def handle_call({:configure, config}, _from, state) do
      new_config = Map.merge(state.config, config)
      new_state = %{state | config: new_config}
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:set_response_scenario, command, scenario}, _from, state) do
      new_handlers = Map.put(state.request_handlers, command, scenario)
      new_state = %{state | request_handlers: new_handlers}
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call(:get_stats, _from, state) do
      {:reply, {:ok, state.stats}, state}
    end

    @impl true
    def handle_call(:reset_stats, _from, state) do
      new_state = %{state | stats: initialize_server_stats()}
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_info({:tcp, socket, data}, state) do
      handle_client_request(socket, data, state)
      {:noreply, state}
    end

    @impl true
    def handle_info({:tcp_closed, socket}, state) do
      Logger.debug("Client disconnected: #{inspect(socket)}")
      new_clients = Map.delete(state.clients, socket)
      new_state = %{state | clients: new_clients}
      {:noreply, new_state}
    end

    @impl true
    def handle_info({:tcp_error, socket, reason}, state) do
      Logger.warning("TCP error on socket #{inspect(socket)}: #{reason}")
      new_clients = Map.delete(state.clients, socket)
      new_state = %{state | clients: new_clients}
      {:noreply, new_state}
    end

    # TCP Server Functions
    defp start_tcp_server(port) do
      :gen_tcp.listen(port, [
        :binary,
        packet: 4,          # Same packet format as bridge
        active: true,       # Receive messages as info
        reuseaddr: true,
        nodelay: true
      ])
    end

    defp accept_connections(listen_socket) do
      case :gen_tcp.accept(listen_socket) do
        {:ok, client_socket} ->
          Logger.debug("New client connected: #{inspect(client_socket)}")

          # Continue accepting more connections
          spawn(fn -> accept_connections(listen_socket) end)

          # Handle this client
          :inet.setopts(client_socket, active: true)

          # Register client with main process
          GenServer.cast(__MODULE__, {:client_connected, client_socket})

          # Keep this process alive to maintain the connection
          receive do
            {:tcp_closed, ^client_socket} -> :ok
            {:tcp_error, ^client_socket, _reason} -> :ok
          end

        {:error, reason} ->
          Logger.error("Failed to accept connection: #{reason}")
      end
    end

    @impl true
    def handle_cast({:client_connected, socket}, state) do
      new_clients = Map.put(state.clients, socket, %{
        connected_at: DateTime.utc_now(),
        requests_handled: 0
      })

      new_state = %{state | clients: new_clients}
      {:noreply, new_state}
    end

    # Request Handling
    defp handle_client_request(socket, data, state) do
      start_time = System.monotonic_time(:millisecond)

      case decode_bridge_request(data) do
        {:ok, request} ->
          response = process_bridge_request(request, state)
          send_response(socket, response)

          duration = System.monotonic_time(:millisecond) - start_time
          update_request_stats(state, request["command"], :success, duration)

        {:error, reason} ->
          Logger.warning("Failed to decode request: #{reason}")
          error_response = build_error_response(nil, "Invalid request format")
          send_response(socket, error_response)

          duration = System.monotonic_time(:millisecond) - start_time
          update_request_stats(state, "unknown", :decode_error, duration)
      end
    end

    defp decode_bridge_request(data) do
      case Jason.decode(data) do
        {:ok, %{"id" => _id, "command" => _command, "args" => _args} = request} ->
          {:ok, request}

        {:ok, invalid_request} ->
          {:error, "Missing required fields: #{inspect(Map.keys(invalid_request))}"}

        {:error, reason} ->
          {:error, "JSON decode error: #{reason}"}
      end
    end

    defp process_bridge_request(request, state) do
      %{"id" => request_id, "command" => command, "args" => args} = request

      # Simulate processing delay if configured
      if state.config.simulate_delays do
        delay = calculate_processing_delay(command, state.config)
        Process.sleep(delay)
      end

      # Check for error injection
      case check_server_error_injection(command, state) do
        {:error, error_message} ->
          build_error_response(request_id, error_message)

        :continue ->
          # Process the command
          case execute_mock_command(command, args, state) do
            {:ok, result} ->
              build_success_response(request_id, result)

            {:error, reason} ->
              build_error_response(request_id, reason)
          end
      end
    end

    defp execute_mock_command("create_program", args, state) do
      program_id = Map.get(args, "id", generate_mock_program_id())

      # Validate program configuration
      case validate_mock_program_config(args) do
        :ok ->
          result = %{
            "program_id" => program_id,
            "status" => "created",
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }

          {:ok, result}

        {:error, reason} ->
          {:error, "Program creation failed: #{reason}"}
      end
    end

    defp execute_mock_command("execute_program", args, state) do
      program_id = Map.get(args, "program_id")
      inputs = Map.get(args, "inputs", %{})

      if program_id do
        # Generate mock execution result
        outputs = generate_mock_execution_outputs(inputs, state)

        result = %{
          "outputs" => outputs,
          "execution_time_ms" => :rand.uniform(500) + 100,
          "metadata" => %{
            "program_id" => program_id,
            "mock" => true,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }

        {:ok, result}
      else
        {:error, "Missing program_id"}
      end
    end

    defp execute_mock_command("optimize_program", args, state) do
      program_id = Map.get(args, "program_id")
      dataset = Map.get(args, "dataset", [])
      config = Map.get(args, "config", %{})

      if program_id do
        # Simulate optimization
        base_score = 0.7
        improvement = :rand.uniform() * 0.3
        final_score = min(base_score + improvement, 0.99)

        result = %{
          "program_id" => program_id,
          "score" => final_score,
          "improvement" => improvement,
          "optimizer" => Map.get(config, "optimizer", "BootstrapFewShot"),
          "dataset_size" => length(dataset),
          "optimization_time_ms" => :rand.uniform(5000) + 2000,
          "metadata" => %{
            "mock" => true,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }

        {:ok, result}
      else
        {:error, "Missing program_id"}
      end
    end

    defp execute_mock_command("list_programs", _args, _state) do
      # Return mock program list
      programs = [
        %{
          "id" => "mock_program_1",
          "status" => "ready",
          "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        %{
          "id" => "mock_program_2",
          "status" => "ready",
          "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      {:ok, %{"programs" => programs}}
    end

    defp execute_mock_command("ping", _args, _state) do
      {:ok, %{"status" => "ok", "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()}}
    end

    defp execute_mock_command(unknown_command, _args, _state) do
      {:error, "Unknown command: #{unknown_command}"}
    end

    # Response Building
    defp build_success_response(request_id, result) do
      %{
        "id" => request_id,
        "success" => true,
        "result" => result
      }
      |> Jason.encode!()
    end

    defp build_error_response(request_id, error_message) do
      %{
        "id" => request_id,
        "success" => false,
        "error" => error_message
      }
      |> Jason.encode!()
    end

    defp send_response(socket, response) do
      case :gen_tcp.send(socket, response) do
        :ok ->
          Logger.debug("Sent response: #{String.slice(response, 0, 100)}...")

        {:error, reason} ->
          Logger.warning("Failed to send response: #{reason}")
      end
    end

    # Mock Data Generation
    defp generate_mock_execution_outputs(inputs, state) do
      # Generate contextual responses based on inputs
      question = get_question_from_inputs(inputs)

      case Map.get(state.config, :predefined_responses, %{}) do
        responses when map_size(responses) > 0 ->
          Map.get(responses, question, generate_default_response(question))

        _ ->
          generate_default_response(question)
      end
    end

    defp get_question_from_inputs(inputs) when is_map(inputs) do
      inputs
      |> Map.get("question", Map.get(inputs, "query", Map.get(inputs, "input", "default question")))
    end

    defp get_question_from_inputs(_), do: "default question"

    defp generate_default_response(question) do
      %{
        "answer" => "Mock response to: #{question}",
        "confidence" => 0.85 + (:rand.uniform() * 0.14)
      }
    end

    # Configuration and Utilities
    defp build_default_server_config(opts) do
      default_config = %{
        simulate_delays: true,
        base_delay_ms: 100,
        delay_variance_ms: 50,
        error_injection_enabled: false,
        predefined_responses: %{},
        log_requests: true
      }

      Enum.reduce(opts, default_config, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)
    end

    defp build_default_handlers do
      %{
        "create_program" => :default,
        "execute_program" => :default,
        "optimize_program" => :default,
        "list_programs" => :default,
        "ping" => :default
      }
    end

    defp initialize_server_stats do
      %{
        requests_total: 0,
        requests_by_command: %{},
        errors_total: 0,
        uptime_started: DateTime.utc_now(),
        clients_connected: 0
      }
    end

    defp calculate_processing_delay(command, config) do
      base_delay = case command do
        "create_program" -> config.base_delay_ms * 2
        "execute_program" -> config.base_delay_ms
        "optimize_program" -> config.base_delay_ms * 10
        _ -> config.base_delay_ms
      end

      variance = :rand.uniform(config.delay_variance_ms * 2) - config.delay_variance_ms
      max(base_delay + variance, 10)
    end

    defp check_server_error_injection(_command, state) do
      if state.config.error_injection_enabled do
        # Implementation for error injection
        :continue
      else
        :continue
      end
    end

    defp validate_mock_program_config(args) do
      required_fields = ["signature"]

      missing_fields = Enum.filter(required_fields, fn field ->
        not Map.has_key?(args, field)
      end)

      case missing_fields do
        [] -> :ok
        missing -> {:error, "Missing required fields: #{inspect(missing)}"}
      end
    end

    defp generate_mock_program_id do
      "mock_bridge_program_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
    end

    defp find_free_port do
      {:ok, socket} = :gen_tcp.listen(0, [])
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)
      port
    end

    defp update_request_stats(state, command, outcome, duration) do
      # Update statistics (async to avoid blocking request handling)
      GenServer.cast(__MODULE__, {:update_stats, command, outcome, duration})
    end

    @impl true
    def handle_cast({:update_stats, command, outcome, duration}, state) do
      new_stats = state.stats
      |> Map.put(:requests_total, state.stats.requests_total + 1)
      |> update_command_stats(command, outcome, duration)

      new_state = %{state | stats: new_stats}
      {:noreply, new_state}
    end

    defp update_command_stats(stats, command, outcome, duration) do
      command_stats = Map.get(stats.requests_by_command, command, %{
        total: 0,
        success: 0,
        error: 0,
        avg_duration_ms: 0
      })

      new_command_stats = command_stats
      |> Map.put(:total, command_stats.total + 1)
      |> Map.put(outcome, Map.get(command_stats, outcome, 0) + 1)
      |> Map.put(:avg_duration_ms,
           (command_stats.avg_duration_ms * (command_stats.total - 1) + duration) / command_stats.total)

      Map.put(stats, :requests_by_command,
        Map.put(stats.requests_by_command, command, new_command_stats))
    end
  end

  LAYER 3: TEST CONFIGURATION SYSTEM

  3.1 Test Mode Manager

  defmodule DSPex.Testing.ModeManager do
    @moduledoc """
    Manages different testing modes and configurations for the layered testing architecture.

    Test Modes:
    - :unit_mock - Pure mock adapter, no bridge communication (fastest)
    - :integration_mock - Bridge with mock Python server (medium speed)
    - :e2e_real - Full stack with real Python DSPy (slowest, most comprehensive)
    """

    @test_modes [:unit_mock, :integration_mock, :e2e_real]

    def setup_test_mode(mode) when mode in @test_modes do
      case mode do
        :unit_mock -> setup_unit_mock_mode()
        :integration_mock -> setup_integration_mock_mode()
        :e2e_real -> setup_e2e_real_mode()
      end
    end

    def setup_test_mode(invalid_mode) do
      {:error, "Invalid test mode: #{invalid_mode}. Valid modes: #{inspect(@test_modes)}"}
    end

    def get_current_mode do
      Application.get_env(:dspex, :test_mode, :unit_mock)
    end

    def teardown_test_mode do
      current_mode = get_current_mode()

      case current_mode do
        :unit_mock -> teardown_unit_mock_mode()
        :integration_mock -> teardown_integration_mock_mode()
        :e2e_real -> teardown_e2e_real_mode()
      end
    end

    # Unit Mock Mode Setup
    defp setup_unit_mock_mode do
      # Configure to use mock adapter directly
      Application.put_env(:dspex, :adapter, DSPex.Adapters.Mock)
      Application.put_env(:dspex, :test_mode, :unit_mock)

      # Start mock adapter with unit test configuration
      case DSPex.Adapters.Mock.start_link(unit_test_config()) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          DSPex.Adapters.Mock.reset()
          DSPex.Adapters.Mock.configure(unit_test_config())
          :ok

        {:error, reason} ->
          {:error, "Failed to start mock adapter: #{reason}"}
      end
    end

    # Integration Mock Mode Setup
    defp setup_integration_mock_mode do
      Application.put_env(:dspex, :adapter, DSPex.Adapters.PythonPort)
      Application.put_env(:dspex, :bridge_mode, :mock_server)
      Application.put_env(:dspex, :test_mode, :integration_mock)

      # Start mock Python server
      case DSPex.PythonBridge.MockServer.start_link(integration_test_config()) do
        {:ok, _pid} ->
          # Start bridge configured to use mock server
          case start_bridge_with_mock_server() do
            {:ok, _bridge_pid} -> :ok
            {:error, reason} -> {:error, "Failed to start bridge: #{reason}"}
          end

        {:error, {:already_started, _pid}} ->
          DSPex.PythonBridge.MockServer.configure(integration_test_config())
          :ok

        {:error, reason} ->
          {:error, "Failed to start mock server: #{reason}"}
      end
    end

    # E2E Real Mode Setup
    defp setup_e2e_real_mode do
      Application.put_env(:dspex, :adapter, DSPex.Adapters.PythonPort)
      Application.put_env(:dspex, :bridge_mode, :production)
      Application.put_env(:dspex, :test_mode, :e2e_real)

      # Verify Python DSPy is available
      case verify_python_dspy_available() do
        :ok ->
          # Start bridge with real Python process
          case DSPex.PythonBridge.Bridge.start_link(production_config()) do
            {:ok, _pid} -> :ok
            {:error, {:already_started, _pid}} -> :ok
            {:error, reason} -> {:error, "Failed to start bridge: #{reason}"}
          end

        {:error, reason} ->
          {:error, "Python DSPy not available: #{reason}"}
      end
    end

    # Teardown Functions
    defp teardown_unit_mock_mode do
      case Process.whereis(DSPex.Adapters.Mock) do
        nil -> :ok
        _pid ->
          DSPex.Adapters.Mock.reset()
          :ok
      end
    end

    defp teardown_integration_mock_mode do
      case Process.whereis(DSPex.PythonBridge.MockServer) do
        nil -> :ok
        _pid ->
          DSPex.PythonBridge.MockServer.stop()
          :ok
      end

      case Process.whereis(DSPex.PythonBridge.Bridge) do
        nil -> :ok
        _pid ->
          GenServer.stop(DSPex.PythonBridge.Bridge)
          :ok
      end
    end

    defp teardown_e2e_real_mode do
      case Process.whereis(DSPex.PythonBridge.Bridge) do
        nil -> :ok
        _pid ->
          GenServer.stop(DSPex.PythonBridge.Bridge)
          :ok
      end
    end

    # Configuration Functions
    defp unit_test_config do
      %{
        realistic_delays: false,
        base_latency_ms: 1,
        latency_variance_ms: 0,
        enable_error_injection: true,
        predefined_responses: default_test_responses()
      }
    end

    defp integration_test_config do
      %{
        simulate_delays: false,  # Fast for tests
        base_delay_ms: 10,
        delay_variance_ms: 5,
        error_injection_enabled: true,
        predefined_responses: default_test_responses(),
        log_requests: false  # Reduce noise in test output
      }
    end

    defp production_config do
      %{
        timeout: 30_000,
        max_retries: 3,
        retry_delay: 1000
      }
    end

    defp default_test_responses do
      %{
        "test question" => %{"answer" => "test answer", "confidence" => 0.9},
        "What is AI?" => %{"answer" => "Artificial Intelligence", "confidence" => 0.95},
        "What is 2+2?" => %{"answer" => "4", "confidence" => 1.0}
      }
    end

    # Helper Functions
    defp start_bridge_with_mock_server do
      # Get mock server port
      {:ok, stats} = DSPex.PythonBridge.MockServer.get_stats()
      mock_port = stats[:port] || 12345

      # Configure bridge to connect to mock server instead of spawning Python
      bridge_config = %{
        mode: :mock_server,
        mock_server_port: mock_port,
        timeout: 10_000
      }

      DSPex.PythonBridge.Bridge.start_link(bridge_config)
    end

    defp verify_python_dspy_available do
      case System.find_executable("python3") do
        nil ->
          {:error, "Python 3 not found"}

        python_path ->
          # Test if DSPy is importable
          case System.cmd(python_path, ["-c", "import dspy; print('ok')"], stderr_to_stdout: true) do
            {"ok\n", 0} -> :ok
            {output, _} -> {:error, "DSPy import failed: #{output}"}
          end
      end
    end
  end

  3.2 Test Helpers

  defmodule DSPex.Testing.Helpers do
    @moduledoc """
    Comprehensive test helpers for all testing modes and common testing patterns.
    """

    alias DSPex.Testing.ModeManager
    alias DSPex.Adapters.Mock
    alias DSPex.PythonBridge.MockServer

    @doc """
    Setup test environment with specified mode.

    Usage:
      setup_test_env(:unit_mock)         # Fast unit tests
      setup_test_env(:integration_mock)  # Bridge integration tests
      setup_test_env(:e2e_real)          # Full end-to-end tests
    """
    def setup_test_env(mode) do
      case ModeManager.setup_test_mode(mode) do
        :ok ->
          configure_test_mode_specifics(mode)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end

    @doc """
    Teardown test environment and clean up resources.
    """
    def teardown_test_env do
      ModeManager.teardown_test_mode()
    end

    @doc """
    Create a test program with the current adapter.
    """
    def create_test_program(signature_module, opts \\ %{}) do
      config = %{
        id: opts[:program_id] || "test_program_#{:rand.uniform(10000)}",
        signature: signature_module.__signature__(),
        modules: opts[:modules] || []
      }

      adapter = get_current_adapter()
      adapter.create_program(config)
    end

    @doc """
    Execute a test program with mock inputs.
    """
    def execute_test_program(program_id, inputs \\ %{}) do
      default_inputs = %{question: "test question"}
      merged_inputs = Map.merge(default_inputs, inputs)

      adapter = get_current_adapter()
      adapter.execute_program(program_id, merged_inputs)
    end

    @doc """
    Wait for operations to complete (useful for async testing).
    """
    def wait_for_operations(operation_count, timeout \\ 5000) do
      case ModeManager.get_current_mode() do
        :unit_mock ->
          wait_for_mock_operations(operation_count, timeout)

        :integration_mock ->
          wait_for_bridge_operations(operation_count, timeout)

        :e2e_real ->
          # E2E operations are synchronous
          :ok
      end
    end

    @doc """
    Configure predefined responses for testing.
    """
    def set_predefined_responses(responses) when is_map(responses) do
      case ModeManager.get_current_mode() do
        :unit_mock ->
          Mock.configure(%{predefined_responses: responses})

        :integration_mock ->
          MockServer.configure(%{predefined_responses: responses})

        :e2e_real ->
          {:error, "Cannot set predefined responses in E2E mode"}
      end
    end

    @doc """
    Inject errors for testing error handling.
    """
    def inject_test_errors(error_configs) when is_list(error_configs) do
      case ModeManager.get_current_mode() do
        :unit_mock ->
          Enum.each(error_configs, fn error_config ->
            Mock.inject_error(error_config)
          end)

        :integration_mock ->
          MockServer.configure(%{error_injection_enabled: true})
          # Configure specific errors...

        :e2e_real ->
          {:error, "Cannot inject errors in E2E mode"}
      end
    end

    @doc """
    Get test statistics from current test mode.
    """
    def get_test_stats do
      case ModeManager.get_current_mode() do
        :unit_mock ->
          Mock.get_stats()

        :integration_mock ->
          MockServer.get_stats()

        :e2e_real ->
          {:ok, %{mode: :e2e_real, note: "No statistics available in E2E mode"}}
      end
    end

    @doc """
    Reset test environment to clean state.
    """
    def reset_test_state do
      case ModeManager.get_current_mode() do
        :unit_mock ->
          Mock.reset()

        :integration_mock ->
          MockServer.reset_stats()

        :e2e_real ->
          # No reset needed for E2E mode
          :ok
      end
    end

    @doc """
    Assert that a certain number of operations completed successfully.
    """
    def assert_operations_completed(operation_type, expected_count) do
      {:ok, stats} = get_test_stats()

      actual_count = case ModeManager.get_current_mode() do
        :unit_mock ->
          get_in(stats, [operation_type, :success]) || 0

        :integration_mock ->
          get_in(stats, [:requests_by_command, to_string(operation_type), :success]) || 0

        :e2e_real ->
          # For E2E, we assume operations completed if no errors
          expected_count
      end

      if actual_count >= expected_count do
        :ok
      else
        {:error, "Expected #{expected_count} #{operation_type} operations, got #{actual_count}"}
      end
    end

    # Private Helper Functions
    defp configure_test_mode_specifics(mode) do
      case mode do
        :unit_mock ->
          # Configure for very fast unit tests
          Mock.configure(%{realistic_delays: false})

        :integration_mock ->
          # Configure for faster integration tests
          MockServer.configure(%{simulate_delays: false})

        :e2e_real ->
          # No special configuration needed
          :ok
      end
    end

    defp get_current_adapter do
      case ModeManager.get_current_mode() do
        :unit_mock -> DSPex.Adapters.Mock
        :integration_mock -> DSPex.Adapters.PythonPort
        :e2e_real -> DSPex.Adapters.PythonPort
      end
    end

    defp wait_for_mock_operations(operation_count, timeout) do
      start_time = System.monotonic_time(:millisecond)
      wait_loop_mock(operation_count, start_time, timeout)
    end

    defp wait_for_bridge_operations(operation_count, timeout) do
      start_time = System.monotonic_time(:millisecond)
      wait_loop_bridge(operation_count, start_time, timeout)
    end

    defp wait_loop_mock(expected_count, start_time, timeout) do
      current_time = System.monotonic_time(:millisecond)

      if current_time - start_time > timeout do
        {:error, :timeout}
      else
        {:ok, stats} = Mock.get_stats()
        current_count = stats.total_operations

        if current_count >= expected_count do
          :ok
        else
          Process.sleep(10)
          wait_loop_mock(expected_count, start_time, timeout)
        end
      end
    end

    defp wait_loop_bridge(expected_count, start_time, timeout) do
      current_time = System.monotonic_time(:millisecond)

      if current_time - start_time > timeout do
        {:error, :timeout}
      else
        {:ok, stats} = MockServer.get_stats()
        current_count = stats.requests_total

        if current_count >= expected_count do
          :ok
        else
          Process.sleep(10)
          wait_loop_bridge(expected_count, start_time, timeout)
        end
      end
    end
  end

  3.3 ExUnit Integration

  defmodule DSPex.Testing.ExUnitCase do
    @moduledoc """
    ExUnit case template for DSPy testing with automatic mode setup.

    Usage:
      defmodule MyTest do
        use DSPex.Testing.ExUnitCase, mode: :unit_mock

        test "my test" do
          # Test code here - mode is automatically configured
        end
      end
    """

    defmacro __using__(opts) do
      mode = Keyword.get(opts, :mode, :unit_mock)

      quote do
        use ExUnit.Case

        alias DSPex.Testing.Helpers

        setup do
          case Helpers.setup_test_env(unquote(mode)) do
            :ok ->
              on_exit(fn -> Helpers.teardown_test_env() end)
              {:ok, test_mode: unquote(mode)}

            {:error, reason} ->
              ExUnit.CaptureLog.capture_log(fn ->
                IO.puts("Failed to setup test environment: #{reason}")
              end)

              {:error, reason}
          end
        end
      end
    end
  end

  INTEGRATION WITH EXISTING BRIDGE

  Enhanced Bridge Configuration

  # Modify your existing bridge to support test modes
  defmodule DSPex.PythonBridge.Bridge do
    # ... existing implementation ...

    def start_link(opts \\ []) do
      mode = Keyword.get(opts, :mode, :production)

      case mode do
        :production ->
          start_production_mode(opts)

        :mock_server ->
          start_mock_server_mode(opts)

        _ ->
          {:error, "Unknown bridge mode: #{mode}"}
      end
    end

    defp start_production_mode(opts) do
      # Your existing bridge implementation
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    defp start_mock_server_mode(opts) do
      mock_port = Keyword.get(opts, :mock_server_port, 12345)

      # Start bridge but connect to mock server instead of spawning Python
      modified_opts = Keyword.merge(opts, [
        python_executable: :mock_server,
        mock_port: mock_port
      ])

      GenServer.start_link(__MODULE__, modified_opts, name: __MODULE__)
    end

    def init(opts) do
      case Keyword.get(opts, :python_executable, "python3") do
        :mock_server ->
          init_mock_server_connection(opts)

        python_path ->
          init_python_process(python_path, opts)
      end
    end

    defp init_mock_server_connection(opts) do
      mock_port = Keyword.get(opts, :mock_port, 12345)

      # Connect to mock server via TCP instead of spawning Python process
      case :gen_tcp.connect('localhost', mock_port, [:binary, packet: 4]) do
        {:ok, socket} ->
          {:ok, %{
            mode: :mock_server,
            socket: socket,
            requests: %{},
            request_id: 0
          }}

        {:error, reason} ->
          {:stop, "Failed to connect to mock server: #{reason}"}
      end
    end

    defp init_python_process(python_path, opts) do
      # Your existing Python process initialization
      # ...
    end

    # Modify call handling to work with both modes
    def handle_call({:call, command, args}, from, %{mode: :mock_server} = state) do
      # Send request to mock server via TCP
      request_id = state.request_id + 1

      request = %{
        id: request_id,
        command: to_string(command),
        args: args
      }

      case :gen_tcp.send(state.socket, Jason.encode!(request)) do
        :ok ->
          new_requests = Map.put(state.requests, request_id, from)
          {:noreply, %{state | requests: new_requests, request_id: request_id}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end

    def handle_call({:call, command, args}, from, state) do
      # Your existing Python process call handling
      # ...
    end

    # Handle responses from mock server
    def handle_info({:tcp, socket, data}, %{mode: :mock_server, socket: socket} = state) do
      case Jason.decode(data) do
        {:ok, %{"id" => id, "success" => true, "result" => result}} ->
          case Map.pop(state.requests, id) do
            {nil, requests} ->
              Logger.warning("Received response for unknown request: #{id}")
              {:noreply, %{state | requests: requests}}

            {from, requests} ->
              GenServer.reply(from, {:ok, result})
              {:noreply, %{state | requests: requests}}
          end

        {:ok, %{"id" => id, "success" => false, "error" => error}} ->
          case Map.pop(state.requests, id) do
            {nil, requests} ->
              Logger.warning("Received error for unknown request: #{id}")
              {:noreply, %{state | requests: requests}}

            {from, requests} ->
              GenServer.reply(from, {:error, error})
              {:noreply, %{state | requests: requests}}
          end

        {:error, reason} ->
          Logger.error("Failed to decode mock server response: #{inspect(reason)}")
          {:noreply, state}
      end
    end

    def handle_info(msg, state) do
      # Your existing message handling for Python process mode
      # ...
    end
  end

  TESTING EXAMPLES

  Example Test Files

  # test/dspex/unit_test_example.exs
  defmodule DSPex.UnitTestExample do
    use DSPex.Testing.ExUnitCase, mode: :unit_mock

    alias DSPex.Testing.Helpers

    defmodule TestSignature do
      use DSPex.Signature
      signature question: :string -> answer: :string
    end

    test "fast unit test with mock adapter" do
      # This test runs in milliseconds
      {:ok, program_id} = Helpers.create_test_program(TestSignature)
      {:ok, result} = Helpers.execute_test_program(program_id)

      assert Map.has_key?(result, :answer)
      assert is_binary(result.answer)
    end

    test "predefined response testing" do
      responses = %{"test question" => %{"answer" => "expected answer"}}
      :ok = Helpers.set_predefined_responses(responses)

      {:ok, program_id} = Helpers.create_test_program(TestSignature)
      {:ok, result} = Helpers.execute_test_program(program_id, %{question: "test question"})

      assert result.answer == "expected answer"
    end
  end

  # test/dspex/integration_test_example.exs
  defmodule DSPex.IntegrationTestExample do
    use DSPex.Testing.ExUnitCase, mode: :integration_mock

    alias DSPex.Testing.Helpers

    defmodule TestSignature do
      use DSPex.Signature
      signature question: :string -> answer: :string
    end

    test "bridge communication with mock server" do
      # This test validates bridge protocol, serialization, etc.
      {:ok, program_id} = Helpers.create_test_program(TestSignature)
      {:ok, result} = Helpers.execute_test_program(program_id)

      assert Map.has_key?(result, :answer)

      # Verify bridge statistics
      {:ok, stats} = Helpers.get_test_stats()
      assert stats.requests_total >= 2  # create + execute
    end
  end

  # test/dspex/e2e_test_example.exs
  defmodule DSPex.E2ETestExample do
    use DSPex.Testing.ExUnitCase, mode: :e2e_real

    alias DSPex.Testing.Helpers

    @moduletag :e2e
    @moduletag timeout: 30_000  # Longer timeout for E2E tests

    defmodule TestSignature do
      use DSPex.Signature
      signature question: :string -> answer: :string
    end

    test "full end-to-end with real Python DSPy" do
      # This test requires Python DSPy installation
      {:ok, program_id} = Helpers.create_test_program(TestSignature)
      {:ok, result} = Helpers.execute_test_program(program_id)

      assert Map.has_key?(result, :answer)
      assert is_binary(result.answer)
    end
  end

  IMPLEMENTATION REQUIREMENTS

  File Structure to Create:

  lib/dspex/
  ├── adapters/
  │   └── mock.ex                     # Layer 1: Pure mock adapter
  ├── python_bridge/
  │   └── mock_server.ex              # Layer 2: Bridge mock server
  └── testing/
      ├── mode_manager.ex             # Test mode configuration
      ├── helpers.ex                  # Test helper functions
      └── ex_unit_case.ex             # ExUnit integration

  test/dspex/
  ├── unit_test_example.exs           # Unit test examples
  ├── integration_test_example.exs    # Integration test examples
  └── e2e_test_example.exs            # E2E test examples

  config/
  ├── test.exs                        # Test configuration
  └── test_modes.exs                  # Mode-specific configurations

  Configuration Files:

  # config/test.exs
  import Config

  # Default to unit mock mode for fast testing
  config :dspex,
    test_mode: :unit_mock,
    adapter: DSPex.Adapters.Mock

  # config/test_modes.exs
  import Config

  case System.get_env("TEST_MODE") do
    "integration" ->
      config :dspex,
        test_mode: :integration_mock,
        adapter: DSPex.Adapters.PythonPort,
        bridge_mode: :mock_server

    "e2e" ->
      config :dspex,
        test_mode: :e2e_real,
        adapter: DSPex.Adapters.PythonPort,
        bridge_mode: :production

    _ ->
      # Default to unit mock
      config :dspex,
        test_mode: :unit_mock,
        adapter: DSPex.Adapters.Mock
  end

  USAGE SCENARIOS

  Development Workflow:

  # Fast unit tests during development (default)
  mix test

  # Integration tests for bridge validation
  TEST_MODE=integration mix test

  # Full E2E tests before deployment
  TEST_MODE=e2e mix test --include e2e

  # Run specific test layer
  mix test test/dspex/unit_test_example.exs      # Unit only
  mix test test/dspex/integration_test_example.exs  # Integration only
  mix test test/dspex/e2e_test_example.exs      # E2E only

  CI/CD Pipeline:

  # .github/workflows/test.yml
  test-unit:
    run: mix test

  test-integration:
    run: TEST_MODE=integration mix test

  test-e2e:
    run: TEST_MODE=e2e mix test --include e2e
    requires: python-dspy-setup

  SUCCESS CRITERIA

  1. Layer 1 (Mock Adapter): Unit tests run in milliseconds without any external dependencies
  2. Layer 2 (Bridge Mock): Integration tests validate wire protocol and serialization correctly
  3. Layer 3 (E2E Real): Full stack tests work with real Python DSPy when available
  4. Mode Switching: Easy configuration switching between all three modes
  5. Test Isolation: Each test mode is completely isolated from others
  6. Future Ready: Architecture supports your planned Elixir native DSPy port
  7. Developer Experience: Fast feedback loop for daily development
  8. CI/CD Ready: Reliable tests that work in automated environments
  9. Comprehensive Coverage: All system components can be tested appropriately
  10. Debugging Support: Clear isolation of failures to specific layers

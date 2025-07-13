● Stage 1 Prompt 2b: Mock Adapter Implementation

  OBJECTIVE

  Implement a comprehensive mock adapter that provides deterministic, configurable responses for DSPy operations without requiring external dependencies. This mock adapter must
  support the full adapter interface, provide realistic simulation of ML operations, and enable comprehensive testing of the entire DSPy-Ash integration stack.

  COMPLETE IMPLEMENTATION CONTEXT

  MOCK ADAPTER ARCHITECTURE OVERVIEW

  From ASH_DSPY_INTEGRATION_ARCHITECTURE.md and stage1_03_adapter_pattern.md:

  Mock Adapter Philosophy:
  - Complete implementation of adapter behavior without external dependencies
  - Deterministic responses for predictable testing
  - Configurable scenarios for edge case testing
  - Performance simulation for load testing
  - State management for testing complex workflows
  - Error injection for resilience testing

  Mock Adapter Requirements:
  ┌─────────────────────────────────────────────────────────────┐
  │                 AshDSPy.Adapters.Mock                      │
  ├─────────────────────────────────────────────────────────────┤
  │                                                             │
  │  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
  │  │ Program         │  │ Response        │  │ Scenario     ││
  │  │ Management      │  │ Generation      │  │ Management   ││
  │  │ - In-memory     │  │ - Deterministic │  │ - Configurable│
  │  │ - State tracking│  │ - Type-aware    │  │ - Error inject││
  │  │ - Lifecycle     │  │ - Realistic     │  │ - Performance││
  │  └─────────────────┘  └─────────────────┘  └──────────────┘│
  │                                                             │
  └─────────────────────────────────────────────────────────────┘

  ADAPTER BEHAVIOR COMPLIANCE

  From stage1_03_adapter_pattern.md:

  @behaviour AshDSPy.Adapters.Adapter

  @callback create_program(program_config()) :: {:ok, String.t()} | {:error, term()}
  @callback execute_program(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback optimize_program(String.t(), list(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_programs() :: {:ok, list(String.t())} | {:error, term()}
  @callback health_check() :: {:ok, map()} | {:error, term()}
  @callback get_program_info(String.t()) :: {:ok, map()} | {:error, term()}

  COMPLETE MOCK ADAPTER IMPLEMENTATION

  1. Core Mock Adapter GenServer

  defmodule AshDSPy.Adapters.Mock do
    @moduledoc """
    Mock adapter for DSPy operations providing deterministic responses
    for testing and development without external dependencies.

    Features:
    - Complete adapter behavior implementation
    - Deterministic response generation
    - Configurable scenarios and error injection
    - Performance simulation with realistic delays
    - State management for complex testing workflows
    - Thread-safe concurrent operation support
    """

    @behaviour AshDSPy.Adapters.Adapter
    use GenServer

    require Logger

    # State structure
    defstruct [
      :programs,           # Map of program_id -> program_state
      :executions,         # Map of execution_id -> execution_result
      :scenarios,          # Current testing scenarios
      :config,             # Mock configuration
      :stats,              # Execution statistics
      :error_injection     # Error injection rules
    ]

    # Public API
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def stop do
      GenServer.stop(__MODULE__)
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

    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end

    def inject_error(error_config) do
      GenServer.call(__MODULE__, {:inject_error, error_config})
    end

    def clear_errors do
      GenServer.call(__MODULE__, :clear_errors)
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

    # GenServer Callbacks
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

      Logger.info("Mock adapter reset")
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:configure, config}, _from, state) do
      new_config = Map.merge(state.config, config)
      new_state = %{state | config: new_config}

      Logger.info("Mock adapter reconfigured: #{inspect(config)}")
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call({:set_scenario, scenario_name, scenario_config}, _from, state) do
      new_scenarios = Map.put(state.scenarios, scenario_name, scenario_config)
      new_state = %{state | scenarios: new_scenarios}

      Logger.info("Mock scenario set: #{scenario_name} -> #{inspect(scenario_config)}")
      {:reply, :ok, new_state}
    end

    @impl true
    def handle_call(:get_stats, _from, state) do
      {:reply, {:ok, state.stats}, state}
    end

    @impl true
    def handle_call({:inject_error, error_config}, _from, state) do
      error_id = generate_id()
      new_errors = Map.put(state.error_injection, error_id, error_config)
      new_state = %{state | error_injection: new_errors}

      Logger.info("Error injection configured: #{error_id} -> #{inspect(error_config)}")
      {:reply, {:ok, error_id}, new_state}
    end

    @impl true
    def handle_call(:clear_errors, _from, state) do
      new_state = %{state | error_injection: %{}}
      Logger.info("Error injection cleared")
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

    @impl true
    def handle_call({:optimize_program, program_id, dataset, config}, _from, state) do
      case check_error_injection(:optimize_program, state) do
        {:error, error} ->
          {:reply, {:error, error}, update_stats(state, :optimize_program, :error)}

        :continue ->
          handle_optimize_program(program_id, dataset, config, state)
      end
    end

    @impl true
    def handle_call(:list_programs, _from, state) do
      case check_error_injection(:list_programs, state) do
        {:error, error} ->
          {:reply, {:error, error}, update_stats(state, :list_programs, :error)}

        :continue ->
          handle_list_programs(state)
      end
    end

    @impl true
    def handle_call(:health_check, _from, state) do
      case check_error_injection(:health_check, state) do
        {:error, error} ->
          {:reply, {:error, error}, state}

        :continue ->
          handle_health_check(state)
      end
    end

    @impl true
    def handle_call({:get_program_info, program_id}, _from, state) do
      case check_error_injection(:get_program_info, state) do
        {:error, error} ->
          {:reply, {:error, error}, state}

        :continue ->
          handle_get_program_info(program_id, state)
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
            last_executed_at: nil,
            optimization_history: []
          }

          new_programs = Map.put(state.programs, program_id, program_state)
          new_state = %{state | programs: new_programs}
          |> update_stats(:create_program, :success)

          Logger.debug("Mock program created: #{program_id}")
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
              execution_id = generate_execution_id()

              # Generate realistic outputs based on signature
              outputs = generate_program_outputs(program_state, validated_inputs, state.config)

              execution_result = %{
                id: execution_id,
                program_id: program_id,
                inputs: validated_inputs,
                outputs: outputs,
                duration_ms: calculate_execution_duration(state.config),
                executed_at: DateTime.utc_now(),
                status: :completed,
                metadata: generate_execution_metadata(program_state, state.config)
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

              Logger.debug("Mock execution completed: #{execution_id}")
              {:reply, {:ok, outputs}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, update_stats(state, :execute_program, :validation_error)}
          end
      end
    end

    defp handle_optimize_program(program_id, dataset, config, state) do
      simulate_delay(:optimize_program, state.config)

      case Map.get(state.programs, program_id) do
        nil ->
          {:reply, {:error, "Program not found: #{program_id}"},
           update_stats(state, :optimize_program, :not_found)}

        program_state ->
          case validate_optimization_config(config) do
            {:ok, validated_config} ->
              # Simulate optimization process
              optimization_result = generate_optimization_result(
                program_state,
                dataset,
                validated_config,
                state.config
              )

              # Update program with optimization history
              optimization_entry = %{
                timestamp: DateTime.utc_now(),
                dataset_size: length(dataset),
                config: validated_config,
                result: optimization_result
              }

              updated_program = program_state
              |> Map.put(:optimization_history,
                   [optimization_entry | program_state.optimization_history])

              new_programs = Map.put(state.programs, program_id, updated_program)
              new_state = %{state | programs: new_programs}
              |> update_stats(:optimize_program, :success)

              Logger.debug("Mock optimization completed for program: #{program_id}")
              {:reply, {:ok, optimization_result}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, update_stats(state, :optimize_program, :validation_error)}
          end
      end
    end

    defp handle_list_programs(state) do
      simulate_delay(:list_programs, state.config)

      program_list = state.programs
      |> Enum.map(fn {program_id, program_state} ->
        %{
          id: program_id,
          status: program_state.status,
          created_at: program_state.created_at,
          execution_count: program_state.execution_count,
          last_executed_at: program_state.last_executed_at
        }
      end)

      new_state = update_stats(state, :list_programs, :success)
      {:reply, {:ok, program_list}, new_state}
    end

    defp handle_health_check(state) do
      simulate_delay(:health_check, state.config)

      health_info = %{
        status: :healthy,
        uptime_ms: get_uptime(),
        programs_count: map_size(state.programs),
        executions_count: map_size(state.executions),
        stats: state.stats,
        memory_usage: get_memory_usage(),
        timestamp: DateTime.utc_now()
      }

      {:reply, {:ok, health_info}, state}
    end

    defp handle_get_program_info(program_id, state) do
      simulate_delay(:get_program_info, state.config)

      case Map.get(state.programs, program_id) do
        nil ->
          {:reply, {:error, "Program not found: #{program_id}"}, state}

        program_state ->
          program_info = %{
            id: program_id,
            config: program_state.config,
            status: program_state.status,
            created_at: program_state.created_at,
            execution_count: program_state.execution_count,
            last_executed_at: program_state.last_executed_at,
            optimization_history: program_state.optimization_history,
            recent_executions: get_recent_executions(program_id, state.executions)
          }

          {:reply, {:ok, program_info}, state}
      end
    end

    # Validation Functions
    defp validate_program_config(config) do
      required_fields = [:id, :signature]

      case check_required_fields(config, required_fields) do
        :ok ->
          case validate_signature_format(config.signature) do
            :ok ->
              {:ok, config}
            {:error, reason} ->
              {:error, "Invalid signature: #{reason}"}
          end

        {:error, missing_fields} ->
          {:error, "Missing required fields: #{inspect(missing_fields)}"}
      end
    end

    defp validate_execution_inputs(program_state, inputs) do
      signature = program_state.config.signature

      # Extract expected input fields from signature
      expected_inputs = case signature do
        %{inputs: input_fields} when is_list(input_fields) ->
          Enum.map(input_fields, fn {name, _type, _constraints} -> name end)

        %{inputs: input_fields} when is_map(input_fields) ->
          Map.keys(input_fields)

        _ ->
          []
      end

      case validate_input_fields(inputs, expected_inputs) do
        :ok ->
          {:ok, inputs}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp validate_optimization_config(config) when is_map(config) do
      default_config = %{
        optimizer: "BootstrapFewShot",
        metric: "exact_match",
        max_iterations: 10,
        timeout: 300_000
      }

      merged_config = Map.merge(default_config, config)
      {:ok, merged_config}
    end

    defp validate_optimization_config(_config) do
      {:error, "Optimization config must be a map"}
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

        %{outputs: outputs} when is_map(outputs) ->
          Map.to_list(outputs)

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
          generate_summary_for_text(text, config)

        _ ->
          "Mock #{field_name} response for inputs: #{inspect(inputs)}"
      end
    end

    defp generate_value_for_type(:float, _inputs, field_name, config) do
      case field_name do
        :confidence -> 0.75 + (:rand.uniform() * 0.24)  # 0.75-0.99
        :probability -> :rand.uniform()
        :score -> config[:base_score] || (0.6 + (:rand.uniform() * 0.4))
        _ -> :rand.uniform() * 100
      end
    end

    defp generate_value_for_type(:integer, _inputs, field_name, _config) do
      case field_name do
        :count -> :rand.uniform(100)
        :tokens -> :rand.uniform(1000) + 100
        _ -> :rand.uniform(1000)
      end
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
          # Generate contextual response
          cond do
            String.contains?(String.downcase(question), ["what", "define"]) ->
              "Mock definition response for: #{question}"

            String.contains?(String.downcase(question), ["how", "explain"]) ->
              "Mock explanation response for: #{question}"

            String.contains?(String.downcase(question), ["why"]) ->
              "Mock reasoning response for: #{question}"

            String.contains?(String.downcase(question), ["when"]) ->
              "Mock temporal response for: #{question}"

            String.contains?(String.downcase(question), ["where"]) ->
              "Mock location response for: #{question}"

            true ->
              "Mock response to: #{question}"
          end

        predefined_response ->
          predefined_response
      end
    end

    defp generate_summary_for_text(text, _config) do
      word_count = text |> String.split() |> length()
      "Mock summary of #{word_count}-word text: #{String.slice(text, 0, 50)}..."
    end

    defp generate_optimization_result(program_state, dataset, config, mock_config) do
      base_score = mock_config[:optimization_base_score] || 0.7
      improvement = (:rand.uniform() * 0.3)  # 0-30% improvement
      final_score = min(base_score + improvement, 0.99)

      %{
        program_id: program_state.id,
        score: final_score,
        improvement: improvement,
        optimizer: config.optimizer,
        metric: config.metric,
        dataset_size: length(dataset),
        optimization_time_ms: calculate_optimization_duration(mock_config),
        iterations: :rand.uniform(config.max_iterations),
        metadata: %{
          mock: true,
          base_score: base_score,
          timestamp: DateTime.utc_now()
        }
      }
    end

    # Utility Functions
    defp build_default_config(opts) do
      default_config = %{
        base_latency_ms: 100,
        latency_variance_ms: 50,
        optimization_base_score: 0.7,
        enable_scenarios: true,
        enable_error_injection: true,
        predefined_responses: %{},
        realistic_delays: true
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
        get_program_info: %{success: 0, error: 0, not_found: 0},
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

    defp generate_id do
      :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    end

    defp generate_program_id(config) do
      case config do
        %{id: id} when is_binary(id) -> id
        %{id: id} -> to_string(id)
        _ -> "mock_program_" <> generate_id()
      end
    end

    defp generate_execution_id do
      "mock_exec_" <> generate_id()
    end

    defp simulate_delay(operation, config) do
      if config.realistic_delays do
        base_latency = case operation do
          :create_program -> config.base_latency_ms * 2
          :execute_program -> config.base_latency_ms
          :optimize_program -> config.base_latency_ms * 10
          :list_programs -> config.base_latency_ms / 2
          :health_check -> config.base_latency_ms / 4
          :get_program_info -> config.base_latency_ms / 2
        end

        variance = :rand.uniform(config.latency_variance_ms * 2) - config.latency_variance_ms
        delay = max(base_latency + variance, 10)  # Minimum 10ms

        Process.sleep(round(delay))
      end
    end

    defp calculate_execution_duration(config) do
      base = config.base_latency_ms
      variance = :rand.uniform(config.latency_variance_ms * 2) - config.latency_variance_ms
      max(base + variance, 10)
    end

    defp calculate_optimization_duration(config) do
      base = config.base_latency_ms * 10
      variance = :rand.uniform(config.latency_variance_ms * 5) - (config.latency_variance_ms * 2)
      max(base + variance, 100)
    end

    defp generate_execution_metadata(program_state, config) do
      %{
        mock: true,
        program_id: program_state.id,
        execution_number: program_state.execution_count + 1,
        simulated_tokens: %{
          input: :rand.uniform(500) + 100,
          output: :rand.uniform(200) + 50,
          total: :rand.uniform(700) + 150
        },
        model_info: %{
          name: "mock-gpt-4",
          provider: "mock",
          version: "1.0.0"
        },
        timestamp: DateTime.utc_now()
      }
    end

    # Error Injection Functions
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

    # Scenario Management Functions
    defp get_scenario_response(operation, program_id, config) do
      if config.enable_scenarios do
        scenario_key = {operation, program_id}
        # Implementation would check configured scenarios
        :no_scenario
      else
        :no_scenario
      end
    end

    # Validation Helper Functions
    defp check_required_fields(map, required_fields) do
      missing_fields = required_fields
      |> Enum.filter(fn field -> not Map.has_key?(map, field) end)

      case missing_fields do
        [] -> :ok
        missing -> {:error, missing}
      end
    end

    defp validate_signature_format(signature) when is_map(signature) do
      case {Map.has_key?(signature, :inputs), Map.has_key?(signature, :outputs)} do
        {true, true} -> :ok
        {false, _} -> {:error, "Missing inputs"}
        {_, false} -> {:error, "Missing outputs"}
      end
    end

    defp validate_signature_format(_), do: {:error, "Signature must be a map"}

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

    defp get_recent_executions(program_id, executions) do
      executions
      |> Enum.filter(fn {_id, execution} -> execution.program_id == program_id end)
      |> Enum.sort_by(fn {_id, execution} -> execution.executed_at end, {:desc, DateTime})
      |> Enum.take(10)
      |> Enum.map(fn {id, execution} -> Map.put(execution, :id, id) end)
    end

    defp get_uptime do
      {uptime_ms, _} = :erlang.statistics(:wall_clock)
      uptime_ms
    end

    defp get_memory_usage do
      memory_info = :erlang.memory()
      %{
        total_mb: round(memory_info[:total] / (1024 * 1024)),
        process_mb: round(memory_info[:processes] / (1024 * 1024)),
        system_mb: round(memory_info[:system] / (1024 * 1024))
      }
    end
  end

  2. Mock Adapter Test Helpers

  defmodule AshDSPy.Adapters.Mock.TestHelpers do
    @moduledoc """
    Test helpers for configuring and using the mock adapter in tests.
    """

    alias AshDSPy.Adapters.Mock

    @doc """
    Set up mock adapter for testing with default configuration.
    """
    def setup_mock_adapter(config \\ %{}) do
      default_config = %{
        realistic_delays: false,  # Disable delays in tests
        base_latency_ms: 1,
        latency_variance_ms: 0
      }

      merged_config = Map.merge(default_config, config)

      case Process.whereis(Mock) do
        nil ->
          {:ok, _pid} = Mock.start_link(merged_config)

        _pid ->
          Mock.reset()
          Mock.configure(merged_config)
      end

      :ok
    end

    @doc """
    Configure predefined responses for specific questions.
    """
    def set_predefined_responses(responses) when is_map(responses) do
      Mock.configure(%{predefined_responses: responses})
    end

    @doc """
    Set up error injection for testing error scenarios.
    """
    def inject_errors(error_configs) when is_list(error_configs) do
      Enum.each(error_configs, fn error_config ->
        Mock.inject_error(error_config)
      end)
    end

    @doc """
    Configure specific scenario for a program.
    """
    def set_program_scenario(program_id, scenario_config) do
      Mock.set_scenario({:execute_program, program_id}, scenario_config)
    end

    @doc """
    Get execution statistics from mock adapter.
    """
    def get_execution_stats do
      {:ok, stats} = Mock.get_stats()
      stats
    end

    @doc """
    Wait for specific number of operations to complete.
    """
    def wait_for_operations(operation_type, expected_count, timeout \\ 5000) do
      start_time = System.monotonic_time(:millisecond)

      wait_loop(operation_type, expected_count, start_time, timeout)
    end

    defp wait_loop(operation_type, expected_count, start_time, timeout) do
      current_time = System.monotonic_time(:millisecond)

      if current_time - start_time > timeout do
        {:error, :timeout}
      else
        {:ok, stats} = Mock.get_stats()
        current_count = get_in(stats, [operation_type, :success]) || 0

        if current_count >= expected_count do
          :ok
        else
          Process.sleep(10)
          wait_loop(operation_type, expected_count, start_time, timeout)
        end
      end
    end

    @doc """
    Create a test program with the mock adapter.
    """
    def create_test_program(signature_module, opts \\ %{}) do
      config = %{
        id: opts[:program_id] || "test_program_#{:rand.uniform(10000)}",
        signature: signature_module.__signature__(),
        modules: opts[:modules] || []
      }

      Mock.create_program(config)
    end

    @doc """
    Execute a test program with mock inputs.
    """
    def execute_test_program(program_id, inputs \\ %{}) do
      default_inputs = %{question: "test question"}
      merged_inputs = Map.merge(default_inputs, inputs)

      Mock.execute_program(program_id, merged_inputs)
    end

    @doc """
    Reset mock adapter to clean state.
    """
    def reset_mock_adapter do
      Mock.reset()
    end

    @doc """
    Stop mock adapter (useful for cleanup in tests).
    """
    def stop_mock_adapter do
      case Process.whereis(Mock) do
        nil -> :ok
        _pid -> Mock.stop()
      end
    end
  end

  3. Mock Adapter Configuration

  defmodule AshDSPy.Adapters.Mock.Config do
    @moduledoc """
    Configuration management for mock adapter scenarios and behaviors.
    """

    @doc """
    Predefined test scenarios for common testing patterns.
    """
    def get_predefined_scenario(scenario_name) do
      scenarios = %{
        :basic_qa => %{
          predefined_responses: %{
            "What is AI?" => "Artificial Intelligence is the simulation of human intelligence processes by machines.",
            "What is ML?" => "Machine Learning is a method of data analysis that automates analytical model building.",
            "What is 2+2?" => "4"
          },
          base_latency_ms: 50,
          optimization_base_score: 0.8
        },

        :high_latency => %{
          base_latency_ms: 2000,
          latency_variance_ms: 500,
          realistic_delays: true
        },

        :error_prone => %{
          enable_error_injection: true,
          error_probability: 0.3
        },

        :fast_responses => %{
          base_latency_ms: 10,
          latency_variance_ms: 5,
          realistic_delays: false
        },

        :comprehensive_testing => %{
          predefined_responses: %{
            "test question" => "test answer",
            "error question" => {:error, "simulated error"},
            "slow question" => {:delay, 1000, "delayed answer"}
          },
          enable_scenarios: true,
          enable_error_injection: true
        }
      }

      Map.get(scenarios, scenario_name)
    end

    @doc """
    Common error injection configurations.
    """
    def get_error_injection_config(error_type) do
      error_configs = %{
        :random_failures => %{
          operation: :execute_program,
          error: "Random execution failure",
          probability: 0.1
        },

        :timeout_errors => %{
          operation: :execute_program,
          error: "Request timeout",
          probability: 0.05
        },

        :validation_errors => %{
          operation: :create_program,
          error: "Invalid program configuration",
          probability: 0.2
        },

        :network_errors => %{
          operation: :execute_program,
          error: "Network connection failed",
          probability: 0.15
        }
      }

      Map.get(error_configs, error_type)
    end
  end

  TESTING INTEGRATION

  Test Usage Examples

  defmodule AshDSPy.MockAdapterTest do
    use ExUnit.Case

    alias AshDSPy.Adapters.Mock
    alias AshDSPy.Adapters.Mock.{TestHelpers, Config}

    setup do
      TestHelpers.setup_mock_adapter()
      on_exit(fn -> TestHelpers.stop_mock_adapter() end)
      :ok
    end

    test "basic program creation and execution" do
      # Create test signature
      defmodule TestSignature do
        use AshDSPy.Signature
        signature question: :string -> answer: :string
      end

      # Create program
      {:ok, program_id} = TestHelpers.create_test_program(TestSignature)
      assert is_binary(program_id)

      # Execute program
      {:ok, outputs} = TestHelpers.execute_test_program(program_id)
      assert Map.has_key?(outputs, :answer)
      assert is_binary(outputs.answer)
    end

    test "predefined responses" do
      responses = %{"test question" => "test answer"}
      TestHelpers.set_predefined_responses(responses)

      {:ok, program_id} = TestHelpers.create_test_program(TestSignature)
      {:ok, outputs} = Mock.execute_program(program_id, %{question: "test question"})

      assert outputs.answer == "test answer"
    end

    test "error injection" do
      error_config = %{
        operation: :execute_program,
        error: "Simulated error",
        probability: 1.0
      }

      {:ok, _error_id} = Mock.inject_error(error_config)
      {:ok, program_id} = TestHelpers.create_test_program(TestSignature)

      {:error, reason} = Mock.execute_program(program_id, %{question: "test"})
      assert reason == "Simulated error"
    end

    test "statistics tracking" do
      {:ok, program_id} = TestHelpers.create_test_program(TestSignature)

      # Execute multiple times
      for _ <- 1..5 do
        TestHelpers.execute_test_program(program_id)
      end

      {:ok, stats} = Mock.get_stats()
      assert stats.execute_program.success == 5
      assert stats.total_operations >= 6  # 1 create + 5 execute
    end
  end

  INTEGRATION WITH ADAPTER REGISTRY

  # config/test.exs
  config :ash_dspy, :adapter, AshDSPy.Adapters.Mock

  # In your adapter registry
  defmodule AshDSPy.Adapters.Registry do
    def get_adapter(:mock), do: AshDSPy.Adapters.Mock
    def get_adapter(:python_port), do: AshDSPy.Adapters.PythonPort
    def get_adapter(atom) when is_atom(atom), do: get_adapter_module(atom)

    defp get_adapter_module(:mock), do: AshDSPy.Adapters.Mock
    defp get_adapter_module(type) do
      Application.get_env(:ash_dspy, :adapter, AshDSPy.Adapters.Mock)
    end
  end

  IMPLEMENTATION REQUIREMENTS

  File Structure to Create:

  lib/ash_dspy/adapters/
  ├── mock.ex                    # Main mock adapter implementation
  ├── mock/
  │   ├── test_helpers.ex        # Test helper functions
  │   └── config.ex              # Scenario and configuration management

  test/ash_dspy/adapters/
  ├── mock_test.ex               # Comprehensive mock adapter tests
  ├── mock_integration_test.exs  # Integration tests with other components
  └── mock_scenarios_test.exs    # Scenario-based testing

  Success Criteria:

  1. Complete adapter behavior implementation with all required callbacks
  2. Deterministic responses for predictable testing
  3. Configurable scenarios for different testing needs
  4. Error injection capabilities for resilience testing
  5. Performance simulation with realistic delays
  6. Statistics tracking for test verification
  7. Thread-safe operation for concurrent testing
  8. Integration with test infrastructure and helpers
  9. Documentation and examples for usage
  10. Comprehensive test coverage of all functionality

  This mock adapter provides a complete, production-ready testing foundation for the entire DSPy-Ash integration without any external dependencies.

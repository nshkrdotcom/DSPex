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

  # Mock adapter - implements same interface as PythonBridge adapter
  use GenServer

  require Logger

  defstruct [
    # Map of program_id -> program_state
    :programs,
    # Map of execution_id -> execution_result
    :executions,
    # Configured test scenarios
    :scenarios,
    # Mock configuration
    :config,
    # Operation statistics
    :stats,
    # Error injection rules
    :error_injection,
    # Language model configuration
    :lm_config
  ]

  # Public API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    genserver_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link(name: __MODULE__) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  def configure(config, server \\ __MODULE__) do
    GenServer.call(server, {:configure, config})
  end

  def set_scenario(scenario_name, scenario_config, server \\ __MODULE__) do
    GenServer.call(server, {:set_scenario, scenario_name, scenario_config})
  end

  def inject_error(error_config, server \\ __MODULE__) do
    GenServer.call(server, {:inject_error, error_config})
  end

  def get_programs(server \\ __MODULE__) do
    GenServer.call(server, :get_programs)
  end

  def get_executions(server \\ __MODULE__) do
    GenServer.call(server, :get_executions)
  end

  # Bridge-compatible API
  def ping do
    GenServer.call(__MODULE__, {:command, :ping, %{}})
  end

  @impl true
  def create_program(program_config) do
    _ = ensure_started()

    case GenServer.call(__MODULE__, {:command, :create_program, program_config}) do
      {:ok, %{program_id: program_id}} ->
        {:ok, program_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    _ = ensure_started()

    GenServer.call(
      __MODULE__,
      {:command, :execute_program, %{program_id: program_id, inputs: inputs}}
    )
  end

  @impl true
  def list_programs do
    _ = ensure_started()

    case GenServer.call(__MODULE__, {:command, :list_programs, %{}}) do
      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, fn p -> Map.get(p, :id) end)
        {:ok, program_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_program_info(program_id) do
    _ = ensure_started()
    GenServer.call(__MODULE__, {:command, :get_program_info, %{program_id: program_id}})
  end

  @impl true
  def delete_program(program_id) do
    _ = ensure_started()

    case GenServer.call(__MODULE__, {:command, :delete_program, %{program_id: program_id}}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def get_stats_info do
    GenServer.call(__MODULE__, {:command, :get_stats, %{}})
  end

  @impl true
  def health_check do
    _ = ensure_started()

    case ping() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_stats do
    _ = ensure_started()

    case get_stats_info() do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def configure_lm(config) do
    _ = ensure_started()

    # Store LM config and check it during execute_program
    case GenServer.call(__MODULE__, {:command, :configure_lm, config}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # GenServer Callbacks
  @impl true
  def init(opts) do
    config = build_config(opts)

    state = %__MODULE__{
      programs: %{},
      executions: %{},
      scenarios: %{},
      config: config,
      stats: %{
        programs_created: 0,
        executions_run: 0,
        errors_injected: 0,
        uptime_start: DateTime.utc_now()
      },
      error_injection: %{},
      lm_config: nil
    }

    Logger.debug("Mock adapter started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | programs: %{},
        executions: %{},
        scenarios: %{},
        error_injection: %{},
        stats: %{
          programs_created: 0,
          executions_run: 0,
          errors_injected: 0,
          uptime_start: DateTime.utc_now()
        },
        lm_config: nil
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:configure, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    {:reply, :ok, %{state | config: new_config}}
  end

  @impl true
  def handle_call({:set_scenario, scenario_name, scenario_config}, _from, state) do
    new_scenarios = Map.put(state.scenarios, scenario_name, scenario_config)
    {:reply, :ok, %{state | scenarios: new_scenarios}}
  end

  @impl true
  def handle_call({:inject_error, error_config}, _from, state) do
    new_error_injection = Map.merge(state.error_injection, error_config)
    {:reply, :ok, %{state | error_injection: new_error_injection}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        active_programs: map_size(state.programs),
        total_executions: map_size(state.executions),
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.stats.uptime_start, :second)
      })

    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_call(:get_programs, _from, state) do
    {:reply, state.programs, state}
  end

  @impl true
  def handle_call(:get_executions, _from, state) do
    {:reply, state.executions, state}
  end

  @impl true
  def handle_call({:command, command, args}, _from, state) do
    # Check for error injection
    case should_inject_error?(state.error_injection, command) do
      {:error, error_type, message} ->
        new_stats = update_in(state.stats, [:errors_injected], &(&1 + 1))
        {:reply, {:error, {error_type, message}}, %{state | stats: new_stats}}

      :ok ->
        # Simulate performance delay if configured
        maybe_simulate_delay(state.config, command)

        # Execute command
        case handle_command(command, args, state) do
          {:ok, result, new_state} ->
            {:reply, {:ok, result}, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  # Command Handlers
  defp handle_command(:ping, _args, state) do
    result = %{
      status: "ok",
      adapter: "mock",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, result, state}
  end

  defp handle_command(:create_program, args, state) do
    program_id = Map.get(args, :id) || Map.get(args, "id") || generate_program_id()
    signature = Map.get(args, :signature) || Map.get(args, "signature")

    if signature do
      program_state = %{
        id: program_id,
        signature: signature,
        created_at: DateTime.utc_now(),
        executions: 0
      }

      new_programs = Map.put(state.programs, program_id, program_state)
      new_stats = update_in(state.stats, [:programs_created], &(&1 + 1))

      result = %{
        program_id: program_id,
        status: "created",
        signature: signature
      }

      {:ok, result, %{state | programs: new_programs, stats: new_stats}}
    else
      {:error, "Program signature is required", state}
    end
  end

  defp handle_command(:execute_program, args, state) do
    program_id = Map.get(args, :program_id) || Map.get(args, "program_id")
    inputs = Map.get(args, :inputs) || Map.get(args, "inputs") || %{}

    # Check if LM is configured (mimic real behavior)
    case state.lm_config do
      nil ->
        {:error, "No LM is loaded.", state}

      _config ->
        case Map.get(state.programs, program_id) do
          nil ->
            {:error, "Program not found: #{program_id}", state}

          program ->
            execution_id = generate_execution_id()

            # Generate mock response based on signature
            result = generate_mock_response(program.signature, inputs, state.scenarios)

            execution_record = %{
              id: execution_id,
              program_id: program_id,
              inputs: inputs,
              result: result,
              executed_at: DateTime.utc_now()
            }

            # Update state
            new_executions = Map.put(state.executions, execution_id, execution_record)
            updated_program = update_in(program, [:executions], &(&1 + 1))
            new_programs = Map.put(state.programs, program_id, updated_program)
            new_stats = update_in(state.stats, [:executions_run], &(&1 + 1))

            new_state = %{
              state
              | executions: new_executions,
                programs: new_programs,
                stats: new_stats
            }

            {:ok, result, new_state}
        end
    end
  end

  defp handle_command(:list_programs, _args, state) do
    programs =
      state.programs
      |> Enum.map(fn {id, program} ->
        %{
          id: id,
          signature: program.signature,
          created_at: program.created_at,
          executions: program.executions
        }
      end)

    result = %{programs: programs}
    {:ok, result, state}
  end

  defp handle_command(:get_program_info, args, state) do
    program_id = Map.get(args, :program_id) || Map.get(args, "program_id")

    case Map.get(state.programs, program_id) do
      nil ->
        {:error, "Program not found: #{program_id}", state}

      program ->
        {:ok, program, state}
    end
  end

  defp handle_command(:delete_program, args, state) do
    program_id = Map.get(args, :program_id) || Map.get(args, "program_id")

    case Map.get(state.programs, program_id) do
      nil ->
        {:error, "Program not found: #{program_id}", state}

      _program ->
        new_programs = Map.delete(state.programs, program_id)
        result = %{status: "deleted", program_id: program_id}
        {:ok, result, %{state | programs: new_programs}}
    end
  end

  defp handle_command(:get_stats, _args, state) do
    stats = %{
      programs_created: state.stats.programs_created,
      executions_run: state.stats.executions_run,
      active_programs: map_size(state.programs),
      total_executions: map_size(state.executions),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.stats.uptime_start, :second),
      adapter_type: "mock"
    }

    {:ok, stats, state}
  end

  defp handle_command(:configure_lm, config, state) do
    # Store the LM configuration
    result = %{
      status: "configured",
      model: Map.get(config, :model) || Map.get(config, "model"),
      provider: Map.get(config, :provider) || Map.get(config, "provider", "mock"),
      temperature: Map.get(config, :temperature) || Map.get(config, "temperature", 0.7)
    }

    {:ok, result, %{state | lm_config: config}}
  end

  # Helper Functions
  defp build_config(opts) do
    default_config = %{
      response_delay_ms: 0,
      error_rate: 0.0,
      deterministic: true,
      mock_responses: %{}
    }

    app_config = Application.get_env(:dspex, :mock_adapter, %{})

    default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end

  defp should_inject_error?(error_injection, command) do
    case Map.get(error_injection, command) do
      nil ->
        :ok

      %{probability: prob, type: type, message: message} ->
        if :rand.uniform() < prob do
          {:error, type, message}
        else
          :ok
        end

      %{always: true, type: type, message: message} ->
        {:error, type, message}

      _ ->
        :ok
    end
  end

  defp maybe_simulate_delay(config, _command) do
    delay_ms = Map.get(config, :response_delay_ms, 0)

    if delay_ms > 0 do
      Process.sleep(delay_ms)
    end
  end

  defp generate_mock_response(signature, inputs, scenarios) do
    # Handle both signature modules and signature maps
    signature_data = extract_signature_data(signature)
    outputs = Map.get(signature_data, "outputs") || Map.get(signature_data, :outputs) || []

    # Generate deterministic responses based on input types and configured scenarios
    Enum.reduce(outputs, %{}, fn output, acc ->
      # Output should already be a map from convert_fields_to_map
      output_name =
        case output do
          %{"name" => name} -> name
          %{:name => name} -> to_string(name)
          {name, _type} when is_atom(name) -> to_string(name)
          {name, _type, _constraints} when is_atom(name) -> to_string(name)
          _ -> "unknown"
        end

      output_type =
        case output do
          %{"type" => type} -> type
          %{:type => type} -> to_string(type)
          {_name, type} when is_atom(type) -> convert_type_to_string(type)
          {_name, type, _constraints} -> convert_type_to_string(type)
          _ -> "string"
        end

      mock_value = generate_mock_value(output_type, inputs, scenarios, output_name)
      Map.put(acc, output_name, mock_value)
    end)
  end

  # Extract signature data from either module or map
  defp extract_signature_data(signature) when is_atom(signature) do
    # Handle signature module - call __signature__() function
    if function_exported?(signature, :__signature__, 0) do
      signature.__signature__()
    else
      # Fallback - try to get signature from metadata
      case signature.__info__(:attributes) do
        attributes when is_list(attributes) ->
          case Keyword.get(attributes, :signature_ast) do
            [{signature_ast, _}] -> convert_ast_to_map(signature_ast)
            _ -> %{}
          end

        _ ->
          %{}
      end
    end
  end

  defp extract_signature_data(signature) when is_map(signature) do
    # Handle signature map directly
    signature
  end

  defp extract_signature_data(_signature) do
    # Default fallback
    %{}
  end

  # Convert signature AST to map format
  defp convert_ast_to_map({:->, _, [inputs, outputs]}) do
    %{
      "inputs" => convert_fields_to_map(inputs),
      "outputs" => convert_fields_to_map(outputs)
    }
  end

  defp convert_ast_to_map(_) do
    %{}
  end

  defp convert_fields_to_map(fields) when is_list(fields) do
    Enum.map(fields, fn
      {name, type, _constraints} when is_atom(name) ->
        %{"name" => to_string(name), "type" => convert_type_to_string(type)}

      {name, type} when is_atom(name) ->
        %{"name" => to_string(name), "type" => convert_type_to_string(type)}

      _ ->
        %{"name" => "unknown", "type" => "string"}
    end)
  end

  defp convert_fields_to_map(_) do
    []
  end

  defp convert_type_to_string(:string), do: "string"
  defp convert_type_to_string(:integer), do: "int"
  defp convert_type_to_string(:float), do: "float"
  defp convert_type_to_string(:boolean), do: "bool"
  defp convert_type_to_string(:probability), do: "float"
  defp convert_type_to_string({:list, inner}), do: "List[#{convert_type_to_string(inner)}]"
  defp convert_type_to_string(type) when is_atom(type), do: to_string(type)
  defp convert_type_to_string(_), do: "string"

  defp generate_mock_value("string", inputs, scenarios, field_name) do
    # Check for scenario-specific responses
    case get_scenario_response(scenarios, field_name) do
      nil ->
        # Generate deterministic response based on inputs
        input_hash = :erlang.phash2(inputs)
        "mock_response_#{field_name}_#{input_hash}"

      response ->
        response
    end
  end

  defp generate_mock_value("int" <> _, inputs, _scenarios, _field_name) do
    :erlang.phash2(inputs) |> rem(1000)
  end

  defp generate_mock_value("float" <> _, inputs, _scenarios, _field_name) do
    (:erlang.phash2(inputs) |> rem(1000)) / 10.0
  end

  defp generate_mock_value("bool" <> _, inputs, _scenarios, _field_name) do
    :erlang.phash2(inputs) |> rem(2) == 0
  end

  defp generate_mock_value(_, inputs, _scenarios, field_name) do
    # Default to string response
    input_hash = :erlang.phash2(inputs)
    "mock_#{field_name}_#{input_hash}"
  end

  defp get_scenario_response(scenarios, field_name) do
    scenarios
    |> Enum.find_value(fn {_name, config} ->
      Map.get(config, field_name)
    end)
  end

  defp generate_program_id do
    "mock_program_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_execution_id do
    "mock_execution_#{:erlang.unique_integer([:positive])}"
  end

  # Test layer support

  @impl true
  def supports_test_layer?(layer), do: layer == :layer_1

  @impl true
  def get_test_capabilities do
    %{
      deterministic_outputs: true,
      call_logging: true,
      fast_execution: true,
      python_execution: false,
      protocol_validation: false,
      performance: :fastest,
      error_injection: true,
      scenario_testing: true,
      state_management: true,
      concurrent_safe: true
    }
  end
end

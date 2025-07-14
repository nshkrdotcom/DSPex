defmodule DSPex.Adapters.BridgeMock do
  @moduledoc """
  Bridge mock adapter for testing bridge protocol without Python.

  This adapter simulates the Python bridge by providing deterministic mock responses
  while validating the bridge protocol format. It's designed for Layer 2 testing
  where you want to test wire protocol correctness without requiring Python.

  ## Features

  - Protocol-accurate JSON communication simulation
  - Deterministic outputs for reliable testing
  - Configurable response delays and error scenarios
  - Fast execution without Python overhead
  - Memory-based program storage

  ## Usage

      # Through the registry (recommended)
      adapter = DSPex.Adapters.Registry.get_adapter(:bridge_mock)
      {:ok, program_id} = adapter.create_program(%{signature: %{...}})

      # Direct usage
      {:ok, result} = DSPex.Adapters.BridgeMock.execute_program("program_id", %{input: "test"})
  """

  @behaviour DSPex.Adapters.Adapter

  use GenServer
  require Logger

  # State structure
  defstruct [
    :programs,
    :config,
    :stats,
    :error_scenarios
  ]

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # Core adapter operations

  @impl true
  def create_program(config) do
    with :ok <- ensure_server_started() do
      program_id = Map.get(config, :id) || Map.get(config, "id") || generate_program_id()
      signature = Map.get(config, :signature) || Map.get(config, "signature")

      request = %{
        command: "create_program",
        args: %{
          id: program_id,
          signature: signature
        }
      }

      case send_mock_command(request) do
        {:ok, response} ->
          {:ok, Map.get(response, "program_id") || Map.get(response, :program_id)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def execute_program(program_id, inputs) do
    with :ok <- ensure_server_started() do
      request = %{
        command: "execute_program",
        args: %{
          program_id: program_id,
          inputs: inputs
        }
      }

      send_mock_command(request)
    end
  end

  @impl true
  def list_programs do
    with :ok <- ensure_server_started() do
      request = %{command: "list_programs", args: %{}}

      case send_mock_command(request) do
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
  end

  @impl true
  def delete_program(program_id) do
    with :ok <- ensure_server_started() do
      request = %{
        command: "delete_program",
        args: %{program_id: program_id}
      }

      case send_mock_command(request) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Optional callbacks

  @impl true
  def get_program_info(program_id) do
    with :ok <- ensure_server_started() do
      request = %{
        command: "get_program_info",
        args: %{program_id: program_id}
      }

      send_mock_command(request)
    end
  end

  @impl true
  def health_check do
    with :ok <- ensure_server_started() do
      request = %{command: "ping", args: %{}}

      case send_mock_command(request) do
        {:ok, %{"status" => "ok"}} -> :ok
        {:ok, %{status: "ok"}} -> :ok
        {:error, reason} -> {:error, reason}
        _ -> {:error, :unhealthy}
      end
    end
  end

  @impl true
  def get_stats do
    with :ok <- ensure_server_started() do
      request = %{command: "get_stats", args: %{}}

      case send_mock_command(request) do
        {:ok, stats} -> {:ok, stats}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Test layer support

  @impl true
  def supports_test_layer?(layer), do: layer == :layer_2

  @impl true
  def get_test_capabilities do
    %{
      layer: :layer_2,
      protocol_testing: true,
      protocol_validation: true,
      wire_format_testing: true,
      wire_format_validation: true,
      python_execution: false,
      error_injection: true,
      performance: :fast,
      deterministic: true,
      deterministic_outputs: true,
      scenario_testing: true,
      concurrency_safe: true
    }
  end

  # Configuration and error injection

  def configure(config) do
    with :ok <- ensure_server_started() do
      GenServer.call(__MODULE__, {:configure, config})
    end
  end

  def add_error_scenario(scenario) do
    with :ok <- ensure_server_started() do
      case GenServer.call(__MODULE__, {:add_error_scenario, scenario}) do
        {:ok, _scenario_id} -> :ok
        error -> error
      end
    end
  end

  def reset do
    with :ok <- ensure_server_started() do
      GenServer.call(__MODULE__, :reset)
    end
  end

  # Private functions

  defp ensure_server_started do
    case Process.whereis(__MODULE__) do
      nil ->
        Logger.debug("Starting BridgeMock adapter")

        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp send_mock_command(request) do
    GenServer.call(__MODULE__, {:mock_command, request})
  end

  defp generate_program_id do
    "bridge_mock_program_#{:erlang.unique_integer([:positive])}"
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    config = %{
      response_delay_ms: Keyword.get(opts, :response_delay_ms, 0),
      error_rate: Keyword.get(opts, :error_rate, 0.0),
      deterministic: Keyword.get(opts, :deterministic, true)
    }

    state = %__MODULE__{
      programs: %{},
      config: config,
      stats: %{
        requests_received: 0,
        responses_sent: 0,
        errors_triggered: 0,
        start_time: DateTime.utc_now()
      },
      error_scenarios: %{}
    }

    {:ok, state}
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
  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | programs: %{},
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
  def handle_call({:mock_command, request}, _from, state) do
    command = Map.get(request, :command) || Map.get(request, "command")
    args = Map.get(request, :args) || Map.get(request, "args", %{})

    # Update stats
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

  # Mock response generation

  defp generate_mock_response("ping", _args, state) do
    response = %{
      status: "ok",
      server: "bridge_mock",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, response, state}
  end

  defp generate_mock_response("create_program", args, state) do
    program_id = Map.get(args, "id") || Map.get(args, :id) || generate_program_id()
    signature = Map.get(args, "signature") || Map.get(args, :signature)

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
    program_id = Map.get(args, "program_id") || Map.get(args, :program_id)
    inputs = Map.get(args, "inputs") || Map.get(args, :inputs, %{})

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
      server_type: "bridge_mock",
      adapter_type: :bridge_mock,
      layer: :layer_2,
      protocol_validated: true,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.stats.start_time, :second)
    }

    {:ok, response, state}
  end

  defp generate_mock_response("delete_program", args, state) do
    program_id = Map.get(args, "program_id") || Map.get(args, :program_id)

    case Map.get(state.programs, program_id) do
      nil ->
        {:error, "Program not found: #{program_id}", state}

      _program ->
        new_programs = Map.delete(state.programs, program_id)

        response = %{
          status: "deleted",
          program_id: program_id
        }

        {:ok, response, %{state | programs: new_programs}}
    end
  end

  defp generate_mock_response("get_program_info", args, state) do
    program_id = Map.get(args, "program_id") || Map.get(args, :program_id)

    case Map.get(state.programs, program_id) do
      nil ->
        {:error, "Program not found: #{program_id}", state}

      program ->
        {:ok, program, state}
    end
  end

  defp generate_mock_response(command, _args, state) do
    {:error, "Unknown command: #{command}", state}
  end

  defp generate_signature_outputs(signature, inputs) do
    # Extract signature data (handle both modules and maps)
    signature_data = extract_signature_data(signature)
    outputs = Map.get(signature_data, :outputs) || Map.get(signature_data, "outputs") || []
    input_hash = :erlang.phash2(inputs)

    Enum.reduce(outputs, %{}, fn output, acc ->
      # Handle both map and tuple formats
      {name, type} =
        case output do
          %{"name" => name, "type" => type} ->
            {name, type}

          %{:name => name, :type => type} ->
            {to_string(name), to_string(type)}

          {name, type} when is_atom(name) ->
            {to_string(name), convert_type_to_string(type)}

          {name, type, _constraints} when is_atom(name) ->
            {to_string(name), convert_type_to_string(type)}

          _ ->
            {"unknown", "string"}
        end

      mock_value =
        case type do
          "string" -> "bridge_mock_#{name}_#{input_hash}"
          "int" -> rem(input_hash, 1000)
          "float" -> rem(input_hash, 1000) / 10.0
          "bool" -> rem(input_hash, 2) == 0
          _ -> "bridge_mock_#{name}_#{input_hash}"
        end

      Map.put(acc, name, mock_value)
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
end

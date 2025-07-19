defmodule ElixirML.Process.ProgramWorker do
  @moduledoc """
  GenServer worker for executing individual programs.
  Handles program lifecycle, execution, and state management.
  """

  use GenServer
  require Logger

  defstruct [
    :program,
    :program_id,
    :variable_configuration,
    :execution_history,
    :performance_metrics,
    :status,
    :started_at
  ]

  def start_link(opts) do
    program = Keyword.fetch!(opts, :program)
    program_id = Keyword.get(opts, :program_id, generate_program_id())

    GenServer.start_link(__MODULE__, %{
      program: program,
      program_id: program_id,
      opts: opts
    })
  end

  def init(%{program: program, program_id: program_id, opts: opts}) do
    state = %__MODULE__{
      program: program,
      program_id: program_id,
      variable_configuration: Keyword.get(opts, :variable_configuration, %{}),
      execution_history: [],
      performance_metrics: %{},
      status: :initialized,
      started_at: System.monotonic_time(:millisecond)
    }

    # Register with variable registry if space is available
    if program.variable_space do
      ElixirML.Process.VariableRegistry.register_space(
        "#{program_id}_space",
        program.variable_space
      )
    end

    {:ok, state}
  end

  @doc """
  Execute the program with given inputs.
  """
  def execute(pid, inputs, opts \\ []) do
    GenServer.call(pid, {:execute, inputs, opts})
  end

  @doc """
  Update the program's variable configuration.
  """
  def update_configuration(pid, new_config) do
    GenServer.call(pid, {:update_configuration, new_config})
  end

  @doc """
  Get program information and status.
  """
  def get_program_info(pid) do
    GenServer.call(pid, :get_program_info)
  end

  @doc """
  Get program performance metrics.
  """
  def get_performance_metrics(pid) do
    GenServer.call(pid, :get_performance_metrics)
  end

  # Server callbacks

  def handle_call({:execute, inputs, opts}, _from, state) do
    execution_start = System.monotonic_time(:millisecond)

    try do
      # Validate inputs against program signature
      validated_inputs = validate_inputs(state.program, inputs)

      # Apply variable configuration
      execution_config = merge_configurations(state.variable_configuration, opts)

      # Execute the program
      result = execute_program_logic(state.program, validated_inputs, execution_config)

      execution_end = System.monotonic_time(:millisecond)
      execution_time = execution_end - execution_start

      # Record execution history
      execution_record = %{
        inputs: inputs,
        result: result,
        execution_time_ms: execution_time,
        timestamp: execution_start,
        status: :success
      }

      # Update metrics
      new_metrics = update_performance_metrics(state.performance_metrics, execution_record)

      new_state = %{
        state
        | execution_history: [execution_record | state.execution_history],
          performance_metrics: new_metrics,
          status: :active
      }

      {:reply, {:ok, result}, new_state}
    catch
      error_type, error ->
        execution_end = System.monotonic_time(:millisecond)
        execution_time = execution_end - execution_start

        error_record = %{
          inputs: inputs,
          error: {error_type, error},
          execution_time_ms: execution_time,
          timestamp: execution_start,
          status: :error
        }

        Logger.error("Program execution failed: #{inspect(error)}")

        new_state = %{
          state
          | execution_history: [error_record | state.execution_history],
            status: :error
        }

        {:reply, {:error, error}, new_state}
    end
  end

  def handle_call({:update_configuration, new_config}, _from, state) do
    # Validate new configuration against variable space
    case validate_configuration(state.program.variable_space, new_config) do
      {:ok, validated_config} ->
        new_state = %{state | variable_configuration: validated_config}
        {:reply, {:ok, validated_config}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_program_info, _from, state) do
    info = %{
      program_id: state.program_id,
      status: state.status,
      started_at: state.started_at,
      execution_count: length(state.execution_history),
      current_configuration: state.variable_configuration,
      performance_summary: summarize_performance(state.performance_metrics)
    }

    {:reply, {:ok, info}, state}
  end

  def handle_call(:get_performance_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end

  # Private functions

  defp generate_program_id do
    "prog_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp validate_inputs(_program, inputs) do
    # TODO: Implement signature-based input validation
    # For now, just return inputs as-is
    inputs
  end

  defp merge_configurations(base_config, execution_opts) do
    execution_config = Keyword.get(execution_opts, :config, %{})
    Map.merge(base_config, execution_config)
  end

  defp execute_program_logic(_program, inputs, config) do
    # TODO: Implement actual program execution logic
    # This is a placeholder that simulates program execution

    # Simulate some processing time
    Process.sleep(Enum.random(10..100))

    # Return a mock result
    %{
      output: "Processed: #{inspect(inputs)}",
      config_used: config,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  defp validate_configuration(nil, _config), do: {:ok, %{}}

  defp validate_configuration(variable_space, config) do
    ElixirML.Variable.Space.validate_configuration(variable_space, config)
  end

  defp update_performance_metrics(current_metrics, execution_record) do
    case execution_record.status do
      :success ->
        execution_times = Map.get(current_metrics, :execution_times, [])
        new_times = [execution_record.execution_time_ms | execution_times] |> Enum.take(100)

        %{
          current_metrics
          | execution_times: new_times,
            total_executions: Map.get(current_metrics, :total_executions, 0) + 1,
            successful_executions: Map.get(current_metrics, :successful_executions, 0) + 1,
            average_execution_time: Enum.sum(new_times) / length(new_times),
            last_execution_time: execution_record.execution_time_ms
        }

      :error ->
        %{
          current_metrics
          | total_executions: Map.get(current_metrics, :total_executions, 0) + 1,
            failed_executions: Map.get(current_metrics, :failed_executions, 0) + 1
        }
    end
  end

  defp summarize_performance(metrics) do
    %{
      total_executions: Map.get(metrics, :total_executions, 0),
      success_rate: calculate_success_rate(metrics),
      average_execution_time: Map.get(metrics, :average_execution_time, 0),
      last_execution_time: Map.get(metrics, :last_execution_time, 0)
    }
  end

  defp calculate_success_rate(metrics) do
    total = Map.get(metrics, :total_executions, 0)
    successful = Map.get(metrics, :successful_executions, 0)

    if total > 0 do
      successful / total
    else
      0.0
    end
  end
end

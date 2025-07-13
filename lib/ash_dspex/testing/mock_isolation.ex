defmodule AshDSPex.Testing.MockIsolation do
  import ExUnit.Callbacks, only: [on_exit: 1]

  @moduledoc """
  Provides isolated Mock adapter instances for testing.

  This module helps create isolated Mock adapter processes for each test,
  preventing state leakage between tests and enabling safe async testing.

  ## Usage in Tests

      use AshDSPex.Testing.MockIsolation
      
      test "my test" do
        # Automatically gets an isolated mock adapter
        {:ok, program_id} = Mock.create_program(%{...})
        {:ok, result} = Mock.execute_program(program_id, %{})
      end
  """

  alias AshDSPex.Adapters.Mock

  @doc """
  Starts an isolated Mock adapter for a test.

  Returns a context that includes the mock process and helper functions.
  """
  def setup_isolated_mock(_context \\ %{}) do
    # Generate a unique name for this test's mock adapter
    test_id = :erlang.unique_integer([:positive])
    mock_name = :"mock_adapter_test_#{test_id}"

    # Start an isolated mock adapter
    {:ok, pid} = Mock.start_link(name: mock_name)

    # Store the current process's mock adapter name
    Process.put(:test_mock_name, mock_name)

    on_exit(fn ->
      # Clean up the mock adapter when test finishes
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    {:ok, %{mock_pid: pid, mock_name: mock_name}}
  end

  @doc """
  Gets the mock adapter name for the current test process.
  """
  def current_mock_name do
    Process.get(:test_mock_name, AshDSPex.Adapters.Mock)
  end

  @doc """
  Runs a function in a new process with the current test's mock context.
  Useful for Task.async operations.
  """
  def with_mock_context(fun) do
    mock_name = current_mock_name()

    fn ->
      Process.put(:test_mock_name, mock_name)
      fun.()
    end
  end

  defmacro __using__(_opts) do
    quote do
      import AshDSPex.Testing.MockIsolation
      setup :setup_isolated_mock

      # Override Mock module in this context to use isolated instance
      alias AshDSPex.Testing.MockIsolation.IsolatedMock, as: Mock
    end
  end
end

defmodule AshDSPex.Testing.MockIsolation.IsolatedMock do
  @moduledoc false
  # Wrapper module that delegates to the test-specific Mock instance

  alias AshDSPex.Testing.MockIsolation

  def create_program(config) do
    mock_name = MockIsolation.current_mock_name()

    GenServer.call(mock_name, {:command, :create_program, config})
    |> handle_response()
  end

  def execute_program(program_id, inputs) do
    mock_name = MockIsolation.current_mock_name()

    GenServer.call(
      mock_name,
      {:command, :execute_program, %{program_id: program_id, inputs: inputs}}
    )
  end

  def list_programs do
    mock_name = MockIsolation.current_mock_name()

    case GenServer.call(mock_name, {:command, :list_programs, %{}}) do
      {:ok, %{programs: programs}} ->
        program_ids = Enum.map(programs, fn p -> Map.get(p, :id) end)
        {:ok, program_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_program(program_id) do
    mock_name = MockIsolation.current_mock_name()

    case GenServer.call(
           mock_name,
           {:command, :delete_program, %{program_id: program_id}}
         ) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def reset do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, :reset)
  end

  def configure(config) do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, {:configure, config})
  end

  def health_check do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, {:command, :health_check, %{}})
  end

  def get_stats do
    mock_name = MockIsolation.current_mock_name()
    {:ok, GenServer.call(mock_name, :get_stats)}
  end

  def get_test_capabilities do
    AshDSPex.Adapters.Mock.get_test_capabilities()
  end

  def supports_test_layer?(layer) do
    AshDSPex.Adapters.Mock.supports_test_layer?(layer)
  end

  def ping do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, {:command, :ping, %{}})
  end

  def get_program_info(program_id) do
    mock_name = MockIsolation.current_mock_name()

    GenServer.call(
      mock_name,
      {:command, :get_program_info, %{program_id: program_id}}
    )
  end

  def set_scenario(scenario_name, scenario_config) do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, {:set_scenario, scenario_name, scenario_config})
  end

  def inject_error(error_config) do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, {:inject_error, error_config})
  end

  def get_programs do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, :get_programs)
  end

  def get_executions do
    mock_name = MockIsolation.current_mock_name()
    GenServer.call(mock_name, :get_executions)
  end

  # Private helper
  defp handle_response({:ok, %{program_id: program_id}}), do: {:ok, program_id}
  defp handle_response({:error, reason}), do: {:error, reason}
  defp handle_response(response), do: response
end

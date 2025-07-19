defmodule DSPex.PythonBridge.ConditionalSupervisor do
  @moduledoc """
  A conditional supervisor that only starts the Python bridge if the environment is available.

  This supervisor will start the Python bridge components only if:
  1. Python bridge is explicitly enabled in configuration
  2. Python environment validation passes

  If the environment is not available, it will start as an empty supervisor.
  """

  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    children =
      case determine_bridge_mode(opts) do
        :pool ->
          Logger.info("Starting Python bridge pool supervisor")
          # Use enhanced supervisor that supports both V2 and V3
          [DSPex.PythonBridge.EnhancedPoolSupervisor]

        :single ->
          Logger.info("Starting Python bridge supervisor (single mode)")
          [DSPex.PythonBridge.Supervisor]

        :disabled ->
          Logger.info("Python bridge disabled or environment not available")
          []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp determine_bridge_mode(opts) do
    # Check if pooling is enabled
    pooling_enabled =
      Keyword.get(opts, :pooling_enabled, Application.get_env(:dspex, :pooling_enabled, false))

    cond do
      not should_start_bridge?(opts) -> :disabled
      pooling_enabled -> :pool
      true -> :single
    end
  end

  defp should_start_bridge?(opts) do
    # In test environment, check test mode first
    if Mix.env() == :test do
      case get_test_mode() do
        :mock_adapter ->
          Logger.info("Test mode: mock_adapter - Python bridge disabled")
          false

        :bridge_mock ->
          Logger.info("Test mode: bridge_mock - Python bridge disabled")
          false

        :full_integration ->
          Logger.info("Test mode: full_integration - Python bridge enabled")
          validate_and_start_bridge()

        _ ->
          # Default test behavior
          validate_and_start_bridge()
      end
    else
      # Production/dev environment - use original logic
      case Keyword.get(
             opts,
             :enabled,
             Application.get_env(:dspex, :python_bridge_enabled, :auto)
           ) do
        false ->
          false

        true ->
          true

        :auto ->
          validate_and_start_bridge()
      end
    end
  end

  defp get_test_mode do
    case System.get_env("TEST_MODE") do
      nil ->
        Application.get_env(:dspex, :test_mode, :full_integration)

      env_mode ->
        try do
          String.to_existing_atom(env_mode)
        rescue
          ArgumentError ->
            :full_integration
        end
    end
  end

  defp validate_and_start_bridge do
    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
      {:ok, _} ->
        Logger.info("Python environment validated, starting bridge")
        true

      {:error, reason} ->
        Logger.info("Python bridge not started: #{reason}")
        false
    end
  end
end

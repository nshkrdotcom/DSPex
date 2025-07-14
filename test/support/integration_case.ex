defmodule DSPex.IntegrationCase do
  @moduledoc """
  This module defines the test case to be used by
  integration tests that require the Python bridge.

  It ensures proper startup sequence:
  1. Application is started
  2. Python bridge/pool is available
  3. Language model is configured
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import DSPex.IntegrationCase

      setup :ensure_integration_ready
    end
  end

  @doc """
  Ensures the integration environment is ready.

  This includes:
  - Waiting for application startup
  - Ensuring Python bridge/pool is running
  - Configuring language model
  """
  def ensure_integration_ready(_context) do
    # First ensure the application is started
    case Application.ensure_all_started(:dspex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :dspex}} -> :ok
      error -> flunk("Failed to start application: #{inspect(error)}")
    end

    # Wait for pool to be available (if in pool mode)
    if Application.get_env(:dspex, :pooling_enabled, false) do
      ensure_pool_ready()
    else
      ensure_bridge_ready()
    end

    # Now configure language model
    configure_lm_for_tests()

    :ok
  end

  defp ensure_pool_ready(retries \\ 10) do
    case Process.whereis(DSPex.PythonBridge.SessionPool) do
      nil when retries > 0 ->
        Process.sleep(100)
        ensure_pool_ready(retries - 1)

      nil ->
        flunk("SessionPool not started after waiting")

      _pid ->
        # Pool is ready, give it a moment to fully initialize
        Process.sleep(100)
        :ok
    end
  end

  defp ensure_bridge_ready(retries \\ 10) do
    case Process.whereis(DSPex.PythonBridge.Bridge) do
      nil when retries > 0 ->
        Process.sleep(100)
        ensure_bridge_ready(retries - 1)

      nil ->
        flunk("Python bridge not started after waiting")

      _pid ->
        # Bridge is ready
        :ok
    end
  end

  defp configure_lm_for_tests do
    # Apply any pending LM configuration
    DSPex.LMTestSetup.apply_pending_config()
  end
end

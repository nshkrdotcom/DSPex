defmodule DSPex.LMTestSetup do
  @moduledoc """
  Language Model configuration for tests.

  Provides proper LM setup based on test mode to ensure all tests
  can execute DSPy programs successfully.
  """

  @doc """
  Sets up the language model configuration for tests.

  Returns :ok after configuring the appropriate adapter with LM settings.
  """
  def setup_lm do
    test_mode = Application.get_env(:dspex, :test_mode, :mock_adapter)

    case test_mode do
      :full_integration ->
        setup_real_lm()

      _ ->
        setup_mock_lm()
    end
  end

  defp setup_real_lm do
    case System.get_env("GEMINI_API_KEY") do
      nil ->
        # Fall back to mock if no API key
        setup_mock_lm()

      api_key ->
        # Configure real Gemini LM
        config = %{
          model: "gemini-1.5-flash",
          api_key: api_key,
          temperature: 0.5,
          provider: :google
        }

        # Store config for later use - don't try to configure yet
        Application.put_env(:dspex, :pending_lm_config, config)
        :ok
    end
  end

  defp setup_mock_lm do
    # Configure mock LM
    config = %{
      model: "mock",
      provider: :mock,
      api_key: "mock-key",
      temperature: 0.7
    }

    # Store config for later use - don't try to configure yet
    Application.put_env(:dspex, :pending_lm_config, config)
    :ok
  end

  @doc """
  Ensures LM is configured for a specific adapter.
  """
  def ensure_lm_configured(adapter) do
    # Check if we have a default LM config
    default_lm = Application.get_env(:dspex, :default_lm)

    if default_lm do
      adapter.configure_lm(default_lm)
    else
      # Configure based on test mode
      setup_lm()
    end
  end

  @doc """
  Applies pending LM configuration after application startup.
  This should be called from test setup callbacks, not test_helper.exs.
  """
  def apply_pending_config do
    case Application.get_env(:dspex, :pending_lm_config) do
      nil ->
        :ok

      config ->
        # Remove the pending config
        Application.delete_env(:dspex, :pending_lm_config)

        # Try to configure the adapter
        adapter = DSPex.Adapters.Registry.get_adapter()

        if adapter && function_exported?(adapter, :configure_lm, 1) do
          case adapter.configure_lm(config) do
            :ok ->
              :ok

            {:error, reason} ->
              IO.warn("Failed to configure LM: #{inspect(reason)}")
              :ok
          end
        else
          :ok
        end
    end
  end
end

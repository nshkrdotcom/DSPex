# Load test support modules
Code.require_file("support/supervision_test_helpers.ex", __DIR__)
Code.require_file("support/bridge_test_helpers.ex", __DIR__)
Code.require_file("support/monitor_test_helpers.ex", __DIR__)
Code.require_file("support/unified_test_foundation.ex", __DIR__)
Code.require_file("support/testing/test_mode.ex", __DIR__)
Code.require_file("support/testing/bridge_mock_server.ex", __DIR__)
Code.require_file("support/testing/mock_isolation.ex", __DIR__)
Code.require_file("support/mock_port.ex", __DIR__)
Code.require_file("support/pool_worker_helpers.ex", __DIR__)
Code.require_file("support/test_data_generators.ex", __DIR__)
Code.require_file("support/lm_test_setup.ex", __DIR__)
Code.require_file("support/integration_case.ex", __DIR__)

# Enable Python bridge for tests when GEMINI_API_KEY is available
gemini_key = System.get_env("GEMINI_API_KEY")
bridge_enabled = gemini_key != nil and gemini_key != ""
Application.put_env(:dspex, :python_bridge_enabled, bridge_enabled)

# Configure pooling based on test mode
test_mode = System.get_env("TEST_MODE", "mock_adapter") |> String.to_atom()
pooling_enabled = test_mode == :full_integration
Application.put_env(:dspex, :pooling_enabled, pooling_enabled)
# Small pool for tests
Application.put_env(:dspex, :pool_size, 2)
Application.put_env(:dspex, :pool_mode, :test)
# Store test mode for use by other modules
Application.put_env(:dspex, :test_mode, test_mode)

# Configure default LM for tests
case test_mode do
  :full_integration ->
    # Configure real LM for integration tests if API key is available
    if gemini_key do
      Application.put_env(:dspex, :default_lm, %{
        model: "gemini-1.5-flash",
        api_key: gemini_key,
        # Lower for more consistent tests
        temperature: 0.5
      })
    end

  _ ->
    # Configure mock LM for unit tests
    Application.put_env(:dspex, :default_lm, %{
      model: "mock",
      provider: "mock",
      api_key: "mock-key",
      temperature: 0.7
    })
end

if bridge_enabled do
  IO.puts("🚀 Python bridge enabled for testing with Gemini")
else
  IO.puts("⚠️ Python bridge disabled - set GEMINI_API_KEY to enable")
end

# Configure test exclusions based on TEST_MODE

exclude_tags =
  case test_mode do
    :mock_adapter ->
      # Layer 1: Only run pure Elixir tests (mock adapter), exclude bridge and protocol tests  
      [:layer_2, :layer_3]

    :bridge_mock ->
      # Layer 2: Run protocol tests but exclude full integration
      [:layer_3]

    :full_integration ->
      # Layer 3: Run all tests including full Python bridge integration
      []
  end

IO.puts("🧪 Test mode: #{test_mode} (excluding: #{inspect(exclude_tags)})")

# Set up language model configuration for tests (stores config for later application)
DSPex.LMTestSetup.setup_lm()

# Start ExUnit with excluded tags
ExUnit.start(exclude: exclude_tags)

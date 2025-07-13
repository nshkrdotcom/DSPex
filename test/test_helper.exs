# Load test support modules
Code.require_file("support/supervision_test_helpers.ex", __DIR__)
Code.require_file("support/bridge_test_helpers.ex", __DIR__)
Code.require_file("support/monitor_test_helpers.ex", __DIR__)
Code.require_file("support/unified_test_foundation.ex", __DIR__)
Code.require_file("support/testing/test_mode.ex", __DIR__)
Code.require_file("support/testing/bridge_mock_server.ex", __DIR__)
Code.require_file("support/testing/mock_isolation.ex", __DIR__)

# Enable Python bridge for tests when GEMINI_API_KEY is available
gemini_key = System.get_env("GEMINI_API_KEY")
bridge_enabled = gemini_key != nil and gemini_key != ""
Application.put_env(:dspex, :python_bridge_enabled, bridge_enabled)

if bridge_enabled do
  IO.puts("🚀 Python bridge enabled for testing with Gemini")
else
  IO.puts("⚠️ Python bridge disabled - set GEMINI_API_KEY to enable")
end

# Configure test exclusions based on TEST_MODE
test_mode = System.get_env("TEST_MODE", "mock_adapter") |> String.to_atom()

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

ExUnit.start(exclude: exclude_tags)

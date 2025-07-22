# Load support files before ExUnit starts
Code.require_file("support/state_provider_test.exs", __DIR__)

ExUnit.start(exclude: [:live])

# Configure test mode based on environment variable
test_mode = System.get_env("TEST_MODE", "mock_adapter")

IO.puts("Running tests in #{test_mode} mode")

# Set application environment based on test mode
case test_mode do
  "mock_adapter" ->
    # Fast unit tests without Python
    Application.put_env(:dspex, :adapter, :mock)

  "bridge_mock" ->
    # Protocol tests without full Python
    Application.put_env(:dspex, :adapter, :bridge_mock)

  "full_integration" ->
    # Full integration tests with Python
    Application.put_env(:dspex, :adapter, :python)

  _ ->
    IO.puts("Unknown TEST_MODE: #{test_mode}, defaulting to mock_adapter")
    Application.put_env(:dspex, :adapter, :mock)
end

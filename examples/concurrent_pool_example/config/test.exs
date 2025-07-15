import Config

# Test environment configuration for concurrent pool example

# Enable pooling for integration tests
test_mode = System.get_env("TEST_MODE", "mock_adapter")
pooling_enabled = test_mode == "full_integration"

config :dspex,
  pooling_enabled: pooling_enabled,
  pool_size: 2,  # Small pool for tests
  pool_mode: :test

if pooling_enabled do
  config :dspex, DSPex.PythonBridge.SessionPoolV2,
    pool_size: 2,
    overflow: 1,
    checkout_timeout: 10_000,
    operation_timeout: 30_000
end

# Test-specific logging
config :logger, level: :warn
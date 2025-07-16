import Config

# Test-specific configuration
config :logger, level: :warning

config :pool_example,
  pool_size: 2,
  overflow: 1

config :dspex,
  test_mode: true
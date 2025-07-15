import Config

# Test configuration
config :logger, level: :warning

# Use smaller pool for testing
config :dspex,
  pool_size: 1,
  overflow: 0
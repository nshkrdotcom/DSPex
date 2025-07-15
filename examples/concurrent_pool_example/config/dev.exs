import Config

# Development environment configuration for concurrent pool example

# Enable pooling in development
config :dspex,
  pooling_enabled: true,
  pool_size: 3,  # Small pool for fast testing
  pool_mode: :development

# Reduce pool size for dev environment
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: 3,
  overflow: 0,  # No overflow for faster startup
  checkout_timeout: 15_000,  # Longer timeout for development/debugging
  operation_timeout: 60_000  # Longer timeout for development

# More verbose logging in development
config :logger, level: :debug
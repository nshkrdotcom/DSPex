import Config

# Production configuration
config :logger, level: :info

# Optimize for production
config :dspex,
  pool_size: 4,
  overflow: 2,
  debug_mode: false
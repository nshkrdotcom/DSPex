import Config

# Development configuration for signature examples
config :logger,
  level: :debug

# Show more detailed logs in development
config :dspex,
  debug_mode: true,
  log_python_bridge: true
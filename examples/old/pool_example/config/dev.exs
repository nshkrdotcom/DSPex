import Config

# Development-specific configuration
config :logger, :console,
  format: "[$level] $message\n"

config :pool_example,
  debug: true
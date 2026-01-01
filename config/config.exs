import Config

config :snakebridge,
  verbose: false,
  runtime: [
    library_profiles: %{"dspy" => :ml_inference}
  ]

# Track current Mix environment for runtime diagnostics
config :snakepit, environment: config_env()

config :logger,
  level: :warning

# Snakepit is configured in runtime.exs using SnakeBridge.ConfigHelper

import_config "#{config_env()}.exs"

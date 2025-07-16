import Config

# General configuration for pool_example
config :pool_example,
  pool_size: 4,
  overflow: 2

# Configure DSPex for pooling
config :dspex,
  pooling_enabled: true,
  default_adapter: :python_pool_v2,
  python_path: System.get_env("PYTHON_PATH") || "python3"

# Configure logger
config :logger,
  level: :info,
  format: "$time $metadata[$level] $message\n"

# Import environment specific config
import_config "#{config_env()}.exs"
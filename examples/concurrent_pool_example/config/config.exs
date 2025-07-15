import Config

# Configure DSPex for pooling in the concurrent example
config :dspex,
  # Enable pooling for concurrent operations
  pooling_enabled: true,
  
  # Pool configuration for the example
  pool_size: 4,
  pool_mode: :example

# Configure SessionPoolV2 for the example
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: 4,
  overflow: 2,
  checkout_timeout: 10_000,
  operation_timeout: 30_000,
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced

# Python bridge configuration
config :dspex, :python_bridge,
  python_executable: "python3",
  default_timeout: 30_000,
  max_retries: 3,
  restart_strategy: :permanent

# Logging for debugging
config :logger, level: :info

# Environment specific overrides
import_config "#{config_env()}.exs"
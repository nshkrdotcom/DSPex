import Config

# Configure DSPex for signature examples
config :dspex,
  # Disable Python bridge pooling temporarily to test signatures
  pooling_enabled: false,
  # Configure pool settings
  pool_size: 2,
  overflow: 1,
  # Enable enhanced workers with session affinity
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced,
  # Configure error handling
  error_handling: [
    max_retries: 3,
    backoff: :exponential,
    circuit_breaker: true
  ]

# Configure logging
config :logger,
  level: :info,
  # Show info level for demo purposes
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

# Environment-specific configuration
import_config "#{config_env()}.exs"
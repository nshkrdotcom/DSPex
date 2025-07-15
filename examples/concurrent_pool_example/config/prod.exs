import Config

# Production environment configuration for concurrent pool example

# Enable pooling in production with optimal settings
config :dspex,
  pooling_enabled: true,
  pool_size: System.schedulers_online() * 2,
  pool_mode: :production

# Production pool configuration
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: System.schedulers_online() * 2,
  overflow: System.schedulers_online(),
  checkout_timeout: 5_000,
  operation_timeout: 30_000,
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced

# Production logging
config :logger, level: :info
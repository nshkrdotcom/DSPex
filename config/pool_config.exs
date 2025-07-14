# Pool Configuration Example for DSPex Python Bridge
#
# This file demonstrates how to configure the advanced pooling
# features of the DSPex Python bridge using NimblePool.

import Config

# Enable pool mode for the Python bridge
config :dspex, :python_bridge_pool_mode, true

# Configure the pool supervisor
config :dspex, DSPex.PythonBridge.PoolSupervisor,
  # Number of Python worker processes
  # Default: System.schedulers_online() * 2
  pool_size: 8,

  # Maximum additional workers that can be created under load
  # Default: System.schedulers_online()
  max_overflow: 4,

  # Maximum time to wait for an available worker (milliseconds)
  # Default: 5000
  checkout_timeout: 5_000,

  # How often to perform health checks (milliseconds)
  # Default: 30000
  health_check_interval: 30_000,

  # Whether to start workers lazily on first use
  # Default: false (eager startup)
  lazy: false,

  # Telemetry metrics collection interval (milliseconds)
  # Default: 10000
  telemetry_period: 10_000

# Configure adapter registry to use pool adapter for layer 3
config :dspex, :adapter_registry, layer_3_adapter: DSPex.Adapters.PythonPool

# Example telemetry configuration
config :dspex, :telemetry_handlers, [
  # Log pool metrics
  {
    [:dspex, :python_bridge, :pool],
    &DSPex.Telemetry.log_pool_metrics/4,
    %{}
  }
]

# Development environment specific settings
if config_env() == :dev do
  config :dspex, DSPex.PythonBridge.PoolSupervisor,
    pool_size: 2,
    max_overflow: 1,
    health_check_interval: 60_000
end

# Test environment specific settings
if config_env() == :test do
  config :dspex, DSPex.PythonBridge.PoolSupervisor,
    pool_size: 4,
    max_overflow: 2,
    checkout_timeout: 10_000,
    # Start workers on demand in tests
    lazy: true
end

# Production environment specific settings
if config_env() == :prod do
  config :dspex, DSPex.PythonBridge.PoolSupervisor,
    pool_size: System.schedulers_online() * 3,
    max_overflow: System.schedulers_online() * 2,
    checkout_timeout: 30_000,
    health_check_interval: 15_000,
    lazy: false
end

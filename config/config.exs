# Sample configuration for DSPex
# Copy this to your application's config/config.exs and modify as needed

import Config

# Signature System Configuration
config :dspex, :signature_system,
  # Enable runtime validation of inputs and outputs
  validation_enabled: true,

  # Enable compile-time checks and optimizations  
  compile_time_checks: true,

  # JSON schema provider for LLM function calling
  # Options: :openai, :anthropic, :generic
  json_schema_provider: :openai,

  # Strict type validation (more restrictive)
  type_validation_strict: false,

  # Cache compiled signatures for performance
  cache_compiled_signatures: true

# Python Bridge Configuration  
config :dspex, :python_bridge,
  # Python executable to use
  python_executable: "python3",

  # Default timeout for Python bridge calls (milliseconds)
  default_timeout: 30_000,

  # Maximum number of retry attempts
  max_retries: 3,

  # Restart strategy for bridge process
  restart_strategy: :permanent,

  # Required Python packages for validation
  required_packages: ["dspy-ai"],

  # Minimum required Python version
  min_python_version: "3.8.0",

  # Path to Python bridge script (relative to priv dir)
  script_path: "python/dspy_bridge.py"

# Error Handling Configuration
config :dspex, :error_handling,
  # Enable graceful test mode for error recovery tests
  test_mode: false,
  
  # Suppress stack traces for expected test errors
  suppress_test_stack_traces: true,
  
  # Show structured test error summary
  test_error_summary: true

# Health Monitor Configuration
config :dspex, :python_bridge_monitor,
  # Interval between health checks (milliseconds)
  health_check_interval: 30_000,

  # Number of consecutive failures before restart
  failure_threshold: 3,

  # Timeout for individual health check requests
  response_timeout: 5_000,

  # Delay before triggering restart
  restart_delay: 1_000,

  # Maximum restart attempts before giving up
  max_restart_attempts: 5,

  # Cooldown period between restart attempts
  restart_cooldown: 60_000

# Supervisor Configuration
config :dspex, :python_bridge_supervisor,
  # Maximum restarts within max_seconds
  max_restarts: 5,

  # Time window for restart counting
  max_seconds: 60,

  # Restart strategy for bridge process
  bridge_restart: :permanent,

  # Restart strategy for monitor process  
  monitor_restart: :permanent

# Environment-specific configurations
if config_env() == :dev do
  config :dspex, :python_bridge,
    # More verbose logging in development
    default_timeout: 60_000

  config :dspex, :python_bridge_monitor,
    # More frequent health checks in development
    health_check_interval: 10_000
end

if config_env() == :test do
  config :dspex, :signature_system,
    # Disable caching in tests for predictable behavior
    cache_compiled_signatures: false

  config :dspex, :python_bridge,
    # Shorter timeouts in tests
    default_timeout: 5_000

  config :dspex, :python_bridge_monitor,
    # Very frequent health checks in tests
    health_check_interval: 1_000,
    failure_threshold: 2

  # Pooling configuration for tests
  # This is read by ConditionalSupervisor at startup
  test_mode = System.get_env("TEST_MODE", "mock_adapter")
  pooling_enabled = test_mode == "full_integration"

  config :dspex,
    pooling_enabled: pooling_enabled,
    # Small pool for tests
    pool_size: 2,
    pool_mode: :test
end

if config_env() == :prod do
  config :dspex, :python_bridge_monitor,
    # Less frequent health checks in production
    health_check_interval: 60_000,
    failure_threshold: 5

  config :dspex, :python_bridge_supervisor,
    # More aggressive restart limits in production
    max_restarts: 10,
    max_seconds: 300
end

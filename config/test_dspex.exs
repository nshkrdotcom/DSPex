# DSPy Test Configuration
# This file configures DSPy integration for testing

import Config

# Enable Python bridge for DSPy tests
config :dspex, :python_bridge_enabled, true

# Enable pool debug mode for better error visibility
config :dspex, :pool_debug_mode, true

# Configure DSPy-specific settings
config :dspex, :dspy_config,
  # Use Gemini as the default model
  default_model: "gemini-2.0-flash-exp",
  api_key_env: "GEMINI_API_KEY",

  # Test-specific timeouts
  request_timeout: 30_000,

  # Enable verbose logging for debugging
  debug_mode: true

# Python bridge settings optimized for testing
config :dspex, :python_bridge,
  python_executable: "python3",
  # Longer timeout for LLM calls
  default_timeout: 45_000,
  max_retries: 2,
  required_packages: ["dspy-ai", "google-generativeai"]

# SessionPoolV2 settings for test environment
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  # Very generous checkout timeout for tests (Python startup can be slow)
  checkout_timeout: 60_000,
  # Longer operation timeout for Python initialization
  timeout: 60_000,
  # Smaller pool for tests
  pool_size: 2,
  # Allow overflow for concurrent tests
  overflow: 2,
  # Start all workers immediately to avoid race conditions
  lazy: false

# Monitor settings for testing
config :dspex, :python_bridge_monitor,
  # More frequent checks
  health_check_interval: 10_000,
  failure_threshold: 3,
  response_timeout: 10_000

# 3-Layer Testing Architecture Configuration
# Default to Layer 1
config :dspex, :test_mode, :mock_adapter

# Layer 1: Mock Adapter Configuration
config :dspex, :mock_adapter,
  # No delay for fast tests
  response_delay_ms: 0,
  # No random errors by default
  error_rate: 0.0,
  # Consistent responses
  deterministic: true,
  # Custom responses can be configured per test
  mock_responses: %{}

# Layer 2: Bridge Mock Server Configuration  
config :dspex, :bridge_mock_server,
  # Minimal delay to simulate protocol overhead
  response_delay_ms: 10,
  # No random errors by default
  error_probability: 0.0,
  # No random timeouts by default
  timeout_probability: 0.0,
  # Limit programs in mock
  max_programs: 100,
  # Enable debug logging
  enable_logging: true

# Test isolation settings
config :dspex, :test_isolation,
  # Use unique process names
  unique_naming: true,
  # Clean up resources after tests
  cleanup_on_exit: true,
  # Use temporary supervision for tests
  supervision_mode: :temporary

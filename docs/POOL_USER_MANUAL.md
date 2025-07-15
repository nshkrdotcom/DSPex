# DSPex SessionPoolV2 User Manual

**Version:** 2.0  
**Date:** 2025-07-15

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [Basic Usage](#basic-usage)
5. [Advanced Usage](#advanced-usage)
6. [Error Handling](#error-handling)
7. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
8. [Production Deployment](#production-deployment)
9. [Migration Guide](#migration-guide)
10. [API Reference](#api-reference)

---

## Overview

DSPex SessionPoolV2 is a production-ready pooling system for managing concurrent Python DSPy bridge workers. It provides:

- **Session Isolation**: Each session maintains independent state and program registry
- **Concurrent Execution**: Multiple Python workers handle requests in parallel
- **Automatic Recovery**: Health monitoring and worker restart capabilities
- **Error Handling**: Circuit breakers, retry logic, and comprehensive error classification
- **Performance Monitoring**: Built-in metrics and telemetry

### Architecture

```
Application
    │
    ├── DSPex.Application
    │   └── DSPex.PythonBridge.ConditionalSupervisor
    │       └── DSPex.PythonBridge.PoolSupervisor (when pooling_enabled: true)
    │           ├── DSPex.PythonBridge.SessionPoolV2 (GenServer)
    │           │   ├── NimblePool
    │           │   │   ├── PoolWorkerV2Enhanced (Worker 1) ←→ Python Process 1
    │           │   │   ├── PoolWorkerV2Enhanced (Worker 2) ←→ Python Process 2
    │           │   │   └── PoolWorkerV2Enhanced (Worker N) ←→ Python Process N
    │           │   └── SessionAffinity (ETS)
    │           ├── ErrorRecoveryOrchestrator
    │           ├── CircuitBreaker
    │           └── PoolErrorHandler
    │
    └── Your Application Code
        └── SessionPoolV2.execute_in_session/3
```

---

## Quick Start

### 1. Enable Pooling

Add to your `config/config.exs`:

```elixir
config :dspex, 
  pooling_enabled: true,
  pool_size: 4
```

### 2. Basic Example

```elixir
# Execute a simple prediction in a session
session_id = "user_123"
result = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
  session_id,
  :predict,
  %{question: "What is the capital of France?"}
)

case result do
  {:ok, response} -> 
    IO.inspect(response)  # %{"answer" => "Paris"}
  {:error, reason} -> 
    IO.puts("Error: #{inspect(reason)}")
end
```

### 3. Using Anonymous Sessions

```elixir
# For one-off operations without session state
result = DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
  :predict,
  %{text: "Classify this sentiment: I love this product!"}
)
```

---

## Configuration

### Basic Configuration

```elixir
# config/config.exs
config :dspex,
  # Enable the pooling system
  pooling_enabled: true,
  
  # Basic pool settings
  pool_size: 4,
  pool_mode: :production

# Optional: Configure SessionPoolV2 specifically
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: 4,
  overflow: 2,
  checkout_timeout: 10_000,
  operation_timeout: 30_000
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :dspex,
  pooling_enabled: true,
  pool_size: 2,
  pool_mode: :development

# config/test.exs
test_mode = System.get_env("TEST_MODE", "mock_adapter")
pooling_enabled = test_mode == "full_integration"

config :dspex,
  pooling_enabled: pooling_enabled,
  pool_size: 2,
  pool_mode: :test

# config/prod.exs
config :dspex,
  pooling_enabled: true,
  pool_size: System.schedulers_online() * 2,
  pool_mode: :production

config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: System.schedulers_online() * 2,
  overflow: System.schedulers_online(),
  checkout_timeout: 5_000,
  operation_timeout: 30_000
```

### Worker Configuration

```elixir
# Choose worker implementation
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  # Basic workers (faster startup)
  worker_module: DSPex.PythonBridge.PoolWorkerV2,
  
  # OR Enhanced workers (health monitoring, session affinity)
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced
```

---

## Basic Usage

### Session-Based Operations

```elixir
# 1. Set up language model first
DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))

# 2. Execute operations in a session
session_id = "user_#{user_id}_#{timestamp}"

# Simple prediction
{:ok, result} = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
  session_id,
  :predict,
  %{question: "What is Elixir?"}
)

# Multiple operations in the same session maintain state
{:ok, _} = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
  session_id,
  :predict,
  %{question: "Tell me more about it"}
)
```

### Anonymous Operations

```elixir
# For stateless operations without session management
alias DSPex.PythonBridge.SessionPoolV2

# Simple prediction
{:ok, result} = SessionPoolV2.execute_anonymous(
  :predict,
  %{text: "Classify sentiment: This is amazing!"}
)

# With timeout options
{:ok, result} = SessionPoolV2.execute_anonymous(
  :predict,
  %{text: "Long processing task..."},
  timeout: 60_000
)
```

### Working with Programs

```elixir
session_id = "my_session"

# Create a custom program
program_config = %{
  id: "qa_bot",
  signature: %{
    name: "QuestionAnswer",
    inputs: [%{name: "question", type: "string"}],
    outputs: [%{name: "answer", type: "string"}]
  }
}

# Create program in session
{:ok, program_id} = SessionPoolV2.execute_in_session(
  session_id,
  :create_program,
  program_config
)

# Execute the program
{:ok, result} = SessionPoolV2.execute_in_session(
  session_id,
  :execute_program,
  %{
    program_id: program_id,
    inputs: %{question: "What is machine learning?"}
  }
)
```

---

## Advanced Usage

### Concurrent Operations

```elixir
# Run multiple operations concurrently
defmodule ConcurrentExample do
  alias DSPex.PythonBridge.SessionPoolV2

  def run_concurrent_operations() do
    # Set up language model
    DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))
    
    # Launch concurrent tasks
    tasks = [
      Task.async(fn -> classify_sentiment() end),
      Task.async(fn -> translate_text() end),
      Task.async(fn -> summarize_text() end)
    ]
    
    # Wait for all to complete
    results = Task.await_many(tasks, 30_000)
    
    {:ok, results}
  end
  
  defp classify_sentiment() do
    SessionPoolV2.execute_in_session(
      "classification_#{:rand.uniform(1000)}",
      :predict,
      %{
        text: "I love this product!",
        task: "classify_sentiment",
        options: ["positive", "negative", "neutral"]
      }
    )
  end
  
  defp translate_text() do
    SessionPoolV2.execute_in_session(
      "translation_#{:rand.uniform(1000)}",
      :predict,
      %{
        text: "Hello world",
        source_language: "English",
        target_language: "French"
      }
    )
  end
  
  defp summarize_text() do
    SessionPoolV2.execute_in_session(
      "summary_#{:rand.uniform(1000)}",
      :predict,
      %{
        text: "Long text to summarize...",
        max_length: 50,
        style: "concise"
      }
    )
  end
end
```

### Session Affinity

```elixir
# Demonstrate session affinity for state continuity
defmodule SessionAffinityExample do
  alias DSPex.PythonBridge.SessionPoolV2

  def conversation_with_memory() do
    session_id = "conversation_#{:rand.uniform(1000)}"
    
    # Set up language model
    DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))
    
    # Multiple operations in same session use the same worker (when possible)
    operations = [
      %{text: "Hello, I'm starting a conversation"},
      %{text: "Can you remember what I just said?"},
      %{text: "Now summarize our entire conversation"}
    ]
    
    results = 
      Enum.map(operations, fn args ->
        SessionPoolV2.execute_in_session(session_id, :predict, args)
      end)
    
    {:ok, results}
  end
end
```

### Error Handling with Retries

```elixir
# Execute with custom retry logic
result = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
  session_id,
  :predict,
  %{question: "Complex question"},
  max_retries: 3,
  backoff: :exponential,
  timeout: 30_000
)

case result do
  {:ok, response} -> 
    # Success
    handle_success(response)
    
  {:error, %{error_category: :timeout}} ->
    # Handle timeout specifically
    handle_timeout()
    
  {:error, %{error_category: :resource_error}} ->
    # Pool exhausted or unavailable
    handle_resource_error()
    
  {:error, reason} ->
    # Other errors
    handle_general_error(reason)
end
```

---

## Error Handling

### Error Categories

SessionPoolV2 classifies errors into categories for appropriate handling:

```elixir
# Initialization errors
{:error, %{error_category: :initialization, message: "Python process failed to start"}}

# Connection errors  
{:error, %{error_category: :connection, message: "Port communication failed"}}

# Communication errors
{:error, %{error_category: :communication, message: "Invalid response format"}}

# Timeout errors
{:error, %{error_category: :timeout, message: "Operation timed out"}}

# Resource errors
{:error, %{error_category: :resource_error, message: "Pool not available"}}

# Health check errors
{:error, %{error_category: :health_check, message: "Worker health check failed"}}

# Session errors
{:error, %{error_category: :session, message: "Session state corrupted"}}

# Python errors
{:error, %{error_category: :python, message: "Python runtime error"}}

# System errors
{:error, %{error_category: :system_error, message: "Unexpected system failure"}}
```

### Retry Strategies

```elixir
# Linear backoff (100ms, 200ms, 300ms...)
SessionPoolV2.execute_in_session(
  session_id, 
  :predict, 
  args,
  max_retries: 3,
  backoff: :linear
)

# Exponential backoff (100ms, 200ms, 400ms, 800ms...)
SessionPoolV2.execute_in_session(
  session_id, 
  :predict, 
  args,
  max_retries: 5,
  backoff: :exponential
)

# Custom backoff function
custom_backoff = fn attempt -> attempt * 150 end
SessionPoolV2.execute_in_session(
  session_id, 
  :predict, 
  args,
  max_retries: 3,
  backoff: custom_backoff
)
```

### Circuit Breaker

The circuit breaker automatically protects against cascading failures:

```elixir
# Circuit breaker states:
# :closed   - Normal operation
# :open     - Failing fast, not attempting operations  
# :half_open - Testing if service has recovered

# Configure circuit breaker thresholds
config :dspex, DSPex.PythonBridge.CircuitBreaker,
  failure_threshold: 5,      # Open after 5 failures
  success_threshold: 3,      # Close after 3 successes
  timeout: 60_000           # Try again after 60 seconds
```

---

## Monitoring & Troubleshooting

### Health Checks

```elixir
# Check overall pool health
case DSPex.PythonBridge.SessionPoolV2.health_check() do
  {:ok, :healthy, stats} ->
    IO.puts("Pool healthy: #{inspect(stats)}")
    
  {:ok, :degraded, stats} ->
    IO.puts("Pool degraded: #{inspect(stats)}")
    # Consider alerting operations team
    
  {:error, reason} ->
    IO.puts("Pool unhealthy: #{inspect(reason)}")
    # Immediate attention required
end
```

### Pool Statistics

```elixir
# Get detailed pool statistics
{:ok, stats} = DSPex.PythonBridge.SessionPoolV2.get_stats()

IO.inspect(stats, label: "Pool Stats")
# Output example:
# Pool Stats: %{
#   pool_size: 4,
#   active_workers: 4,
#   available_workers: 2,
#   active_sessions: 3,
#   total_requests: 1542,
#   total_errors: 12,
#   average_response_time: 245,
#   uptime_seconds: 3600
# }
```

### Common Issues

#### 1. "Pool not available" errors

```elixir
# Check if pooling is enabled
pooling_enabled = Application.get_env(:dspex, :pooling_enabled, false)
if not pooling_enabled do
  IO.puts("Pooling is disabled. Enable with: config :dspex, pooling_enabled: true")
end

# Check if pool supervisor is running
case Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
  nil -> IO.puts("SessionPoolV2 is not running")
  pid -> IO.puts("SessionPoolV2 running at #{inspect(pid)}")
end
```

#### 2. Checkout timeouts

```elixir
# Increase pool size or timeout
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: 8,           # More workers
  overflow: 4,            # Allow temporary overflow
  checkout_timeout: 10_000 # Longer timeout
```

#### 3. Worker failures

```elixir
# Check worker health
{:ok, stats} = DSPex.PythonBridge.SessionPoolV2.get_stats()
unhealthy_workers = stats.pool_size - stats.active_workers

if unhealthy_workers > 0 do
  IO.puts("#{unhealthy_workers} workers are unhealthy")
  # Check logs for worker restart messages
end
```

### Debugging Commands

```elixir
# Force health check
DSPex.PythonBridge.SessionPoolV2.health_check()

# Get current pool state
:sys.get_state(DSPex.PythonBridge.SessionPoolV2)

# List active sessions
DSPex.PythonBridge.SessionAffinity.list_sessions()

# Check circuit breaker state
DSPex.PythonBridge.CircuitBreaker.get_state()
```

---

## Production Deployment

### Recommended Configuration

```elixir
# config/prod.exs
config :dspex,
  pooling_enabled: true,
  pool_size: System.schedulers_online() * 2,
  pool_mode: :production

config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: System.schedulers_online() * 2,
  overflow: System.schedulers_online(),
  checkout_timeout: 5_000,
  operation_timeout: 30_000,
  worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced

# Error handling configuration
config :dspex, DSPex.PythonBridge.PoolErrorHandler,
  error_rate_threshold: 0.05,
  alert_destinations: [:logger, :telemetry]

config :dspex, DSPex.PythonBridge.CircuitBreaker,
  failure_threshold: 5,
  success_threshold: 3,
  timeout: 30_000
```

### Monitoring Setup

```elixir
# Set up telemetry for monitoring
:telemetry.attach_many(
  "dspex-pool-metrics",
  [
    [:dspex, :session_pool, :checkout],
    [:dspex, :session_pool, :execute],
    [:dspex, :session_pool, :error]
  ],
  &MyApp.PoolMetrics.handle_event/4,
  nil
)

defmodule MyApp.PoolMetrics do
  def handle_event([:dspex, :session_pool, :checkout], measurements, metadata, _) do
    # Track checkout latency
    StatsD.timing("dspex.pool.checkout_time", measurements.duration)
  end
  
  def handle_event([:dspex, :session_pool, :execute], measurements, metadata, _) do
    # Track execution metrics
    StatsD.timing("dspex.pool.execution_time", measurements.duration)
    StatsD.increment("dspex.pool.requests")
  end
  
  def handle_event([:dspex, :session_pool, :error], measurements, metadata, _) do
    # Track errors
    StatsD.increment("dspex.pool.errors.#{metadata.error_category}")
  end
end
```

### Load Testing

```elixir
defmodule LoadTest do
  alias DSPex.PythonBridge.SessionPoolV2
  
  def run_load_test(concurrent_users, operations_per_user) do
    # Pre-warm the pool
    DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))
    
    start_time = System.monotonic_time(:millisecond)
    
    # Launch concurrent users
    tasks = 
      for user_id <- 1..concurrent_users do
        Task.async(fn ->
          session_id = "load_test_user_#{user_id}"
          
          results = 
            for op <- 1..operations_per_user do
              SessionPoolV2.execute_in_session(
                session_id,
                :predict,
                %{question: "Test question #{op}"}
              )
            end
          
          {user_id, results}
        end)
      end
    
    # Wait for completion
    results = Task.await_many(tasks, 60_000)
    end_time = System.monotonic_time(:millisecond)
    
    # Analyze results
    total_operations = concurrent_users * operations_per_user
    duration_ms = end_time - start_time
    ops_per_second = total_operations / (duration_ms / 1000)
    
    successes = 
      results
      |> Enum.flat_map(fn {_user, ops} -> ops end)
      |> Enum.count(&match?({:ok, _}, &1))
    
    %{
      total_operations: total_operations,
      successes: successes,
      failures: total_operations - successes,
      duration_ms: duration_ms,
      ops_per_second: ops_per_second,
      success_rate: successes / total_operations
    }
  end
end

# Run load test
LoadTest.run_load_test(10, 100)
```

---

## Migration Guide

### From Single Bridge to SessionPoolV2

#### Before (Single Bridge)

```elixir
# Old approach using direct adapter
adapter = DSPex.Adapters.Registry.get_adapter()
{:ok, program_id} = adapter.create_program(config)
{:ok, result} = adapter.execute_program(program_id, inputs)
```

#### After (SessionPoolV2)

```elixir
# New approach with session management
session_id = generate_session_id()

{:ok, result} = DSPex.PythonBridge.SessionPoolV2.execute_in_session(
  session_id,
  :predict,
  %{question: "What is the capital of France?"}
)
```

### Configuration Migration

```elixir
# Old configuration
config :dspex, :python_bridge,
  python_executable: "python3",
  default_timeout: 30_000

# New configuration (additional settings)
config :dspex,
  pooling_enabled: true,   # Enable pooling
  pool_size: 4

config :dspex, DSPex.PythonBridge.SessionPoolV2,
  pool_size: 4,
  overflow: 2,
  checkout_timeout: 5_000,
  operation_timeout: 30_000
```

---

## API Reference

### Core Functions

#### `execute_in_session/3`
Execute a command in a specific session.

```elixir
@spec execute_in_session(session_id :: String.t(), command :: atom(), args :: map()) ::
  {:ok, term()} | {:error, term()}

execute_in_session(session_id, command, args)
```

#### `execute_in_session/4`
Execute a command with options.

```elixir
@spec execute_in_session(session_id :: String.t(), command :: atom(), args :: map(), opts :: keyword()) ::
  {:ok, term()} | {:error, term()}

execute_in_session(session_id, command, args, opts)
```

**Options:**
- `:timeout` - Operation timeout in milliseconds
- `:max_retries` - Maximum retry attempts
- `:backoff` - Backoff strategy (`:linear`, `:exponential`, or function)

#### `execute_anonymous/2`
Execute a command without session state.

```elixir
@spec execute_anonymous(command :: atom(), args :: map()) :: {:ok, term()} | {:error, term()}

execute_anonymous(command, args)
```

#### `execute_anonymous/3`
Execute a command anonymously with options.

```elixir
@spec execute_anonymous(command :: atom(), args :: map(), opts :: keyword()) :: 
  {:ok, term()} | {:error, term()}

execute_anonymous(command, args, opts)
```

### Monitoring Functions

#### `health_check/0`
Check the health of the pool.

```elixir
@spec health_check() :: {:ok, :healthy | :degraded, map()} | {:error, term()}

health_check()
```

#### `get_stats/0`
Get detailed pool statistics.

```elixir
@spec get_stats() :: {:ok, map()} | {:error, term()}

get_stats()
```

### Session Management

#### Session Affinity Functions

```elixir
# List active sessions
DSPex.PythonBridge.SessionAffinity.list_sessions()

# Get session info
DSPex.PythonBridge.SessionAffinity.get_session(session_id)

# Cleanup session manually
DSPex.PythonBridge.SessionAffinity.cleanup_session(session_id)
```

---

## Best Practices

### 1. Session Management
- Use meaningful session IDs (e.g., `"user_#{user_id}_#{timestamp}"`)
- Keep sessions short-lived when possible
- Clean up sessions explicitly for long-running applications

### 2. Error Handling
- Always handle the error tuple returned by pool functions
- Use appropriate retry strategies based on error categories
- Monitor error rates in production

### 3. Performance
- Size your pool based on workload: CPU-bound ~= schedulers, I/O-bound = 2-3x schedulers
- Use session affinity for conversational or stateful operations
- Monitor pool utilization and adjust as needed

### 4. Monitoring
- Set up telemetry for production monitoring
- Monitor pool health and worker restart rates
- Track operation latencies and error rates

### 5. Configuration
- Start with conservative pool sizes and tune based on metrics
- Use different configurations per environment
- Enable circuit breakers and retries for production resilience

---

This manual provides comprehensive guidance for using DSPex SessionPoolV2 effectively. For advanced configuration and troubleshooting, refer to the technical documentation and implementation guides in the `/docs` directory.
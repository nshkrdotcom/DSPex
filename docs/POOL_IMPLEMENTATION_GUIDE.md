# DSPex Python Bridge Pool Implementation Guide

## Overview

This guide documents the comprehensive NimblePool-based implementation for the DSPex Python bridge, providing advanced pooling capabilities with session isolation, concurrent execution, and production-ready features.

## Architecture

```
Application
    │
    ├── PoolSupervisor
    │   ├── SessionPool (GenServer)
    │   │   └── NimblePool
    │   │       ├── PoolWorker 1 (Python process)
    │   │       ├── PoolWorker 2 (Python process)
    │   │       └── PoolWorker N (Python process)
    │   ├── SessionRegistry
    │   └── TelemetryPoller
    │
    └── PythonPool Adapter (Elixir interface)
```

## Key Components

### 1. PoolWorker (NimblePool Worker)

The `DSPex.PythonBridge.PoolWorker` module implements the NimblePool behaviour and manages individual Python processes:

```elixir
# Each worker maintains:
- Port connection to Python process
- Session binding state
- Request correlation
- Health monitoring
- Statistics tracking
```

**Key Features:**
- Lazy or eager worker initialization
- Session affinity during checkout
- Automatic cleanup on checkin
- Health checks and recovery
- Request/response correlation

### 2. SessionPool (Pool Manager)

The `DSPex.PythonBridge.SessionPool` module manages the pool and provides session-aware operations:

```elixir
# Core responsibilities:
- Pool lifecycle management
- Session state tracking
- Request routing
- Metrics collection
- Graceful shutdown
```

**Session Management:**
- Create/end sessions
- Track session state
- Cleanup on termination
- Resource isolation

### 3. Python Bridge Updates

The Python `dspy_bridge.py` script now supports two modes:

```python
# Standalone mode (default)
python3 dspy_bridge.py

# Pool worker mode
python3 dspy_bridge.py --mode pool-worker --worker-id worker_123
```

**Pool Worker Features:**
- Session-namespaced programs
- Session cleanup commands
- Worker identification
- Graceful shutdown support

### 4. PythonPool Adapter

The `DSPex.Adapters.PythonPool` provides a clean Elixir interface:

```elixir
# Automatic session management
{:ok, result} = PythonPool.execute_program(
  program_id, 
  inputs,
  session_id: "user_123"
)
```

## Usage Examples

### Basic Usage

```elixir
# 1. Create a session
session_id = "user_#{user_id}_#{timestamp}"
DSPex.PythonBridge.PoolSupervisor.create_session(session_id)

# 2. Create and execute programs
config = %{
  signature: MySignature,
  id: "qa_bot"
}

{:ok, program_id} = DSPex.Adapters.PythonPool.create_program(
  config,
  session_id: session_id
)

{:ok, result} = DSPex.Adapters.PythonPool.execute_program(
  program_id,
  %{question: "What is DSPex?"},
  session_id: session_id
)

# 3. Clean up
DSPex.PythonBridge.PoolSupervisor.end_session(session_id)
```

### Advanced Usage

```elixir
# Parallel execution with different sessions
tasks = 
  for user_id <- user_ids do
    Task.async(fn ->
      session_id = "user_#{user_id}"
      PoolSupervisor.create_session(session_id)
      
      # Execute operations...
      result = process_user_request(user_id, session_id)
      
      PoolSupervisor.end_session(session_id)
      result
    end)
  end

results = Task.await_many(tasks)
```

### Health Monitoring

```elixir
# Check pool health
case PoolSupervisor.health_check() do
  {:ok, :healthy, details} ->
    Logger.info("Pool healthy: #{inspect(details)}")
    
  {:ok, :degraded, details} ->
    Logger.warning("Pool degraded: #{inspect(details)}")
    alert_operations_team(details)
end

# Get pool statistics
{:ok, stats} = PoolSupervisor.get_stats()
Logger.info("Active sessions: #{stats.active_sessions}")
Logger.info("Pool utilization: #{stats.pool_size}")
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs
config :dspex, :python_bridge_pool_mode, true

config :dspex, DSPex.PythonBridge.PoolSupervisor,
  pool_size: 8,
  max_overflow: 4,
  checkout_timeout: 5_000
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :dspex, DSPex.PythonBridge.PoolSupervisor,
  pool_size: 2,
  lazy: true

# config/prod.exs
config :dspex, DSPex.PythonBridge.PoolSupervisor,
  pool_size: System.schedulers_online() * 3,
  max_overflow: System.schedulers_online() * 2,
  health_check_interval: 15_000
```

## Migration from Single Bridge

### Before (Single Bridge)

```elixir
# Direct bridge calls
{:ok, response} = DSPex.PythonBridge.Bridge.call(:create_program, args)
```

### After (Pool)

```elixir
# Session-aware pool calls
session_id = generate_session_id()
PoolSupervisor.create_session(session_id)

{:ok, response} = PoolSupervisor.execute_in_session(
  session_id,
  :create_program,
  args
)
```

### Using Adapter Pattern

```elixir
# Transparent migration using adapters
adapter = DSPex.Adapters.Registry.get_adapter(:python_pool)
{:ok, program_id} = adapter.create_program(config, session_id: session_id)
```

## Performance Considerations

### Pool Sizing

```elixir
# Recommended pool sizes:
# - CPU-bound: schedulers * 1.5
# - I/O-bound: schedulers * 3
# - Mixed: schedulers * 2

pool_size = System.schedulers_online() * 2
```

### Checkout Timeout

```elixir
# Balance between responsiveness and queue depth
checkout_timeout: 5_000  # 5 seconds default

# For long-running operations
checkout_timeout: 30_000  # 30 seconds
```

### Health Check Frequency

```elixir
# Production: Check every 15-30 seconds
health_check_interval: 30_000

# Development: Less frequent
health_check_interval: 60_000
```

## Monitoring and Telemetry

### Built-in Metrics

The pool emits telemetry events:

```elixir
:telemetry.attach(
  "pool-metrics",
  [:dspex, :python_bridge, :pool],
  fn _event, measurements, metadata, _config ->
    Logger.info("Pool metrics: #{inspect(measurements)}")
  end,
  nil
)
```

### Available Metrics

- `active_sessions` - Current number of active sessions
- `pool_size` - Configured pool size
- `total_commands` - Total commands executed
- `total_errors` - Total errors encountered
- `healthy_workers` - Number of healthy workers

### Custom Metrics

```elixir
defmodule MyApp.PoolMetrics do
  def handle_event([:dspex, :python_bridge, :pool], measurements, metadata, _) do
    # Send to monitoring service
    StatsD.gauge("python_pool.active_sessions", measurements.active_sessions)
    StatsD.increment("python_pool.commands", measurements.total_commands)
  end
end
```

## Troubleshooting

### Common Issues

1. **"Python bridge not running"**
   - Check Python environment is available
   - Verify pool supervisor started successfully
   - Check logs for worker startup errors

2. **Checkout timeouts**
   - Increase pool size or max_overflow
   - Check for long-running operations
   - Monitor pool utilization

3. **Session not found**
   - Ensure session was created before use
   - Check session hasn't been cleaned up
   - Verify session_id consistency

### Debug Commands

```elixir
# Check individual worker status
:sys.get_state(worker_pid)

# List all workers
Supervisor.which_children(PoolSupervisor)

# Force health check
PoolSupervisor.health_check()

# Get detailed stats
{:ok, stats} = PoolSupervisor.get_stats()
IO.inspect(stats, label: "Pool Stats")
```

## Production Deployment

### Recommended Settings

```elixir
config :dspex, DSPex.PythonBridge.PoolSupervisor,
  pool_size: System.schedulers_online() * 2,
  max_overflow: System.schedulers_online(),
  checkout_timeout: 10_000,
  health_check_interval: 30_000,
  lazy: false  # Eager startup for production
```

### Graceful Shutdown

```elixir
# In your application shutdown
def stop(_state) do
  Logger.info("Shutting down Python pool...")
  PoolSupervisor.shutdown(30_000)  # 30 second timeout
  :ok
end
```

### Load Testing

```elixir
# Example load test
defmodule LoadTest do
  def run(concurrent_users, operations_per_user) do
    for user_id <- 1..concurrent_users do
      Task.async(fn ->
        session_id = "load_test_#{user_id}"
        PoolSupervisor.create_session(session_id)
        
        for op <- 1..operations_per_user do
          # Simulate operations
          execute_test_operation(session_id, op)
        end
        
        PoolSupervisor.end_session(session_id)
      end)
    end
    |> Task.await_many(60_000)
  end
end
```

## Advanced Features

### Session Context

Sessions can maintain state across operations:

```elixir
# Create session with initial state
PoolSupervisor.create_session(session_id, %{
  user_preferences: %{theme: "dark"},
  conversation_history: []
})

# State is available to Python workers
{:ok, state} = PythonPool.get_session_state(session_id)
```

### Custom Worker Behavior

Extend the pool worker for custom behavior:

```elixir
defmodule MyApp.CustomPoolWorker do
  use DSPex.PythonBridge.PoolWorker
  
  # Override initialization
  def init_worker(pool_state) do
    {:ok, worker_state, pool_state} = super(pool_state)
    
    # Add custom initialization
    worker_state = Map.put(worker_state, :custom_field, "value")
    
    {:ok, worker_state, pool_state}
  end
end
```

## Summary

The NimblePool implementation provides:

1. **Scalability** - Handle multiple concurrent users efficiently
2. **Isolation** - Session-based separation of concerns
3. **Reliability** - Health monitoring and automatic recovery
4. **Performance** - Optimized resource utilization
5. **Observability** - Built-in metrics and telemetry
6. **Flexibility** - Configurable for different workloads

This implementation is production-ready and designed to scale with your application's needs while maintaining the simplicity of the DSPex adapter pattern.
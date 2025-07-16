# DSPex Python Pool V3 Architecture

## Overview

The V3 pool design abandons complex pool libraries in favor of simple OTP patterns that are better suited for managing heavy Python processes. This design leverages DynamicSupervisor, Registry, and basic Erlang queues to achieve concurrent initialization and efficient process management.

## Core Principles

1. **Python processes are heavy resources**, not lightweight connections
2. **OTP knows how to manage processes** - let it do its job
3. **Concurrent startup is critical** - 8 workers × 2-3 seconds sequential = unacceptable
4. **Simplicity over features** - avoid over-engineering for future requirements
5. **Stateless workers** - all state lives in the centralized SessionStore

## Architecture Components

### 1. Worker Supervisor (DynamicSupervisor)

```elixir
DSPex.Python.WorkerSupervisor
```

- Uses DynamicSupervisor for on-demand worker creation
- Handles crashes and restarts automatically via OTP
- One-for-one strategy: each worker is independent
- No manual restart logic needed

### 2. Individual Workers (GenServer)

```elixir
DSPex.Python.Worker
```

- Each worker owns exactly one Python process via Port
- Named processes registered in Registry
- Handles one request at a time (busy/available state)
- Automatic health checks every 30 seconds
- Graceful shutdown on termination

### 3. Pool Manager (GenServer)

```elixir
DSPex.Python.Pool
```

- Simple queue-based request distribution
- Tracks available/busy workers
- Queues requests when all workers are busy
- Non-blocking async execution
- Concurrent worker initialization on startup

### 4. Registry

```elixir
DSPex.Python.Registry
```

- Named process registration for all workers
- Enables direct worker communication
- Foundation for future clustering support
- O(1) worker lookup by ID

## Request Flow

```
Client Request
    ↓
Pool Manager
    ↓
Available Worker? → Yes → Assign & Execute Async
    ↓ No                        ↓
Queue Request              Worker executes
    ↓                          ↓
Wait for worker           Returns to pool or
                         serves queued request
```

## Concurrent Initialization

The key innovation is truly concurrent worker startup:

```elixir
Task.async_stream(1..count, fn i ->
  DSPex.Python.WorkerSupervisor.start_worker("python_worker_#{i}")
end, max_concurrency: count, timeout: 10_000)
```

All workers start in parallel, reducing startup time from O(n×startup_time) to O(startup_time).

## State Management

- **Workers**: Stateless, only track busy/available status
- **Pool**: Minimal state - worker queues and request queue
- **SessionStore**: All application state (programs, data, etc.)

## Error Handling

1. **Port crashes**: Supervisor restarts the worker
2. **Python errors**: Propagated to client with context
3. **Timeout**: Client receives timeout error
4. **Worker unavailable**: Request queued or rejected based on config

## Comparison with V2

| Feature | V2 (NimblePool) | V3 (OTP) |
|---------|-----------------|----------|
| Startup Time | Sequential (16-24s) | Concurrent (2-3s) |
| Complexity | High | Low |
| Lines of Code | ~2000 | ~300 |
| Dependencies | NimblePool | None (pure OTP) |
| Clustering Ready | No | Yes |
| Worker Recovery | Manual | Automatic (OTP) |

## Future Extensions

The design supports easy evolution:

1. **Clustering**: Replace Registry with Horde.Registry
2. **Metrics**: Add telemetry events at key points
3. **Circuit Breaking**: Add per-worker circuit breakers if needed
4. **Priority Queues**: Replace simple queue with priority queue
5. **Worker Pools by Type**: Different pools for different Python workloads

## Key Benefits

1. **Fast Startup**: All workers initialize concurrently
2. **Simple Code**: ~300 lines vs ~2000 lines
3. **OTP Reliability**: Battle-tested supervision trees
4. **Clustering Ready**: Registry pattern enables distribution
5. **Maintainable**: Standard OTP patterns, no magic
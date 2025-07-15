# Design Document

## Overview

This design implements a streamlined, minimal Python pooling system using the existing DSPex V2 architecture. The focus is on creating a "Golden Path" that provides reliable, stateless pooling of Python processes while ignoring complex enterprise features. The design leverages the proven V2 components but simplifies configuration, testing, and usage patterns.

## Architecture

### High-Level Architecture

```
Client Application
       ↓
PythonPoolV2 (Adapter)
       ↓
SessionPoolV2 (Pool Manager)
       ↓
NimblePool (Worker Pool)
       ↓
PoolWorkerV2 (Simple Workers)
       ↓
Python Processes (dspy_bridge.py)
```

### Core Components

The design focuses on six essential modules that form the "Golden Path":

1. **PythonPoolV2** - Public API adapter
2. **SessionPoolV2** - Pool manager with NimblePool integration
3. **PoolWorkerV2** - Simple worker implementation (NOT Enhanced)
4. **PoolSupervisor** - Supervision tree root
5. **Protocol** - JSON communication protocol
6. **dspy_bridge.py** - Python worker script

### Key Design Principles

- **Stateless Architecture**: No session affinity or state binding between workers and sessions
- **Direct Port Communication**: Clients communicate directly with Python processes after checkout
- **Simple Worker Model**: Use basic PoolWorkerV2, avoid enhanced variants
- **Minimal Configuration**: Focus on essential pool settings only
- **Focused Testing**: Tag-based test execution for core functionality only

## Components and Interfaces

### 1. Public API Layer (PythonPoolV2)

**Purpose**: Single entry point for all Python pooling operations

**Key Functions**:
- `execute_program/3` - Execute Python programs with inputs
- `health_check/1` - Verify pool health
- `get_stats/1` - Retrieve pool statistics

**Interface**:
```elixir
@spec execute_program(String.t(), map(), map()) :: {:ok, term()} | {:error, term()}
def execute_program(program_id, inputs, options \\ %{})

@spec health_check(map()) :: :ok | {:error, term()}
def health_check(options \\ %{})
```

### 2. Pool Management Layer (SessionPoolV2)

**Purpose**: Manages NimblePool and worker lifecycle

**Key Functions**:
- `execute_in_session/4` - Execute commands in client process context
- `execute_anonymous/3` - Execute commands without session binding
- `get_pool_status/1` - Retrieve pool status information

**Interface**:
```elixir
@spec execute_in_session(String.t(), atom(), map(), keyword()) :: {:ok, term()} | {:error, term()}
def execute_in_session(session_id, command, args, opts \\ [])

@spec execute_anonymous(atom(), map(), keyword()) :: {:ok, term()} | {:error, term()}
def execute_anonymous(command, args, opts \\ [])
```

### 3. Worker Layer (PoolWorkerV2)

**Purpose**: Manages individual Python process lifecycle

**Key Behaviors**:
- Initialize Python processes with health checks
- Handle checkout/checkin operations
- Direct port connection to client processes
- Automatic restart on failure

**NimblePool Callbacks**:
- `init_worker/1` - Start Python process and verify health
- `handle_checkout/4` - Connect port to client process
- `handle_checkin/4` - Return worker to pool
- `terminate_worker/3` - Clean shutdown of Python process

### 4. Communication Layer (Protocol)

**Purpose**: JSON-based message protocol for Elixir-Python communication

**Message Format**:
```json
// Request
{
  "id": 123,
  "command": "execute_program",
  "args": {...},
  "timestamp": "2024-01-01T00:00:00Z"
}

// Response
{
  "id": 123,
  "success": true,
  "result": {...},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### 5. Supervision Layer (PoolSupervisor)

**Purpose**: Supervise pool components and handle failures

**Supervision Tree**:
```
PoolSupervisor
├── SessionPoolV2 (GenServer)
│   └── NimblePool
│       ├── PoolWorkerV2 (Python Process 1)
│       ├── PoolWorkerV2 (Python Process 2)
│       └── PoolWorkerV2 (Python Process N)
└── PoolMonitor (Health Monitoring)
```

The `PoolMonitor` is included to provide essential, non-intrusive health checks and session cleanup, ensuring long-term pool stability without adding complexity to the core request path.

## Data Models

### Worker State
```elixir
%PoolWorkerV2{
  port: port(),
  python_path: String.t(),
  script_path: String.t(),
  worker_id: String.t(),
  current_session: nil,  # Always nil in stateless architecture
  stats: %{
    checkouts: integer(),
    successful_checkins: integer(),
    error_checkins: integer(),
    last_activity: integer()
  },
  health_status: :healthy | :initializing | :unhealthy,
  started_at: integer()
}
```

### Pool Configuration
```elixir
%{
  pool_size: integer(),        # Number of worker processes
  overflow: integer(),         # Additional workers under load
  checkout_timeout: integer(), # Max wait time for worker
  operation_timeout: integer() # Max time for Python operations
}
```

### Session Tracking (ETS)
```elixir
{session_id, %{
  session_id: String.t(),
  started_at: integer(),
  last_activity: integer(),
  operations: integer()
}}
```

This table is used for **monitoring and observability only** (e.g., getting stats on active sessions). It is explicitly **not used** for stateful routing or worker affinity.

## Error Handling

### Error Categories

1. **Timeout Errors**
   - Checkout timeout: No workers available
   - Operation timeout: Python process unresponsive

2. **Resource Errors**
   - Pool unavailable: NimblePool not started
   - Worker initialization failure: Python process won't start

3. **Communication Errors**
   - Port closed: Python process died
   - Protocol errors: Malformed JSON messages

4. **System Errors**
   - Supervisor crashes: Automatic restart
   - Worker crashes: Automatic replacement

### Error Recovery Strategy

1. **Worker Level**: Automatic restart by NimblePool supervision
2. **Pool Level**: Restart entire pool if supervisor crashes
3. **Client Level**: Return structured error responses
4. **System Level**: Application supervisor handles critical failures

### Error Response Format
```elixir
# Structured error tuple format
{:error, {category, type, message, context}}

# Examples
{:error, {:timeout_error, :checkout_timeout, "No workers available", %{pool_size: 4, active: 4}}}
{:error, {:resource_error, :worker_init_failed, "Python process failed to start", %{worker_id: "worker_1"}}}
{:error, {:communication_error, :port_closed, "Python process died unexpectedly", %{session_id: "session_123"}}}
```

## Testing Strategy

### Core Test Tags

Tag essential tests with `@moduletag :core_pool` to enable focused testing:

- `test/dspex/adapters/python_pool_v2_test.exs`
- `test/dspex/python_bridge/session_pool_v2_test.exs`
- `test/dspex/python_bridge/pool_worker_v2_test.exs`
- `test/dspex/python_bridge/protocol_test.exs`

### Test Execution
```bash
mix test --only core_pool
```

### Test Coverage Areas

1. **API Layer Tests**
   - Program execution with various inputs
   - Error handling and timeout scenarios
   - Health check functionality

2. **Pool Management Tests**
   - Worker checkout/checkin cycles
   - Concurrent operation handling
   - Pool status and metrics

3. **Worker Tests**
   - Python process initialization
   - Port communication
   - Worker lifecycle management

4. **Protocol Tests**
   - JSON encoding/decoding
   - Message validation
   - Error response formatting

### Ignored Test Areas

Tests for complex enterprise features are excluded from core testing:
- Session affinity and migration
- Complex error orchestration
- Enhanced worker state machines
- Circuit breaker functionality

## Configuration

### Minimal Configuration Example

```elixir
# config/config.exs
config :dspex, DSPex.PythonBridge.PoolSupervisor,
  pool_size: System.schedulers_online(),
  overflow: 2,
  checkout_timeout: 5_000,
  operation_timeout: 30_000
```

### Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pool_size` | `System.schedulers_online()` | Number of Python worker processes |
| `overflow` | `2` | Additional workers under high load |
| `checkout_timeout` | `5_000` | Max wait time for available worker (ms) |
| `operation_timeout` | `30_000` | Max time for Python operations (ms) |

## Performance Characteristics

### Execution Flow Performance

1. **Client Call** → **Worker Checkout** (< 1ms typical)
2. **Direct Port Communication** → **Python Execution** (variable, depends on Python task)
3. **Response Handling** → **Worker Checkin** (< 1ms typical)

### Bottleneck Analysis

- **Primary Bottleneck**: Python task execution time
- **Secondary Bottleneck**: Worker availability under high concurrency
- **Minimal Overhead**: Direct port communication eliminates message passing delays

### Scalability Considerations

- **Horizontal Scaling**: Increase `pool_size` based on CPU cores
- **Overflow Handling**: Configure `overflow` for burst capacity
- **Memory Usage**: Each worker consumes ~10-50MB depending on Python libraries

## Deployment Considerations

### Dependencies

- **Elixir**: OTP 24+ with NimblePool
- **Python**: 3.8+ with required packages
- **System**: Sufficient memory for worker processes

### Monitoring

- Pool status via `get_stats/1`
- Health checks via `health_check/1`
- ETS session tracking for debugging

### Operational Procedures

1. **Startup**: Automatic worker initialization with health verification
2. **Scaling**: Adjust `pool_size` in configuration and restart
3. **Maintenance**: Workers restart automatically on failure
4. **Shutdown**: Graceful termination with cleanup timeouts
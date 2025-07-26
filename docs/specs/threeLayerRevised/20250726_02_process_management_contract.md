# Snakepit Process Management Contract

## Executive Summary

This document specifies the contract between Snakepit (infrastructure) and SnakepitGRPCBridge (ML platform) for robust process management. It details how responsibilities are divided to achieve maximal cohesion within each layer and minimal coupling between them.

## Core Process Management Architecture

### Snakepit Responsibilities (Infrastructure)

1. **Process Lifecycle Management**
   - Start external OS processes via adapters
   - Monitor process health via BEAM process monitoring
   - Restart crashed processes automatically
   - Clean shutdown with graceful termination

2. **Process Tracking**
   - Track OS PIDs in persistent storage (DETS)
   - Detect and clean orphaned processes across VM restarts
   - Maintain BEAM run ID to prevent killing unrelated processes
   - Process group management for clean termination

3. **Worker Pool Management**
   - Concurrent worker startup
   - Load balancing across workers
   - Request queuing when workers busy
   - Session affinity routing

4. **Guarantees Provided**
   - No orphaned processes survive VM crashes
   - Automatic restart of crashed workers
   - Graceful shutdown (SIGTERM) before forceful (SIGKILL)
   - Process group termination for child process cleanup

### SnakepitGRPCBridge Responsibilities (Platform)

1. **Process Creation**
   - Define how Python processes are started
   - Configure process arguments and environment
   - Set up communication channels (gRPC)
   - Handle process initialization

2. **Communication Protocol**
   - Implement gRPC server/client
   - Handle message serialization
   - Manage connection lifecycle
   - Error handling and retry logic

3. **Process Identity**
   - Generate unique process fingerprints
   - Provide process identification for tracking
   - Session-to-process mapping
   - Health check implementation

## The Adapter Contract

### Required Callbacks

```elixir
defmodule Snakepit.Adapter do
  # Core execution - the only required callback
  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}
end
```

### Optional Callbacks for Process Management

```elixir
defmodule Snakepit.Adapter do
  # Initialize adapter resources
  @callback init(config :: keyword()) :: {:ok, state} | {:error, reason}
  
  # Clean up adapter resources  
  @callback terminate(reason :: term(), state :: term()) :: term()
  
  # Start a worker process
  @callback start_worker(adapter_state :: term(), worker_id :: term()) :: 
    {:ok, worker_pid} | {:error, reason}
    
  # Check if adapter supports streaming
  @callback supports_streaming?() :: boolean()
  
  # Execute streaming command
  @callback execute_stream(command, args, callback, opts) :: :ok | {:error, reason}
  
  # Get session-specific worker (for affinity)
  @callback get_session_worker(session_id :: String.t()) :: 
    {:ok, worker_id} | {:error, :not_found}
    
  # Store session-worker affinity
  @callback store_session_worker(session_id :: String.t(), worker_id :: String.t()) :: :ok
end
```

## Process Management Flow

### 1. Worker Startup

```elixir
# Snakepit initiates worker startup
Snakepit.Pool.start_workers_concurrently(count, timeout, worker_module, adapter_module)
  ↓
# Calls adapter to start actual process
adapter_module.start_worker(adapter_state, worker_id)
  ↓
# SnakepitGRPCBridge.Adapter implementation
def start_worker(adapter_state, worker_id) do
  # Reserve tracking slot FIRST (prevents orphans)
  :ok = Snakepit.Pool.ProcessRegistry.reserve_worker(worker_id)
  
  # Start Python process with unique identifiers
  python_args = build_python_args(worker_id, adapter_state)
  port = start_python_port(python_args)
  
  # Get actual OS PID for tracking
  os_pid = get_os_pid(port)
  fingerprint = generate_fingerprint(worker_id)
  
  # Activate tracking with real process info
  Snakepit.Pool.ProcessRegistry.activate_worker(
    worker_id, 
    self(),      # Elixir PID
    os_pid,      # OS PID
    fingerprint  # Unique identifier
  )
  
  {:ok, self()}
end
```

### 2. Process Tracking Requirements

The adapter MUST provide to ProcessRegistry:
- **worker_id**: Unique identifier for the worker
- **elixir_pid**: BEAM process managing the external process
- **process_pid**: Actual OS PID of external process
- **fingerprint**: Unique identifier for orphan detection

### 3. Orphan Prevention Strategy

```python
# Python process started with unique BEAM run ID
python grpc_server.py \
  --worker-id worker_123 \
  --snakepit-run-id "1234567890_123456" \
  --port 50051
```

This enables targeted cleanup:
```bash
# Snakepit can kill only processes from its run
pkill -9 -f "grpc_server.py.*--snakepit-run-id 1234567890_123456"
```

### 4. Graceful Shutdown Contract

```elixir
# SnakepitGRPCBridge must handle shutdown signals
def terminate(reason, state) do
  # 1. Close gRPC connections gracefully
  close_grpc_connections(state)
  
  # 2. Send shutdown command to Python
  send_shutdown_command(state)
  
  # 3. Wait briefly for acknowledgment
  wait_for_ack(state, timeout: 1000)
  
  # Snakepit will handle forceful termination if needed
  :ok
end
```

## Communication Channel Management

### Snakepit Provides
- Process lifecycle hooks (init, execute, terminate)
- Worker identity and session context
- Automatic restart on failure
- Request routing and queuing

### SnakepitGRPCBridge Implements
```elixir
defmodule SnakepitGRPCBridge.Python.Process do
  use GenServer
  
  # Manages Port/gRPC connection to Python
  defstruct [:port, :os_pid, :grpc_channel, :worker_id]
  
  def init({worker_id, config}) do
    # Start Python process via Port
    port = Port.open({:spawn_executable, python_path()}, [
      args: build_args(worker_id, config),
      env: build_env(config),
      cd: working_directory()
    ])
    
    # Get OS PID for tracking
    os_pid = get_os_pid_from_port(port)
    
    # Establish gRPC connection
    grpc_channel = establish_grpc_connection(config.grpc_port)
    
    {:ok, %__MODULE__{
      port: port,
      os_pid: os_pid, 
      grpc_channel: grpc_channel,
      worker_id: worker_id
    }}
  end
  
  # Handle Port messages
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Log Python stdout/stderr
    Logger.debug("Python output: #{data}")
    {:noreply, state}
  end
  
  # Handle Port exit
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, {:python_exit, status}, state}
  end
end
```

## Session Affinity Contract

### Platform-Managed Affinity
```elixir
defmodule SnakepitGRPCBridge.SessionManager do
  # Platform owns session-to-worker mapping
  def store_session_affinity(session_id, worker_id) do
    # Store in ETS/Redis/Database
    :ets.insert(:session_workers, {session_id, worker_id})
  end
  
  def get_worker_for_session(session_id) do
    case :ets.lookup(:session_workers, session_id) do
      [{^session_id, worker_id}] -> {:ok, worker_id}
      [] -> {:error, :not_found}
    end
  end
end

# Adapter implements the callbacks
defmodule SnakepitGRPCBridge.Adapter do
  def get_session_worker(session_id) do
    SnakepitGRPCBridge.SessionManager.get_worker_for_session(session_id)
  end
  
  def store_session_worker(session_id, worker_id) do
    SnakepitGRPCBridge.SessionManager.store_session_affinity(session_id, worker_id)
  end
end
```

## Error Handling and Recovery

### Infrastructure Handles
- Worker process crashes → automatic restart
- Request timeouts → client notification
- Queue overflow → backpressure
- VM shutdown → process cleanup

### Platform Handles
- gRPC connection failures → reconnection logic
- Python exceptions → error translation
- Protocol errors → graceful degradation
- Resource exhaustion → throttling

## Monitoring and Observability

### Snakepit Provides
```elixir
# Worker statistics
%{
  total_workers: 8,
  available_workers: 6,
  busy_workers: 2,
  queued_requests: 3,
  total_requests: 1000,
  errors: 5
}

# Process tracking info
%{
  registered_processes: 8,
  alive_processes: 8,
  orphaned_cleaned: 0
}
```

### Platform Enhances
```elixir
# ML-specific metrics
%{
  grpc_connections: 8,
  python_memory_mb: 512,
  model_loaded: true,
  inference_latency_ms: 45,
  gpu_utilization: 0.75
}
```

## Best Practices for Platform Implementation

### 1. Process Initialization
```python
# Python side
class SnakepitWorker:
    def __init__(self, worker_id, beam_run_id):
        # Set process group for clean termination
        os.setsid()
        
        # Store identifiers for debugging
        self.worker_id = worker_id
        self.beam_run_id = beam_run_id
        
        # Set up graceful shutdown
        signal.signal(signal.SIGTERM, self.handle_shutdown)
        
        # Start gRPC server
        self.start_grpc_server()
    
    def handle_shutdown(self, signum, frame):
        logger.info(f"Worker {self.worker_id} received shutdown signal")
        self.cleanup()
        sys.exit(0)
```

### 2. Health Checking
```elixir
# Platform implements health checks
defmodule SnakepitGRPCBridge.HealthCheck do
  def check_worker_health(worker_state) do
    case grpc_health_check(worker_state.grpc_channel) do
      {:ok, :serving} -> :healthy
      {:ok, :not_serving} -> :unhealthy
      {:error, _} -> :disconnected
    end
  end
end
```

### 3. Resource Management
```elixir
# Platform manages ML-specific resources
defmodule SnakepitGRPCBridge.ResourceManager do
  def before_worker_start(worker_id) do
    # Ensure GPU is available
    # Pre-load models if needed
    # Set memory limits
  end
  
  def after_worker_stop(worker_id) do
    # Release GPU allocation
    # Clear model cache
    # Cleanup temp files
  end
end
```

## Summary

The process management contract ensures:

1. **Snakepit** provides robust, generic process lifecycle management
2. **SnakepitGRPCBridge** implements ML-specific process behavior
3. **Clear boundaries** prevent coupling between layers
4. **Adapter pattern** enables different platforms to customize behavior
5. **No process orphans** through comprehensive tracking and cleanup
6. **Graceful operations** with proper shutdown sequencing

This separation allows Snakepit to remain a pure infrastructure component while SnakepitGRPCBridge owns all ML platform complexity, including gRPC communication, Python bridge specifics, and domain logic.
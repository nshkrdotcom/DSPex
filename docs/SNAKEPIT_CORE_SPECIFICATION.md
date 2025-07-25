# Snakepit Core Technical Specification

## Overview

Snakepit Core is the minimal infrastructure package providing high-performance worker pooling and session management for external processes. After separation, it contains only the essential OTP-based pooling logic with no domain-specific concerns.

## Architecture Principles

### Single Responsibility
Snakepit Core handles **only** infrastructure concerns:
- Worker process lifecycle management
- Session affinity and routing
- Adapter pattern for external process communication
- Performance monitoring and statistics

### Domain Agnostic
The core makes **no assumptions** about:
- What external processes do (Python, Ruby, Node.js, etc.)
- What protocols are used (gRPC, JSON-RPC, TCP, etc.)
- What data is processed (ML models, databases, APIs, etc.)

## Core Components

### 1. Public API Module (`Snakepit`)

**File**: `lib/snakepit.ex`  
**Responsibility**: Main entry point and convenience functions

```elixir
defmodule Snakepit do
  @moduledoc """
  Snakepit - High-performance pooler and session manager for external processes.
  
  Provides OTP-based worker pooling with session affinity, designed to work
  with any external process through the adapter pattern.
  """

  @doc """
  Execute a command on any available worker.
  
  ## Examples
  
      {:ok, result} = Snakepit.execute("ping", %{message: "hello"})
      {:ok, data} = Snakepit.execute("process_data", %{items: [1, 2, 3]})
  
  ## Options
  
    * `:timeout` - Command timeout in milliseconds (default: 30000)
    * `:pool` - Specific pool to use (default: Snakepit.Pool)
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(command, args, opts \\ [])

  @doc """
  Execute a command with session affinity.
  
  Ensures that subsequent calls with the same session_id prefer the same
  worker when possible, enabling stateful operations.
  
  ## Examples
  
      # Initialize session state
      {:ok, _} = Snakepit.execute_in_session("user_123", "init_session", %{})
      
      # Use session state
      {:ok, result} = Snakepit.execute_in_session("user_123", "get_state", %{})
  """
  @spec execute_in_session(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def execute_in_session(session_id, command, args, opts \\ [])

  @doc """
  Execute a streaming command with callback.
  
  Only supported by adapters that implement streaming (e.g., gRPC).
  
  ## Examples
  
      Snakepit.execute_stream("batch_process", %{items: data}, fn chunk ->
        IO.inspect(chunk, label: "Received")
      end)
  """
  @spec execute_stream(String.t(), map(), (term() -> any()), keyword()) :: 
    :ok | {:error, term()}
  def execute_stream(command, args, callback_fn, opts \\ [])

  @doc """
  Execute streaming command with session affinity.
  """
  @spec execute_in_session_stream(String.t(), String.t(), map(), (term() -> any()), keyword()) :: 
    :ok | {:error, term()}
  def execute_in_session_stream(session_id, command, args, callback_fn, opts \\ [])

  @doc """
  Get current pool statistics.
  
  ## Returns
  
      %{
        total_workers: 4,
        available_workers: 2,
        busy_workers: 2,
        total_requests: 1250,
        avg_response_time_ms: 45.3,
        error_rate: 0.02
      }
  """
  @spec get_stats(atom()) :: map()
  def get_stats(pool \\ Snakepit.Pool)

  @doc """
  List all workers with their current status.
  """
  @spec list_workers(atom()) :: [map()]
  def list_workers(pool \\ Snakepit.Pool)

  @doc """
  Run function with automatic Snakepit lifecycle management.
  
  Handles application start, pool initialization, and graceful shutdown.
  Perfect for scripts and Mix tasks.
  
  ## Examples
  
      Snakepit.run_as_script(fn ->
        {:ok, result} = Snakepit.execute("my_command", %{data: "test"})
        IO.inspect(result)
      end)
  """
  @spec run_as_script((-> any()), keyword()) :: any() | {:error, term()}
  def run_as_script(fun, opts \\ [])
end
```

### 2. Pool Management (`Snakepit.Pool`)

**File**: `lib/snakepit/pool/pool.ex`  
**Responsibility**: Core worker pool logic

```elixir
defmodule Snakepit.Pool do
  @moduledoc """
  High-performance OTP worker pool with session affinity.
  
  Manages worker lifecycle, load balancing, and session routing.
  Completely adapter-agnostic.
  """
  
  use GenServer
  require Logger

  @doc """
  Start the worker pool.
  
  ## Options
  
    * `:size` - Number of workers to start (default: 4)
    * `:adapter_module` - Module implementing Snakepit.Adapter behavior
    * `:worker_timeout` - Individual worker timeout (default: 30000)
    * `:name` - Pool name (default: __MODULE__)
  """
  def start_link(opts \\ [])

  @doc """
  Execute command on any available worker.
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(command, args, opts \\ [])

  @doc """
  Execute streaming command with callback.
  """
  @spec execute_stream(String.t(), map(), (term() -> any()), keyword()) :: 
    :ok | {:error, term()}
  def execute_stream(command, args, callback_fn, opts \\ [])

  @doc """
  Wait for pool to be fully initialized.
  
  Used by run_as_script/2 to ensure deterministic startup.
  """
  @spec await_ready(atom(), timeout()) :: :ok | {:error, :timeout}
  def await_ready(pool, timeout \\ 15_000)

  @doc """
  Get detailed pool statistics.
  """
  @spec get_stats(atom()) :: map()
  def get_stats(pool \\ __MODULE__)

  @doc """
  List workers with status information.
  """
  @spec list_workers(atom()) :: [map()]
  def list_workers(pool \\ __MODULE__)

  # Internal GenServer implementation
  # - Worker selection algorithms (round-robin, session affinity)
  # - Load balancing and health checks
  # - Performance monitoring and telemetry
  # - Graceful shutdown handling
end
```

### 3. Worker Registry (`Snakepit.Pool.Registry`)

**File**: `lib/snakepit/pool/registry.ex`  
**Responsibility**: Worker process registration and discovery

```elixir
defmodule Snakepit.Pool.Registry do
  @moduledoc """
  Registry for worker processes with session affinity tracking.
  
  Maintains mapping between sessions and preferred workers for
  stateful operations.
  """

  @doc """
  Register a worker process.
  """
  @spec register_worker(pid(), map()) :: :ok | {:error, term()}
  def register_worker(worker_pid, metadata)

  @doc """
  Get available worker for command execution.
  
  Implements session affinity when session_id is provided.
  """
  @spec get_worker(keyword()) :: {:ok, pid()} | {:error, term()}
  def get_worker(opts \\ [])

  @doc """
  Get preferred worker for session.
  
  Falls back to any available worker if preferred worker is unavailable.
  """
  @spec get_session_worker(String.t()) :: {:ok, pid()} | {:error, term()}
  def get_session_worker(session_id)

  @doc """
  Mark worker as busy/available.
  """
  @spec update_worker_status(pid(), :busy | :available) :: :ok
  def update_worker_status(worker_pid, status)

  @doc """
  Remove worker from registry.
  """
  @spec unregister_worker(pid()) :: :ok
  def unregister_worker(worker_pid)
end
```

### 4. Worker Starter Registry (`Snakepit.Pool.WorkerStarterRegistry`)

**File**: `lib/snakepit/pool/worker_starter_registry.ex`  
**Responsibility**: Managing worker process initialization

```elixir
defmodule Snakepit.Pool.WorkerStarterRegistry do
  @moduledoc """
  Registry for tracking worker initialization processes.
  
  Prevents race conditions during concurrent worker startup
  and provides initialization status tracking.
  """

  @doc """
  Start worker initialization process.
  """
  @spec start_worker_init(String.t(), module(), keyword()) :: 
    {:ok, pid()} | {:error, term()}
  def start_worker_init(worker_id, adapter_module, opts)

  @doc """
  Get initialization status for worker.
  """
  @spec get_init_status(String.t()) :: 
    :initializing | :ready | :failed | :not_found
  def get_init_status(worker_id)

  @doc """
  Mark worker initialization as complete.
  """
  @spec complete_init(String.t(), pid()) :: :ok
  def complete_init(worker_id, worker_pid)

  @doc """
  Mark worker initialization as failed.
  """
  @spec fail_init(String.t(), term()) :: :ok
  def fail_init(worker_id, reason)
end
```

### 5. Session Helpers (`Snakepit.SessionHelpers`)

**File**: `lib/snakepit/session_helpers.ex`  
**Responsibility**: Session affinity utilities (domain-agnostic)

```elixir
defmodule Snakepit.SessionHelpers do
  @moduledoc """
  Utilities for session-based operations.
  
  Provides session affinity without domain-specific logic.
  All domain enhancement should be handled by bridges.
  """

  @doc """
  Execute command with session context.
  
  This is the raw session execution - no domain-specific enhancement.
  For ML/DSP workflows, use bridge-specific helpers.
  """
  @spec execute_with_session(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def execute_with_session(session_id, command, args, opts \\ [])

  @doc """
  Get session affinity information.
  """
  @spec get_session_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_session_info(session_id)

  @doc """
  Clean up session resources.
  
  This only handles core Snakepit session cleanup.
  Bridge-specific cleanup should be handled by the bridge.
  """
  @spec cleanup_session(String.t()) :: :ok | {:error, term()}
  def cleanup_session(session_id)
end
```

### 6. Adapter Behavior (`Snakepit.Adapter`)

**File**: `lib/snakepit/adapter.ex`  
**Responsibility**: Interface contract for external process adapters

```elixir
defmodule Snakepit.Adapter do
  @moduledoc """
  Behavior for external process adapters.
  
  All domain-specific logic (DSPy, gRPC, variables, etc.) should be
  implemented in separate bridge packages that implement this behavior.
  """

  @doc """
  Execute a command through the external process.
  
  This is the core integration point between Snakepit and bridges.
  """
  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}

  @doc """
  Execute a streaming command with callback.
  
  Optional callback - adapters that don't support streaming should
  return {:error, :streaming_not_supported}.
  """
  @callback execute_stream(
    command :: String.t(), 
    args :: map(), 
    callback :: (term() -> any()), 
    opts :: keyword()
  ) :: :ok | {:error, term()}

  @doc """
  Check if adapter uses gRPC protocol.
  
  Used by core to determine streaming support availability.
  """
  @callback uses_grpc?() :: boolean()

  @doc """
  Check if adapter supports streaming operations.
  """
  @callback supports_streaming?() :: boolean()

  @doc """
  Initialize adapter with given configuration.
  
  Called once during pool startup.
  """
  @callback init(config :: keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Clean up adapter resources.
  
  Called during pool shutdown.
  """
  @callback terminate(reason :: term(), state :: term()) :: term()

  @optional_callbacks [
    execute_stream: 4,
    uses_grpc?: 0,
    supports_streaming?: 0,
    init: 1,
    terminate: 2
  ]
end
```

## Configuration System

### Application Configuration

```elixir
# config/config.exs
config :snakepit,
  # REQUIRED: Adapter module implementing Snakepit.Adapter
  adapter_module: YourBridge.Adapter,
  
  # Pool configuration
  pooling_enabled: true,
  pool_size: 4,
  worker_timeout: 30_000,
  
  # Session configuration
  session_affinity_enabled: true,
  session_cleanup_interval: 300_000,  # 5 minutes
  
  # Performance tuning
  max_retries: 3,
  retry_backoff_ms: 1000,
  
  # Monitoring
  telemetry_enabled: true,
  stats_collection_interval: 60_000   # 1 minute
```

### Runtime Configuration

```elixir
# Dynamic configuration through application environment
Application.put_env(:snakepit, :pool_size, 8)
Application.put_env(:snakepit, :adapter_module, NewAdapter)

# Configuration validation
defmodule Snakepit.Config do
  def validate_config! do
    adapter = Application.get_env(:snakepit, :adapter_module)
    
    unless adapter && Code.ensure_loaded?(adapter) do
      raise "Snakepit: adapter_module must be configured and available"
    end
    
    unless function_exported?(adapter, :execute, 3) do
      raise "Snakepit: adapter_module must implement Snakepit.Adapter behavior"
    end
    
    :ok
  end
end
```

## Performance Characteristics

### Benchmarks and Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Startup Time | < 2s | Pool initialization to ready state |
| Request Throughput | > 1000 req/s | With 4 workers, simple commands |
| Session Affinity Overhead | < 5ms | Additional routing time |
| Memory per Worker | < 50MB | Base OTP overhead only |
| Worker Recovery Time | < 10s | From failure to replacement ready |

### Performance Monitoring

```elixir
defmodule Snakepit.Telemetry do
  @moduledoc """
  Telemetry events emitted by Snakepit Core.
  
  All events are in the [:snakepit] namespace.
  """

  # Pool-level events
  # [:snakepit, :pool, :request] - Individual request metrics
  # [:snakepit, :pool, :worker_started] - Worker initialization
  # [:snakepit, :pool, :worker_stopped] - Worker termination
  
  # Session-level events  
  # [:snakepit, :session, :created] - New session started
  # [:snakepit, :session, :cleanup] - Session cleanup completed

  @doc """
  Attach telemetry handlers for performance monitoring.
  """
  def attach_handlers do
    :telemetry.attach_many(
      "snakepit-core-metrics",
      [
        [:snakepit, :pool, :request],
        [:snakepit, :pool, :worker_started],
        [:snakepit, :session, :created]
      ],
      &handle_event/4,
      %{}
    )
  end
  
  defp handle_event([:snakepit, :pool, :request], measurements, metadata, _config) do
    # Log performance metrics
    Logger.info(
      "Pool request completed",
      command: metadata.command,
      duration_ms: measurements.duration,
      worker_id: metadata.worker_id
    )
  end
end
```

## Error Handling and Resilience

### Worker Failure Recovery
```elixir
defmodule Snakepit.Pool.Supervisor do
  @moduledoc """
  Supervisor for worker processes with automatic restart.
  """
  
  def init(_) do
    children = [
      # Pool manager
      {Snakepit.Pool, pool_config()},
      
      # Worker registry
      {Snakepit.Pool.Registry, []},
      
      # Worker starter registry
      {Snakepit.Pool.WorkerStarterRegistry, []},
      
      # Dynamic supervisor for workers
      {DynamicSupervisor, name: Snakepit.WorkerSupervisor, strategy: :one_for_one}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Circuit Breaker Pattern
```elixir
defmodule Snakepit.Pool.CircuitBreaker do
  @moduledoc """
  Circuit breaker for adapter calls to prevent cascade failures.
  """
  
  @doc """
  Execute command with circuit breaker protection.
  """
  def safe_execute(adapter, command, args, opts) do
    case get_circuit_state(adapter) do
      :closed -> 
        try_execute(adapter, command, args, opts)
      :open -> 
        {:error, :circuit_breaker_open}
      :half_open -> 
        try_recovery_execute(adapter, command, args, opts)
    end
  end
end
```

## Testing Strategy

### Unit Testing Structure
```
test/
├── snakepit_test.exs                 # Public API tests
├── snakepit/
│   ├── pool/
│   │   ├── pool_test.exs             # Pool logic tests
│   │   ├── registry_test.exs         # Worker registry tests
│   │   └── worker_starter_registry_test.exs
│   ├── session_helpers_test.exs      # Session utilities tests
│   └── adapter_test.exs              # Adapter behavior tests
├── support/
│   ├── mock_adapter.ex               # Test adapter implementation
│   └── test_helpers.ex               # Common test utilities
└── integration/
    ├── pool_integration_test.exs     # End-to-end pool tests
    └── session_integration_test.exs  # Session affinity tests
```

### Mock Adapter for Testing
```elixir
defmodule Snakepit.Test.MockAdapter do
  @behaviour Snakepit.Adapter
  
  def execute("ping", _args, _opts), do: {:ok, %{status: "pong"}}
  def execute("error", _args, _opts), do: {:error, "simulated error"}
  def execute("slow", _args, opts) do
    timeout = Keyword.get(opts, :delay, 1000)
    Process.sleep(timeout)
    {:ok, %{delay: timeout}}
  end
  
  def uses_grpc?, do: false
  def supports_streaming?, do: false
  
  def init(_config), do: {:ok, %{}}
  def terminate(_reason, _state), do: :ok
end
```

## Security Considerations

### Input Validation
```elixir
defmodule Snakepit.Validation do
  @doc """
  Validate command input to prevent injection attacks.
  """
  def validate_command(command) when is_binary(command) do
    if String.printable?(command) and byte_size(command) < 1000 do
      :ok
    else
      {:error, :invalid_command}
    end
  end
  
  @doc """
  Validate arguments map structure.
  """
  def validate_args(args) when is_map(args) do
    # Size limits to prevent DoS
    if map_size(args) < 100 and deep_size(args) < 10_000 do
      :ok
    else
      {:error, :args_too_large}
    end
  end
end
```

### Session Security
```elixir
defmodule Snakepit.Session.Security do
  @doc """
  Generate cryptographically secure session IDs.
  """
  def generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
  
  @doc """
  Validate session ID format to prevent directory traversal.
  """
  def validate_session_id(session_id) do
    if String.match?(session_id, ~r/^[A-Za-z0-9_-]+$/) do
      :ok
    else
      {:error, :invalid_session_id}
    end
  end
end
```

## Dependencies

### Required Dependencies
```elixir
# mix.exs
defp deps do
  [
    # Core OTP/Elixir - no external dependencies
    # This is intentional to keep the core minimal and stable
  ]
end
```

### Optional Dependencies
```elixir
# For enhanced monitoring (opt-in)
{:telemetry_metrics, "~> 0.6", optional: true},
{:telemetry_poller, "~> 1.0", optional: true}
```

## Backward Compatibility

### Deprecated APIs (Removed in 0.4.0)
```elixir
# These were moved to snakepit_grpc_bridge
# DSPy-specific functionality
defmodule Snakepit.Bridge do
  @deprecated "Use SnakepitGrpcBridge.DSPy instead"
  def call_dspy(module_path, function_name, args, opts \\ [])
end

# Variables functionality
defmodule Snakepit.Variables do
  @deprecated "Use SnakepitGrpcBridge.Variables instead"
  def get(ctx, identifier, default \\ nil)
end
```

### Migration Shims (Temporary)
```elixir
# Provide helpful error messages during migration
defmodule Snakepit.Bridge do
  def call_dspy(_module_path, _function_name, _args, _opts) do
    raise """
    Snakepit.Bridge has been moved to SnakepitGrpcBridge.
    
    Add to your mix.exs:
        {:snakepit_grpc_bridge, "~> 0.1"}
    
    Update your code:
        Snakepit.Bridge.call_dspy(...) 
        # becomes
        SnakepitGrpcBridge.execute_dspy(session_id, ...)
    
    See migration guide: docs/SNAKEPIT_SEPARATION_MIGRATION.md
    """
  end
end
```

This specification ensures Snakepit Core remains focused, stable, and reusable while providing clear interfaces for bridge implementations.
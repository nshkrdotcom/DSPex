# Snakepit Infrastructure Specification

## Overview

Snakepit provides **pure infrastructure** for external process management with gRPC transport. It is completely domain-agnostic and can support any type of external process bridge.

## Core Capabilities

Snakepit is a production-grade process management foundation providing:

- **Dynamic Worker Supervision:** Manages a dynamic set of workers using the robust 'Permanent Wrapper' OTP pattern (`DynamicSupervisor` -> `Starter` -> `Worker`) for automatic, self-healing restarts.
- **Persistent OS Process Tracking:** Utilizes a DETS-backed registry (`ProcessRegistry`) to track OS-level PIDs, ensuring no orphaned processes across application restarts.
- **Guaranteed Process Cleanup:** An `ApplicationCleanup` module hooks into VM shutdown to ensure all external processes are terminated gracefully, escalating to `SIGKILL` only when necessary.
- **Pluggable Adapters:** A clean `Snakepit.Adapter` behavior allows any external process bridge to be integrated seamlessly.

## Core Principles

### 1. Pure Infrastructure Only
- Process pooling and lifecycle management
- Session affinity and routing
- Adapter pattern for bridge implementations
- **Zero domain-specific logic**
- **Does not mandate communication protocol** - adapters are free to use Ports, gRPC, or other mechanisms

### 2. Generic and Reusable
- Can host ML bridges, data processing bridges, etc.
- Adapter pattern enables any external process integration

### 3. Stable and Reliable
- Changes infrequently (infrastructure concerns)
- Focus on performance, reliability, and monitoring
- Production-ready OTP practices

## Module Architecture

### Core Structure
```
snakepit/
├── lib/snakepit.ex                # Public API
├── lib/snakepit/
│   ├── application.ex             # OTP application
│   ├── pool/
│   │   ├── pool.ex               # Worker pool management
│   │   ├── registry.ex           # Worker registry
│   │   └── supervisor.ex         # Pool supervision
│   ├── session/
│   │   ├── manager.ex            # Session lifecycle
│   │   ├── affinity.ex           # Session affinity tracking
│   │   └── cleanup.ex            # Session cleanup
│   ├── adapter.ex                # Adapter behavior
│   └── telemetry.ex              # Infrastructure telemetry
└── test/
```

## Detailed Module Specifications

### 1. Main API (`lib/snakepit.ex`)

```elixir
defmodule Snakepit do
  @moduledoc """
  Generic infrastructure for external process management with gRPC transport.
  
  Provides high-performance OTP-based worker pooling with session affinity,
  designed to support any external process bridge through the adapter pattern.
  """

  @doc """
  Execute command on any available worker.
  
  Routes to adapter-specific implementation for execution.
  
  ## Examples
  
      {:ok, result} = Snakepit.execute("process_task", %{data: "input"})
  
  ## Options
  
    * `:timeout` - Command timeout in milliseconds (default: 30000)
    * `:pool` - Specific pool to use (default: Snakepit.Pool)
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(command, args, opts \\ []) do
    Snakepit.Pool.execute(command, args, opts)
  end

  @doc """
  Execute command with session affinity.
  
  Ensures that subsequent calls with the same session_id prefer the same
  worker when possible, enabling stateful operations.
  
  ## Examples
  
      # Initialize session
      {:ok, _} = Snakepit.execute_in_session("user_123", "init_session", %{})
      
      # Use session state  
      {:ok, result} = Snakepit.execute_in_session("user_123", "process_with_context", %{})
  """
  @spec execute_in_session(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def execute_in_session(session_id, command, args, opts \\ []) do
    opts_with_session = Keyword.put(opts, :session_id, session_id)
    execute(command, args, opts_with_session)
  end

  @doc """
  Execute streaming command with callback.
  
  Only supported by adapters that implement streaming capabilities.
  """
  @spec execute_stream(String.t(), map(), (term() -> any()), keyword()) :: 
    :ok | {:error, term()}
  def execute_stream(command, args, callback_fn, opts \\ []) do
    Snakepit.Pool.execute_stream(command, args, callback_fn, opts)
  end

  @doc """
  Get pool statistics for monitoring.
  """
  @spec get_stats(atom()) :: map()
  def get_stats(pool \\ Snakepit.Pool) do
    Snakepit.Pool.get_stats(pool)
  end

  @doc """
  List all workers with status information.
  """
  @spec list_workers(atom()) :: [map()]
  def list_workers(pool \\ Snakepit.Pool) do
    Snakepit.Pool.list_workers(pool)
  end

  @doc """
  Wait for pool to be ready.
  """
  @spec await_ready(atom(), pos_integer()) :: :ok | {:error, term()}
  def await_ready(pool \\ Snakepit.Pool, timeout \\ 15_000) do
    Snakepit.Pool.await_ready(pool, timeout)
  end
end
```

### 2. Worker Pool (`lib/snakepit/pool/pool.ex`)

```elixir
defmodule Snakepit.Pool do
  @moduledoc """
  Generic worker pool for external process management.
  
  Manages worker lifecycle, load balancing, and session routing.
  Completely adapter-agnostic.
  """
  
  use GenServer
  require Logger

  defstruct [
    :workers,
    :available_workers,
    :busy_workers,
    :adapter_module,
    :pool_config,
    :session_affinity_tracker,
    :stats,
    :telemetry_collector
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def init(opts) do
    # Get adapter module from configuration
    adapter_module = opts[:adapter_module] || 
                    Application.get_env(:snakepit, :adapter_module) ||
                    raise "Snakepit: adapter_module must be configured"

    # Validate adapter implements required behavior
    unless function_exported?(adapter_module, :execute, 3) do
      raise "Snakepit: adapter_module must implement Snakepit.Adapter behavior"
    end

    pool_config = %{
      size: opts[:size] || Application.get_env(:snakepit, :pool_size, 4),
      worker_timeout: opts[:worker_timeout] || Application.get_env(:snakepit, :worker_timeout, 30_000),
      session_affinity_enabled: Application.get_env(:snakepit, :session_affinity_enabled, true)
    }

    state = %__MODULE__{
      workers: [],
      available_workers: [],
      busy_workers: MapSet.new(),
      adapter_module: adapter_module,
      pool_config: pool_config,
      session_affinity_tracker: %{},
      stats: initialize_stats(),
      telemetry_collector: Snakepit.Telemetry.new_collector(:pool)
    }

    # Initialize adapter
    case adapter_module.init(opts) do
      {:ok, adapter_state} ->
        case start_initial_workers(state, adapter_state) do
          {:ok, updated_state} ->
            {:ok, updated_state}
          {:error, reason} ->
            {:stop, reason}
        end
      {:error, reason} ->
        {:stop, reason}
    end
  end

  def execute(command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute, command, args, opts})
  end

  def execute_stream(command, args, callback_fn, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_stream, command, args, callback_fn, opts})
  end

  def handle_call({:execute, command, args, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    session_id = opts[:session_id]

    # Select optimal worker (with session affinity if enabled)
    case select_optimal_worker(state, session_id) do
      {:ok, worker_pid} ->
        # Execute on selected worker through adapter
        result = execute_on_worker(worker_pid, state.adapter_module, command, args, opts)
        
        # Update worker status
        updated_state = update_worker_status_after_execution(state, worker_pid, result)
        
        # Collect telemetry
        execution_time = System.monotonic_time(:microsecond) - start_time
        telemetry_data = build_execution_telemetry(command, args, result, execution_time, session_id, worker_pid)
        final_state = record_execution_telemetry(updated_state, telemetry_data)
        
        {:reply, result, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:execute_stream, command, args, callback_fn, opts}, _from, state) do
    # Check if adapter supports streaming
    if function_exported?(state.adapter_module, :execute_stream, 4) do
      case select_optimal_worker(state, opts[:session_id]) do
        {:ok, worker_pid} ->
          result = state.adapter_module.execute_stream(command, args, callback_fn, 
                                                     Keyword.put(opts, :worker_pid, worker_pid))
          {:reply, result, state}
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :streaming_not_supported}, state}
    end
  end

  def get_stats(pool \\ __MODULE__) do
    GenServer.call(pool, :get_stats)
  end

  def handle_call(:get_stats, _from, state) do
    current_stats = %{
      total_workers: length(state.workers),
      available_workers: length(state.available_workers),
      busy_workers: MapSet.size(state.busy_workers),
      total_requests: state.stats.total_requests,
      successful_requests: state.stats.successful_requests,
      failed_requests: state.stats.failed_requests,
      session_affinity_hits: state.stats.session_affinity_hits,
      last_updated: DateTime.utc_now()
    }
    
    {:reply, current_stats, state}
  end

  def list_workers(pool \\ __MODULE__) do
    GenServer.call(pool, :list_workers)
  end

  def handle_call(:list_workers, _from, state) do
    worker_details = Enum.map(state.workers, fn worker_pid ->
      %{
        pid: worker_pid,
        status: determine_worker_status(worker_pid, state),
        memory_usage: get_worker_memory_usage(worker_pid),
        uptime: get_worker_uptime(worker_pid)
      }
    end)
    
    {:reply, worker_details, state}
  end

  def await_ready(pool, timeout \\ 15_000) do
    GenServer.call(pool, :await_ready, timeout)
  end

  def handle_call(:await_ready, _from, state) do
    if length(state.available_workers) > 0 do
      {:reply, :ok, state}
    else
      {:reply, {:error, :no_workers_available}, state}
    end
  end

  # Private implementation functions
  
  defp select_optimal_worker(state, session_id) do
    cond do
      # Session affinity (when enabled and session exists)
      state.pool_config.session_affinity_enabled and session_id ->
        select_session_affinity_worker(state, session_id)
        
      # Load balancing for general requests
      length(state.available_workers) > 0 ->
        select_load_balanced_worker(state)
        
      # No workers available
      true ->
        {:error, :no_workers_available}
    end
  end

  defp select_session_affinity_worker(state, session_id) do
    case Map.get(state.session_affinity_tracker, session_id) do
      worker_pid when is_pid(worker_pid) ->
        if worker_pid in state.available_workers do
          {:ok, worker_pid}
        else
          # Fallback to load balancing
          select_load_balanced_worker(state)
        end
      
      nil ->
        # New session - select worker and establish affinity
        case select_load_balanced_worker(state) do
          {:ok, worker_pid} ->
            establish_session_affinity(state, session_id, worker_pid)
            {:ok, worker_pid}
          error ->
            error
        end
    end
  end

  defp select_load_balanced_worker(state) do
    # Simple round-robin for now
    case state.available_workers do
      [worker_pid | _] -> {:ok, worker_pid}
      [] -> {:error, :no_workers_available}
    end
  end

  defp execute_on_worker(worker_pid, adapter_module, command, args, opts) do
    # Mark worker as busy
    GenServer.cast(__MODULE__, {:mark_worker_busy, worker_pid})
    
    try do
      # Execute through adapter
      result = adapter_module.execute(command, args, Keyword.put(opts, :worker_pid, worker_pid))
      
      # Mark worker as available
      GenServer.cast(__MODULE__, {:mark_worker_available, worker_pid})
      
      result
    rescue
      exception ->
        # Mark worker as available even on error
        GenServer.cast(__MODULE__, {:mark_worker_available, worker_pid})
        {:error, {:execution_exception, Exception.message(exception)}}
    end
  end

  defp start_initial_workers(state, adapter_state) do
    worker_count = state.pool_config.size
    
    workers = for i <- 1..worker_count do
      case start_worker(state.adapter_module, adapter_state, i) do
        {:ok, worker_pid} -> worker_pid
        {:error, reason} -> 
          Logger.error("Failed to start worker #{i}: #{inspect(reason)}")
          nil
      end
    end
    |> Enum.filter(&(&1 != nil))
    
    if length(workers) > 0 do
      updated_state = %{state | 
        workers: workers,
        available_workers: workers
      }
      {:ok, updated_state}
    else
      {:error, :failed_to_start_workers}
    end
  end

  defp start_worker(adapter_module, adapter_state, worker_id) do
    # Start worker process through adapter
    case adapter_module.start_worker(adapter_state, worker_id) do
      {:ok, worker_pid} -> {:ok, worker_pid}
      {:error, reason} -> {:error, reason}
    end
  end

  # Worker status management
  def handle_cast({:mark_worker_busy, worker_pid}, state) do
    updated_state = %{state |
      available_workers: List.delete(state.available_workers, worker_pid),
      busy_workers: MapSet.put(state.busy_workers, worker_pid)
    }
    {:noreply, updated_state}
  end

  def handle_cast({:mark_worker_available, worker_pid}, state) do
    updated_state = %{state |
      available_workers: [worker_pid | state.available_workers],
      busy_workers: MapSet.delete(state.busy_workers, worker_pid)
    }
    {:noreply, updated_state}
  end

  # Helper functions
  defp initialize_stats do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      session_affinity_hits: 0
    }
  end

  defp build_execution_telemetry(command, args, result, execution_time, session_id, worker_pid) do
    %{
      command: command,
      args_size: :erlang.external_size(args),
      result_success: match?({:ok, _}, result),
      execution_time_microseconds: execution_time,
      session_id: session_id,
      worker_pid: worker_pid,
      timestamp: DateTime.utc_now()
    }
  end

  defp record_execution_telemetry(state, telemetry_data) do
    # Update statistics
    updated_stats = update_execution_stats(state.stats, telemetry_data)
    
    # Record telemetry
    Snakepit.Telemetry.record(state.telemetry_collector, telemetry_data)
    
    %{state | stats: updated_stats}
  end

  defp update_execution_stats(stats, telemetry_data) do
    %{stats |
      total_requests: stats.total_requests + 1,
      successful_requests: stats.successful_requests + (if telemetry_data.result_success, do: 1, else: 0),
      failed_requests: stats.failed_requests + (if telemetry_data.result_success, do: 0, else: 1)
    }
  end

  defp update_worker_status_after_execution(state, _worker_pid, _result), do: state
  defp establish_session_affinity(_state, _session_id, _worker_pid), do: :ok
  defp determine_worker_status(_worker_pid, _state), do: :available
  defp get_worker_memory_usage(_worker_pid), do: 0
  defp get_worker_uptime(_worker_pid), do: 0
end
```

### 3. Adapter Behavior (`lib/snakepit/adapter.ex`)

```elixir
defmodule Snakepit.Adapter do
  @moduledoc """
  Behavior for external process adapters.
  
  Defines the interface that bridge packages must implement to integrate
  with Snakepit infrastructure.
  """

  @doc """
  Execute a command through the external process.
  
  This is the core integration point between Snakepit and bridge implementations.
  
  ## Parameters
  
    * `command` - The command string to execute
    * `args` - Arguments as a map
    * `opts` - Options including worker_pid, session_id, timeout, etc.
  
  ## Returns
  
    * `{:ok, result}` - Successful execution with result
    * `{:error, reason}` - Execution failed with reason
  """
  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}

  @doc """
  Execute a streaming command with callback.
  
  Optional callback for adapters that support streaming operations.
  """
  @callback execute_stream(
    command :: String.t(), 
    args :: map(), 
    callback :: (term() -> any()), 
    opts :: keyword()
  ) :: :ok | {:error, term()}

  @doc """
  Initialize adapter with configuration.
  
  Called once during pool startup to initialize adapter-specific resources.
  """
  @callback init(config :: keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Clean up adapter resources.
  
  Called during pool shutdown to clean up adapter-specific resources.
  """
  @callback terminate(reason :: term(), adapter_state :: term()) :: term()

  @doc """
  Start a worker process for this adapter.
  
  Called to start individual worker processes that will handle commands.
  """
  @callback start_worker(adapter_state :: term(), worker_id :: term()) :: 
    {:ok, pid()} | {:error, term()}

  # Optional callbacks
  @optional_callbacks [
    execute_stream: 4,
    init: 1,
    terminate: 2,
    start_worker: 2
  ]

  @doc """
  Validate that a module properly implements the Snakepit.Adapter behavior.
  """
  def validate_implementation(module) do
    required_callbacks = [{:execute, 3}]
    
    missing_callbacks = Enum.filter(required_callbacks, fn {function, arity} ->
      not function_exported?(module, function, arity)
    end)
    
    if Enum.empty?(missing_callbacks) do
      :ok
    else
      {:error, missing_callbacks}
    end
  end
end
```

### 4. Configuration (`config/config.exs`)

```elixir
import Config

# Snakepit Infrastructure Configuration
config :snakepit,
  # REQUIRED: Adapter module that implements Snakepit.Adapter behavior
  # This will be set by bridge packages
  adapter_module: nil,
  
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
  
  # Telemetry and monitoring
  telemetry_enabled: true,
  telemetry_interval: 60_000,  # 1 minute
  stats_collection_interval: 60_000

# Environment-specific configuration
import_config "#{config_env()}.exs"
```

## Key Features

### 1. Pure Infrastructure Focus
- No domain-specific logic (DSPy, ML, etc.)
- Only process management, pooling, and transport
- Adapter pattern for all domain concerns

### 2. Generic and Reusable
- Can support any external process bridge
- Session management works for any stateful operations

### 3. Production Ready
- Comprehensive error handling
- Performance monitoring
- Health checks and recovery
- Graceful shutdown handling

### 4. Extensible Architecture
- Adapter pattern enables any bridge implementation
- Telemetry system provides observability
- Configuration-driven behavior

This specification defines Snakepit as pure, generic infrastructure that can support any external process bridge, providing the foundation for the ML platform layer without being tied to any specific domain.
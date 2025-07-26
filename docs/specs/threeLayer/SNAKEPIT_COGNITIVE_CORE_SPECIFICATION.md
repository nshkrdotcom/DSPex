# Snakepit Cognitive Core Technical Specification

## Overview

Snakepit Core provides the **minimal infrastructure foundation** that can support cognitive bridge functionality while remaining completely agnostic to domain-specific concerns. This is pure OTP-based infrastructure with cognitive-ready interfaces.

## Core Principles

### Pure Infrastructure Only
- Process pooling and lifecycle management
- Session affinity and routing  
- Adapter pattern for bridge implementations
- Performance monitoring infrastructure
- **Zero domain-specific logic**

### Cognitive-Ready Interfaces
- Telemetry collection points for future learning
- Extensible adapter behavior for cognitive bridges
- Session management that supports persistent state
- Performance monitoring that enables optimization

## Architecture

### Core Module Structure

```
snakepit/
├── lib/snakepit.ex                    # Public API
├── lib/snakepit/
│   ├── pool/
│   │   ├── pool.ex                    # Enhanced pool management
│   │   ├── registry.ex                # Worker registry with cognitive hooks
│   │   └── worker_starter_registry.ex # Worker initialization tracking
│   ├── session_helpers.ex             # Enhanced session management  
│   ├── adapter.ex                     # Cognitive-ready adapter behavior
│   └── telemetry.ex                   # Telemetry infrastructure
├── config/
│   └── config.exs                     # Core configuration
├── test/
└── README.md
```

## Detailed Module Specifications

### 1. Main API Module (`lib/snakepit.ex`)

```elixir
defmodule Snakepit do
  @moduledoc """
  Snakepit - Cognitive-ready infrastructure for external process management.
  
  Provides high-performance OTP-based worker pooling with session affinity,
  designed to support cognitive bridge implementations through the adapter pattern.
  """

  @doc """
  Execute command on any available worker.
  
  Routes through cognitive-ready scheduling that can be enhanced by bridges.
  
  ## Examples
  
      {:ok, result} = Snakepit.execute("process_task", %{data: "input"})
  
  ## Options
  
    * `:timeout` - Command timeout in milliseconds (default: 30000)
    * `:pool` - Specific pool to use (default: Snakepit.Pool)
    * `:telemetry_metadata` - Additional metadata for telemetry
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute(command, args, opts \\ []) do
    Snakepit.Pool.execute(command, args, opts)
  end

  @doc """
  Execute command with session affinity.
  
  Ensures that subsequent calls with the same session_id prefer the same
  worker when possible, enabling stateful operations and learning.
  
  ## Examples
  
      # Initialize session
      {:ok, _} = Snakepit.execute_in_session("user_123", "init_session", %{})
      
      # Use session state  
      {:ok, result} = Snakepit.execute_in_session("user_123", "process_with_context", %{})
  """
  @spec execute_in_session(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def execute_in_session(session_id, command, args, opts \\ []) do
    # Add session_id to opts for routing and telemetry
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
  Execute streaming command with session affinity.
  """
  @spec execute_in_session_stream(String.t(), String.t(), map(), (term() -> any()), keyword()) :: 
    :ok | {:error, term()}
  def execute_in_session_stream(session_id, command, args, callback_fn, opts \\ []) do
    opts_with_session = Keyword.put(opts, :session_id, session_id)
    execute_stream(command, args, callback_fn, opts_with_session)
  end

  @doc """
  Get comprehensive pool statistics.
  
  Returns cognitive-ready metrics that bridges can use for optimization.
  """
  @spec get_stats(atom()) :: map()
  def get_stats(pool \\ Snakepit.Pool) do
    Snakepit.Pool.get_stats(pool)
  end

  @doc """
  List all workers with detailed status information.
  
  Includes cognitive-ready metadata for intelligent routing.
  """
  @spec list_workers(atom()) :: [map()]
  def list_workers(pool \\ Snakepit.Pool) do
    Snakepit.Pool.list_workers(pool)
  end

  @doc """
  Run function with automatic Snakepit lifecycle management.
  
  Perfect for scripts and Mix tasks with cognitive bridge initialization.
  """
  @spec run_as_script((-> any()), keyword()) :: any() | {:error, term()}
  def run_as_script(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    {:ok, _apps} = Application.ensure_all_started(:snakepit)

    case Snakepit.Pool.await_ready(Snakepit.Pool, timeout) do
      :ok ->
        try do
          fun.()
        after
          IO.puts("\n[Snakepit] Script execution finished. Shutting down gracefully...")
          Application.stop(:snakepit)
          Process.sleep(500)
          IO.puts("[Snakepit] Shutdown complete.")
        end

      {:error, :timeout} ->
        IO.puts("[Snakepit] Error: Pool failed to initialize within #{timeout}ms")
        Application.stop(:snakepit)
        {:error, :pool_initialization_timeout}
    end
  end
end
```

### 2. Enhanced Pool Management (`lib/snakepit/pool/pool.ex`)

```elixir
defmodule Snakepit.Pool do
  @moduledoc """
  High-performance OTP worker pool with cognitive-ready infrastructure.
  
  Manages worker lifecycle, load balancing, and session routing with
  telemetry collection points for future cognitive enhancement.
  """
  
  use GenServer
  require Logger

  defstruct [
    # Core pool state
    :workers,
    :available_workers,
    :busy_workers,
    :adapter_module,
    :pool_config,
    
    # Cognitive-ready infrastructure
    :telemetry_collector,
    :performance_monitor,
    :session_affinity_tracker,
    :routing_intelligence,
    
    # Statistics and monitoring
    :stats,
    :worker_health_status
  ]

  @doc """
  Start the worker pool with cognitive-ready configuration.
  """
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
      
      # Initialize cognitive-ready infrastructure
      telemetry_collector: Snakepit.Telemetry.new_collector(:pool),
      performance_monitor: initialize_performance_monitor(),
      session_affinity_tracker: %{},
      routing_intelligence: %{total_requests: 0, routing_decisions: []},
      
      # Initialize statistics
      stats: initialize_stats(),
      worker_health_status: %{}
    }

    # Initialize adapter
    case adapter_module.init(opts) do
      {:ok, adapter_state} ->
        # Start workers
        case start_initial_workers(state, adapter_state) do
          {:ok, updated_state} ->
            # Start telemetry collection
            schedule_telemetry_collection()
            {:ok, updated_state}
          {:error, reason} ->
            {:stop, reason}
        end
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Execute command with cognitive-ready routing.
  """
  def execute(command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute, command, args, opts})
  end

  @doc """
  Execute streaming command with callback.
  """
  def execute_stream(command, args, callback_fn, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_stream, command, args, callback_fn, opts})
  end

  def handle_call({:execute, command, args, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    session_id = opts[:session_id]

    # Cognitive-ready worker selection
    case select_optimal_worker(state, command, args, session_id) do
      {:ok, worker_pid} ->
        # Execute on selected worker
        result = execute_on_worker(worker_pid, state.adapter_module, command, args, opts)
        
        # Update worker status
        updated_state = update_worker_status_after_execution(state, worker_pid, result)
        
        # Collect execution telemetry
        execution_time = System.monotonic_time(:microsecond) - start_time
        telemetry_data = build_execution_telemetry(command, args, result, execution_time, session_id, worker_pid)
        
        # Record for cognitive learning
        final_state = record_execution_telemetry(updated_state, telemetry_data)
        
        {:reply, result, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:execute_stream, command, args, callback_fn, opts}, _from, state) do
    # Check if adapter supports streaming
    if function_exported?(state.adapter_module, :execute_stream, 4) do
      case select_optimal_worker(state, command, args, opts[:session_id]) do
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

  @doc """
  Get comprehensive pool statistics.
  """
  def get_stats(pool \\ __MODULE__) do
    GenServer.call(pool, :get_stats)
  end

  def handle_call(:get_stats, _from, state) do
    current_stats = %{
      # Basic pool stats
      total_workers: length(state.workers),
      available_workers: length(state.available_workers),
      busy_workers: MapSet.size(state.busy_workers),
      
      # Performance stats
      total_requests: state.stats.total_requests,
      successful_requests: state.stats.successful_requests,
      failed_requests: state.stats.failed_requests,
      average_response_time_ms: calculate_average_response_time(state.stats),
      
      # Cognitive-ready stats
      session_affinity_hits: state.stats.session_affinity_hits,
      worker_specialization_data: collect_worker_specialization_data(state),
      routing_intelligence_score: calculate_routing_intelligence_score(state),
      
      # Health stats
      worker_health_distribution: calculate_health_distribution(state.worker_health_status),
      last_updated: DateTime.utc_now()
    }
    
    {:reply, current_stats, state}
  end

  @doc """
  List workers with cognitive-ready metadata.
  """
  def list_workers(pool \\ __MODULE__) do
    GenServer.call(pool, :list_workers)
  end

  def handle_call(:list_workers, _from, state) do
    worker_details = Enum.map(state.workers, fn worker_pid ->
      %{
        pid: worker_pid,
        status: determine_worker_status(worker_pid, state),
        health: Map.get(state.worker_health_status, worker_pid, :unknown),
        
        # Cognitive-ready metadata
        specialization_score: calculate_worker_specialization(worker_pid, state),
        performance_history: get_worker_performance_history(worker_pid, state),
        session_affinity_data: get_worker_session_data(worker_pid, state),
        
        # Basic metadata
        memory_usage: get_worker_memory_usage(worker_pid),
        uptime: get_worker_uptime(worker_pid),
        last_activity: get_worker_last_activity(worker_pid, state)
      }
    end)
    
    {:reply, worker_details, state}
  end

  @doc """
  Wait for pool to be fully initialized.
  """
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

  # Cognitive-ready worker selection
  defp select_optimal_worker(state, command, args, session_id) do
    cond do
      # Session affinity (when enabled and session exists)
      state.pool_config.session_affinity_enabled and session_id ->
        select_session_affinity_worker(state, session_id, command, args)
        
      # Load balancing for general requests
      length(state.available_workers) > 0 ->
        select_load_balanced_worker(state, command, args)
        
      # No workers available
      true ->
        {:error, :no_workers_available}
    end
  end

  defp select_session_affinity_worker(state, session_id, command, args) do
    case Map.get(state.session_affinity_tracker, session_id) do
      worker_pid when is_pid(worker_pid) ->
        if worker_pid in state.available_workers do
          # Session affinity hit
          record_session_affinity_hit(state, session_id, worker_pid)
          {:ok, worker_pid}
        else
          # Fallback to load balancing
          select_load_balanced_worker(state, command, args)
        end
      
      nil ->
        # New session - select worker and establish affinity
        case select_load_balanced_worker(state, command, args) do
          {:ok, worker_pid} ->
            establish_session_affinity(state, session_id, worker_pid)
            {:ok, worker_pid}
          error ->
            error
        end
    end
  end

  defp select_load_balanced_worker(state, _command, _args) do
    # Current: Simple round-robin
    # Future: Cognitive-ready for intelligent routing based on:
    # - Worker specialization scores
    # - Current load and performance
    # - Task complexity analysis
    # - Historical success patterns
    
    case state.available_workers do
      [worker_pid | _] ->
        {:ok, worker_pid}
      [] ->
        {:error, :no_workers_available}
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

  # Telemetry and monitoring
  defp build_execution_telemetry(command, args, result, execution_time, session_id, worker_pid) do
    %{
      command: command,
      args_complexity: analyze_args_complexity(args),
      result_success: match?({:ok, _}, result),
      execution_time_microseconds: execution_time,
      session_id: session_id,
      worker_pid: worker_pid,
      timestamp: DateTime.utc_now(),
      
      # Cognitive-ready metadata
      task_complexity_score: calculate_task_complexity(command, args),
      worker_suitability_score: 0.5,  # Placeholder for future cognitive scoring
      routing_decision_quality: 0.7   # Placeholder for future routing intelligence
    }
  end

  defp record_execution_telemetry(state, telemetry_data) do
    # Update statistics
    updated_stats = update_execution_stats(state.stats, telemetry_data)
    
    # Record telemetry for cognitive learning
    Snakepit.Telemetry.record(state.telemetry_collector, telemetry_data)
    
    # Update routing intelligence
    updated_routing = update_routing_intelligence(state.routing_intelligence, telemetry_data)
    
    %{state | 
      stats: updated_stats,
      routing_intelligence: updated_routing
    }
  end

  # Worker management
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
        available_workers: workers,
        worker_health_status: initialize_worker_health(workers)
      }
      {:ok, updated_state}
    else
      {:error, :failed_to_start_workers}
    end
  end

  defp start_worker(adapter_module, adapter_state, worker_id) do
    # Start worker process (implementation depends on adapter)
    # This is a simplified version - actual implementation would be more complex
    worker_spec = %{
      id: :"worker_#{worker_id}",
      start: {adapter_module, :start_worker, [adapter_state, worker_id]},
      restart: :transient
    }
    
    case DynamicSupervisor.start_child(Snakepit.WorkerSupervisor, worker_spec) do
      {:ok, worker_pid} -> {:ok, worker_pid}
      {:error, reason} -> {:error, reason}
    end
  end

  # Handler for worker status updates
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

  # Telemetry collection scheduling
  defp schedule_telemetry_collection do
    # Schedule periodic telemetry collection
    interval = Application.get_env(:snakepit, :telemetry_interval, 60_000)
    Process.send_after(self(), :collect_telemetry, interval)
  end

  def handle_info(:collect_telemetry, state) do
    # Collect and emit telemetry data
    telemetry_snapshot = %{
      pool_stats: get_current_pool_stats(state),
      worker_health: state.worker_health_status,
      routing_intelligence: state.routing_intelligence,
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit, :pool, :snapshot], telemetry_snapshot)
    
    # Schedule next collection
    schedule_telemetry_collection()
    
    {:noreply, state}
  end

  # Helper functions for cognitive-ready features
  defp initialize_performance_monitor do
    %{
      response_times: CircularBuffer.new(1000),
      error_rates: CircularBuffer.new(100),
      throughput_samples: CircularBuffer.new(60)
    }
  end

  defp initialize_stats do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      session_affinity_hits: 0,
      average_response_times: CircularBuffer.new(1000)
    }
  end

  defp initialize_worker_health(workers) do
    workers
    |> Enum.map(fn worker -> {worker, :healthy} end)
    |> Map.new()
  end

  defp analyze_args_complexity(args) when is_map(args) do
    %{
      parameter_count: map_size(args),
      total_size: :erlang.external_size(args),
      nesting_depth: calculate_map_depth(args)
    }
  end
  defp analyze_args_complexity(_args), do: %{complexity: :unknown}

  defp calculate_task_complexity(command, args) do
    # Simple complexity scoring for cognitive readiness
    command_complexity = String.length(command) / 50.0
    args_complexity = if is_map(args), do: map_size(args) / 10.0, else: 0.0
    
    min(command_complexity + args_complexity, 1.0)
  end

  # Additional helper functions would be implemented here...
  defp calculate_map_depth(map, current_depth \\ 0) when is_map(map) do
    if map_size(map) == 0 do
      current_depth
    else
      max_child_depth = map
      |> Map.values()
      |> Enum.map(fn 
           child_map when is_map(child_map) -> calculate_map_depth(child_map, current_depth + 1)
           _ -> current_depth
         end)
      |> Enum.max()
      
      max_child_depth
    end
  end
  defp calculate_map_depth(_, current_depth), do: current_depth

  # Placeholder implementations for cognitive-ready features
  defp record_session_affinity_hit(_state, _session_id, _worker_pid), do: :ok
  defp establish_session_affinity(_state, _session_id, _worker_pid), do: :ok
  defp update_worker_status_after_execution(state, _worker_pid, _result), do: state
  defp update_execution_stats(stats, _telemetry_data), do: stats
  defp update_routing_intelligence(routing, _telemetry_data), do: routing
  defp calculate_average_response_time(_stats), do: 0.0
  defp collect_worker_specialization_data(_state), do: %{}
  defp calculate_routing_intelligence_score(_state), do: 0.5
  defp calculate_health_distribution(_health_status), do: %{healthy: 100}
  defp determine_worker_status(_worker_pid, _state), do: :available
  defp calculate_worker_specialization(_worker_pid, _state), do: 0.5
  defp get_worker_performance_history(_worker_pid, _state), do: []
  defp get_worker_session_data(_worker_pid, _state), do: %{}
  defp get_worker_memory_usage(_worker_pid), do: 0
  defp get_worker_uptime(_worker_pid), do: 0
  defp get_worker_last_activity(_worker_pid, _state), do: DateTime.utc_now()
  defp get_current_pool_stats(state), do: %{workers: length(state.workers)}
end
```

### 3. Cognitive-Ready Adapter Behavior (`lib/snakepit/adapter.ex`)

```elixir
defmodule Snakepit.Adapter do
  @moduledoc """
  Behavior for cognitive-ready external process adapters.
  
  Defines the interface that bridge packages must implement to integrate
  with Snakepit Core infrastructure. Includes cognitive-ready hooks for
  future enhancement.
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
  
  ## Cognitive-Ready Features
  
  Implementations should collect telemetry data for future cognitive enhancement:
  - Execution time tracking
  - Success/failure patterns
  - Resource usage patterns
  - Performance characteristics
  """
  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}

  @doc """
  Execute a streaming command with callback.
  
  Optional callback for adapters that support streaming operations.
  
  ## Parameters
  
    * `command` - The streaming command to execute
    * `args` - Arguments as a map
    * `callback` - Function called for each streaming result
    * `opts` - Options including session context
  
  ## Returns
  
    * `:ok` - Streaming completed successfully
    * `{:error, reason}` - Streaming failed
  """
  @callback execute_stream(
    command :: String.t(), 
    args :: map(), 
    callback :: (term() -> any()), 
    opts :: keyword()
  ) :: :ok | {:error, term()}

  @doc """
  Check if adapter uses gRPC protocol.
  
  Used by core infrastructure to optimize communication patterns.
  """
  @callback uses_grpc?() :: boolean()

  @doc """
  Check if adapter supports streaming operations.
  
  Used by core infrastructure to route streaming requests appropriately.
  """
  @callback supports_streaming?() :: boolean()

  @doc """
  Initialize adapter with configuration.
  
  Called once during pool startup to initialize adapter-specific resources.
  
  ## Parameters
  
    * `config` - Configuration keyword list
  
  ## Returns
  
    * `{:ok, adapter_state}` - Successful initialization with state
    * `{:error, reason}` - Initialization failed
  
  ## Cognitive-Ready Features
  
  Implementations should:
  - Set up telemetry collection infrastructure
  - Initialize performance monitoring
  - Prepare for cognitive enhancement hooks
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
  
  ## Parameters
  
    * `adapter_state` - State returned from init/1
    * `worker_id` - Unique identifier for this worker
  
  ## Returns
  
    * `{:ok, worker_pid}` - Worker started successfully
    * `{:error, reason}` - Worker startup failed
  """
  @callback start_worker(adapter_state :: term(), worker_id :: term()) :: 
    {:ok, pid()} | {:error, term()}

  @doc """
  Get cognitive-ready metadata about adapter capabilities.
  
  Optional callback that provides metadata for intelligent routing and optimization.
  
  ## Returns
  
  Map containing:
    * `:cognitive_capabilities` - List of supported cognitive features
    * `:performance_characteristics` - Expected performance patterns
    * `:resource_requirements` - Resource usage patterns
    * `:optimization_hints` - Hints for optimization
  """
  @callback get_cognitive_metadata() :: map()

  @doc """
  Report performance metrics to adapter for learning.
  
  Optional callback that allows core infrastructure to provide performance
  feedback to adapters for self-optimization.
  
  ## Parameters
  
    * `metrics` - Performance metrics map
    * `context` - Execution context
  """
  @callback report_performance_metrics(metrics :: map(), context :: map()) :: :ok

  # Optional callbacks
  @optional_callbacks [
    execute_stream: 4,
    uses_grpc?: 0,
    supports_streaming?: 0,
    init: 1,
    terminate: 2,
    start_worker: 2,
    get_cognitive_metadata: 0,
    report_performance_metrics: 2
  ]

  @doc """
  Validate that a module properly implements the Snakepit.Adapter behavior.
  
  ## Examples
  
      iex> Snakepit.Adapter.validate_implementation(MyBridge.Adapter)
      :ok
      
      iex> Snakepit.Adapter.validate_implementation(InvalidModule)
      {:error, [:missing_execute_callback]}
  """
  def validate_implementation(module) do
    required_callbacks = [
      {:execute, 3}
    ]
    
    missing_callbacks = Enum.filter(required_callbacks, fn {function, arity} ->
      not function_exported?(module, function, arity)
    end)
    
    if Enum.empty?(missing_callbacks) do
      :ok
    else
      {:error, missing_callbacks}
    end
  end

  @doc """
  Get default cognitive metadata template.
  
  Provides a template that adapter implementations can use as a starting point.
  """
  def default_cognitive_metadata do
    %{
      cognitive_capabilities: [],
      performance_characteristics: %{
        typical_latency_ms: 100,
        throughput_ops_per_sec: 10,
        resource_intensity: :medium
      },
      resource_requirements: %{
        memory_mb: 100,
        cpu_usage: :low,
        network_usage: :medium
      },
      optimization_hints: [
        :supports_batching,
        :benefits_from_caching,
        :session_affinity_beneficial
      ]
    }
  end
end
```

### 4. Telemetry Infrastructure (`lib/snakepit/telemetry.ex`)

```elixir
defmodule Snakepit.Telemetry do
  @moduledoc """
  Telemetry infrastructure for cognitive-ready data collection.
  
  Provides lightweight telemetry collection that can support future
  cognitive enhancements without impacting current performance.
  """

  @doc """
  Create a new telemetry collector.
  """
  def new_collector(namespace) do
    %{
      namespace: namespace,
      buffer: CircularBuffer.new(1000),
      started_at: DateTime.utc_now(),
      event_count: 0
    }
  end

  @doc """
  Record telemetry event.
  """
  def record(collector, event_data) do
    updated_buffer = CircularBuffer.push(collector.buffer, event_data)
    updated_collector = %{collector | 
      buffer: updated_buffer,
      event_count: collector.event_count + 1
    }
    
    # Emit telemetry event for external subscribers
    :telemetry.execute(
      [:snakepit, collector.namespace, :event], 
      %{event_count: updated_collector.event_count},
      event_data
    )
    
    updated_collector
  end

  @doc """
  Get telemetry summary.
  """
  def get_summary(collector) do
    events = CircularBuffer.to_list(collector.buffer)
    
    %{
      namespace: collector.namespace,
      total_events: collector.event_count,
      recent_events: length(events),
      started_at: collector.started_at,
      last_event_at: get_last_event_time(events),
      event_rate_per_minute: calculate_event_rate(collector)
    }
  end

  # Helper functions
  defp get_last_event_time([]), do: nil
  defp get_last_event_time(events) do
    events
    |> List.last()
    |> Map.get(:timestamp)
  end

  defp calculate_event_rate(collector) do
    duration_minutes = DateTime.diff(DateTime.utc_now(), collector.started_at, :second) / 60.0
    if duration_minutes > 0, do: collector.event_count / duration_minutes, else: 0.0
  end
end

# Simple circular buffer implementation
defmodule CircularBuffer do
  @moduledoc """
  Simple circular buffer for telemetry data collection.
  """

  def new(max_size) do
    %{
      items: [],
      max_size: max_size,
      current_size: 0
    }
  end

  def push(buffer, item) do
    new_items = [item | buffer.items]
    
    if buffer.current_size >= buffer.max_size do
      %{buffer | 
        items: Enum.take(new_items, buffer.max_size),
        current_size: buffer.max_size
      }
    else
      %{buffer | 
        items: new_items,
        current_size: buffer.current_size + 1
      }
    end
  end

  def to_list(buffer) do
    Enum.reverse(buffer.items)
  end

  def size(buffer) do
    buffer.current_size
  end
end
```

### 5. Configuration (`config/config.exs`)

```elixir
import Config

# Snakepit Core Configuration
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
  stats_collection_interval: 60_000,
  
  # Cognitive-ready features (disabled by default)
  cognitive_features: %{
    performance_learning: false,
    intelligent_routing: false,
    adaptive_optimization: false,
    telemetry_collection: true  # Always enabled for future learning
  }

# Environment-specific configuration
import_config "#{config_env()}.exs"
```

## Key Features

### 1. Pure Infrastructure Focus
- No domain-specific logic (DSPy, ML, etc.)
- Only process management, pooling, and sessions
- Adapter pattern for all domain concerns

### 2. Cognitive-Ready Architecture
- Telemetry collection points throughout
- Performance monitoring infrastructure
- Session tracking for future learning
- Extensible adapter behavior

### 3. Future Evolution Support
- Feature flags for cognitive capabilities
- Telemetry data collection for ML training
- Hooks for intelligent routing and optimization
- Infrastructure for collaborative worker networks

### 4. Production Excellence
- Comprehensive error handling
- Performance monitoring
- Health checks and recovery
- Graceful shutdown handling

This core provides the **minimal infrastructure foundation** that can support revolutionary cognitive capabilities while remaining completely focused on infrastructure concerns. The cognitive features are achieved through the adapter pattern - bridges implement the intelligence while core provides the infrastructure.
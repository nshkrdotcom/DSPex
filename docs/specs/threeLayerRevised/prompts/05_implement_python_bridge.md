# Prompt: Implement Python Bridge Infrastructure

## Context

You are implementing the **Light Snakepit + Heavy Bridge** architecture as described in the three-layer architecture documentation. This prompt covers **Phase 1, Days 8-9** of the implementation plan - creating the Python bridge infrastructure for cross-language communication.

## Required Reading

Before starting, read these documents in order:
1. `docs/specs/threeLayerRevised/01_LIGHT_SNAKEPIT_HEAVY_BRIDGE_ARCHITECTURE.md` - Overall architecture
2. `docs/specs/threeLayerRevised/03_SNAKEPIT_GRPC_BRIDGE_PLATFORM_SPECIFICATION.md` - Platform specification (Python Bridge section)
3. `docs/specs/threeLayerRevised/07_DETAILED_IN_PLACE_IMPLEMENTATION_PLAN.md` - Implementation plan (Days 8-9)

## Current State Analysis

Examine the current codebase to understand existing Python integration:
- `./snakepit/priv/python/` (Current Python execution)
- `./snakepit_grpc_bridge/priv/python/snakepit_bridge/` (Moved Python code)
- `./snakepit_grpc_bridge/lib/snakepit_grpc_bridge/` (Previous implementations)

Identify:
1. Current Python process management and communication
2. Existing gRPC or communication protocols
3. Python dependency management and environment setup
4. Error handling and process recovery patterns

## Objective

Create a robust Python bridge infrastructure that provides:
1. Reliable Python process management with worker affinity
2. High-performance cross-language communication
3. Comprehensive error handling and recovery
4. Session-aware Python execution
5. Proper resource management and cleanup

## Implementation Tasks

### Task 1: Implement Python Bridge Manager

Create `lib/snakepit_grpc_bridge/python/bridge.ex`:

```elixir
defmodule SnakepitGRPCBridge.Python.Bridge do
  @moduledoc """
  Python bridge manager for the ML platform.
  
  Manages Python processes, handles cross-language communication,
  and provides session-aware Python execution.
  """
  
  use GenServer
  require Logger
  
  alias SnakepitGRPCBridge.Python.Process
  alias SnakepitGRPCBridge.Python.Communication
  
  @python_startup_timeout 30_000
  @python_execution_timeout 60_000
  @max_python_workers 10
  @worker_idle_timeout 300_000  # 5 minutes
  
  # GenServer API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  # Public API
  
  @doc """
  Execute Python function with session affinity.
  """
  def execute_python(session_id, module_name, function_name, args, opts \\ []) do
    timeout = opts[:timeout] || @python_execution_timeout
    
    GenServer.call(__MODULE__, {
      :execute_python, 
      session_id, 
      module_name, 
      function_name, 
      args, 
      opts
    }, timeout + 5_000)
  end
  
  @doc """
  Execute Python code directly with session context.
  """
  def execute_code(session_id, code, context \\ %{}, opts \\ []) do
    timeout = opts[:timeout] || @python_execution_timeout
    
    GenServer.call(__MODULE__, {
      :execute_code,
      session_id,
      code,
      context,
      opts
    }, timeout + 5_000)
  end
  
  @doc """
  Get or create a dedicated Python worker for a session.
  """
  def get_session_worker(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_session_worker, session_id, opts})
  end
  
  @doc """
  Cleanup resources for a session.
  """
  def cleanup_session(session_id) do
    GenServer.call(__MODULE__, {:cleanup_session, session_id})
  end
  
  @doc """
  Get bridge status and worker information.
  """
  def get_status() do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Restart Python environment (for development/debugging).
  """
  def restart_python_environment() do
    GenServer.call(__MODULE__, :restart_python_environment)
  end
  
  # GenServer Callbacks
  
  @impl GenServer
  def init(opts) do
    Logger.info("Starting Python bridge manager")
    
    # Initialize worker registry
    worker_registry = :ets.new(:python_workers, [:set, :protected])
    
    # Initialize session affinity map
    session_affinity = :ets.new(:python_session_affinity, [:set, :protected])
    
    # Initialize execution telemetry
    :telemetry.execute([:snakepit_grpc_bridge, :python, :bridge, :started], %{})
    
    # Start initial Python workers
    initial_workers = opts[:initial_workers] || 2
    
    state = %{
      worker_registry: worker_registry,
      session_affinity: session_affinity,
      next_worker_id: 1,
      config: build_config(opts),
      started_at: DateTime.utc_now()
    }
    
    # Start initial workers
    spawn_initial_workers(state, initial_workers)
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    Logger.info("Python bridge manager started successfully")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:execute_python, session_id, module_name, function_name, args, opts}, from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Get or assign worker for session
    case get_or_assign_worker(session_id, state) do
      {:ok, worker_pid} ->
        # Execute in background to avoid blocking GenServer
        spawn_link(fn ->
          result = execute_on_worker(
            worker_pid, 
            session_id, 
            :function_call,
            %{
              module: module_name,
              function: function_name,
              args: args,
              options: opts
            }
          )
          
          # Collect telemetry
          execution_time = System.monotonic_time(:microsecond) - start_time
          collect_execution_telemetry(
            :function_call, session_id, module_name, 
            function_name, execution_time, result
          )
          
          GenServer.reply(from, result)
        end)
        
        {:noreply, state}
      
      {:error, reason} ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        collect_execution_telemetry(
          :function_call, session_id, module_name, 
          function_name, execution_time, {:error, reason}
        )
        
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:execute_code, session_id, code, context, opts}, from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case get_or_assign_worker(session_id, state) do
      {:ok, worker_pid} ->
        spawn_link(fn ->
          result = execute_on_worker(
            worker_pid,
            session_id,
            :code_execution,
            %{
              code: code,
              context: context,
              options: opts
            }
          )
          
          execution_time = System.monotonic_time(:microsecond) - start_time
          collect_execution_telemetry(
            :code_execution, session_id, "direct_code", 
            "execute", execution_time, result
          )
          
          GenServer.reply(from, result)
        end)
        
        {:noreply, state}
      
      {:error, reason} ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        collect_execution_telemetry(
          :code_execution, session_id, "direct_code", 
          "execute", execution_time, {:error, reason}
        )
        
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_session_worker, session_id, opts}, _from, state) do
    case get_or_assign_worker(session_id, state) do
      {:ok, worker_pid} ->
        worker_info = get_worker_info(worker_pid, state)
        {:reply, {:ok, worker_info}, state}
      
      error ->
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:cleanup_session, session_id}, _from, state) do
    Logger.info("Cleaning up Python resources for session", session_id: session_id)
    
    # Remove session affinity
    :ets.delete(state.session_affinity, session_id)
    
    # Notify worker to cleanup session state
    case :ets.lookup(state.session_affinity, session_id) do
      [{^session_id, worker_pid}] ->
        Process.send(worker_pid, {:cleanup_session, session_id}, [])
      [] ->
        :ok
    end
    
    :telemetry.execute([:snakepit_grpc_bridge, :python, :session, :cleaned_up], %{
      session_id: session_id
    })
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call(:get_status, _from, state) do
    workers = :ets.tab2list(state.worker_registry)
    sessions = :ets.tab2list(state.session_affinity)
    
    status = %{
      total_workers: length(workers),
      active_sessions: length(sessions),
      worker_details: Enum.map(workers, fn {worker_id, worker_info} ->
        %{
          id: worker_id,
          pid: worker_info.pid,
          started_at: worker_info.started_at,
          status: worker_info.status,
          assigned_sessions: get_worker_sessions(worker_info.pid, state)
        }
      end),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second)
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl GenServer
  def handle_call(:restart_python_environment, _from, state) do
    Logger.warn("Restarting Python environment")
    
    # Stop all workers
    workers = :ets.tab2list(state.worker_registry)
    Enum.each(workers, fn {_worker_id, worker_info} ->
      Process.exit(worker_info.pid, :restart)
    end)
    
    # Clear registries
    :ets.delete_all_objects(state.worker_registry)
    :ets.delete_all_objects(state.session_affinity)
    
    # Start fresh workers
    spawn_initial_workers(state, 2)
    
    :telemetry.execute([:snakepit_grpc_bridge, :python, :environment, :restarted], %{})
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup_idle_workers, state) do
    cleanup_idle_workers(state)
    schedule_cleanup()
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    Logger.warn("Python worker exited", worker_pid: worker_pid, reason: reason)
    
    # Remove worker from registry
    remove_worker_from_registry(worker_pid, state)
    
    # Remove any session affinities for this worker
    remove_worker_affinities(worker_pid, state)
    
    # If we have too few workers, spawn a new one
    current_worker_count = :ets.info(state.worker_registry, :size)
    if current_worker_count < 2 do
      spawn_worker(state)
    end
    
    :telemetry.execute([:snakepit_grpc_bridge, :python, :worker, :exited], %{
      worker_pid: worker_pid,
      reason: reason,
      remaining_workers: current_worker_count - 1
    })
    
    {:noreply, state}
  end
  
  # Private helper functions
  
  defp build_config(opts) do
    %{
      python_executable: opts[:python_executable] || "python3",
      python_path: opts[:python_path] || get_python_bridge_path(),
      startup_timeout: opts[:startup_timeout] || @python_startup_timeout,
      execution_timeout: opts[:execution_timeout] || @python_execution_timeout,
      max_workers: opts[:max_workers] || @max_python_workers,
      worker_idle_timeout: opts[:worker_idle_timeout] || @worker_idle_timeout
    }
  end
  
  defp get_python_bridge_path() do
    Application.app_dir(:snakepit_grpc_bridge, "priv/python")
  end
  
  defp spawn_initial_workers(state, count) do
    Enum.each(1..count, fn _ ->
      spawn_worker(state)
    end)
  end
  
  defp spawn_worker(state) do
    worker_id = state.next_worker_id
    
    case Process.start_python_worker(worker_id, state.config) do
      {:ok, worker_pid} ->
        # Monitor the worker
        Process.monitor(worker_pid)
        
        # Register worker
        worker_info = %{
          id: worker_id,
          pid: worker_pid,
          started_at: DateTime.utc_now(),
          status: :ready,
          last_activity: DateTime.utc_now()
        }
        
        :ets.insert(state.worker_registry, {worker_id, worker_info})
        
        Logger.info("Python worker started", worker_id: worker_id, worker_pid: worker_pid)
        
        :telemetry.execute([:snakepit_grpc_bridge, :python, :worker, :started], %{
          worker_id: worker_id,
          worker_pid: worker_pid
        })
        
        {:ok, worker_pid}
      
      {:error, reason} ->
        Logger.error("Failed to start Python worker", worker_id: worker_id, reason: reason)
        {:error, reason}
    end
  end
  
  defp get_or_assign_worker(session_id, state) do
    case :ets.lookup(state.session_affinity, session_id) do
      [{^session_id, worker_pid}] ->
        # Check if worker is still alive
        if Process.alive?(worker_pid) do
          {:ok, worker_pid}
        else
          # Worker died, assign a new one
          assign_new_worker(session_id, state)
        end
      
      [] ->
        # No worker assigned, find or create one
        assign_new_worker(session_id, state)
    end
  end
  
  defp assign_new_worker(session_id, state) do
    case find_available_worker(state) do
      {:ok, worker_pid} ->
        # Assign worker to session
        :ets.insert(state.session_affinity, {session_id, worker_pid})
        
        Logger.debug("Assigned Python worker to session", 
          session_id: session_id, worker_pid: worker_pid)
        
        {:ok, worker_pid}
      
      :no_available_workers ->
        # Try to spawn a new worker if under limit
        current_count = :ets.info(state.worker_registry, :size)
        
        if current_count < state.config.max_workers do
          case spawn_worker(state) do
            {:ok, worker_pid} ->
              :ets.insert(state.session_affinity, {session_id, worker_pid})
              {:ok, worker_pid}
            
            error ->
              error
          end
        else
          {:error, :no_available_workers}
        end
    end
  end
  
  defp find_available_worker(state) do
    workers = :ets.tab2list(state.worker_registry)
    
    # Find worker with least load (fewest assigned sessions)
    worker_loads = Enum.map(workers, fn {worker_id, worker_info} ->
      session_count = count_worker_sessions(worker_info.pid, state)
      {worker_id, worker_info, session_count}
    end)
    
    case Enum.min_by(worker_loads, fn {_id, _info, count} -> count end, fn -> nil end) do
      {_worker_id, worker_info, _count} -> {:ok, worker_info.pid}
      nil -> :no_available_workers
    end
  end
  
  defp count_worker_sessions(worker_pid, state) do
    pattern = {:_, worker_pid}
    :ets.select_count(state.session_affinity, [{pattern, [], [true]}])
  end
  
  defp get_worker_sessions(worker_pid, state) do
    pattern = {:_, worker_pid}
    matches = :ets.match(state.session_affinity, {:"$1", worker_pid})
    Enum.map(matches, fn [session_id] -> session_id end)
  end
  
  defp execute_on_worker(worker_pid, session_id, operation_type, operation_data) do
    Communication.execute_on_worker(worker_pid, session_id, operation_type, operation_data)
  end
  
  defp get_worker_info(worker_pid, state) do
    workers = :ets.tab2list(state.worker_registry)
    
    case Enum.find(workers, fn {_id, info} -> info.pid == worker_pid end) do
      {worker_id, worker_info} ->
        %{
          id: worker_id,
          pid: worker_pid,
          started_at: worker_info.started_at,
          status: worker_info.status,
          assigned_sessions: get_worker_sessions(worker_pid, state)
        }
      
      nil ->
        %{error: :worker_not_found}
    end
  end
  
  defp remove_worker_from_registry(worker_pid, state) do
    workers = :ets.tab2list(state.worker_registry)
    
    case Enum.find(workers, fn {_id, info} -> info.pid == worker_pid end) do
      {worker_id, _info} ->
        :ets.delete(state.worker_registry, worker_id)
      
      nil ->
        :ok
    end
  end
  
  defp remove_worker_affinities(worker_pid, state) do
    pattern = {:_, worker_pid}
    :ets.match_delete(state.session_affinity, pattern)
  end
  
  defp cleanup_idle_workers(state) do
    current_time = DateTime.utc_now()
    idle_threshold = DateTime.add(current_time, -state.config.worker_idle_timeout, :millisecond)
    
    workers = :ets.tab2list(state.worker_registry)
    
    Enum.each(workers, fn {worker_id, worker_info} ->
      if DateTime.compare(worker_info.last_activity, idle_threshold) == :lt do
        # Worker is idle, check if it has active sessions
        session_count = count_worker_sessions(worker_info.pid, state)
        
        if session_count == 0 do
          Logger.info("Stopping idle Python worker", worker_id: worker_id)
          Process.exit(worker_info.pid, :idle_timeout)
        end
      end
    end)
  end
  
  defp schedule_cleanup() do
    Process.send_after(self(), :cleanup_idle_workers, @worker_idle_timeout)
  end
  
  defp collect_execution_telemetry(operation_type, session_id, module_name, function_name, execution_time, result) do
    telemetry_data = %{
      operation_type: operation_type,
      session_id: session_id,
      module_name: module_name,
      function_name: function_name,
      execution_time_microseconds: execution_time,
      success: match?({:ok, _}, result),
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :python, :execution], telemetry_data)
  end
end
```

### Task 2: Implement Python Process Management

Create `lib/snakepit_grpc_bridge/python/process.ex`:

```elixir
defmodule SnakepitGRPCBridge.Python.Process do
  @moduledoc """
  Python process management for individual worker processes.
  
  Handles spawning, monitoring, and communicating with Python worker processes.
  """
  
  require Logger
  
  @python_init_script """
  import sys
  import os
  import json
  import traceback
  from pathlib import Path
  
  # Add bridge path to Python path
  bridge_path = Path(__file__).parent / "snakepit_bridge"
  sys.path.insert(0, str(bridge_path))
  
  from snakepit_bridge.core.bridge import SnakepitBridge
  
  # Initialize bridge
  bridge = SnakepitBridge()
  bridge.start()
  
  print("PYTHON_WORKER_READY")
  sys.stdout.flush()
  """
  
  @doc """
  Start a new Python worker process.
  """
  def start_python_worker(worker_id, config) do
    Logger.debug("Starting Python worker", worker_id: worker_id)
    
    python_script_path = create_worker_script(worker_id, config)
    
    port_opts = [
      :binary,
      :exit_status,
      {:args, [python_script_path]},
      {:cd, config.python_path},
      {:env, build_python_env(config)},
      {:packet, 4}  # Use 4-byte length prefix for messages
    ]
    
    try do
      port = Port.open({:spawn_executable, config.python_executable}, port_opts)
      
      # Wait for Python to initialize
      case wait_for_python_ready(port, config.startup_timeout) do
        :ok ->
          worker_pid = spawn_link(__MODULE__, :worker_loop, [worker_id, port, config])
          {:ok, worker_pid}
        
        {:error, reason} ->
          Port.close(port)
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Failed to start Python worker", 
          worker_id: worker_id, 
          error: inspect(error)
        )
        {:error, {:spawn_failed, error}}
    end
  end
  
  @doc """
  Worker loop that handles communication with Python process.
  """
  def worker_loop(worker_id, port, config) do
    receive do
      # Message from Python process
      {^port, {:data, data}} ->
        handle_python_message(worker_id, data)
        worker_loop(worker_id, port, config)
      
      # Port closed/crashed
      {^port, {:exit_status, status}} ->
        Logger.warn("Python worker exited", worker_id: worker_id, exit_status: status)
        :telemetry.execute([:snakepit_grpc_bridge, :python, :worker, :exited], %{
          worker_id: worker_id,
          exit_status: status
        })
        exit({:python_worker_exited, status})
      
      # Execution request
      {:execute, from, session_id, operation_type, operation_data} ->
        result = execute_python_operation(port, session_id, operation_type, operation_data, config)
        send(from, {:execution_result, result})
        worker_loop(worker_id, port, config)
      
      # Session cleanup
      {:cleanup_session, session_id} ->
        cleanup_python_session(port, session_id)
        worker_loop(worker_id, port, config)
      
      # Worker shutdown
      :shutdown ->
        Logger.info("Shutting down Python worker", worker_id: worker_id)
        Port.close(port)
        exit(:shutdown)
      
      # Health check
      {:health_check, from} ->
        health_status = check_python_health(port)
        send(from, {:health_result, health_status})
        worker_loop(worker_id, port, config)
      
      # Unexpected message
      msg ->
        Logger.warn("Python worker received unexpected message", 
          worker_id: worker_id, 
          message: inspect(msg)
        )
        worker_loop(worker_id, port, config)
    end
  end
  
  # Private helper functions
  
  defp create_worker_script(worker_id, config) do
    script_dir = Path.join([config.python_path, "tmp"])
    File.mkdir_p!(script_dir)
    
    script_path = Path.join(script_dir, "worker_#{worker_id}.py")
    
    script_content = @python_init_script
    
    File.write!(script_path, script_content)
    script_path
  end
  
  defp build_python_env(config) do
    base_env = System.get_env()
    
    python_path = case Map.get(base_env, "PYTHONPATH") do
      nil -> config.python_path
      existing -> "#{config.python_path}:#{existing}"
    end
    
    Map.merge(base_env, %{
      "PYTHONPATH" => python_path,
      "PYTHONUNBUFFERED" => "1",
      "SNAKEPIT_BRIDGE_MODE" => "worker"
    })
  end
  
  defp wait_for_python_ready(port, timeout) do
    receive do
      {^port, {:data, data}} ->
        case String.trim(data) do
          "PYTHON_WORKER_READY" ->
            Logger.debug("Python worker ready")
            :ok
          
          other ->
            Logger.debug("Python worker startup message", message: other)
            wait_for_python_ready(port, timeout)
        end
      
      {^port, {:exit_status, status}} ->
        Logger.error("Python worker failed to start", exit_status: status)
        {:error, {:startup_failed, status}}
    after
      timeout ->
        Logger.error("Python worker startup timeout")
        {:error, :startup_timeout}
    end
  end
  
  defp handle_python_message(worker_id, data) do
    try do
      case Jason.decode(data) do
        {:ok, %{"type" => "log", "level" => level, "message" => message}} ->
          log_level = String.to_existing_atom(level)
          Logger.log(log_level, "Python worker log", 
            worker_id: worker_id, 
            python_message: message
          )
        
        {:ok, %{"type" => "telemetry"} = telemetry_data} ->
          :telemetry.execute([:snakepit_grpc_bridge, :python, :worker, :telemetry], 
            Map.delete(telemetry_data, "type")
          )
        
        {:ok, %{"type" => "error", "error" => error_info}} ->
          Logger.error("Python worker error", 
            worker_id: worker_id, 
            error: error_info
          )
        
        {:ok, other} ->
          Logger.debug("Python worker message", 
            worker_id: worker_id, 
            message: other
          )
        
        {:error, _} ->
          Logger.warn("Invalid JSON from Python worker", 
            worker_id: worker_id, 
            raw_data: data
          )
      end
    rescue
      error ->
        Logger.warn("Error processing Python message", 
          worker_id: worker_id, 
          error: inspect(error),
          raw_data: data
        )
    end
  end
  
  defp execute_python_operation(port, session_id, operation_type, operation_data, config) do
    request = %{
      type: "execute",
      session_id: session_id,
      operation_type: operation_type,
      operation_data: operation_data,
      request_id: generate_request_id()
    }
    
    case Jason.encode(request) do
      {:ok, json_data} ->
        # Send request to Python
        Port.command(port, json_data)
        
        # Wait for response
        wait_for_python_response(port, request.request_id, config.execution_timeout)
      
      {:error, encode_error} ->
        Logger.error("Failed to encode Python request", error: encode_error)
        {:error, {:encode_failed, encode_error}}
    end
  end
  
  defp wait_for_python_response(port, request_id, timeout) do
    receive do
      {^port, {:data, data}} ->
        case Jason.decode(data) do
          {:ok, %{"type" => "response", "request_id" => ^request_id} = response} ->
            case response do
              %{"success" => true, "result" => result} ->
                {:ok, result}
              
              %{"success" => false, "error" => error_info} ->
                {:error, error_info}
              
              _ ->
                {:error, {:invalid_response, response}}
            end
          
          {:ok, %{"type" => "response", "request_id" => other_id}} ->
            Logger.warn("Received response for different request", 
              expected: request_id, 
              received: other_id
            )
            wait_for_python_response(port, request_id, timeout)
          
          {:ok, other} ->
            # Non-response message, continue waiting
            handle_python_message("unknown", data)
            wait_for_python_response(port, request_id, timeout)
          
          {:error, decode_error} ->
            Logger.error("Failed to decode Python response", error: decode_error)
            {:error, {:decode_failed, decode_error}}
        end
      
      {^port, {:exit_status, status}} ->
        Logger.error("Python worker crashed during execution", exit_status: status)
        {:error, {:worker_crashed, status}}
    after
      timeout ->
        Logger.error("Python execution timeout", request_id: request_id)
        {:error, :execution_timeout}
    end
  end
  
  defp cleanup_python_session(port, session_id) do
    request = %{
      type: "cleanup_session",
      session_id: session_id,
      request_id: generate_request_id()
    }
    
    case Jason.encode(request) do
      {:ok, json_data} ->
        Port.command(port, json_data)
        # Don't wait for response for cleanup
        :ok
      
      {:error, _} ->
        :ok
    end
  end
  
  defp check_python_health(port) do
    request = %{
      type: "health_check",
      request_id: generate_request_id()
    }
    
    case Jason.encode(request) do
      {:ok, json_data} ->
        Port.command(port, json_data)
        
        receive do
          {^port, {:data, data}} ->
            case Jason.decode(data) do
              {:ok, %{"type" => "health_response", "status" => "healthy"}} ->
                :healthy
              
              _ ->
                :unhealthy
            end
          
          {^port, {:exit_status, _}} ->
            :dead
        after
          5_000 ->
            :timeout
        end
      
      {:error, _} ->
        :unhealthy
    end
  end
  
  defp generate_request_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
```

### Task 3: Implement Communication Protocol

Create `lib/snakepit_grpc_bridge/python/communication.ex`:

```elixir
defmodule SnakepitGRPCBridge.Python.Communication do
  @moduledoc """
  Communication protocol for Python bridge operations.
  
  Handles serialization, request/response matching, and error handling
  for cross-language communication.
  """
  
  require Logger
  
  @doc """
  Execute operation on a specific Python worker.
  """
  def execute_on_worker(worker_pid, session_id, operation_type, operation_data) do
    # Send execution request to worker
    ref = make_ref()
    send(worker_pid, {:execute, self(), session_id, operation_type, operation_data})
    
    # Wait for response
    receive do
      {:execution_result, result} ->
        result
    after
      60_000 ->
        Logger.error("Worker execution timeout", 
          worker_pid: worker_pid, 
          session_id: session_id,
          operation_type: operation_type
        )
        {:error, :worker_timeout}
    end
  end
  
  @doc """
  Check health of a Python worker.
  """
  def check_worker_health(worker_pid) do
    send(worker_pid, {:health_check, self()})
    
    receive do
      {:health_result, status} ->
        status
    after
      5_000 ->
        :timeout
    end
  end
  
  @doc """
  Serialize data for Python communication.
  """
  def serialize_for_python(data) do
    try do
      # Convert Elixir data structures to Python-compatible format
      python_data = convert_to_python_types(data)
      {:ok, python_data}
    rescue
      error ->
        Logger.error("Serialization failed", error: inspect(error), data: inspect(data))
        {:error, {:serialization_failed, error}}
    end
  end
  
  @doc """
  Deserialize data from Python.
  """
  def deserialize_from_python(data) do
    try do
      # Convert Python data structures to Elixir format
      elixir_data = convert_to_elixir_types(data)
      {:ok, elixir_data}
    rescue
      error ->
        Logger.error("Deserialization failed", error: inspect(error), data: inspect(data))
        {:error, {:deserialization_failed, error}}
    end
  end
  
  # Private helper functions
  
  defp convert_to_python_types(data) when is_map(data) do
    # Handle special Elixir types
    case data do
      %DateTime{} = dt ->
        %{
          "__type__" => "datetime",
          "value" => DateTime.to_iso8601(dt)
        }
      
      %Date{} = date ->
        %{
          "__type__" => "date", 
          "value" => Date.to_iso8601(date)
        }
      
      %Time{} = time ->
        %{
          "__type__" => "time",
          "value" => Time.to_iso8601(time)
        }
      
      # Handle binary data
      %{__binary__: binary_data} ->
        %{
          "__type__" => "binary",
          "value" => Base.encode64(binary_data)
        }
      
      # Handle atoms (convert to strings)
      %{__atom__: atom_value} ->
        %{
          "__type__" => "atom",
          "value" => Atom.to_string(atom_value)
        }
      
      # Regular map
      _ ->
        Enum.reduce(data, %{}, fn {key, value}, acc ->
          python_key = convert_to_python_types(key)
          python_value = convert_to_python_types(value)
          Map.put(acc, python_key, python_value)
        end)
    end
  end
  
  defp convert_to_python_types(data) when is_list(data) do
    Enum.map(data, &convert_to_python_types/1)
  end
  
  defp convert_to_python_types(data) when is_atom(data) do
    if data in [nil, true, false] do
      data
    else
      %{
        "__type__" => "atom",
        "value" => Atom.to_string(data)
      }
    end
  end
  
  defp convert_to_python_types(data) when is_binary(data) do
    # Check if it's valid UTF-8
    if String.valid?(data) do
      data
    else
      # Handle as binary data
      %{
        "__type__" => "binary",
        "value" => Base.encode64(data)
      }
    end
  end
  
  defp convert_to_python_types(data) when is_tuple(data) do
    %{
      "__type__" => "tuple",
      "value" => Tuple.to_list(data) |> Enum.map(&convert_to_python_types/1)
    }
  end
  
  defp convert_to_python_types(data) do
    # Numbers, booleans, nil pass through
    data
  end
  
  defp convert_to_elixir_types(data) when is_map(data) do
    case data do
      %{"__type__" => "datetime", "value" => iso_string} ->
        case DateTime.from_iso8601(iso_string) do
          {:ok, dt, _} -> dt
          _ -> data
        end
      
      %{"__type__" => "date", "value" => iso_string} ->
        case Date.from_iso8601(iso_string) do
          {:ok, date} -> date
          _ -> data
        end
      
      %{"__type__" => "time", "value" => iso_string} ->
        case Time.from_iso8601(iso_string) do
          {:ok, time} -> time
          _ -> data
        end
      
      %{"__type__" => "binary", "value" => base64_data} ->
        case Base.decode64(base64_data) do
          {:ok, binary} -> binary
          _ -> data
        end
      
      %{"__type__" => "atom", "value" => atom_string} ->
        String.to_existing_atom(atom_string)
      
      %{"__type__" => "tuple", "value" => list_data} ->
        elixir_list = Enum.map(list_data, &convert_to_elixir_types/1)
        List.to_tuple(elixir_list)
      
      # Regular map
      _ ->
        Enum.reduce(data, %{}, fn {key, value}, acc ->
          elixir_key = convert_to_elixir_types(key)
          elixir_value = convert_to_elixir_types(value)
          Map.put(acc, elixir_key, elixir_value)
        end)
    end
  end
  
  defp convert_to_elixir_types(data) when is_list(data) do
    Enum.map(data, &convert_to_elixir_types/1)
  end
  
  defp convert_to_elixir_types(data) do
    # Primitives pass through
    data
  end
end
```

### Task 4: Implement Python Bridge Core

Create `priv/python/snakepit_bridge/core/bridge.py`:

```python
"""
Core Python bridge for cross-language communication.

Handles request processing, session management, and integration
with the Elixir bridge system.
"""

import json
import sys
import logging
import traceback
from typing import Dict, Any, Optional
from datetime import datetime

from .session import SessionManager
from ..variables.manager import VariableManager
from ..tools.bridge import ToolBridge
from ..dspy.integration import DSPyOperations

logger = logging.getLogger(__name__)


class SnakepitBridge:
    """Main bridge class for handling Elixir <-> Python communication."""
    
    def __init__(self):
        self.session_manager = SessionManager()
        self.variable_manager = VariableManager(self.session_manager)
        self.tool_bridge = ToolBridge(self.session_manager)
        self.dspy_operations = DSPyOperations(self.session_manager)
        
        # Request handlers
        self.handlers = {
            'function_call': self._handle_function_call,
            'code_execution': self._handle_code_execution,
            'health_check': self._handle_health_check,
            'cleanup_session': self._handle_cleanup_session
        }
        
        self.running = False
    
    def start(self):
        """Start the bridge and begin processing requests."""
        self.running = True
        
        # Send ready signal
        print("PYTHON_WORKER_READY")
        sys.stdout.flush()
        
        # Start request processing loop
        self._process_requests()
    
    def stop(self):
        """Stop the bridge gracefully."""
        self.running = False
        logger.info("Python bridge stopped")
    
    def _process_requests(self):
        """Main request processing loop."""
        logger.info("Python bridge started, processing requests")
        
        while self.running:
            try:
                # Read request from stdin
                line = sys.stdin.readline()
                if not line:
                    # EOF, exit gracefully
                    break
                
                # Parse request
                try:
                    request = json.loads(line.strip())
                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON request: {e}")
                    continue
                
                # Process request
                self._handle_request(request)
                
            except KeyboardInterrupt:
                logger.info("Received interrupt, stopping bridge")
                break
            except Exception as e:
                logger.error(f"Unexpected error in request loop: {e}")
                logger.error(traceback.format_exc())
                # Continue processing other requests
    
    def _handle_request(self, request: Dict[str, Any]):
        """Handle a single request from Elixir."""
        request_id = request.get('request_id')
        request_type = request.get('type')
        
        logger.debug(f"Processing request: {request_type} (ID: {request_id})")
        
        try:
            if request_type == 'execute':
                self._handle_execute_request(request)
            elif request_type == 'health_check':
                self._send_health_response(request_id)
            elif request_type == 'cleanup_session':
                self._handle_cleanup_session_request(request)
            else:
                self._send_error_response(request_id, f"Unknown request type: {request_type}")
        
        except Exception as e:
            logger.error(f"Error handling request {request_id}: {e}")
            logger.error(traceback.format_exc())
            self._send_error_response(request_id, str(e))
    
    def _handle_execute_request(self, request: Dict[str, Any]):
        """Handle execution request."""
        request_id = request.get('request_id')
        session_id = request.get('session_id')
        operation_type = request.get('operation_type')
        operation_data = request.get('operation_data', {})
        
        # Get handler for operation type
        handler = self.handlers.get(operation_type)
        if not handler:
            self._send_error_response(request_id, f"Unknown operation type: {operation_type}")
            return
        
        try:
            # Execute operation
            result = handler(session_id, operation_data)
            self._send_success_response(request_id, result)
        
        except Exception as e:
            logger.error(f"Operation {operation_type} failed: {e}")
            logger.error(traceback.format_exc())
            self._send_error_response(request_id, {
                'error_type': type(e).__name__,
                'error_message': str(e),
                'traceback': traceback.format_exc()
            })
    
    def _handle_function_call(self, session_id: str, operation_data: Dict[str, Any]) -> Dict[str, Any]:
        """Handle function call operation."""
        module_name = operation_data.get('module')
        function_name = operation_data.get('function')
        args = operation_data.get('args', {})
        options = operation_data.get('options', {})
        
        logger.info(f"Executing {module_name}.{function_name} for session {session_id}")
        
        # Route to appropriate module
        if module_name == 'variables':
            return self._handle_variable_operation(session_id, function_name, args, options)
        elif module_name == 'tools':
            return self._handle_tool_operation(session_id, function_name, args, options)
        elif module_name == 'dspy_operations':
            return self._handle_dspy_operation(session_id, function_name, args, options)
        else:
            raise ValueError(f"Unknown module: {module_name}")
    
    def _handle_code_execution(self, session_id: str, operation_data: Dict[str, Any]) -> Dict[str, Any]:
        """Handle direct code execution."""
        code = operation_data.get('code')
        context = operation_data.get('context', {})
        options = operation_data.get('options', {})
        
        logger.info(f"Executing code for session {session_id}")
        
        # Set up execution context
        exec_globals = {
            '__session_id__': session_id,
            'variables': self.variable_manager,
            'tools': self.tool_bridge,
            'dspy': self.dspy_operations,
            **context
        }
        
        exec_locals = {}
        
        try:
            # Execute the code
            exec(code, exec_globals, exec_locals)
            
            # Return any results in locals
            return {
                'locals': {k: v for k, v in exec_locals.items() if not k.startswith('_')},
                'execution_successful': True
            }
        
        except Exception as e:
            logger.error(f"Code execution failed: {e}")
            raise
    
    def _handle_variable_operation(self, session_id: str, function_name: str, 
                                 args: Dict[str, Any], options: Dict[str, Any]) -> Dict[str, Any]:
        """Handle variable operation."""
        method = getattr(self.variable_manager, function_name, None)
        if not method:
            raise ValueError(f"Unknown variable operation: {function_name}")
        
        return method(session_id, **args)
    
    def _handle_tool_operation(self, session_id: str, function_name: str,
                             args: Dict[str, Any], options: Dict[str, Any]) -> Dict[str, Any]:
        """Handle tool operation."""
        method = getattr(self.tool_bridge, function_name, None)
        if not method:
            raise ValueError(f"Unknown tool operation: {function_name}")
        
        return method(session_id, **args)
    
    def _handle_dspy_operation(self, session_id: str, function_name: str,
                             args: Dict[str, Any], options: Dict[str, Any]) -> Dict[str, Any]:
        """Handle DSPy operation."""
        method = getattr(self.dspy_operations, function_name, None)
        if not method:
            raise ValueError(f"Unknown DSPy operation: {function_name}")
        
        return method(session_id, **args)
    
    def _handle_cleanup_session_request(self, request: Dict[str, Any]):
        """Handle session cleanup request."""
        session_id = request.get('session_id')
        
        logger.info(f"Cleaning up session: {session_id}")
        
        # Cleanup session resources
        self.session_manager.cleanup_session(session_id)
        self.variable_manager.cleanup_session(session_id)
        self.tool_bridge.cleanup_session(session_id)
        
        # No response needed for cleanup
    
    def _send_success_response(self, request_id: str, result: Any):
        """Send success response to Elixir."""
        response = {
            'type': 'response',
            'request_id': request_id,
            'success': True,
            'result': self._serialize_for_elixir(result)
        }
        
        self._send_response(response)
    
    def _send_error_response(self, request_id: str, error_info: Any):
        """Send error response to Elixir."""
        response = {
            'type': 'response',
            'request_id': request_id,
            'success': False,
            'error': error_info
        }
        
        self._send_response(response)
    
    def _send_health_response(self, request_id: str):
        """Send health check response."""
        response = {
            'type': 'health_response',
            'request_id': request_id,
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self._send_response(response)
    
    def _send_response(self, response: Dict[str, Any]):
        """Send response to Elixir via stdout."""
        try:
            json_response = json.dumps(response)
            print(json_response)
            sys.stdout.flush()
        except Exception as e:
            logger.error(f"Failed to send response: {e}")
    
    def _serialize_for_elixir(self, data: Any) -> Any:
        """Serialize Python data for Elixir consumption."""
        # Convert Python-specific types to Elixir-compatible format
        if isinstance(data, datetime):
            return {
                '__type__': 'datetime',
                'value': data.isoformat()
            }
        elif isinstance(data, bytes):
            return {
                '__type__': 'binary',
                'value': data.hex()
            }
        elif isinstance(data, set):
            return {
                '__type__': 'set',
                'value': list(data)
            }
        elif isinstance(data, tuple):
            return {
                '__type__': 'tuple',
                'value': [self._serialize_for_elixir(item) for item in data]
            }
        elif isinstance(data, dict):
            return {k: self._serialize_for_elixir(v) for k, v in data.items()}
        elif isinstance(data, list):
            return [self._serialize_for_elixir(item) for item in data]
        else:
            return data
```

### Task 5: Update Adapter Integration

Update `lib/snakepit_grpc_bridge/adapter.ex` to handle new bridge operations:

```elixir
# Add to the route_command function:

# Python bridge operations
"execute_python" ->
  SnakepitGRPCBridge.Python.Bridge.execute_python(
    opts[:session_id],
    args["module"],
    args["function"], 
    args["args"],
    args["options"] || []
  )

"execute_python_code" ->
  SnakepitGRPCBridge.Python.Bridge.execute_code(
    opts[:session_id],
    args["code"],
    args["context"] || %{},
    args["options"] || []
  )

"get_python_status" ->
  SnakepitGRPCBridge.Python.Bridge.get_status()
```

## Validation

After completing this phase, verify:

1. ✅ Python Bridge manager starts successfully with worker processes
2. ✅ Python workers initialize and respond to health checks  
3. ✅ Session affinity works - same session uses same worker
4. ✅ Function calls execute successfully through the bridge
5. ✅ Code execution works with proper context
6. ✅ Error handling and recovery works correctly
7. ✅ Worker cleanup and resource management works
8. ✅ Telemetry collection works for all bridge operations
9. ✅ All tests pass

## Next Steps

This completes the Python bridge infrastructure. The next prompt will implement the gRPC infrastructure for external communication.

## Files Created/Modified

- `lib/snakepit_grpc_bridge/python/bridge.ex`
- `lib/snakepit_grpc_bridge/python/process.ex`
- `lib/snakepit_grpc_bridge/python/communication.ex`
- `priv/python/snakepit_bridge/core/bridge.py`
- `lib/snakepit_grpc_bridge/adapter.ex` (updated)

This implementation provides a robust, high-performance Python bridge with proper process management, session affinity, and comprehensive error handling.
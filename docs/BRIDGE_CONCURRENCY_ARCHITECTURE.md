# Bridge Concurrency Architecture: Detailed Implementation Analysis

## Executive Summary

This document provides a comprehensive analysis of two approaches for implementing concurrent session support in the DSPex Python Bridge: **Process-Per-Session** vs **Process Pool Architecture**. Each approach has distinct trade-offs in complexity, scalability, resource usage, and implementation effort.

## Current State Analysis

### Existing Architecture Limitations
```
Single Python Process
├── Global Programs Registry: {program_id -> program}
├── Global State: counters, config
└── Sequential Request Processing
```

**Critical Issues:**
- ❌ Program ID conflicts between concurrent users
- ❌ No session isolation 
- ❌ State pollution between operations
- ❌ Cannot scale beyond single-user scenarios
- ❌ Test interference and flakiness

### Success Criteria for New Architecture
1. **Session Isolation**: Multiple users can have programs with same IDs
2. **Concurrent Execution**: Parallel request processing without conflicts
3. **Resource Efficiency**: Reasonable memory/CPU usage under load
4. **Test Reliability**: Clean isolation for test scenarios
5. **Production Scalability**: Handle 100+ concurrent sessions
6. **Development Simplicity**: Maintainable codebase

## Approach 1: Process-Per-Session Architecture

### Core Concept
Each session gets a dedicated Python process with complete isolation.

```
┌─────────────┐    ┌──────────────────┐
│ Session A   │────│ Python Process A │
│ User: alice │    │ Programs: {A}    │
│ Programs:   │    │ State: isolated  │
│ - qa_bot    │    │ PID: 1234       │
│ - summarizer│    └──────────────────┘
└─────────────┘    
                   
┌─────────────┐    ┌──────────────────┐
│ Session B   │────│ Python Process B │
│ User: bob   │    │ Programs: {B}    │
│ Programs:   │    │ State: isolated  │
│ - qa_bot    │    │ PID: 1235       │ ← Same program ID, different process
│ - classifier│    └──────────────────┘
└─────────────┘
```

### Implementation Details

#### Elixir Supervision Tree
```elixir
defmodule DSPex.PythonBridge.SessionSupervisor do
  use DynamicSupervisor
  
  def start_session(session_id, opts \\ []) do
    child_spec = {
      DSPex.PythonBridge.SessionProcess,
      [session_id: session_id, name: via_name(session_id)] ++ opts
    }
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def stop_session(session_id) do
    case GenServer.whereis(via_name(session_id)) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end
  
  defp via_name(session_id) do
    {:via, Registry, {DSPex.SessionRegistry, session_id}}
  end
end
```

#### Session Process GenServer
```elixir
defmodule DSPex.PythonBridge.SessionProcess do
  use GenServer
  
  defstruct [
    :session_id,
    :port,
    :python_path,
    :script_path,
    requests: %{},
    request_id: 0,
    programs: [],
    status: :starting,
    created_at: nil,
    last_activity: nil
  ]
  
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = Keyword.get(opts, :name, {:via, Registry, {DSPex.SessionRegistry, session_id}})
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def call(session_id, command, args, timeout \\ 5000) do
    case GenServer.whereis({:via, Registry, {DSPex.SessionRegistry, session_id}}) do
      nil -> {:error, :session_not_found}
      pid -> GenServer.call(pid, {:bridge_call, command, args}, timeout)
    end
  end
  
  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    
    # Start dedicated Python process for this session
    case start_session_python_process(session_id) do
      {:ok, port} ->
        state = %__MODULE__{
          session_id: session_id,
          port: port,
          status: :running,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
        
        # Schedule periodic cleanup check
        schedule_cleanup_check()
        {:ok, state}
        
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:bridge_call, command, args}, from, state) do
    case state.status do
      :running ->
        request_id = state.request_id + 1
        
        # Add session context to command
        enhanced_args = Map.put(args, :session_id, state.session_id)
        request = encode_request(request_id, command, enhanced_args)
        
        send(state.port, {self(), {:command, request}})
        
        new_requests = Map.put(state.requests, request_id, from)
        new_state = %{state | 
          request_id: request_id, 
          requests: new_requests,
          last_activity: DateTime.utc_now()
        }
        
        {:noreply, new_state}
        
      status ->
        {:reply, {:error, {:session_status, status}}, state}
    end
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case decode_response(data) do
      {:ok, request_id, result} ->
        case Map.pop(state.requests, request_id) do
          {nil, _} ->
            Logger.warning("Received response for unknown request #{request_id} in session #{state.session_id}")
            {:noreply, state}
            
          {from, remaining_requests} ->
            GenServer.reply(from, {:ok, result})
            {:noreply, %{state | requests: remaining_requests, last_activity: DateTime.utc_now()}}
        end
        
      {:error, reason} ->
        Logger.error("Failed to decode response in session #{state.session_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process for session #{state.session_id} exited with status #{status}")
    {:stop, {:python_exit, status}, %{state | status: :failed}}
  end
  
  @impl true
  def handle_info(:cleanup_check, state) do
    idle_time = DateTime.diff(DateTime.utc_now(), state.last_activity, :second)
    max_idle = Application.get_env(:dspex, :session_max_idle_seconds, 3600) # 1 hour default
    
    if idle_time > max_idle and Enum.empty?(state.requests) do
      Logger.info("Session #{state.session_id} idle for #{idle_time}s, shutting down")
      {:stop, :idle_timeout, state}
    else
      schedule_cleanup_check()
      {:noreply, state}
    end
  end
  
  defp start_session_python_process(session_id) do
    # Use session-specific script or pass session ID to script
    script_path = get_bridge_script_path()
    python_path = get_python_executable()
    
    port_opts = [
      {:args, [script_path, "--session-id", session_id]},
      :binary,
      :exit_status,
      {:packet, 4},
      {:env, [{"DSPEX_SESSION_ID", session_id}]}
    ]
    
    try do
      port = Port.open({:spawn_executable, python_path}, port_opts)
      {:ok, port}
    rescue
      error -> {:error, "Failed to start session process: #{inspect(error)}"}
    end
  end
  
  defp schedule_cleanup_check do
    Process.send_after(self(), :cleanup_check, 60_000) # Check every minute
  end
end
```

#### Session Management API
```elixir
defmodule DSPex.PythonBridge.SessionManager do
  @doc "Create a new isolated session"
  def create_session(opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    user_id = Keyword.get(opts, :user_id)
    
    case DSPex.PythonBridge.SessionSupervisor.start_session(session_id, opts) do
      {:ok, _pid} -> 
        if user_id, do: register_user_session(user_id, session_id)
        {:ok, session_id}
      error -> error
    end
  end
  
  @doc "Execute command in specific session"
  def call(session_id, command, args, timeout \\ 5000) do
    DSPex.PythonBridge.SessionProcess.call(session_id, command, args, timeout)
  end
  
  @doc "Clean up session and its resources"
  def destroy_session(session_id) do
    DSPex.PythonBridge.SessionSupervisor.stop_session(session_id)
  end
  
  @doc "List all active sessions"
  def list_sessions do
    Registry.select(DSPex.SessionRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end
  
  @doc "Get session info"
  def get_session_info(session_id) do
    case GenServer.whereis({:via, Registry, {DSPex.SessionRegistry, session_id}}) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_info)
    end
  end
  
  defp generate_session_id do
    "session_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp register_user_session(user_id, session_id) do
    # Store user -> session mapping for cleanup and management
    :ets.insert(:user_sessions, {user_id, session_id})
  end
end
```

#### Python Bridge Session Support
```python
import sys
import os
import argparse

class SessionAwareBridge:
    def __init__(self, session_id=None):
        self.session_id = session_id or os.getenv('DSPEX_SESSION_ID', 'default')
        self.programs = {}  # Session-isolated programs
        self.stats = {
            'session_id': self.session_id,
            'created_at': time.time(),
            'commands_processed': 0,
            'programs_created': 0
        }
        
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        # All commands automatically operate in session context
        self.stats['commands_processed'] += 1
        
        # Add session context to logs
        print(f"[Session {self.session_id}] Processing {command}", file=sys.stderr)
        
        # Handle commands with session isolation
        if command == 'create_program':
            return self.create_program_in_session(args)
        elif command == 'execute_program':
            return self.execute_program_in_session(args)
        # ... other commands
        
    def create_program_in_session(self, args):
        program_id = args['id']
        
        # Programs are automatically isolated to this session
        if program_id in self.programs:
            raise ValueError(f"Program '{program_id}' already exists in session {self.session_id}")
            
        # Create program
        program = self._create_dspy_program(args['signature'])
        self.programs[program_id] = program
        self.stats['programs_created'] += 1
        
        return {
            'status': 'created',
            'program_id': program_id,
            'session_id': self.session_id
        }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--session-id', help='Session ID for isolation')
    args = parser.parse_args()
    
    bridge = SessionAwareBridge(session_id=args.session_id)
    
    print(f"DSPy Bridge started for session {bridge.session_id}", file=sys.stderr)
    
    # Main message loop
    while True:
        message = read_message()
        if message is None:
            break
            
        try:
            result = bridge.handle_command(message['command'], message.get('args', {}))
            write_message({'id': message['id'], 'result': result})
        except Exception as e:
            write_message({'id': message['id'], 'error': str(e)})

if __name__ == '__main__':
    main()
```

### Process-Per-Session Advantages

#### Complete Isolation
- ✅ **True isolation**: Each session has completely separate Python process
- ✅ **No state pollution**: Impossible for sessions to interfere
- ✅ **Crash isolation**: One session crash doesn't affect others
- ✅ **Memory isolation**: Each process has its own memory space

#### Simplicity
- ✅ **Conceptually simple**: 1 session = 1 process
- ✅ **Easy debugging**: Each session has dedicated logs and process
- ✅ **Straightforward cleanup**: Kill process = clean session
- ✅ **No resource sharing complexity**

#### DSPy Compatibility
- ✅ **No threading concerns**: Each process is single-threaded
- ✅ **Global state safe**: `dspy.configure()` only affects one session
- ✅ **Library compatibility**: All Python libraries work normally

### Process-Per-Session Disadvantages

#### Resource Overhead
- ❌ **Memory usage**: Each Python process ~50-100MB base
- ❌ **Startup cost**: New process creation ~1-2 seconds
- ❌ **CPU overhead**: Process switching and management
- ❌ **File descriptor limits**: Each process uses multiple FDs

#### Scalability Limits
- ❌ **Poor scaling**: 1000 sessions = 1000 processes
- ❌ **Resource exhaustion**: Memory/CPU limits hit quickly
- ❌ **OS limits**: Process limits on most systems
- ❌ **Cold start problem**: Every new session pays startup cost

#### Operational Complexity
- ❌ **Process management**: Need to monitor and restart failed processes
- ❌ **Resource monitoring**: Track per-process memory/CPU usage
- ❌ **Zombie processes**: Risk of orphaned processes
- ❌ **Platform differences**: Process behavior varies across OS

## Approach 2: Process Pool Architecture

### Core Concept
Fixed pool of Python processes handle requests from multiple sessions using namespace isolation.

```
Sessions (Many)           Process Pool (Few)              Session Store
┌─────────────┐         ┌──────────────────┐            ┌─────────────────┐
│ Session A   │────────▶│ Process 1        │◀──────────▶│ SessionA:       │
│ Session B   │─┐       │ (Available)      │            │  programs: {}   │
│ Session C   │─┼──────▶│                  │            │ SessionB:       │
│ Session D   │─┘       └──────────────────┘            │  programs: {}   │
└─────────────┘         ┌──────────────────┐            │ SessionC:       │
                        │ Process 2        │            │  programs: {}   │
┌─────────────┐    ┌───▶│ (Working)        │            └─────────────────┘
│ Session E   │────┘    │                  │            
│ Session F   │         └──────────────────┘            
└─────────────┘         ┌──────────────────┐            
                        │ Process 3        │            
                        │ (Working)        │            
                        └──────────────────┘            
```

### Implementation Details

#### Process Pool Manager
```elixir
defmodule DSPex.PythonBridge.ProcessPool do
  use GenServer
  
  defstruct [
    :pool_size,
    available: [],      # List of available worker PIDs
    busy: %{},         # Map of worker_pid -> {session_id, request_ref}
    pending: :queue.new(), # Queue of {session_id, command, args, from}
    workers: %{},      # Map of worker_pid -> worker_state
    sessions: %{}      # Map of session_id -> session_metadata
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def execute(session_id, command, args, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:execute, session_id, command, args}, timeout)
  end
  
  def create_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:create_session, session_id, opts})
  end
  
  def destroy_session(session_id) do
    GenServer.call(__MODULE__, {:destroy_session, session_id})
  end
  
  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 5)
    
    # Start session store
    :ets.new(:session_store, [:named_table, :public, {:read_concurrency, true}])
    
    # Start worker processes
    workers = for i <- 1..pool_size do
      {:ok, pid} = DSPex.PythonBridge.PoolWorker.start_link([worker_id: i])
      Process.monitor(pid)
      {pid, %{worker_id: i, status: :available, started_at: DateTime.utc_now()}}
    end
    
    state = %__MODULE__{
      pool_size: pool_size,
      available: Enum.map(workers, fn {pid, _} -> pid end),
      workers: Map.new(workers)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create_session, session_id, opts}, _from, state) do
    case :ets.lookup(:session_store, session_id) do
      [] ->
        session_data = %{
          session_id: session_id,
          created_at: DateTime.utc_now(),
          programs: %{},
          stats: %{commands: 0, programs_created: 0},
          user_id: Keyword.get(opts, :user_id),
          config: opts
        }
        
        :ets.insert(:session_store, {session_id, session_data})
        new_state = put_in(state.sessions[session_id], session_data)
        
        {:reply, {:ok, session_id}, new_state}
        
      [{_session_id, _data}] ->
        {:reply, {:error, :session_exists}, state}
    end
  end
  
  @impl true
  def handle_call({:execute, session_id, command, args}, from, state) do
    # Verify session exists
    case :ets.lookup(:session_store, session_id) do
      [] ->
        {:reply, {:error, :session_not_found}, state}
        
      [{_session_id, session_data}] ->
        request = {session_id, command, args, from}
        
        case assign_worker(request, state) do
          {:ok, new_state} ->
            {:noreply, new_state}
            
          {:queue, new_state} ->
            # No workers available, queue the request
            {:noreply, new_state}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:destroy_session, session_id}, _from, state) do
    # Remove from session store
    :ets.delete(:session_store, session_id)
    
    # Cancel any pending requests for this session
    new_pending = :queue.filter(fn {sid, _, _, _} -> sid != session_id end, state.pending)
    
    # Remove from state
    new_state = %{state | 
      pending: new_pending,
      sessions: Map.delete(state.sessions, session_id)
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info({:worker_result, worker_pid, result}, state) do
    case Map.get(state.busy, worker_pid) do
      nil ->
        Logger.warning("Received result from unknown worker #{inspect(worker_pid)}")
        {:noreply, state}
        
      {session_id, request_ref, from} ->
        # Send result back to caller
        GenServer.reply(from, result)
        
        # Update worker statistics
        update_session_stats(session_id)
        
        # Mark worker as available
        new_state = %{state |
          available: [worker_pid | state.available],
          busy: Map.delete(state.busy, worker_pid)
        }
        
        # Process any queued requests
        process_queue(new_state)
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    Logger.error("Worker process #{inspect(worker_pid)} died: #{inspect(reason)}")
    
    # Remove from all tracking
    new_state = %{state |
      available: List.delete(state.available, worker_pid),
      busy: Map.delete(state.busy, worker_pid),
      workers: Map.delete(state.workers, worker_pid)
    }
    
    # Start replacement worker
    {:ok, new_worker_pid} = DSPex.PythonBridge.PoolWorker.start_link([])
    Process.monitor(new_worker_pid)
    
    replacement_state = %{new_state |
      available: [new_worker_pid | new_state.available],
      workers: Map.put(new_state.workers, new_worker_pid, %{
        status: :available,
        started_at: DateTime.utc_now()
      })
    }
    
    {:noreply, replacement_state}
  end
  
  defp assign_worker({session_id, command, args, from} = request, state) do
    case state.available do
      [worker_pid | remaining_available] ->
        request_ref = make_ref()
        
        # Send work to worker
        enhanced_args = Map.merge(args, %{
          session_id: session_id,
          request_ref: request_ref
        })
        
        case DSPex.PythonBridge.PoolWorker.execute(worker_pid, command, enhanced_args) do
          :ok ->
            new_state = %{state |
              available: remaining_available,
              busy: Map.put(state.busy, worker_pid, {session_id, request_ref, from})
            }
            {:ok, new_state}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      [] ->
        # No workers available, queue request
        new_pending = :queue.in(request, state.pending)
        {:queue, %{state | pending: new_pending}}
    end
  end
  
  defp process_queue(state) do
    case {state.available, :queue.out(state.pending)} do
      {[_worker | _], {{:value, request}, new_pending}} ->
        # Have worker and queued request
        new_state = %{state | pending: new_pending}
        case assign_worker(request, new_state) do
          {:ok, final_state} -> {:noreply, final_state}
          {:queue, final_state} -> {:noreply, final_state}  # Shouldn't happen
          {:error, _reason} -> {:noreply, new_state}  # Drop failed request
        end
        
      _ ->
        # No workers or no queued requests
        {:noreply, state}
    end
  end
  
  defp update_session_stats(session_id) do
    case :ets.lookup(:session_store, session_id) do
      [{^session_id, session_data}] ->
        updated_stats = Map.update!(session_data.stats, :commands, &(&1 + 1))
        updated_data = %{session_data | stats: updated_stats}
        :ets.insert(:session_store, {session_id, updated_data})
        
      [] ->
        # Session was deleted while request was processing
        :ok
    end
  end
end
```

#### Pool Worker Process
```elixir
defmodule DSPex.PythonBridge.PoolWorker do
  use GenServer
  
  defstruct [
    :worker_id,
    :port,
    :python_path,
    :script_path,
    current_request: nil,
    requests: %{},
    request_id: 0,
    status: :starting
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def execute(worker_pid, command, args) do
    GenServer.call(worker_pid, {:execute, command, args})
  end
  
  @impl true
  def init(opts) do
    worker_id = Keyword.get(opts, :worker_id, :rand.uniform(1000))
    
    case start_python_worker_process() do
      {:ok, port} ->
        state = %__MODULE__{
          worker_id: worker_id,
          port: port,
          status: :ready
        }
        {:ok, state}
        
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:execute, command, args}, _from, state) do
    case state.status do
      :ready ->
        request_id = state.request_id + 1
        session_id = Map.get(args, :session_id)
        
        # Enhance args with session context
        enhanced_args = Map.merge(args, %{
          worker_id: state.worker_id,
          session_context: get_session_context(session_id)
        })
        
        request = encode_request(request_id, command, enhanced_args)
        send(state.port, {self(), {:command, request}})
        
        new_state = %{state |
          request_id: request_id,
          current_request: {request_id, session_id, args[:request_ref]},
          status: :working
        }
        
        {:reply, :ok, new_state}
        
      status ->
        {:reply, {:error, {:worker_busy, status}}, state}
    end
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case decode_response(data) do
      {:ok, request_id, result} ->
        case state.current_request do
          {^request_id, session_id, request_ref} ->
            # Update session data in store
            update_session_data(session_id, result)
            
            # Notify pool manager
            send(DSPex.PythonBridge.ProcessPool, {:worker_result, self(), {:ok, result}})
            
            new_state = %{state |
              current_request: nil,
              status: :ready
            }
            
            {:noreply, new_state}
            
          _ ->
            Logger.warning("Worker #{state.worker_id} received response for unexpected request #{request_id}")
            {:noreply, state}
        end
        
      {:error, reason} ->
        # Notify pool manager of error
        send(DSPex.PythonBridge.ProcessPool, {:worker_result, self(), {:error, reason}})
        
        new_state = %{state |
          current_request: nil,
          status: :ready
        }
        
        {:noreply, new_state}
    end
  end
  
  defp start_python_worker_process do
    script_path = get_bridge_script_path()
    python_path = get_python_executable()
    
    port_opts = [
      {:args, [script_path, "--mode", "pool-worker"]},
      :binary,
      :exit_status,
      {:packet, 4}
    ]
    
    try do
      port = Port.open({:spawn_executable, python_path}, port_opts)
      {:ok, port}
    rescue
      error -> {:error, "Failed to start worker process: #{inspect(error)}"}
    end
  end
  
  defp get_session_context(session_id) do
    case :ets.lookup(:session_store, session_id) do
      [{^session_id, session_data}] ->
        %{
          programs: session_data.programs,
          config: session_data.config,
          stats: session_data.stats
        }
      [] ->
        %{programs: %{}, config: %{}, stats: %{}}
    end
  end
  
  defp update_session_data(session_id, result) do
    # Update session data based on command result
    case :ets.lookup(:session_store, session_id) do
      [{^session_id, session_data}] ->
        updated_data = apply_result_to_session(session_data, result)
        :ets.insert(:session_store, {session_id, updated_data})
        
      [] ->
        # Session was deleted
        :ok
    end
  end
  
  defp apply_result_to_session(session_data, %{"command" => "create_program", "program_id" => program_id} = result) do
    updated_programs = Map.put(session_data.programs, program_id, %{
      created_at: DateTime.utc_now(),
      signature: result["signature"]
    })
    
    updated_stats = Map.update!(session_data.stats, :programs_created, &(&1 + 1))
    
    %{session_data | programs: updated_programs, stats: updated_stats}
  end
  
  defp apply_result_to_session(session_data, _result) do
    # For other commands, just return unchanged
    session_data
  end
end
```

#### Python Pool Worker Bridge
```python
import sys
import time
import json
import argparse
from typing import Dict, Any, Optional

class PoolWorkerBridge:
    def __init__(self, mode="pool-worker"):
        self.mode = mode
        self.worker_id = None
        self.current_session = None
        self.session_cache = {}  # Cache session data for performance
        
        # Global DSPy programs - shared across sessions but namespaced
        self.global_programs = {}  # {session_id: {program_id: program}}
        
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        session_id = args.get('session_id')
        worker_id = args.get('worker_id')
        session_context = args.get('session_context', {})
        
        if not session_id:
            raise ValueError("Session ID required for pool worker commands")
            
        # Load session context
        self._load_session_context(session_id, session_context)
        
        # Process command in session namespace
        return self._execute_in_session(session_id, command, args)
    
    def _load_session_context(self, session_id: str, context: Dict[str, Any]):
        """Load session state from context provided by Elixir"""
        
        # Initialize session namespace if not exists
        if session_id not in self.global_programs:
            self.global_programs[session_id] = {}
            
        # Update session cache
        self.session_cache[session_id] = {
            'programs': context.get('programs', {}),
            'config': context.get('config', {}),
            'stats': context.get('stats', {}),
            'loaded_at': time.time()
        }
        
        # Restore DSPy programs for this session
        for program_id, program_data in context.get('programs', {}).items():
            if program_id not in self.global_programs[session_id]:
                # Recreate DSPy program from stored data
                self.global_programs[session_id][program_id] = self._recreate_program(program_data)
    
    def _execute_in_session(self, session_id: str, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute command within session namespace"""
        
        if command == 'create_program':
            return self._create_program_in_session(session_id, args)
        elif command == 'execute_program':
            return self._execute_program_in_session(session_id, args)
        elif command == 'list_programs':
            return self._list_programs_in_session(session_id, args)
        elif command == 'delete_program':
            return self._delete_program_in_session(session_id, args)
        elif command == 'get_stats':
            return self._get_session_stats(session_id, args)
        else:
            raise ValueError(f"Unknown command: {command}")
    
    def _create_program_in_session(self, session_id: str, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['id']
        signature_def = args['signature']
        
        # Check if program exists in this session
        session_programs = self.global_programs.get(session_id, {})
        if program_id in session_programs:
            raise ValueError(f"Program '{program_id}' already exists in session {session_id}")
        
        # Create DSPy program
        try:
            program = self._create_dspy_program(signature_def)
            
            # Store in session namespace
            if session_id not in self.global_programs:
                self.global_programs[session_id] = {}
            self.global_programs[session_id][program_id] = program
            
            return {
                'status': 'created',
                'program_id': program_id,
                'session_id': session_id,
                'worker_id': self.worker_id,
                'command': 'create_program',
                'signature': signature_def
            }
            
        except Exception as e:
            raise RuntimeError(f"Failed to create program in session {session_id}: {str(e)}")
    
    def _execute_program_in_session(self, session_id: str, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['program_id']
        inputs = args['inputs']
        
        # Get program from session namespace
        session_programs = self.global_programs.get(session_id, {})
        if program_id not in session_programs:
            raise ValueError(f"Program '{program_id}' not found in session {session_id}")
        
        program = session_programs[program_id]
        
        # Configure DSPy for this session if needed
        session_config = self.session_cache.get(session_id, {}).get('config', {})
        if 'lm_config' in session_config:
            self._configure_session_lm(session_config['lm_config'])
        
        try:
            # Execute program
            result = program(**inputs)
            
            return {
                'status': 'executed',
                'program_id': program_id,
                'session_id': session_id,
                'result': result,
                'worker_id': self.worker_id
            }
            
        except Exception as e:
            raise RuntimeError(f"Program execution failed in session {session_id}: {str(e)}")
    
    def _list_programs_in_session(self, session_id: str, args: Dict[str, Any]) -> Dict[str, Any]:
        session_programs = self.global_programs.get(session_id, {})
        program_ids = list(session_programs.keys())
        
        return {
            'status': 'listed',
            'session_id': session_id,
            'programs': program_ids,
            'count': len(program_ids)
        }
    
    def _delete_program_in_session(self, session_id: str, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['program_id']
        
        session_programs = self.global_programs.get(session_id, {})
        if program_id not in session_programs:
            raise ValueError(f"Program '{program_id}' not found in session {session_id}")
        
        # Remove program
        del session_programs[program_id]
        
        return {
            'status': 'deleted',
            'program_id': program_id,
            'session_id': session_id
        }
    
    def _get_session_stats(self, session_id: str, args: Dict[str, Any]) -> Dict[str, Any]:
        session_programs = self.global_programs.get(session_id, {})
        session_cache = self.session_cache.get(session_id, {})
        
        return {
            'session_id': session_id,
            'programs_count': len(session_programs),
            'cached_stats': session_cache.get('stats', {}),
            'worker_id': self.worker_id,
            'mode': self.mode
        }
    
    def _create_dspy_program(self, signature_def):
        """Create DSPy program from signature definition"""
        # Implementation depends on signature format
        # This is simplified - real implementation would handle complex signatures
        import dspy
        
        # Create signature class dynamically
        inputs = signature_def.get('inputs', [])
        outputs = signature_def.get('outputs', [])
        
        # Build signature string for DSPy
        input_fields = [f"{inp['name']}" for inp in inputs]
        output_fields = [f"{out['name']}" for out in outputs]
        signature_str = ", ".join(input_fields) + " -> " + ", ".join(output_fields)
        
        # Create and return DSPy program
        return dspy.Predict(signature_str)
    
    def _recreate_program(self, program_data):
        """Recreate DSPy program from stored metadata"""
        # This would restore program from saved state
        # Implementation depends on how programs are serialized
        signature = program_data.get('signature')
        return self._create_dspy_program(signature)
    
    def _configure_session_lm(self, lm_config):
        """Configure DSPy LM for specific session"""
        # This would set up session-specific LM configuration
        # Could be different LM per session, or shared with different settings
        pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', default='pool-worker', help='Bridge mode')
    args = parser.parse_args()
    
    bridge = PoolWorkerBridge(mode=args.mode)
    
    print(f"DSPy Pool Worker Bridge started in {args.mode} mode", file=sys.stderr)
    
    # Main message loop
    while True:
        try:
            message = read_message()
            if message is None:
                print("No more messages, worker exiting", file=sys.stderr)
                break
                
            command = message.get('command')
            args = message.get('args', {})
            request_id = message.get('id')
            
            if not command or request_id is None:
                write_message({
                    'id': request_id,
                    'error': 'Invalid message format'
                })
                continue
            
            result = bridge.handle_command(command, args)
            write_message({
                'id': request_id,
                'result': result
            })
            
        except Exception as e:
            print(f"Worker error: {e}", file=sys.stderr)
            write_message({
                'id': message.get('id') if 'message' in locals() else None,
                'error': str(e)
            })

if __name__ == '__main__':
    main()
```

### Process Pool Advantages

#### Resource Efficiency
- ✅ **Fixed resource usage**: Pool size independent of session count
- ✅ **Process reuse**: Warm processes avoid startup overhead
- ✅ **Memory optimization**: Shared process overhead across sessions
- ✅ **Better scaling**: 1000 sessions can use 5-10 processes

#### Performance
- ✅ **No cold starts**: Processes stay warm and ready
- ✅ **Load balancing**: Work distributed across available processes
- ✅ **Queue management**: Handle bursts efficiently
- ✅ **Parallelism**: Multiple requests processed simultaneously

#### Production Readiness
- ✅ **Horizontal scaling**: Easy to add more workers
- ✅ **Health monitoring**: Monitor worker process health
- ✅ **Fault tolerance**: Failed workers are replaced automatically
- ✅ **Resource monitoring**: Track pool utilization and performance

### Process Pool Disadvantages

#### Implementation Complexity
- ❌ **Complex state management**: Session data stored separately from execution
- ❌ **Synchronization challenges**: Ensuring session data consistency
- ❌ **Worker assignment logic**: Efficiently distributing work
- ❌ **Error handling complexity**: Managing failures across multiple layers

#### Session Data Management
- ❌ **Data marshalling overhead**: Session context passed with each request
- ❌ **State synchronization**: Keeping session store and worker state aligned
- ❌ **Memory usage**: Session data stored in multiple places
- ❌ **Cleanup complexity**: Ensuring session data is properly cleaned up

#### Debugging Challenges
- ❌ **Request tracing**: Harder to follow request through pool
- ❌ **Session affinity issues**: Same session may execute on different workers
- ❌ **State debugging**: Session state distributed across components
- ❌ **Race conditions**: Potential for concurrent access issues

#### DSPy Integration Challenges
- ❌ **Global state conflicts**: `dspy.configure()` shared across sessions
- ❌ **Program lifecycle**: Managing DSPy program creation/destruction
- ❌ **Memory leaks**: Programs may accumulate in worker processes
- ❌ **Library limitations**: Some Python libraries not thread-safe

## Comparative Analysis

### Resource Usage Comparison

| Metric | Process-Per-Session | Process Pool |
|--------|-------------------|--------------|
| **Memory (100 sessions)** | ~5-10GB (50-100MB × 100) | ~500MB-1GB (100MB × 5-10) |
| **Startup Time** | ~1-2s per session | ~1-2s total pool startup |
| **CPU Overhead** | High (context switching) | Low (shared processes) |
| **File Descriptors** | High (per process) | Low (pool size) |

### Scalability Comparison

| Sessions | Process-Per-Session | Process Pool |
|----------|-------------------|--------------|
| **10** | ✅ Works well | ✅ Works well |
| **100** | ⚠️ Heavy resource usage | ✅ Efficient |
| **1000** | ❌ Likely resource exhaustion | ✅ Good performance |
| **10000** | ❌ Impossible on most systems | ⚠️ May need pool scaling |

### Development Complexity Comparison

| Aspect | Process-Per-Session | Process Pool |
|--------|-------------------|--------------|
| **Initial Implementation** | ✅ Simpler | ❌ Complex |
| **Testing** | ✅ Easier to test | ❌ Complex test scenarios |
| **Debugging** | ✅ Clear process boundaries | ❌ Distributed state |
| **Maintenance** | ✅ Straightforward | ❌ Multiple moving parts |
| **Feature Addition** | ✅ Simple | ❌ Requires pool coordination |

### Performance Characteristics

| Scenario | Process-Per-Session | Process Pool |
|----------|-------------------|--------------|
| **Low Concurrency (1-10 sessions)** | ✅ Good | ✅ Good |
| **Medium Concurrency (10-100 sessions)** | ⚠️ Resource intensive | ✅ Excellent |
| **High Concurrency (100+ sessions)** | ❌ Poor/Impossible | ✅ Very good |
| **Burst Traffic** | ❌ Slow session creation | ✅ Queue management |
| **Session Creation** | ❌ 1-2s startup | ✅ Immediate |
| **Session Cleanup** | ✅ Process termination | ⚠️ Complex cleanup |

## Implementation Recommendations

### Phase 1: Immediate Solution (Process-Per-Session)
**Timeline**: 1-2 weeks
**Use Case**: Fix current test issues, support low-medium concurrency

```elixir
# Simple implementation for immediate needs
{:ok, session_id} = SessionManager.create_session()
{:ok, result} = SessionManager.call(session_id, :create_program, args)
:ok = SessionManager.destroy_session(session_id)
```

**Benefits**:
- ✅ Solves current test isolation issues
- ✅ Provides true session isolation
- ✅ Simpler to implement and debug
- ✅ Good enough for current scale needs

**Limitations**:
- ❌ Won't scale beyond ~50-100 concurrent sessions
- ❌ Resource intensive for high-concurrency scenarios

### Phase 2: Production Solution (Process Pool)
**Timeline**: 4-6 weeks
**Use Case**: Production deployment, high concurrency support

```elixir
# Advanced implementation for production scale
{:ok, session_id} = ProcessPool.create_session()
{:ok, result} = ProcessPool.execute(session_id, :create_program, args)
:ok = ProcessPool.destroy_session(session_id)
```

**Benefits**:
- ✅ Scales to hundreds/thousands of concurrent sessions
- ✅ Resource efficient
- ✅ Production-ready architecture
- ✅ Better performance characteristics

**Challenges**:
- ❌ Complex implementation
- ❌ Requires careful state management
- ❌ More testing and debugging complexity

### Hybrid Approach: Common API
**Design a common API that works for both implementations:**

```elixir
defmodule DSPex.PythonBridge.SessionAPI do
  @behaviour DSPex.PythonBridge.SessionBehaviour
  
  def create_session(opts \\ []) do
    case get_backend() do
      :process_per_session -> SessionManager.create_session(opts)
      :process_pool -> ProcessPool.create_session(opts)
    end
  end
  
  def call(session_id, command, args, timeout \\ 5000) do
    case get_backend() do
      :process_per_session -> SessionManager.call(session_id, command, args, timeout)
      :process_pool -> ProcessPool.execute(session_id, command, args, timeout)
    end
  end
  
  def destroy_session(session_id) do
    case get_backend() do
      :process_per_session -> SessionManager.destroy_session(session_id)
      :process_pool -> ProcessPool.destroy_session(session_id)
    end
  end
  
  defp get_backend do
    Application.get_env(:dspex, :session_backend, :process_per_session)
  end
end
```

**This allows**:
- ✅ Start with simple implementation
- ✅ Migrate to complex implementation later
- ✅ A/B testing between approaches
- ✅ Configuration-based backend selection

## Configuration and Deployment

### Process-Per-Session Configuration
```elixir
config :dspex, :session_backend, :process_per_session

config :dspex, :process_per_session,
  max_idle_seconds: 3600,        # 1 hour idle timeout
  max_concurrent_sessions: 100,   # Limit total sessions
  cleanup_interval: 60_000,      # Check every minute
  python_executable: "python3",
  python_timeout: 30_000
```

### Process Pool Configuration
```elixir
config :dspex, :session_backend, :process_pool

config :dspex, :process_pool,
  pool_size: 10,                 # Number of worker processes
  max_queue_size: 1000,          # Max queued requests
  worker_timeout: 30_000,        # Request timeout
  session_cleanup_interval: 300, # Clean session store every 5 min
  worker_restart_strategy: :permanent
```

## Monitoring and Observability

### Key Metrics to Track

#### Process-Per-Session Metrics
- Active session count
- Memory usage per session
- Session creation/destruction rate
- Idle session count
- Process restart rate

#### Process Pool Metrics
- Pool utilization (busy workers / total workers)
- Queue depth and wait times
- Session store size
- Worker failure rate
- Request throughput per worker

### Health Checks

#### Process-Per-Session Health
```elixir
def health_check do
  %{
    active_sessions: SessionSupervisor.count_children().active,
    memory_usage: get_total_memory_usage(),
    idle_sessions: count_idle_sessions(),
    failed_sessions: count_failed_sessions()
  }
end
```

#### Process Pool Health
```elixir
def health_check do
  %{
    pool_size: ProcessPool.pool_size(),
    available_workers: ProcessPool.available_count(),
    queue_depth: ProcessPool.queue_depth(),
    session_count: ProcessPool.session_count(),
    avg_response_time: ProcessPool.avg_response_time()
  }
end
```

## Migration Strategy

### From Current to Process-Per-Session
1. **Implement SessionManager API**
2. **Update tests to use sessions**
3. **Add session cleanup to test teardown**
4. **Configure session timeouts**
5. **Add monitoring and health checks**

### From Process-Per-Session to Process Pool
1. **Implement ProcessPool alongside SessionManager**
2. **Add configuration switch between backends**
3. **Migrate tests to use unified SessionAPI**
4. **Load test both approaches**
5. **Gradual rollout in production**
6. **Remove SessionManager once stable**

## Conclusion

Both approaches solve the immediate session isolation problem but with different trade-offs:

**Process-Per-Session** is the right choice for:
- ✅ Immediate implementation needs
- ✅ Simple debugging and testing
- ✅ Low-to-medium concurrency scenarios
- ✅ Development and testing environments

**Process Pool** is the right choice for:
- ✅ Production high-concurrency scenarios
- ✅ Resource-constrained environments
- ✅ Long-term scalability requirements
- ✅ Performance-critical applications

**Recommendation**: Start with **Process-Per-Session** to solve immediate needs, then migrate to **Process Pool** for production scaling. Use a common API to enable smooth migration.

The session isolation problem is fundamentally about choosing the right level of abstraction for concurrent execution. Both approaches provide isolation, but at different costs and complexity levels.
# Prompt: Implement ML Platform Worker and Adapter Integration

## Context

**CRITICAL UNDERSTANDING:** `snakepit` provides robust, generic process management infrastructure. Your task is NOT to rebuild this infrastructure, but to create ML-specific workers and plug them into the existing `snakepit` system via the `Snakepit.Adapter` behavior.

## Required Reading

Before starting, read these documents in order:
1. `docs/specs/threeLayerRevised/01_LIGHT_SNAKEPIT_HEAVY_BRIDGE_ARCHITECTURE.md` - Overall architecture
2. `docs/specs/threeLayerRevised/02_SNAKEPIT_INFRASTRUCTURE_SPECIFICATION.md` - Infrastructure capabilities  
3. `docs/specs/threeLayerRevised/07_DETAILED_IN_PLACE_IMPLEMENTATION_PLAN.md` - Implementation plan (Days 8-9)

## Current State Analysis

Examine the existing `snakepit` infrastructure to understand what already exists:
- `./snakepit/lib/snakepit/pool/` - Existing worker supervision (`DynamicSupervisor`, `WorkerSupervisor`)
- `./snakepit/lib/snakepit/pool/process_registry.ex` - OS PID tracking with DETS
- `./snakepit/lib/snakepit/adapter.ex` - Adapter behavior contract
- `./snakepit/lib/snakepit/application_cleanup.ex` - Graceful shutdown handling

**Key Insight:** All the robust process management already exists. You just need to implement the ML-specific pieces.

## Objective

Create an Elixir-side worker process that manages communication with a single Python OS process and fully implement the `SnakepitGRPCBridge.Adapter` callbacks to integrate with the existing `snakepit` infrastructure.

## Implementation Tasks

### Task 1: Create the Python Worker GenServer

Create `lib/snakepit_grpc_bridge/python/process.ex`:

```elixir
defmodule SnakepitGRPCBridge.Python.Process do
  @moduledoc """
  Single Python worker process that manages communication with one Python OS process.
  
  This GenServer represents one Elixir <-> Python bridge. It will be started by
  the existing Snakepit infrastructure through our adapter.
  """
  
  use GenServer
  require Logger
  
  @doc """
  Start a Python worker process. Called by our adapter.
  """
  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    GenServer.start_link(__MODULE__, opts, name: :"python_worker_#{worker_id}")
  end
  
  @doc """
  Execute a command on this Python worker.
  """
  def execute(worker_pid, command, args) do
    GenServer.call(worker_pid, {:execute, command, args}, 30_000)
  end
  
  @impl GenServer
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    
    # IMPORTANT: Use existing Snakepit process tracking
    case Snakepit.Pool.ProcessRegistry.reserve_worker(worker_id) do
      :ok ->
        case start_python_port(worker_id) do
          {:ok, port, os_pid} ->
            # IMPORTANT: Register the OS PID with existing infrastructure
            Snakepit.Pool.ProcessRegistry.activate_worker(worker_id, self(), port, os_pid)
            
            state = %{
              worker_id: worker_id,
              port: port,
              os_pid: os_pid,
              pending_requests: %{}
            }
            
            Logger.info("Python worker started", worker_id: worker_id, os_pid: os_pid)
            {:ok, state}
          
          {:error, reason} ->
            Snakepit.Pool.ProcessRegistry.unregister_worker(worker_id)
            {:stop, reason}
        end
      
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  @impl GenServer
  def handle_call({:execute, command, args}, from, state) do
    request_id = generate_request_id()
    
    # Build Python request
    python_request = %{
      request_id: request_id,
      command: command,
      args: args
    }
    
    case Jason.encode(python_request) do
      {:ok, json_data} ->
        # Send to Python process
        Port.command(state.port, json_data <> "\n")
        
        # Store pending request
        updated_state = %{state | 
          pending_requests: Map.put(state.pending_requests, request_id, from)
        }
        
        {:noreply, updated_state}
      
      {:error, reason} ->
        {:reply, {:error, {:encoding_failed, reason}}, state}
    end
  end
  
  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Jason.decode(data) do
      {:ok, %{"request_id" => request_id, "success" => true, "result" => result}} ->
        case Map.pop(state.pending_requests, request_id) do
          {from, updated_requests} when from != nil ->
            GenServer.reply(from, {:ok, result})
            {:noreply, %{state | pending_requests: updated_requests}}
          
          {nil, _} ->
            Logger.warn("Received response for unknown request", request_id: request_id)
            {:noreply, state}
        end
      
      {:ok, %{"request_id" => request_id, "success" => false, "error" => error}} ->
        case Map.pop(state.pending_requests, request_id) do
          {from, updated_requests} when from != nil ->
            GenServer.reply(from, {:error, error})
            {:noreply, %{state | pending_requests: updated_requests}}
          
          {nil, _} ->
            {:noreply, state}
        end
      
      {:error, decode_error} ->
        Logger.error("Failed to decode Python response", error: decode_error, data: data)
        {:noreply, state}
    end
  end
  
  @impl GenServer
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited", worker_id: state.worker_id, exit_status: status)
    {:stop, {:python_process_exited, status}, state}
  end
  
  @impl GenServer
  def terminate(_reason, state) do
    # IMPORTANT: Clean up with existing infrastructure
    if state.port do
      Port.close(state.port)
    end
    
    # Unregister from Snakepit's process tracking
    Snakepit.Pool.ProcessRegistry.unregister_worker(state.worker_id)
    
    :ok
  end
  
  # Private helper functions
  
  defp start_python_port(worker_id) do
    python_script = Application.app_dir(:snakepit_grpc_bridge, "priv/python/worker.py")
    
    port_opts = [
      :binary,
      :exit_status,
      {:line, 1024},
      {:args, [python_script, "--worker-id", to_string(worker_id)]},
      {:env, [{"PYTHONPATH", get_python_path()}]}
    ]
    
    try do
      port = Port.open({:spawn_executable, get_python_executable()}, port_opts)
      
      # Wait for Python to report its PID
      receive do
        {^port, {:data, {:eol, line}}} ->
          case Jason.decode(line) do
            {:ok, %{"type" => "ready", "pid" => os_pid}} ->
              {:ok, port, os_pid}
            
            _ ->
              Port.close(port)
              {:error, :invalid_ready_message}
          end
        
        {^port, {:exit_status, status}} ->
          {:error, {:startup_failed, status}}
      after
        10_000 ->
          Port.close(port)
          {:error, :startup_timeout}
      end
    rescue
      error ->
        {:error, {:port_failed, error}}
    end
  end
  
  defp get_python_executable() do
    Application.get_env(:snakepit_grpc_bridge, :python_executable, "python3")
  end
  
  defp get_python_path() do
    Application.app_dir(:snakepit_grpc_bridge, "priv/python")
  end
  
  defp generate_request_id() do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
```

### Task 2: Implement the SnakepitGRPCBridge.Adapter

Create `lib/snakepit_grpc_bridge/adapter.ex`:

```elixir
defmodule SnakepitGRPCBridge.Adapter do
  @moduledoc """
  Adapter that integrates the ML platform with Snakepit infrastructure.
  
  This is the glue between the generic snakepit pool and our specific Python workers.
  """
  
  @behaviour Snakepit.Adapter
  require Logger
  
  @impl Snakepit.Adapter
  def start_worker(_adapter_state, worker_id) do
    # This is called by Snakepit's supervision tree
    # Our job is to start one of our Python.Process workers
    Logger.debug("Adapter starting ML worker", worker_id: worker_id)
    
    case SnakepitGRPCBridge.Python.Process.start_link(worker_id: worker_id) do
      {:ok, worker_pid} ->
        Logger.info("ML worker started successfully", worker_id: worker_id, worker_pid: worker_pid)
        {:ok, worker_pid}
      
      {:error, reason} ->
        Logger.error("Failed to start ML worker", worker_id: worker_id, reason: reason)
        {:error, reason}
    end
  end
  
  @impl Snakepit.Adapter  
  def execute(command, args, opts) do
    # This is called by Snakepit.Pool manager
    # The worker_pid is provided in opts
    worker_pid = Keyword.fetch!(opts, :worker_pid)
    session_id = Keyword.get(opts, :session_id)
    
    Logger.debug("Adapter executing command", 
      command: command, 
      worker_pid: worker_pid, 
      session_id: session_id
    )
    
    # Add session context to args if present
    enhanced_args = if session_id do
      Map.put(args, :session_id, session_id)
    else
      args
    end
    
    # Execute on our Python worker
    SnakepitGRPCBridge.Python.Process.execute(worker_pid, command, enhanced_args)
  end
  
  @impl Snakepit.Adapter
  def init(_config) do
    Logger.info("Initializing ML platform adapter")
    
    # Perform any global initialization for the ML platform
    # Return adapter state (can be any term)
    {:ok, %{initialized_at: DateTime.utc_now()}}
  end
  
  @impl Snakepit.Adapter
  def terminate(_reason, _adapter_state) do
    Logger.info("Terminating ML platform adapter")
    :ok
  end
  
  # Optional: Session affinity logic
  # You can implement session -> worker affinity here using Registry
  
  def get_preferred_worker_for_session(session_id) do
    # This could use Registry to maintain session -> worker mappings
    # For now, letting Snakepit handle load balancing
    :no_preference
  end
end
```

### Task 3: Create Python Worker Script

Create `priv/python/worker.py`:

```python
#!/usr/bin/env python3
"""
Python worker script that communicates with Elixir via JSON lines.

This script is started by the SnakepitGRPCBridge.Python.Process and handles
ML platform operations.
"""

import sys
import json
import os
import signal
from datetime import datetime

# Import your ML platform modules
from snakepit_bridge.core.session import SessionManager
from snakepit_bridge.variables.manager import VariableManager  
from snakepit_bridge.tools.executor import ToolExecutor
from snakepit_bridge.dspy.integration import DSPyOperations

class PythonWorker:
    """Main worker class that handles requests from Elixir."""
    
    def __init__(self, worker_id):
        self.worker_id = worker_id
        self.running = True
        
        # Initialize ML platform components
        self.session_manager = SessionManager()
        self.variable_manager = VariableManager()
        self.tool_executor = ToolExecutor()
        self.dspy_operations = DSPyOperations()
        
        # Command handlers
        self.handlers = {
            'create_variable': self.handle_create_variable,
            'get_variable': self.handle_get_variable,
            'execute_tool': self.handle_execute_tool,
            'enhanced_predict': self.handle_enhanced_predict,
            # Add more command handlers
        }
    
    def start(self):
        """Start the worker and send ready signal."""
        # Send ready signal with our OS PID
        ready_message = {
            'type': 'ready',
            'pid': os.getpid(),
            'worker_id': self.worker_id,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        print(json.dumps(ready_message), flush=True)
        
        # Start processing requests
        self.process_requests()
    
    def process_requests(self):
        """Main request processing loop."""
        while self.running:
            try:
                # Read JSON request from stdin
                line = sys.stdin.readline().strip()
                if not line:
                    break
                
                request = json.loads(line)
                self.handle_request(request)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                error_response = {
                    'request_id': request.get('request_id', 'unknown'),
                    'success': False,
                    'error': {
                        'type': type(e).__name__,
                        'message': str(e)
                    }
                }
                print(json.dumps(error_response), flush=True)
    
    def handle_request(self, request):
        """Handle a single request from Elixir."""
        request_id = request.get('request_id')
        command = request.get('command')
        args = request.get('args', {})
        
        try:
            # Get handler for command
            handler = self.handlers.get(command)
            if not handler:
                raise ValueError(f"Unknown command: {command}")
            
            # Execute command
            result = handler(args)
            
            # Send success response
            response = {
                'request_id': request_id,
                'success': True,
                'result': result
            }
            
        except Exception as e:
            # Send error response
            response = {
                'request_id': request_id,
                'success': False,
                'error': {
                    'type': type(e).__name__,
                    'message': str(e)
                }
            }
        
        print(json.dumps(response), flush=True)
    
    def handle_create_variable(self, args):
        """Handle variable creation."""
        session_id = args['session_id']
        var_name = args['name']
        var_type = args['type']
        var_value = args['value']
        
        return self.variable_manager.create_variable(
            session_id, var_name, var_type, var_value
        )
    
    def handle_get_variable(self, args):
        """Handle variable retrieval."""
        session_id = args['session_id']
        var_name = args['name']
        
        return self.variable_manager.get_variable(session_id, var_name)
    
    def handle_execute_tool(self, args):
        """Handle tool execution."""
        session_id = args['session_id']
        tool_name = args['tool_name']
        tool_args = args['arguments']
        
        return self.tool_executor.execute(session_id, tool_name, tool_args)
    
    def handle_enhanced_predict(self, args):
        """Handle DSPy prediction."""
        session_id = args['session_id']
        signature = args['signature']
        inputs = args['inputs']
        
        return self.dspy_operations.enhanced_predict(session_id, signature, inputs)

def main():
    """Main entry point."""
    if len(sys.argv) != 3 or sys.argv[1] != '--worker-id':
        print("Usage: worker.py --worker-id <worker_id>", file=sys.stderr)
        sys.exit(1)
    
    worker_id = sys.argv[2]
    worker = PythonWorker(worker_id)
    
    # Handle shutdown gracefully
    def signal_handler(sig, frame):
        worker.running = False
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    worker.start()

if __name__ == '__main__':
    main()
```

### Task 4: Configure the System

Update your application configuration:

```elixir
# config/config.exs
import Config

# Configure Snakepit to use our adapter
config :snakepit,
  adapter_module: SnakepitGRPCBridge.Adapter,
  pool_size: 4,
  worker_timeout: 30_000

# ML platform configuration  
config :snakepit_grpc_bridge,
  python_executable: "python3"
```

## Validation

After completing this implementation, verify:

1. ✅ Snakepit starts and uses your adapter to start Python workers
2. ✅ A call to `Snakepit.execute_in_session/3` correctly routes through `Snakepit.Pool` to your adapter, into your worker GenServer, over the port to Python, and back
3. ✅ Killing a Python OS process causes the existing `Worker.Starter` to automatically restart it
4. ✅ Session affinity works - same session ID uses same worker when possible
5. ✅ The existing `ProcessRegistry` correctly tracks your Python OS processes
6. ✅ Graceful shutdown works through the existing `ApplicationCleanup`

## Next Steps

This implementation leverages the existing robust Snakepit infrastructure instead of rebuilding it. The next prompt will implement the variables system that uses this Python bridge.

## Files Created

- `lib/snakepit_grpc_bridge/python/process.ex` - Python worker GenServer
- `lib/snakepit_grpc_bridge/adapter.ex` - Snakepit adapter implementation  
- `priv/python/worker.py` - Python worker script
- Configuration updates

This approach respects and leverages your existing excellent infrastructure while adding the ML-specific functionality on top.
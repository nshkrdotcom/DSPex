# Stage 1 Prompt 2: Python Bridge Communication Layer

## OBJECTIVE

Implement a robust GenServer-based Python bridge that enables bidirectional communication between Elixir and Python DSPy processes. This bridge must handle process lifecycle management, request/response correlation, error handling, and provide a clean interface for executing DSPy operations from Elixir.

## COMPLETE IMPLEMENTATION CONTEXT

### PYTHON BRIDGE ARCHITECTURE OVERVIEW

From STAGE_1_FOUNDATION_IMPLEMENTATION.md, the Python bridge consists of:

```
lib/dspex/python_bridge/
├── bridge.ex             # GenServer for Python communication
└── protocol.ex           # Wire protocol
priv/python/
└── dspy_bridge.py        # Python bridge script
```

**Core Requirements:**
- GenServer managing Python subprocess lifecycle
- Packet-based binary communication with length headers
- JSON protocol for structured data exchange
- Request/response correlation with unique IDs
- Error handling and process recovery
- Timeout management for long-running operations

### COMPLETE GENSERVER IMPLEMENTATION REFERENCE

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule DSPex.PythonBridge.Bridge do
  @moduledoc """
  GenServer managing Python DSPy process communication.
  """
  
  use GenServer
  require Logger
  
  alias DSPex.PythonBridge.Protocol
  
  defstruct [:port, :requests, :request_id]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def call(command, args, timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:call, command, args}, timeout)
  end
  
  @impl true
  def init(_opts) do
    python_script = Path.join(:code.priv_dir(:dspex), "python/dspy_bridge.py")
    
    case System.find_executable("python3") do
      nil -> 
        {:stop, "Python 3 not found"}
      python_path ->
        port = Port.open({:spawn_executable, python_path}, [
          {:args, [python_script]},
          {:packet, 4},
          :binary,
          :exit_status
        ])
        
        {:ok, %__MODULE__{
          port: port,
          requests: %{},
          request_id: 0
        }}
    end
  end
  
  @impl true
  def handle_call({:call, command, args}, from, state) do
    request_id = state.request_id + 1
    
    request = Protocol.encode_request(request_id, command, args)
    
    # Send to Python
    send(state.port, {self(), {:command, request}})
    
    # Store request
    new_requests = Map.put(state.requests, request_id, from)
    
    {:noreply, %{state | requests: new_requests, request_id: request_id}}
  end
  
  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Protocol.decode_response(data) do
      {:ok, id, result} ->
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warning("Received response for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
          {from, requests} ->
            GenServer.reply(from, {:ok, result})
            {:noreply, %{state | requests: requests}}
        end
      
      {:error, id, error} ->
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warning("Received error for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
          {from, requests} ->
            GenServer.reply(from, {:error, error})
            {:noreply, %{state | requests: requests}}
        end
      
      {:error, reason} ->
        Logger.error("Failed to decode Python response: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, :python_process_died, state}
  end
end
```

### WIRE PROTOCOL IMPLEMENTATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule DSPex.PythonBridge.Protocol do
  @moduledoc """
  Wire protocol for Python bridge communication.
  """
  
  def encode_request(id, command, args) do
    request = %{
      id: id,
      command: to_string(command),
      args: args,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Jason.encode!(request)
  end
  
  def decode_response(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "success" => true, "result" => result}} ->
        {:ok, id, result}
      
      {:ok, %{"id" => id, "success" => false, "error" => error}} ->
        {:error, id, error}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### COMPLETE PYTHON BRIDGE SCRIPT IMPLEMENTATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```python
#!/usr/bin/env python3

import sys
import json
import struct
import traceback
import dspy

class DSPyBridge:
    def __init__(self):
        self.programs = {}
        
    def handle_command(self, command, args):
        handlers = {
            'create_program': self.create_program,
            'execute_program': self.execute_program,
            'list_programs': self.list_programs
        }
        
        if command not in handlers:
            raise ValueError(f"Unknown command: {command}")
            
        return handlers[command](args)
    
    def create_program(self, args):
        program_id = args['id']
        signature_def = args['signature']
        
        # Create dynamic signature class
        class DynamicSignature(dspy.Signature):
            pass
        
        # Add input fields
        for field in signature_def['inputs']:
            setattr(DynamicSignature, field['name'], dspy.InputField())
        
        # Add output fields  
        for field in signature_def['outputs']:
            setattr(DynamicSignature, field['name'], dspy.OutputField())
        
        # Create simple predict program
        program = dspy.Predict(DynamicSignature)
        self.programs[program_id] = program
        
        return {"program_id": program_id, "status": "created"}
    
    def execute_program(self, args):
        program_id = args['program_id']
        inputs = args['inputs']
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program = self.programs[program_id]
        result = program(**inputs)
        
        # Convert result to dict
        if hasattr(result, '__dict__'):
            output = {k: v for k, v in result.__dict__.items() 
                     if not k.startswith('_')}
        else:
            output = {"result": str(result)}
        
        return output
    
    def list_programs(self, args):
        return {"programs": list(self.programs.keys())}

def read_message():
    # Read 4-byte length header
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        return None
    
    length = struct.unpack('>I', length_bytes)[0]
    
    # Read message
    message_bytes = sys.stdin.buffer.read(length)
    if len(message_bytes) < length:
        return None
    
    return json.loads(message_bytes.decode('utf-8'))

def write_message(message):
    message_bytes = json.dumps(message).encode('utf-8')
    length = len(message_bytes)
    
    # Write length header + message
    sys.stdout.buffer.write(struct.pack('>I', length))
    sys.stdout.buffer.write(message_bytes)
    sys.stdout.buffer.flush()

def main():
    bridge = DSPyBridge()
    
    while True:
        try:
            message = read_message()
            if message is None:
                break
            
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            try:
                result = bridge.handle_command(command, args)
                write_message({
                    'id': request_id,
                    'success': True,
                    'result': result
                })
            except Exception as e:
                write_message({
                    'id': request_id,
                    'success': False,
                    'error': str(e)
                })
                
        except Exception as e:
            sys.stderr.write(f"Bridge error: {e}\n")
            sys.stderr.write(traceback.format_exc())

if __name__ == '__main__':
    main()
```

### ELIXIR PORT COMMUNICATION PATTERNS

From Elixir documentation and best practices:

**Port Configuration:**
```elixir
port = Port.open({:spawn_executable, python_path}, [
  {:args, [python_script]},
  {:packet, 4},              # 4-byte length headers
  :binary,                   # Binary data mode
  :exit_status              # Monitor process exit
])
```

**Packet Protocol Details:**
- 4-byte big-endian length header
- JSON payload following header
- Bidirectional communication
- Length-prefixed for proper framing

**Message Sending:**
```elixir
send(port, {self(), {:command, encoded_request}})
```

**Message Receiving:**
```elixir
def handle_info({port, {:data, data}}, state) do
  # Process incoming data
end

def handle_info({port, {:exit_status, status}}, state) do
  # Handle process termination
end
```

### ERROR HANDLING AND RECOVERY PATTERNS

**Process Lifecycle Management:**
```elixir
defmodule DSPex.PythonBridge.Supervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {DSPex.PythonBridge.Bridge, []},
      # Add process monitor
      {DSPex.PythonBridge.Monitor, []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 60)
  end
end
```

**Error Recovery Strategies:**
- Automatic process restart on failure
- Request timeout handling
- Graceful degradation on communication errors
- Health check mechanisms

**Timeout Management:**
```elixir
def call(command, args, timeout \\ 30_000) do
  GenServer.call(__MODULE__, {:call, command, args}, timeout)
catch
  :exit, {:timeout, _} ->
    Logger.warning("Python bridge call timed out: #{command}")
    {:error, :timeout}
end
```

### INTEGRATION WITH APPLICATION SUPERVISION TREE

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule DSPex.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Start Python bridge
      DSPex.PythonBridge.Bridge,
      
      # Start Ash resources if using Postgres
      {AshPostgres.Repo, Application.get_env(:dspex, DSPex.Repo)}
    ]
    
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### CONFIGURATION AND ENVIRONMENT SETUP

**Application Configuration:**
```elixir
# config/config.exs
import Config

config :dspex, :python_bridge,
  python_executable: System.get_env("PYTHON_EXECUTABLE", "python3"),
  script_path: "python/dspy_bridge.py",
  default_timeout: 30_000,
  max_retries: 3

config :dspex, :python_environment,
  virtual_env: System.get_env("DSPY_VENV"),
  required_packages: ["dspy-ai", "openai", "numpy"]
```

**Runtime Environment Checks:**
```elixir
defmodule DSPex.PythonBridge.EnvironmentCheck do
  @moduledoc """
  Validate Python environment before starting bridge.
  """
  
  def validate_environment do
    with {:ok, python_path} <- find_python_executable(),
         {:ok, _} <- check_dspy_installation(python_path),
         {:ok, script_path} <- validate_bridge_script() do
      {:ok, %{python_path: python_path, script_path: script_path}}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp find_python_executable do
    python_cmd = Application.get_env(:dspex, :python_bridge)[:python_executable]
    
    case System.find_executable(python_cmd) do
      nil -> {:error, "Python executable not found: #{python_cmd}"}
      path -> {:ok, path}
    end
  end
  
  defp check_dspy_installation(python_path) do
    case System.cmd(python_path, ["-c", "import dspy; print(dspy.__version__)"]) do
      {version, 0} -> 
        Logger.info("DSPy version: #{String.trim(version)}")
        {:ok, version}
      {error, _} -> 
        {:error, "DSPy not installed or not accessible: #{error}"}
    end
  end
  
  defp validate_bridge_script do
    script_path = Path.join(:code.priv_dir(:dspex), "python/dspy_bridge.py")
    
    if File.exists?(script_path) do
      {:ok, script_path}
    else
      {:error, "Python bridge script not found: #{script_path}"}
    end
  end
end
```

### HEALTH MONITORING AND METRICS

**Bridge Health Monitoring:**
```elixir
defmodule DSPex.PythonBridge.Monitor do
  use GenServer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    schedule_health_check()
    {:ok, %{last_check: DateTime.utc_now(), failures: 0}}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    case perform_health_check() do
      :ok ->
        schedule_health_check()
        {:noreply, %{state | last_check: DateTime.utc_now(), failures: 0}}
      
      {:error, reason} ->
        new_failures = state.failures + 1
        Logger.warning("Python bridge health check failed: #{reason} (#{new_failures})")
        
        if new_failures >= 3 do
          Logger.error("Python bridge unhealthy, restarting...")
          DSPex.PythonBridge.Bridge.restart()
        end
        
        schedule_health_check()
        {:noreply, %{state | failures: new_failures}}
    end
  end
  
  defp perform_health_check do
    case DSPex.PythonBridge.Bridge.call(:ping, %{}, 5_000) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, response} -> {:error, "unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # 30 seconds
  end
end
```

### ENHANCED PYTHON BRIDGE WITH HEALTH CHECKS

**Extended Python Script Features:**
```python
def handle_command(self, command, args):
    handlers = {
        'create_program': self.create_program,
        'execute_program': self.execute_program,
        'list_programs': self.list_programs,
        'ping': self.ping,
        'get_stats': self.get_stats,
        'cleanup': self.cleanup
    }
    
    if command not in handlers:
        raise ValueError(f"Unknown command: {command}")
        
    return handlers[command](args)

def ping(self, args):
    return {"status": "ok", "timestamp": time.time()}

def get_stats(self, args):
    return {
        "programs_count": len(self.programs),
        "memory_usage": self.get_memory_usage(),
        "uptime": time.time() - self.start_time
    }

def cleanup(self, args):
    # Clean up resources
    self.programs.clear()
    return {"status": "cleaned"}

def get_memory_usage(self):
    import psutil
    process = psutil.Process()
    return {
        "rss": process.memory_info().rss,
        "vms": process.memory_info().vms
    }
```

### COMPREHENSIVE TESTING PATTERNS

**Bridge Communication Tests:**
```elixir
defmodule DSPex.PythonBridge.BridgeTest do
  use ExUnit.Case
  
  setup do
    # Ensure bridge is running
    {:ok, _} = DSPex.PythonBridge.Bridge.start_link()
    :ok
  end
  
  test "basic ping communication" do
    {:ok, response} = DSPex.PythonBridge.Bridge.call(:ping, %{})
    assert response["status"] == "ok"
    assert is_number(response["timestamp"])
  end
  
  test "program creation and execution" do
    # Create program
    {:ok, create_response} = DSPex.PythonBridge.Bridge.call(:create_program, %{
      id: "test_program",
      signature: %{
        inputs: [%{name: "question", type: "str"}],
        outputs: [%{name: "answer", type: "str"}]
      }
    })
    
    assert create_response["program_id"] == "test_program"
    assert create_response["status"] == "created"
    
    # Execute program
    {:ok, exec_response} = DSPex.PythonBridge.Bridge.call(:execute_program, %{
      program_id: "test_program",
      inputs: %{question: "What is 2+2?"}
    })
    
    assert Map.has_key?(exec_response, "answer")
  end
  
  test "error handling for unknown program" do
    {:error, error_msg} = DSPex.PythonBridge.Bridge.call(:execute_program, %{
      program_id: "nonexistent",
      inputs: %{question: "test"}
    })
    
    assert error_msg =~ "Program not found"
  end
  
  test "timeout handling" do
    # Test with very short timeout
    result = DSPex.PythonBridge.Bridge.call(:ping, %{}, 1)
    
    case result do
      {:ok, _} -> :ok  # Fast response
      {:error, :timeout} -> :ok  # Expected timeout
    end
  end
  
  test "concurrent requests" do
    tasks = for i <- 1..10 do
      Task.async(fn ->
        DSPex.PythonBridge.Bridge.call(:ping, %{request_id: i})
      end)
    end
    
    results = Task.await_many(tasks, 5000)
    
    assert length(results) == 10
    assert Enum.all?(results, fn {:ok, response} -> 
      response["status"] == "ok" 
    end)
  end
end
```

### PERFORMANCE OPTIMIZATION

**Connection Pooling:**
```elixir
defmodule DSPex.PythonBridge.Pool do
  @moduledoc """
  Connection pool for Python bridge instances.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def checkout do
    GenServer.call(__MODULE__, :checkout)
  end
  
  def checkin(bridge_pid) do
    GenServer.cast(__MODULE__, {:checkin, bridge_pid})
  end
  
  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    
    bridges = for _ <- 1..pool_size do
      {:ok, pid} = DSPex.PythonBridge.Bridge.start_link()
      pid
    end
    
    {:ok, %{available: bridges, checked_out: []}}
  end
  
  @impl true
  def handle_call(:checkout, _from, %{available: []} = state) do
    {:reply, {:error, :pool_exhausted}, state}
  end
  
  def handle_call(:checkout, _from, %{available: [bridge | rest]} = state) do
    new_state = %{
      state | 
      available: rest, 
      checked_out: [bridge | state.checked_out]
    }
    {:reply, {:ok, bridge}, new_state}
  end
  
  @impl true
  def handle_cast({:checkin, bridge}, state) do
    new_state = %{
      state |
      available: [bridge | state.available],
      checked_out: List.delete(state.checked_out, bridge)
    }
    {:noreply, new_state}
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the Python bridge communication layer with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/python_bridge/
├── bridge.ex             # Main GenServer implementation
├── protocol.ex           # Wire protocol handling
├── monitor.ex            # Health monitoring
├── environment_check.ex  # Environment validation
└── supervisor.ex         # Bridge supervision

priv/python/
└── dspy_bridge.py        # Python bridge script

test/dspex/python_bridge/
├── bridge_test.exs       # Bridge communication tests
├── protocol_test.exs     # Protocol encoding/decoding tests
└── integration_test.exs  # End-to-end integration tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Bridge GenServer (`lib/dspex/python_bridge/bridge.ex`)**:
   - Complete GenServer implementation with proper state management
   - Python subprocess lifecycle management
   - Request/response correlation with unique IDs
   - Timeout handling and error recovery
   - Graceful shutdown and cleanup

2. **Wire Protocol (`lib/dspex/python_bridge/protocol.ex`)**:
   - JSON encoding/decoding for requests and responses
   - Packet framing with 4-byte length headers
   - Error message standardization
   - Request ID management and correlation

3. **Health Monitoring (`lib/dspex/python_bridge/monitor.ex`)**:
   - Periodic health checks with ping operations
   - Failure tracking and automatic restart triggers
   - Performance metrics collection
   - Bridge availability monitoring

4. **Environment Validation (`lib/dspex/python_bridge/environment_check.ex`)**:
   - Python executable detection and validation
   - DSPy package installation verification
   - Script file existence and permissions check
   - Environment configuration validation

5. **Python Bridge Script (`priv/python/dspy_bridge.py`)**:
   - Complete Python implementation with DSPy integration
   - Command handler architecture
   - Dynamic signature creation from Elixir definitions
   - Program lifecycle management
   - Error handling and logging

### QUALITY REQUIREMENTS:

- **Reliability**: Handle process failures gracefully with automatic recovery
- **Performance**: Efficient request/response handling with minimal latency
- **Monitoring**: Comprehensive health checks and metrics collection
- **Error Handling**: Clear error messages and proper error propagation
- **Testing**: Complete test coverage for all communication scenarios
- **Documentation**: Detailed documentation for all public APIs
- **Configuration**: Flexible configuration for different environments

### INTEGRATION POINTS:

- Must integrate with application supervision tree
- Should support configuration through application environment
- Must provide clean API for adapter layer consumption
- Should support metrics collection and monitoring
- Must handle concurrent requests efficiently

### SUCCESS CRITERIA:

1. Python subprocess starts reliably and maintains communication
2. Request/response correlation works correctly under load
3. Error handling provides meaningful feedback
4. Health monitoring detects and recovers from failures
5. Environment validation catches configuration issues early
6. All test scenarios pass with high reliability
7. Performance meets requirements for ML workloads
8. Integration with supervision tree works correctly

This Python bridge forms the critical communication layer between Elixir and Python DSPy processes, enabling the entire DSPy-Ash integration to function reliably.
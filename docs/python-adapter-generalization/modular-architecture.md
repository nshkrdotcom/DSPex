# Modular Architecture Design

## Overview

This document presents the detailed design for a modular Python bridge architecture that supports multiple ML frameworks while leveraging DSPex's robust infrastructure.

## Architecture Principles

1. **Separation of Concerns**: Clear boundaries between communication, framework logic, and business operations
2. **Open/Closed Principle**: Open for extension (new frameworks), closed for modification (core infrastructure)
3. **Framework Agnosticism**: Core components make no assumptions about specific ML frameworks
4. **Backward Compatibility**: Existing DSPy integration continues to work unchanged
5. **Performance First**: No degradation from current implementation

## Component Architecture

### Layer 1: Communication Infrastructure (Generic)

```
┌─────────────────────────────────────────────────────────────┐
│                    Communication Layer                       │
├─────────────────────────┬───────────────────────────────────┤
│   Protocol (JSON/MP)    │        Port Management           │
├─────────────────────────┼───────────────────────────────────┤
│   Message Framing       │        Process Lifecycle         │
├─────────────────────────┴───────────────────────────────────┤
│                    Error Handling                            │
└─────────────────────────────────────────────────────────────┘
```

### Layer 2: Bridge Infrastructure (Generic)

```
┌─────────────────────────────────────────────────────────────┐
│                    Python Side                               │
├─────────────────────────┬───────────────────────────────────┤
│      BaseBridge         │         Command Router           │
├─────────────────────────┼───────────────────────────────────┤
│   Health Monitoring     │        Stats Collection          │
└─────────────────────────┴───────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Elixir Side                               │
├─────────────────────────┬───────────────────────────────────┤
│     BaseMLAdapter       │        Bridge Registry           │
├─────────────────────────┼───────────────────────────────────┤
│    Pool Integration     │      Session Management          │
└─────────────────────────┴───────────────────────────────────┘
```

### Layer 3: Framework Integration (Specific)

```
┌─────────────┬─────────────┬─────────────┬─────────────────┐
│    DSPy     │  LangChain  │ Transformers│     Custom      │
├─────────────┼─────────────┼─────────────┼─────────────────┤
│  Signatures │   Chains    │   Models    │  User-defined   │
│  Programs   │   Agents    │  Pipelines  │   Resources     │
│  LM Config  │   Tools     │  Tokenizers │   Operations    │
└─────────────┴─────────────┴─────────────┴─────────────────┘
```

## Detailed Component Design

### 1. Python Base Bridge

```python
from abc import ABC, abstractmethod
import json
import struct
import sys
import uuid
from datetime import datetime
from typing import Dict, Any, Optional, Callable

class BaseBridge(ABC):
    """Base class for all Python ML framework bridges"""
    
    def __init__(self, mode: str = "standalone", worker_id: Optional[str] = None):
        self.mode = mode
        self.worker_id = worker_id or str(uuid.uuid4())
        self.stats = {
            'requests_processed': 0,
            'errors': 0,
            'start_time': datetime.utcnow().isoformat()
        }
        self._handlers: Dict[str, Callable] = self._register_handlers()
        self._initialize_framework()
    
    @abstractmethod
    def _initialize_framework(self) -> None:
        """Initialize the specific ML framework"""
        pass
    
    @abstractmethod
    def _register_handlers(self) -> Dict[str, Callable]:
        """Register command handlers specific to the framework"""
        # Must include at minimum:
        # - ping
        # - get_info
        # - get_stats
        # - cleanup
        pass
    
    @abstractmethod
    def get_framework_info(self) -> Dict[str, Any]:
        """Return framework name, version, and capabilities"""
        pass
    
    def run(self) -> None:
        """Main event loop for bridge communication"""
        while True:
            try:
                # Read length header (4 bytes, big-endian)
                length_bytes = sys.stdin.buffer.read(4)
                if not length_bytes:
                    break
                    
                length = struct.unpack('>I', length_bytes)[0]
                
                # Read message
                message_bytes = sys.stdin.buffer.read(length)
                message = json.loads(message_bytes.decode('utf-8'))
                
                # Process request
                response = self._handle_request(message)
                
                # Send response
                self._send_response(response)
                
            except Exception as e:
                error_response = {
                    'id': 0,
                    'success': False,
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                }
                self._send_response(error_response)
    
    def _handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Route request to appropriate handler"""
        request_id = request.get('id', 0)
        command = request.get('command', '')
        args = request.get('args', {})
        
        self.stats['requests_processed'] += 1
        
        try:
            # Check for namespaced commands
            if ':' in command:
                namespace, cmd = command.split(':', 1)
                if namespace != 'common' and namespace != self.get_framework_info()['name']:
                    raise ValueError(f"Unknown namespace: {namespace}")
                command = cmd
            
            if command not in self._handlers:
                raise ValueError(f"Unknown command: {command}")
            
            result = self._handlers[command](args)
            
            return {
                'id': request_id,
                'success': True,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            self.stats['errors'] += 1
            return {
                'id': request_id,
                'success': False,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    def _send_response(self, response: Dict[str, Any]) -> None:
        """Send response back to Elixir"""
        response_bytes = json.dumps(response).encode('utf-8')
        length = len(response_bytes)
        
        # Write length header
        sys.stdout.buffer.write(struct.pack('>I', length))
        # Write message
        sys.stdout.buffer.write(response_bytes)
        sys.stdout.buffer.flush()
    
    # Common handlers that all bridges must implement
    def ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Health check"""
        return {'status': 'ok', 'worker_id': self.worker_id}
    
    def get_stats(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Return bridge statistics"""
        return self.stats
    
    def get_info(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Return framework information"""
        return self.get_framework_info()
    
    def cleanup(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Cleanup resources before shutdown"""
        return {'status': 'cleaned'}
```

### 2. Elixir Base Adapter

```elixir
defmodule DSPex.Adapters.BaseMLAdapter do
  @moduledoc """
  Base behaviour for ML framework adapters.
  Provides common functionality that all adapters can use.
  """
  
  @type adapter_config :: %{
    bridge_module: module(),
    python_script: String.t(),
    pool_size: pos_integer(),
    overflow: non_neg_integer(),
    required_env: [String.t()],
    options: keyword()
  }
  
  @callback get_framework_info() :: {:ok, map()} | {:error, term()}
  @callback validate_environment() :: :ok | {:error, String.t()}
  @callback initialize(keyword()) :: {:ok, map()} | {:error, term()}
  
  defmacro __using__(opts) do
    quote do
      @behaviour DSPex.Adapters.BaseMLAdapter
      
      # Import common functionality
      import DSPex.Adapters.BaseMLAdapter
      
      # Default implementations
      def create_resource(type, config, options \\ []) do
        call_bridge("create_#{type}", config, options)
      end
      
      def execute_resource(resource_id, inputs, options \\ []) do
        call_bridge("execute_resource", %{
          resource_id: resource_id,
          inputs: inputs
        }, options)
      end
      
      def list_resources(type, options \\ []) do
        call_bridge("list_#{type}s", %{}, options)
      end
      
      def delete_resource(resource_id, options \\ []) do
        call_bridge("delete_resource", %{resource_id: resource_id}, options)
      end
      
      def get_stats(options \\ []) do
        call_bridge("get_stats", %{}, options)
      end
      
      # Pool integration
      defp call_bridge(command, args, options) do
        adapter_config = get_adapter_config()
        
        case Keyword.get(options, :session_id) do
          nil ->
            # Anonymous execution
            adapter_config.bridge_module.execute_anonymous(
              command,
              args,
              options
            )
            
          session_id ->
            # Session-based execution
            adapter_config.bridge_module.execute_in_session(
              session_id,
              command,
              args,
              options
            )
        end
      end
      
      defp get_adapter_config do
        Application.get_env(:dspex, __MODULE__)
      end
      
      # Allow adapters to override
      defoverridable [
        create_resource: 3,
        execute_resource: 3,
        list_resources: 2,
        delete_resource: 2
      ]
    end
  end
  
  @doc """
  Validates that required environment variables are set
  """
  def validate_environment(required_env) do
    missing = Enum.filter(required_env, fn var ->
      System.get_env(var) == nil
    end)
    
    case missing do
      [] -> :ok
      vars -> {:error, "Missing environment variables: #{Enum.join(vars, ", ")}"}
    end
  end
  
  @doc """
  Creates a pool for the adapter using the provided configuration
  """
  def create_pool(adapter_module, config) do
    pool_config = [
      name: Module.concat(adapter_module, Pool),
      worker_module: DSPex.PythonBridge.PoolWorkerV2,
      size: config.pool_size,
      max_overflow: config.overflow,
      python_script: config.python_script
    ]
    
    DSPex.PythonBridge.SessionPoolV2.start_link(pool_config)
  end
end
```

### 3. Bridge Registry

```elixir
defmodule DSPex.MLBridgeRegistry do
  @moduledoc """
  Registry for available ML framework bridges
  """
  
  use GenServer
  
  @type bridge_name :: atom()
  @type bridge_config :: map()
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register a new ML bridge
  """
  def register_bridge(name, config) do
    GenServer.call(__MODULE__, {:register, name, config})
  end
  
  @doc """
  Get bridge configuration
  """
  def get_bridge(name) do
    GenServer.call(__MODULE__, {:get, name})
  end
  
  @doc """
  List all available bridges
  """
  def list_bridges do
    GenServer.call(__MODULE__, :list)
  end
  
  @doc """
  Get the default bridge
  """
  def get_default_bridge do
    GenServer.call(__MODULE__, :get_default)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    bridges = load_configured_bridges()
    default = Application.get_env(:dspex, :ml_bridges)[:default] || :dspy
    
    state = %{
      bridges: bridges,
      default: default
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, name, config}, _from, state) do
    # Validate bridge configuration
    case validate_bridge_config(config) do
      :ok ->
        bridges = Map.put(state.bridges, name, config)
        {:reply, :ok, %{state | bridges: bridges}}
        
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:get, name}, _from, state) do
    case Map.get(state.bridges, name) do
      nil -> {:reply, {:error, :not_found}, state}
      config -> {:reply, {:ok, config}, state}
    end
  end
  
  @impl true
  def handle_call(:list, _from, state) do
    bridges = Map.keys(state.bridges)
    {:reply, {:ok, bridges}, state}
  end
  
  @impl true
  def handle_call(:get_default, _from, state) do
    case Map.get(state.bridges, state.default) do
      nil -> {:reply, {:error, :no_default}, state}
      config -> {:reply, {:ok, state.default, config}, state}
    end
  end
  
  # Private functions
  
  defp load_configured_bridges do
    config = Application.get_env(:dspex, :ml_bridges, %{})
    
    config
    |> Map.get(:bridges, [])
    |> Enum.into(%{})
  end
  
  defp validate_bridge_config(config) do
    required_keys = [:adapter, :python_script]
    
    missing = required_keys -- Map.keys(config)
    
    case missing do
      [] -> validate_adapter_module(config.adapter)
      keys -> {:error, "Missing required keys: #{inspect(keys)}"}
    end
  end
  
  defp validate_adapter_module(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, "Adapter module not found: #{inspect(module)}"}
    end
  end
end
```

### 4. Unified ML Bridge Interface

```elixir
defmodule DSPex.MLBridge do
  @moduledoc """
  Unified interface for accessing different ML framework bridges
  """
  
  @doc """
  Get an adapter for a specific framework
  """
  def get_adapter(framework) do
    with {:ok, config} <- DSPex.MLBridgeRegistry.get_bridge(framework),
         {:ok, _} <- ensure_adapter_started(framework, config) do
      {:ok, config.adapter}
    end
  end
  
  @doc """
  Get the default adapter
  """
  def get_default_adapter do
    with {:ok, framework, config} <- DSPex.MLBridgeRegistry.get_default_bridge(),
         {:ok, _} <- ensure_adapter_started(framework, config) do
      {:ok, config.adapter}
    end
  end
  
  @doc """
  Execute a command on a specific framework
  """
  def execute(framework, command, args, options \\ []) do
    with {:ok, adapter} <- get_adapter(framework) do
      apply(adapter, :call_bridge, [command, args, options])
    end
  end
  
  @doc """
  Create a resource using the specified framework
  """
  def create_resource(framework, type, config, options \\ []) do
    with {:ok, adapter} <- get_adapter(framework) do
      apply(adapter, :create_resource, [type, config, options])
    end
  end
  
  @doc """
  Execute a resource
  """
  def execute_resource(framework, resource_id, inputs, options \\ []) do
    with {:ok, adapter} <- get_adapter(framework) do
      apply(adapter, :execute_resource, [resource_id, inputs, options])
    end
  end
  
  @doc """
  List available frameworks
  """
  def list_frameworks do
    DSPex.MLBridgeRegistry.list_bridges()
  end
  
  @doc """
  Get information about a framework
  """
  def get_framework_info(framework) do
    with {:ok, adapter} <- get_adapter(framework) do
      apply(adapter, :get_framework_info, [])
    end
  end
  
  # Private functions
  
  defp ensure_adapter_started(framework, config) do
    # Check if the adapter's pool is already started
    pool_name = Module.concat(config.adapter, Pool)
    
    case Process.whereis(pool_name) do
      nil ->
        # Start the adapter's pool
        DSPex.Adapters.BaseMLAdapter.create_pool(config.adapter, config)
        
      pid ->
        {:ok, pid}
    end
  end
end
```

## Configuration System

### Application Configuration

```elixir
# config/config.exs
config :dspex, :ml_bridges,
  default: :dspy,
  bridges: [
    dspy: %{
      adapter: DSPex.Adapters.DSPyAdapter,
      python_module: "dspy_bridge",
      python_script: "priv/python/dspy_bridge.py",
      pool_size: 4,
      overflow: 2,
      required_env: ["GEMINI_API_KEY"],
      required_packages: ["dspy-ai", "google-generativeai"],
      options: [
        timeout: 30_000,
        health_check_interval: 30_000
      ]
    },
    
    langchain: %{
      adapter: DSPex.Adapters.LangChainAdapter,
      python_module: "langchain_bridge",
      python_script: "priv/python/langchain_bridge.py",
      pool_size: 2,
      overflow: 1,
      required_env: ["OPENAI_API_KEY"],
      required_packages: ["langchain", "openai"],
      options: [
        timeout: 60_000,  # LangChain operations can be slower
        streaming_enabled: true
      ]
    },
    
    transformers: %{
      adapter: DSPex.Adapters.TransformersAdapter,
      python_module: "transformers_bridge",
      python_script: "priv/python/transformers_bridge.py",
      pool_size: 1,  # Models are memory-intensive
      overflow: 0,
      required_env: [],
      required_packages: ["transformers", "torch"],
      options: [
        timeout: 120_000,  # Model loading can be slow
        gpu_enabled: true,
        model_cache_dir: "/tmp/transformers_cache"
      ]
    }
  ]

# Per-environment overrides
config :dspex, DSPex.Adapters.DSPyAdapter,
  default_model: "gemini-1.5-flash",
  temperature: 0.7

config :dspex, DSPex.Adapters.LangChainAdapter,
  default_model: "gpt-4",
  temperature: 0.7,
  max_retries: 3
```

### Runtime Configuration

```elixir
# Start a specific bridge with custom config
{:ok, _} = DSPex.MLBridge.start_bridge(:custom,
  adapter: MyApp.CustomAdapter,
  python_script: "priv/python/custom_bridge.py",
  pool_size: 2
)

# Update bridge configuration
DSPex.MLBridge.update_config(:langchain,
  pool_size: 4,
  timeout: 90_000
)
```

## Error Handling Strategy

### Framework-Specific Errors

```elixir
defmodule DSPex.MLBridge.ErrorTranslator do
  @moduledoc """
  Translates framework-specific errors to common error types
  """
  
  def translate_error(:dspy, error) do
    case error do
      %{"error" => "InvalidSignature" <> _} ->
        {:error, :invalid_configuration}
        
      %{"error" => "LMError" <> _} ->
        {:error, :model_error}
        
      _ ->
        {:error, :unknown}
    end
  end
  
  def translate_error(:langchain, error) do
    case error do
      %{"error" => "InvalidChain" <> _} ->
        {:error, :invalid_configuration}
        
      %{"error" => "RateLimitError" <> _} ->
        {:error, :rate_limit}
        
      _ ->
        {:error, :unknown}
    end
  end
  
  def translate_error(_, error) do
    {:error, error}
  end
end
```

## Performance Considerations

### 1. Pool Isolation
Each framework gets its own pool to prevent interference:
- DSPy: 4 workers for high concurrency
- LangChain: 2 workers for moderate load
- Transformers: 1 worker due to memory constraints

### 2. Resource Management
- Lazy loading of Python frameworks
- Framework-specific cleanup handlers
- Memory monitoring per framework

### 3. Caching Strategy
- Framework-level caching (models, tokenizers)
- Session-based state caching
- Configurable cache TTL

## Security Considerations

### 1. Sandbox Options
```python
# Optional sandboxing for untrusted code
class SandboxedBridge(BaseBridge):
    def __init__(self, *args, **kwargs):
        # Use RestrictedPython or similar
        self.sandbox = RestrictedPython()
        super().__init__(*args, **kwargs)
```

### 2. Resource Limits
```elixir
# Configure per-framework resource limits
config :dspex, :ml_bridges,
  resource_limits: [
    dspy: %{
      max_memory: "2GB",
      max_cpu: "100%",
      timeout: 30_000
    },
    transformers: %{
      max_memory: "8GB",
      max_cpu: "200%",  # Multi-core
      timeout: 120_000
    }
  ]
```

## Monitoring and Telemetry

### Framework-Specific Metrics

```elixir
# Telemetry events per framework
:telemetry.execute(
  [:dspex, :ml_bridge, :request],
  %{duration: duration},
  %{
    framework: :langchain,
    command: "create_chain",
    success: true
  }
)

# Framework health metrics
:telemetry.execute(
  [:dspex, :ml_bridge, :health],
  %{
    memory_usage: memory,
    active_resources: count
  },
  %{framework: :transformers}
)
```

## Testing Strategy

### 1. Framework Mocks
```elixir
defmodule DSPex.Test.MockBridge do
  use DSPex.Adapters.BaseMLAdapter
  
  def get_framework_info do
    {:ok, %{
      name: "mock",
      version: "1.0.0",
      capabilities: ["test"]
    }}
  end
end
```

### 2. Integration Tests
```elixir
defmodule MLBridgeIntegrationTest do
  use ExUnit.Case
  
  @tag :integration
  test "multiple frameworks can coexist" do
    # Start multiple bridges
    {:ok, _} = DSPex.MLBridge.get_adapter(:dspy)
    {:ok, _} = DSPex.MLBridge.get_adapter(:langchain)
    
    # Execute on different frameworks
    {:ok, result1} = DSPex.MLBridge.execute(:dspy, "ping", %{})
    {:ok, result2} = DSPex.MLBridge.execute(:langchain, "ping", %{})
    
    assert result1["framework"] == "dspy"
    assert result2["framework"] == "langchain"
  end
end
```

This modular architecture provides a clean separation between generic infrastructure and framework-specific logic, enabling easy integration of new ML frameworks while maintaining the robustness of the current implementation.
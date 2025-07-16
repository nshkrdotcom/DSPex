# Modular Python Bridge Architecture for DSPex

## Overview

This document outlines a modular architecture that allows developers to create custom Python bridges for any ML framework (LangChain, Transformers, custom frameworks) while reusing DSPex's robust core infrastructure for process management, pooling, error handling, and communication.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│        (Your Elixir code using ML capabilities)              │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Adapter Layer (Elixir)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐     │
│  │ DSPy        │  │ LangChain   │  │ Custom ML       │     │
│  │ Adapter     │  │ Adapter     │  │ Adapter         │     │
│  └─────────────┘  └─────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              Core Infrastructure (Elixir)                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ SessionPoolV2, Workers, Error Handling, Monitoring    │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Protocol, Port Communication, Process Management      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                    ╔═══════════════════╗
                    ║   JSON Protocol   ║
                    ╚═══════════════════╝
                              │
┌─────────────────────────────────────────────────────────────┐
│                  Bridge Layer (Python)                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              BaseBridge (Abstract Class)              │  │
│  │  - Protocol handling  - Message routing               │  │
│  │  - Error handling     - Health monitoring             │  │
│  └───────────────────────────────────────────────────────┘  │
│                              ▲                               │
│         ┌────────────────────┼────────────────────┐         │
│         │                    │                    │         │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   │
│  │ DSPyBridge   │   │ LangChain    │   │ Custom ML    │   │
│  │              │   │ Bridge       │   │ Bridge       │   │
│  └──────────────┘   └──────────────┘   └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    ML Framework Layer                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐     │
│  │ DSPy        │  │ LangChain   │  │ Transformers   │     │
│  │ Framework   │  │ Framework   │  │ Framework      │     │
│  └─────────────┘  └─────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## 1. Python Side - Pluggable Design

### Base Bridge Class

```python
# priv/python/base_bridge.py
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List
import json
import struct
import sys
import time
import threading
import traceback

class BaseBridge(ABC):
    """
    Abstract base class for all ML framework bridges.
    
    Handles:
    - Protocol communication with Elixir
    - Message routing and error handling
    - Health monitoring and stats
    - Session management for pool workers
    """
    
    def __init__(self, mode="standalone", worker_id=None):
        self.mode = mode
        self.worker_id = worker_id
        self.start_time = time.time()
        self.command_count = 0
        self.error_count = 0
        self.lock = threading.Lock()
        
        # Command handlers registry
        self._handlers = {
            'ping': self._handle_ping,
            'get_stats': self._handle_get_stats,
            'shutdown': self._handle_shutdown,
            'get_capabilities': self._handle_get_capabilities,
        }
        
        # Register framework-specific handlers
        self._register_handlers()
        
        # Initialize framework
        self._initialize_framework()
    
    @abstractmethod
    def _register_handlers(self):
        """Register framework-specific command handlers."""
        pass
    
    @abstractmethod
    def _initialize_framework(self):
        """Initialize the ML framework."""
        pass
    
    @abstractmethod
    def get_framework_info(self) -> Dict[str, Any]:
        """Return framework name, version, and capabilities."""
        pass
    
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Route commands to appropriate handlers."""
        with self.lock:
            self.command_count += 1
            
        if command not in self._handlers:
            self.error_count += 1
            raise ValueError(f"Unknown command: {command}")
        
        try:
            return self._handlers[command](args)
        except Exception as e:
            self.error_count += 1
            raise
    
    def _handle_ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Health check handler."""
        return {
            "status": "ok",
            "timestamp": time.time(),
            "uptime": time.time() - self.start_time,
            "mode": self.mode,
            "worker_id": self.worker_id,
            "framework": self.get_framework_info()
        }
    
    def _handle_get_stats(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Get bridge statistics."""
        return {
            "command_count": self.command_count,
            "error_count": self.error_count,
            "uptime": time.time() - self.start_time,
            "framework": self.get_framework_info()
        }
    
    def _handle_shutdown(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Graceful shutdown."""
        return {
            "status": "shutting_down",
            "worker_id": self.worker_id,
            "mode": self.mode
        }
    
    def _handle_get_capabilities(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Return bridge capabilities."""
        return {
            "framework": self.get_framework_info(),
            "supported_operations": list(self._handlers.keys()),
            "mode": self.mode
        }
    
    def run(self):
        """Main event loop."""
        while True:
            message = self._read_message()
            if message is None:
                break
            
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            try:
                result = self.handle_command(command, args)
                response = {
                    'id': request_id,
                    'success': True,
                    'result': result,
                    'timestamp': time.time()
                }
            except Exception as e:
                response = {
                    'id': request_id,
                    'success': False,
                    'error': str(e),
                    'timestamp': time.time()
                }
            
            self._write_message(response)
    
    def _read_message(self) -> Optional[Dict[str, Any]]:
        """Read length-prefixed JSON message from stdin."""
        try:
            length_bytes = sys.stdin.buffer.read(4)
            if len(length_bytes) < 4:
                return None
            
            length = struct.unpack('>I', length_bytes)[0]
            message_bytes = sys.stdin.buffer.read(length)
            
            if len(message_bytes) < length:
                return None
            
            return json.loads(message_bytes.decode('utf-8'))
        except Exception:
            return None
    
    def _write_message(self, message: Dict[str, Any]):
        """Write length-prefixed JSON message to stdout."""
        message_bytes = json.dumps(message).encode('utf-8')
        length = len(message_bytes)
        
        sys.stdout.buffer.write(struct.pack('>I', length))
        sys.stdout.buffer.write(message_bytes)
        sys.stdout.buffer.flush()
```

### DSPy Bridge Implementation

```python
# priv/python/dspy_bridge.py
from base_bridge import BaseBridge
import dspy

class DSPyBridge(BaseBridge):
    """DSPy-specific bridge implementation."""
    
    def _register_handlers(self):
        """Register DSPy-specific handlers."""
        self._handlers.update({
            'configure_lm': self._handle_configure_lm,
            'create_program': self._handle_create_program,
            'execute_program': self._handle_execute_program,
            'list_programs': self._handle_list_programs,
            'delete_program': self._handle_delete_program,
        })
    
    def _initialize_framework(self):
        """Initialize DSPy framework."""
        self.programs = {}
        self.lm_configured = False
        self.signature_cache = {}
    
    def get_framework_info(self) -> Dict[str, Any]:
        """Return DSPy framework info."""
        return {
            "name": "dspy",
            "version": dspy.__version__ if hasattr(dspy, '__version__') else "unknown",
            "capabilities": ["signatures", "programs", "language_models"]
        }
    
    # ... DSPy-specific implementation methods ...
```

### LangChain Bridge Implementation

```python
# priv/python/langchain_bridge.py
from base_bridge import BaseBridge
from langchain import __version__ as langchain_version
from langchain.llms import OpenAI
from langchain.chains import LLMChain
from langchain.prompts import PromptTemplate

class LangChainBridge(BaseBridge):
    """LangChain-specific bridge implementation."""
    
    def _register_handlers(self):
        """Register LangChain-specific handlers."""
        self._handlers.update({
            'configure_llm': self._handle_configure_llm,
            'create_chain': self._handle_create_chain,
            'run_chain': self._handle_run_chain,
            'create_agent': self._handle_create_agent,
            'run_agent': self._handle_run_agent,
            'list_chains': self._handle_list_chains,
            'delete_chain': self._handle_delete_chain,
        })
    
    def _initialize_framework(self):
        """Initialize LangChain framework."""
        self.chains = {}
        self.agents = {}
        self.llm = None
    
    def get_framework_info(self) -> Dict[str, Any]:
        """Return LangChain framework info."""
        return {
            "name": "langchain",
            "version": langchain_version,
            "capabilities": ["chains", "agents", "prompts", "memory", "tools"]
        }
    
    def _handle_configure_llm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Configure the LLM for LangChain."""
        model_type = args.get('model_type', 'openai')
        model_name = args.get('model_name', 'gpt-3.5-turbo')
        api_key = args.get('api_key')
        temperature = args.get('temperature', 0.7)
        
        if model_type == 'openai':
            self.llm = OpenAI(
                model_name=model_name,
                api_key=api_key,
                temperature=temperature
            )
        # Add more LLM types as needed
        
        return {
            "status": "configured",
            "model_type": model_type,
            "model_name": model_name
        }
    
    def _handle_create_chain(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a LangChain chain."""
        chain_id = args.get('id')
        template = args.get('template')
        input_variables = args.get('input_variables', [])
        
        prompt = PromptTemplate(
            template=template,
            input_variables=input_variables
        )
        
        chain = LLMChain(llm=self.llm, prompt=prompt)
        self.chains[chain_id] = chain
        
        return {
            "chain_id": chain_id,
            "status": "created",
            "input_variables": input_variables
        }
    
    def _handle_run_chain(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a LangChain chain."""
        chain_id = args.get('chain_id')
        inputs = args.get('inputs', {})
        
        if chain_id not in self.chains:
            raise ValueError(f"Chain not found: {chain_id}")
        
        chain = self.chains[chain_id]
        result = chain.run(**inputs)
        
        return {
            "chain_id": chain_id,
            "result": result,
            "execution_time": time.time()
        }
```

### Custom ML Bridge Template

```python
# priv/python/custom_ml_bridge_template.py
from base_bridge import BaseBridge
from typing import Dict, Any

class CustomMLBridge(BaseBridge):
    """Template for custom ML framework bridges."""
    
    def _register_handlers(self):
        """Register custom ML framework handlers."""
        self._handlers.update({
            'load_model': self._handle_load_model,
            'predict': self._handle_predict,
            'train': self._handle_train,
            'evaluate': self._handle_evaluate,
        })
    
    def _initialize_framework(self):
        """Initialize custom ML framework."""
        self.models = {}
        self.datasets = {}
    
    def get_framework_info(self) -> Dict[str, Any]:
        """Return custom framework info."""
        return {
            "name": "custom_ml",
            "version": "1.0.0",
            "capabilities": ["models", "training", "prediction", "evaluation"]
        }
    
    def _handle_load_model(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Load a model from file or create new."""
        # Implementation specific to your ML framework
        pass
    
    def _handle_predict(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Make predictions with a loaded model."""
        # Implementation specific to your ML framework
        pass
```

## 2. Elixir Side - Framework-Agnostic Design

### Base Adapter Behaviour

```elixir
# lib/dspex/adapters/base_ml_adapter.ex
defmodule DSPex.Adapters.BaseMLAdapter do
  @moduledoc """
  Base behaviour for ML framework adapters.
  
  Provides common functionality for all ML adapters including:
  - Bridge communication
  - Session management
  - Error handling
  - Pool integration
  """
  
  @callback framework_name() :: String.t()
  @callback supported_operations() :: [atom()]
  @callback validate_config(map()) :: :ok | {:error, term()}
  @callback transform_request(operation :: atom(), args :: map()) :: map()
  @callback transform_response(operation :: atom(), response :: map()) :: {:ok, any()} | {:error, term()}
  
  defmacro __using__(opts) do
    quote do
      @behaviour DSPex.Adapters.BaseMLAdapter
      @behaviour DSPex.Adapters.Adapter
      
      alias DSPex.PythonBridge.SessionPoolV2
      alias DSPex.PythonBridge.PoolErrorHandler
      
      require Logger
      
      @framework_name unquote(opts[:framework]) || "unknown"
      @default_session "anonymous"
      
      ## Common Implementation
      
      def framework_name, do: @framework_name
      
      def execute_operation(operation, args, options \\ %{}) do
        session_id = get_session_id(options)
        pool_opts = get_pool_opts(options)
        
        # Transform request for specific framework
        request = transform_request(operation, args)
        
        case SessionPoolV2.execute_in_session(session_id, operation, request, pool_opts) do
          {:ok, response} ->
            transform_response(operation, response)
          
          {:error, reason} ->
            handle_pool_error(reason)
        end
      end
      
      defp get_session_id(options) do
        Map.get(options, :session_id, @default_session)
      end
      
      defp get_pool_opts(options) do
        options
        |> Map.take([:timeout, :checkout_timeout, :max_retries])
        |> Map.put_new(:timeout, 30_000)
      end
      
      defp handle_pool_error(reason) do
        case PoolErrorHandler.handle_error(reason, %{adapter: @framework_name}) do
          {:retry, _} -> {:error, {:temporary, reason}}
          {:abandon, _} -> {:error, {:permanent, reason}}
          _ -> {:error, reason}
        end
      end
      
      ## Test Support
      
      @impl DSPex.Adapters.Adapter
      def supports_test_layer?(layer), do: layer in [:layer_2, :layer_3]
      
      @impl DSPex.Adapters.Adapter
      def get_test_capabilities do
        %{
          deterministic_outputs: false,
          python_execution: true,
          performance: :medium,
          framework: @framework_name
        }
      end
      
      defoverridable [
        framework_name: 0,
        supports_test_layer?: 1,
        get_test_capabilities: 0
      ]
    end
  end
end
```

### DSPy Adapter Using Base

```elixir
# lib/dspex/adapters/dspy_adapter.ex
defmodule DSPex.Adapters.DSPyAdapter do
  use DSPex.Adapters.BaseMLAdapter, framework: "dspy"
  
  @impl true
  def supported_operations do
    [:configure_lm, :create_program, :execute_program, :list_programs, :delete_program]
  end
  
  @impl true
  def validate_config(config) do
    # DSPy-specific validation
    :ok
  end
  
  @impl true
  def transform_request(:create_program, args) do
    %{
      id: args[:id] || generate_id(),
      signature: transform_signature(args[:signature]),
      program_type: args[:type] || "predict"
    }
  end
  
  @impl true
  def transform_request(operation, args), do: args
  
  @impl true
  def transform_response(:create_program, %{"program_id" => id}) do
    {:ok, id}
  end
  
  @impl true
  def transform_response(:execute_program, %{"outputs" => outputs}) do
    {:ok, outputs}
  end
  
  @impl true
  def transform_response(_operation, response), do: {:ok, response}
  
  # DSPy Adapter Interface (implements Adapter behaviour)
  
  @impl DSPex.Adapters.Adapter
  def create_program(config) do
    execute_operation(:create_program, config)
  end
  
  @impl DSPex.Adapters.Adapter
  def execute_program(program_id, inputs, options \\ %{}) do
    args = %{program_id: program_id, inputs: inputs}
    execute_operation(:execute_program, args, options)
  end
  
  # ... other Adapter callbacks ...
end
```

### LangChain Adapter

```elixir
# lib/dspex/adapters/langchain_adapter.ex
defmodule DSPex.Adapters.LangChainAdapter do
  use DSPex.Adapters.BaseMLAdapter, framework: "langchain"
  
  @impl true
  def supported_operations do
    [:configure_llm, :create_chain, :run_chain, :create_agent, :run_agent, :list_chains]
  end
  
  @impl true
  def validate_config(config) do
    cond do
      not Map.has_key?(config, :model_type) ->
        {:error, "model_type is required"}
      
      not Map.has_key?(config, :api_key) ->
        {:error, "api_key is required"}
      
      true ->
        :ok
    end
  end
  
  @impl true
  def transform_request(:create_chain, args) do
    %{
      id: args[:id] || generate_id(),
      template: args[:prompt_template],
      input_variables: extract_variables(args[:prompt_template])
    }
  end
  
  @impl true
  def transform_request(:run_chain, args) do
    %{
      chain_id: args[:chain_id],
      inputs: args[:inputs]
    }
  end
  
  @impl true
  def transform_response(:run_chain, %{"result" => result}) do
    {:ok, %{output: result}}
  end
  
  # LangChain-specific public interface
  
  def configure_llm(config) do
    execute_operation(:configure_llm, config)
  end
  
  def create_chain(template, options \\ %{}) do
    args = %{prompt_template: template}
    execute_operation(:create_chain, args, options)
  end
  
  def run_chain(chain_id, inputs, options \\ %{}) do
    args = %{chain_id: chain_id, inputs: inputs}
    execute_operation(:run_chain, args, options)
  end
end
```

## 3. Configuration System

### Bridge Configuration

```elixir
# config/config.exs
config :dspex, :ml_bridges,
  default: :dspy,
  bridges: [
    dspy: %{
      adapter: DSPex.Adapters.DSPyAdapter,
      python_module: "dspy_bridge",
      python_class: "DSPyBridge",
      script_path: "priv/python/dspy_bridge.py",
      required_packages: ["dspy-ai"],
      min_python_version: "3.8.0"
    },
    langchain: %{
      adapter: DSPex.Adapters.LangChainAdapter,
      python_module: "langchain_bridge",
      python_class: "LangChainBridge", 
      script_path: "priv/python/langchain_bridge.py",
      required_packages: ["langchain", "openai"],
      min_python_version: "3.8.0"
    },
    custom_ml: %{
      adapter: MyApp.CustomMLAdapter,
      python_module: "custom_ml_bridge",
      python_class: "CustomMLBridge",
      script_path: "priv/python/custom_ml_bridge.py",
      required_packages: ["numpy", "scikit-learn"],
      min_python_version: "3.9.0"
    }
  ]

# Per-bridge pool configuration
config :dspex, DSPex.Adapters.DSPyAdapter,
  pool_size: 4,
  overflow: 2,
  checkout_timeout: 5_000

config :dspex, DSPex.Adapters.LangChainAdapter,
  pool_size: 2,
  overflow: 1,
  checkout_timeout: 10_000
```

### Bridge Registry

```elixir
# lib/dspex/ml_bridge_registry.ex
defmodule DSPex.MLBridgeRegistry do
  @moduledoc """
  Registry for ML framework bridges.
  
  Manages available bridges and their configurations.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    bridges = load_bridge_configs()
    {:ok, %{bridges: bridges, active_pools: %{}}}
  end
  
  def get_adapter(bridge_name) do
    GenServer.call(__MODULE__, {:get_adapter, bridge_name})
  end
  
  def list_bridges do
    GenServer.call(__MODULE__, :list_bridges)
  end
  
  def validate_bridge(bridge_name) do
    GenServer.call(__MODULE__, {:validate_bridge, bridge_name})
  end
  
  @impl true
  def handle_call({:get_adapter, bridge_name}, _from, state) do
    case get_in(state.bridges, [bridge_name, :adapter]) do
      nil -> {:reply, {:error, :not_found}, state}
      adapter -> {:reply, {:ok, adapter}, state}
    end
  end
  
  @impl true
  def handle_call(:list_bridges, _from, state) do
    bridges = Map.keys(state.bridges)
    {:reply, bridges, state}
  end
  
  @impl true
  def handle_call({:validate_bridge, bridge_name}, _from, state) do
    with {:ok, config} <- Map.fetch(state.bridges, bridge_name),
         :ok <- validate_python_script(config),
         :ok <- validate_python_packages(config),
         :ok <- validate_adapter_module(config) do
      {:reply, :ok, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  defp load_bridge_configs do
    :dspex
    |> Application.get_env(:ml_bridges, %{})
    |> Map.get(:bridges, %{})
  end
  
  defp validate_python_script(%{script_path: path}) do
    if File.exists?(path) do
      :ok
    else
      {:error, {:script_not_found, path}}
    end
  end
  
  defp validate_python_packages(%{required_packages: packages}) do
    # Could check if packages are installed
    :ok
  end
  
  defp validate_adapter_module(%{adapter: module}) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, {:adapter_not_loaded, module}}
    end
  end
end
```

### Dynamic Bridge Selection

```elixir
# lib/dspex/ml_bridge.ex
defmodule DSPex.MLBridge do
  @moduledoc """
  Unified interface for ML bridges.
  
  Automatically routes to the appropriate adapter based on configuration.
  """
  
  def create_program(config, options \\ %{}) do
    bridge = options[:bridge] || get_default_bridge()
    
    with {:ok, adapter} <- DSPex.MLBridgeRegistry.get_adapter(bridge) do
      adapter.create_program(config, options)
    end
  end
  
  def execute(program_or_chain_id, inputs, options \\ %{}) do
    bridge = options[:bridge] || detect_bridge_from_id(program_or_chain_id)
    
    with {:ok, adapter} <- DSPex.MLBridgeRegistry.get_adapter(bridge) do
      adapter.execute_program(program_or_chain_id, inputs, options)
    end
  end
  
  def configure(bridge_name, config) do
    with {:ok, adapter} <- DSPex.MLBridgeRegistry.get_adapter(bridge_name) do
      case adapter.validate_config(config) do
        :ok -> adapter.configure(config)
        error -> error
      end
    end
  end
  
  defp get_default_bridge do
    Application.get_env(:dspex, :ml_bridges)[:default] || :dspy
  end
  
  defp detect_bridge_from_id(id) do
    # Could implement ID prefixing or metadata lookup
    get_default_bridge()
  end
end
```

## 4. Example Implementations

### Using DSPy (Current)

```elixir
# Existing DSPy usage remains unchanged
{:ok, program_id} = DSPex.MLBridge.create_program(%{
  signature: %{
    inputs: [%{name: "question", type: "str"}],
    outputs: [%{name: "answer", type: "str"}]
  }
})

{:ok, result} = DSPex.MLBridge.execute(program_id, %{question: "What is 2+2?"})
```

### Using LangChain

```elixir
# Configure LangChain
:ok = DSPex.MLBridge.configure(:langchain, %{
  model_type: "openai",
  api_key: System.get_env("OPENAI_API_KEY"),
  model_name: "gpt-3.5-turbo"
})

# Create a chain
{:ok, chain_id} = DSPex.MLBridge.create_program(%{
  prompt_template: "Answer this question: {question}",
}, bridge: :langchain)

# Run the chain
{:ok, result} = DSPex.MLBridge.execute(
  chain_id, 
  %{question: "What is the capital of France?"}, 
  bridge: :langchain
)
```

### Using Transformers

```elixir
# Custom Transformers adapter
defmodule MyApp.TransformersAdapter do
  use DSPex.Adapters.BaseMLAdapter, framework: "transformers"
  
  def load_model(model_name, options \\ %{}) do
    execute_operation(:load_model, %{model_name: model_name}, options)
  end
  
  def generate(model_id, prompt, options \\ %{}) do
    args = %{model_id: model_id, prompt: prompt, max_length: options[:max_length] || 100}
    execute_operation(:generate, args, options)
  end
end

# Usage
{:ok, model_id} = MyApp.TransformersAdapter.load_model("gpt2")
{:ok, text} = MyApp.TransformersAdapter.generate(model_id, "Once upon a time")
```

## 5. Migration Path from Current DSPy Implementation

### Phase 1: Refactor Python Side (Non-Breaking)

1. Extract base functionality from `dspy_bridge.py` into `base_bridge.py`
2. Create `DSPyBridge` class that inherits from `BaseBridge`
3. Keep existing command structure for backward compatibility
4. Add bridge type identification to responses

### Phase 2: Add Bridge Registry (Additive)

1. Implement `MLBridgeRegistry` GenServer
2. Add configuration for bridge registry
3. Update `SessionPoolV2` to accept bridge type parameter
4. Default to DSPy bridge for backward compatibility

### Phase 3: Create Unified Interface (Opt-In)

1. Implement `DSPex.MLBridge` module
2. Add bridge detection and routing logic
3. Allow explicit bridge selection in options
4. Maintain existing `DSPex.Adapters.PythonPoolV2` for compatibility

### Phase 4: Migrate Examples and Documentation

1. Update examples to show both old and new usage
2. Create migration guide
3. Add examples for new ML frameworks
4. Document bridge creation process

### Phase 5: Deprecate Old Interface (Long-Term)

1. Mark direct `DSPex.Adapters.PythonPoolV2` usage as deprecated
2. Provide automated migration tools
3. Update all internal usage to new interface
4. Plan removal in major version bump

## Benefits of This Architecture

1. **Extensibility**: Easy to add new ML frameworks without modifying core
2. **Reusability**: All bridges benefit from pooling, error handling, monitoring
3. **Type Safety**: Each adapter can provide framework-specific interfaces
4. **Testing**: Existing 3-layer test architecture works for all bridges
5. **Performance**: Shared pool infrastructure optimizes resource usage
6. **Flexibility**: Can run different ML frameworks in same application
7. **Migration**: Gradual migration path preserves backward compatibility

## Creating Your Own Bridge

### Step 1: Create Python Bridge

```python
# priv/python/my_ml_bridge.py
from base_bridge import BaseBridge

class MyMLBridge(BaseBridge):
    def _register_handlers(self):
        self._handlers.update({
            'my_operation': self._handle_my_operation,
        })
    
    def _initialize_framework(self):
        # Initialize your ML framework
        pass
    
    def get_framework_info(self):
        return {
            "name": "my_ml",
            "version": "1.0.0",
            "capabilities": ["custom_ops"]
        }
    
    def _handle_my_operation(self, args):
        # Implement your operation
        return {"result": "success"}

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', default='standalone')
    parser.add_argument('--worker-id', type=str)
    args = parser.parse_args()
    
    bridge = MyMLBridge(mode=args.mode, worker_id=args.worker_id)
    bridge.run()
```

### Step 2: Create Elixir Adapter

```elixir
# lib/my_app/my_ml_adapter.ex
defmodule MyApp.MyMLAdapter do
  use DSPex.Adapters.BaseMLAdapter, framework: "my_ml"
  
  @impl true
  def supported_operations do
    [:my_operation]
  end
  
  @impl true
  def validate_config(config), do: :ok
  
  @impl true
  def transform_request(:my_operation, args), do: args
  
  @impl true
  def transform_response(:my_operation, response), do: {:ok, response}
  
  # Public API
  def do_my_operation(args, options \\ %{}) do
    execute_operation(:my_operation, args, options)
  end
end
```

### Step 3: Configure Bridge

```elixir
# config/config.exs
config :dspex, :ml_bridges,
  bridges: Map.put(existing_bridges, :my_ml, %{
    adapter: MyApp.MyMLAdapter,
    python_module: "my_ml_bridge",
    python_class: "MyMLBridge",
    script_path: "priv/python/my_ml_bridge.py",
    required_packages: [],
    min_python_version: "3.8.0"
  })
```

### Step 4: Use Your Bridge

```elixir
# In your application
{:ok, result} = MyApp.MyMLAdapter.do_my_operation(%{data: "test"})

# Or through unified interface
{:ok, result} = DSPex.MLBridge.execute_operation(
  :my_operation,
  %{data: "test"},
  bridge: :my_ml
)
```

This modular architecture provides a clean separation of concerns, maximum reusability of the robust infrastructure already built in DSPex, and the flexibility to integrate any Python ML framework while maintaining the performance and reliability benefits of the Elixir supervision tree and pooling system.
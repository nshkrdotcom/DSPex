# Unified gRPC Bridge: Implementation Guide

## Overview

This guide provides a step-by-step implementation path for the unified gRPC bridge that seamlessly integrates both tools and variables. We'll build incrementally, ensuring each phase delivers working functionality.

## Implementation Phases

### Phase 1: Enhanced SessionStore (Week 1)

The foundation is extending the existing SessionStore to manage variables alongside tools.

#### Step 1.1: Extend SessionStore State

```elixir
# lib/dspex/bridge/session_store.ex

defmodule DSPex.Bridge.SessionStore do
  use GenServer
  require Logger
  
  # Extended state to include variables
  defstruct [
    :session_id,
    :tools,              # Existing
    :variables,          # NEW: Map of var_id => Variable struct
    :variable_observers, # NEW: Map of var_id => MapSet of PIDs
    :variable_locks,     # NEW: Map of var_id => optimizer_pid
    :metadata,
    :created_at,
    :last_accessed_at
  ]
  
  # Add to init/1
  def init(session_id) do
    state = %__MODULE__{
      session_id: session_id,
      tools: %{},
      variables: %{},
      variable_observers: %{},
      variable_locks: %{},
      metadata: %{},
      created_at: DateTime.utc_now(),
      last_accessed_at: DateTime.utc_now()
    }
    
    # Set up session monitoring
    :timer.send_interval(@cleanup_interval, :check_session_timeout)
    
    {:ok, state}
  end
```

#### Step 1.2: Implement Variable Registration

```elixir
# Add to session_store.ex

@doc """
Register a variable in the session with type validation.
"""
def register_variable(session_id, name, type, initial_value, opts \\ []) do
  GenServer.call(__MODULE__, {:register_variable, session_id, name, type, initial_value, opts})
end

# Add handler
def handle_call({:register_variable, session_id, name, type, initial_value, opts}, _from, state) do
  with {:ok, session} <- get_session_state(state, session_id),
       {:ok, type_module} <- validate_variable_type(type),
       {:ok, validated_value} <- type_module.validate(initial_value) do
    
    var_id = generate_variable_id(name)
    
    variable = %Variable{
      id: var_id,
      name: name,
      type: type,
      value: validated_value,
      constraints: opts[:constraints] || %{},
      metadata: %{
        created_at: DateTime.utc_now(),
        source: :elixir,
        description: opts[:description]
      },
      last_updated_at: DateTime.utc_now()
    }
    
    updated_session = %{session | 
      variables: Map.put(session.variables, var_id, variable),
      last_accessed_at: DateTime.utc_now()
    }
    
    new_state = Map.put(state, session_id, updated_session)
    
    Logger.info("Registered variable #{name} (#{var_id}) in session #{session_id}")
    
    {:reply, {:ok, var_id}, new_state}
  else
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end
```

#### Step 1.3: Implement Variable Access

```elixir
# Variable getter with type information
def handle_call({:get_variable, session_id, var_id}, _from, state) do
  with {:ok, session} <- get_session_state(state, session_id),
       {:ok, variable} <- Map.fetch(session.variables, var_id) do
    
    # Update last accessed time
    updated_session = %{session | last_accessed_at: DateTime.utc_now()}
    new_state = Map.put(state, session_id, updated_session)
    
    {:reply, {:ok, variable}, new_state}
  else
    :error -> {:reply, {:error, :variable_not_found}, state}
    error -> {:reply, error, state}
  end
end

# Variable setter with validation and notifications
def handle_call({:update_variable, session_id, var_id, new_value, metadata}, _from, state) do
  with {:ok, session} <- get_session_state(state, session_id),
       {:ok, variable} <- Map.fetch(session.variables, var_id),
       {:ok, type_module} <- validate_variable_type(variable.type),
       {:ok, validated_value} <- type_module.validate(new_value) do
    
    updated_variable = %{variable |
      value: validated_value,
      last_updated_at: DateTime.utc_now(),
      metadata: Map.merge(variable.metadata, metadata)
    }
    
    updated_session = %{session |
      variables: Map.put(session.variables, var_id, updated_variable),
      last_accessed_at: DateTime.utc_now()
    }
    
    new_state = Map.put(state, session_id, updated_session)
    
    # Notify observers
    notify_variable_observers(session_id, var_id, updated_variable, 
      Map.get(session.variable_observers, var_id, MapSet.new()))
    
    {:reply, :ok, new_state}
  else
    error -> {:reply, error, state}
  end
end
```

### Phase 2: gRPC Protocol Extensions (Week 1-2)

#### Step 2.1: Update Protocol Buffers

```protobuf
// protos/snakepit_bridge.proto

// Add to existing service
service SnakepitBridge {
  // ... existing RPCs ...
  
  // Variable operations
  rpc GetVariable(GetVariableRequest) returns (GetVariableResponse);
  rpc SetVariable(SetVariableRequest) returns (SetVariableResponse);
  rpc ListVariables(ListVariablesRequest) returns (ListVariablesResponse);
  rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
}

// Variable messages
message Variable {
  string id = 1;
  string name = 2;
  string type = 3;
  google.protobuf.Any value = 4;
  string constraints_json = 5;
  map<string, string> metadata = 6;
  enum Source {
    ELIXIR = 0;
    PYTHON = 1;
  }
  Source source = 7;
  int64 last_updated_at = 8;
}

message GetVariableRequest {
  string session_id = 1;
  string variable_id = 2;
}

message GetVariableResponse {
  Variable variable = 1;
}

message SetVariableRequest {
  string session_id = 1;
  string variable_id = 2;
  google.protobuf.Any value = 3;
  map<string, string> metadata = 4;
}

message SetVariableResponse {
  bool success = 1;
  string error_message = 2;
}

message WatchVariablesRequest {
  string session_id = 1;
  repeated string variable_ids = 2;
}

message VariableUpdate {
  string variable_id = 1;
  Variable variable = 2;
  string update_source = 3;
  map<string, string> update_metadata = 4;
}
```

#### Step 2.2: Implement gRPC Handlers

```elixir
# lib/dspex/bridge/grpc_server.ex

defmodule DSPex.Bridge.GRPCServer do
  use GRPC.Server, service: DSPex.Bridge.SnakepitBridge.Service
  
  # Add variable handlers
  
  @impl true
  def get_variable(request, _stream) do
    case SessionStore.get_variable(request.session_id, request.variable_id) do
      {:ok, variable} ->
        %GetVariableResponse{
          variable: variable_to_proto(variable)
        }
        
      {:error, reason} ->
        raise GRPC.RPCError, status: :not_found, message: "Variable not found: #{reason}"
    end
  end
  
  @impl true
  def set_variable(request, _stream) do
    with {:ok, value} <- deserialize_any(request.value),
         :ok <- SessionStore.update_variable(
           request.session_id,
           request.variable_id,
           value,
           request.metadata
         ) do
      %SetVariableResponse{success: true}
    else
      {:error, reason} ->
        %SetVariableResponse{
          success: false,
          error_message: to_string(reason)
        }
    end
  end
  
  @impl true
  def watch_variables(request, stream) do
    # Set up variable watching
    {:ok, watcher} = VariableWatcher.start_link(
      session_id: request.session_id,
      variable_ids: request.variable_ids,
      stream: stream
    )
    
    # Keep connection alive
    ref = Process.monitor(watcher)
    
    receive do
      {:DOWN, ^ref, :process, ^watcher, _reason} ->
        # Watcher terminated, end stream
        :ok
    end
  end
  
  # Helper to convert Variable to protobuf
  defp variable_to_proto(%Variable{} = var) do
    %DSPex.Bridge.Proto.Variable{
      id: var.id,
      name: to_string(var.name),
      type: to_string(var.type),
      value: serialize_value(var.value, var.type),
      constraints_json: Jason.encode!(var.constraints),
      metadata: var.metadata,
      source: if(var.metadata[:source] == :python, do: :PYTHON, else: :ELIXIR),
      last_updated_at: DateTime.to_unix(var.last_updated_at, :millisecond)
    }
  end
end
```

### Phase 3: Python SessionContext Enhancement (Week 2)

#### Step 3.1: Extend SessionContext

```python
# python/dspex_bridge/session_context.py

import asyncio
import time
from typing import Dict, Any, List, Optional, Tuple, AsyncIterator
import grpc
from google.protobuf import any_pb2

from .proto import snakepit_bridge_pb2 as pb2
from .proto import snakepit_bridge_pb2_grpc as pb2_grpc
from .serialization import serialize_value, deserialize_value

class SessionContext:
    """Enhanced session context with unified tool and variable access."""
    
    def __init__(self, session_id: str, channel: grpc.aio.Channel):
        self.session_id = session_id
        self.channel = channel
        self.stub = pb2_grpc.SnakepitBridgeStub(channel)
        
        # Tool management (existing)
        self._tools: Dict[str, AsyncGRPCProxyTool] = {}
        
        # Variable management (new)
        self._variable_cache: Dict[str, Tuple[Any, float]] = {}
        self._cache_ttl = 1.0  # 1 second TTL
        self._variable_watchers: Dict[str, asyncio.Task] = {}
        
    async def get_variable(self, name: str, bypass_cache: bool = False) -> Any:
        """
        Get a variable value from the session.
        
        Args:
            name: Variable name or ID
            bypass_cache: Force fetch from server
            
        Returns:
            The variable value, properly typed
        """
        # Check cache unless bypassed
        if not bypass_cache and name in self._variable_cache:
            value, timestamp = self._variable_cache[name]
            if time.time() - timestamp < self._cache_ttl:
                return value
        
        # Fetch from server
        request = pb2.GetVariableRequest(
            session_id=self.session_id,
            variable_id=name
        )
        
        try:
            response = await self.stub.GetVariable(request)
            variable = response.variable
            
            # Deserialize value based on type
            value = deserialize_value(variable.value, variable.type)
            
            # Update cache
            self._variable_cache[name] = (value, time.time())
            
            return value
            
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.NOT_FOUND:
                raise KeyError(f"Variable '{name}' not found in session")
            raise
            
    async def set_variable(self, name: str, value: Any, 
                          metadata: Optional[Dict[str, str]] = None) -> None:
        """
        Set a variable value in the session.
        
        Args:
            name: Variable name or ID
            value: New value (will be type-checked on server)
            metadata: Optional metadata for the update
        """
        # Serialize value
        serialized = serialize_value(value)
        
        request = pb2.SetVariableRequest(
            session_id=self.session_id,
            variable_id=name,
            value=serialized,
            metadata=metadata or {}
        )
        
        response = await self.stub.SetVariable(request)
        
        if not response.success:
            raise ValueError(f"Failed to set variable: {response.error_message}")
            
        # Update cache
        self._variable_cache[name] = (value, time.time())
        
    async def list_variables(self) -> Dict[str, Any]:
        """List all variables in the session."""
        request = pb2.ListVariablesRequest(session_id=self.session_id)
        response = await self.stub.ListVariables(request)
        
        variables = {}
        for var in response.variables:
            value = deserialize_value(var.value, var.type)
            variables[var.name] = {
                'id': var.id,
                'type': var.type,
                'value': value,
                'metadata': dict(var.metadata)
            }
            
        return variables
        
    async def watch_variables(self, variable_names: List[str]) -> AsyncIterator[Dict[str, Any]]:
        """
        Watch variables for changes.
        
        Yields:
            Dict containing variable_id, new_value, and metadata
        """
        request = pb2.WatchVariablesRequest(
            session_id=self.session_id,
            variable_ids=variable_names
        )
        
        async for update in self.stub.WatchVariables(request):
            # Update cache
            value = deserialize_value(update.variable.value, update.variable.type)
            self._variable_cache[update.variable_id] = (value, time.time())
            
            yield {
                'variable_id': update.variable_id,
                'value': value,
                'type': update.variable.type,
                'metadata': dict(update.update_metadata),
                'source': update.update_source
            }
```

#### Step 3.2: Create Variable-Aware Tools

```python
# python/dspex_bridge/variable_aware_tools.py

from typing import List, Dict, Any, Optional
from .proxy_tool import AsyncGRPCProxyTool
from .session_context import SessionContext

class VariableAwareProxyTool(AsyncGRPCProxyTool):
    """
    Enhanced proxy tool that automatically fetches and injects variables.
    """
    
    def __init__(self, tool_spec: Dict[str, Any], session_context: SessionContext,
                 variable_bindings: Optional[Dict[str, str]] = None):
        """
        Args:
            tool_spec: Tool specification from server
            session_context: Session context for variable access
            variable_bindings: Map of parameter_name -> variable_name
        """
        super().__init__(tool_spec, session_context)
        self.variable_bindings = variable_bindings or {}
        
    async def __call__(self, *args, **kwargs) -> Any:
        """Execute tool with automatic variable injection."""
        # Fetch and inject bound variables
        for param_name, var_name in self.variable_bindings.items():
            if param_name not in kwargs:  # Don't override explicit args
                try:
                    kwargs[param_name] = await self.session_context.get_variable(var_name)
                except KeyError:
                    # Variable doesn't exist, skip
                    pass
        
        # Add all variables as context if requested
        if kwargs.get('_include_all_variables', False):
            kwargs['_variables'] = await self.session_context.list_variables()
            
        # Execute tool with enriched kwargs
        return await super().__call__(*args, **kwargs)
        
    def bind_variable(self, param_name: str, variable_name: str) -> 'VariableAwareProxyTool':
        """Bind a parameter to a variable."""
        self.variable_bindings[param_name] = variable_name
        return self
```

### Phase 4: DSPy Integration (Week 2-3)

#### Step 4.1: Variable-Aware DSPy Modules

```python
# python/dspex_bridge/dspy_integration.py

import dspy
from typing import Dict, Any, List, Optional
from .session_context import SessionContext

class VariableAwareMixin:
    """
    Mixin to make any DSPy module variable-aware.
    """
    
    def __init__(self, *args, session_context: SessionContext = None, **kwargs):
        super().__init__(*args, **kwargs)
        self.session_context = session_context
        self._variable_bindings: Dict[str, str] = {}
        
    async def bind_to_variable(self, attribute: str, variable_name: str) -> None:
        """
        Bind a module attribute to a session variable.
        
        Example:
            await module.bind_to_variable('temperature', 'global_temperature')
        """
        if not self.session_context:
            raise RuntimeError("No session context available")
            
        # Get current value
        value = await self.session_context.get_variable(variable_name)
        
        # Set attribute
        setattr(self, attribute, value)
        
        # Remember binding
        self._variable_bindings[attribute] = variable_name
        
    async def sync_variables(self) -> None:
        """Sync all bound variables from session."""
        if not self.session_context:
            return
            
        for attr, var_name in self._variable_bindings.items():
            try:
                value = await self.session_context.get_variable(var_name)
                setattr(self, attr, value)
            except KeyError:
                # Variable was removed, skip
                pass
                
    async def forward_with_variables(self, *args, **kwargs):
        """Forward method that syncs variables before execution."""
        await self.sync_variables()
        return super().forward(*args, **kwargs)


# Example: Variable-aware Predict module
class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    """Predict module with variable support."""
    
    async def forward(self, *args, **kwargs):
        """Override forward to sync variables."""
        await self.sync_variables()
        return super().forward(*args, **kwargs)


# Example: Variable-aware ChainOfThought
class VariableAwareChainOfThought(VariableAwareMixin, dspy.ChainOfThought):
    """ChainOfThought module with variable support."""
    
    async def forward(self, *args, **kwargs):
        await self.sync_variables()
        return super().forward(*args, **kwargs)
```

#### Step 4.2: Module-Type Variables

```python
# python/dspex_bridge/module_variables.py

from typing import Type, Dict, Any
import dspy
from .session_context import SessionContext

class ModuleVariableResolver:
    """Resolves module-type variables to actual DSPy module classes."""
    
    # Registry of available modules
    MODULE_REGISTRY = {
        'Predict': dspy.Predict,
        'ChainOfThought': dspy.ChainOfThought,
        'ReAct': dspy.ReAct,
        'ProgramOfThought': dspy.ProgramOfThought,
    }
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        
    async def resolve_module(self, variable_name: str) -> Type[dspy.Module]:
        """
        Resolve a module-type variable to a DSPy module class.
        
        Args:
            variable_name: Name of the module-type variable
            
        Returns:
            DSPy module class
        """
        module_name = await self.session_context.get_variable(variable_name)
        
        if module_name not in self.MODULE_REGISTRY:
            raise ValueError(f"Unknown module type: {module_name}")
            
        return self.MODULE_REGISTRY[module_name]
        
    async def create_module(self, variable_name: str, *args, **kwargs) -> dspy.Module:
        """
        Create a module instance from a module-type variable.
        
        Args:
            variable_name: Name of the module-type variable
            *args, **kwargs: Arguments for module constructor
            
        Returns:
            Module instance
        """
        module_class = await self.resolve_module(variable_name)
        
        # Make it variable-aware if possible
        if hasattr(module_class, '__name__'):
            # Try to get variable-aware version
            var_aware_name = f"VariableAware{module_class.__name__}"
            var_aware_class = globals().get(var_aware_name, module_class)
            
            if var_aware_class != module_class:
                return var_aware_class(*args, session_context=self.session_context, **kwargs)
                
        return module_class(*args, **kwargs)
```

### Phase 5: Complete Example (Week 3)

Here's a complete example showing the unified system in action:

```python
# example_unified_usage.py

import asyncio
import grpc
from dspex_bridge import SessionContext, VariableAwareChainOfThought

async def main():
    # Connect to DSPex bridge
    channel = grpc.aio.insecure_channel('localhost:50051')
    
    # Initialize session (assume session created in Elixir)
    session = SessionContext('session_123', channel)
    
    # Set some variables
    await session.set_variable('temperature', 0.7)
    await session.set_variable('reasoning_style', 'detailed')
    await session.set_variable('max_tokens', 256)
    
    # Create variable-aware DSPy module
    cot = VariableAwareChainOfThought(
        "question -> reasoning, answer",
        session_context=session
    )
    
    # Bind module parameters to variables
    await cot.bind_to_variable('temperature', 'temperature')
    await cot.bind_to_variable('max_tokens', 'max_tokens')
    
    # Use the module - it automatically uses current variable values
    result = await cot.forward(question="What causes rain?")
    
    print(f"Reasoning: {result.reasoning}")
    print(f"Answer: {result.answer}")
    
    # Watch for variable changes
    async def watch_temperature():
        async for update in session.watch_variables(['temperature']):
            print(f"Temperature changed to: {update['value']}")
            # Module will use new value on next call
    
    # Start watching in background
    watch_task = asyncio.create_task(watch_temperature())
    
    # From Elixir side, temperature could be updated by an optimizer
    # The module will automatically use the new value
    
    await asyncio.sleep(10)  # Keep running to see updates
    watch_task.cancel()

if __name__ == "__main__":
    asyncio.run(main())
```

### Elixir Side Usage:

```elixir
# Create session with tools and variables
{:ok, session_id} = SessionStore.create_session()

# Register a tool
:ok = SessionStore.register_tool(session_id, "web_search", %{
  name: "web_search",
  description: "Search the web",
  parameters: [...],
  handler: &WebSearch.execute/2
})

# Register variables
{:ok, temp_id} = SessionStore.register_variable(
  session_id, :temperature, :float, 0.7,
  constraints: %{min: 0.0, max: 2.0}
)

{:ok, style_id} = SessionStore.register_variable(
  session_id, :reasoning_style, :choice, "concise",
  constraints: %{choices: ["concise", "detailed", "academic"]}
)

# Variables can be optimized
Task.start(fn ->
  for temp <- [0.3, 0.5, 0.7, 0.9, 1.1] do
    Process.sleep(5000)
    SessionStore.update_variable(session_id, temp_id, temp, %{
      source: "optimizer",
      iteration: temp
    })
  end
end)
```

## Testing During Implementation

### Unit Tests for Each Component:

```elixir
# test/session_store_variables_test.exs
defmodule DSPex.Bridge.SessionStoreVariablesTest do
  use ExUnit.Case
  
  test "register and retrieve variable" do
    {:ok, session_id} = SessionStore.create_session()
    
    {:ok, var_id} = SessionStore.register_variable(
      session_id, :test_var, :float, 1.5
    )
    
    {:ok, variable} = SessionStore.get_variable(session_id, var_id)
    assert variable.value == 1.5
    assert variable.type == :float
  end
end
```

### Integration Tests:

```python
# test_unified_bridge.py
import pytest
import asyncio
from dspex_bridge import SessionContext

@pytest.mark.asyncio
async def test_variable_tool_integration(session_context):
    # Set a variable
    await session_context.set_variable('quality_threshold', 0.8)
    
    # Create a tool that uses the variable
    search_tool = session_context.create_variable_aware_tool(
        'search',
        {'min_quality': 'quality_threshold'}
    )
    
    # Tool should use the variable value
    results = await search_tool("DSPy framework")
    assert len(results) > 0
```

## Common Pitfalls and Solutions

1. **Cache Invalidation**: Always invalidate cache when variables are updated externally
2. **Type Mismatches**: Ensure consistent type handling between Elixir and Python
3. **Streaming Lifecycle**: Properly handle streaming RPC cleanup
4. **Variable Scope**: Remember variables are session-scoped, not global

## Next Steps

After implementing the unified bridge:

1. Add batch variable operations for performance
2. Implement variable dependency tracking
3. Add support for complex types (embeddings, tensors)
4. Build optimization framework on top
5. Create higher-level abstractions for common patterns
# Unified gRPC Bridge: Variables Integration Specification

## Executive Summary

This specification describes how the revolutionary DSPex Variables system integrates seamlessly into the gRPC Tool Bridge architecture. Rather than creating a parallel bridge, variables become first-class citizens within the existing gRPC infrastructure, creating a unified system for both tools and variables.

## Architecture Overview

### Unified State Management

```
┌─────────────────────────────────────────────────────────┐
│                    Elixir Side                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │          Enhanced SessionStore                   │  │
│  │  ┌────────────────┐  ┌────────────────────┐    │  │
│  │  │  Tools Registry │  │ Variables Registry │    │  │
│  │  └────────────────┘  └────────────────────┘    │  │
│  │  ┌────────────────┐  ┌────────────────────┐    │  │
│  │  │    Observers   │  │   Optimizers      │    │  │
│  │  └────────────────┘  └────────────────────┘    │  │
│  └──────────────────────────────────────────────────┘  │
│                           ↕ gRPC                        │
└─────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────┐
│                    Python Side                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │          Enhanced SessionContext                 │  │
│  │  ┌────────────────┐  ┌────────────────────┐    │  │
│  │  │ Variable Cache │  │  Tool Proxies     │    │  │
│  │  └────────────────┘  └────────────────────┘    │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │        Variable-Aware DSPy Modules               │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Enhanced SessionStore (Elixir)

The `SessionStore` now manages both tools and variables in a unified manner:

```elixir
defmodule DSPex.Bridge.SessionStore do
  use GenServer
  
  defstruct [
    :session_id,
    :tools,              # Map of tool_id => tool_spec
    :variables,          # Map of var_id => variable
    :observers,          # Map of var_id => MapSet of PIDs
    :optimizers,         # Map of var_id => optimizer_pid
    :metadata,           # Session metadata
    :created_at,
    :last_accessed_at
  ]
  
  # Unified API for tools and variables
  
  @doc "Register a variable in the session"
  def register_variable(session_id, name, type, initial_value, opts \\ []) do
    GenServer.call(__MODULE__, {:register_variable, session_id, name, type, initial_value, opts})
  end
  
  @doc "Get variable value with type information"
  def get_variable(session_id, var_id) do
    GenServer.call(__MODULE__, {:get_variable, session_id, var_id})
  end
  
  @doc "Update variable and notify observers"
  def update_variable(session_id, var_id, new_value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_variable, session_id, var_id, new_value, metadata})
  end
  
  @doc "Watch variables for changes (streaming)"
  def watch_variables(session_id, var_ids, watcher_pid) do
    GenServer.cast(__MODULE__, {:watch_variables, session_id, var_ids, watcher_pid})
  end
end
```

### 2. Variable Type System Integration

Variable types are designed to work seamlessly with protobuf serialization:

```elixir
defmodule DSPex.Bridge.Variables.Types do
  @moduledoc """
  Variable types compatible with gRPC/protobuf serialization
  """
  
  defmodule Variable do
    @type t :: %__MODULE__{
      id: String.t(),
      name: atom(),
      type: atom(),
      value: any(),
      constraints: map(),
      metadata: map(),
      source: :elixir | :python,
      last_updated_at: DateTime.t()
    }
    
    defstruct [:id, :name, :type, :value, :constraints, :metadata, :source, :last_updated_at]
    
    def to_proto(%__MODULE__{} = var) do
      %VariableProto{
        id: var.id,
        name: to_string(var.name),
        type: to_string(var.type),
        value: serialize_value(var.value, var.type),
        constraints: Jason.encode!(var.constraints),
        metadata: encode_metadata(var.metadata),
        source: var.source,
        last_updated_at: DateTime.to_unix(var.last_updated_at, :millisecond)
      }
    end
    
    def from_proto(%VariableProto{} = proto) do
      %__MODULE__{
        id: proto.id,
        name: String.to_atom(proto.name),
        type: String.to_atom(proto.type),
        value: deserialize_value(proto.value, proto.type),
        constraints: Jason.decode!(proto.constraints),
        metadata: decode_metadata(proto.metadata),
        source: proto.source,
        last_updated_at: DateTime.from_unix!(proto.last_updated_at, :millisecond)
      }
    end
  end
end
```

### 3. Enhanced gRPC Service

New RPCs for variable management integrated into the existing service:

```protobuf
// In snakepit_bridge.proto

service SnakepitBridge {
  // Existing tool RPCs...
  
  // Variable management RPCs
  rpc GetVariable(GetVariableRequest) returns (GetVariableResponse);
  rpc SetVariable(SetVariableRequest) returns (SetVariableResponse);
  rpc ListVariables(ListVariablesRequest) returns (ListVariablesResponse);
  rpc WatchVariables(WatchVariablesRequest) returns (stream VariableUpdate);
  
  // Variable-aware tool execution
  rpc ExecuteToolWithVariables(ExecuteToolRequest) returns (ExecuteToolResponse);
}

message Variable {
  string id = 1;
  string name = 2;
  string type = 3;
  google.protobuf.Any value = 4;
  string constraints = 5;  // JSON encoded
  map<string, string> metadata = 6;
  string source = 7;  // "elixir" or "python"
  int64 last_updated_at = 8;
}

message GetVariableRequest {
  string session_id = 1;
  string variable_id = 2;
}

message GetVariableResponse {
  Variable variable = 1;
}

message VariableUpdate {
  string variable_id = 1;
  Variable variable = 2;
  string update_source = 3;
  map<string, string> update_metadata = 4;
}
```

### 4. Enhanced Python SessionContext

The `SessionContext` now provides unified access to both tools and variables:

```python
class SessionContext:
    """Enhanced session context with integrated variable support."""
    
    def __init__(self, session_id: str, channel: grpc.aio.Channel):
        self.session_id = session_id
        self.channel = channel
        self.stub = SnakepitBridgeStub(channel)
        self._tools: Dict[str, AsyncGRPCProxyTool] = {}
        self._variable_cache: Dict[str, Tuple[Any, float]] = {}  # (value, timestamp)
        self._variable_watchers: Dict[str, asyncio.Queue] = {}
        self._cache_ttl = 1.0  # 1 second cache TTL
        
    async def get_variable(self, name: str, bypass_cache: bool = False) -> Any:
        """Get a variable value from the session."""
        # Check cache first
        if not bypass_cache and name in self._variable_cache:
            value, timestamp = self._variable_cache[name]
            if time.time() - timestamp < self._cache_ttl:
                return value
        
        # Fetch from Elixir
        request = GetVariableRequest(
            session_id=self.session_id,
            variable_id=name
        )
        response = await self.stub.GetVariable(request)
        
        # Deserialize and cache
        value = self._deserialize_variable_value(response.variable)
        self._variable_cache[name] = (value, time.time())
        
        return value
        
    async def set_variable(self, name: str, value: Any, metadata: Dict[str, str] = None) -> None:
        """Set a variable value in the session."""
        serialized_value = self._serialize_value(value)
        
        request = SetVariableRequest(
            session_id=self.session_id,
            variable_id=name,
            value=serialized_value,
            metadata=metadata or {}
        )
        
        await self.stub.SetVariable(request)
        
        # Update local cache
        self._variable_cache[name] = (value, time.time())
        
    async def watch_variables(self, variable_names: List[str]) -> AsyncIterator[VariableUpdate]:
        """Watch variables for changes."""
        request = WatchVariablesRequest(
            session_id=self.session_id,
            variable_ids=variable_names
        )
        
        async for update in self.stub.WatchVariables(request):
            # Update cache
            value = self._deserialize_variable_value(update.variable)
            self._variable_cache[update.variable_id] = (value, time.time())
            
            yield update
            
    def create_variable_aware_tool(self, tool_name: str, variable_dependencies: List[str]) -> AsyncGRPCProxyTool:
        """Create a tool proxy that automatically fetches required variables."""
        base_tool = self._tools.get(tool_name)
        if not base_tool:
            raise ValueError(f"Tool {tool_name} not found in session")
            
        return VariableAwareProxyTool(
            base_tool.tool_spec,
            self,
            variable_dependencies
        )
```

### 5. Variable-Aware Tools

Tools can now seamlessly access variables:

```python
class VariableAwareProxyTool(AsyncGRPCProxyTool):
    """Tool proxy that automatically injects variable values."""
    
    def __init__(self, tool_spec: ToolSpec, session_context: SessionContext, 
                 variable_dependencies: List[str]):
        super().__init__(tool_spec, session_context)
        self.variable_dependencies = variable_dependencies
        
    async def __call__(self, *args, **kwargs) -> Any:
        # Fetch all required variables
        variables = {}
        for var_name in self.variable_dependencies:
            variables[var_name] = await self.session_context.get_variable(var_name)
        
        # Inject variables into kwargs
        kwargs['_variables'] = variables
        
        # Execute tool with enriched context
        return await super().__call__(*args, **kwargs)
```

### 6. DSPy Module Integration

DSPy modules become variable-aware through the SessionContext:

```python
class VariableAwareDSPyModule:
    """Mixin for DSPy modules to access session variables."""
    
    def __init__(self, session_context: SessionContext, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.session_context = session_context
        self._variable_subscriptions = set()
        
    async def get_variable(self, name: str) -> Any:
        """Get a variable value."""
        return await self.session_context.get_variable(name)
        
    async def set_variable(self, name: str, value: Any) -> None:
        """Set a variable value."""
        await self.session_context.set_variable(name, value)
        
    async def use_variable_as_parameter(self, param_name: str, variable_name: str):
        """Bind a module parameter to a variable."""
        value = await self.get_variable(variable_name)
        setattr(self, param_name, value)
        self._variable_subscriptions.add((param_name, variable_name))
        
    async def sync_variables(self):
        """Update all parameter bindings from variables."""
        for param_name, var_name in self._variable_subscriptions:
            value = await self.get_variable(var_name)
            setattr(self, param_name, value)
```

## Key Integration Patterns

### 1. Unified State Management

All state (tools and variables) lives in the Elixir SessionStore:

```elixir
# In Elixir
{:ok, session_id} = SessionStore.create_session()
:ok = SessionStore.register_tool(session_id, "search", search_spec)
{:ok, var_id} = SessionStore.register_variable(session_id, :temperature, :float, 0.7)

# In Python
session = await SessionContext.initialize(session_id, channel)
result = await session.tools["search"]("query")
temp = await session.get_variable("temperature")
```

### 2. Cross-Language Type Safety

Variables maintain type safety across the bridge:

```python
# Python side
await session.set_variable("max_tokens", "not_a_number")  # Raises TypeError

# Elixir side validates
case Types.Integer.validate(value) do
  {:ok, valid} -> :ok
  {:error, reason} -> {:error, {:invalid_type, reason}}
end
```

### 3. Observer Pattern via Streaming

Real-time variable updates using gRPC streaming:

```python
# Python: Watch for variable changes
async for update in session.watch_variables(["temperature", "max_tokens"]):
    print(f"Variable {update.variable_id} changed to {update.variable.value}")
    
    # React to changes
    if update.variable_id == "temperature":
        await reconfigure_model(update.variable.value)
```

### 4. Module-Type Variables

Special handling for module selection variables:

```python
# Register module variable in Elixir
SessionStore.register_variable(session_id, :reasoning_module, :module, "Predict",
  constraints: %{choices: ["Predict", "ChainOfThought", "ReAct"]}
)

# Use in Python
module_name = await session.get_variable("reasoning_module")
module_class = getattr(dspy, module_name)
reasoning = module_class("question -> answer")
```

## Migration from Separate Variables Bridge

### Before (Separate Bridge):
```python
# Old approach with separate infrastructure
handler = VariableCommandHandler()
module_id = handler.create_variable_aware_module("Predict", "q->a", {"temp": "var_123"})
```

### After (Unified gRPC):
```python
# New approach with unified infrastructure
session = await SessionContext.initialize(session_id, channel)
await session.set_variable("temperature", 0.7)

# Tools automatically have access to variables
predictor = session.create_variable_aware_tool("predict", ["temperature"])
result = await predictor(question="What is DSPy?")
```

## Performance Optimizations

1. **Variable Caching**: Python maintains a TTL-based cache
2. **Batch Operations**: Multiple variables fetched in one RPC
3. **Streaming Updates**: Only changed variables sent over the wire
4. **Lazy Loading**: Variables fetched only when accessed

## Security Considerations

1. **Session Isolation**: Variables scoped to sessions
2. **Type Validation**: All values validated before storage
3. **Access Control**: Future support for read-only variables
4. **Audit Trail**: All variable changes logged with metadata

## Implementation Phases

### Phase 1: Core Variable Operations
- GetVariable/SetVariable RPCs
- Basic type system (float, int, string, bool)
- SessionContext variable methods

### Phase 2: Advanced Features
- WatchVariables streaming
- Module-type variables
- Variable-aware tools
- Observer pattern

### Phase 3: Optimization Support
- Batch variable operations
- Variable dependency tracking
- Cross-module optimization coordination

This unified approach creates a single, powerful bridge that handles both tools and variables, eliminating architectural divergence while enabling the revolutionary variable-centric programming model.
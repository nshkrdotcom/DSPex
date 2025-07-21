# Stage 2: Tool & DSPy Module Integration

## Overview

Stage 2 breathes life into the variable system by connecting it to the computational logic in Python. Where Stage 1 was about *storing* state, Stage 2 is about *using* that state to dynamically control the behavior of tools and DSPy modules. This is the crucial step that enables Elixir to orchestrate and configure Python execution at runtime, forming the core of the unified bridge's power.

## Goals

1.  **Connect Variables to Tools:** Implement a mechanism for tool execution to automatically use values from session variables.
2.  **Connect Variables to DSPy Modules:** Allow DSPy module parameters (like `temperature`, `max_tokens`) to be bound to and controlled by session variables.
3.  **Enable Dynamic Configuration:** Provide a complete loop where Elixir can update a variable, and subsequent Python executions automatically reflect that change without redeployment.
4.  **Refactor Python Adapter:** Make the advanced logic from `enhanced_bridge.py` the primary, session-aware command handler for the gRPC server.
5.  **Prove Functionality:** Demonstrate the entire system working end-to-end with comprehensive integration tests.

## Deliverables

-   `VariableAwareProxyTool` class in Python for tools that automatically inject variable values.
-   `VariableAwareMixin` class in Python to make any DSPy module controllable by session variables.
-   Refactored `grpc_bridge.py` and a new `enhanced_adapter.py` that use the `SessionContext` to manage state.
-   Updated `DSPex.Modules` in Elixir to support variable binding syntax.
-   Integration tests verifying that changes to Elixir variables dynamically alter the behavior of Python tools and DSPy modules.

## Detailed Implementation Plan

### 1. Implement Variable-Aware Proxy Tool (Python)

This proxy tool wraps a standard tool, automatically fetching variable values before execution.

#### Create `snakepit/priv/python/snakepit_bridge/proxy_tool.py`:

```python
"""
Proxy tool for executing Elixir-defined tools via gRPC.
"""

from typing import Dict, Any, Optional

from .session_context import SessionContext

class AsyncGRPCProxyTool:
    """A proxy object that executes a tool on the Elixir side via gRPC."""
    
    def __init__(self, tool_spec: Dict[str, Any], session_context: SessionContext):
        self.spec = tool_spec
        self.session_context = session_context
        self.name = tool_spec.get('name')
        self.description = tool_spec.get('description')
    
    async def __call__(self, *args, **kwargs) -> Any:
        """Executes the remote tool."""
        # This will call the ExecuteTool RPC
        return await self.session_context.execute_tool(self.name, kwargs)

class VariableAwareProxyTool(AsyncGRPCProxyTool):
    """
    Enhanced proxy tool that automatically fetches and injects variables.
    """
    
    def __init__(
        self, 
        tool_spec: Dict[str, Any], 
        session_context: SessionContext,
        variable_bindings: Optional[Dict[str, str]] = None
    ):
        super().__init__(tool_spec, session_context)
        self.variable_bindings = variable_bindings or {}
    
    def bind_variable(self, parameter: str, variable_name: str) -> 'VariableAwareProxyTool':
        """Dynamically bind a tool parameter to a session variable."""
        self.variable_bindings[parameter] = variable_name
        return self
    
    async def __call__(self, *args, **kwargs) -> Any:
        """Execute tool with automatic variable injection."""
        injected_kwargs = kwargs.copy()
        
        # Fetch and inject bound variables
        for param_name, var_name in self.variable_bindings.items():
            # Explicitly passed arguments override variable bindings
            if param_name not in injected_kwargs:
                try:
                    # Fetch from session, no default. If missing, it's an error.
                    injected_kwargs[param_name] = await self.session_context.get_variable(var_name)
                except KeyError:
                    # You could log a warning here if a bound variable is missing
                    pass
        
        # Execute the underlying tool with the enriched kwargs
        return await super().__call__(**injected_kwargs)

```

### 2. Implement Variable-Aware DSPy Mixin (Python)

This mixin makes any DSPy module dynamically configurable via session variables.

#### Create `snakepit/priv/python/snakepit_bridge/dspy_integration.py`:

```python
"""
Integration layer for making DSPy modules variable-aware.
"""
import dspy
from typing import Dict, Any, Optional

from .session_context import SessionContext

class VariableAwareMixin:
    """Mixin to make any DSPy module dynamically configurable."""
    
    def __init__(self, *args, session_context: SessionContext = None, **kwargs):
        # Separate out our custom kwarg
        self._session_context = session_context
        self._variable_bindings: Dict[str, str] = {}
        super().__init__(*args, **kwargs)

    def bind_variable(self, attribute: str, variable_name: str):
        """Bind a module attribute (e.g., 'temperature') to a session variable."""
        if not self._session_context:
            raise RuntimeError("Cannot bind variable without a SessionContext.")
        self._variable_bindings[attribute] = variable_name

    async def sync_variables(self):
        """Synchronize all bound variables from the Elixir session."""
        if not self._session_context or not self._variable_bindings:
            return
            
        for attr, var_name in self._variable_bindings.items():
            try:
                value = await self._session_context.get_variable(var_name)
                # Update the module's attribute, e.g., self.temperature = 0.9
                setattr(self, attr, value)
            except KeyError:
                # Log a warning or handle as needed
                pass

# Create concrete variable-aware classes
class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    async def forward(self, *args, **kwargs):
        await self.sync_variables()
        return super().forward(*args, **kwargs)

class VariableAwareChainOfThought(VariableAwareMixin, dspy.ChainOfThought):
    async def forward(self, *args, **kwargs):
        await self.sync_variables()
        return super().forward(*args, **kwargs)
```

### 3. Refactor Core Python Bridge Logic

The `enhanced_bridge` logic becomes the primary adapter, now fully session-aware.

#### Update `snakepit/priv/python/snakepit_bridge/adapters/enhanced.py`:

```python
from snakepit_bridge.session_context import SessionContext
from snakepit_bridge.dspy_integration import VariableAwarePredict, VariableAwareChainOfThought

class EnhancedBridgeAdapter:
    """The primary, session-aware logic handler for the gRPC bridge."""
    
    def __init__(self):
        self.session_context: Optional[SessionContext] = None

    def set_session_context(self, session_context: SessionContext):
        self.session_context = session_context

    async def execute_dynamic_call(self, target: str, kwargs: Dict[str, Any]):
        """
        Handles dynamic calls like creating modules or calling functions.
        This is a refactoring of the logic from the old enhanced_bridge.py.
        """
        # Example: Creating a DSPy module
        if target == "dspy.Predict":
            # The session context is now passed to the constructor
            module = VariableAwarePredict(session_context=self.session_context, **kwargs)
            
            # Store the module instance in the session's local object store
            # The 'store_as' key will be in kwargs
            if 'store_as' in kwargs:
                self.session_context.store_local_object(kwargs['store_as'], module)
            return {"status": "ok", "module_id": kwargs.get('store_as')}

        # Example: Executing a stored module
        if target.startswith("stored."):
            parts = target.split('.')
            module_id = parts[1]
            method_name = parts[2]
            
            module = self.session_context.get_local_object(module_id)
            method = getattr(module, method_name)
            
            # Since forward is async, we need to await it
            if asyncio.iscoroutinefunction(method):
                result = await method(**kwargs)
            else:
                result = method(**kwargs)

            # TODO: Add smart serialization of the result
            return {"status": "ok", "result": str(result)} # Simplified for now

        # ... other dynamic call logic ...
        return {"status": "error", "message": "Target not found"}

```

#### Update `snakepit/priv/python/grpc_bridge.py`:

```python
class SnakepitBridgeServicer(pb2_grpc.SnakepitBridgeServicer):
    # ... (init, Ping, InitializeSession, etc. from Stage 0) ...
    
    async def ExecuteTool(self, request, context):
        """Execute a tool, which can be a dynamic call."""
        session_id = request.session_id
        if session_id not in self.adapters:
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"Session not found: {session_id}")
            return pb2.ExecuteToolResponse()
        
        adapter = self.adapters[session_id]
        
        # Deserialize parameters
        # This will be more robust in the future, using the serializer
        params = {k: json.loads(v.value.decode('utf-8')) for k, v in request.parameters.items()}
        
        try:
            # The adapter method is now async
            result = await adapter.execute_dynamic_call(request.tool_name, params)
            
            # Serialize result back
            response = pb2.ExecuteToolResponse()
            response.success = True
            # Simplified serialization for now
            response.result.value = json.dumps(result).encode('utf-8')
            return response
            
        except Exception as e:
            logger.error(f"Tool execution failed: {e}", exc_info=True)
            response = pb2.ExecuteToolResponse()
            response.success = False
            response.error_message = str(e)
            return response
```

### 4. Update Elixir `DSPex` API & gRPC Client

#### Update `dspex/lib/dspex/modules/predict.ex`:

```elixir
defmodule DSPex.Modules.Predict do
  alias DSPex.Utils.ID

  def create(signature, opts \\ []) do
    module_id = opts[:store_as] || ID.generate("predict")
    
    # Process options to find variable bindings
    {bindings, dspy_kwargs} = extract_variable_bindings(opts)
    
    tool_params = %{
      signature: signature,
      store_as: module_id,
      variable_bindings: bindings
    }
    |> Map.merge(dspy_kwargs)

    # Use the ExecuteTool RPC to create the module
    case Snakepit.GRPC.Client.execute_tool(
           opts[:channel], # The channel needs to be available
           opts[:session_id],
           "dspy.Predict", # The "tool" is the constructor
           tool_params
         ) do
      {:ok, _} -> {:ok, module_id}
      error -> error
    end
  end

  defp extract_variable_bindings(opts) do
    Enum.reduce(opts, { %{}, %{} }, fn
      {key, {:variable, var_name}}, {bindings, kwargs} ->
        {Map.put(bindings, to_string(key), var_name), kwargs}
      {key, value}, {bindings, kwargs} ->
        {bindings, Map.put(kwargs, key, value)}
    end)
  end
  
  def execute(module_id, inputs, opts \\ []) do
    Snakepit.GRPC.Client.execute_tool(
      opts[:channel],
      opts[:session_id],
      "stored.#{module_id}.forward",
      inputs
    )
  end
end
```

#### Update `snakepit/lib/snakepit/grpc/client.ex`:

```elixir
defmodule Snakepit.GRPC.Client do
  # ... (existing functions) ...

  def execute_tool(channel, session_id, tool_name, parameters) do
    # Serialize parameters
    proto_params = Enum.into(parameters, %{}, fn {k, v} ->
      {to_string(k), encode_any(v)}
    end)

    request = ExecuteToolRequest.new(
      session_id: session_id,
      tool_name: tool_name,
      parameters: proto_params
    )

    channel
    |> Stub.execute_tool(request, timeout: @timeout)
    |> handle_response()
  end
  
  # Update encode_any to handle variable binding metadata
  defp encode_any({:variable, var_name}) do
      # Special encoding for variable bindings
      value_map = %{"__dspex_variable__": var_name}
      # ... encode value_map to Any ...
  end
  defp encode_any(value) do
    # ... existing logic ...
  end
end
```

### 5. Integration Tests

#### Create `test/snakepit/grpc_stage2_integration_test.exs`:

```elixir
defmodule Snakepit.GRPCStage2IntegrationTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.GRPC.Client
  
  @moduletag :integration
  
  setup do
    # ... (same setup as Stage 1 test) ...
    # Register a variable for testing
    {:ok, _} = SessionStore.register_variable(
      session_id, "test_temp", :float, 0.7
    )
    
    {:ok, session_id: session_id, channel: channel}
  end

  defp create_predict_module(channel, session_id, opts) do
      # Helper to create a Predict module for tests
      Client.execute_tool(
        channel, session_id, "dspy.Predict",
        %{signature: "question -> answer", store_as: "test_predictor"}
        |> Map.merge(opts)
      )
  end
  
  describe "Variable-Aware DSPy Modules" do
    test "module uses variable for its parameter", %{session_id: session_id, channel: channel} do
      # Create a Predict module and bind its temperature to our variable
      {:ok, _} = create_predict_module(channel, session_id, %{
        variable_bindings: %{"temperature" => "test_temp"}
      })
      
      # Add a helper tool to inspect the module's state on the Python side
      # In a real scenario, you'd verify by observing the output's creativity
      {:ok, inspect_response} = Client.execute_tool(
        channel, session_id, "inspector.get_attribute",
        %{target: "stored.test_predictor", attribute: "temperature"}
      )
      
      assert decode_value(inspect_response.result) == 0.7
      
      # Now, update the variable in Elixir
      :ok = SessionStore.update_variable(session_id, "test_temp", 0.95)
      
      # Execute the module (this will trigger sync_variables)
      {:ok, _} = Client.execute_tool(
        channel, session_id, "stored.test_predictor.forward",
        %{question: "test"}
      )
      
      # Inspect the module again
      {:ok, inspect_response_after} = Client.execute_tool(
        channel, session_id, "inspector.get_attribute",
        %{target: "stored.test_predictor", attribute: "temperature"}
      )
      
      # Verify the module's internal state has changed
      assert decode_value(inspect_response_after.result) == 0.95
    end
  end
end
```

## Success Criteria

1.  **Tool Integration:** A Python tool can be defined to automatically use a variable from the Elixir session.
2.  **DSPy Module Integration:** A DSPy module's parameter (e.g., `temperature`) can be bound to an Elixir variable.
3.  **Dynamic Control Loop:** An Elixir process can update a variable, and a subsequent execution of a bound Python module uses the new value without being re-created.
4.  **Adapter Refactoring:** The `grpc_bridge.py` is simplified, delegating all complex logic to a session-aware adapter instance.
5.  **Tests Pass:** The Stage 2 integration tests pass, proving the entire control loop.

## Common Issues and Solutions

-   **Issue:** `async`/`await` complexity in Python.
    -   **Solution:** Ensure all methods in the call chain that might touch the network (`get_variable`, `forward`) are `async` and are properly `await`ed.
-   **Issue:** Variable bindings are not being applied.
    -   **Solution:** Ensure the `sync_variables()` method is explicitly called at the beginning of the module's `forward` method.
-   **Issue:** Serialization of variable binding instructions.
    -   **Solution:** Define a clear, special format (e.g., `%{ "__dspex_variable__": "var_name" }`) that the Python serialization layer can recognize and translate into a binding action rather than a literal value.

## Next Stage

With the core dynamic control loop in place, Stage 3 will build on this to enable real-time, push-based updates. It will focus on implementing the `WatchVariables` gRPC stream, allowing Python to react instantly to changes in Elixir without needing to poll or execute a module. This will unlock fully reactive and adaptive systems.

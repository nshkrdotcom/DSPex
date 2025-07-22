# Prompt: Implement Python gRPC Server with Variable Support

## Objective
Update the Python gRPC server to implement the unified protocol, adding variable management and streaming capabilities while maintaining tool execution functionality.

## Context
The Python server is the bridge between Elixir and Python ecosystems. It must handle tool execution, variable management, and provide real-time streaming updates.

## Requirements

### Core Components to Implement

1. **SessionContext Class**
   - Manages variables for a session
   - Handles type serialization/deserialization  
   - Provides subscription mechanism for watchers
   - Thread-safe for concurrent access

2. **BridgeServicer Implementation**
   - Implements all RPC methods from the protocol
   - Manages session lifecycle
   - Handles streaming for WatchVariables
   - Proper error handling and logging

3. **Type System Implementation**
   - Serializers for each variable type
   - JSON encoding for complex types in Any fields
   - Validation for constraints
   - Type conversion utilities

4. **Startup Sequence**
   - Print "GRPC_READY:port" when server is ready
   - Proper signal handling
   - Graceful shutdown

## Implementation Steps

### 1. Create SessionContext
```python
# File: snakepit/priv/python/snakepit_bridge/session_context.py

import asyncio
import json
from typing import Any, Dict, List, Optional, Callable
from google.protobuf import any_pb2
import threading

class SessionContext:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.variables: Dict[str, Variable] = {}
        self.observers: Dict[str, List[Callable]] = {}
        self._lock = threading.RLock()
        self._version_counter = 0
    
    def register_variable(self, name: str, var_type: str, 
                         initial_value: Any, constraints: Dict) -> str:
        with self._lock:
            # Implementation here
            pass
    
    def get_variable(self, identifier: str) -> Optional[Variable]:
        with self._lock:
            # Support both name and ID lookup
            pass
    
    def set_variable(self, identifier: str, value: Any, 
                    metadata: Dict[str, str]) -> None:
        with self._lock:
            old_value = self.variables[identifier].value
            # Update variable
            # Notify observers
            self._notify_observers(identifier, old_value, value, metadata)
    
    def watch_variable(self, identifier: str, callback: Callable) -> str:
        """Register a callback for variable changes"""
        with self._lock:
            # Add to observers
            pass
```

### 2. Implement Type Serialization
```python
# File: snakepit/priv/python/snakepit_bridge/type_serialization.py

class TypeSerializer:
    @staticmethod
    def serialize_value(value: Any, var_type: str) -> any_pb2.Any:
        """Serialize Python value to protobuf Any with JSON encoding"""
        if var_type in ['float', 'integer', 'string', 'boolean']:
            # Direct JSON encoding
            json_str = json.dumps(value)
        elif var_type == 'embedding':
            # Convert numpy array to list
            json_str = json.dumps(value.tolist() if hasattr(value, 'tolist') else value)
        elif var_type == 'tensor':
            # Include shape and data
            json_str = json.dumps({
                'shape': value.shape if hasattr(value, 'shape') else [],
                'data': value.tolist() if hasattr(value, 'tolist') else value
            })
        else:
            json_str = json.dumps(value)
        
        any_msg = any_pb2.Any()
        any_msg.type_url = f"dspex.variables/{var_type}"
        any_msg.value = json_str.encode('utf-8')
        return any_msg
    
    @staticmethod
    def deserialize_value(any_msg: any_pb2.Any, var_type: str) -> Any:
        """Deserialize protobuf Any to Python value"""
        json_str = any_msg.value.decode('utf-8')
        
        if var_type in ['float', 'integer', 'string', 'boolean']:
            return json.loads(json_str)
        elif var_type == 'embedding':
            # Could convert back to numpy if needed
            return json.loads(json_str)
        elif var_type == 'tensor':
            data = json.loads(json_str)
            # Reconstruct tensor if needed
            return data
        else:
            return json.loads(json_str)
```

### 3. Implement gRPC Service
```python
# File: snakepit/priv/python/snakepit_bridge/bridge_servicer.py

import grpc
from concurrent import futures
import asyncio
from . import bridge_service_pb2
from . import bridge_service_pb2_grpc

class BridgeServicer(bridge_service_pb2_grpc.BridgeServiceServicer):
    def __init__(self):
        self.sessions: Dict[str, SessionContext] = {}
        self._lock = threading.Lock()
    
    def RegisterVariable(self, request, context):
        session = self._get_or_create_session(request.session_id)
        
        try:
            var_id = session.register_variable(
                name=request.name,
                var_type=request.type,
                initial_value=TypeSerializer.deserialize_value(
                    request.initial_value, request.type
                ),
                constraints=MessageToDict(request.constraints)
            )
            
            variable = session.get_variable(var_id)
            return bridge_service_pb2.RegisterVariableResponse(
                variable_id=var_id,
                variable=self._variable_to_proto(variable)
            )
        except Exception as e:
            context.abort(grpc.StatusCode.INTERNAL, str(e))
    
    def WatchVariables(self, request, context):
        """Server streaming RPC for variable updates"""
        session = self._get_session(request.session_id)
        if not session:
            context.abort(grpc.StatusCode.NOT_FOUND, "Session not found")
        
        # Create queue for this watcher
        update_queue = asyncio.Queue()
        observer_ids = []
        
        def make_callback(var_id):
            def callback(old_value, new_value, metadata):
                # Queue update for streaming
                update = self._create_update(var_id, old_value, new_value, metadata)
                asyncio.create_task(update_queue.put(update))
            return callback
        
        # Register observers
        for var_id in request.variable_identifiers:
            callback = make_callback(var_id)
            obs_id = session.watch_variable(var_id, callback)
            observer_ids.append((var_id, obs_id))
        
        # Send initial values if requested
        if request.include_initial_values:
            for var_id in request.variable_identifiers:
                var = session.get_variable(var_id)
                if var:
                    initial_update = self._create_initial_update(var)
                    yield initial_update
        
        # Stream updates
        try:
            while context.is_active():
                try:
                    # Wait for updates with timeout for liveness
                    update = asyncio.run(
                        asyncio.wait_for(update_queue.get(), timeout=30.0)
                    )
                    yield update
                except asyncio.TimeoutError:
                    # Send heartbeat
                    yield bridge_service_pb2.VariableUpdate(
                        update_type="heartbeat",
                        timestamp=Timestamp(seconds=int(time.time()))
                    )
        finally:
            # Cleanup observers
            for var_id, obs_id in observer_ids:
                session.unwatch_variable(var_id, obs_id)
```

### 4. Implement Server Startup
```python
# File: snakepit/priv/python/snakepit_bridge/server.py

def serve():
    # Create thread pool for request handling
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add servicer
    servicer = BridgeServicer()
    bridge_service_pb2_grpc.add_BridgeServiceServicer_to_server(servicer, server)
    
    # Bind to port
    port = server.add_insecure_port('[::]:0')
    server.start()
    
    # CRITICAL: Print ready message for Elixir to detect
    print(f"GRPC_READY:{port}", flush=True)
    
    # Also print to stderr for debugging
    print(f"Python gRPC server started on port {port}", file=sys.stderr)
    
    # Handle shutdown gracefully
    def handle_signal(sig, frame):
        print("Shutting down server...", file=sys.stderr)
        server.stop(grace=5)
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    
    # Wait for termination
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
```

### 5. Integration with DSPy Tools
```python
# File: snakepit/priv/python/snakepit_bridge/variable_aware_mixin.py

class VariableAwareMixin:
    """Mixin for DSPy modules to access variables"""
    
    def __init__(self, session_context: SessionContext, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._session_context = session_context
    
    def get_variable(self, name: str) -> Any:
        """Get current value of a variable"""
        var = self._session_context.get_variable(name)
        return var.value if var else None
    
    def set_variable(self, name: str, value: Any) -> None:
        """Update a variable"""
        self._session_context.set_variable(name, value, {"source": "dspy_module"})
    
    def watch_variable(self, name: str, callback: Callable) -> None:
        """Watch a variable for changes"""
        self._session_context.watch_variable(name, callback)
```

## Testing Requirements

1. **Unit Tests**
   - Test each variable type serialization
   - Test concurrent access to SessionContext
   - Test observer notification

2. **Integration Tests**
   - Test streaming with multiple watchers
   - Test variable updates during tool execution
   - Test error handling

3. **Load Tests**
   - Test with many concurrent sessions
   - Test with rapid variable updates
   - Test streaming stability

## Files to Create/Modify

1. Create: `snakepit/priv/python/snakepit_bridge/session_context.py`
2. Create: `snakepit/priv/python/snakepit_bridge/type_serialization.py`
3. Update: `snakepit/priv/python/snakepit_bridge/bridge_servicer.py`
4. Update: `snakepit/priv/python/snakepit_bridge/server.py`
5. Create: `snakepit/priv/python/snakepit_bridge/variable_aware_mixin.py`
6. Update: `snakepit/priv/python/requirements.txt` (if needed)

## Critical Implementation Notes

1. **Thread Safety**: Use proper locking for all shared state
2. **Streaming**: Handle client disconnections gracefully
3. **Type Safety**: Validate types match expected constraints
4. **Performance**: Use efficient data structures for observers
5. **Debugging**: Add comprehensive logging at INFO level

## Next Steps
After implementing the Python server:
1. Test server startup and "GRPC_READY" output
2. Test basic variable operations with grpcurl
3. Proceed to update Elixir client (next prompt)
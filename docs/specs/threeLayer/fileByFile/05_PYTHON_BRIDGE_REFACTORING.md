# Python Bridge Refactoring Plan

## Current Python-Side Problems

The Python side of the bridge has grown organically and suffers from:

1. **Monolithic bridge_server.py**: 2000+ lines doing everything
2. **Mixed Concerns**: Business logic tangled with infrastructure
3. **Poor Error Handling**: Generic exceptions bubble up
4. **No Abstraction**: Direct gRPC handling everywhere
5. **Stateful Workers**: Hidden state causes bugs

## Refactoring Goals

1. **Separation of Concerns**: Clear layers and responsibilities
2. **Testability**: Unit test without starting gRPC
3. **Extensibility**: Easy to add new handlers
4. **Performance**: Efficient serialization and routing
5. **Observability**: Comprehensive logging and metrics

## New Python Architecture

### Layer 1: gRPC Service Layer

Thin layer that only handles gRPC concerns:

```python
# snakepit_bridge/grpc/server.py
class SnakepitBridgeServer:
    """Pure gRPC server - no business logic."""
    
    def __init__(self, handler: CommandHandler, port: int = 50051):
        self.handler = handler
        self.server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        
    def Execute(self, request, context):
        """Delegate to handler, manage gRPC concerns only."""
        try:
            result = self.handler.execute(
                session_id=request.session_id,
                command=request.command,
                args=self._deserialize_args(request.args)
            )
            return snakepit_pb2.ExecuteResponse(
                result=self._serialize_result(result)
            )
        except Exception as e:
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(str(e))
            raise
```

### Layer 2: Command Handler Layer

Business logic for routing and executing commands:

```python
# snakepit_bridge/handlers/command_handler.py
class CommandHandler:
    """Routes commands to appropriate handlers."""
    
    def __init__(self, registry: HandlerRegistry, session_manager: SessionManager):
        self.registry = registry
        self.session_manager = session_manager
        
    def execute(self, session_id: str, command: str, args: Dict[str, Any]) -> Any:
        # Get or create session context
        session = self.session_manager.get_or_create(session_id)
        
        # Find appropriate handler
        handler = self.registry.get_handler(command)
        if not handler:
            raise CommandNotFoundError(f"No handler for command: {command}")
            
        # Execute with telemetry
        with telemetry.span("command.execute", command=command):
            return handler.execute(session, args)
```

### Layer 3: Domain-Specific Handlers

Focused handlers for each domain:

```python
# snakepit_bridge/handlers/dspy_handler.py
class DSPyHandler:
    """Handles all DSPy-related commands."""
    
    def __init__(self, instance_manager: InstanceManager):
        self.instance_manager = instance_manager
        
    @handles("dspy.create_instance")
    def create_instance(self, session: Session, args: Dict[str, Any]) -> str:
        class_path = args["class_path"]
        init_args = args.get("args", {})
        
        # Create instance with proper error handling
        try:
            instance = self._import_and_create(class_path, init_args)
            return self.instance_manager.register(session.id, instance)
        except ImportError as e:
            raise DSPyError(f"Failed to import {class_path}: {e}")
        except Exception as e:
            raise DSPyError(f"Failed to create instance: {e}")
            
    @handles("dspy.call_method")
    def call_method(self, session: Session, args: Dict[str, Any]) -> Any:
        ref = args["ref"]
        method = args["method"]
        method_args = args.get("args", {})
        
        instance = self.instance_manager.get(session.id, ref)
        if not instance:
            raise DSPyError(f"Instance not found: {ref}")
            
        # Call with proper error handling
        try:
            result = getattr(instance, method)(**method_args)
            return self._serialize_result(result)
        except AttributeError:
            raise DSPyError(f"Method {method} not found on {type(instance)}")
```

### Layer 4: Session Management

Clean session abstraction with bidirectional support:

```python
# snakepit_bridge/session/manager.py
class SessionManager:
    """Manages session state and provides context."""
    
    def __init__(self, bridge_client: BridgeClient):
        self.sessions: Dict[str, Session] = {}
        self.bridge_client = bridge_client
        
    def get_or_create(self, session_id: str) -> Session:
        if session_id not in self.sessions:
            self.sessions[session_id] = Session(
                id=session_id,
                bridge_client=self.bridge_client,
                created_at=datetime.now()
            )
        return self.sessions[session_id]

# snakepit_bridge/session/context.py
class Session:
    """Session context with bidirectional capabilities."""
    
    def __init__(self, id: str, bridge_client: BridgeClient, created_at: datetime):
        self.id = id
        self.bridge_client = bridge_client
        self.created_at = created_at
        self._instances: Dict[str, Any] = {}
        
    def call_elixir_tool(self, tool_name: str, args: Dict[str, Any]) -> Any:
        """Enable Python → Elixir tool calls."""
        return self.bridge_client.call_tool(
            session_id=self.id,
            tool_name=tool_name,
            args=args
        )
        
    def get_variable(self, name: str) -> Any:
        """Get session variable from Elixir."""
        return self.bridge_client.get_variable(
            session_id=self.id,
            name=name
        )
        
    def set_variable(self, name: str, value: Any) -> None:
        """Set session variable in Elixir."""
        self.bridge_client.set_variable(
            session_id=self.id,
            name=name,
            value=value
        )
```

### Layer 5: Telemetry and Observability

Comprehensive instrumentation:

```python
# snakepit_bridge/telemetry/instrumentation.py
class Telemetry:
    """Unified telemetry for Python bridge."""
    
    def __init__(self):
        self.meter = metrics.get_meter("snakepit_bridge")
        self.tracer = trace.get_tracer("snakepit_bridge")
        
        # Define metrics
        self.command_counter = self.meter.create_counter(
            "commands_total",
            description="Total commands executed"
        )
        
        self.command_duration = self.meter.create_histogram(
            "command_duration_ms",
            description="Command execution duration"
        )
        
    @contextmanager
    def span(self, name: str, **attributes):
        """Create telemetry span with automatic metrics."""
        with self.tracer.start_as_current_span(name, attributes=attributes) as span:
            start = time.time()
            try:
                yield span
                self.command_counter.add(1, {"command": name, "status": "success"})
            except Exception as e:
                span.record_exception(e)
                self.command_counter.add(1, {"command": name, "status": "error"})
                raise
            finally:
                duration = (time.time() - start) * 1000
                self.command_duration.record(duration, {"command": name})
```

## Refactoring Execution Plan

### Phase 1: Extract Session Management (Week 1)

1. Create `session/` package
2. Extract Session and SessionManager classes
3. Add bidirectional support
4. Update existing code to use new sessions

**Before**:
```python
# Everything in bridge_server.py
def execute_command(session_id, command, args):
    if session_id not in sessions:
        sessions[session_id] = {}
    # ... 500 lines of mixed logic
```

**After**:
```python
# Clean separation
def execute_command(session_id, command, args):
    session = session_manager.get_or_create(session_id)
    return command_handler.execute(session, command, args)
```

### Phase 2: Create Handler Registry (Week 2)

1. Define Handler protocol
2. Create HandlerRegistry
3. Extract DSPyHandler
4. Extract ToolHandler

**Handler Protocol**:
```python
from typing import Protocol

class Handler(Protocol):
    """Protocol for command handlers."""
    
    def can_handle(self, command: str) -> bool:
        """Check if this handler can handle the command."""
        ...
        
    def execute(self, session: Session, args: Dict[str, Any]) -> Any:
        """Execute the command."""
        ...
```

### Phase 3: Implement Telemetry (Week 3)

1. Add OpenTelemetry dependencies
2. Create telemetry module
3. Instrument all handlers
4. Add performance tracking

**Instrumented Handler**:
```python
class InstrumentedHandler:
    """Decorator for automatic telemetry."""
    
    def __init__(self, handler: Handler):
        self.handler = handler
        
    def execute(self, session: Session, args: Dict[str, Any]) -> Any:
        command = args.get("command", "unknown")
        with telemetry.span("handler.execute", command=command):
            return self.handler.execute(session, args)
```

### Phase 4: Error Handling Reform (Week 4)

1. Define error hierarchy
2. Add error mapping
3. Improve error messages
4. Add recovery mechanisms

**Error Hierarchy**:
```python
# snakepit_bridge/errors.py
class BridgeError(Exception):
    """Base error for bridge operations."""
    def __init__(self, message: str, details: Dict[str, Any] = None):
        super().__init__(message)
        self.details = details or {}

class CommandNotFoundError(BridgeError):
    """Command handler not found."""
    pass

class DSPyError(BridgeError):
    """DSPy-specific errors."""
    pass

class SessionError(BridgeError):
    """Session-related errors."""
    pass
```

### Phase 5: Testing Infrastructure (Week 5)

1. Create test fixtures
2. Add unit tests for each layer
3. Integration tests for handlers
4. Performance benchmarks

**Test Structure**:
```python
# tests/unit/test_session_manager.py
def test_session_creation():
    manager = SessionManager(mock_bridge_client)
    session = manager.get_or_create("test-session")
    
    assert session.id == "test-session"
    assert session.created_at is not None
    
def test_bidirectional_calls():
    mock_client = Mock()
    session = Session("test", mock_client, datetime.now())
    
    session.call_elixir_tool("validate", {"data": "test"})
    
    mock_client.call_tool.assert_called_once_with(
        session_id="test",
        tool_name="validate",
        args={"data": "test"}
    )
```

## Migration Benefits

### 1. Maintainability
- 2000 line file → 10+ focused modules
- Clear responsibilities
- Easy to find and fix bugs

### 2. Testability
- Unit test each layer independently
- Mock boundaries easily
- Better test coverage

### 3. Performance
- Efficient routing
- Better error handling
- Connection pooling ready

### 4. Extensibility
- Add new handlers easily
- Plug in new transports
- Support new protocols

### 5. Observability
- Comprehensive metrics
- Distributed tracing
- Better debugging

## Success Criteria

1. **No Behavior Changes**: All existing functionality works identically
2. **Performance Enablement**: Infrastructure supports intelligent routing, enabling potential latency reduction of >10% on suitable workloads
3. **Higher Test Coverage**: From 40% to 80%
4. **Cleaner Code**: Average module size < 200 lines
5. **Better Errors**: Specific, actionable error messages

## Summary

This refactoring:
1. **Separates Concerns**: Each module has one job
2. **Enables Testing**: Clean boundaries for mocking
3. **Improves Observability**: Telemetry throughout
4. **Maintains Compatibility**: No breaking changes
5. **Prepares for Scale**: Ready for connection pooling and clustering

The Python side becomes as clean and maintainable as the Elixir side.
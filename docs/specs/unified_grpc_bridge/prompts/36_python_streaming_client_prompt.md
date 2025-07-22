# Prompt: Implement Python Streaming Client for Variable Watching

## Objective
Create Python client code that provides an elegant async iterator interface for watching variables in real-time, with support for filtering, debouncing, and error recovery.

## Context
The Python client complements the gRPC streaming server, enabling DSPy modules and other Python components to react to variable changes in real-time. The implementation must be Pythonic, robust, and easy to use.

## Requirements

### Core Features
1. Async iterator interface for variable watching
2. Automatic reconnection on stream failures
3. Client-side filtering and debouncing
4. Integration with variable cache
5. Type-safe variable updates

### API Design
- Simple: `async for update in session.watch_variables(['temp'])`
- Powerful: Support filtering, debouncing, error handling
- Pythonic: Follow Python async conventions
- Robust: Handle network issues gracefully

## Implementation

### Extend SessionContext

```python
# File: snakepit/priv/python/snakepit_bridge/session_context.py

import asyncio
import time
import logging
from typing import List, Optional, Callable, Any, AsyncIterator, Dict
from dataclasses import dataclass
from datetime import datetime
import grpc

from . import unified_bridge_pb2 as pb2
from . import unified_bridge_pb2_grpc as pb2_grpc
from .serialization import TypeSerializer

logger = logging.getLogger(__name__)


@dataclass
class VariableUpdate:
    """Represents a variable change event."""
    variable_id: str
    variable_name: str
    value: Any
    old_value: Optional[Any]
    metadata: Dict[str, str]
    source: str
    timestamp: datetime
    update_type: str
    
    @property
    def is_initial(self) -> bool:
        """Check if this is an initial value notification."""
        return self.update_type == "initial_value"
    
    @property
    def change_magnitude(self) -> Optional[float]:
        """Calculate change magnitude for numeric types."""
        if self.old_value is None or not isinstance(self.value, (int, float)):
            return None
        if not isinstance(self.old_value, (int, float)):
            return None
        return abs(self.value - self.old_value)


class SessionContext:
    """Extended with streaming support."""
    
    # ... existing methods ...
    
    async def watch_variables(
        self,
        names: List[str],
        include_initial: bool = True,
        filter_fn: Optional[Callable[[str, Any, Any], bool]] = None,
        debounce_ms: int = 0,
        on_error: Optional[Callable[[Exception], None]] = None,
        reconnect: bool = True,
        reconnect_delay_ms: int = 1000
    ) -> AsyncIterator[VariableUpdate]:
        """
        Watch variables for changes via gRPC streaming.
        
        This method returns an async iterator that yields VariableUpdate objects
        whenever watched variables change. The stream automatically handles
        reconnection and error recovery.
        
        Args:
            names: List of variable names to watch
            include_initial: Emit current values immediately (prevents stale reads)
            filter_fn: Optional filter function (name, old_value, new_value) -> bool
            debounce_ms: Minimum milliseconds between updates per variable
            on_error: Optional error callback for non-fatal errors
            reconnect: Automatically reconnect on stream failure
            reconnect_delay_ms: Base delay between reconnection attempts
            
        Yields:
            VariableUpdate objects with change information
            
        Example:
            # Simple watching
            async for update in session.watch_variables(['temperature']):
                print(f"{update.variable_name} = {update.value}")
                
            # With filtering
            def significant_change(name, old, new):
                if name == 'temperature':
                    return abs(new - old) > 0.1
                return True
                
            async for update in session.watch_variables(
                ['temperature', 'pressure'],
                filter_fn=significant_change
            ):
                process_update(update)
                
            # With error handling
            async for update in session.watch_variables(
                ['status'],
                on_error=lambda e: logger.error(f"Stream error: {e}"),
                reconnect=True
            ):
                update_dashboard(update)
        """
        # Validate inputs
        if not names:
            raise ValueError("Must specify at least one variable to watch")
            
        # Convert names to strings
        names = [str(name) for name in names]
        
        # Track reconnection attempts
        reconnect_attempts = 0
        max_reconnect_attempts = 10 if reconnect else 1
        
        while reconnect_attempts < max_reconnect_attempts:
            try:
                # Create watch request
                request = pb2.WatchVariablesRequest(
                    session_id=self.session_id,
                    variable_identifiers=names,
                    include_initial_values=include_initial
                )
                
                # Start streaming
                stream = self.stub.WatchVariables(request)
                
                # Reset reconnection counter on successful connection
                if reconnect_attempts > 0:
                    logger.info(f"Reconnected to variable stream after {reconnect_attempts} attempts")
                reconnect_attempts = 0
                
                # Process stream with debouncing
                debounce_state = {} if debounce_ms > 0 else None
                
                async for update_proto in stream:
                    try:
                        # Process update
                        update = await self._process_stream_update(
                            update_proto,
                            filter_fn,
                            debounce_state,
                            debounce_ms
                        )
                        
                        if update:
                            yield update
                            
                    except Exception as e:
                        # Non-fatal error in processing
                        logger.error(f"Error processing update: {e}")
                        if on_error:
                            on_error(e)
                        # Continue processing stream
                        
            except asyncio.CancelledError:
                # Clean cancellation
                logger.info("Variable watch cancelled")
                raise
                
            except grpc.RpcError as e:
                if e.code() == grpc.StatusCode.CANCELLED:
                    logger.info("Variable watch stream closed")
                    return
                    
                # Stream error - maybe reconnect
                reconnect_attempts += 1
                
                if not reconnect or reconnect_attempts >= max_reconnect_attempts:
                    logger.error(f"Variable watch error: {e}")
                    if on_error:
                        on_error(e)
                    raise
                    
                # Calculate backoff delay
                delay = reconnect_delay_ms * (2 ** min(reconnect_attempts - 1, 5))
                delay = min(delay, 60000)  # Cap at 1 minute
                
                logger.warning(
                    f"Stream disconnected, reconnecting in {delay}ms "
                    f"(attempt {reconnect_attempts}/{max_reconnect_attempts})"
                )
                
                await asyncio.sleep(delay / 1000.0)
                
            except Exception as e:
                # Unexpected error
                logger.error(f"Unexpected error in variable watch: {e}")
                if on_error:
                    on_error(e)
                raise
    
    async def _process_stream_update(
        self,
        update_proto,
        filter_fn: Optional[Callable],
        debounce_state: Optional[Dict],
        debounce_ms: int
    ) -> Optional[VariableUpdate]:
        """Process a single stream update."""
        
        # Skip heartbeats
        if update_proto.update_type == "heartbeat":
            logger.debug("Received heartbeat")
            return None
            
        # Deserialize variable
        try:
            variable = self._deserialize_variable(update_proto.variable)
        except Exception as e:
            logger.error(f"Failed to deserialize variable: {e}")
            return None
            
        var_name = variable['name']
        var_id = update_proto.variable_id
        
        # Apply debouncing
        if debounce_state is not None and debounce_ms > 0:
            now = time.time() * 1000
            last_update = debounce_state.get(var_name, 0)
            
            if now - last_update < debounce_ms:
                logger.debug(f"Debounced update for {var_name}")
                return None
                
            debounce_state[var_name] = now
        
        # Deserialize old value
        old_value = None
        if update_proto.HasField('old_value') and update_proto.old_value.type_url:
            try:
                old_value = self._serializer.deserialize(
                    update_proto.old_value,
                    variable['type']
                )
            except Exception as e:
                logger.error(f"Failed to deserialize old value: {e}")
        
        # Apply filter
        if filter_fn:
            try:
                if not filter_fn(var_name, old_value, variable['value']):
                    logger.debug(f"Filtered update for {var_name}")
                    return None
            except Exception as e:
                logger.error(f"Filter function error: {e}")
                # Default to allowing update on filter error
        
        # Update cache if available
        if self._variable_cache:
            self._variable_cache.set(var_name, variable['value'])
            self._variable_cache.set(var_id, variable['value'])
        
        # Create update object
        update = VariableUpdate(
            variable_id=var_id,
            variable_name=var_name,
            value=variable['value'],
            old_value=old_value,
            metadata=dict(update_proto.update_metadata),
            source=update_proto.update_source,
            timestamp=datetime.fromtimestamp(update_proto.timestamp.seconds),
            update_type=update_proto.update_type
        )
        
        return update
    
    def watch_variable(
        self,
        name: str,
        **kwargs
    ) -> AsyncIterator[VariableUpdate]:
        """
        Convenience method to watch a single variable.
        
        Args:
            name: Variable name to watch
            **kwargs: Additional arguments passed to watch_variables
            
        Returns:
            Async iterator of updates for this variable
        """
        return self.watch_variables([name], **kwargs)
```

### Create Reactive Helpers

```python
# File: snakepit/priv/python/snakepit_bridge/reactive.py

"""
Reactive programming helpers for variable watching.
"""

import asyncio
from typing import AsyncIterator, Callable, List, Optional, Any, Dict
from collections import defaultdict
import logging

from .session_context import SessionContext, VariableUpdate

logger = logging.getLogger(__name__)


class ReactiveVariable:
    """
    A reactive wrapper around a variable that provides convenient access
    and change notifications.
    """
    
    def __init__(
        self,
        session: SessionContext,
        name: str,
        initial_value: Any = None
    ):
        self.session = session
        self.name = name
        self._value = initial_value
        self._listeners: List[Callable] = []
        self._watching = False
        self._watch_task: Optional[asyncio.Task] = None
    
    @property
    def value(self) -> Any:
        """Get current value."""
        return self._value
    
    @value.setter
    def value(self, new_value: Any):
        """Set value (updates remote variable)."""
        asyncio.create_task(self._set_value(new_value))
    
    async def _set_value(self, new_value: Any):
        """Async value setter."""
        try:
            await self.session.set_variable(self.name, new_value)
            # Local value will be updated by watcher
        except Exception as e:
            logger.error(f"Failed to set {self.name}: {e}")
    
    def on_change(self, callback: Callable[[Any, Any], None]):
        """Register a change listener."""
        self._listeners.append(callback)
        
        # Start watching if not already
        if not self._watching:
            self._start_watching()
    
    def _start_watching(self):
        """Start watching the variable."""
        if self._watching:
            return
            
        self._watching = True
        self._watch_task = asyncio.create_task(self._watch_loop())
    
    async def _watch_loop(self):
        """Internal watch loop."""
        try:
            async for update in self.session.watch_variables([self.name]):
                old_value = self._value
                self._value = update.value
                
                # Notify listeners
                for listener in self._listeners:
                    try:
                        listener(old_value, update.value)
                    except Exception as e:
                        logger.error(f"Listener error: {e}")
                        
        except asyncio.CancelledError:
            logger.debug(f"Watch loop cancelled for {self.name}")
            raise
        except Exception as e:
            logger.error(f"Watch loop error for {self.name}: {e}")
            self._watching = False
    
    def close(self):
        """Stop watching and clean up."""
        if self._watch_task:
            self._watch_task.cancel()
        self._watching = False
        self._listeners.clear()


class VariableGroup:
    """
    Manages a group of related variables with coordinated updates.
    """
    
    def __init__(self, session: SessionContext):
        self.session = session
        self._variables: Dict[str, ReactiveVariable] = {}
        self._group_listeners: List[Callable] = []
        self._watch_task: Optional[asyncio.Task] = None
    
    def add_variable(self, name: str, initial_value: Any = None) -> ReactiveVariable:
        """Add a variable to the group."""
        if name in self._variables:
            return self._variables[name]
            
        var = ReactiveVariable(self.session, name, initial_value)
        self._variables[name] = var
        
        # Restart group watching
        if self._watch_task:
            self._restart_watching()
            
        return var
    
    def on_any_change(self, callback: Callable[[str, Any, Any], None]):
        """Register a listener for any variable change in the group."""
        self._group_listeners.append(callback)
        
        if not self._watch_task:
            self._start_group_watching()
    
    def _start_group_watching(self):
        """Start watching all variables in the group."""
        if not self._variables:
            return
            
        self._watch_task = asyncio.create_task(self._group_watch_loop())
    
    async def _group_watch_loop(self):
        """Watch all variables in the group."""
        names = list(self._variables.keys())
        
        try:
            async for update in self.session.watch_variables(names):
                # Update local cache
                if update.variable_name in self._variables:
                    var = self._variables[update.variable_name]
                    var._value = update.value
                
                # Notify group listeners
                for listener in self._group_listeners:
                    try:
                        listener(update.variable_name, update.old_value, update.value)
                    except Exception as e:
                        logger.error(f"Group listener error: {e}")
                        
        except asyncio.CancelledError:
            logger.debug("Group watch loop cancelled")
            raise
        except Exception as e:
            logger.error(f"Group watch loop error: {e}")
    
    def _restart_watching(self):
        """Restart group watching with updated variable list."""
        if self._watch_task:
            self._watch_task.cancel()
        self._start_group_watching()
    
    async def update_many(self, updates: Dict[str, Any]):
        """Update multiple variables atomically."""
        await self.session.update_variables(updates)
    
    def close(self):
        """Stop watching and clean up."""
        if self._watch_task:
            self._watch_task.cancel()
        
        for var in self._variables.values():
            var.close()
        
        self._variables.clear()
        self._group_listeners.clear()


async def watch_for_condition(
    session: SessionContext,
    variables: List[str],
    condition: Callable[[Dict[str, Any]], bool],
    timeout: Optional[float] = None
) -> Dict[str, Any]:
    """
    Watch variables until a condition is met.
    
    Args:
        session: Session context
        variables: Variable names to watch
        condition: Function that receives dict of values and returns bool
        timeout: Optional timeout in seconds
        
    Returns:
        Dict of variable values when condition was met
        
    Example:
        # Wait for temperature to exceed threshold
        values = await watch_for_condition(
            session,
            ['temperature', 'pressure'],
            lambda vals: vals['temperature'] > 100
        )
    """
    current_values = {}
    condition_met = asyncio.Event()
    
    async def check_condition(update: VariableUpdate):
        current_values[update.variable_name] = update.value
        
        # Check if we have all variables
        if all(var in current_values for var in variables):
            if condition(current_values):
                condition_met.set()
    
    # Start watching
    watch_task = asyncio.create_task(
        _condition_watcher(session, variables, check_condition)
    )
    
    try:
        # Wait for condition with timeout
        await asyncio.wait_for(condition_met.wait(), timeout)
        return current_values.copy()
        
    finally:
        watch_task.cancel()
        try:
            await watch_task
        except asyncio.CancelledError:
            pass


async def _condition_watcher(session, variables, check_fn):
    """Helper for watch_for_condition."""
    try:
        async for update in session.watch_variables(variables, include_initial=True):
            await check_fn(update)
    except asyncio.CancelledError:
        raise
    except Exception as e:
        logger.error(f"Condition watcher error: {e}")
```

### Usage Examples

```python
# File: snakepit/priv/python/examples/reactive_example.py

import asyncio
import logging
from snakepit_bridge import SessionContext
from snakepit_bridge.reactive import ReactiveVariable, VariableGroup, watch_for_condition

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def basic_watching_example(session: SessionContext):
    """Basic variable watching example."""
    print("\n=== Basic Watching ===")
    
    # Watch temperature changes
    async for update in session.watch_variables(['temperature']):
        print(f"Temperature changed: {update.old_value}°C -> {update.value}°C")
        print(f"  Change magnitude: {update.change_magnitude}°C")
        print(f"  Source: {update.source}")
        
        if update.value > 30:
            print("  WARNING: High temperature!")
            break


async def filtered_watching_example(session: SessionContext):
    """Filtered watching with debouncing."""
    print("\n=== Filtered Watching ===")
    
    def significant_change(name, old, new):
        """Only notify on significant changes."""
        if name == 'temperature' and old is not None:
            return abs(new - old) > 0.5
        return True
    
    # Watch with filter and debouncing
    async for update in session.watch_variables(
        ['temperature', 'humidity'],
        filter_fn=significant_change,
        debounce_ms=1000  # Max 1 update per second
    ):
        print(f"{update.variable_name}: {update.value}")


async def reactive_variable_example(session: SessionContext):
    """Reactive variable wrapper example."""
    print("\n=== Reactive Variable ===")
    
    # Create reactive variable
    temperature = ReactiveVariable(session, 'temperature')
    
    # Register change listener
    def on_temp_change(old, new):
        print(f"Temperature alert: {old} -> {new}")
        if new > 25:
            print("  Turning on cooling...")
    
    temperature.on_change(on_temp_change)
    
    # Update value (async operation)
    temperature.value = 22.5
    
    # Keep watching for 10 seconds
    await asyncio.sleep(10)
    
    temperature.close()


async def variable_group_example(session: SessionContext):
    """Variable group example."""
    print("\n=== Variable Group ===")
    
    # Create a group of related variables
    sensors = VariableGroup(session)
    
    temp = sensors.add_variable('temperature', 20.0)
    humidity = sensors.add_variable('humidity', 50.0)
    pressure = sensors.add_variable('pressure', 1013.0)
    
    # Listen to any change in the group
    def on_sensor_change(name, old, new):
        print(f"Sensor {name}: {old} -> {new}")
        
        # Check if we need to adjust other sensors
        if name == 'temperature' and new > 30:
            print("  High temp detected, checking humidity...")
    
    sensors.on_any_change(on_sensor_change)
    
    # Update multiple sensors atomically
    await sensors.update_many({
        'temperature': 25.0,
        'humidity': 60.0
    })
    
    await asyncio.sleep(10)
    sensors.close()


async def condition_watching_example(session: SessionContext):
    """Watch until condition is met."""
    print("\n=== Condition Watching ===")
    
    # Wait for optimal conditions
    print("Waiting for optimal conditions...")
    
    values = await watch_for_condition(
        session,
        ['temperature', 'humidity', 'pressure'],
        lambda vals: (
            20 <= vals.get('temperature', 0) <= 25 and
            40 <= vals.get('humidity', 0) <= 60 and
            vals.get('pressure', 0) > 1000
        ),
        timeout=30.0
    )
    
    print(f"Optimal conditions reached: {values}")


async def error_recovery_example(session: SessionContext):
    """Demonstrate error recovery."""
    print("\n=== Error Recovery ===")
    
    errors = []
    
    def on_error(e):
        errors.append(e)
        print(f"Stream error: {e}")
    
    # Watch with automatic reconnection
    async for update in session.watch_variables(
        ['status'],
        on_error=on_error,
        reconnect=True,
        reconnect_delay_ms=2000
    ):
        print(f"Status: {update.value}")
        
        # Simulate processing
        await asyncio.sleep(0.1)


async def main():
    """Run all examples."""
    # Connect to bridge
    async with SessionContext.connect('localhost:50051', 'example_session') as session:
        # Define variables for examples
        await session.set_variable('temperature', 20.0)
        await session.set_variable('humidity', 50.0)
        await session.set_variable('pressure', 1013.0)
        await session.set_variable('status', 'online')
        
        # Run examples
        await basic_watching_example(session)
        await filtered_watching_example(session)
        await reactive_variable_example(session)
        await variable_group_example(session)
        await condition_watching_example(session)
        await error_recovery_example(session)


if __name__ == '__main__':
    asyncio.run(main())
```

## Testing

```python
# File: snakepit/priv/python/tests/test_streaming.py

import asyncio
import pytest
from unittest.mock import Mock, AsyncMock

from snakepit_bridge import SessionContext, VariableUpdate
from snakepit_bridge.reactive import ReactiveVariable, watch_for_condition


@pytest.mark.asyncio
async def test_basic_watching(mock_session):
    """Test basic variable watching."""
    updates = []
    
    async for update in mock_session.watch_variables(['test_var']):
        updates.append(update)
        if len(updates) >= 3:
            break
    
    assert len(updates) == 3
    assert all(isinstance(u, VariableUpdate) for u in updates)


@pytest.mark.asyncio
async def test_filtering(mock_session):
    """Test client-side filtering."""
    def filter_fn(name, old, new):
        return new > 10
    
    updates = []
    
    async for update in mock_session.watch_variables(
        ['value'],
        filter_fn=filter_fn
    ):
        updates.append(update)
    
    # Only updates with new > 10 should pass
    assert all(u.value > 10 for u in updates)


@pytest.mark.asyncio
async def test_debouncing(mock_session):
    """Test debouncing of rapid updates."""
    updates = []
    
    async for update in mock_session.watch_variables(
        ['rapid'],
        debounce_ms=100
    ):
        updates.append(update)
    
    # Updates should be spaced at least 100ms apart
    for i in range(1, len(updates)):
        time_diff = (updates[i].timestamp - updates[i-1].timestamp).total_seconds()
        assert time_diff >= 0.1


@pytest.mark.asyncio
async def test_error_handling(mock_session):
    """Test error handling and recovery."""
    errors = []
    
    def on_error(e):
        errors.append(e)
    
    # Simulate stream with errors
    mock_session.stub.WatchVariables = AsyncMock(
        side_effect=[
            Exception("Connection lost"),
            create_mock_stream([])  # Successful reconnect
        ]
    )
    
    updates = []
    
    async for update in mock_session.watch_variables(
        ['test'],
        on_error=on_error,
        reconnect=True
    ):
        updates.append(update)
    
    assert len(errors) == 1
    assert "Connection lost" in str(errors[0])


@pytest.mark.asyncio
async def test_reactive_variable(mock_session):
    """Test ReactiveVariable wrapper."""
    var = ReactiveVariable(mock_session, 'test_var', 10)
    
    changes = []
    
    def on_change(old, new):
        changes.append((old, new))
    
    var.on_change(on_change)
    
    # Simulate updates
    await simulate_variable_update(mock_session, 'test_var', 20)
    await simulate_variable_update(mock_session, 'test_var', 30)
    
    assert len(changes) == 2
    assert changes[0] == (10, 20)
    assert changes[1] == (20, 30)
    
    var.close()


@pytest.mark.asyncio
async def test_watch_for_condition(mock_session):
    """Test conditional watching."""
    # Set up mock to return increasing temperature values
    mock_session._current_values = {'temperature': 15, 'pressure': 1000}
    
    result = await watch_for_condition(
        mock_session,
        ['temperature', 'pressure'],
        lambda vals: vals['temperature'] > 25,
        timeout=5.0
    )
    
    assert result['temperature'] > 25
    assert 'pressure' in result
```

## Performance Considerations

### Stream Efficiency
- Heartbeats keep connections alive without data
- Debouncing reduces unnecessary updates
- Filtering happens client-side to reduce processing

### Memory Management
- No buffering of historical updates
- Cancelled streams are cleaned up immediately
- Weak references for listeners where appropriate

### Concurrency
- Each stream runs independently
- Updates are processed asynchronously
- Multiple variables can be watched efficiently

## Next Steps
After implementing the Python streaming client:
1. Create DSPy integration with reactive variables
2. Add advanced variable types (choice, module)
3. Build reactive examples and patterns
4. Performance test with high-frequency updates
5. Document best practices for reactive programming
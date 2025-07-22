# Prompt: Enhance Python SessionContext with Variables

## Objective
Extend the Python SessionContext to support comprehensive variable management with intelligent caching. This creates a smooth Python API that minimizes gRPC round trips while maintaining consistency.

## Context
The Python SessionContext is the primary interface for DSPy modules to interact with variables. It must provide an intuitive API, efficient caching, and seamless synchronization with the Elixir backend.

## Requirements

### Core Features
1. Variable CRUD operations with Pythonic API
2. Intelligent caching with TTL and invalidation
3. Type validation and constraint enforcement
4. Batch operations for efficiency
5. Context manager support
6. Lazy loading and write-through caching

### Cache Requirements
- TTL-based expiration (default 5 seconds)
- Write-through updates
- Batch prefetching
- Memory-efficient storage
- Thread-safe operations

## Implementation Steps

### 1. Extend SessionContext with Variables

```python
# File: python/unified_bridge/session_context.py

from typing import Any, Dict, List, Optional, Union, TypeVar, Generic
from contextlib import contextmanager
from datetime import datetime, timedelta
from threading import Lock
import weakref
import logging
from dataclasses import dataclass, field
from enum import Enum

from .proto import unified_bridge_pb2 as pb2
from .proto import unified_bridge_pb2_grpc as pb2_grpc
from .types import (
    VariableType, 
    TypeValidator,
    serialize_value,
    deserialize_value,
    validate_constraints
)

logger = logging.getLogger(__name__)

T = TypeVar('T')

@dataclass
class CachedVariable:
    """Cached variable with TTL tracking."""
    variable: pb2.Variable
    cached_at: datetime
    ttl: timedelta = field(default_factory=lambda: timedelta(seconds=5))
    
    @property
    def expired(self) -> bool:
        return datetime.now() > self.cached_at + self.ttl
    
    def refresh(self, variable: pb2.Variable):
        self.variable = variable
        self.cached_at = datetime.now()


class VariableNotFoundError(KeyError):
    """Raised when a variable is not found."""
    pass


class VariableProxy(Generic[T]):
    """
    Proxy object for lazy variable access.
    
    Provides attribute-style access to variable values with
    automatic synchronization.
    """
    
    def __init__(self, context: 'SessionContext', name: str):
        self._context = weakref.ref(context)
        self._name = name
        self._lock = Lock()
    
    @property
    def value(self) -> T:
        """Get the current value."""
        ctx = self._context()
        if ctx is None:
            raise RuntimeError("SessionContext has been destroyed")
        return ctx.get_variable(self._name)
    
    @value.setter
    def value(self, new_value: T):
        """Update the value."""
        ctx = self._context()
        if ctx is None:
            raise RuntimeError("SessionContext has been destroyed")
        ctx.update_variable(self._name, new_value)
    
    def __repr__(self):
        try:
            return f"<Variable {self._name}={self.value}>"
        except:
            return f"<Variable {self._name} (not loaded)>"


class SessionContext:
    """
    Enhanced session context with comprehensive variable support.
    
    Provides intuitive Python API for variable management with
    intelligent caching to minimize gRPC calls.
    """
    
    def __init__(self, stub: pb2_grpc.UnifiedBridgeStub, session_id: str):
        self.stub = stub
        self.session_id = session_id
        self._cache: Dict[str, CachedVariable] = {}
        self._cache_lock = Lock()
        self._default_ttl = timedelta(seconds=5)
        self._proxies: Dict[str, VariableProxy] = {}
        
        # Tool registry remains from Stage 0
        self._tools = {}
        
        logger.info(f"Created SessionContext for session {session_id}")
    
    # Variable Registration
    
    def register_variable(
        self,
        name: str,
        var_type: Union[str, VariableType],
        initial_value: Any,
        constraints: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, str]] = None,
        ttl: Optional[timedelta] = None
    ) -> str:
        """
        Register a new variable in the session.
        
        Args:
            name: Variable name (must be unique in session)
            var_type: Type of the variable
            initial_value: Initial value
            constraints: Type-specific constraints
            metadata: Additional metadata
            ttl: Cache TTL for this variable
            
        Returns:
            Variable ID
            
        Raises:
            ValueError: If type validation fails
            RuntimeError: If registration fails
        """
        # Convert type
        if isinstance(var_type, str):
            var_type = VariableType[var_type.upper()]
        
        # Validate value against type
        validator = TypeValidator.get_validator(var_type)
        validated_value = validator.validate(initial_value)
        
        # Validate constraints if provided
        if constraints:
            validate_constraints(validated_value, var_type, constraints)
        
        # Serialize for gRPC
        value_any = serialize_value(validated_value, var_type)
        constraints_any = {}
        if constraints:
            for k, v in constraints.items():
                constraints_any[k] = serialize_value(v, VariableType.STRING)
        
        request = pb2.RegisterVariableRequest(
            session_id=self.session_id,
            name=name,
            type=var_type.to_proto(),
            initial_value=value_any,
            constraints=constraints_any,
            metadata=metadata or {}
        )
        
        response = self.stub.RegisterVariable(request)
        
        if response.HasField('error'):
            raise RuntimeError(f"Failed to register variable: {response.error}")
        
        var_id = response.variable_id
        logger.info(f"Registered variable {name} ({var_id}) of type {var_type}")
        
        # Invalidate cache for this name
        self._invalidate_cache(name)
        
        return var_id
    
    # Variable Access
    
    def get_variable(self, identifier: str) -> Any:
        """
        Get a variable's value by name or ID.
        
        Uses cache when possible to minimize gRPC calls.
        
        Args:
            identifier: Variable name or ID
            
        Returns:
            The variable's current value
            
        Raises:
            VariableNotFoundError: If variable doesn't exist
        """
        # Check cache first
        with self._cache_lock:
            cached = self._cache.get(identifier)
            if cached and not cached.expired:
                logger.debug(f"Cache hit for variable {identifier}")
                return deserialize_value(
                    cached.variable.value, 
                    VariableType.from_proto(cached.variable.type)
                )
        
        # Cache miss - fetch from server
        logger.debug(f"Cache miss for variable {identifier}")
        
        request = pb2.GetVariableRequest(
            session_id=self.session_id,
            identifier=identifier
        )
        
        response = self.stub.GetVariable(request)
        
        if response.HasField('error'):
            raise VariableNotFoundError(f"Variable not found: {identifier}")
        
        variable = response.variable
        
        # Update cache (by both ID and name)
        with self._cache_lock:
            cached_var = CachedVariable(
                variable=variable,
                cached_at=datetime.now(),
                ttl=self._default_ttl
            )
            self._cache[variable.id] = cached_var
            self._cache[variable.name] = cached_var
        
        # Deserialize and return value
        return deserialize_value(
            variable.value,
            VariableType.from_proto(variable.type)
        )
    
    def update_variable(
        self,
        identifier: str,
        new_value: Any,
        metadata: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Update a variable's value.
        
        Performs write-through caching for consistency.
        
        Args:
            identifier: Variable name or ID
            new_value: New value (will be validated)
            metadata: Additional metadata for the update
            
        Raises:
            ValueError: If value doesn't match type/constraints
            VariableNotFoundError: If variable doesn't exist
        """
        # First get the variable to know its type
        # This also populates the cache
        self.get_variable(identifier)
        
        # Get from cache to access type info
        with self._cache_lock:
            cached = self._cache.get(identifier)
            if not cached:
                raise RuntimeError("Variable should be in cache")
            
            var_type = VariableType.from_proto(cached.variable.type)
        
        # Validate new value
        validator = TypeValidator.get_validator(var_type)
        validated_value = validator.validate(new_value)
        
        # Serialize for gRPC
        value_any = serialize_value(validated_value, var_type)
        
        request = pb2.UpdateVariableRequest(
            session_id=self.session_id,
            identifier=identifier,
            new_value=value_any,
            metadata=metadata or {}
        )
        
        response = self.stub.UpdateVariable(request)
        
        if response.HasField('error'):
            raise RuntimeError(f"Failed to update variable: {response.error}")
        
        # Invalidate cache for write-through consistency
        self._invalidate_cache(identifier)
        
        logger.info(f"Updated variable {identifier}")
    
    def list_variables(self, pattern: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        List all variables or those matching a pattern.
        
        Args:
            pattern: Optional wildcard pattern (e.g., "temp_*")
            
        Returns:
            List of variable info dictionaries
        """
        request = pb2.ListVariablesRequest(
            session_id=self.session_id,
            pattern=pattern or ""
        )
        
        response = self.stub.ListVariables(request)
        
        if response.HasField('error'):
            raise RuntimeError(f"Failed to list variables: {response.error}")
        
        variables = []
        for var in response.variables.variables:
            var_type = VariableType.from_proto(var.type)
            variables.append({
                'id': var.id,
                'name': var.name,
                'type': var_type.value,
                'value': deserialize_value(var.value, var_type),
                'version': var.version,
                'constraints': self._deserialize_constraints(var.constraints),
                'metadata': dict(var.metadata),
                'optimizing': var.optimizing
            })
            
            # Update cache opportunistically
            with self._cache_lock:
                cached_var = CachedVariable(
                    variable=var,
                    cached_at=datetime.now(),
                    ttl=self._default_ttl
                )
                self._cache[var.id] = cached_var
                self._cache[var.name] = cached_var
        
        return variables
    
    def delete_variable(self, identifier: str) -> None:
        """Delete a variable from the session."""
        request = pb2.DeleteVariableRequest(
            session_id=self.session_id,
            identifier=identifier
        )
        
        response = self.stub.DeleteVariable(request)
        
        if response.HasField('error'):
            raise RuntimeError(f"Failed to delete variable: {response.error}")
        
        # Remove from cache
        self._invalidate_cache(identifier)
        
        # Remove proxy if exists
        self._proxies.pop(identifier, None)
        
        logger.info(f"Deleted variable {identifier}")
    
    # Batch Operations
    
    def get_variables(self, identifiers: List[str]) -> Dict[str, Any]:
        """
        Get multiple variables efficiently.
        
        Uses cache and batches uncached requests.
        
        Args:
            identifiers: List of variable names or IDs
            
        Returns:
            Dict mapping identifier to value
        """
        result = {}
        uncached = []
        
        # Check cache first
        with self._cache_lock:
            for identifier in identifiers:
                cached = self._cache.get(identifier)
                if cached and not cached.expired:
                    var_type = VariableType.from_proto(cached.variable.type)
                    result[identifier] = deserialize_value(
                        cached.variable.value,
                        var_type
                    )
                else:
                    uncached.append(identifier)
        
        # Batch fetch uncached
        if uncached:
            request = pb2.GetVariablesRequest(
                session_id=self.session_id,
                identifiers=uncached
            )
            
            response = self.stub.GetVariables(request)
            
            if response.HasField('error'):
                raise RuntimeError(f"Failed to get variables: {response.error}")
            
            # Process found variables
            for var_id, var in response.batch_result.found.items():
                var_type = VariableType.from_proto(var.type)
                value = deserialize_value(var.value, var_type)
                
                # Update result
                result[var_id] = value
                result[var.name] = value
                
                # Update cache
                with self._cache_lock:
                    cached_var = CachedVariable(
                        variable=var,
                        cached_at=datetime.now(),
                        ttl=self._default_ttl
                    )
                    self._cache[var.id] = cached_var
                    self._cache[var.name] = cached_var
            
            # Handle missing
            for missing in response.batch_result.missing:
                if missing in identifiers:
                    raise VariableNotFoundError(f"Variable not found: {missing}")
        
        return result
    
    def update_variables(
        self,
        updates: Dict[str, Any],
        atomic: bool = False,
        metadata: Optional[Dict[str, str]] = None
    ) -> Dict[str, Union[bool, str]]:
        """
        Update multiple variables efficiently.
        
        Args:
            updates: Dict mapping identifier to new value
            atomic: If True, all updates must succeed
            metadata: Metadata for all updates
            
        Returns:
            Dict mapping identifier to success/error
        """
        # First, get all variables to know their types
        var_info = self.get_variables(list(updates.keys()))
        
        # Prepare updates with proper serialization
        serialized_updates = {}
        for identifier, new_value in updates.items():
            # Get variable type from cache
            with self._cache_lock:
                cached = self._cache.get(identifier)
                if not cached:
                    continue
                var_type = VariableType.from_proto(cached.variable.type)
            
            # Validate and serialize
            validator = TypeValidator.get_validator(var_type)
            validated = validator.validate(new_value)
            serialized_updates[identifier] = serialize_value(validated, var_type)
        
        request = pb2.UpdateVariablesRequest(
            session_id=self.session_id,
            updates=serialized_updates,
            atomic=atomic,
            metadata=metadata or {}
        )
        
        response = self.stub.UpdateVariables(request)
        
        if response.HasField('error'):
            raise RuntimeError(f"Failed to update variables: {response.error}")
        
        # Process results
        results = {}
        for identifier, update_result in response.results.items():
            if update_result.HasField('success'):
                results[identifier] = True
                # Invalidate cache
                self._invalidate_cache(identifier)
            else:
                results[identifier] = update_result.error
        
        return results
    
    # Pythonic Access Patterns
    
    def __getitem__(self, name: str) -> Any:
        """Allow dict-style access: value = ctx['temperature']"""
        return self.get_variable(name)
    
    def __setitem__(self, name: str, value: Any):
        """Allow dict-style updates: ctx['temperature'] = 0.8"""
        try:
            self.update_variable(name, value)
        except VariableNotFoundError:
            # Auto-register if doesn't exist
            var_type = TypeValidator.infer_type(value)
            self.register_variable(name, var_type, value)
    
    def __contains__(self, name: str) -> bool:
        """Check if variable exists: 'temperature' in ctx"""
        try:
            self.get_variable(name)
            return True
        except VariableNotFoundError:
            return False
    
    @property
    def v(self) -> 'VariableNamespace':
        """
        Attribute-style access to variables.
        
        Example:
            ctx.v.temperature = 0.8
            print(ctx.v.temperature)
        """
        return VariableNamespace(self)
    
    def variable(self, name: str) -> VariableProxy:
        """
        Get a variable proxy for repeated access.
        
        The proxy provides efficient access to a single variable.
        """
        if name not in self._proxies:
            self._proxies[name] = VariableProxy(self, name)
        return self._proxies[name]
    
    @contextmanager
    def batch_updates(self):
        """
        Context manager for batched updates.
        
        Example:
            with ctx.batch_updates() as batch:
                batch['var1'] = 10
                batch['var2'] = 20
                batch['var3'] = 30
        """
        batch = BatchUpdater(self)
        yield batch
        batch.commit()
    
    # Cache Management
    
    def set_cache_ttl(self, ttl: timedelta):
        """Set default cache TTL for variables."""
        self._default_ttl = ttl
    
    def clear_cache(self):
        """Clear all cached variables."""
        with self._cache_lock:
            self._cache.clear()
        logger.info("Cleared variable cache")
    
    def _invalidate_cache(self, identifier: str):
        """Invalidate cache entry for a variable."""
        with self._cache_lock:
            # Try to remove by identifier
            self._cache.pop(identifier, None)
            
            # Also check if it's cached by the other key
            to_remove = []
            for key, cached in self._cache.items():
                if cached.variable.id == identifier or cached.variable.name == identifier:
                    to_remove.append(key)
            
            for key in to_remove:
                self._cache.pop(key, None)
    
    def _deserialize_constraints(self, constraints_any: Dict[str, Any]) -> Dict[str, Any]:
        """Deserialize constraint values."""
        result = {}
        for key, value_any in constraints_any.items():
            try:
                result[key] = deserialize_value(value_any, VariableType.STRING)
            except:
                result[key] = None
        return result
    
    # Existing tool methods remain...
    
    def register_tool(self, tool_class):
        """Register a tool (from Stage 0)."""
        # Implementation remains from Stage 0
        pass
    
    def call_tool(self, tool_name: str, **kwargs):
        """Call a tool (from Stage 0)."""
        # Implementation remains from Stage 0
        pass


class VariableNamespace:
    """
    Namespace for attribute-style variable access.
    
    Provides ctx.v.variable_name syntax.
    """
    
    def __init__(self, context: SessionContext):
        self._context = weakref.ref(context)
    
    def __getattr__(self, name: str) -> Any:
        ctx = self._context()
        if ctx is None:
            raise RuntimeError("SessionContext has been destroyed")
        return ctx.get_variable(name)
    
    def __setattr__(self, name: str, value: Any):
        if name.startswith('_'):
            super().__setattr__(name, value)
        else:
            ctx = self._context()
            if ctx is None:
                raise RuntimeError("SessionContext has been destroyed")
            try:
                ctx.update_variable(name, value)
            except VariableNotFoundError:
                # Auto-register
                var_type = TypeValidator.infer_type(value)
                ctx.register_variable(name, var_type, value)


class BatchUpdater:
    """Collect updates for batch submission."""
    
    def __init__(self, context: SessionContext):
        self.context = context
        self.updates = {}
    
    def __setitem__(self, name: str, value: Any):
        self.updates[name] = value
    
    def commit(self, atomic: bool = False):
        """Commit all updates."""
        if self.updates:
            return self.context.update_variables(self.updates, atomic=atomic)
        return {}
```

### 2. Create Type System Support

```python
# File: python/unified_bridge/types.py

from enum import Enum
from typing import Any, Dict, Type, Union
import json
import struct
from google.protobuf.any_pb2 import Any as ProtoAny

from .proto import unified_bridge_pb2 as pb2


class VariableType(Enum):
    """Variable types matching the protobuf definition."""
    FLOAT = "float"
    INTEGER = "integer"
    STRING = "string"
    BOOLEAN = "boolean"
    CHOICE = "choice"
    MODULE = "module"
    EMBEDDING = "embedding"
    TENSOR = "tensor"
    
    def to_proto(self) -> pb2.VariableType:
        """Convert to protobuf enum."""
        mapping = {
            VariableType.FLOAT: pb2.TYPE_FLOAT,
            VariableType.INTEGER: pb2.TYPE_INTEGER,
            VariableType.STRING: pb2.TYPE_STRING,
            VariableType.BOOLEAN: pb2.TYPE_BOOLEAN,
            VariableType.CHOICE: pb2.TYPE_CHOICE,
            VariableType.MODULE: pb2.TYPE_MODULE,
            VariableType.EMBEDDING: pb2.TYPE_EMBEDDING,
            VariableType.TENSOR: pb2.TYPE_TENSOR,
        }
        return mapping[self]
    
    @classmethod
    def from_proto(cls, proto_type: pb2.VariableType) -> 'VariableType':
        """Create from protobuf enum."""
        mapping = {
            pb2.TYPE_FLOAT: cls.FLOAT,
            pb2.TYPE_INTEGER: cls.INTEGER,
            pb2.TYPE_STRING: cls.STRING,
            pb2.TYPE_BOOLEAN: cls.BOOLEAN,
            pb2.TYPE_CHOICE: cls.CHOICE,
            pb2.TYPE_MODULE: cls.MODULE,
            pb2.TYPE_EMBEDDING: cls.EMBEDDING,
            pb2.TYPE_TENSOR: cls.TENSOR,
        }
        return mapping.get(proto_type, cls.STRING)


class TypeValidator:
    """Base class for type validators."""
    
    @staticmethod
    def validate(value: Any) -> Any:
        """Validate and potentially convert value."""
        raise NotImplementedError
    
    @staticmethod
    def validate_constraints(value: Any, constraints: Dict[str, Any]) -> None:
        """Validate value against constraints."""
        pass
    
    @classmethod
    def get_validator(cls, var_type: VariableType) -> Type['TypeValidator']:
        """Get validator for a type."""
        validators = {
            VariableType.FLOAT: FloatValidator,
            VariableType.INTEGER: IntegerValidator,
            VariableType.STRING: StringValidator,
            VariableType.BOOLEAN: BooleanValidator,
        }
        return validators.get(var_type, StringValidator)
    
    @classmethod
    def infer_type(cls, value: Any) -> VariableType:
        """Infer type from a Python value."""
        if isinstance(value, bool):
            return VariableType.BOOLEAN
        elif isinstance(value, int):
            return VariableType.INTEGER
        elif isinstance(value, float):
            return VariableType.FLOAT
        else:
            return VariableType.STRING


class FloatValidator(TypeValidator):
    """Validator for float type."""
    
    @staticmethod
    def validate(value: Any) -> float:
        if isinstance(value, (int, float)):
            return float(value)
        elif value in ('inf', 'Infinity'):
            return float('inf')
        elif value in ('-inf', '-Infinity'):
            return float('-inf')
        elif value in ('nan', 'NaN'):
            return float('nan')
        else:
            raise ValueError(f"Cannot convert {value} to float")
    
    @staticmethod
    def validate_constraints(value: float, constraints: Dict[str, Any]) -> None:
        if 'min' in constraints and value < constraints['min']:
            raise ValueError(f"Value {value} below minimum {constraints['min']}")
        if 'max' in constraints and value > constraints['max']:
            raise ValueError(f"Value {value} above maximum {constraints['max']}")


class IntegerValidator(TypeValidator):
    """Validator for integer type."""
    
    @staticmethod
    def validate(value: Any) -> int:
        if isinstance(value, bool):
            raise ValueError("Boolean cannot be converted to integer")
        elif isinstance(value, int):
            return value
        elif isinstance(value, float):
            if value.is_integer():
                return int(value)
            else:
                raise ValueError(f"Float {value} is not a whole number")
        else:
            raise ValueError(f"Cannot convert {value} to integer")
    
    @staticmethod
    def validate_constraints(value: int, constraints: Dict[str, Any]) -> None:
        if 'min' in constraints and value < constraints['min']:
            raise ValueError(f"Value {value} below minimum {constraints['min']}")
        if 'max' in constraints and value > constraints['max']:
            raise ValueError(f"Value {value} above maximum {constraints['max']}")


class StringValidator(TypeValidator):
    """Validator for string type."""
    
    @staticmethod
    def validate(value: Any) -> str:
        return str(value)
    
    @staticmethod
    def validate_constraints(value: str, constraints: Dict[str, Any]) -> None:
        length = len(value)
        if 'min_length' in constraints and length < constraints['min_length']:
            raise ValueError(f"String too short: {length} < {constraints['min_length']}")
        if 'max_length' in constraints and length > constraints['max_length']:
            raise ValueError(f"String too long: {length} > {constraints['max_length']}")
        if 'pattern' in constraints:
            import re
            if not re.match(constraints['pattern'], value):
                raise ValueError(f"String doesn't match pattern: {constraints['pattern']}")
        if 'enum' in constraints and value not in constraints['enum']:
            raise ValueError(f"Value must be one of: {constraints['enum']}")


class BooleanValidator(TypeValidator):
    """Validator for boolean type."""
    
    @staticmethod
    def validate(value: Any) -> bool:
        if isinstance(value, bool):
            return value
        elif isinstance(value, str):
            if value.lower() == 'true':
                return True
            elif value.lower() == 'false':
                return False
        elif isinstance(value, int):
            if value == 1:
                return True
            elif value == 0:
                return False
        raise ValueError(f"Cannot convert {value} to boolean")


def serialize_value(value: Any, var_type: VariableType) -> ProtoAny:
    """Serialize a value to protobuf Any."""
    data = {
        'type': var_type.value,
        'value': value
    }
    
    return ProtoAny(
        type_url=f"type.googleapis.com/unified_bridge.{var_type.value}",
        value=json.dumps(data).encode('utf-8')
    )


def deserialize_value(proto_any: ProtoAny, expected_type: VariableType) -> Any:
    """Deserialize a value from protobuf Any."""
    try:
        data = json.loads(proto_any.value.decode('utf-8'))
        if isinstance(data, dict) and 'value' in data:
            return data['value']
        return data
    except:
        # Fallback to raw value
        return proto_any.value.decode('utf-8')


def validate_constraints(value: Any, var_type: VariableType, constraints: Dict[str, Any]) -> None:
    """Validate a value against type constraints."""
    validator = TypeValidator.get_validator(var_type)
    validator.validate_constraints(value, constraints)
```

### 3. Create Usage Examples

```python
# File: examples/variable_usage.py

from unified_bridge import SessionContext, VariableType
import time


def basic_usage(ctx: SessionContext):
    """Basic variable operations."""
    
    # Register variables
    ctx.register_variable('temperature', VariableType.FLOAT, 0.7,
                         constraints={'min': 0.0, 'max': 2.0})
    
    ctx.register_variable('max_tokens', VariableType.INTEGER, 100,
                         constraints={'min': 1, 'max': 1000})
    
    ctx.register_variable('model_name', VariableType.STRING, 'gpt-3.5-turbo',
                         constraints={'enum': ['gpt-3.5-turbo', 'gpt-4']})
    
    # Get values
    temp = ctx.get_variable('temperature')
    print(f"Temperature: {temp}")
    
    # Update values
    ctx.update_variable('temperature', 0.9)
    
    # Dict-style access
    ctx['max_tokens'] = 200
    print(f"Max tokens: {ctx['max_tokens']}")
    
    # Attribute-style access
    ctx.v.temperature = 0.8
    print(f"Temperature via .v: {ctx.v.temperature}")


def batch_operations(ctx: SessionContext):
    """Efficient batch operations."""
    
    # Register multiple variables
    for i in range(10):
        ctx.register_variable(f'param_{i}', VariableType.FLOAT, i * 0.1)
    
    # Batch get
    names = [f'param_{i}' for i in range(10)]
    values = ctx.get_variables(names)
    print(f"All values: {values}")
    
    # Batch update
    with ctx.batch_updates() as batch:
        for i in range(10):
            batch[f'param_{i}'] = i * 0.2
    
    # Verify updates
    new_values = ctx.get_variables(names)
    print(f"Updated values: {new_values}")


def cache_demonstration(ctx: SessionContext):
    """Show caching behavior."""
    
    ctx.register_variable('cached_var', VariableType.INTEGER, 42)
    
    # First access - cache miss
    start = time.time()
    value1 = ctx['cached_var']
    time1 = time.time() - start
    print(f"First access (cache miss): {time1:.4f}s")
    
    # Second access - cache hit
    start = time.time()
    value2 = ctx['cached_var']
    time2 = time.time() - start
    print(f"Second access (cache hit): {time2:.4f}s")
    print(f"Speedup: {time1/time2:.1f}x")
    
    # Wait for cache expiry
    print("Waiting for cache expiry...")
    time.sleep(6)
    
    # Third access - cache miss again
    start = time.time()
    value3 = ctx['cached_var']
    time3 = time.time() - start
    print(f"Third access (cache expired): {time3:.4f}s")


def variable_proxy_usage(ctx: SessionContext):
    """Use variable proxies for repeated access."""
    
    ctx.register_variable('counter', VariableType.INTEGER, 0)
    
    # Get a proxy
    counter = ctx.variable('counter')
    
    # Repeated access through proxy
    for i in range(5):
        current = counter.value
        counter.value = current + 1
        print(f"Counter: {counter.value}")


def auto_registration(ctx: SessionContext):
    """Demonstrate auto-registration of variables."""
    
    # Setting a non-existent variable auto-registers it
    ctx['auto_var'] = 3.14
    print(f"Auto-registered: {ctx['auto_var']}")
    
    # Type is inferred
    ctx['auto_int'] = 42
    ctx['auto_str'] = "hello"
    ctx['auto_bool'] = True
    
    # List to verify
    variables = ctx.list_variables()
    for var in variables:
        if var['name'].startswith('auto_'):
            print(f"{var['name']}: {var['type']} = {var['value']}")


if __name__ == '__main__':
    # Assume gRPC connection setup
    from grpc import insecure_channel
    from unified_bridge.proto import unified_bridge_pb2_grpc
    
    channel = insecure_channel('localhost:50051')
    stub = unified_bridge_pb2_grpc.UnifiedBridgeStub(channel)
    
    ctx = SessionContext(stub, 'demo_session')
    
    print("=== Basic Usage ===")
    basic_usage(ctx)
    
    print("\n=== Batch Operations ===")
    batch_operations(ctx)
    
    print("\n=== Cache Demonstration ===")
    cache_demonstration(ctx)
    
    print("\n=== Variable Proxy ===")
    variable_proxy_usage(ctx)
    
    print("\n=== Auto Registration ===")
    auto_registration(ctx)
```

## Performance Optimizations

1. **Cache Strategy**:
   - TTL-based expiration (configurable)
   - Write-through for consistency
   - Opportunistic caching during list operations
   - Thread-safe with minimal locking

2. **Batch Operations**:
   - Reduce round trips for bulk operations
   - Efficient serialization
   - Atomic update support

3. **Lazy Loading**:
   - Variable proxies for repeated access
   - Namespace objects avoid unnecessary loads

## Design Principles

1. **Pythonic API**: Natural Python patterns (dict, attributes)
2. **Type Safety**: Validation at boundaries
3. **Performance**: Smart caching, batch operations
4. **Flexibility**: Multiple access patterns
5. **Error Handling**: Clear, actionable errors

## Files to Create/Modify

1. Modify: `python/unified_bridge/session_context.py`
2. Create: `python/unified_bridge/types.py`
3. Create: `examples/variable_usage.py`
4. Update: `python/unified_bridge/__init__.py` to export new types

## Next Steps

After implementing the Python SessionContext:
1. Test cache effectiveness
2. Verify type validation
3. Benchmark batch operations
4. Create integration tests (next prompt)
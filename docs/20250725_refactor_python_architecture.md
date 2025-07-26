# Python Architecture Redesign - Composable Bridge System

**Date:** July 25, 2025  
**Focus:** Designing clean, modular Python architecture for the Snakepit platform

## 🎯 Current Python Architecture Issues

### Problems with Existing Code

#### Scattered Functionality
```python
# Current scattered approach
dspex/priv/python/dspex_adapters/dspy_grpc.py           # DSPy functionality
snakepit/priv/python/snakepit_bridge/dspy_integration.py # More DSPy functionality  
snakepit/priv/python/snakepit_bridge/variable_aware_mixin.py # Variable logic
snakepit/priv/python/snakepit_bridge/session_context.py    # Session management
```

#### Monolithic Adapters
```python
# Current: Everything jammed into one adapter class
class DSPyGRPCHandler(BaseAdapter):
    def check_dspy(self): pass           # DSPy functionality
    def register_variable(self): pass    # Variable functionality  
    def execute_tool(self): pass         # Tool functionality
    def call_elixir_function(self): pass # Bridge functionality
    # 500+ lines of mixed concerns
```

#### Tight Coupling
```python
# Variables depend on DSPy, tools depend on variables, etc.
class VariableAwareMixin:
    def __init__(self, dspy_module, session_context, tool_registry):
        # Everything depends on everything
```

## 🏗️ New Modular Architecture

### Design Principles

1. **Single Responsibility**: Each module has one clear purpose
2. **Loose Coupling**: Modules interact through clean interfaces
3. **High Cohesion**: Related functionality grouped together
4. **Composability**: Modules can be combined in different ways
5. **Extensibility**: Easy to add new capabilities

### Directory Structure

```
snakepit/priv/python/snakepit_bridge/
├── core/                           # Core infrastructure (generic)
│   ├── __init__.py
│   ├── base_adapter.py            # Generic adapter framework
│   ├── session_manager.py         # Session lifecycle management
│   ├── serialization.py           # Data serialization/deserialization
│   ├── grpc_client.py             # gRPC communication layer
│   └── error_handling.py          # Error handling utilities
├── variables/                      # Variable system (domain-agnostic)
│   ├── __init__.py
│   ├── manager.py                 # Variable lifecycle management
│   ├── types/                     # Type system
│   │   ├── __init__.py
│   │   ├── base.py               # Base type interface
│   │   ├── primitives.py         # String, int, float, bool
│   │   ├── collections.py        # List, dict, choice
│   │   └── ml_types.py           # Tensor, embedding (ML-specific)
│   ├── storage.py                # Variable storage backend
│   ├── constraints.py            # Validation and constraints
│   └── sync.py                   # Elixir ↔ Python synchronization
├── tools/                         # Bidirectional tool calling (generic)
│   ├── __init__.py
│   ├── registry.py               # Tool registration and discovery
│   ├── executor.py               # Tool execution engine
│   ├── bridge.py                 # Elixir ↔ Python bridge
│   ├── decorators.py             # @tool decorator and helpers
│   └── exceptions.py             # Tool-specific exceptions
└── dspy/                         # DSPy-specific integrations
    ├── __init__.py
    ├── adapter.py                # DSPy-specific adapter
    ├── integration.py            # Core DSPy integration
    ├── enhanced_workflows.py     # Enhanced predict, CoT, etc.
    ├── schema_discovery.py       # DSPy introspection
    ├── variable_binding.py       # DSPy ↔ Variable integration
    └── tool_integration.py       # DSPy ↔ Tool bridge integration
```

## 🔧 Module Specifications

### Core Infrastructure (`core/`)

#### Base Adapter Framework (`core/base_adapter.py`)
```python
"""
Generic adapter framework that all domain-specific adapters inherit from.
Provides common functionality like session management, error handling, etc.
"""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from .session_manager import SessionManager
from ..variables.manager import VariableManager
from ..tools.registry import ToolRegistry

class BaseAdapter(ABC):
    """Base class for all adapters with common infrastructure."""
    
    def __init__(self):
        self.session_manager = SessionManager()
        self.variable_manager = VariableManager()
        self.tool_registry = ToolRegistry()
        self._initialized = False
    
    def initialize(self, config: Dict[str, Any]) -> None:
        """Initialize the adapter with configuration."""
        self.session_manager.initialize(config.get('session', {}))
        self.variable_manager.initialize(config.get('variables', {}))
        self.tool_registry.initialize(config.get('tools', {}))
        self._initialized = True
    
    @abstractmethod
    def get_supported_commands(self) -> List[str]:
        """Return list of commands this adapter supports."""
        pass
    
    @abstractmethod
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle a specific command."""
        pass
    
    def get_session_context(self, session_id: str) -> 'SessionContext':
        """Get session context for the given session ID."""
        return self.session_manager.get_context(session_id)
```

#### Session Management (`core/session_manager.py`)
```python
"""
Session lifecycle management that's independent of any domain-specific logic.
Handles session creation, cleanup, context switching, etc.
"""

from typing import Dict, Any, Optional
from dataclasses import dataclass
from datetime import datetime, timedelta

@dataclass
class SessionInfo:
    session_id: str
    created_at: datetime
    last_accessed: datetime
    ttl_seconds: int
    metadata: Dict[str, Any]

class SessionContext:
    """Context object that provides access to session-scoped services."""
    
    def __init__(self, session_id: str, variable_manager, tool_registry):
        self.session_id = session_id
        self.variables = variable_manager.get_session_scope(session_id)
        self.tools = tool_registry.get_session_scope(session_id)
        self.metadata = {}
    
    def get_variable(self, name: str) -> Any:
        """Get a variable value from this session."""
        return self.variables.get(name)
    
    def set_variable(self, name: str, value: Any, type_hint: str = None) -> None:
        """Set a variable value in this session."""
        self.variables.set(name, value, type_hint)
    
    def call_tool(self, name: str, **kwargs) -> Any:
        """Call a tool within this session context."""
        return self.tools.execute(name, kwargs)

class SessionManager:
    """Manages session lifecycle and context creation."""
    
    def __init__(self):
        self._sessions: Dict[str, SessionInfo] = {}
        self._contexts: Dict[str, SessionContext] = {}
        self._default_ttl = 3600  # 1 hour
    
    def create_session(self, session_id: str, ttl: int = None) -> SessionContext:
        """Create a new session and return its context."""
        if session_id in self._sessions:
            raise ValueError(f"Session {session_id} already exists")
        
        session_info = SessionInfo(
            session_id=session_id,
            created_at=datetime.now(),
            last_accessed=datetime.now(),
            ttl_seconds=ttl or self._default_ttl,
            metadata={}
        )
        
        self._sessions[session_id] = session_info
        context = SessionContext(session_id, self._variable_manager, self._tool_registry)
        self._contexts[session_id] = context
        
        return context
    
    def get_context(self, session_id: str) -> SessionContext:
        """Get existing session context."""
        if session_id not in self._sessions:
            raise ValueError(f"Session {session_id} not found")
        
        # Update last accessed time
        self._sessions[session_id].last_accessed = datetime.now()
        return self._contexts[session_id]
    
    def cleanup_expired_sessions(self) -> int:
        """Remove expired sessions and return count of cleaned up sessions."""
        now = datetime.now()
        expired_sessions = []
        
        for session_id, info in self._sessions.items():
            if now - info.last_accessed > timedelta(seconds=info.ttl_seconds):
                expired_sessions.append(session_id)
        
        for session_id in expired_sessions:
            self.destroy_session(session_id)
        
        return len(expired_sessions)
```

### Variable System (`variables/`)

#### Variable Manager (`variables/manager.py`)
```python
"""
Domain-agnostic variable management system.
Handles storage, type validation, constraints, and synchronization.
"""

from typing import Dict, Any, Optional, List, Type
from .types.base import BaseType
from .storage import VariableStorage
from .constraints import ConstraintValidator
from .sync import ElixirSync

class VariableManager:
    """Main interface for variable operations."""
    
    def __init__(self):
        self.storage = VariableStorage()
        self.type_registry = TypeRegistry()
        self.constraint_validator = ConstraintValidator()
        self.elixir_sync = ElixirSync()
        self._session_scopes: Dict[str, 'SessionVariableScope'] = {}
    
    def initialize(self, config: Dict[str, Any]) -> None:
        """Initialize variable system."""
        self.storage.initialize(config.get('storage', {}))
        self.type_registry.register_default_types()
        self.elixir_sync.initialize(config.get('sync', {}))
    
    def get_session_scope(self, session_id: str) -> 'SessionVariableScope':
        """Get variable scope for a specific session."""
        if session_id not in self._session_scopes:
            self._session_scopes[session_id] = SessionVariableScope(
                session_id, self.storage, self.type_registry, 
                self.constraint_validator, self.elixir_sync
            )
        return self._session_scopes[session_id]
    
    def register_type(self, type_name: str, type_class: Type[BaseType]) -> None:
        """Register a new variable type."""
        self.type_registry.register(type_name, type_class)

class SessionVariableScope:
    """Variable operations scoped to a specific session."""
    
    def __init__(self, session_id: str, storage, type_registry, validator, sync):
        self.session_id = session_id
        self.storage = storage
        self.type_registry = type_registry
        self.validator = validator
        self.sync = sync
    
    def set(self, name: str, value: Any, type_hint: str = None, 
            constraints: Dict[str, Any] = None) -> None:
        """Set a variable with optional type and constraints."""
        # Infer type if not provided
        if type_hint is None:
            type_hint = self._infer_type(value)
        
        # Get type handler
        type_handler = self.type_registry.get(type_hint)
        if not type_handler:
            raise ValueError(f"Unknown type: {type_hint}")
        
        # Validate value against type
        validated_value = type_handler.validate(value)
        
        # Apply constraints if provided
        if constraints:
            self.validator.validate(validated_value, type_hint, constraints)
        
        # Store the variable
        self.storage.set(self.session_id, name, {
            'value': validated_value,
            'type': type_hint,
            'constraints': constraints or {},
            'metadata': {
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }
        })
        
        # Sync to Elixir if enabled
        self.sync.notify_variable_updated(self.session_id, name, validated_value, type_hint)
    
    def get(self, name: str) -> Any:
        """Get a variable value."""
        variable_data = self.storage.get(self.session_id, name)
        if variable_data is None:
            raise VariableNotFoundError(f"Variable '{name}' not found in session '{self.session_id}'")
        
        return variable_data['value']
    
    def delete(self, name: str) -> bool:
        """Delete a variable."""
        success = self.storage.delete(self.session_id, name)
        if success:
            self.sync.notify_variable_deleted(self.session_id, name)
        return success
    
    def list(self) -> List[Dict[str, Any]]:
        """List all variables in this session."""
        return self.storage.list(self.session_id)
```

#### Type System (`variables/types/`)

##### Base Type Interface (`variables/types/base.py`)
```python
"""
Base interface for all variable types.
Defines the contract that all type handlers must implement.
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, List

class BaseType(ABC):
    """Base interface for variable type handlers."""
    
    @abstractmethod
    def validate(self, value: Any) -> Any:
        """Validate and potentially transform a value for this type."""
        pass
    
    @abstractmethod
    def serialize(self, value: Any) -> bytes:
        """Serialize value to bytes for storage/transport."""
        pass
    
    @abstractmethod
    def deserialize(self, data: bytes) -> Any:
        """Deserialize bytes back to value."""
        pass
    
    @abstractmethod
    def get_constraints_schema(self) -> Dict[str, Any]:
        """Return JSON schema for valid constraints on this type."""
        pass
    
    def validate_constraints(self, value: Any, constraints: Dict[str, Any]) -> None:
        """Validate that value meets the given constraints."""
        # Default implementation - subclasses can override
        pass
    
    def get_type_info(self) -> Dict[str, Any]:
        """Return metadata about this type."""
        return {
            'name': self.__class__.__name__.lower().replace('type', ''),
            'description': self.__doc__ or 'No description available',
            'constraints_schema': self.get_constraints_schema()
        }
```

##### ML-Specific Types (`variables/types/ml_types.py`)
```python
"""
Machine Learning specific variable types like tensors and embeddings.
These types are optimized for ML workloads and include binary serialization.
"""

import numpy as np
import pickle
from typing import Any, Dict, List
from .base import BaseType

class TensorType(BaseType):
    """Type handler for tensor/array data with shape validation."""
    
    def validate(self, value: Any) -> np.ndarray:
        """Convert value to numpy array and validate."""
        if isinstance(value, np.ndarray):
            return value
        elif isinstance(value, (list, tuple)):
            return np.array(value)
        elif isinstance(value, dict) and 'shape' in value and 'data' in value:
            # Handle serialized tensor format
            array = np.array(value['data'])
            return array.reshape(value['shape'])
        else:
            raise ValueError(f"Cannot convert {type(value)} to tensor")
    
    def serialize(self, value: np.ndarray) -> bytes:
        """Serialize numpy array using pickle for efficiency."""
        return pickle.dumps({
            'shape': value.shape,
            'dtype': str(value.dtype),
            'data': value.tobytes()
        })
    
    def deserialize(self, data: bytes) -> np.ndarray:
        """Deserialize bytes back to numpy array."""
        tensor_data = pickle.loads(data)
        array = np.frombuffer(tensor_data['data'], dtype=tensor_data['dtype'])
        return array.reshape(tensor_data['shape'])
    
    def get_constraints_schema(self) -> Dict[str, Any]:
        """Return JSON schema for tensor constraints."""
        return {
            'type': 'object',
            'properties': {
                'shape': {
                    'type': 'array',
                    'items': {'type': 'integer', 'minimum': 1},
                    'description': 'Required tensor shape'
                },
                'dtype': {
                    'type': 'string', 
                    'enum': ['float32', 'float64', 'int32', 'int64'],
                    'description': 'Required data type'
                },
                'min_value': {'type': 'number', 'description': 'Minimum allowed value'},
                'max_value': {'type': 'number', 'description': 'Maximum allowed value'}
            }
        }
    
    def validate_constraints(self, value: np.ndarray, constraints: Dict[str, Any]) -> None:
        """Validate tensor against constraints."""
        if 'shape' in constraints:
            required_shape = tuple(constraints['shape'])
            if value.shape != required_shape:
                raise ValueError(f"Tensor shape {value.shape} doesn't match required {required_shape}")
        
        if 'dtype' in constraints:
            required_dtype = constraints['dtype']
            if str(value.dtype) != required_dtype:
                raise ValueError(f"Tensor dtype {value.dtype} doesn't match required {required_dtype}")
        
        if 'min_value' in constraints:
            if np.any(value < constraints['min_value']):
                raise ValueError(f"Tensor contains values below minimum {constraints['min_value']}")
        
        if 'max_value' in constraints:
            if np.any(value > constraints['max_value']):
                raise ValueError(f"Tensor contains values above maximum {constraints['max_value']}")

class EmbeddingType(BaseType):
    """Type handler for embedding vectors with dimension validation."""
    
    def validate(self, value: Any) -> List[float]:
        """Convert value to float list and validate."""
        if isinstance(value, (list, tuple)):
            return [float(x) for x in value]
        elif isinstance(value, np.ndarray):
            if value.ndim != 1:
                raise ValueError("Embedding must be 1-dimensional")
            return value.tolist()
        else:
            raise ValueError(f"Cannot convert {type(value)} to embedding")
    
    def serialize(self, value: List[float]) -> bytes:
        """Serialize embedding as numpy array for efficiency."""
        return pickle.dumps(np.array(value, dtype=np.float32))
    
    def deserialize(self, data: bytes) -> List[float]:
        """Deserialize bytes back to float list."""
        array = pickle.loads(data)
        return array.tolist()
    
    def get_constraints_schema(self) -> Dict[str, Any]:
        """Return JSON schema for embedding constraints."""
        return {
            'type': 'object',
            'properties': {
                'dimensions': {
                    'type': 'integer',
                    'minimum': 1,
                    'description': 'Required number of dimensions'
                },
                'norm': {
                    'type': 'string',
                    'enum': ['l1', 'l2', 'unit'],
                    'description': 'Required normalization'
                },
                'range': {
                    'type': 'array',
                    'items': {'type': 'number'},
                    'minItems': 2,
                    'maxItems': 2,
                    'description': 'Valid range [min, max] for values'
                }
            }
        }
    
    def validate_constraints(self, value: List[float], constraints: Dict[str, Any]) -> None:
        """Validate embedding against constraints."""
        if 'dimensions' in constraints:
            required_dims = constraints['dimensions']
            if len(value) != required_dims:
                raise ValueError(f"Embedding has {len(value)} dimensions, expected {required_dims}")
        
        if 'range' in constraints:
            min_val, max_val = constraints['range']
            if any(x < min_val or x > max_val for x in value):
                raise ValueError(f"Embedding values must be in range [{min_val}, {max_val}]")
        
        if 'norm' in constraints:
            arr = np.array(value)
            norm_type = constraints['norm']
            
            if norm_type == 'unit':
                norm = np.linalg.norm(arr)
                if not np.isclose(norm, 1.0, atol=1e-6):
                    raise ValueError(f"Embedding must be unit normalized, got norm {norm}")
            elif norm_type == 'l1':
                if not np.isclose(np.sum(np.abs(arr)), 1.0, atol=1e-6):
                    raise ValueError("Embedding must be L1 normalized")
            elif norm_type == 'l2':
                if not np.isclose(np.sum(arr ** 2), 1.0, atol=1e-6):
                    raise ValueError("Embedding must be L2 normalized")
```

### Tool Bridge System (`tools/`)

#### Tool Registry (`tools/registry.py`)
```python
"""
Tool registration and discovery system.
Handles both Python tools and Elixir tools, providing unified interface.
"""

from typing import Dict, Any, Callable, List, Optional
from dataclasses import dataclass
from .decorators import ToolMetadata
from .exceptions import ToolNotFoundError, ToolExecutionError

@dataclass
class ToolInfo:
    name: str
    description: str
    parameters: List[Dict[str, Any]]
    returns: Dict[str, Any]
    language: str  # 'python' or 'elixir'
    handler: Callable
    metadata: Dict[str, Any]

class ToolRegistry:
    """Registry for both Python and Elixir tools."""
    
    def __init__(self):
        self._python_tools: Dict[str, ToolInfo] = {}
        self._elixir_tools: Dict[str, ToolInfo] = {}
        self._session_tools: Dict[str, Dict[str, ToolInfo]] = {}
        self._bridge = None  # Will be set by bridge module
    
    def set_bridge(self, bridge) -> None:
        """Set the bridge for Elixir communication."""
        self._bridge = bridge
    
    def register_python_tool(self, name: str, func: Callable, 
                           metadata: ToolMetadata = None) -> None:
        """Register a Python function as a tool."""
        if metadata is None:
            metadata = getattr(func, '_tool_metadata', ToolMetadata())
        
        tool_info = ToolInfo(
            name=name,
            description=metadata.description,
            parameters=metadata.parameters,
            returns=metadata.returns,
            language='python',
            handler=func,
            metadata=metadata.extra
        )
        
        self._python_tools[name] = tool_info
    
    def register_elixir_tool(self, session_id: str, name: str, 
                           description: str = "", parameters: List[Dict] = None) -> None:
        """Register an Elixir function as a callable tool."""
        if session_id not in self._session_tools:
            self._session_tools[session_id] = {}
        
        tool_info = ToolInfo(
            name=name,
            description=description,
            parameters=parameters or [],
            returns={},
            language='elixir',
            handler=self._create_elixir_handler(session_id, name),
            metadata={}
        )
        
        self._session_tools[session_id][name] = tool_info
    
    def _create_elixir_handler(self, session_id: str, tool_name: str) -> Callable:
        """Create a handler that calls Elixir via the bridge."""
        def elixir_handler(**kwargs):
            if not self._bridge:
                raise ToolExecutionError("Bridge not available for Elixir tool calls")
            return self._bridge.call_elixir_tool(session_id, tool_name, kwargs)
        
        return elixir_handler
    
    def get_tool(self, name: str, session_id: str = None) -> ToolInfo:
        """Get tool by name, checking session-specific tools first."""
        # Check session-specific tools first
        if session_id and session_id in self._session_tools:
            if name in self._session_tools[session_id]:
                return self._session_tools[session_id][name]
        
        # Check global Python tools
        if name in self._python_tools:
            return self._python_tools[name]
        
        raise ToolNotFoundError(f"Tool '{name}' not found")
    
    def list_tools(self, session_id: str = None) -> List[ToolInfo]:
        """List available tools."""
        tools = list(self._python_tools.values())
        
        if session_id and session_id in self._session_tools:
            tools.extend(self._session_tools[session_id].values())
        
        return tools
    
    def execute_tool(self, name: str, params: Dict[str, Any], 
                    session_id: str = None) -> Any:
        """Execute a tool with given parameters."""
        tool_info = self.get_tool(name, session_id)
        
        try:
            # TODO: Add parameter validation here
            return tool_info.handler(**params)
        except Exception as e:
            raise ToolExecutionError(f"Error executing tool '{name}': {str(e)}") from e
```

#### Bidirectional Bridge (`tools/bridge.py`)
```python
"""
Bidirectional communication bridge between Python and Elixir.
Handles calling Elixir functions from Python and vice versa.
"""

import logging
from typing import Dict, Any, Callable
from ..core.grpc_client import GRPCClient
from .registry import ToolRegistry
from .exceptions import BridgeError

logger = logging.getLogger(__name__)

class ToolBridge:
    """Manages bidirectional tool calling between Python and Elixir."""
    
    def __init__(self, grpc_client: GRPCClient):
        self.grpc_client = grpc_client
        self.tool_registry = ToolRegistry()
        self.tool_registry.set_bridge(self)
    
    def register_python_tool_for_elixir(self, name: str, func: Callable) -> None:
        """Register a Python function that Elixir can call."""
        self.tool_registry.register_python_tool(name, func)
        
        # Notify Elixir that this tool is available
        self._notify_elixir_tool_available(name, func)
    
    def call_elixir_tool(self, session_id: str, tool_name: str, params: Dict[str, Any]) -> Any:
        """Call an Elixir function from Python."""
        try:
            # Use gRPC client to call Elixir
            response = self.grpc_client.call("execute_elixir_tool", {
                "session_id": session_id,
                "tool_name": tool_name,
                "parameters": params
            })
            
            if response.get("success"):
                return response.get("result")
            else:
                error = response.get("error", "Unknown error")
                raise BridgeError(f"Elixir tool '{tool_name}' failed: {error}")
                
        except Exception as e:
            logger.error(f"Failed to call Elixir tool '{tool_name}': {e}")
            raise BridgeError(f"Bridge communication failed: {str(e)}") from e
    
    def handle_elixir_tool_call(self, tool_name: str, params: Dict[str, Any], 
                              session_id: str = None) -> Dict[str, Any]:
        """Handle a tool call from Elixir to Python."""
        try:
            result = self.tool_registry.execute_tool(tool_name, params, session_id)
            return {"success": True, "result": result}
        except Exception as e:
            logger.error(f"Python tool '{tool_name}' failed: {e}")
            return {"success": False, "error": str(e)}
    
    def _notify_elixir_tool_available(self, name: str, func: Callable) -> None:
        """Notify Elixir that a Python tool is available."""
        # Extract metadata from function
        metadata = getattr(func, '_tool_metadata', None)
        
        tool_info = {
            "name": name,
            "description": metadata.description if metadata else func.__doc__ or "",
            "parameters": metadata.parameters if metadata else [],
            "language": "python"
        }
        
        try:
            self.grpc_client.call("register_python_tool", {
                "tool_info": tool_info
            })
        except Exception as e:
            logger.warning(f"Failed to notify Elixir about tool '{name}': {e}")
```

### DSPy Integration Module (`dspy/`)

#### DSPy Adapter (`dspy/adapter.py`)
```python
"""
DSPy-specific adapter that uses the generic bridge infrastructure.
Provides DSPy functionality while integrating with variables and tools.
"""

from typing import Dict, Any, List, Optional
from ..core.base_adapter import BaseAdapter  
from ..tools.decorators import tool
from .integration import DSPyIntegration
from .enhanced_workflows import EnhancedWorkflows
from .schema_discovery import SchemaDiscovery
from .variable_binding import VariableBinding

class DSPyAdapter(BaseAdapter):
    """DSPy-specific adapter using modular architecture."""
    
    def __init__(self):
        super().__init__()
        self.dspy_integration = DSPyIntegration()
        self.enhanced_workflows = EnhancedWorkflows()
        self.schema_discovery = SchemaDiscovery()
        self.variable_binding = VariableBinding()
    
    def initialize(self, config: Dict[str, Any]) -> None:
        """Initialize DSPy adapter and all submodules."""
        super().initialize(config)
        
        # Initialize DSPy-specific modules
        self.dspy_integration.initialize(config.get('dspy', {}))
        self.enhanced_workflows.initialize(
            variable_manager=self.variable_manager,
            tool_registry=self.tool_registry
        )
        self.variable_binding.initialize(self.variable_manager)
    
    def get_supported_commands(self) -> List[str]:
        """Return all DSPy-specific commands."""
        return [
            'check_dspy',
            'configure_lm', 
            'call_dspy',
            'discover_dspy_schema',
            'enhanced_predict',
            'enhanced_chain_of_thought',
            'bind_dspy_variable',
            'list_dspy_modules'
        ]
    
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Route command to appropriate handler."""
        if command == 'check_dspy':
            return self.check_dspy()
        elif command == 'configure_lm':
            return self.configure_lm(**args)
        elif command == 'call_dspy':
            return self.call_dspy(**args)
        elif command == 'discover_dspy_schema':
            return self.discover_dspy_schema(**args)
        elif command == 'enhanced_predict':
            return self.enhanced_predict(**args)
        elif command == 'enhanced_chain_of_thought':
            return self.enhanced_chain_of_thought(**args)
        else:
            raise ValueError(f"Unknown command: {command}")
    
    @tool(description="Check if DSPy is available and return version info")
    def check_dspy(self) -> Dict[str, Any]:
        """Check DSPy availability."""
        return self.dspy_integration.check_availability()
    
    @tool(description="Configure DSPy with a language model")
    def configure_lm(self, model_type: str, **kwargs) -> Dict[str, Any]:
        """Configure DSPy language model."""
        return self.dspy_integration.configure_lm(model_type, **kwargs)
    
    @tool(description="Call any DSPy function with introspection")
    def call_dspy(self, module_path: str, function_name: str, 
                  args: List = None, kwargs: Dict = None) -> Dict[str, Any]:
        """Universal DSPy function caller."""
        return self.dspy_integration.call_function(
            module_path, function_name, args or [], kwargs or {}
        )
    
    @tool(description="Discover DSPy module schema and available classes")
    def discover_dspy_schema(self, module_path: str = "dspy") -> Dict[str, Any]:
        """Discover DSPy module structure."""
        return self.schema_discovery.discover_schema(module_path)
    
    @tool(description="Enhanced prediction with tool integration")
    def enhanced_predict(self, signature: str, **inputs) -> Dict[str, Any]:
        """Enhanced DSPy prediction with Elixir tool access."""
        session_context = self.get_session_context(inputs.get('session_id', 'default'))
        return self.enhanced_workflows.enhanced_predict(
            signature, inputs, session_context
        )
    
    @tool(description="Enhanced chain of thought with tool integration")
    def enhanced_chain_of_thought(self, signature: str, **inputs) -> Dict[str, Any]:
        """Enhanced DSPy CoT with Elixir tool access."""
        session_context = self.get_session_context(inputs.get('session_id', 'default'))
        return self.enhanced_workflows.enhanced_chain_of_thought(
            signature, inputs, session_context
        )
```

## 🔗 Integration Points

### How Modules Interact

```python
# Example: Enhanced DSPy workflow using all modules
class EnhancedWorkflows:
    def __init__(self):
        self.variable_manager = None  # Injected during initialization
        self.tool_registry = None     # Injected during initialization
    
    def enhanced_predict(self, signature: str, inputs: Dict, session_context) -> Dict:
        # 1. Get session variables
        temperature = session_context.variables.get('temperature', 0.7)
        
        # 2. Create DSPy predictor with variable binding
        predictor = dspy.Predict(signature=signature)
        
        # 3. Register tools for DSPy to call back to Elixir
        session_context.tools.register_python_tool(
            'validate_reasoning', 
            self._create_validation_tool(session_context)
        )
        
        # 4. Execute with enhanced context
        with dspy.context(lm=dspy.LM(temperature=temperature)):
            result = predictor(**inputs)
        
        # 5. Store results as variables
        session_context.variables.set('last_prediction', result.answer, 'string')
        
        return {"success": True, "result": result}
```

## 📊 Benefits of New Architecture

### Modularity
- ✅ **Core**: Generic infrastructure reusable for any domain
- ✅ **Variables**: Domain-agnostic variable system with ML extensions
- ✅ **Tools**: Generic bidirectional calling with any language
- ✅ **DSPy**: Domain-specific integration using generic components

### Composability  
- ✅ **Mix and Match**: Use variables without DSPy, tools without variables, etc.
- ✅ **Extension Points**: Easy to add new variable types, tools, or integrations
- ✅ **Clean Interfaces**: Each module exposes clear API boundaries

### Maintainability
- ✅ **Single Responsibility**: Each module has one clear purpose
- ✅ **Loose Coupling**: Modules communicate through defined interfaces
- ✅ **Testability**: Each module can be tested independently

### Performance
- ✅ **Optimized Types**: Binary serialization for large data (tensors, embeddings)
- ✅ **Efficient Communication**: Minimal gRPC overhead with smart batching
- ✅ **Resource Management**: Proper cleanup and session lifecycle

This modular Python architecture provides a solid foundation for the Snakepit platform while maintaining clean separation of concerns and enabling easy extension for future use cases.
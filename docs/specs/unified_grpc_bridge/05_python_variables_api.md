# Python Variables API Specification

## Overview

This document specifies the Python-side API for the Variables feature within the unified gRPC Bridge. The API provides intuitive access to variables stored in Elixir sessions, with automatic type conversion, caching, and real-time updates.

## Core Classes

### SessionContext Variable Methods

The `SessionContext` class provides all variable-related functionality.

#### Variable Retrieval

```python
async def get_variable(
    self, 
    name: str, 
    default: Any = None,
    bypass_cache: bool = False
) -> Any:
    """
    Retrieves a variable value from the session.
    
    Args:
        name: Variable name or ID to retrieve
        default: Default value if variable not found (None raises KeyError)
        bypass_cache: Force fetch from server, ignoring local cache
    
    Returns:
        The variable value with proper Python type
        
    Raises:
        KeyError: If variable not found and no default provided
        TypeError: If server returns incompatible type
        grpc.RpcError: On communication errors
        
    Examples:
        # Simple retrieval
        temperature = await session.get_variable('temperature')
        
        # With default value
        max_tokens = await session.get_variable('max_tokens', default=256)
        
        # Force server fetch
        current_temp = await session.get_variable('temperature', bypass_cache=True)
        
        # Type-specific returns
        model_name = await session.get_variable('model')  # Returns string
        threshold = await session.get_variable('threshold')  # Returns float
        choices = await session.get_variable('options')  # Returns list
    """
    
async def get_variables(
    self, 
    names: List[str], 
    defaults: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    Retrieves multiple variables in a single call.
    
    Args:
        names: List of variable names to retrieve
        defaults: Optional dict of default values per variable
        
    Returns:
        Dict mapping variable names to values
        
    Examples:
        # Get multiple variables
        vars = await session.get_variables(['temperature', 'max_tokens', 'model'])
        
        # With defaults
        vars = await session.get_variables(
            ['temp', 'tokens'],
            defaults={'temp': 0.7, 'tokens': 256}
        )
    """
```

#### Variable Updates

```python
async def set_variable(
    self,
    name: str,
    value: Any,
    metadata: Optional[Dict[str, str]] = None,
    create_if_missing: bool = False
) -> None:
    """
    Sets a variable value in the session.
    
    Args:
        name: Variable name or ID
        value: New value (will be type-checked on server)
        metadata: Optional metadata about the update
        create_if_missing: Create variable if it doesn't exist
        
    Raises:
        ValueError: If value fails type validation
        KeyError: If variable not found and create_if_missing is False
        PermissionError: If variable is read-only
        
    Examples:
        # Simple update
        await session.set_variable('temperature', 0.9)
        
        # With metadata
        await session.set_variable(
            'temperature',
            0.9,
            metadata={'reason': 'user_preference', 'source': 'ui'}
        )
        
        # Create if missing (requires type inference)
        await session.set_variable('new_var', 42, create_if_missing=True)
    """

async def update_variables(
    self,
    updates: Dict[str, Any],
    metadata: Optional[Dict[str, str]] = None
) -> Dict[str, Union[bool, str]]:
    """
    Updates multiple variables in a single transaction.
    
    Args:
        updates: Dict mapping variable names to new values
        metadata: Metadata applied to all updates
        
    Returns:
        Dict mapping variable names to success (True) or error message
        
    Examples:
        results = await session.update_variables({
            'temperature': 0.8,
            'max_tokens': 512,
            'model': 'gpt-4'
        })
        
        # Check results
        for var, result in results.items():
            if result is not True:
                print(f"Failed to update {var}: {result}")
    """
```

#### Variable Listing and Inspection

```python
async def list_variables(
    self,
    type_filter: Optional[str] = None,
    source_filter: Optional[str] = None,
    include_values: bool = True
) -> Dict[str, Dict[str, Any]]:
    """
    Lists all variables in the session with their metadata.
    
    Args:
        type_filter: Filter by type ('float', 'integer', 'string', etc.)
        source_filter: Filter by source ('elixir' or 'python')
        include_values: Include current values in response
        
    Returns:
        Dict mapping variable names to their info:
        {
            'temperature': {
                'id': 'var_temperature_12345',
                'type': 'float',
                'value': 0.7,
                'constraints': {'min': 0.0, 'max': 2.0},
                'metadata': {...},
                'source': 'elixir',
                'created_at': datetime(...),
                'updated_at': datetime(...)
            },
            ...
        }
        
    Examples:
        # List all variables
        all_vars = await session.list_variables()
        
        # List only float variables
        float_vars = await session.list_variables(type_filter='float')
        
        # List without values (metadata only)
        var_info = await session.list_variables(include_values=False)
    """

async def get_variable_info(self, name: str) -> Dict[str, Any]:
    """
    Gets detailed information about a specific variable.
    
    Args:
        name: Variable name or ID
        
    Returns:
        Dict with complete variable information including constraints,
        metadata, and optimization history
        
    Examples:
        info = await session.get_variable_info('temperature')
        print(f"Type: {info['type']}")
        print(f"Constraints: {info['constraints']}")
        print(f"Last updated: {info['updated_at']}")
    """
```

#### Variable Observation (Streaming)

```python
async def watch_variable(
    self,
    name: str,
    include_initial: bool = True
) -> AsyncIterator[VariableUpdate]:
    """
    Watches a single variable for changes.
    
    Args:
        name: Variable name to watch
        include_initial: Emit current value immediately
        
    Yields:
        VariableUpdate objects with:
        - variable_id: str
        - value: Any
        - old_value: Any
        - metadata: Dict[str, str]
        - timestamp: datetime
        - source: str
        
    Examples:
        # Watch temperature changes
        async for update in session.watch_variable('temperature'):
            print(f"Temperature changed from {update.old_value} to {update.value}")
            if update.source == 'optimizer':
                print(f"Optimized by: {update.metadata.get('optimizer_id')}")
    """

async def watch_variables(
    self,
    names: List[str],
    include_initial: bool = True
) -> AsyncIterator[VariableUpdate]:
    """
    Watches multiple variables for changes.
    
    Args:
        names: List of variable names to watch
        include_initial: Emit current values immediately
        
    Yields:
        VariableUpdate objects for any changed variable
        
    Examples:
        # Watch multiple variables
        vars_to_watch = ['temperature', 'max_tokens', 'model']
        async for update in session.watch_variables(vars_to_watch):
            print(f"{update.variable_id} changed to {update.value}")
            
            # React to specific changes
            if update.variable_id == 'model':
                await reconfigure_llm(update.value)
    """
```

#### Variable Deletion

```python
async def delete_variable(self, name: str) -> None:
    """
    Deletes a variable from the session.
    
    Args:
        name: Variable name or ID to delete
        
    Raises:
        KeyError: If variable not found
        PermissionError: If variable cannot be deleted
        ValueError: If other variables depend on this one
        
    Examples:
        await session.delete_variable('old_config')
    """
```

### Variable Types and Constraints

```python
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Union
from datetime import datetime

@dataclass
class VariableUpdate:
    """Represents a variable change event."""
    variable_id: str
    value: Any
    old_value: Any
    metadata: Dict[str, str]
    timestamp: datetime
    source: str  # 'elixir' or 'python'

@dataclass
class VariableConstraints:
    """Type-specific constraints for variables."""
    # For numeric types
    min: Optional[float] = None
    max: Optional[float] = None
    step: Optional[float] = None
    
    # For choice types
    choices: Optional[List[Any]] = None
    
    # For string types
    pattern: Optional[str] = None  # Regex pattern
    min_length: Optional[int] = None
    max_length: Optional[int] = None

class VariableTypes:
    """Constants for variable types."""
    FLOAT = 'float'
    INTEGER = 'integer'
    STRING = 'string'
    BOOLEAN = 'boolean'
    CHOICE = 'choice'
    MODULE = 'module'
    LIST = 'list'
    DICT = 'dict'
```

### Variable-Aware Tools

```python
class VariableAwareProxyTool(AsyncGRPCProxyTool):
    """
    Enhanced tool proxy that integrates with session variables.
    """
    
    def __init__(
        self,
        tool_spec: Dict[str, Any],
        session_context: SessionContext,
        variable_bindings: Optional[Dict[str, str]] = None,
        auto_inject_all: bool = False
    ):
        """
        Args:
            tool_spec: Tool specification from server
            session_context: Session context for variable access
            variable_bindings: Map of parameter_name -> variable_name
            auto_inject_all: Inject all variables as _variables parameter
            
        Examples:
            # Create tool with specific bindings
            search_tool = VariableAwareProxyTool(
                spec,
                session,
                variable_bindings={
                    'min_quality': 'quality_threshold',
                    'max_results': 'search_depth'
                }
            )
            
            # Create tool that gets all variables
            analysis_tool = VariableAwareProxyTool(
                spec,
                session,
                auto_inject_all=True
            )
        """
        
    def bind_variable(self, parameter: str, variable_name: str) -> 'VariableAwareProxyTool':
        """
        Dynamically bind a tool parameter to a variable.
        
        Args:
            parameter: Tool parameter name
            variable_name: Session variable name
            
        Returns:
            Self for chaining
            
        Examples:
            tool = session.tools['summarize']
            tool.bind_variable('temperature', 'global_temperature')
            tool.bind_variable('style', 'summary_style')
            
            # Now tool uses these variables automatically
            summary = await tool(text="Long document...")
        """
        
    async def __call__(self, *args, **kwargs) -> Any:
        """
        Execute tool with automatic variable injection.
        
        Variable values are fetched and injected before tool execution.
        Explicitly passed parameters override variable bindings.
        
        Examples:
            # Variables are injected automatically
            results = await search_tool(query="DSPy framework")
            
            # Override a variable binding
            results = await search_tool(
                query="DSPy framework",
                max_results=10  # Overrides variable binding
            )
        """
```

### Variable-Aware DSPy Modules

```python
class VariableAwareMixin:
    """
    Mixin to make any DSPy module variable-aware.
    
    Provides variable access and automatic parameter synchronization.
    """
    
    async def bind_to_variable(self, attribute: str, variable_name: str) -> None:
        """
        Bind a module attribute to a session variable.
        
        Args:
            attribute: Module attribute name (e.g., 'temperature')
            variable_name: Session variable name
            
        Examples:
            # Make ChainOfThought use global temperature
            cot = VariableAwareChainOfThought("question -> reasoning, answer", session)
            await cot.bind_to_variable('temperature', 'global_temperature')
            await cot.bind_to_variable('max_tokens', 'reasoning_tokens')
        """
        
    async def sync_variables(self) -> None:
        """
        Synchronize all bound variables from session.
        
        Called automatically before forward() execution.
        
        Examples:
            # Manual sync if needed
            await module.sync_variables()
        """
        
    async def get_variable(self, name: str) -> Any:
        """
        Get a session variable value.
        
        Convenience method for accessing variables within module logic.
        """
        
    async def set_variable(self, name: str, value: Any) -> None:
        """
        Set a session variable value.
        
        Convenience method for updating variables from module logic.
        """

# Concrete implementations
class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    """Predict module with variable support."""
    pass

class VariableAwareChainOfThought(VariableAwareMixin, dspy.ChainOfThought):
    """ChainOfThought module with variable support."""
    pass

class VariableAwareReAct(VariableAwareMixin, dspy.ReAct):
    """ReAct module with variable support."""
    pass
```

### Module-Type Variables

```python
class ModuleVariableResolver:
    """
    Resolves module-type variables to DSPy module instances.
    """
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        self.module_registry = {
            'Predict': dspy.Predict,
            'ChainOfThought': dspy.ChainOfThought,
            'ReAct': dspy.ReAct,
            'ProgramOfThought': dspy.ProgramOfThought,
            # Add custom modules
        }
        
    async def resolve_module(self, variable_name: str) -> Type[dspy.Module]:
        """
        Resolve a module-type variable to a module class.
        
        Args:
            variable_name: Name of module-type variable
            
        Returns:
            DSPy module class
            
        Examples:
            resolver = ModuleVariableResolver(session)
            
            # Variable 'reasoning_strategy' contains "ChainOfThought"
            ModuleClass = await resolver.resolve_module('reasoning_strategy')
            module = ModuleClass("question -> answer")
        """
        
    async def create_module(
        self,
        variable_name: str,
        *args,
        make_variable_aware: bool = True,
        **kwargs
    ) -> dspy.Module:
        """
        Create a module instance from a module-type variable.
        
        Args:
            variable_name: Name of module-type variable
            *args: Arguments for module constructor
            make_variable_aware: Wrap with variable awareness
            **kwargs: Keyword arguments for module constructor
            
        Returns:
            Module instance, optionally variable-aware
            
        Examples:
            # Create module based on variable
            reasoning = await resolver.create_module(
                'reasoning_strategy',
                "question -> reasoning, answer"
            )
            
            # Module type can change based on variable updates
            async for update in session.watch_variable('reasoning_strategy'):
                reasoning = await resolver.create_module(
                    'reasoning_strategy',
                    "question -> reasoning, answer"
                )
        """
        
    def register_module(self, name: str, module_class: Type[dspy.Module]) -> None:
        """
        Register a custom module type.
        
        Args:
            name: Module name for variable values
            module_class: Module class to instantiate
            
        Examples:
            # Register custom module
            resolver.register_module('CustomReasoner', MyCustomModule)
            
            # Now can be used in module variables
            await session.set_variable('reasoning_strategy', 'CustomReasoner')
        """
```

## Usage Examples

### Basic Variable Operations

```python
import asyncio
from dspex_bridge import SessionContext

async def basic_usage():
    # Initialize session
    channel = grpc.aio.insecure_channel('localhost:50051')
    session = SessionContext('session_123', channel)
    await session.initialize()
    
    # Get and set variables
    temperature = await session.get_variable('temperature', default=0.7)
    await session.set_variable('temperature', 0.9)
    
    # Batch operations
    config = await session.get_variables([
        'temperature',
        'max_tokens', 
        'model',
        'reasoning_style'
    ])
    
    # Update multiple
    results = await session.update_variables({
        'temperature': 0.8,
        'max_tokens': 512,
        'reasoning_style': 'detailed'
    })
    
    # List all variables
    all_vars = await session.list_variables()
    for name, info in all_vars.items():
        print(f"{name}: {info['value']} ({info['type']})")
```

### Variable-Aware Tools

```python
async def tool_with_variables():
    # Create variable-aware tool
    search_tool = session.create_variable_aware_tool(
        'web_search',
        variable_bindings={
            'min_quality': 'quality_threshold',
            'max_results': 'search_depth',
            'language': 'target_language'
        }
    )
    
    # Tool automatically uses current variable values
    results = await search_tool(query="DSPy framework tutorial")
    
    # Variables can be updated and affect next call
    await session.set_variable('quality_threshold', 0.9)
    await session.set_variable('search_depth', 10)
    
    # Next call uses new values
    better_results = await search_tool(query="DSPy framework tutorial")
```

### Variable-Aware DSPy Modules

```python
async def dspy_with_variables():
    # Create variable-aware module
    cot = VariableAwareChainOfThought(
        "question -> reasoning, answer",
        session_context=session
    )
    
    # Bind module parameters to variables
    await cot.bind_to_variable('temperature', 'reasoning_temperature')
    await cot.bind_to_variable('max_tokens', 'reasoning_tokens')
    
    # Module automatically syncs before execution
    result = await cot.forward(question="What causes rain?")
    
    # Watch for variable changes
    async def adapt_to_changes():
        async for update in session.watch_variable('reasoning_temperature'):
            print(f"Temperature changed to {update.value}")
            # Module will use new value on next call
```

### Module-Type Variables

```python
async def dynamic_module_selection():
    # Create module resolver
    resolver = ModuleVariableResolver(session)
    
    # Module type determined by variable
    await session.set_variable('qa_strategy', 'ChainOfThought')
    
    # Create module from variable
    qa_module = await resolver.create_module(
        'qa_strategy',
        "question -> answer",
        make_variable_aware=True
    )
    
    # Use the module
    answer = await qa_module.forward(question="What is DSPy?")
    
    # Change strategy
    await session.set_variable('qa_strategy', 'ReAct')
    
    # Create new module with different type
    qa_module = await resolver.create_module(
        'qa_strategy',
        "question -> answer",
        make_variable_aware=True
    )
```

### Real-Time Adaptation

```python
async def adaptive_system():
    # Set up variables
    await session.set_variable('complexity_threshold', 0.7)
    await session.set_variable('simple_model', 'Predict')
    await session.set_variable('complex_model', 'ChainOfThought')
    
    # Create adaptive module
    class AdaptiveQA:
        def __init__(self, session):
            self.session = session
            self.resolver = ModuleVariableResolver(session)
            
        async def answer(self, question):
            # Assess complexity (simplified)
            complexity = len(question.split()) / 10.0
            
            # Choose model based on threshold
            threshold = await self.session.get_variable('complexity_threshold')
            model_var = 'complex_model' if complexity > threshold else 'simple_model'
            
            # Create appropriate module
            module = await self.resolver.create_module(
                model_var,
                "question -> answer"
            )
            
            return await module.forward(question=question)
    
    # Use adaptive system
    qa = AdaptiveQA(session)
    
    # Simple question uses Predict
    answer1 = await qa.answer("What is 2+2?")
    
    # Complex question uses ChainOfThought
    answer2 = await qa.answer("Explain the philosophical implications of consciousness in AI")
    
    # Adjust threshold
    await session.set_variable('complexity_threshold', 0.5)
    # Now more questions will use complex model
```

## Error Handling

```python
# Variable not found
try:
    value = await session.get_variable('nonexistent')
except KeyError:
    print("Variable not found")

# Type validation error
try:
    await session.set_variable('temperature', 'not a number')
except ValueError as e:
    print(f"Invalid value: {e}")

# Read-only variable
try:
    await session.set_variable('system_constant', 42)
except PermissionError:
    print("Cannot modify read-only variable")

# Connection errors
try:
    value = await session.get_variable('temperature')
except grpc.RpcError as e:
    if e.code() == grpc.StatusCode.UNAVAILABLE:
        print("Server unavailable")
    else:
        print(f"RPC error: {e}")
```

## Performance Optimization

### Caching Configuration

```python
# Configure cache TTL
session.set_cache_ttl(2.0)  # 2 second cache

# Disable cache for real-time requirements
session.set_cache_ttl(0)  # No caching

# Selective cache bypass
latest = await session.get_variable('counter', bypass_cache=True)
```

### Batch Operations

```python
# Efficient batch retrieval
variables = await session.get_variables([
    'var1', 'var2', 'var3', 'var4', 'var5'
])

# Efficient batch update
await session.update_variables({
    'var1': 'value1',
    'var2': 'value2',
    'var3': 'value3'
})
```

### Connection Pooling

```python
# Reuse session across operations
async with SessionPool() as pool:
    session = await pool.get_session('session_123')
    # Perform many operations
    # Connection automatically returned to pool
```

## Type Conversion Reference

| Elixir Type | Python Type | Notes |
|-------------|-------------|-------|
| `:float` | `float` | Automatic conversion |
| `:integer` | `int` | Preserves precision |
| `:string` | `str` | UTF-8 encoded |
| `:boolean` | `bool` | Direct mapping |
| `:choice` | `str` | Validated against choices |
| `:module` | `str` | Special handling for module references |
| `:list` | `list` | Recursive type conversion |
| `:map` | `dict` | Keys converted to strings |

## Best Practices

1. **Use descriptive variable names**: `reasoning_temperature` not `temp`
2. **Set appropriate cache TTL**: Balance freshness vs performance
3. **Handle errors gracefully**: Variables may not exist or change type
4. **Use batch operations**: When working with multiple variables
5. **Watch for changes**: In long-running processes
6. **Document constraints**: Make variable constraints clear
7. **Use defaults**: Provide sensible defaults for missing variables
8. **Clean up watchers**: Cancel watch tasks when done
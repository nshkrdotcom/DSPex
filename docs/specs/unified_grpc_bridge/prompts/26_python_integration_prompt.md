# Prompt: Implement Variable-Aware DSPy Modules

## Objective
Create the Python integration layer that makes DSPy modules variable-aware. This includes the `VariableAwareMixin` that enables automatic parameter binding and the `ModuleVariableResolver` for dynamic module selection.

## Context
This integration enables DSPy modules to:
- Automatically sync parameters with DSPex variables
- Support dynamic module selection via module-type variables
- Maintain consistency between Elixir and Python state
- Work seamlessly in the unified bridge architecture

## Requirements

### Core Components
1. VariableAwareMixin for DSPy modules
2. Concrete variable-aware module implementations
3. ModuleVariableResolver for dynamic modules
4. Async/sync compatibility
5. Proper error handling

### Integration Goals
- Zero configuration for basic usage
- Automatic synchronization before execution
- Support for all standard DSPy modules
- Clean async/await patterns

## Implementation

### Create DSPy Integration Module

```python
# File: snakepit/priv/python/snakepit_bridge/dspy_integration.py

"""
Integration layer for making DSPy modules variable-aware.

This module provides the bridge between DSPex.Variables and DSPy modules,
enabling automatic parameter synchronization and dynamic configuration.
"""

import asyncio
import inspect
import logging
from typing import Dict, Any, Optional, Type, Union, List, Callable
from dataclasses import dataclass
from datetime import datetime
import weakref

import dspy
from dspy import Module as DSPyModule

from .session_context import SessionContext
from .exceptions import VariableNotFoundError, BridgeError

logger = logging.getLogger(__name__)


class VariableAwareMixin:
    """
    Mixin to make any DSPy module variable-aware.
    
    When mixed into a DSPy module, it enables:
    - Automatic parameter binding to session variables
    - Dynamic configuration updates
    - Seamless integration with DSPex.Variables
    
    Example:
        class MyPredictor(VariableAwareMixin, dspy.Predict):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                
        predictor = MyPredictor("question -> answer", session_context=ctx)
        await predictor.bind_to_variable('temperature', 'generation_temp')
    """
    
    def __init__(self, *args, session_context: Optional[SessionContext] = None, **kwargs):
        # Extract our custom kwargs before passing to parent
        self._session_context = session_context
        self._variable_bindings: Dict[str, str] = {}
        self._last_sync: Dict[str, Any] = {}
        self._sync_callbacks: List[Callable] = []
        self._auto_sync = kwargs.pop('auto_sync', True)
        
        # Initialize parent class
        super().__init__(*args, **kwargs)
        
        # Set up weak reference to avoid circular references
        if self._session_context:
            self._session_ref = weakref.ref(self._session_context)
        else:
            self._session_ref = None
            
        # Log initialization
        module_name = self.__class__.__name__
        if self._session_context:
            logger.info(
                f"Variable-aware {module_name} initialized with session {session_context.session_id}"
            )
        else:
            logger.debug(f"{module_name} initialized without session context")
    
    @property
    def session_context(self) -> Optional[SessionContext]:
        """Get the session context if available."""
        if self._session_ref:
            return self._session_ref()
        return None
    
    async def bind_to_variable(
        self, 
        attribute: str, 
        variable_name: str,
        sync_callback: Optional[Callable[[str, Any, Any], None]] = None
    ) -> None:
        """
        Bind a module attribute to a session variable.
        
        Args:
            attribute: Module attribute name (e.g., 'temperature')
            variable_name: Session variable name
            sync_callback: Optional callback when value changes
        
        Example:
            await module.bind_to_variable('temperature', 'generation_temperature')
            
            # With callback
            def on_temp_change(attr, old_val, new_val):
                print(f"Temperature changed from {old_val} to {new_val}")
                
            await module.bind_to_variable('temperature', 'temp', on_temp_change)
        """
        ctx = self.session_context
        if not ctx:
            raise RuntimeError("No session context available for variable binding")
        
        # Verify variable exists and get initial value
        try:
            value = await ctx.get_variable(variable_name)
            old_value = getattr(self, attribute, None)
            setattr(self, attribute, value)
            
            self._variable_bindings[attribute] = variable_name
            self._last_sync[attribute] = value
            
            # Call sync callback if provided
            if sync_callback and old_value != value:
                sync_callback(attribute, old_value, value)
            
            # Store callback for future syncs
            if sync_callback:
                self._sync_callbacks.append(sync_callback)
            
            logger.info(
                f"Bound {attribute} to variable {variable_name} "
                f"(initial value: {value})"
            )
            
        except VariableNotFoundError:
            raise ValueError(f"Variable '{variable_name}' not found in session")
        except Exception as e:
            raise BridgeError(f"Failed to bind variable: {e}")
    
    def bind_to_variable_sync(
        self, 
        attribute: str, 
        variable_name: str,
        sync_callback: Optional[Callable] = None
    ) -> None:
        """Synchronous version of bind_to_variable."""
        try:
            asyncio.run(self.bind_to_variable(attribute, variable_name, sync_callback))
        except RuntimeError:
            # Already in async context
            loop = asyncio.get_event_loop()
            loop.create_task(self.bind_to_variable(attribute, variable_name, sync_callback))
    
    async def sync_variables(self) -> Dict[str, tuple]:
        """
        Synchronize all bound variables from the session.
        
        Returns:
            Dict mapping attribute names to (old_value, new_value) tuples
            for attributes that changed.
        """
        ctx = self.session_context
        if not ctx or not self._variable_bindings:
            return {}
        
        changes = {}
        
        for attr, var_name in self._variable_bindings.items():
            try:
                new_value = await ctx.get_variable(var_name)
                old_value = self._last_sync.get(attr)
                
                if new_value != old_value:
                    setattr(self, attr, new_value)
                    self._last_sync[attr] = new_value
                    changes[attr] = (old_value, new_value)
                    
                    # Call sync callbacks
                    for callback in self._sync_callbacks:
                        try:
                            callback(attr, old_value, new_value)
                        except Exception as e:
                            logger.error(f"Sync callback error: {e}")
                    
            except VariableNotFoundError:
                logger.warning(f"Variable {var_name} no longer exists")
            except Exception as e:
                logger.error(f"Error syncing {var_name}: {e}")
        
        if changes:
            logger.debug(f"Synced {len(changes)} variable changes")
            for attr, (old, new) in changes.items():
                logger.debug(f"  {attr}: {old} -> {new}")
                
        return changes
    
    def sync_variables_sync(self) -> Dict[str, tuple]:
        """Synchronous version of sync_variables."""
        try:
            return asyncio.run(self.sync_variables())
        except RuntimeError:
            # Already in async context
            loop = asyncio.get_event_loop()
            future = asyncio.ensure_future(self.sync_variables())
            return loop.run_until_complete(future)
    
    async def get_bound_variable(self, attribute: str) -> Any:
        """Get the current value of a bound variable."""
        if attribute not in self._variable_bindings:
            raise ValueError(f"Attribute {attribute} is not bound to a variable")
        
        ctx = self.session_context
        if not ctx:
            raise RuntimeError("Session context no longer available")
            
        var_name = self._variable_bindings[attribute]
        return await ctx.get_variable(var_name)
    
    def get_bindings(self) -> Dict[str, str]:
        """Get all variable bindings."""
        return self._variable_bindings.copy()
    
    def unbind_variable(self, attribute: str) -> None:
        """Remove a variable binding."""
        if attribute in self._variable_bindings:
            del self._variable_bindings[attribute]
            if attribute in self._last_sync:
                del self._last_sync[attribute]
            logger.info(f"Unbound {attribute}")
    
    def _should_auto_sync(self) -> bool:
        """Check if automatic sync is enabled and needed."""
        return (
            self._auto_sync and 
            self._session_context is not None and 
            len(self._variable_bindings) > 0
        )


# Concrete variable-aware DSPy modules

class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    """
    Predict module with automatic variable synchronization.
    
    Example:
        predictor = VariableAwarePredict(
            "question -> answer",
            session_context=ctx
        )
        await predictor.bind_to_variable('temperature', 'llm_temperature')
        
        # Variables sync automatically before prediction
        result = await predictor.forward_async(question="What is DSPex?")
    """
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        if self._should_auto_sync():
            await self.sync_variables()
        
        # DSPy's forward is synchronous, so we run it in executor
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, 
            self.forward, 
            *args, 
            **kwargs
        )
    
    def forward(self, *args, **kwargs):
        """Override to optionally sync variables before prediction."""
        if self._should_auto_sync() and hasattr(self, '_warned_sync'):
            # For sync usage, warn once about missing auto-sync
            if not self._warned_sync:
                logger.warning(
                    "Using synchronous forward() with variable bindings. "
                    "Consider using forward_async() or calling sync_variables_sync() manually."
                )
                self._warned_sync = True
        
        return super().forward(*args, **kwargs)


class VariableAwareChainOfThought(VariableAwareMixin, dspy.ChainOfThought):
    """ChainOfThought module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        if self._should_auto_sync():
            await self.sync_variables()
            
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            self.forward,
            *args,
            **kwargs
        )


class VariableAwareReAct(VariableAwareMixin, dspy.ReAct):
    """ReAct module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        if self._should_auto_sync():
            await self.sync_variables()
            
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            self.forward,
            *args,
            **kwargs
        )


class VariableAwareProgramOfThought(VariableAwareMixin, dspy.ProgramOfThought):
    """ProgramOfThought module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        if self._should_auto_sync():
            await self.sync_variables()
            
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            self.forward,
            *args,
            **kwargs
        )


# Module factory for dynamic creation

@dataclass
class ModuleSpec:
    """Specification for a DSPy module."""
    name: str
    module_class: Type[DSPyModule]
    variable_aware_class: Optional[Type[DSPyModule]] = None
    requires_context: bool = True


class ModuleVariableResolver:
    """
    Resolves module-type variables to actual DSPy module classes.
    
    This enables dynamic module selection based on variables.
    
    Example:
        # In Elixir:
        DSPex.Variables.defvariable(ctx, :reasoning_module, :module, "ChainOfThought")
        
        # In Python:
        resolver = ModuleVariableResolver(session_context)
        module = await resolver.create_module('reasoning_module', "question -> answer")
    """
    
    # Registry of available modules
    MODULE_REGISTRY: Dict[str, ModuleSpec] = {
        # Standard DSPy modules
        'Predict': ModuleSpec(
            name='Predict',
            module_class=dspy.Predict,
            variable_aware_class=VariableAwarePredict
        ),
        'ChainOfThought': ModuleSpec(
            name='ChainOfThought',
            module_class=dspy.ChainOfThought,
            variable_aware_class=VariableAwareChainOfThought
        ),
        'ChainOfThoughtWithHint': ModuleSpec(
            name='ChainOfThoughtWithHint',
            module_class=dspy.ChainOfThoughtWithHint,
            variable_aware_class=None  # TODO: Create if needed
        ),
        'ReAct': ModuleSpec(
            name='ReAct',
            module_class=dspy.ReAct,
            variable_aware_class=VariableAwareReAct
        ),
        'ProgramOfThought': ModuleSpec(
            name='ProgramOfThought',
            module_class=dspy.ProgramOfThought,
            variable_aware_class=VariableAwareProgramOfThought
        ),
        
        # Aliases
        'COT': ModuleSpec(
            name='COT',
            module_class=dspy.ChainOfThought,
            variable_aware_class=VariableAwareChainOfThought
        ),
    }
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        self._module_cache: Dict[str, Type[DSPyModule]] = {}
    
    async def resolve_module(self, variable_name: str) -> Type[DSPyModule]:
        """
        Resolve a module-type variable to a DSPy module class.
        
        Args:
            variable_name: Name of the module-type variable
            
        Returns:
            DSPy module class
            
        Raises:
            ValueError: If module type is unknown
            VariableNotFoundError: If variable doesn't exist
        """
        # Check cache first
        if variable_name in self._module_cache:
            return self._module_cache[variable_name]
        
        # Get module name from variable
        module_name = await self.session_context.get_variable(variable_name)
        
        # Handle string module names
        if isinstance(module_name, str):
            if module_name not in self.MODULE_REGISTRY:
                # Try case-insensitive lookup
                for key in self.MODULE_REGISTRY:
                    if key.lower() == module_name.lower():
                        module_name = key
                        break
                else:
                    raise ValueError(f"Unknown module type: {module_name}")
        
        spec = self.MODULE_REGISTRY[module_name]
        module_class = spec.module_class
        
        # Cache for future use
        self._module_cache[variable_name] = module_class
        
        return module_class
    
    async def create_module(
        self, 
        variable_name: str, 
        *args,
        use_variable_aware: bool = True,
        **kwargs
    ) -> DSPyModule:
        """
        Create a module instance from a module-type variable.
        
        Automatically uses variable-aware version if available.
        
        Args:
            variable_name: Name of the module-type variable
            *args: Arguments for module constructor
            use_variable_aware: Whether to use variable-aware version
            **kwargs: Keyword arguments for module constructor
            
        Returns:
            Module instance
            
        Example:
            module = await resolver.create_module(
                'reasoning_module',
                "question -> answer",
                temperature=0.7
            )
        """
        module_name = await self.session_context.get_variable(variable_name)
        
        if module_name not in self.MODULE_REGISTRY:
            raise ValueError(f"Unknown module type: {module_name}")
            
        spec = self.MODULE_REGISTRY[module_name]
        
        # Choose implementation
        if use_variable_aware and spec.variable_aware_class:
            module_class = spec.variable_aware_class
            # Add session context if not provided
            if 'session_context' not in kwargs and spec.requires_context:
                kwargs['session_context'] = self.session_context
            logger.info(f"Creating variable-aware {module_name}")
        else:
            module_class = spec.module_class
            logger.info(f"Creating standard {module_name}")
        
        # Create instance
        try:
            return module_class(*args, **kwargs)
        except Exception as e:
            logger.error(f"Failed to create {module_name}: {e}")
            raise
    
    @classmethod
    def register_module(
        cls, 
        name: str, 
        module_class: Type[DSPyModule],
        variable_aware_class: Optional[Type[DSPyModule]] = None
    ) -> None:
        """Register a custom module type."""
        cls.MODULE_REGISTRY[name] = ModuleSpec(
            name=name,
            module_class=module_class,
            variable_aware_class=variable_aware_class
        )
        logger.info(f"Registered module type: {name}")
    
    def get_available_modules(self) -> List[str]:
        """Get list of available module types."""
        return sorted(self.MODULE_REGISTRY.keys())


# Convenience functions

async def create_variable_aware_module(
    session_context: SessionContext,
    module_type: Union[str, Type[DSPyModule]],
    *args,
    variable_bindings: Optional[Dict[str, str]] = None,
    **kwargs
) -> DSPyModule:
    """
    Convenience function to create a variable-aware module.
    
    Args:
        session_context: Session context for variables
        module_type: Module type name or class
        *args: Module constructor arguments
        variable_bindings: Optional dict of attribute -> variable_name bindings
        **kwargs: Module constructor keyword arguments
        
    Returns:
        Variable-aware module instance
        
    Example:
        module = await create_variable_aware_module(
            ctx,
            "ChainOfThought",
            "question -> answer",
            variable_bindings={
                'temperature': 'llm_temperature',
                'max_tokens': 'generation_max_tokens'
            }
        )
    """
    # Determine module class
    if isinstance(module_type, str):
        if module_type not in ModuleVariableResolver.MODULE_REGISTRY:
            raise ValueError(f"Unknown module type: {module_type}")
        spec = ModuleVariableResolver.MODULE_REGISTRY[module_type]
        module_class = spec.variable_aware_class or spec.module_class
    else:
        module_class = module_type
    
    # Add session context
    kwargs['session_context'] = session_context
    
    # Create instance
    module = module_class(*args, **kwargs)
    
    # Apply variable bindings
    if variable_bindings:
        for attr, var_name in variable_bindings.items():
            await module.bind_to_variable(attr, var_name)
    
    return module
```

### Create Exception Types

```python
# File: snakepit/priv/python/snakepit_bridge/exceptions.py

"""
Custom exceptions for the snakepit bridge.
"""


class BridgeError(Exception):
    """Base exception for bridge-related errors."""
    pass


class VariableNotFoundError(BridgeError):
    """Raised when a variable is not found in the session."""
    def __init__(self, variable_name: str):
        self.variable_name = variable_name
        super().__init__(f"Variable not found: {variable_name}")


class SessionError(BridgeError):
    """Raised when there's a session-related error."""
    pass


class ValidationError(BridgeError):
    """Raised when variable validation fails."""
    pass
```

### Create Usage Examples

```python
# File: examples/variable_aware_dspy.py

"""
Examples of using variable-aware DSPy modules.
"""

import asyncio
import logging
from typing import Dict, Any

import dspy
from snakepit_bridge import SessionContext
from snakepit_bridge.dspy_integration import (
    VariableAwareChainOfThought,
    ModuleVariableResolver,
    create_variable_aware_module
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def basic_variable_binding(ctx: SessionContext):
    """Example of basic variable binding."""
    print("\n=== Basic Variable Binding ===")
    
    # Create a variable-aware module
    cot = VariableAwareChainOfThought(
        "question -> reasoning, answer",
        session_context=ctx
    )
    
    # Bind module parameters to variables
    await cot.bind_to_variable('temperature', 'llm_temperature')
    await cot.bind_to_variable('max_tokens', 'generation_max_tokens')
    
    # Variables automatically sync before execution
    result = await cot.forward_async(
        question="What are the key benefits of DSPex?"
    )
    
    print(f"Answer: {result.answer}")
    print(f"Current temperature: {cot.temperature}")
    
    # Update variable in Elixir side
    # ctx.set_variable('llm_temperature', 0.9)
    
    # Next execution will use new value
    result2 = await cot.forward_async(
        question="Explain variable synchronization."
    )
    print(f"Updated temperature: {cot.temperature}")


async def dynamic_module_selection(ctx: SessionContext):
    """Example of dynamic module selection via variables."""
    print("\n=== Dynamic Module Selection ===")
    
    # Assume Elixir has set a module-type variable
    # DSPex.Variables.defvariable(ctx, :reasoning_strategy, :module, "ChainOfThought")
    
    resolver = ModuleVariableResolver(ctx)
    
    # Create module based on variable value
    module = await resolver.create_module(
        'reasoning_strategy',
        "question -> answer",
        temperature=0.7
    )
    
    print(f"Created module: {module.__class__.__name__}")
    
    # Use the dynamically selected module
    result = await module.forward_async(
        question="How does dynamic module selection work?"
    )
    print(f"Answer: {result.answer}")
    
    # Change strategy in Elixir
    # DSPex.Variables.set(ctx, :reasoning_strategy, "ReAct")
    
    # Create new module with updated strategy
    new_module = await resolver.create_module(
        'reasoning_strategy',
        "question -> action, answer"
    )
    print(f"New module: {new_module.__class__.__name__}")


async def sync_callbacks(ctx: SessionContext):
    """Example of using sync callbacks."""
    print("\n=== Sync Callbacks ===")
    
    # Track temperature changes
    temperature_history = []
    
    def on_temperature_change(attr: str, old_val: Any, new_val: Any):
        temperature_history.append({
            'timestamp': asyncio.get_event_loop().time(),
            'old': old_val,
            'new': new_val
        })
        print(f"Temperature changed: {old_val} -> {new_val}")
    
    # Create module with callback
    predictor = await create_variable_aware_module(
        ctx,
        "Predict",
        "text -> summary",
        variable_bindings={'temperature': 'llm_temperature'}
    )
    
    # Add callback
    predictor._sync_callbacks.append(on_temperature_change)
    
    # Simulate temperature changes
    for temp in [0.5, 0.7, 0.9]:
        await ctx.set_variable('llm_temperature', temp)
        await predictor.sync_variables()
        
        result = await predictor.forward_async(
            text="DSPex provides seamless integration between Elixir and Python."
        )
    
    print(f"\nTemperature history: {temperature_history}")


async def batch_configuration(ctx: SessionContext):
    """Example of configuring multiple modules with variables."""
    print("\n=== Batch Configuration ===")
    
    # Define a pipeline configuration in variables
    config_vars = {
        'pipeline_temperature': 0.7,
        'pipeline_max_tokens': 256,
        'pipeline_model': 'gpt-4',
        'pipeline_strategy': 'ChainOfThought'
    }
    
    # Set variables (would be done in Elixir)
    for name, value in config_vars.items():
        await ctx.set_variable(name, value)
    
    # Create resolver
    resolver = ModuleVariableResolver(ctx)
    
    # Create pipeline modules
    modules = {}
    
    # Question understanding module
    modules['understand'] = await create_variable_aware_module(
        ctx,
        "Predict",
        "question -> key_concepts",
        variable_bindings={
            'temperature': 'pipeline_temperature',
            'model': 'pipeline_model'
        }
    )
    
    # Reasoning module (dynamic type)
    modules['reason'] = await resolver.create_module(
        'pipeline_strategy',
        "question, key_concepts -> reasoning, answer"
    )
    await modules['reason'].bind_to_variable('temperature', 'pipeline_temperature')
    await modules['reason'].bind_to_variable('max_tokens', 'pipeline_max_tokens')
    
    # Summary module
    modules['summarize'] = await create_variable_aware_module(
        ctx,
        "Predict",
        "answer -> summary",
        variable_bindings={
            'temperature': 'pipeline_temperature'
        }
    )
    
    # Run pipeline
    question = "What are the advantages of functional programming?"
    
    concepts = await modules['understand'].forward_async(question=question)
    answer = await modules['reason'].forward_async(
        question=question,
        key_concepts=concepts.key_concepts
    )
    summary = await modules['summarize'].forward_async(answer=answer.answer)
    
    print(f"Question: {question}")
    print(f"Key concepts: {concepts.key_concepts}")
    print(f"Answer: {answer.answer}")
    print(f"Summary: {summary.summary}")


async def main():
    """Run all examples."""
    # Create mock session context
    # In real usage, this would connect to the gRPC bridge
    from unittest.mock import AsyncMock
    
    ctx = AsyncMock(spec=SessionContext)
    ctx.session_id = "example_session"
    
    # Mock variable storage
    variables = {
        'llm_temperature': 0.7,
        'generation_max_tokens': 256,
        'reasoning_strategy': 'ChainOfThought',
        'pipeline_model': 'gpt-4'
    }
    
    async def get_var(name):
        if name not in variables:
            raise VariableNotFoundError(name)
        return variables[name]
    
    async def set_var(name, value):
        variables[name] = value
        return None
    
    ctx.get_variable = get_var
    ctx.set_variable = set_var
    
    # Run examples
    await basic_variable_binding(ctx)
    await dynamic_module_selection(ctx)
    await sync_callbacks(ctx)
    await batch_configuration(ctx)


if __name__ == "__main__":
    # Configure DSPy (mock for examples)
    dspy.settings.configure(lm=None)  # Would use real LM in practice
    
    asyncio.run(main())
```

## Testing

```python
# File: test/python/test_dspy_integration.py

import asyncio
import pytest
from unittest.mock import Mock, AsyncMock, MagicMock
from typing import Dict, Any

from snakepit_bridge.session_context import SessionContext
from snakepit_bridge.dspy_integration import (
    VariableAwareMixin,
    VariableAwarePredict,
    VariableAwareChainOfThought,
    ModuleVariableResolver,
    create_variable_aware_module
)
from snakepit_bridge.exceptions import VariableNotFoundError


class MockDSPyModule:
    """Mock base DSPy module for testing."""
    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        
    def forward(self, **kwargs):
        return {"result": "mock_forward"}


class TestVariableAwareMixin:
    """Test the VariableAwareMixin functionality."""
    
    @pytest.fixture
    async def mock_session(self):
        """Create a mock session context."""
        session = AsyncMock(spec=SessionContext)
        session.session_id = "test_session"
        
        # Variable storage
        variables = {'temp': 0.7, 'tokens': 256}
        
        async def get_var(name):
            if name not in variables:
                raise VariableNotFoundError(name)
            return variables[name]
            
        async def set_var(name, value):
            variables[name] = value
            
        session.get_variable = get_var
        session.set_variable = set_var
        
        return session
    
    @pytest.fixture
    def TestModule(self):
        """Create a test module class with the mixin."""
        class TestModule(VariableAwareMixin, MockDSPyModule):
            pass
        return TestModule
    
    @pytest.mark.asyncio
    async def test_initialization(self, TestModule, mock_session):
        """Test mixin initialization."""
        module = TestModule("test_arg", session_context=mock_session)
        
        assert module._session_context == mock_session
        assert module._variable_bindings == {}
        assert module._auto_sync is True
        assert module.args == ("test_arg",)
    
    @pytest.mark.asyncio
    async def test_bind_to_variable(self, TestModule, mock_session):
        """Test variable binding."""
        module = TestModule(session_context=mock_session)
        
        # Bind temperature
        await module.bind_to_variable('temperature', 'temp')
        
        assert module.temperature == 0.7
        assert module._variable_bindings['temperature'] == 'temp'
        assert module._last_sync['temperature'] == 0.7
    
    @pytest.mark.asyncio
    async def test_bind_missing_variable(self, TestModule, mock_session):
        """Test binding to non-existent variable."""
        module = TestModule(session_context=mock_session)
        
        with pytest.raises(ValueError, match="not found"):
            await module.bind_to_variable('attr', 'missing')
    
    @pytest.mark.asyncio
    async def test_sync_variables(self, TestModule, mock_session):
        """Test variable synchronization."""
        module = TestModule(session_context=mock_session)
        
        # Bind and get initial values
        await module.bind_to_variable('temperature', 'temp')
        await module.bind_to_variable('max_tokens', 'tokens')
        
        assert module.temperature == 0.7
        assert module.max_tokens == 256
        
        # Change values in session
        await mock_session.set_variable('temp', 0.9)
        await mock_session.set_variable('tokens', 512)
        
        # Sync
        changes = await module.sync_variables()
        
        assert module.temperature == 0.9
        assert module.max_tokens == 512
        assert changes == {
            'temperature': (0.7, 0.9),
            'max_tokens': (256, 512)
        }
    
    @pytest.mark.asyncio
    async def test_sync_callback(self, TestModule, mock_session):
        """Test sync callbacks."""
        module = TestModule(session_context=mock_session)
        
        callback_calls = []
        
        def callback(attr, old_val, new_val):
            callback_calls.append((attr, old_val, new_val))
        
        # Bind with callback
        await module.bind_to_variable('temperature', 'temp', callback)
        
        # Change and sync
        await mock_session.set_variable('temp', 0.8)
        await module.sync_variables()
        
        assert len(callback_calls) == 1
        assert callback_calls[0] == ('temperature', 0.7, 0.8)
    
    @pytest.mark.asyncio
    async def test_unbind_variable(self, TestModule, mock_session):
        """Test unbinding variables."""
        module = TestModule(session_context=mock_session)
        
        await module.bind_to_variable('temperature', 'temp')
        assert 'temperature' in module._variable_bindings
        
        module.unbind_variable('temperature')
        assert 'temperature' not in module._variable_bindings
        assert 'temperature' not in module._last_sync


class TestVariableAwareModules:
    """Test concrete variable-aware module implementations."""
    
    @pytest.fixture
    async def mock_session(self):
        """Create mock session with variables."""
        session = AsyncMock(spec=SessionContext)
        session.session_id = "test"
        
        variables = {'temp': 0.7}
        
        async def get_var(name):
            return variables.get(name, 0.5)
            
        session.get_variable = get_var
        return session
    
    @pytest.mark.asyncio
    async def test_variable_aware_predict(self, mock_session):
        """Test VariableAwarePredict."""
        # Mock dspy.Predict.forward
        with pytest.mock.patch.object(
            VariableAwarePredict, 
            'forward',
            return_value={'answer': 'test'}
        ) as mock_forward:
            
            predictor = VariableAwarePredict(
                "question -> answer",
                session_context=mock_session
            )
            
            await predictor.bind_to_variable('temperature', 'temp')
            
            # Test async forward
            result = await predictor.forward_async(question="test?")
            
            assert result == {'answer': 'test'}
            mock_forward.assert_called_once()


class TestModuleVariableResolver:
    """Test dynamic module resolution."""
    
    @pytest.fixture
    async def resolver_setup(self):
        """Set up resolver with mock session."""
        session = AsyncMock(spec=SessionContext)
        
        variables = {
            'strategy': 'ChainOfThought',
            'predictor': 'Predict'
        }
        
        async def get_var(name):
            if name not in variables:
                raise VariableNotFoundError(name)
            return variables[name]
            
        session.get_variable = get_var
        session.session_id = "test"
        
        resolver = ModuleVariableResolver(session)
        return resolver, session
    
    @pytest.mark.asyncio
    async def test_resolve_module(self, resolver_setup):
        """Test module resolution."""
        resolver, session = resolver_setup
        
        # Mock the registry
        from snakepit_bridge.dspy_integration import ModuleSpec
        resolver.MODULE_REGISTRY['ChainOfThought'] = ModuleSpec(
            name='ChainOfThought',
            module_class=MockDSPyModule,
            variable_aware_class=None
        )
        
        module_class = await resolver.resolve_module('strategy')
        assert module_class == MockDSPyModule
    
    @pytest.mark.asyncio
    async def test_create_module(self, resolver_setup):
        """Test module creation."""
        resolver, session = resolver_setup
        
        # Set up registry
        class MockVariableAware(VariableAwareMixin, MockDSPyModule):
            pass
            
        from snakepit_bridge.dspy_integration import ModuleSpec
        resolver.MODULE_REGISTRY['Predict'] = ModuleSpec(
            name='Predict',
            module_class=MockDSPyModule,
            variable_aware_class=MockVariableAware
        )
        
        # Create module
        module = await resolver.create_module(
            'predictor',
            "test_signature"
        )
        
        assert isinstance(module, MockVariableAware)
        assert module._session_context == session
    
    @pytest.mark.asyncio  
    async def test_unknown_module(self, resolver_setup):
        """Test error on unknown module."""
        resolver, session = resolver_setup
        
        await session.set_variable('bad_module', 'UnknownModule')
        
        with pytest.raises(ValueError, match="Unknown module"):
            await resolver.resolve_module('bad_module')


@pytest.mark.asyncio
async def test_create_variable_aware_module():
    """Test the convenience function."""
    session = AsyncMock(spec=SessionContext)
    session.session_id = "test"
    
    variables = {'temp': 0.8}
    
    async def get_var(name):
        return variables.get(name)
        
    session.get_variable = get_var
    
    # Mock the registry
    from snakepit_bridge.dspy_integration import ModuleVariableResolver, ModuleSpec
    
    class MockModule(VariableAwareMixin, MockDSPyModule):
        pass
    
    ModuleVariableResolver.MODULE_REGISTRY['TestModule'] = ModuleSpec(
        name='TestModule',
        module_class=MockDSPyModule,
        variable_aware_class=MockModule
    )
    
    # Create with bindings
    module = await create_variable_aware_module(
        session,
        "TestModule",
        "test_sig",
        variable_bindings={'temperature': 'temp'}
    )
    
    assert isinstance(module, MockModule)
    assert module.temperature == 0.8
```

## Integration with Elixir

The Python integration works seamlessly with the Elixir side:

```elixir
# In Elixir
{:ok, ctx} = DSPex.Context.start_link()

# Define variables
DSPex.Variables.defvariable(ctx, :llm_temperature, :float, 0.7,
  constraints: %{min: 0.0, max: 2.0}
)
DSPex.Variables.defvariable(ctx, :reasoning_module, :module, "ChainOfThought")

# Variables are accessible in Python
# Python DSPy modules automatically use these values
```

## Design Decisions

1. **Mixin Pattern**: Allows retrofitting existing DSPy modules
2. **Async First**: Native async/await support with sync fallbacks
3. **Weak References**: Avoid circular references with session
4. **Auto Sync**: Configurable automatic synchronization
5. **Type Safety**: Proper type hints throughout

## Performance Considerations

- Variable sync adds ~0.1-1ms overhead
- Batch sync for multiple variables
- Cache module type resolutions
- Async execution avoids blocking

## Next Steps

After implementing Python integration:
1. Test with real DSPy modules
2. Add more variable-aware module types
3. Create comprehensive examples
4. Performance benchmarking
5. Create integration tests
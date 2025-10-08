"""
DSPy Variable Integration for DSPex

This module provides variable-aware DSPy modules that automatically synchronize
with Elixir-managed session variables.

Extracted from Snakepit v0.4.2 as part of architectural cleanup (see ADR-001).
Now maintained by DSPex project.

Migration Note:
  This module replaces the deprecated snakepit_bridge.dspy_integration module.
  See: https://github.com/nshkrdotcom/dspex/docs/architecture_review_20251007/
"""

import asyncio
import logging
from typing import Any, Dict, Optional, List, Union, Callable
from functools import wraps

# DSPy import
try:
    import dspy
    DSPY_AVAILABLE = True
except ImportError:
    DSPY_AVAILABLE = False
    # Create mock classes for type hints
    class MockDSPy:
        class Predict: pass
        class ChainOfThought: pass
        class ReAct: pass
        class ProgramOfThought: pass
        class Retrieve: pass
    dspy = MockDSPy()

# Import from Snakepit (these remain generic infrastructure)
from snakepit_bridge.variable_aware_mixin import VariableAwareMixin
from snakepit_bridge.session_context import SessionContext, VariableNotFoundError

logger = logging.getLogger(__name__)


class VariableBindingMixin:
    """
    Enhanced mixin that adds automatic variable binding to VariableAwareMixin.

    This provides the automatic synchronization functionality that was missing
    from the base VariableAwareMixin.
    """

    def __init__(self, *args, session_context: Optional[SessionContext] = None, **kwargs):
        # Initialize variable bindings
        self._variable_bindings: Dict[str, str] = {}
        self._last_sync: Dict[str, Any] = {}
        self._session_context = session_context
        self._auto_sync = kwargs.pop('auto_sync', True)

        # Initialize parent (will be VariableAwareMixin)
        super().__init__(*args, **kwargs)

        if session_context:
            # Initialize VariableAwareMixin with session info
            self._channel = session_context.channel
            self._session_id = session_context.session_id

            logger.info(f"Initialized variable-aware module for session {self._session_id}")

    def bind_variable(self, attribute: str, variable_name: str) -> None:
        """
        Bind a module attribute to a session variable.

        Args:
            attribute: The module attribute name (e.g., 'temperature')
            variable_name: The session variable name to bind to
        """
        self._variable_bindings[attribute] = variable_name
        logger.debug(f"Bound attribute '{attribute}' to variable '{variable_name}'")

        # Perform initial sync
        if self._session_context and self._auto_sync:
            try:
                value = self.get_variable(variable_name)
                if value is not None:
                    setattr(self, attribute, value)
                    self._last_sync[attribute] = value
                    logger.debug(f"Initial sync: {attribute} = {value}")
            except Exception as e:
                logger.warning(f"Failed to sync {attribute}: {e}")

    def unbind_variable(self, attribute: str) -> None:
        """Remove a variable binding."""
        if attribute in self._variable_bindings:
            del self._variable_bindings[attribute]
            if attribute in self._last_sync:
                del self._last_sync[attribute]

    async def sync_variables(self) -> Dict[str, Any]:
        """
        Asynchronously sync all bound variables from the session.

        Returns:
            Dict of attribute names to their new values
        """
        if not self._session_context:
            return {}

        updates = {}
        for attribute, variable_name in self._variable_bindings.items():
            try:
                # Use async version if available, otherwise run sync in executor
                if hasattr(self, 'get_variable_async'):
                    value = await self.get_variable_async(variable_name)
                else:
                    loop = asyncio.get_event_loop()
                    value = await loop.run_in_executor(None, self.get_variable, variable_name)

                if value is not None and value != self._last_sync.get(attribute):
                    setattr(self, attribute, value)
                    self._last_sync[attribute] = value
                    updates[attribute] = value
                    logger.debug(f"Synced {attribute} = {value}")

            except Exception as e:
                logger.error(f"Failed to sync variable {variable_name} to {attribute}: {e}")

        return updates

    def sync_variables_sync(self) -> Dict[str, Any]:
        """
        Synchronously sync all bound variables (for non-async contexts).

        Returns:
            Dict of attribute names to their new values
        """
        if not self._session_context:
            return {}

        updates = {}
        for attribute, variable_name in self._variable_bindings.items():
            try:
                value = self.get_variable(variable_name)

                if value is not None and value != self._last_sync.get(attribute):
                    setattr(self, attribute, value)
                    self._last_sync[attribute] = value
                    updates[attribute] = value
                    logger.debug(f"Synced {attribute} = {value}")

            except Exception as e:
                logger.error(f"Failed to sync variable {variable_name} to {attribute}: {e}")

        return updates

    def get_bindings(self) -> Dict[str, str]:
        """Get current variable bindings."""
        return self._variable_bindings.copy()


def auto_sync_decorator(func):
    """Decorator that automatically syncs variables before method execution."""
    @wraps(func)
    def sync_wrapper(self, *args, **kwargs):
        if hasattr(self, '_auto_sync') and self._auto_sync and hasattr(self, 'sync_variables_sync'):
            self.sync_variables_sync()
        return func(self, *args, **kwargs)

    @wraps(func)
    async def async_sync_wrapper(self, *args, **kwargs):
        if hasattr(self, '_auto_sync') and self._auto_sync and hasattr(self, 'sync_variables'):
            await self.sync_variables()
        return await func(self, *args, **kwargs)

    # Return appropriate wrapper based on function type
    if asyncio.iscoroutinefunction(func):
        return async_sync_wrapper
    else:
        return sync_wrapper


# Concrete variable-aware DSPy modules

class VariableAwarePredict(VariableBindingMixin, VariableAwareMixin, dspy.Predict):
    """
    Predict module with automatic variable synchronization.

    Example:
        predictor = VariableAwarePredict("question -> answer", session_context=ctx)
        predictor.bind_variable('temperature', 'llm_temperature')
        predictor.bind_variable('max_tokens', 'max_generation_tokens')

        # Variables are automatically synced before each forward call
        result = predictor(question="What is DSPy?")
    """

    def __init__(self, signature, *args, session_context: Optional[SessionContext] = None, **kwargs):
        # Initialize all mixins and parent
        super().__init__(signature, *args, session_context=session_context, **kwargs)

        # Set up default bindings for common LLM parameters
        if session_context and kwargs.get('auto_bind_common', True):
            self._setup_common_bindings()

    def _setup_common_bindings(self):
        """Set up common parameter bindings."""
        common_bindings = {
            'temperature': 'temperature',
            'max_tokens': 'max_tokens',
            'top_p': 'top_p',
            'frequency_penalty': 'frequency_penalty',
            'presence_penalty': 'presence_penalty',
        }

        for attr, var in common_bindings.items():
            try:
                # Only bind if variable exists in session
                value = self.get_variable(var)
                if value is not None:
                    self.bind_variable(attr, var)
            except:
                pass  # Variable doesn't exist, skip

    @auto_sync_decorator
    def forward(self, *args, **kwargs):
        """Forward with automatic variable sync."""
        return super().forward(*args, **kwargs)

    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        # DSPy's forward is synchronous, so we call it directly
        return self.forward(*args, **kwargs)


class VariableAwareChainOfThought(VariableBindingMixin, VariableAwareMixin, dspy.ChainOfThought):
    """
    ChainOfThought module with automatic variable synchronization.

    Example:
        cot = VariableAwareChainOfThought("question -> answer", session_context=ctx)
        cot.bind_variable('temperature', 'reasoning_temperature')
        cot.bind_variable('max_tokens', 'reasoning_max_tokens')

        result = cot(question="Explain step by step: What is 2+2?")
    """

    def __init__(self, signature, *args, session_context: Optional[SessionContext] = None, **kwargs):
        super().__init__(signature, *args, session_context=session_context, **kwargs)

        if session_context and kwargs.get('auto_bind_common', True):
            self._setup_common_bindings()

    def _setup_common_bindings(self):
        """Set up common parameter bindings for reasoning."""
        common_bindings = {
            'temperature': 'reasoning_temperature',
            'max_tokens': 'reasoning_max_tokens',
            'reasoning_steps': 'max_reasoning_steps',
        }

        for attr, var in common_bindings.items():
            try:
                value = self.get_variable(var)
                if value is not None:
                    self.bind_variable(attr, var)
            except:
                pass

    @auto_sync_decorator
    def forward(self, *args, **kwargs):
        """Forward with automatic variable sync."""
        return super().forward(*args, **kwargs)

    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        return self.forward(*args, **kwargs)


class VariableAwareReAct(VariableBindingMixin, VariableAwareMixin, dspy.ReAct):
    """
    ReAct module with automatic variable synchronization.

    Example:
        react = VariableAwareReAct("question -> answer", session_context=ctx)
        react.bind_variable('temperature', 'react_temperature')
        react.bind_variable('max_iterations', 'max_react_iterations')

        result = react(question="Research and answer: What is the capital of France?")
    """

    def __init__(self, signature, *args, session_context: Optional[SessionContext] = None, **kwargs):
        super().__init__(signature, *args, session_context=session_context, **kwargs)

        if session_context and kwargs.get('auto_bind_common', True):
            self._setup_common_bindings()

    def _setup_common_bindings(self):
        """Set up common parameter bindings for ReAct."""
        common_bindings = {
            'temperature': 'react_temperature',
            'max_tokens': 'react_max_tokens',
            'max_iterations': 'max_react_iterations',
            'tools': 'available_tools',
        }

        for attr, var in common_bindings.items():
            try:
                value = self.get_variable(var)
                if value is not None:
                    self.bind_variable(attr, var)
            except:
                pass

    @auto_sync_decorator
    def forward(self, *args, **kwargs):
        """Forward with automatic variable sync."""
        return super().forward(*args, **kwargs)

    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        return self.forward(*args, **kwargs)


class VariableAwareProgramOfThought(VariableBindingMixin, VariableAwareMixin, dspy.ProgramOfThought):
    """ProgramOfThought module with automatic variable synchronization."""

    def __init__(self, signature, *args, session_context: Optional[SessionContext] = None, **kwargs):
        super().__init__(signature, *args, session_context=session_context, **kwargs)

        if session_context and kwargs.get('auto_bind_common', True):
            self._setup_common_bindings()

    def _setup_common_bindings(self):
        """Set up common parameter bindings."""
        common_bindings = {
            'temperature': 'pot_temperature',
            'max_tokens': 'pot_max_tokens',
            'language': 'programming_language',
        }

        for attr, var in common_bindings.items():
            try:
                value = self.get_variable(var)
                if value is not None:
                    self.bind_variable(attr, var)
            except:
                pass

    @auto_sync_decorator
    def forward(self, *args, **kwargs):
        """Forward with automatic variable sync."""
        return super().forward(*args, **kwargs)


# Module factory for dynamic creation

class ModuleVariableResolver:
    """
    Resolves module-type variables to actual DSPy module classes.

    This enables dynamic module selection based on variables.
    """

    # Registry of available modules (both standard and variable-aware)
    MODULE_REGISTRY = {
        # Standard DSPy modules
        'Predict': dspy.Predict,
        'ChainOfThought': dspy.ChainOfThought,
        'ReAct': dspy.ReAct,
        'ProgramOfThought': dspy.ProgramOfThought,
        'Retrieve': dspy.Retrieve,

        # Variable-aware versions
        'VariableAwarePredict': VariableAwarePredict,
        'VariableAwareChainOfThought': VariableAwareChainOfThought,
        'VariableAwareReAct': VariableAwareReAct,
        'VariableAwareProgramOfThought': VariableAwareProgramOfThought,
    }

    @classmethod
    def resolve(cls, module_name: str) -> type:
        """Resolve a module name to its class."""
        if module_name not in cls.MODULE_REGISTRY:
            raise ValueError(f"Unknown module type: {module_name}. "
                           f"Available: {list(cls.MODULE_REGISTRY.keys())}")
        return cls.MODULE_REGISTRY[module_name]

    @classmethod
    def create_module(cls, module_name: str, signature: str,
                     session_context: Optional[SessionContext] = None,
                     **kwargs) -> Any:
        """
        Create a module instance from a variable.

        Args:
            module_name: Name of the module type
            signature: DSPy signature
            session_context: Optional session context for variable-aware modules
            **kwargs: Additional arguments for module initialization

        Returns:
            Module instance
        """
        module_class = cls.resolve(module_name)

        # Check if it's a variable-aware module
        if module_name.startswith('VariableAware'):
            return module_class(signature, session_context=session_context, **kwargs)
        else:
            return module_class(signature, **kwargs)

    @classmethod
    def register_module(cls, name: str, module_class: type) -> None:
        """Register a custom module type."""
        cls.MODULE_REGISTRY[name] = module_class


# Helper function for creating variable-aware programs

def create_variable_aware_program(
    module_type: str,
    signature: str,
    session_context: SessionContext,
    variable_bindings: Optional[Dict[str, str]] = None,
    **kwargs
) -> Any:
    """
    Create a variable-aware DSPy program with automatic bindings.

    Args:
        module_type: Type of module ('Predict', 'ChainOfThought', etc.)
        signature: DSPy signature string
        session_context: Session context for variable management
        variable_bindings: Optional dict of attribute -> variable_name bindings
        **kwargs: Additional module configuration

    Returns:
        Variable-aware module instance

    Example:
        module = create_variable_aware_program(
            'ChainOfThought',
            'question -> answer',
            session_context,
            variable_bindings={
                'temperature': 'reasoning_temp',
                'max_tokens': 'max_tokens'
            }
        )
    """
    # Ensure we use the variable-aware version
    if not module_type.startswith('VariableAware'):
        module_type = f'VariableAware{module_type}'

    # Create the module
    module = ModuleVariableResolver.create_module(
        module_type, signature, session_context, **kwargs
    )

    # Apply custom bindings
    if variable_bindings:
        for attr, var in variable_bindings.items():
            module.bind_variable(attr, var)

    return module


# Export all public classes and functions
__all__ = [
    'VariableBindingMixin',
    'auto_sync_decorator',
    'VariableAwarePredict',
    'VariableAwareChainOfThought',
    'VariableAwareReAct',
    'VariableAwareProgramOfThought',
    'ModuleVariableResolver',
    'create_variable_aware_program',
]

"""
Stage 2 Integration Tests for Variable-Aware DSPy Modules

This test suite verifies the integration between DSPex Variables and
DSPy modules through the VariableAwareMixin functionality.
"""

import pytest
import asyncio
from unittest.mock import Mock, MagicMock, patch, call
import grpc
from datetime import datetime
import sys
import os

# Add the snakepit bridge to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../snakepit/priv/python'))

# Mock dspy if not available
try:
    import dspy
except ImportError:
    # Create mock dspy module
    class MockDSPyModule:
        def __init__(self, *args, **kwargs):
            self.signature = args[0] if args else None
            self.temperature = None
            self.max_tokens = None
        
        def forward(self, **kwargs):
            result = Mock()
            for k, v in kwargs.items():
                setattr(result, k, f"Generated {k}")
            result.answer = "Generated answer"
            return result
    
    class MockDSPy:
        class Predict(MockDSPyModule): pass
        class ChainOfThought(MockDSPyModule): pass
        class ReAct(MockDSPyModule): pass
        class ProgramOfThought(MockDSPyModule): pass
        class Retrieve(MockDSPyModule): pass
    
    sys.modules['dspy'] = MockDSPy()
    dspy = MockDSPy()

from snakepit_bridge.dspy_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    VariableAwareReAct,
    ModuleVariableResolver,
    create_variable_aware_program
)
from snakepit_bridge.session_context import SessionContext
from snakepit_bridge.variable_aware_mixin import VariableAwareMixin


class TestVariableAwareMixin:
    """Test the base VariableAwareMixin functionality."""
    
    @pytest.fixture
    def mock_channel(self):
        """Create a mock gRPC channel."""
        return Mock(spec=grpc.Channel)
    
    @pytest.fixture
    def mock_session_context(self, mock_channel):
        """Create a mock session context."""
        ctx = Mock(spec=SessionContext)
        ctx.session_id = "test_session_123"
        ctx.channel = mock_channel
        ctx.stub = Mock()
        ctx.get_variable = Mock(side_effect=lambda name: {
            'temperature': 0.8,
            'max_tokens': 100,
            'reasoning_temperature': 0.9
        }.get(name))
        return ctx
    
    def test_variable_binding(self, mock_session_context):
        """Test variable binding functionality."""
        # Create a variable-aware module
        module = VariableAwarePredict("question -> answer", session_context=mock_session_context)
        
        # Bind a variable
        module.bind_variable('temperature', 'llm_temperature')
        
        # Check binding
        assert 'temperature' in module.get_bindings()
        assert module.get_bindings()['temperature'] == 'llm_temperature'
    
    def test_variable_sync(self, mock_session_context):
        """Test variable synchronization."""
        # Set up mock to return different values
        values = {'first': 0.7, 'second': 0.9}
        call_count = 0
        
        def get_var(name):
            nonlocal call_count
            if name == 'temperature':
                result = list(values.values())[call_count % 2]
                call_count += 1
                return result
            return None
        
        mock_session_context.get_variable = Mock(side_effect=get_var)
        
        # Create module and bind variable
        module = VariableAwarePredict("question -> answer", session_context=mock_session_context)
        module.bind_variable('temperature', 'temperature')
        
        # Initial sync
        updates = module.sync_variables_sync()
        assert 'temperature' in updates
        assert updates['temperature'] == 0.7
        assert module.temperature == 0.7
        
        # Sync again - should get new value
        updates = module.sync_variables_sync()
        assert 'temperature' in updates
        assert updates['temperature'] == 0.9
        assert module.temperature == 0.9
    
    @pytest.mark.asyncio
    async def test_async_variable_sync(self, mock_session_context):
        """Test asynchronous variable synchronization."""
        # Set up async mock
        async def async_get_var(name):
            if name == 'temperature':
                return 0.85
            return None
        
        module = VariableAwarePredict("question -> answer", session_context=mock_session_context)
        module.get_variable_async = async_get_var
        module.bind_variable('temperature', 'temperature')
        
        # Async sync
        updates = await module.sync_variables()
        assert 'temperature' in updates
        assert updates['temperature'] == 0.85
        assert module.temperature == 0.85
    
    def test_auto_sync_decorator(self, mock_session_context):
        """Test automatic synchronization before forward()."""
        mock_session_context.get_variable = Mock(return_value=0.95)
        
        module = VariableAwarePredict("question -> answer", session_context=mock_session_context)
        module.bind_variable('temperature', 'temperature')
        
        # Clear last sync to force update
        module._last_sync.clear()
        
        # Call forward - should trigger sync
        result = module.forward(question="Test question")
        
        # Verify temperature was synced
        assert module.temperature == 0.95
        assert hasattr(result, 'answer')


class TestVariableAwareModules:
    """Test specific variable-aware DSPy module implementations."""
    
    @pytest.fixture
    def session_context(self):
        """Create a session context with variable support."""
        ctx = Mock(spec=SessionContext)
        ctx.session_id = "test_session"
        ctx.channel = Mock()
        ctx.get_variable = Mock(side_effect=lambda name: {
            'temperature': 0.7,
            'max_tokens': 256,
            'reasoning_temperature': 0.8,
            'reasoning_max_tokens': 512,
            'max_reasoning_steps': 5,
            'react_temperature': 0.6,
            'max_react_iterations': 3
        }.get(name))
        return ctx
    
    def test_variable_aware_predict(self, session_context):
        """Test VariableAwarePredict with auto-binding."""
        module = VariableAwarePredict(
            "question -> answer",
            session_context=session_context,
            auto_bind_common=True
        )
        
        # Should auto-bind common parameters
        bindings = module.get_bindings()
        assert 'temperature' in bindings
        assert 'max_tokens' in bindings
        
        # Should sync values
        module.sync_variables_sync()
        assert module.temperature == 0.7
        assert module.max_tokens == 256
    
    def test_variable_aware_chain_of_thought(self, session_context):
        """Test VariableAwareChainOfThought with custom bindings."""
        module = VariableAwareChainOfThought(
            "question -> answer",
            session_context=session_context,
            auto_bind_common=True
        )
        
        # Should bind reasoning-specific variables
        module.sync_variables_sync()
        assert hasattr(module, 'temperature')
        assert hasattr(module, 'max_tokens')
        
        # Test forward
        result = module.forward(question="Explain step by step: What is 2+2?")
        assert hasattr(result, 'answer')
    
    def test_variable_aware_react(self, session_context):
        """Test VariableAwareReAct module."""
        module = VariableAwareReAct(
            "question -> answer",
            session_context=session_context,
            auto_bind_common=True
        )
        
        module.sync_variables_sync()
        
        # Custom binding
        module.bind_variable('max_iterations', 'max_react_iterations')
        module.sync_variables_sync()
        
        assert hasattr(module, 'max_iterations')
        assert module.max_iterations == 3
    
    def test_module_without_session_context(self):
        """Test module creation without session context (backward compatibility)."""
        # Should work without session context
        module = VariableAwarePredict("question -> answer")
        
        # No bindings without context
        assert len(module.get_bindings()) == 0
        
        # Sync should be no-op
        updates = module.sync_variables_sync()
        assert updates == {}
        
        # Forward should still work
        result = module.forward(question="Test")
        assert hasattr(result, 'answer')


class TestModuleVariableResolver:
    """Test the module resolver and factory functionality."""
    
    def test_module_resolution(self):
        """Test resolving module names to classes."""
        # Standard modules
        assert ModuleVariableResolver.resolve('Predict') == dspy.Predict
        assert ModuleVariableResolver.resolve('ChainOfThought') == dspy.ChainOfThought
        
        # Variable-aware modules
        assert ModuleVariableResolver.resolve('VariableAwarePredict') == VariableAwarePredict
        assert ModuleVariableResolver.resolve('VariableAwareChainOfThought') == VariableAwareChainOfThought
    
    def test_unknown_module(self):
        """Test error handling for unknown modules."""
        with pytest.raises(ValueError, match="Unknown module type"):
            ModuleVariableResolver.resolve('UnknownModule')
    
    def test_module_creation(self):
        """Test creating modules through the resolver."""
        ctx = Mock(spec=SessionContext)
        ctx.session_id = "test"
        ctx.channel = Mock()
        
        # Create variable-aware module
        module = ModuleVariableResolver.create_module(
            'VariableAwarePredict',
            'question -> answer',
            session_context=ctx
        )
        
        assert isinstance(module, VariableAwarePredict)
        assert module._session_context == ctx
    
    def test_custom_module_registration(self):
        """Test registering custom modules."""
        class CustomModule:
            def __init__(self, signature, **kwargs):
                self.signature = signature
        
        # Register custom module
        ModuleVariableResolver.register_module('Custom', CustomModule)
        
        # Should be resolvable
        assert ModuleVariableResolver.resolve('Custom') == CustomModule
        
        # Should be creatable
        module = ModuleVariableResolver.create_module('Custom', 'input -> output')
        assert isinstance(module, CustomModule)


class TestVariableAwareProgram:
    """Test the high-level program creation function."""
    
    @pytest.fixture
    def session_context(self):
        ctx = Mock(spec=SessionContext)
        ctx.session_id = "test"
        ctx.channel = Mock()
        ctx.get_variable = Mock(return_value=0.7)
        ctx.register_variable = Mock(return_value="var_123")
        return ctx
    
    def test_create_variable_aware_program(self, session_context):
        """Test creating a program with automatic variable bindings."""
        module = create_variable_aware_program(
            'ChainOfThought',
            'question -> answer',
            session_context,
            variable_bindings={
                'temperature': 'reasoning_temp',
                'max_tokens': 'max_tokens'
            }
        )
        
        # Should create variable-aware version
        assert isinstance(module, VariableAwareChainOfThought)
        
        # Should have bindings
        bindings = module.get_bindings()
        assert bindings['temperature'] == 'reasoning_temp'
        assert bindings['max_tokens'] == 'max_tokens'
    
    def test_create_with_auto_prefix(self, session_context):
        """Test automatic VariableAware prefix addition."""
        # Should add prefix automatically
        module = create_variable_aware_program(
            'Predict',  # No prefix
            'question -> answer',
            session_context
        )
        
        assert isinstance(module, VariableAwarePredict)


class TestIntegrationScenarios:
    """Test real-world integration scenarios."""
    
    @pytest.fixture
    def full_context(self):
        """Create a full mock context with all features."""
        ctx = Mock(spec=SessionContext)
        ctx.session_id = "integration_test"
        ctx.channel = Mock()
        
        # Variable storage
        variables = {
            'temperature': 0.7,
            'max_tokens': 256,
            'model': 'gpt-4',
            'reasoning_steps': 5
        }
        
        def get_var(name):
            return variables.get(name)
        
        def set_var(name, value, metadata=None):
            variables[name] = value
        
        ctx.get_variable = Mock(side_effect=get_var)
        ctx.update_variable = Mock(side_effect=set_var)
        ctx.register_variable = Mock(return_value="var_new")
        
        return ctx
    
    def test_dynamic_module_configuration(self, full_context):
        """Test dynamically configuring a module based on variables."""
        # Create module
        module = VariableAwarePredict("question -> answer", session_context=full_context)
        
        # Bind configuration variables
        module.bind_variable('temperature', 'temperature')
        module.bind_variable('max_tokens', 'max_tokens')
        module.bind_variable('model', 'model')
        
        # Initial sync
        module.sync_variables_sync()
        assert module.temperature == 0.7
        assert module.max_tokens == 256
        assert module.model == 'gpt-4'
        
        # Update variables in context
        full_context.update_variable('temperature', 0.9)
        full_context.update_variable('max_tokens', 512)
        
        # Re-sync
        updates = module.sync_variables_sync()
        assert module.temperature == 0.9
        assert module.max_tokens == 512
        assert len(updates) == 2
    
    @pytest.mark.asyncio
    async def test_concurrent_variable_updates(self, full_context):
        """Test handling concurrent variable updates."""
        # Create multiple modules sharing context
        module1 = VariableAwarePredict("q1 -> a1", session_context=full_context)
        module2 = VariableAwareChainOfThought("q2 -> a2", session_context=full_context)
        
        # Both bind to same variable
        module1.bind_variable('temperature', 'temperature')
        module2.bind_variable('temperature', 'temperature')
        
        # Concurrent updates
        async def update_module1():
            await asyncio.sleep(0.1)
            full_context.update_variable('temperature', 0.8)
            return module1.sync_variables_sync()
        
        async def update_module2():
            await asyncio.sleep(0.05)
            full_context.update_variable('temperature', 0.85)
            return module2.sync_variables_sync()
        
        # Run concurrently
        results = await asyncio.gather(update_module1(), update_module2())
        
        # Both should have synced (last write wins)
        final_temp = full_context.get_variable('temperature')
        assert final_temp in [0.8, 0.85]  # Either could win
    
    def test_error_handling(self, full_context):
        """Test error handling in variable operations."""
        # Simulate variable not found
        full_context.get_variable = Mock(side_effect=Exception("Variable not found"))
        
        module = VariableAwarePredict("question -> answer", session_context=full_context)
        module.bind_variable('missing', 'nonexistent')
        
        # Sync should handle error gracefully
        updates = module.sync_variables_sync()
        assert updates == {}  # No updates due to error
        
        # Module should still be usable
        result = module.forward(question="Test")
        assert hasattr(result, 'answer')


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
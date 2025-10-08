"""
DSPex Adapters Package

This package contains DSPy gRPC adapters and variable integration for Snakepit v0.4+ compatibility.
"""

from .dspy_grpc import DSPyGRPCHandler

# Import variable-aware DSPy classes (optional - requires dspy-ai)
try:
    from .dspy_variable_integration import (
        VariableAwarePredict,
        VariableAwareChainOfThought,
        VariableAwareReAct,
        VariableAwareProgramOfThought,
        ModuleVariableResolver,
        create_variable_aware_program,
    )
except ImportError:
    # DSPy not installed - that's OK, basic functionality still works
    pass

__version__ = "0.4.3"
__all__ = ['DSPyGRPCHandler']
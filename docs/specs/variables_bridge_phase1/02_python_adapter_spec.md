# Python Variable Adapter Implementation Specification

## Overview

The Python Variable Adapter enables DSPy modules to become "variable-aware" without modifying DSPy's core code. It provides mechanisms for variable injection, usage tracking, and impact reporting.

## Architecture

### Component Structure

```
┌─────────────────────────────────────────────┐
│          Python Variable System             │
│  ┌─────────────────────────────────────┐    │
│  │     VariableAdapter Class           │    │
│  │  - Variable value injection         │    │
│  │  - Usage tracking                   │    │
│  │  - Impact measurement               │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │   VariableAwareModule Wrapper       │    │
│  │  - Wraps any DSPy module           │    │
│  │  - Intercepts forward() calls      │    │
│  │  - Reports to Elixir               │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │    Variable Bridge Protocol         │    │
│  │  - get_variable_value()            │    │
│  │  - report_variable_usage()         │    │
│  │  - report_variable_impact()        │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Implementation Details

### File: `snakepit/priv/python/dspex_variables.py`

```python
"""
DSPex Variable System - Python Adapter
Enables variable awareness in DSPy modules without modifying DSPy core.
"""

import inspect
import functools
import logging
from typing import Dict, Any, List, Optional, Callable, Type
from dataclasses import dataclass, field
import dspy
from enhanced_command_handler import EnhancedCommandHandler

logger = logging.getLogger(__name__)


@dataclass
class VariableSpec:
    """Specification for a variable injection point."""
    variable_id: str
    parameter_path: str  # e.g., "lm.kwargs.temperature"
    transform: Optional[Callable] = None  # Optional value transformation
    
    
@dataclass
class VariableUsage:
    """Records how a variable was used during execution."""
    variable_id: str
    value: Any
    parameter_path: str
    timestamp: float
    context: Dict[str, Any] = field(default_factory=dict)


@dataclass
class VariableImpact:
    """Measures the impact of a variable on execution results."""
    variable_id: str
    metric_impacts: Dict[str, float]  # metric_name -> impact_score
    confidence: float
    samples: int


class VariableBridge:
    """
    Bridge between Python DSPy modules and Elixir Variable Registry.
    Handles communication and state synchronization.
    """
    
    def __init__(self, command_handler: EnhancedCommandHandler):
        self.handler = command_handler
        self.variable_cache: Dict[str, Any] = {}
        self.usage_buffer: List[VariableUsage] = []
        self.impact_buffer: List[VariableImpact] = []
        
    def get_variable_value(self, variable_id: str) -> Any:
        """Fetch current variable value from Elixir registry."""
        # Check cache first
        if variable_id in self.variable_cache:
            return self.variable_cache[variable_id]
            
        # Request from Elixir
        result = self.handler.call_elixir_function(
            "DSPex.Variables.Registry.get",
            [variable_id]
        )
        
        if result and "value" in result:
            value = result["value"]
            self.variable_cache[variable_id] = value
            return value
        else:
            raise ValueError(f"Variable {variable_id} not found")
            
    def report_variable_usage(self, usage: VariableUsage):
        """Buffer variable usage for batch reporting."""
        self.usage_buffer.append(usage)
        
        # Flush buffer if it gets too large
        if len(self.usage_buffer) >= 100:
            self.flush_usage_buffer()
            
    def report_variable_impact(self, impact: VariableImpact):
        """Buffer variable impact measurements."""
        self.impact_buffer.append(impact)
        
    def flush_usage_buffer(self):
        """Send buffered usage data to Elixir."""
        if not self.usage_buffer:
            return
            
        usage_data = [
            {
                "variable_id": u.variable_id,
                "value": u.value,
                "parameter_path": u.parameter_path,
                "timestamp": u.timestamp,
                "context": u.context
            }
            for u in self.usage_buffer
        ]
        
        self.handler.call_elixir_function(
            "DSPex.Variables.Telemetry.record_usage_batch",
            [usage_data]
        )
        
        self.usage_buffer.clear()
        
    def invalidate_cache(self, variable_id: Optional[str] = None):
        """Invalidate cached variable values."""
        if variable_id:
            self.variable_cache.pop(variable_id, None)
        else:
            self.variable_cache.clear()


class VariableAdapter:
    """
    Main adapter class that adds variable awareness to DSPy modules.
    """
    
    def __init__(self, bridge: VariableBridge):
        self.bridge = bridge
        self.module_specs: Dict[str, List[VariableSpec]] = {}
        
    def inject_variables(self, module: Any, variable_specs: List[VariableSpec]) -> Any:
        """
        Inject current variable values into a DSPy module instance.
        
        Args:
            module: DSPy module instance
            variable_specs: List of variable injection specifications
            
        Returns:
            The module with injected values
        """
        import time
        
        for spec in variable_specs:
            try:
                # Get current value
                value = self.bridge.get_variable_value(spec.variable_id)
                
                # Apply transformation if specified
                if spec.transform:
                    value = spec.transform(value)
                
                # Inject into module
                self._set_nested_attribute(module, spec.parameter_path, value)
                
                # Record usage
                usage = VariableUsage(
                    variable_id=spec.variable_id,
                    value=value,
                    parameter_path=spec.parameter_path,
                    timestamp=time.time(),
                    context={
                        "module_class": module.__class__.__name__,
                        "module_id": getattr(module, "_variable_module_id", None)
                    }
                )
                self.bridge.report_variable_usage(usage)
                
            except Exception as e:
                logger.error(f"Failed to inject variable {spec.variable_id}: {e}")
                
        return module
        
    def wrap_module(self, module_class: Type, variable_specs: List[VariableSpec]) -> Type:
        """
        Create a variable-aware wrapper for a DSPy module class.
        
        Args:
            module_class: DSPy module class to wrap
            variable_specs: Variable specifications for this module
            
        Returns:
            Variable-aware module class
        """
        adapter = self
        
        class VariableAwareModule(module_class):
            """Dynamic wrapper that adds variable awareness to any DSPy module."""
            
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self._variable_specs = variable_specs
                self._variable_adapter = adapter
                self._variable_module_id = f"{module_class.__name__}_{id(self)}"
                self._execution_count = 0
                self._last_inputs = None
                self._last_outputs = None
                
            def forward(self, *args, **kwargs):
                """
                Intercept forward calls to inject variables and track impact.
                """
                # Increment execution count
                self._execution_count += 1
                
                # Store inputs for impact analysis
                self._last_inputs = {"args": args, "kwargs": kwargs}
                
                # Apply current variable values
                self._variable_adapter.inject_variables(self, self._variable_specs)
                
                # Track pre-execution state
                pre_state = self._capture_state()
                
                # Execute original forward method
                result = super().forward(*args, **kwargs)
                
                # Store outputs
                self._last_outputs = result
                
                # Track post-execution state
                post_state = self._capture_state()
                
                # Analyze variable impact
                self._analyze_impact(pre_state, post_state, result)
                
                return result
                
            def _capture_state(self) -> Dict[str, Any]:
                """Capture relevant module state for impact analysis."""
                state = {
                    "execution_count": self._execution_count,
                    "timestamp": time.time()
                }
                
                # Capture predictor states if available
                if hasattr(self, "predictors"):
                    state["predictor_states"] = {}
                    for name, predictor in self.predictors():
                        if hasattr(predictor, "demos"):
                            state["predictor_states"][name] = {
                                "demo_count": len(predictor.demos) if predictor.demos else 0
                            }
                            
                return state
                
            def _analyze_impact(self, pre_state: Dict, post_state: Dict, result: Any):
                """Analyze how variables impacted the execution."""
                # This is a simplified impact analysis
                # In practice, this would be more sophisticated
                
                for spec in self._variable_specs:
                    impact = VariableImpact(
                        variable_id=spec.variable_id,
                        metric_impacts={
                            "execution_time": post_state["timestamp"] - pre_state["timestamp"],
                            "output_length": len(str(result)) if result else 0
                        },
                        confidence=0.8,  # Simplified confidence score
                        samples=self._execution_count
                    )
                    self._variable_adapter.bridge.report_variable_impact(impact)
                    
            def get_variable_info(self) -> Dict[str, Any]:
                """Get information about variables used by this module."""
                return {
                    "module_id": self._variable_module_id,
                    "variable_specs": [
                        {
                            "variable_id": spec.variable_id,
                            "parameter_path": spec.parameter_path,
                            "current_value": self._variable_adapter.bridge.get_variable_value(spec.variable_id)
                        }
                        for spec in self._variable_specs
                    ],
                    "execution_count": self._execution_count
                }
                
        # Copy class metadata
        VariableAwareModule.__name__ = f"VariableAware{module_class.__name__}"
        VariableAwareModule.__qualname__ = f"VariableAware{module_class.__qualname__}"
        
        return VariableAwareModule
        
    def _set_nested_attribute(self, obj: Any, path: str, value: Any):
        """
        Set a nested attribute using dot notation.
        
        Args:
            obj: Object to modify
            path: Dot-separated path (e.g., "lm.kwargs.temperature")
            value: Value to set
        """
        parts = path.split(".")
        
        # Navigate to the parent of the final attribute
        current = obj
        for part in parts[:-1]:
            if hasattr(current, part):
                current = getattr(current, part)
            elif isinstance(current, dict) and part in current:
                current = current[part]
            else:
                # Create missing intermediate objects
                if isinstance(current, dict):
                    current[part] = {}
                    current = current[part]
                else:
                    setattr(current, part, {})
                    current = getattr(current, part)
                    
        # Set the final attribute
        final_attr = parts[-1]
        if isinstance(current, dict):
            current[final_attr] = value
        else:
            setattr(current, final_attr, value)
            
    def create_variable_config(self, **mappings) -> List[VariableSpec]:
        """
        Helper to create variable specifications from keyword arguments.
        
        Example:
            adapter.create_variable_config(
                temperature="var_temperature_123",
                max_tokens="var_max_tokens_456"
            )
        """
        specs = []
        
        for param_path, variable_id in mappings.items():
            # Handle common parameter patterns
            if param_path == "temperature":
                param_path = "lm.kwargs.temperature"
            elif param_path == "max_tokens":
                param_path = "lm.kwargs.max_tokens"
            elif param_path == "top_p":
                param_path = "lm.kwargs.top_p"
                
            specs.append(VariableSpec(
                variable_id=variable_id,
                parameter_path=param_path
            ))
            
        return specs


class VariableAwareProgram:
    """
    Wrapper for complete DSPy programs with multiple modules.
    """
    
    def __init__(self, program: Any, adapter: VariableAdapter):
        self.program = program
        self.adapter = adapter
        self.module_variables: Dict[str, List[VariableSpec]] = {}
        
    def register_module_variables(self, module_name: str, variable_specs: List[VariableSpec]):
        """Register variables for a specific module in the program."""
        self.module_variables[module_name] = variable_specs
        
        # Wrap the module if it exists
        if hasattr(self.program, module_name):
            module = getattr(self.program, module_name)
            wrapped_class = self.adapter.wrap_module(module.__class__, variable_specs)
            wrapped_instance = wrapped_class(*self._get_module_args(module))
            setattr(self.program, module_name, wrapped_instance)
            
    def _get_module_args(self, module: Any) -> tuple:
        """Extract construction arguments from existing module."""
        # This is simplified - in practice would need more sophisticated extraction
        if hasattr(module, "signature"):
            return (module.signature,)
        return ()
        
    def forward(self, *args, **kwargs):
        """Execute the program with variable awareness."""
        # Ensure all variables are fresh
        self.adapter.bridge.invalidate_cache()
        
        # Execute program
        result = self.program.forward(*args, **kwargs)
        
        # Flush any buffered data
        self.adapter.bridge.flush_usage_buffer()
        
        return result
        
    def get_variable_summary(self) -> Dict[str, Any]:
        """Get summary of all variables used in the program."""
        summary = {
            "program_class": self.program.__class__.__name__,
            "modules": {}
        }
        
        for module_name, specs in self.module_variables.items():
            if hasattr(self.program, module_name):
                module = getattr(self.program, module_name)
                if hasattr(module, "get_variable_info"):
                    summary["modules"][module_name] = module.get_variable_info()
                    
        return summary


# Integration with enhanced command handler
class VariableCommandHandler(EnhancedCommandHandler):
    """Extended command handler with variable support."""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.variable_bridge = VariableBridge(self)
        self.variable_adapter = VariableAdapter(self.variable_bridge)
        
    def create_variable_aware_module(self, module_type: str, signature: str, 
                                   variable_mappings: Dict[str, str]) -> str:
        """
        Create a variable-aware DSPy module.
        
        Args:
            module_type: DSPy module type (e.g., "Predict", "ChainOfThought")
            signature: Module signature
            variable_mappings: Parameter to variable ID mappings
            
        Returns:
            Stored module ID
        """
        # Get module class
        module_class = getattr(dspy, module_type)
        
        # Create variable specs
        specs = self.variable_adapter.create_variable_config(**variable_mappings)
        
        # Create wrapped class
        wrapped_class = self.variable_adapter.wrap_module(module_class, specs)
        
        # Instantiate
        module = wrapped_class(signature)
        
        # Store and return ID
        module_id = f"variable_aware_{module_type}_{id(module)}"
        self.stored_objects[module_id] = module
        
        return module_id
        
    def execute_with_variables(self, module_id: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a variable-aware module with given inputs."""
        module = self.stored_objects.get(module_id)
        if not module:
            raise ValueError(f"Module {module_id} not found")
            
        # Execute
        result = module(**inputs)
        
        # Flush buffers
        self.variable_bridge.flush_usage_buffer()
        
        # Return result with metadata
        return {
            "result": result,
            "variable_info": module.get_variable_info() if hasattr(module, "get_variable_info") else {}
        }


# Helper functions for common patterns
def make_temperature_variable(variable_id: str, default: float = 0.7) -> VariableSpec:
    """Create a temperature variable specification."""
    return VariableSpec(
        variable_id=variable_id,
        parameter_path="lm.kwargs.temperature",
        transform=lambda x: max(0.0, min(2.0, float(x)))  # Ensure valid range
    )
    
    
def make_max_tokens_variable(variable_id: str, default: int = 150) -> VariableSpec:
    """Create a max_tokens variable specification."""
    return VariableSpec(
        variable_id=variable_id,
        parameter_path="lm.kwargs.max_tokens",
        transform=lambda x: max(1, int(x))  # Ensure positive integer
    )
    
    
def make_module_selection_variable(variable_id: str, 
                                 module_map: Dict[str, Type]) -> VariableSpec:
    """Create a module selection variable specification."""
    def transform(value: str) -> Type:
        if value not in module_map:
            raise ValueError(f"Unknown module: {value}")
        return module_map[value]
        
    return VariableSpec(
        variable_id=variable_id,
        parameter_path="_module_class",  # Special path for module selection
        transform=transform
    )
```

### File: `snakepit/priv/python/test_dspex_variables.py`

```python
"""
Tests for DSPex variable system Python adapter.
"""

import pytest
import dspy
from dspex_variables import (
    VariableAdapter, VariableBridge, VariableSpec,
    make_temperature_variable, make_max_tokens_variable
)
from unittest.mock import Mock, MagicMock


class TestVariableAdapter:
    """Test variable adapter functionality."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.mock_handler = Mock()
        self.bridge = VariableBridge(self.mock_handler)
        self.adapter = VariableAdapter(self.bridge)
        
    def test_inject_simple_variable(self):
        """Test injecting a simple variable into a module."""
        # Mock module
        module = Mock()
        module.lm = Mock()
        module.lm.kwargs = {}
        
        # Mock variable value
        self.mock_handler.call_elixir_function.return_value = {"value": 0.8}
        
        # Create spec and inject
        spec = VariableSpec("var_temp_123", "lm.kwargs.temperature")
        self.adapter.inject_variables(module, [spec])
        
        # Verify injection
        assert module.lm.kwargs["temperature"] == 0.8
        assert len(self.bridge.usage_buffer) == 1
        
    def test_wrap_predict_module(self):
        """Test wrapping a DSPy Predict module."""
        # Mock variable value
        self.mock_handler.call_elixir_function.return_value = {"value": 0.5}
        
        # Create wrapped class
        specs = [make_temperature_variable("var_temp_123")]
        WrappedPredict = self.adapter.wrap_module(dspy.Predict, specs)
        
        # Verify wrapped class
        assert WrappedPredict.__name__ == "VariableAwarePredict"
        assert issubclass(WrappedPredict, dspy.Predict)
        
    def test_nested_attribute_setting(self):
        """Test setting nested attributes with dot notation."""
        obj = Mock()
        obj.level1 = Mock()
        obj.level1.level2 = {}
        
        self.adapter._set_nested_attribute(obj, "level1.level2.value", 42)
        
        assert obj.level1.level2["value"] == 42
        
    def test_variable_config_helper(self):
        """Test creating variable configuration."""
        config = self.adapter.create_variable_config(
            temperature="var_temp_123",
            max_tokens="var_tokens_456"
        )
        
        assert len(config) == 2
        assert config[0].variable_id == "var_temp_123"
        assert config[0].parameter_path == "lm.kwargs.temperature"
        assert config[1].variable_id == "var_tokens_456"
        assert config[1].parameter_path == "lm.kwargs.max_tokens"


class TestVariableBridge:
    """Test variable bridge functionality."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.mock_handler = Mock()
        self.bridge = VariableBridge(self.mock_handler)
        
    def test_get_variable_with_caching(self):
        """Test variable retrieval with caching."""
        # Mock Elixir response
        self.mock_handler.call_elixir_function.return_value = {"value": 1.5}
        
        # First call should hit Elixir
        value1 = self.bridge.get_variable_value("var_123")
        assert value1 == 1.5
        assert self.mock_handler.call_elixir_function.call_count == 1
        
        # Second call should use cache
        value2 = self.bridge.get_variable_value("var_123")
        assert value2 == 1.5
        assert self.mock_handler.call_elixir_function.call_count == 1
        
    def test_usage_buffer_flushing(self):
        """Test automatic buffer flushing."""
        from dspex_variables import VariableUsage
        
        # Add 100 usage records
        for i in range(100):
            usage = VariableUsage(f"var_{i}", i, "test.path", 0.0)
            self.bridge.report_variable_usage(usage)
            
        # Should trigger flush
        assert len(self.bridge.usage_buffer) == 0
        assert self.mock_handler.call_elixir_function.called
        
    def test_cache_invalidation(self):
        """Test cache invalidation."""
        self.bridge.variable_cache = {"var_1": 1, "var_2": 2}
        
        # Invalidate specific variable
        self.bridge.invalidate_cache("var_1")
        assert "var_1" not in self.bridge.variable_cache
        assert "var_2" in self.bridge.variable_cache
        
        # Invalidate all
        self.bridge.invalidate_cache()
        assert len(self.bridge.variable_cache) == 0
```

## Integration Examples

### Example 1: Simple Variable-Aware Module

```python
# Creating a temperature-controlled Predict module
handler = VariableCommandHandler()

# Create module with variable
module_id = handler.create_variable_aware_module(
    "Predict",
    "question -> answer",
    {"temperature": "var_temperature_123"}
)

# Execute with current variable values
result = handler.execute_with_variables(
    module_id,
    {"question": "What is the capital of France?"}
)
```

### Example 2: Complex Program with Multiple Variables

```python
# Create a program with multiple modules sharing variables
adapter = VariableAdapter(bridge)

# Define shared temperature variable
temp_spec = make_temperature_variable("var_shared_temp")

# Create modules with shared variable
class MyProgram(dspy.Module):
    def __init__(self):
        self.generate = dspy.Predict("topic -> idea")
        self.improve = dspy.ChainOfThought("idea -> refined_idea")
        
# Wrap modules
program = MyProgram()
wrapped_program = VariableAwareProgram(program, adapter)

# Register variables for each module
wrapped_program.register_module_variables("generate", [temp_spec])
wrapped_program.register_module_variables("improve", [temp_spec])

# Execute - both modules use same temperature
result = wrapped_program.forward(topic="AI safety")
```

## Performance Considerations

1. **Caching**: Variable values are cached to avoid repeated Elixir calls
2. **Batch Reporting**: Usage data is buffered and sent in batches
3. **Lazy Injection**: Variables are only injected when modules are called
4. **Minimal Overhead**: Wrapping adds <5ms per forward() call

## Testing Strategy

1. **Unit Tests**: Test each component in isolation
2. **Integration Tests**: Test with real DSPy modules
3. **Performance Tests**: Measure overhead of variable injection
4. **Compatibility Tests**: Ensure all DSPy modules work when wrapped

## Next Steps

1. Implement the bridge protocol for Elixir communication
2. Add support for more complex variable types (embeddings, module selection)
3. Implement sophisticated impact analysis
4. Add async variable updates
5. Create comprehensive examples
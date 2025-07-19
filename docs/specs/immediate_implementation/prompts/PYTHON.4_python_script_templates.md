# Task: PYTHON.4 - Python Script Templates

## Context
You are creating Python script templates that implement the DSPy bridge functionality. These scripts will be executed by Snakepit to handle DSPy operations from Elixir.

## Required Reading

### 1. Snakepit Python Bridge V2
- **File**: `/home/home/p/g/n/dspex/snakepit/PYTHON_BRIDGE_V2.md`
  - Lines 28-46: Package structure
  - Lines 100-130: V2 bridge approach with examples

### 2. Snakepit Bridge Examples
- **File**: `/home/home/p/g/n/dspex/snakepit/README.md`
  - Lines 332-361: Python bridge V2 pattern
  - Lines 428-533: Bridge script examples

### 3. Example Bridge Scripts
- Look for `generic_bridge_v2.py` patterns in Snakepit
- Note the BaseCommandHandler usage
- Protocol handling patterns

### 4. DSPy Operations
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Stage 3 examples of DSPy module usage
  - Expected inputs/outputs

### 5. Serialization Protocol
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/prompts/PYTHON.3_serialization_protocol.md`
  - Protocol format details
  - Type conversion requirements

## Implementation Requirements

### Main DSPy Bridge Script
Create `priv/python/dspex_bridge.py`:
```python
#!/usr/bin/env python3
"""
DSPex Bridge - Handles DSPy operations for Elixir
"""

import sys
import os
import json
import traceback
from typing import Dict, Any, Optional

# Add parent directory to path for development
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from snakepit_bridge import BaseCommandHandler, ProtocolHandler
from snakepit_bridge.core import setup_graceful_shutdown, setup_broken_pipe_suppression

import dspy
import numpy as np


class DSPexBridgeHandler(BaseCommandHandler):
    """Main handler for DSPex DSPy operations"""
    
    def __init__(self):
        super().__init__()
        self.modules = {}
        self.programs = {}
        self.lm_configured = False
        self.session_data = {}
        
    def _register_commands(self):
        """Register all DSPy-related commands"""
        # Configuration
        self.register_command("configure_lm", self.handle_configure_lm)
        self.register_command("list_dspy_modules", self.handle_list_modules)
        
        # Module execution
        self.register_command("execute_module", self.handle_execute_module)
        self.register_command("create_program", self.handle_create_program)
        self.register_command("execute_program", self.handle_execute_program)
        
        # Optimization
        self.register_command("optimize_prompt", self.handle_optimize_prompt)
        self.register_command("bootstrap_examples", self.handle_bootstrap_examples)
        
        # Utilities
        self.register_command("create_signature", self.handle_create_signature)
        self.register_command("validate_inputs", self.handle_validate_inputs)
        
    def handle_configure_lm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Configure the language model for DSPy"""
        try:
            provider = args.get("provider", "openai")
            config = args.get("config", {})
            
            if provider == "openai":
                import os
                api_key = config.get("api_key") or os.getenv("OPENAI_API_KEY")
                lm = dspy.OpenAI(
                    model=config.get("model", "gpt-3.5-turbo"),
                    api_key=api_key,
                    **{k: v for k, v in config.items() if k not in ["model", "api_key"]}
                )
            elif provider == "anthropic":
                api_key = config.get("api_key") or os.getenv("ANTHROPIC_API_KEY")
                lm = dspy.Claude(
                    model=config.get("model", "claude-3-sonnet"),
                    api_key=api_key,
                    **{k: v for k, v in config.items() if k not in ["model", "api_key"]}
                )
            elif provider == "local":
                lm = dspy.HFClientTGI(
                    model=config.get("model", "meta-llama/Llama-2-7b-hf"),
                    port=config.get("port", 8080),
                    **{k: v for k, v in config.items() if k not in ["model", "port"]}
                )
            else:
                return {"error": f"Unknown provider: {provider}"}
            
            dspy.settings.configure(lm=lm)
            self.lm_configured = True
            
            return {
                "status": "configured",
                "provider": provider,
                "model": config.get("model", "default")
            }
            
        except Exception as e:
            return {"error": str(e), "traceback": traceback.format_exc()}
    
    def handle_execute_module(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a DSPy module"""
        try:
            if not self.lm_configured:
                return {"error": "LM not configured. Call configure_lm first."}
            
            module_name = args.get("module", "Predict")
            signature = args.get("signature", "")
            inputs = args.get("inputs", {})
            config = args.get("config", {})
            
            # Get module class
            if hasattr(dspy, module_name):
                module_class = getattr(dspy, module_name)
            else:
                return {"error": f"Unknown module: {module_name}"}
            
            # Create module instance
            if signature:
                module = module_class(signature, **config)
            else:
                module = module_class(**config)
            
            # Execute module
            result = module(**inputs)
            
            # Convert result to serializable format
            return self._serialize_result(result)
            
        except Exception as e:
            return {"error": str(e), "traceback": traceback.format_exc()}
    
    def _serialize_result(self, result) -> Dict[str, Any]:
        """Convert DSPy result to serializable format"""
        if hasattr(result, '__dict__'):
            # DSPy Prediction object
            serialized = {}
            for key, value in result.__dict__.items():
                if not key.startswith('_'):
                    serialized[key] = self._serialize_value(value)
            return serialized
        else:
            return {"result": self._serialize_value(result)}
    
    def _serialize_value(self, value):
        """Serialize individual values"""
        if isinstance(value, (str, int, float, bool, type(None))):
            return value
        elif isinstance(value, (list, tuple)):
            return [self._serialize_value(v) for v in value]
        elif isinstance(value, dict):
            return {k: self._serialize_value(v) for k, v in value.items()}
        elif isinstance(value, np.ndarray):
            return {
                "_type": "ndarray",
                "data": value.tolist(),
                "shape": value.shape,
                "dtype": str(value.dtype)
            }
        else:
            return str(value)


def main():
    """Main entry point"""
    setup_broken_pipe_suppression()
    
    handler = DSPexBridgeHandler()
    protocol = ProtocolHandler(handler)
    setup_graceful_shutdown(protocol)
    
    # Log startup
    sys.stderr.write("DSPex Bridge started successfully\n")
    sys.stderr.flush()
    
    protocol.run()


if __name__ == "__main__":
    main()
```

### Module-Specific Handlers
Create `priv/python/dspex_modules.py`:
```python
"""
Module-specific handlers for DSPex
"""

from typing import Dict, Any, List
import dspy


class ModuleHandlers:
    """Handlers for specific DSPy modules"""
    
    @staticmethod
    def handle_chain_of_thought(signature: str, inputs: Dict[str, Any], config: Dict[str, Any]):
        """Special handling for ChainOfThought"""
        cot = dspy.ChainOfThought(signature, **config)
        result = cot(**inputs)
        
        # Extract reasoning steps if available
        response = {
            "reasoning": getattr(result, "reasoning", ""),
            "answer": getattr(result, "answer", result)
        }
        
        # Add any intermediate steps
        if hasattr(result, "_trace"):
            response["trace"] = result._trace
            
        return response
    
    @staticmethod
    def handle_react(signature: str, inputs: Dict[str, Any], config: Dict[str, Any]):
        """Special handling for ReAct"""
        tools = config.pop("tools", [])
        react = dspy.ReAct(signature, tools=tools, **config)
        
        result = react(**inputs)
        
        return {
            "thought": getattr(result, "thought", ""),
            "action": getattr(result, "action", ""),
            "observation": getattr(result, "observation", ""),
            "answer": getattr(result, "answer", result)
        }
    
    @staticmethod
    def handle_program_of_thought(signature: str, inputs: Dict[str, Any], config: Dict[str, Any]):
        """Special handling for ProgramOfThought"""
        pot = dspy.ProgramOfThought(signature, **config)
        result = pot(**inputs)
        
        return {
            "program": getattr(result, "program", ""),
            "execution_result": getattr(result, "execution_result", ""),
            "answer": getattr(result, "answer", result)
        }
```

### Optimization Handlers
Create `priv/python/dspex_optimizers.py`:
```python
"""
Optimization handlers for DSPex
"""

import dspy
from typing import Dict, Any, List


class OptimizationHandlers:
    """Handlers for DSPy optimization operations"""
    
    @staticmethod
    def bootstrap_few_shot(program, trainset, config: Dict[str, Any]):
        """Bootstrap few-shot examples"""
        teleprompter = dspy.BootstrapFewShot(
            metric=config.get("metric"),
            max_bootstrapped_demos=config.get("max_demos", 4),
            max_labeled_demos=config.get("max_labeled", 16)
        )
        
        optimized = teleprompter.compile(
            program,
            trainset=trainset
        )
        
        return optimized
    
    @staticmethod
    def optimize_signature(signature: str, examples: List[Dict], config: Dict[str, Any]):
        """Optimize a signature with examples"""
        # Create a simple program
        program = dspy.Predict(signature)
        
        # Convert examples to DSPy format
        trainset = [dspy.Example(**ex) for ex in examples]
        
        # Use appropriate optimizer
        if config.get("optimizer") == "mipro":
            optimizer = dspy.MIPROv2(
                metric=config.get("metric"),
                num_candidates=config.get("num_candidates", 10)
            )
        else:
            optimizer = dspy.BootstrapFewShot(
                metric=config.get("metric")
            )
        
        optimized = optimizer.compile(program, trainset=trainset)
        
        return {
            "optimized_prompt": optimized.get_prompt(),
            "examples_used": len(optimized.demos),
            "performance": optimizer.get_scores() if hasattr(optimizer, "get_scores") else None
        }
```

### Utility Scripts
Create `priv/python/dspex_utils.py`:
```python
"""
Utility functions for DSPex bridge
"""

import re
from typing import Dict, Any, List, Tuple


def parse_signature(signature: str) -> Dict[str, Any]:
    """Parse a DSPy signature string"""
    # Handle arrow notation: "input1, input2 -> output1, output2"
    if "->" in signature:
        inputs_str, outputs_str = signature.split("->")
        inputs = parse_fields(inputs_str.strip())
        outputs = parse_fields(outputs_str.strip())
    else:
        inputs = parse_fields(signature.strip())
        outputs = []
    
    return {
        "inputs": inputs,
        "outputs": outputs,
        "original": signature
    }


def parse_fields(fields_str: str) -> List[Dict[str, str]]:
    """Parse comma-separated fields with optional types"""
    fields = []
    
    for field in fields_str.split(","):
        field = field.strip()
        if not field:
            continue
            
        # Check for type annotation
        if ":" in field:
            name, type_str = field.split(":", 1)
            fields.append({
                "name": name.strip(),
                "type": type_str.strip()
            })
        else:
            fields.append({
                "name": field,
                "type": "str"  # Default type
            })
    
    return fields


def validate_inputs(signature: Dict[str, Any], inputs: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """Validate inputs against a signature"""
    errors = []
    
    # Check required inputs
    for field in signature.get("inputs", []):
        name = field["name"]
        if name not in inputs:
            errors.append(f"Missing required input: {name}")
    
    # Check types if specified
    for field in signature.get("inputs", []):
        name = field["name"]
        expected_type = field.get("type", "str")
        
        if name in inputs:
            value = inputs[name]
            if not check_type(value, expected_type):
                errors.append(f"Input '{name}' has wrong type. Expected {expected_type}")
    
    return len(errors) == 0, errors


def check_type(value: Any, type_str: str) -> bool:
    """Check if value matches expected type"""
    type_map = {
        "str": str,
        "int": int,
        "float": float,
        "bool": bool,
        "list": list,
        "dict": dict
    }
    
    if type_str in type_map:
        return isinstance(value, type_map[type_str])
    
    # Handle complex types like list[str]
    if type_str.startswith("list[") and isinstance(value, list):
        inner_type = type_str[5:-1]
        return all(check_type(v, inner_type) for v in value)
    
    return True  # Unknown types pass
```

### Setup Script
Create `priv/python/setup_dspex.py`:
```python
"""
Setup script to verify DSPex Python environment
"""

import sys
import importlib


def check_requirements():
    """Check if all required packages are installed"""
    required = [
        ("dspy", "dspy-ai"),
        ("numpy", "numpy"),
        ("snakepit_bridge", "snakepit_bridge")
    ]
    
    missing = []
    
    for module, package in required:
        try:
            importlib.import_module(module)
            print(f"✓ {module} is installed")
        except ImportError:
            print(f"✗ {module} is missing")
            missing.append(package)
    
    if missing:
        print("\nPlease install missing packages:")
        print(f"pip install {' '.join(missing)}")
        return False
    
    print("\nAll requirements satisfied!")
    return True


if __name__ == "__main__":
    sys.exit(0 if check_requirements() else 1)
```

## Acceptance Criteria
- [ ] Main bridge script handles all DSPy operations
- [ ] Module-specific handlers for special cases
- [ ] Optimization handlers for teleprompters
- [ ] Utility functions for signature parsing
- [ ] Setup script verifies environment
- [ ] Proper error handling with tracebacks
- [ ] Session data persistence support
- [ ] Type serialization for ML types
- [ ] Graceful shutdown handling

## Testing Requirements
Create tests in:
- `test/integration/python_scripts_test.exs`

Test the scripts by:
- Direct execution with test inputs
- Integration through Snakepit
- Error scenarios
- Large data handling
- Session persistence

## Example Usage
From Elixir:
```elixir
# Configure LM
{:ok, _} = DSPex.Python.Snakepit.execute(
  :general,
  "configure_lm",
  %{
    provider: "openai",
    config: %{model: "gpt-3.5-turbo"}
  }
)

# Execute ChainOfThought
{:ok, result} = DSPex.Python.Snakepit.execute(
  :general,
  "execute_module",
  %{
    module: "ChainOfThought",
    signature: "question -> answer",
    inputs: %{question: "What causes rain?"}
  }
)

# Result includes reasoning
%{
  "reasoning" => "Let me think about the water cycle...",
  "answer" => "Rain is caused by water vapor condensing..."
}
```

## Dependencies
- Python 3.8+
- DSPy (`pip install dspy-ai`)
- Snakepit bridge package
- NumPy for array handling

## Time Estimate
6 hours total:
- 2 hours: Main bridge script
- 1 hour: Module-specific handlers
- 1 hour: Optimization handlers
- 1 hour: Utilities and setup
- 1 hour: Testing scripts

## Notes
- Use stderr for logging (stdout is for protocol)
- Handle graceful shutdown properly
- Consider adding caching for compiled programs
- Monitor memory usage in long-running processes
- Add telemetry hooks for monitoring
- Plan for custom module registration
# Task: LLM.4 - Python DSPy Adapter Implementation

## Context
You are implementing the Python DSPy adapter that bridges to Python for complex DSPy operations. This adapter leverages Snakepit to execute DSPy modules that don't have native Elixir implementations or when Python execution is preferred for compatibility.

## Required Reading

### 1. Existing Python Adapter
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapters/python.ex`
  - Review current structure
  - Note Snakepit integration approach

### 2. Python Bridge Documentation
- **File**: `/home/home/p/g/n/dspex/lib/dspex/python/bridge.ex`
  - Understand bridge communication patterns
  - Note serialization approach

### 3. Snakepit Integration
- **File**: `/home/home/p/g/n/dspex/snakepit/README.md`
  - Lines 40-62: Quick start usage
  - Lines 175-195: Session-based execution
  - Lines 260-285: Python adapter examples

### 4. DSPy Module Support
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Section on Python/DSPy integration
  - List of DSPy modules to support

### 5. Bridge Script Template
- **File**: Review any existing Python scripts in project
  - Note snakepit_bridge usage patterns
  - Command registration approach

## Implementation Requirements

### Adapter Structure
```elixir
defmodule DSPex.LLM.Adapters.Python do
  @behaviour DSPex.LLM.Adapter
  
  defstruct [
    :pool,
    :timeout,
    :serialization_format,
    :module_config
  ]
  
  # Default DSPy modules to support
  @supported_modules [
    "dspy.Predict",
    "dspy.ChainOfThought", 
    "dspy.ReAct",
    "dspy.ProgramOfThought",
    "dspy.MultiChainComparison"
  ]
end
```

### Python Bridge Script
Create a bridge script that handles DSPy operations:
```python
# priv/python/dspy_bridge.py
from snakepit_bridge import BaseCommandHandler, ProtocolHandler
import dspy
import json

class DSPyHandler(BaseCommandHandler):
    def __init__(self):
        super().__init__()
        self.programs = {}
        self.lm_configs = {}
        
    def _register_commands(self):
        self.register_command("configure_lm", self.handle_configure_lm)
        self.register_command("execute_module", self.handle_execute_module)
        self.register_command("create_program", self.handle_create_program)
        self.register_command("execute_program", self.handle_execute_program)
        
    def handle_configure_lm(self, args):
        """Configure language model for DSPy"""
        provider = args.get("provider", "openai")
        config = args.get("config", {})
        
        if provider == "openai":
            lm = dspy.OpenAI(**config)
        elif provider == "anthropic":
            lm = dspy.Claude(**config)
        else:
            return {"error": f"Unknown provider: {provider}"}
            
        dspy.settings.configure(lm=lm)
        self.lm_configs[provider] = config
        return {"status": "configured", "provider": provider}
        
    def handle_execute_module(self, args):
        """Execute a DSPy module directly"""
        module_name = args.get("module")
        signature = args.get("signature")
        inputs = args.get("inputs", {})
        
        # Get module class
        module_class = getattr(dspy, module_name.split(".")[-1])
        
        # Create and execute
        module = module_class(signature)
        result = module(**inputs)
        
        # Convert result to dict
        return self._serialize_result(result)
```

### Module Execution Flow
```elixir
def generate(adapter, prompt, opts) do
  # Determine DSPy module from opts
  module = opts[:module] || "dspy.Predict"
  signature = opts[:signature] || build_signature(opts)
  
  # Execute via Snakepit
  case Snakepit.execute(
    adapter.pool,
    "execute_module",
    %{
      module: module,
      signature: signature,
      inputs: %{input: prompt},
      config: opts
    },
    timeout: adapter.timeout
  ) do
    {:ok, result} -> 
      {:ok, transform_result(result)}
    {:error, reason} ->
      {:error, {:python_error, reason}}
  end
end
```

### Session Support
For stateful DSPy programs:
```elixir
def create_program(adapter, signature, opts) do
  session_id = opts[:session_id] || UUID.generate()
  
  Snakepit.execute_in_session(
    session_id,
    "create_program",
    %{
      signature: signature,
      modules: opts[:modules],
      config: opts[:config]
    }
  )
end

def execute_program(adapter, program_id, inputs, opts) do
  session_id = opts[:session_id]
  
  Snakepit.execute_in_session(
    session_id,
    "execute_program",
    %{
      program_id: program_id,
      inputs: inputs
    }
  )
end
```

## Acceptance Criteria
- [ ] Implements all adapter protocol functions
- [ ] Supports core DSPy modules (Predict, ChainOfThought, etc.)
- [ ] Python bridge script with proper error handling
- [ ] Session support for stateful programs
- [ ] Configuration management for different LM providers
- [ ] Serialization of complex DSPy results
- [ ] Timeout handling with graceful errors
- [ ] Module validation before execution
- [ ] Performance metrics collection

## Error Handling
```elixir
defp handle_python_error({:error, {:python_exception, details}}) do
  case details do
    %{"type" => "ModuleNotFoundError"} ->
      {:error, :module_not_found}
      
    %{"type" => "ValueError", "message" => msg} ->
      {:error, {:invalid_input, msg}}
      
    %{"type" => "TimeoutError"} ->
      {:error, :python_timeout}
      
    _ ->
      {:error, {:python_error, details}}
  end
end
```

## Testing Requirements
Create tests in:
- `test/dspex/llm/adapters/python_test.exs`
- `test/integration/python_dspy_test.exs`

Test scenarios:
- Basic module execution (Predict, ChainOfThought)
- Complex modules (ReAct, ProgramOfThought)
- Session persistence
- Error conditions
- Timeout handling
- Large input/output handling

## Example Usage
```elixir
# Configure adapter
adapter = %DSPex.LLM.Adapters.Python{
  pool: :general,
  timeout: 30_000
}

# Simple prediction
{:ok, result} = DSPex.LLM.Adapter.generate(
  adapter,
  "What is machine learning?",
  module: "dspy.Predict",
  signature: "question -> answer"
)

# Chain of Thought
{:ok, result} = DSPex.LLM.Adapter.generate(
  adapter,
  "Explain how photosynthesis works",
  module: "dspy.ChainOfThought",
  signature: "question -> explanation",
  max_hops: 3
)

# Stateful program
{:ok, program} = create_program(
  adapter,
  "context, question -> answer",
  modules: ["dspy.ChainOfThought", "dspy.Predict"]
)

{:ok, result} = execute_program(
  adapter,
  program.id,
  %{
    context: "Previous conversation...",
    question: "What did we discuss?"
  }
)
```

## Dependencies
- Requires LLM.1 (Adapter Protocol) complete
- Requires PYTHON.1 (Snakepit Integration) complete
- Python environment with DSPy installed
- Snakepit bridge scripts

## Time Estimate
8 hours total:
- 2 hours: Core adapter implementation
- 2 hours: Python bridge script
- 1 hour: Session support
- 1 hour: Result serialization
- 1 hour: Error handling
- 1 hour: Integration testing

## Notes
- Leverage Snakepit's session support for stateful operations
- Consider caching compiled DSPy programs
- Monitor Python process memory usage
- Add telemetry for module execution patterns
- Support batch operations for efficiency
- Consider implementing module-specific optimizations
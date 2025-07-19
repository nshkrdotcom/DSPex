# DSPex V2 Architecture

## Overview

DSPex V2 is a complete rewrite that creates a native Elixir DSPy implementation while using Snakepit for Python DSPy integration. The architecture enables:

1. **Gradual Native Implementation**: Start with Python DSPy via Snakepit, gradually add native Elixir implementations
2. **Mixed Execution**: Mix and match native/Python implementations in the same pipeline
3. **First-Class Python Processes**: Python processes are integrated as equals, not second-class citizens
4. **Smart Routing**: Automatically choose the best implementation based on availability and performance

## Key Design Decisions

### 1. Snakepit Integration
- Snakepit manages all Python process pooling
- DSPex focuses on the DSPy API and routing logic
- Clean separation of concerns

### 2. Native-First Where It Makes Sense
- Signatures: Always native (fast parsing, no Python overhead)
- Templates: Native EEx implementation
- Validators: Native for simple validations
- LLM Clients: Adapter pattern with InstructorLite, HTTP, or Python backends
- Complex ML: Delegate to Python (e.g., ColBERTv2, miprov2)

### 3. Protocol-Agnostic Bridge
- Support multiple serialization formats (JSON, MessagePack, Arrow)
- Extensible for future protocols
- Efficient data transfer

## Architecture Components

### Core Modules

1. **DSPex** - Public API module
   - Clean, intuitive interface
   - Hides implementation details
   - Delegates to appropriate subsystems

2. **DSPex.Router** - Smart routing engine
   - Tracks available implementations
   - Routes to native or Python based on capability
   - Collects performance metrics for optimization

3. **DSPex.Pipeline** - Workflow orchestration
   - Sequential, parallel, conditional execution
   - Mix native and Python steps seamlessly
   - Streaming support (when available)

4. **DSPex.Native.*** - Native implementations
   - Signature - DSPy signature parsing
   - Template - EEx-based templating
   - Validator - Data validation
   - Metrics - Performance tracking
   - LMClient - Adapter-based LLM integration

5. **DSPex.Python.*** - Python bridge
   - Bridge - Snakepit integration
   - Registry - Track Python modules
   - PoolManager - Lifecycle management

## Data Flow

```
User Request
    ↓
DSPex API
    ↓
Router (decides native vs Python)
    ↓
Native Module ←→ Python Bridge
                      ↓
                  Snakepit
                      ↓
                  Python DSPy
```

## Pipeline Example

```elixir
pipeline = DSPex.pipeline([
  {:native, Signature, spec: "query -> keywords: list[str]"},
  {:python, "dspy.ChainOfThought", signature: "keywords -> analysis"},
  {:parallel, [
    {:native, Search, index: "docs"},
    {:python, "dspy.ColBERTv2", k: 10}
  ]},
  {:native, Template, template: "Results: <%= @results %>"}
])

{:ok, result} = DSPex.run_pipeline(pipeline, %{query: "explain DSPy"})
```

## Testing Strategy

Three-layer testing architecture:

1. **Layer 1: Mock Adapter** (~70ms)
   - Unit tests with mocked Python responses
   - Fast feedback during development

2. **Layer 2: Bridge Mock**
   - Protocol testing without full Python
   - Validates serialization/deserialization

3. **Layer 3: Full Integration**
   - Complete end-to-end testing
   - Requires Python environment

## Next Steps

1. **Python Environment Setup**
   - Install DSPy in Python environment
   - Create bridge scripts for DSPy modules
   - Test end-to-end integration

2. **LLM Adapter Implementation**
   - Add InstructorLite to dependencies
   - Implement InstructorLite adapter
   - Create HTTP adapter for direct API calls
   - Test adapter switching and configuration

3. **Additional Native Modules**
   - Implement more DSPy modules natively
   - Focus on performance-critical operations
   - Maintain API compatibility

4. **Performance Optimization**
   - Profile router decisions
   - Optimize serialization
   - Add caching where beneficial

5. **Advanced Features**
   - Streaming support (pending Snakepit implementation)
   - Distributed execution
   - Model management

## Development Commands

```bash
# Run tests by layer
mix test.fast        # Layer 1: Mock adapter
mix test.protocol    # Layer 2: Bridge mock  
mix test.integration # Layer 3: Full integration
mix test.all         # All layers sequentially

# Check code quality
mix dialyzer         # Type checking
mix format           # Code formatting
mix credo            # Static analysis

# Development
iex -S mix           # Interactive shell
```

## Configuration

```elixir
# config/config.exs
config :dspex,
  router: [
    prefer_native: true,
    fallback_to_python: true
  ]

config :snakepit,
  python_path: "python3",
  pool_size: 4
```

## Status

✅ Core architecture implemented
✅ Native signature parsing
✅ Router with smart delegation
✅ Pipeline orchestration
✅ Snakepit integration
✅ Clean compilation
✅ Dialyzer passing

🚧 Python DSPy scripts
🚧 End-to-end testing
🚧 Performance benchmarks
🚧 Documentation
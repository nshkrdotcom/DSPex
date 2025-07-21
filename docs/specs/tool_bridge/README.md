# DSPex Bridge Specifications

This directory contains detailed technical specifications and documentation for the DSPex Python-Elixir bridge system.

## Core Architecture Documents

### 1. [PYTHON_TOOL_BRIDGE.md](./PYTHON_TOOL_BRIDGE.md)
The foundational specification for the bidirectional RPC bridge between Elixir and Python, enabling DSPy's ReAct module to call Elixir functions.

### 2. [PYTHON_TOOL_BRIDGE_COMMON.md](./PYTHON_TOOL_BRIDGE_COMMON.md)
Implementation details for the tool bridge across all four communication protocols (JSON, MessagePack, gRPC unary, and gRPC streaming).

### 3. [PYTHON_TOOL_BRIDGE_COMMON_generic.md](./PYTHON_TOOL_BRIDGE_COMMON_generic.md)
Explains the layered architecture with a generic RPC core and DSPy-specific integration layer.

## Implementation Guides

### 4. [ENHANCED_BRIDGE_ARCHITECTURE.md](./ENHANCED_BRIDGE_ARCHITECTURE.md)
Complete architectural overview of the enhanced bridge, including:
- Dynamic method invocation
- Framework plugins (DSPy, Transformers, Pandas)
- Object persistence and lifecycle
- Message flow diagrams

### 5. [STORED_OBJECT_RESOLUTION.md](./STORED_OBJECT_RESOLUTION.md)
Deep dive into the stored object resolution mechanism:
- How objects are stored and referenced
- The automatic resolution process
- Common use cases and patterns
- Implementation of `_resolve_stored_references`

### 6. [DEBUGGING_DSPY_INTEGRATION.md](./DEBUGGING_DSPY_INTEGRATION.md)
Practical debugging guide for DSPy integration issues:
- Common errors and solutions
- Step-by-step debugging workflows
- Testing strategies
- Prevention tips

## Quick Reference

### Setting Up DSPy with DSPex

```elixir
# Configure the language model
{:ok, _} = DSPex.LM.configure("gemini-2.0-flash-lite", api_key: api_key)

# Create a DSPy module
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")

# Use the module
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is DSPy?"})
```

### Common Issues

1. **"No LM is loaded"** - See [DEBUGGING_DSPY_INTEGRATION.md](./DEBUGGING_DSPY_INTEGRATION.md)
2. **Stored object not found** - See [STORED_OBJECT_RESOLUTION.md](./STORED_OBJECT_RESOLUTION.md)
3. **Bridge architecture questions** - See [ENHANCED_BRIDGE_ARCHITECTURE.md](./ENHANCED_BRIDGE_ARCHITECTURE.md)

### Key Concepts

- **Stored Objects**: Python objects persisted with IDs like `"stored.default_lm"`
- **Dynamic Invocation**: Call any Python method via `"module.Class.method"` syntax
- **Framework Plugins**: Specialized handlers for DSPy, Transformers, Pandas
- **Smart Serialization**: Automatic handling of complex Python objects

## Development Notes

When working on the bridge:

1. Test changes with the examples in `/examples/dspy/`
2. Enable debug logging: `BRIDGE_DEBUG=true mix run script.exs`
3. Check stored objects: Look for `"stored_objects"` in ping responses
4. Verify resolution: Add logging to `_resolve_stored_references`

## Future Enhancements

- Asynchronous tool support
- Streaming responses
- Additional framework plugins
- Performance optimizations for large objects
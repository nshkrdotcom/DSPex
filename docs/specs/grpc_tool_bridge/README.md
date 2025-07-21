# gRPC-Based Tool Bridge Architecture

This directory contains the revised technical specification for the DSPex tool bridge, built on our gRPC infrastructure to enable seamless bidirectional tool execution between DSPy (Python) and DSPex (Elixir).

## Documents

1. **[Technical Specification](technical_specification.md)** - Complete architectural design and implementation details
2. **[Protocol Definition](protocol_definition.md)** - gRPC service definitions and message formats
3. **[Implementation Guide](implementation_guide.md)** - Step-by-step implementation plan
4. **[Testing Strategy](testing_strategy.md)** - Comprehensive testing approach

## Key Design Principles

- **gRPC-First**: Built on existing gRPC infrastructure, not legacy stdin/stdout
- **Stateless Workers**: Python workers remain stateless with centralized session management
- **Async/Await**: Non-blocking tool execution with asyncio integration
- **Variable Integration**: Seamless integration with the variable bridge for shared state
- **Developer Experience**: Type hints, introspection, and rich error handling

## Architecture Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│   DSPy ReAct Agent  │     │  DSPex Application  │
└──────────┬──────────┘     └──────────┬──────────┘
           │                           │
           ▼                           ▼
┌─────────────────────┐     ┌─────────────────────┐
│  gRPC Proxy Tools   │     │   Tool Registry     │
└──────────┬──────────┘     └──────────┬──────────┘
           │                           │
           ▼                           ▼
┌─────────────────────────────────────────────────┐
│              gRPC Bidirectional Stream           │
│                  (HTTP/2 Multiplexed)            │
└─────────────────────────────────────────────────┘
           │                           │
           ▼                           ▼
┌─────────────────────┐     ┌─────────────────────┐
│  Python gRPC Client │     │  Elixir gRPC Server │
└─────────────────────┘     └─────────────────────┘
```

## Benefits Over Previous Design

1. **Unified Architecture**: Single communication system for all cross-language needs
2. **Mid-Stream Tool Calls**: Support for tool execution during active streaming
3. **True Concurrency**: Async tools with proper parallelism support
4. **Variable Bridge Integration**: Shared session state and "innovative variables"
5. **Production Ready**: Built on battle-tested gRPC with proper error handling
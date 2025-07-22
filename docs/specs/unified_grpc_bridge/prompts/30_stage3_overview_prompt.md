# Prompt: Implement Stage 3 Streaming and Reactive Capabilities

## Objective
Transform the bridge from a request-response system into a fully reactive platform by implementing variable watching via gRPC streams. Enable real-time synchronization between Elixir and Python with backend-aware watching mechanisms.

## Context
Stage 3 builds upon the variable system from Stages 1-2 to add:
- Real-time variable watching through streaming
- Reactive programming patterns in both languages
- Advanced variable types (choice and module)
- Performance optimizations through batch operations
- Backend-aware implementation (process messages for LocalState, gRPC for BridgedState)

## Key Innovation
The watching mechanism is backend-aware:
- LocalState uses efficient Erlang process messaging (essentially free)
- BridgedState leverages gRPC streaming for cross-language updates
- Both use the same high-level API, maintaining abstraction

## Requirements

### Core Features
1. Implement `WatchVariables` streaming for real-time updates
2. Create ObserverManager to decouple SessionStore from stream management
3. Add backend-specific watch implementations
4. Enable reactive programming patterns
5. Introduce advanced variable types
6. Ensure no "stale reads" through atomic observer registration

### Performance Targets
- Local watching: Process message passing (sub-microsecond)
- Bridged watching: ~1-2ms per update including gRPC overhead
- Support thousands of concurrent watchers
- Efficient filtering to reduce callback overhead

## Architecture

```
DSPex.Variables.watch/2
        ↓
LocalState.watch ←→ ObserverManager
   (Process Msgs)        ↓
                    Stream Processors
BridgedState.watch       ↓
   (gRPC Streams)   Python Updates
```

## Implementation Tasks

1. **Extend StateProvider Behaviour**
   - Add watch_variables/4 callback
   - Add unwatch_variables/2 callback
   - Add list_watchers/1 callback

2. **Implement LocalState Watching**
   - Use Agent for observer storage
   - Process-based notification system
   - Automatic cleanup on process death
   - Support filtering and debouncing

3. **Implement BridgedState Watching**
   - Create StreamConsumer GenServer
   - Manage gRPC streaming connections
   - Handle reconnection and errors
   - Synchronize with Python clients

4. **Create ObserverManager**
   - Centralized observer registration
   - Efficient notification dispatch
   - Prevent SessionStore bloat
   - Handle concurrent access

5. **Add Advanced Variable Types**
   - Implement choice type with enumeration
   - Implement module type for dynamic behavior
   - Ensure serialization compatibility

6. **Update High-Level API**
   - Add DSPex.Variables.watch/4
   - Add convenience functions
   - Support various filtering options
   - Enable debouncing

## Critical Design Decisions

### Stale Read Prevention
When `include_initial_values` is true, the server MUST:
1. Register the observer BEFORE reading initial values
2. Send initial values AFTER observer is active
3. Queue any concurrent updates after initial values

This guarantees no updates are missed between registration and stream activation.

### Process Cleanup
- Monitor all watcher processes
- Automatically unregister on process death
- Clean up gRPC streams on disconnect
- Prevent orphan watchers

### Filtering Architecture
Support filtering at multiple levels:
- Client-side: Reduce callback invocations
- Server-side: Reduce network traffic
- Debouncing: Limit update frequency
- Batch updates: Combine related changes

## Success Criteria

1. Same watch API works for both backends
2. Real-time updates with appropriate latency
3. Filtering reduces noise effectively
4. Dead watchers are automatically cleaned up
5. Advanced types work with validation
6. Python async iteration over changes
7. Bidirectional cross-language updates

## Next Steps
After implementing streaming:
1. Create comprehensive reactive examples
2. Benchmark streaming performance
3. Test with high-frequency updates
4. Document reactive patterns
5. Prepare for Stage 4 production hardening
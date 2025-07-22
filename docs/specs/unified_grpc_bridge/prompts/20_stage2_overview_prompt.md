# Stage 2 Implementation Overview Prompt

## Context
You are implementing Stage 2 (Cognitive Layer & Bridge Integration) of the unified gRPC bridge for DSPex. This stage introduces the high-level cognitive layer that provides an elegant, Elixir-first API. The key innovation is automatic backend switching: pure Elixir workflows get blazing-fast local state, while Python-dependent programs transparently use the gRPC bridge.

## Key Documents to Read First
1. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/42_revised_stage2_tool_dspy_module_integration.md` - The complete Stage 2 specification
2. Review Stage 1 implementation for context on the bridge infrastructure
3. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/43_revised_stage3_streaming_observation.md` - Understand future streaming requirements

## Implementation Goals
1. Create user-facing `DSPex.Context` and `DSPex.Variables` API
2. Implement pluggable state backend system (`StateProvider` behaviour)
3. Build LocalState (Agent-based) and BridgedState (gRPC) backends
4. Enable automatic, transparent backend switching
5. Integrate variables with DSPy modules via `VariableAwareMixin`
6. Update `DSPex.Program` to be context-aware
7. Prove the same code works in both pure-Elixir and hybrid modes

## Critical Innovation: Automatic Backend Switching
The `DSPex.Context` process automatically detects when Python components are added and upgrades itself from local to bridged state, migrating all data seamlessly. This provides:
- Sub-microsecond latency for pure Elixir workflows
- Automatic upgrade to bridge when Python is needed
- Zero configuration required from users
- Transparent state migration

## Architectural Overview
```
User Code
    ↓
DSPex.Variables API → DSPex.Context (GenServer)
                            ↓
                     StateProvider Behaviour
                        ↙         ↘
                LocalState     BridgedState
                (Agent)        (Uses Stage 1)
                              ↓
                         SessionStore → gRPC → Python
```

## Success Criteria
- Pure Elixir workflows achieve sub-microsecond variable operations
- Backend switching is transparent and preserves all state
- Python integration works seamlessly after switch
- Same user code works in both modes without modification
- Variable-aware DSPy modules automatically sync state

## Implementation Order
1. StateProvider behaviour definition
2. LocalState implementation (pure Elixir)
3. BridgedState implementation (Stage 1 integration)
4. DSPex.Context with auto-switching
5. DSPex.Variables high-level API
6. Python VariableAwareMixin
7. Integration tests

## Performance Targets
- LocalState: < 10 microseconds per operation
- Backend switch: < 50ms one-time cost
- BridgedState: < 2ms per operation (acceptable for LLM)

## Next Steps
After reading this overview, proceed to the individual implementation prompts:
1. `21_state_provider_prompt.md` - Define the backend abstraction
2. `22_local_state_prompt.md` - Implement the fast local backend
3. `23_bridged_state_prompt.md` - Implement the bridge backend
4. `24_dspex_context_prompt.md` - Create the smart context
5. `25_dspex_variables_prompt.md` - Build the user API
6. `26_python_integration_prompt.md` - Variable-aware DSPy modules
7. `27_integration_tests_prompt.md` - Comprehensive testing
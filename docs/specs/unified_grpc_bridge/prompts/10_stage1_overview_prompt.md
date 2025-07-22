# Stage 1 Implementation Overview Prompt

## Context
You are implementing Stage 1 (Core Variable Implementation) of the unified gRPC bridge for DSPex. This stage builds upon the protocol foundation from Stage 0 to add comprehensive variable management capabilities while keeping future architectural layers in mind.

## Key Documents to Read First
1. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/41_revised_stage1_core_variables.md` - The complete Stage 1 specification
2. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/40_revised_stage0_protocol_foundation.md` - Review Stage 0 foundation
3. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/42_revised_stage2_tool_dspy_module_integration.md` - Understand future layering

## Implementation Goals
1. Create Variable module as a first-class entity
2. Extend SessionStore with comprehensive variable management
3. Implement type system for basic types (float, integer, string, boolean)
4. Build gRPC handlers for all variable operations
5. Create Python SessionContext with caching
6. Enable bidirectional state synchronization
7. Design with future LocalState/BridgedState architecture in mind

## Critical Requirements
- Variables must be properly typed and versioned
- Both name and ID lookups must work
- Constraints must be enforced across languages
- Python caching must reduce server calls
- Batch operations must be efficient
- The implementation must not break existing tool functionality
- Design must support future optimization without the bridge

## Architecture Notes
While implementing the bridge infrastructure, remember that:
- This will become the `BridgedState` backend in Stage 2
- Pure Elixir workflows won't need this complexity
- The SessionStore we're extending will be wrapped by higher-level APIs
- Keep the implementation modular for future refactoring

## Success Criteria
- Variable CRUD operations work from both languages
- Type validation enforces constraints consistently
- Python cache improves performance measurably
- Batch operations reduce round trips
- State changes propagate immediately
- All Stage 0 functionality remains intact
- Tests prove cross-language synchronization

## Next Steps
After reading this overview, proceed to the individual implementation prompts in order:
1. `11_variable_module_prompt.md` - Create Variable module and extend Session
2. `12_sessionstore_extensions_prompt.md` - Add variable operations to SessionStore
3. `13_type_system_prompt.md` - Implement the type system
4. `14_grpc_handlers_prompt.md` - Create gRPC handlers
5. `15_python_sessioncontext_prompt.md` - Enhance Python with variables
6. `16_integration_tests_prompt.md` - Comprehensive cross-language tests
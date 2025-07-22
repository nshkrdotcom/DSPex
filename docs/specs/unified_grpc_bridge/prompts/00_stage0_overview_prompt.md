# Stage 0 Implementation Overview Prompt

## Context
You are implementing Stage 0 (Protocol Foundation) of the unified gRPC bridge for DSPex. This stage establishes the foundational protocol definitions and infrastructure that all subsequent stages will build upon.

## Key Documents to Read First
1. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/40_revised_stage0_protocol_foundation.md` - The complete Stage 0 specification
2. `/home/home/p/g/n/dspex/docs/specs/grpc_tool_bridge/bridge_design.md` - Original bridge design for context
3. `/home/home/p/g/n/dspex/docs/specs/unified_grpc_bridge/01_unified_variables_specification.md` - Unified architecture vision

## Implementation Goals
1. Create comprehensive protobuf definitions for the unified bridge
2. Update Python server with variable support and streaming
3. Enhance Elixir GRPCWorker with stdout-based readiness detection
4. Implement proper serialization with protobuf Any and JSON
5. Add telemetry and monitoring hooks
6. Create integration tests for the complete protocol

## Critical Requirements
- The protocol must support both tools AND variables in a unified way
- Streaming must be implemented for real-time variable watching
- Server startup must use stdout monitoring (not TCP polling) for robustness
- All types (float, integer, string, boolean, choice, module, embedding, tensor) must be supported
- The implementation must maintain backward compatibility with existing tool bridge functionality

## Success Criteria
- All protobuf messages compile without errors
- Python server starts reliably with "GRPC_READY:port" message
- Elixir client can successfully call all RPC methods
- Integration tests pass for both tools and variables
- Telemetry events are properly emitted
- No regressions in existing tool functionality

## Next Steps
After reading this overview, proceed to the individual implementation prompts in order:
1. `01_protobuf_definition_prompt.md` - Define the protocol
2. `02_python_server_prompt.md` - Implement Python server
3. `03_elixir_client_prompt.md` - Update Elixir client
4. `04_serialization_prompt.md` - Implement type serialization
5. `05_integration_tests_prompt.md` - Create comprehensive tests
# DSPex Three-Layer Architecture Migration Plan

## Overview
This document outlines the migration of DSPex to conform to the three-layer architecture where DSPex becomes a thin orchestration layer that delegates all implementation to SnakepitGRPCBridge.

## Current Non-Conformance Issues

### 1. Implementation Code in DSPex
The following directories contain implementation code that must be removed or migrated:
- `lib/dspex/contracts/` - Contract definitions (should be in Bridge)
- `lib/dspex/modules/` - Module implementations (should be in Bridge)  
- `lib/dspex/llm/` - LLM adapter logic (should be in Bridge)

### 2. Complex Logic in Main Module
The main `lib/dspex.ex` contains some implementation logic that should delegate to Bridge APIs.

## Migration Steps

### Phase 1: Prepare Bridge APIs
Ensure SnakepitGRPCBridge has complete APIs for:
- [x] Variables API (`api/variables.ex`)
- [x] Tools API (`api/tools.ex`)
- [x] DSPy API (`api/dspy.ex`)
- [x] Sessions API (`api/sessions.ex`)

### Phase 2: Update DSPex Functions
1. Update `predict/3` to call `SnakepitGRPCBridge.API.DSPy.predict/4`
2. Update `chain_of_thought/3` to use Bridge APIs
3. Update `react/4` to use Bridge APIs
4. Remove direct contract/module references

### Phase 3: Remove Implementation Directories
1. Archive existing code for reference
2. Delete `contracts/`, `modules/`, `llm/` directories
3. Update mix.exs to remove unnecessary dependencies

### Phase 4: Simplify Macros
1. Update `defdsyp` macro to generate Bridge API calls
2. Remove complex macro logic
3. Focus on developer convenience

## Backward Compatibility
To maintain compatibility during migration:
1. Create deprecation warnings for direct module usage
2. Provide migration guide for existing code
3. Keep function signatures unchanged where possible

## Verification
After migration, DSPex should:
- Have no implementation code
- Only contain orchestration and convenience functions
- Delegate all operations to SnakepitGRPCBridge APIs
- Pass all existing tests (with updated implementations)
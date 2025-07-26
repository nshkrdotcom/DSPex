# Slice 1: Basic Predict Implementation Guide

## Overview

This guide provides specific prompts and conversation flows for implementing Slice 1 of the migration: Basic Predict functionality. This is the foundation slice that proves the new architecture works.

## Slice 1 Goals

- Migrate DSPex.Predict to use new contract-based system
- Implement basic session management
- Add foundational telemetry
- Maintain 100% backward compatibility

## Pre-Implementation Checklist

Before starting, ensure you have:
- [ ] Current `dspex/predict.ex` file from `reorg-bridge` branch
- [ ] Access to docs 02, 03, 04, and 07
- [ ] Test file `test/dspex/predict_test.exs`
- [ ] Clean git branch: `git checkout -b slice-1-basic-predict`

## Conversation Flow

### Conversation 1: Create the Contract Module

**Objective**: Create DSPex.Contracts.Predict with explicit type definitions

**Source Documents**:
- `03_EXPLICIT_CONTRACTS_SPECIFICATION.md` - Section 4 (Contract Definitions)
- `07_SIMPLIFIED_MACRO_IMPLEMENTATION.md` - Contract examples

**Prompt**:
```text
I am starting to implement Slice 1: Basic Predict from our vertical slice migration plan (04_VERTICAL_SLICE_MIGRATION.md).

Our goal is to replace the string-based API with explicit, typed contracts as specified in 03_EXPLICIT_CONTRACTS_SPECIFICATION.md.

Here is the key specification from section 4 of that document:

--- PASTE lines 116-153 from 03_EXPLICIT_CONTRACTS_SPECIFICATION.md ---

Your task: Create the full Elixir module for `DSPex.Contracts.Predict` based on this specification. 

The module should:
1. Use DSPex.Contract behavior
2. Define the @python_class as "dspy.Predict"
3. Include defmethod for :create (__init__) that takes a signature parameter
4. Include defmethod for :predict (__call__) that takes a question parameter
5. Add a @moduledoc explaining its purpose as the explicit contract for dspy.Predict
6. Include a contract_version/0 function returning "1.0.0"

Make sure the returns specifications use proper types - :reference for create and {:struct, DSPex.Types.Prediction} for predict.
```

**Expected Output**: A complete contract module defining the Predict API

**Verification**:
- [ ] Module compiles without errors
- [ ] Contains all required defmethod calls
- [ ] Types are properly specified
- [ ] Has module documentation

### Conversation 2: Create the Prediction Type

**Objective**: Create the DSPex.Types.Prediction struct

**Source Documents**:
- `03_EXPLICIT_CONTRACTS_SPECIFICATION.md` - Section 2 (Typed Domain Models)

**Prompt**:
```text
Now I need to create the Prediction type that our contract references.

Based on section 2 of 03_EXPLICIT_CONTRACTS_SPECIFICATION.md (Typed Domain Models), specifically the DSPex.Types.Prediction example:

--- PASTE lines 52-77 from 03_EXPLICIT_CONTRACTS_SPECIFICATION.md ---

Your task: Create the complete DSPex.Types.Prediction module following this pattern.

Requirements:
1. Define the struct with fields: answer, confidence, reasoning, metadata
2. Include the @type specification
3. Implement from_python_result/1 that validates and constructs from Python output
4. Handle the case where Python returns unexpected format
5. Add @moduledoc explaining this is the typed representation of a DSPy prediction

The from_python_result should expect a map with at least an "answer" key and optionally "confidence", "reasoning", and other metadata fields.
```

**Expected Output**: Complete type module with validation

### Conversation 3: Create the Contract Infrastructure

**Objective**: Implement the DSPex.Contract behavior and defmethod macro

**Source Documents**:
- `07_SIMPLIFIED_MACRO_IMPLEMENTATION.md` - Contract implementation details

**Prompt**:
```text
I need to implement the base Contract infrastructure that our Predict contract uses.

Based on the contract system design in our architecture, create the DSPex.Contract module that provides:

1. A behavior that contract modules implement
2. A defmethod macro for defining contract methods
3. A __using__ macro that sets up contracts

Here's what defmethod should do:
- Take a method name, python name, params spec, and returns spec  
- Store these in module attributes for later use
- Generate no functions (that's done by ContractBased)

Example usage from our Predict contract:
```elixir
defmethod :create, :__init__,
  params: [signature: {:required, :string}],
  returns: :reference
```

The module should accumulate all methods in a @methods attribute that can be retrieved with __methods__/0.
```

**Expected Output**: Base contract infrastructure module

### Conversation 4: Implement ContractBased Wrapper

**Objective**: Create the macro that generates functions from contracts

**Source Documents**:
- `02_DECOMPOSED_DEFDSYP_DESIGN.md` - Section 2 (Contract-Based Wrapper)
- `07_SIMPLIFIED_MACRO_IMPLEMENTATION.md` - Step 6 (Contract-Based Wrapper)

**Prompt**:
```text
Now I need the ContractBased wrapper that uses contracts to generate typed functions.

From 02_DECOMPOSED_DEFDSYP_DESIGN.md section 2:

--- PASTE lines 41-64 from 02_DECOMPOSED_DEFDSYP_DESIGN.md ---

And implementation guidance from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md:

--- PASTE lines 276-314 from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md ---

Your task: Implement DSPex.Bridge.ContractBased that:

1. Provides a use_contract/1 macro
2. Reads method definitions from the contract module
3. Generates properly typed wrapper functions for each method
4. Handles parameter validation based on the contract
5. Delegates actual calls to DSPex.Bridge module

For now, keep it simple - just generate functions that:
- Validate required parameters are present
- Call DSPex.Bridge.create_instance for :create methods  
- Call DSPex.Bridge.call_method for other methods
- Return results in the specified type format

Don't worry about complex validation or transformation yet.
```

**Expected Output**: ContractBased macro module

### Conversation 5: Refactor DSPex.Predict

**Objective**: Update existing module to use new contract system

**Source Documents**:
- Current implementation from your codebase
- `02_DECOMPOSED_DEFDSYP_DESIGN.md` - Migration examples

**Prompt**:
```text
Time to refactor the existing DSPex.Predict module to use our new contract-based system.

Here is the current implementation:
--- PASTE current lib/dspex/predict.ex ---

Our new architecture (from 02_DECOMPOSED_DEFDSYP_DESIGN.md) specifies this pattern:

--- PASTE lines 298-324 from 02_DECOMPOSED_DEFDSYP_DESIGN.md ---

Your task: Refactor DSPex.Predict to:

1. Remove all the old implementation
2. Use DSPex.Bridge.ContractBased  
3. use_contract DSPex.Contracts.Predict
4. Keep the same public API for backward compatibility
5. Update the @moduledoc to explain it's now a contract-based wrapper

The contract-based macro should generate all the necessary functions, so the module will be quite small.

Important: We need to maintain backward compatibility, so if the old module had any additional helper functions, we should keep them.
```

**Expected Output**: Refactored Predict module using contracts

### Conversation 6: Add Basic Telemetry

**Objective**: Add telemetry events to bridge operations

**Source Documents**:
- `08_TELEMETRY_AND_OBSERVABILITY.md` - Core telemetry events

**Prompt**:
```text
Now let's add basic telemetry to our bridge operations as specified in our observability plan.

From 08_TELEMETRY_AND_OBSERVABILITY.md, here are the events we need:

--- PASTE lines 13-49 from 08_TELEMETRY_AND_OBSERVABILITY.md ---

Your task: Update the DSPex.Bridge module (or create it if it doesn't exist) to emit these telemetry events:

1. For create_instance:
   - [:dspex, :bridge, :create_instance, :start] 
   - [:dspex, :bridge, :create_instance, :stop]
   - [:dspex, :bridge, :create_instance, :exception]

2. For call_method:
   - [:dspex, :bridge, :call_method, :start]
   - [:dspex, :bridge, :call_method, :stop] 
   - [:dspex, :bridge, :call_method, :exception]

Use :telemetry.span/3 to automatically handle the start/stop/exception pattern.

Include meaningful metadata like python_class, method name, success status, and duration.
```

**Expected Output**: Bridge module with telemetry

### Conversation 7: Create Basic Session Manager

**Objective**: Implement minimal session management

**Source Documents**:
- `04_VERTICAL_SLICE_MIGRATION.md` - Slice 1 requirements

**Prompt**:
```text
For Slice 1, we need basic session management in SnakepitGrpcBridge.

Based on the requirements in 04_VERTICAL_SLICE_MIGRATION.md:

--- PASTE lines 33-40 from 04_VERTICAL_SLICE_MIGRATION.md ---

Your task: Create SnakepitGrpcBridge.Session.Manager with:

1. A GenServer that maintains session state
2. get_or_create/1 function that returns a session
3. Basic session struct with id and created_at
4. No persistence or variables yet (that's Slice 2)
5. Simple in-memory storage using a Map

Keep it minimal - just enough to pass through session_id to Python calls.

Example usage:
```elixir
session = SnakepitGrpcBridge.Session.Manager.get_or_create("session-123")
# Returns: %Session{id: "session-123", created_at: ~U[...]}
```
```

**Expected Output**: Basic session manager GenServer

### Conversation 8: Write Integration Tests

**Objective**: Ensure Slice 1 works end-to-end

**Source Documents**:
- `04_VERTICAL_SLICE_MIGRATION.md` - Success criteria
- `06_COGNITIVE_READINESS_TESTS.md` - Test patterns

**Prompt**:
```text
Let's write integration tests that verify Slice 1 works correctly.

From our success criteria in 04_VERTICAL_SLICE_MIGRATION.md:

--- PASTE lines 44-51 from 04_VERTICAL_SLICE_MIGRATION.md ---

Your task: Create test/dspex/predict_integration_test.exs that verifies:

1. The new contract-based Predict module works identically to the old one
2. Telemetry events are emitted correctly  
3. Basic session management works
4. The example from success criteria passes

Use the patterns from 06_COGNITIVE_READINESS_TESTS.md for capturing telemetry.

The test should:
- Create a predictor with DSPex.Predict.new/1
- Call it with a question
- Verify the result has an answer
- Check that telemetry events were emitted
- Ensure backward compatibility is maintained
```

**Expected Output**: Comprehensive integration test

## Verification Checklist

After completing all conversations:

- [ ] `mix compile` succeeds without warnings
- [ ] `mix test test/dspex/predict_test.exs` passes (existing tests)
- [ ] `mix test test/dspex/predict_integration_test.exs` passes (new tests)
- [ ] Telemetry events are captured in tests
- [ ] No breaking changes to public API
- [ ] Code follows patterns from architecture docs

## Commit Strategy

After each successful conversation:

```bash
# Conversation 1
git add lib/dspex/contracts/predict.ex
git commit -m "feat(slice1): Add DSPex.Contracts.Predict module"

# Conversation 2  
git add lib/dspex/types/prediction.ex
git commit -m "feat(slice1): Add Prediction type with validation"

# Continue for each conversation...
```

## Troubleshooting

### Issue: Contract module not found
**Solution**: Ensure DSPex.Contract behavior is implemented first (Conversation 3)

### Issue: Tests fail with undefined function
**Solution**: ContractBased macro may not be generating functions correctly. Review Conversation 4.

### Issue: Telemetry not captured in tests
**Solution**: Ensure test helper is properly attached to events. See examples in doc 06.

## Next Steps

Once Slice 1 is complete and all tests pass:

1. Create PR: "feat: Implement Slice 1 - Basic Predict with contracts"
2. Get code review focusing on:
   - Contract design
   - Backward compatibility
   - Telemetry completeness
3. Merge to main migration branch
4. Proceed to Slice 2: Session Variables

## Summary

Slice 1 establishes the foundation:
- ✅ Contract-based API replacing strings
- ✅ Type safety with explicit structs  
- ✅ Basic telemetry for observability
- ✅ Minimal session management
- ✅ 100% backward compatibility

This proves the architecture works and sets the pattern for remaining slices.
# Pre-Conversation Checklists and Session Preparation

## Overview

This document provides detailed checklists and preparation templates for each type of implementation task. Use these before starting any AI conversation to ensure productive sessions.

## Master Pre-Flight Checklist

Before ANY implementation conversation:

- [ ] **Git Status**: Clean working directory, on correct branch
- [ ] **Documentation Ready**: Relevant architecture docs identified and accessible
- [ ] **Current Code Located**: Know exactly which files you'll be modifying
- [ ] **Tests Identified**: Know which tests must pass after changes
- [ ] **Success Criteria Clear**: Can articulate exactly what "done" looks like
- [ ] **Rollback Plan**: Know how to undo changes if needed

## Task-Specific Checklists

### Checklist: New Contract Module

**Documentation Needed**:
- [ ] `03_EXPLICIT_CONTRACTS_SPECIFICATION.md` - Contract patterns
- [ ] DSPy documentation for the component being wrapped
- [ ] Examples of existing contracts in codebase

**Information to Gather**:
- [ ] Full Python class path (e.g., "dspy.ChainOfThought")
- [ ] List of methods to expose
- [ ] Parameter names and types for each method
- [ ] Return types for each method
- [ ] Optional vs required parameters

**Preparation Template**:
```text
Component: [e.g., ChainOfThought]
Python Class: dspy.[Component]
Methods to wrap:
  - __init__: 
    - Parameters: signature (required), rationale_type (optional, default="simple")
    - Returns: reference
  - __call__:
    - Parameters: inputs (required, map)
    - Returns: struct with reasoning and answer
```

### Checklist: Type Module Creation

**Documentation Needed**:
- [ ] `03_EXPLICIT_CONTRACTS_SPECIFICATION.md` - Type patterns
- [ ] Sample Python output for the type

**Information to Gather**:
- [ ] All possible fields in Python output
- [ ] Which fields are always present vs optional
- [ ] Data types of each field
- [ ] Validation rules needed

**Preparation Template**:
```text
Type: [e.g., ChainOfThoughtResult]
Python output example:
{
  "reasoning": ["step1", "step2", "step3"],
  "answer": "final answer",
  "confidence": 0.95,
  "metadata": {...}
}

Required fields: reasoning, answer
Optional fields: confidence, metadata
Validation: reasoning must be non-empty list
```

### Checklist: Refactoring Existing Module

**Documentation Needed**:
- [ ] Migration plan for this component
- [ ] New pattern documentation
- [ ] Current implementation

**Information to Gather**:
- [ ] Current file path
- [ ] Public API that must be preserved
- [ ] Current test file path
- [ ] Dependencies on this module

**Preparation Template**:
```text
Module: [e.g., DSPex.Predict]
Current location: lib/dspex/predict.ex
Public API to preserve:
  - new/1, new/2
  - call/2
  - __using__ macro (if applicable)
Tests: test/dspex/predict_test.exs
Depends on: DSPex.Bridge, SnakepitGrpcBridge
Used by: [list of modules]
```

### Checklist: Adding Behavior to Module

**Documentation Needed**:
- [ ] Behavior specification (e.g., Bidirectional, Observable)
- [ ] Implementation examples
- [ ] Current module code

**Information to Gather**:
- [ ] Which behaviors to add
- [ ] Required callbacks for each behavior
- [ ] Existing module structure
- [ ] Integration points

**Preparation Template**:
```text
Module: [Current module name]
Adding behaviors: [e.g., Bidirectional, Observable]
Required callbacks:
  - Bidirectional: elixir_tools/0, on_python_callback/3
  - Observable: telemetry_metadata/2
Current uses: [List current use statements]
Integration points: [Where behaviors hook in]
```

### Checklist: Writing Tests

**Documentation Needed**:
- [ ] `06_COGNITIVE_READINESS_TESTS.md` - Test patterns
- [ ] Existing test examples
- [ ] Module being tested

**Information to Gather**:
- [ ] Test scenarios to cover
- [ ] Expected behavior for each scenario  
- [ ] Error cases to test
- [ ] Telemetry events to verify

**Preparation Template**:
```text
Testing: [Module name]
Test file: test/[path]/[module]_test.exs
Scenarios:
  1. Happy path: [description]
     - Input: [example]
     - Expected: [output]
  2. Error case: [description]
     - Input: [example]
     - Expected: [error]
  3. Edge case: [description]
     - Input: [example]
     - Expected: [behavior]
Telemetry events: [List events to capture]
```

## Session Preparation Templates

### Template 1: Starting Fresh Implementation

```markdown
# Session Preparation: [Task Name]

## Objective
[One sentence describing what we're building]

## Context Documents
1. Primary: [Main architecture doc + relevant sections]
2. Secondary: [Supporting doc + relevant sections]
3. Examples: [Example doc or code + location]

## Current State
- Branch: `[branch-name]`
- Starting point: [Greenfield/Existing code at path]
- Dependencies: [What this relies on]

## Implementation Plan
1. [First concrete step]
2. [Second concrete step]
3. [Third concrete step]

## Success Criteria
- [ ] [Specific, measurable criterion]
- [ ] [Another criterion]
- [ ] Tests: [Which tests must pass]

## First Prompt Draft
[Draft your first prompt here following C.T.C.E.]
```

### Template 2: Debugging Session

```markdown
# Debug Session: [Issue Description]

## Problem
- Error message: [Exact error]
- When it occurs: [Specific trigger]
- Expected behavior: [What should happen]

## Investigation Done
- [ ] Checked logs: [Findings]
- [ ] Verified inputs: [What was passed]
- [ ] Tested isolation: [What worked/didn't]

## Relevant Code
```elixir
# Current implementation
[paste code]
```

## Hypothesis
[What you think is wrong]

## Debug Plan
1. [First thing to check]
2. [Second thing to try]
3. [Fallback approach]
```

### Template 3: Feature Addition

```markdown
# Feature Addition: [Feature Name]

## Feature Requirements
- User story: As a [user], I want [feature] so that [benefit]
- Technical requirements: [List specific needs]
- Constraints: [What to avoid]

## Integration Points
- Modifies: [List of files/modules affected]
- Depends on: [What must exist first]
- Used by: [What will use this feature]

## Design Decisions
- Pattern: [Which pattern from docs]
- Trade-offs: [What we're optimizing for]
- Non-goals: [What we're NOT doing]

## Implementation Steps
1. [First module/file to create]
2. [Second step]
3. [Integration step]
4. [Test addition]
```

## Quick Reference Cards

### Card 1: Contract Creation Quick Ref

```text
Contract Module Checklist:
□ use DSPex.Contract
□ @python_class "dspy.ClassName"  
□ @contract_version "1.0.0"
□ defmethod for each Python method
□ Parameter specs: {:required, type} or {:optional, type, default}
□ Return specs: :reference, :string, {:struct, Module}, etc.
□ @moduledoc with purpose
□ contract_version/0 function
```

### Card 2: Type Module Quick Ref

```text
Type Module Checklist:
□ defstruct with all fields
□ @type t() specification
□ from_python_result/1 that returns {:ok, struct} or {:error, reason}
□ Validation in from_python_result
□ Handle missing/optional fields with Map.get
□ @moduledoc explaining the type
□ Consider defaults in struct definition
```

### Card 3: Test Structure Quick Ref

```text
Test Module Checklist:
□ use ExUnit.Case
□ describe blocks for logical grouping
□ test names describe behavior not implementation
□ Setup block if needed
□ AAA pattern: Arrange, Act, Assert
□ Test both success and failure paths
□ Capture telemetry with test helpers
□ Clean up after tests (if needed)
```

### Card 4: Refactoring Safety Quick Ref

```text
Safe Refactoring Checklist:
□ All public functions preserved
□ Same function signatures
□ Same return value shapes
□ Existing tests still pass
□ No new dependencies added
□ Deprecation warnings if needed
□ Documentation updated
□ Typespec compatibility maintained
```

## Common Preparation Mistakes

### Mistake 1: Insufficient Context
**Problem**: Starting conversation without key documents
**Solution**: Always have 2-3 specific document sections ready

### Mistake 2: Vague Success Criteria
**Problem**: "Make it work better"
**Solution**: Define specific, measurable outcomes

### Mistake 3: No Code Examples
**Problem**: Describing patterns without showing them
**Solution**: Always include code snippets from docs or existing code

### Mistake 4: Forgetting Dependencies
**Problem**: Creating module that relies on non-existent code
**Solution**: Check what needs to exist first

### Mistake 5: No Test Plan
**Problem**: Writing code without knowing how to verify it
**Solution**: List specific test scenarios before coding

## Session Management Tips

### Tip 1: Keep Sessions Focused
- One major task per conversation
- Break complex tasks into steps
- Start new conversation when switching context

### Tip 2: Maintain Context Between Sessions
- Save successful outputs
- Note what was completed
- Create brief summary for next session

### Tip 3: Version Control Hygiene
- Commit after each successful step
- Use descriptive commit messages
- Tag important milestones

### Tip 4: Document Decisions
- Note why certain approaches were chosen
- Document any deviations from plan
- Keep running list of TODOs

## Emergency Procedures

### When Things Go Wrong

1. **Build Broken**
   ```bash
   git stash  # Save current work
   git checkout .  # Reset to last commit
   mix deps.get && mix compile  # Verify clean build
   ```

2. **Tests Failing**
   - Run specific test: `mix test test/file.exs:LINE`
   - Check for race conditions
   - Verify test isolation

3. **Unclear Requirements**
   - Return to architecture docs
   - Check existing similar implementations
   - Ask for clarification before proceeding

4. **Performance Issues**
   - Add basic timing logs
   - Check for N+1 queries
   - Profile before optimizing

## Summary

Effective AI-assisted development requires:
1. **Thorough Preparation**: Know what you want before asking
2. **Clear Documentation**: Have references ready
3. **Specific Goals**: Define success criteria
4. **Safety Measures**: Plan for rollback
5. **Incremental Progress**: Small, verified steps

Use these checklists and templates to ensure every AI conversation is productive and advances your migration goals.
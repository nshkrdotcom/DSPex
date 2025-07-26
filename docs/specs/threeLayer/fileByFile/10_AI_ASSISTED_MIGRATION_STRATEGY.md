# AI-Assisted Migration Strategy

## Executive Summary

This document outlines how to effectively use AI (Claude) as a pair programmer to implement the three-layer architecture migration. The key is treating AI as a highly capable but context-dependent partner who needs precise guidance.

## Core Philosophy: Technical Lead + AI Pair Programmer

You are the **Technical Lead** who:
- Holds the architectural vision
- Makes high-level decisions
- Provides precise context
- Verifies implementation quality

Claude is the **Pair Programmer** who:
- Writes code according to specifications
- Follows architectural patterns
- Executes specific tasks
- Provides implementation feedback

## The AI-Assisted Vertical Slice Workflow

### 1. Session Preparation (Pre-Flight Checklist)

Before starting any AI conversation, prepare three key elements:

#### A. Source of Truth Documents
Identify which architectural documents are relevant:
- For contract implementation: `03_EXPLICIT_CONTRACTS_SPECIFICATION.md`
- For macro decomposition: `02_DECOMPOSED_DEFDSYP_DESIGN.md`
- For testing strategy: `06_COGNITIVE_READINESS_TESTS.md`

#### B. Current State Code
Locate the existing implementation:
- Current module on `reorg-bridge` branch
- Related test files
- Dependencies and imports

#### C. Definition of Done
Define clear success criteria:
- What should the code do?
- What tests should pass?
- What patterns should it follow?

### 2. The C.T.C.E. Prompting Methodology

Structure every implementation prompt with four elements:

#### Context (The "Why")
- High-level goal
- Relevant architecture principles
- Specific documentation sections

#### Task (The "What")
- Clear, atomic action
- Current code state
- Expected outcome

#### Constraints (The "How")
- Architectural patterns to follow
- Specific requirements
- Expected structure

#### Example (The "Show Me")
- Before/after code samples
- Expected behavior
- Test cases

### 3. Conversation Scoping

Each AI conversation should focus on one vertical slice component:

**Good Scope**: "Implement the ContractBased wrapper for DSPex.Predict"
**Bad Scope**: "Migrate the entire session management system"

**Good Scope**: "Create tests for bidirectional tool calls"
**Bad Scope**: "Write all the tests"

### 4. Iterative Refinement

After each AI response:
1. **Review**: Does it match the architectural vision?
2. **Test**: Run the code, verify behavior
3. **Refine**: Provide specific feedback
4. **Iterate**: Continue until Definition of Done is met

## Implementation Workflow Examples

### Example 1: Implementing Contract-Based Wrapper

```text
=== CONVERSATION 1: Create the Contract Module ===

CONTEXT:
- Goal: Replace string-based API with typed contracts
- Architecture: Using explicit contracts from 03_EXPLICIT_CONTRACTS_SPECIFICATION.md
- Pattern: Contract modules define the API without runtime Python dependency

TASK:
- Create DSPex.Contracts.Predict module
- Define methods for __init__ and __call__
- Include proper type specifications

CONSTRAINTS:
- Follow the defmethod pattern shown in the docs
- Use @python_class attribute
- Include returns specifications

EXAMPLE:
From docs:
defmethod :predict, :__call__,
  params: [question: {:required, :string}],
  returns: {:struct, DSPex.Types.Prediction}
```

### Example 2: Migrating Existing Module

```text
=== CONVERSATION 2: Refactor Existing Module ===

CONTEXT:
- Goal: Update DSPex.Predict to use new contract system
- Current: String-based Bridge.call_method approach
- Target: Contract-based typed functions

TASK:
- Refactor lib/dspex/predict.ex
- Current code: [paste existing implementation]
- Use the contract module created in Conversation 1

CONSTRAINTS:
- Must pass all existing tests
- Use DSPex.Bridge.ContractBased
- Remove old string-based calls

EXAMPLE:
Before: Bridge.call_method(ref, "__call__", %{question: q})
After: Contract generates typed predict/2 function
```

## Common Patterns and Anti-Patterns

### ✅ Good Patterns

1. **Atomic Tasks**
   ```
   "Create the Session.Manager module with get_or_create/1 function"
   ```

2. **Specific Context**
   ```
   "Following pattern from section 4.2 of 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md"
   ```

3. **Clear Examples**
   ```
   "Like the ObservableWrapper example but for ChainOfThought"
   ```

### ❌ Anti-Patterns

1. **Vague Requests**
   ```
   "Make the code better"
   ```

2. **Missing Context**
   ```
   "Implement the new system" (without providing docs)
   ```

3. **Too Broad**
   ```
   "Migrate everything to the new architecture"
   ```

## Prompt Templates

### Template 1: New Module Creation

```text
CONTEXT:
I'm implementing [SLICE NAME] from our vertical slice migration plan.
This follows the architecture in [RELEVANT_DOC.md], specifically [SECTION].

TASK:
Create [MODULE_NAME] module that [SPECIFIC_FUNCTIONALITY].
This module should [KEY_BEHAVIORS].

CONSTRAINTS:
- Follow pattern from [PATTERN_REFERENCE]
- Include these functions: [FUNCTION_LIST]
- Use these behaviors: [BEHAVIOR_LIST]

EXAMPLE:
[RELEVANT_CODE_EXAMPLE]
The new module should work similarly but for [SPECIFIC_USE_CASE].
```

### Template 2: Code Refactoring

```text
CONTEXT:
Refactoring [MODULE] to use our new [FEATURE] system.
Old approach: [OLD_PATTERN_DESCRIPTION]
New approach: [NEW_PATTERN_DESCRIPTION] from [DOC_REFERENCE]

TASK:
Update the following code to use the new pattern:
[PASTE_CURRENT_CODE]

CONSTRAINTS:
- Maintain backward compatibility
- All existing tests must pass
- Follow the [SPECIFIC_PATTERN] approach

EXAMPLE:
Old: [OLD_CODE_SNIPPET]
New: [NEW_CODE_SNIPPET]
```

### Template 3: Test Implementation

```text
CONTEXT:
Writing tests for [FEATURE] based on our testing strategy.
This verifies [WHAT_IT_VERIFIES] as specified in [TEST_DOC].

TASK:
Create tests for [MODULE_NAME] that verify:
1. [TEST_CASE_1]
2. [TEST_CASE_2]
3. [TEST_CASE_3]

CONSTRAINTS:
- Use ExUnit.Case
- Follow patterns from [EXISTING_TEST_FILE]
- Include both happy path and error cases

EXAMPLE:
[EXAMPLE_TEST_CASE]
```

## Managing Multi-Conversation Workflows

### For Complex Features

When implementing a complex feature across multiple conversations:

1. **Create a Feature Branch**
   ```bash
   git checkout -b slice-1-basic-predict
   ```

2. **Track Progress**
   - Keep a local TODO.md with conversation outcomes
   - Commit after each successful conversation
   - Use clear commit messages referencing the slice

3. **Maintain Context**
   - Start each new conversation with a summary
   - Reference previous conversation outcomes
   - Provide updated code state

### Example Multi-Conversation Flow

```text
Conversation 1: Create Contract Module
└── Commit: "feat(slice1): Add DSPex.Contracts.Predict module"

Conversation 2: Create ContractBased Macro  
└── Commit: "feat(slice1): Implement ContractBased wrapper macro"

Conversation 3: Refactor DSPex.Predict
└── Commit: "feat(slice1): Migrate Predict to use contracts"

Conversation 4: Update Tests
└── Commit: "test(slice1): Update tests for contract-based Predict"

Conversation 5: Add Telemetry
└── Commit: "feat(slice1): Add telemetry to Predict operations"
```

## Quality Assurance Checklist

After each AI interaction:

- [ ] Code follows architectural principles?
- [ ] Matches patterns in documentation?
- [ ] Tests pass?
- [ ] No unnecessary complexity added?
- [ ] Comments and docs updated?
- [ ] Telemetry events included?
- [ ] Error handling appropriate?

## Common Challenges and Solutions

### Challenge: AI Adds Unnecessary Features
**Solution**: Be explicit about scope in constraints. Use "ONLY implement X, do not add Y"

### Challenge: AI Uses Wrong Patterns
**Solution**: Provide specific examples from docs. Reference exact line numbers.

### Challenge: AI Loses Context
**Solution**: Start new conversation with summary. Keep conversations focused.

### Challenge: Generated Code Too Complex
**Solution**: Ask for simpler approach. Reference "Explicit over Implicit" principle.

## Summary

Successful AI-assisted migration requires:
1. **Preparation**: Know what you want before asking
2. **Precision**: Provide exact context and constraints
3. **Iteration**: Refine based on output
4. **Verification**: Always test and review
5. **Documentation**: Keep the architectural vision clear

The AI is a powerful tool, but you remain the architect. Use it to accelerate implementation while maintaining quality and vision.
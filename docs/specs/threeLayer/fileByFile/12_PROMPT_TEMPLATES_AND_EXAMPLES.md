# Prompt Templates and Examples

## Overview

This document provides battle-tested prompt templates and real examples for implementing the DSPex migration using AI assistance. Each template follows the C.T.C.E. methodology (Context, Task, Constraints, Example).

## Core Templates

### Template 1: Contract Module Creation

**When to use**: Creating new contract modules for DSPy components

```text
CONTEXT:
I'm implementing the contract module for [COMPONENT_NAME] as part of our migration to explicit contracts.
This follows the specification in 03_EXPLICIT_CONTRACTS_SPECIFICATION.md, section 4 (Contract Definitions).

Our contracts define the Python API without requiring Python at compile time.

TASK:
Create the module DSPex.Contracts.[ComponentName] that defines the contract for dspy.[ComponentName].

The contract should include:
- @python_class attribute set to "dspy.[ComponentName]"
- defmethod calls for each Python method we need to wrap
- Proper parameter specifications with required/optional markers
- Return type specifications
- @moduledoc explaining the contract's purpose
- contract_version/0 function

CONSTRAINTS:
- Use the DSPex.Contract behavior
- Follow the defmethod pattern: defmethod :elixir_name, :python_name, params: [...], returns: type
- Parameter specs use {:required, type} or {:optional, type, default}
- Return types can be :reference, :string, :map, {:struct, Module}, {:list, type}
- No actual implementation - just contract definition

EXAMPLE:
From our Predict contract:
```elixir
defmethod :create, :__init__,
  params: [signature: {:required, :string}],
  returns: :reference

defmethod :predict, :__call__,
  params: [question: {:required, :string}],
  returns: {:struct, DSPex.Types.Prediction}
```
```

### Template 2: Type Module Creation

**When to use**: Creating typed structs for Python return values

```text
CONTEXT:
I need a typed struct to represent [RETURN_TYPE] from Python operations.
This is part of moving from generic maps to explicit types as described in 03_EXPLICIT_CONTRACTS_SPECIFICATION.md.

TASK:
Create DSPex.Types.[TypeName] module with:
- Struct definition with appropriate fields
- @type specification
- from_python_result/1 function that validates and constructs from Python output
- Proper error handling for invalid data

CONSTRAINTS:
- The struct should have all fields that Python might return
- from_python_result/1 must handle missing or invalid data gracefully
- Use pattern matching for validation
- Return {:ok, struct} or {:error, reason}
- Include @moduledoc and @doc strings

EXAMPLE:
```elixir
def from_python_result(%{"answer" => answer} = result) do
  {:ok, %__MODULE__{
    answer: answer,
    confidence: Map.get(result, "confidence"),
    metadata: Map.drop(result, ["answer", "confidence"])
  }}
end

def from_python_result(_), do: {:error, :invalid_prediction_format}
```
```

### Template 3: Macro Implementation

**When to use**: Creating the composable macro behaviors

```text
CONTEXT:
I'm implementing the [BEHAVIOR_NAME] macro as part of our decomposed macro system.
This replaces part of the old defdsyp god macro as described in 02_DECOMPOSED_DEFDSYP_DESIGN.md.

Reference the implementation pattern from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md.

TASK:
Create DSPex.Bridge.[BehaviorName] that:
- Defines a behavior with appropriate callbacks
- Provides a __using__ macro
- Integrates with the module attribute system
- Has default implementations where appropriate

CONSTRAINTS:
- Must be composable with other behaviors
- Use module attributes for metadata, not module variables
- Provide sensible defaults that can be overridden
- No complex macro magic - keep it simple and explicit
- Register behavior in @dspex_behaviors for orchestration

EXAMPLE:
```elixir
defmacro __using__(_opts) do
  quote do
    @behaviour DSPex.Bridge.Behaviours.[BehaviorName]
    Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
    @dspex_behaviors :[behavior_atom]
    
    # Default implementation
    def callback_name(args), do: :default_behavior
    defoverridable [callback_name: 1]
  end
end
```
```

### Template 4: Test Implementation

**When to use**: Writing tests for new functionality

```text
CONTEXT:
Writing tests for [FEATURE] following our testing strategy from 06_COGNITIVE_READINESS_TESTS.md.
These tests should verify [WHAT_THEY_VERIFY] and follow ExUnit patterns.

TASK:
Create test module [TestModuleName] that tests:
1. [SCENARIO_1]
2. [SCENARIO_2]
3. [SCENARIO_3]

Include both positive and negative test cases.

CONSTRAINTS:
- Use ExUnit.Case
- Follow AAA pattern (Arrange, Act, Assert)
- Use descriptive test names
- Include docstrings for complex tests
- Capture telemetry where relevant
- Test error conditions explicitly

EXAMPLE:
```elixir
describe "contract validation" do
  test "enforces required parameters" do
    # Arrange
    contract_module = TestContract
    
    # Act
    result = contract_module.validate_params(%{}, [:required_field])
    
    # Assert
    assert {:error, {:missing_required_field, _}} = result
  end
end
```
```

### Template 5: Refactoring Existing Code

**When to use**: Migrating existing modules to new patterns

```text
CONTEXT:
Refactoring [MODULE_NAME] to use our new [PATTERN_NAME] pattern.
Currently it uses [OLD_PATTERN] which we're replacing as part of the migration.
This is part of [SLICE_NAME] from 04_VERTICAL_SLICE_MIGRATION.md.

TASK:
Update the following module to use the new pattern:

[PASTE CURRENT CODE]

The refactored version should:
- [CHANGE_1]
- [CHANGE_2]
- [CHANGE_3]

CONSTRAINTS:
- Maintain backward compatibility for public API
- All existing tests must continue to pass
- Follow the new pattern exactly as specified
- Update documentation to reflect changes
- Don't add features not in the original

EXAMPLE:
Before:
```elixir
def old_pattern(arg) do
  Bridge.call_method(ref, "method", %{arg: arg})
end
```

After:
```elixir
def new_pattern(arg) do
  # Contract-based function generated by macro
  contract_method(ref, arg: arg)
end
```
```

## Real-World Examples

### Example 1: Creating ChainOfThought Contract

```text
CONTEXT:
I'm implementing the contract module for ChainOfThought as part of our migration to explicit contracts.
This follows the specification in 03_EXPLICIT_CONTRACTS_SPECIFICATION.md, section 4 (Contract Definitions).

Our contracts define the Python API without requiring Python at compile time.

TASK:
Create the module DSPex.Contracts.ChainOfThought that defines the contract for dspy.ChainOfThought.

Based on the DSPy documentation, ChainOfThought:
- Takes a signature and optional rationale_type in __init__
- Has a __call__ method that takes inputs and returns reasoning steps plus answer
- May have a forward method as well

The contract should include all necessary method definitions with proper types.

CONSTRAINTS:
- Use the DSPex.Contract behavior
- Follow the defmethod pattern from our Predict example
- rationale_type should be optional with default "simple"
- Return type should reference a proper struct type
- Include contract version "1.0.0"

EXAMPLE:
Our Predict contract uses:
```elixir
defmethod :create, :__init__,
  params: [signature: {:required, :string}],
  returns: :reference
```

ChainOfThought should follow the same pattern but with its specific parameters.
```

### Example 2: Adding Bidirectional Support

```text
CONTEXT:
I'm adding bidirectional support to our ChainOfThought wrapper so Python can call back to Elixir.
This implements the killer feature described in 01_REFACTORED_ARCHITECTURE_OVERVIEW.md section "Bidirectional Tool Bridge".

We want ChainOfThought to be able to validate reasoning steps using Elixir business logic.

TASK:
Update the ChainOfThought wrapper module to:
1. Use DSPex.Bridge.Bidirectional behavior
2. Define elixir_tools that Python can call
3. Include a reasoning validator tool

Here's the current module:
```elixir
defmodule DSPex.ChainOfThought do
  use DSPex.Bridge.ContractBased
  use_contract DSPex.Contracts.ChainOfThought
end
```

CONSTRAINTS:
- Keep all existing functionality
- Add only the bidirectional behavior
- Tools should be focused and single-purpose
- Follow the pattern from 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md
- Tool functions should return simple values Python can use

EXAMPLE:
From the docs, bidirectional tools look like:
```elixir
@impl DSPex.Bridge.Bidirectional
def elixir_tools do
  [
    {"validate_reasoning", &validate_reasoning_steps/1},
    {"fetch_context", &fetch_relevant_context/1}
  ]
end
```
```

### Example 3: Complex Test Scenario

```text
CONTEXT:
Writing integration tests for our bidirectional ChainOfThought implementation.
This follows the test patterns in 06_COGNITIVE_READINESS_TESTS.md section 3 (Bidirectional Communication Tests).

We need to verify Python successfully calls our Elixir validation tools.

TASK:
Create a test that:
1. Registers an Elixir reasoning validator
2. Creates a ChainOfThought instance that uses it
3. Verifies the validator was called from Python
4. Checks the reasoning meets our business rules

The test should simulate a real usage scenario where reasoning must contain "because" to be valid.

CONSTRAINTS:
- Use ExUnit.Case with descriptive test names
- Set up tools before the test
- Clean up after test completes
- Verify both success and failure cases
- Include telemetry verification
- Make the test deterministic

EXAMPLE:
The pattern from the docs:
```elixir
test "Python can call Elixir tools" do
  # Register tool
  DSPex.Tools.register("uppercase", fn %{"text" => text} ->
    String.upcase(text)
  end)
  
  # Use from Python component
  result = DSPex.Component.call(ref, %{text: "hello"})
  assert result == "HELLO"
end
```

Apply this pattern to ChainOfThought reasoning validation.
```

## Advanced Patterns

### Pattern 1: Multi-Module Coordination

When implementing features that span multiple modules:

```text
CONTEXT:
Implementing [FEATURE] which requires changes to:
- Module A: [CHANGE_DESCRIPTION]
- Module B: [CHANGE_DESCRIPTION]  
- Module C: [CHANGE_DESCRIPTION]

This is part of [SLICE] and the modules must work together.

TASK:
First, let's update Module A:
[SPECIFIC_CHANGES_FOR_A]

The other modules will be updated in subsequent messages to maintain coordination.

[Rest of standard template...]
```

### Pattern 2: Debugging Assistance

When something isn't working:

```text
CONTEXT:
I'm debugging an issue with [FEATURE]. The error is:
[PASTE ERROR MESSAGE]

This happens when [DESCRIBE WHEN IT OCCURS].

Current implementation:
[PASTE RELEVANT CODE]

TASK:
Help me identify the issue and provide a fix. The expected behavior is [EXPECTED].

CONSTRAINTS:
- Don't rewrite everything - just fix the specific issue
- Maintain all existing functionality
- Add debugging output if helpful
- Include error handling if missing

EXAMPLE:
Common issues with this pattern include [COMMON_ISSUE_1], [COMMON_ISSUE_2].
```

### Pattern 3: Performance Optimization

When addressing performance:

```text
CONTEXT:
Optimizing [OPERATION] which currently [PERFORMANCE_ISSUE].
Telemetry shows [METRICS] which indicates [PROBLEM].

This relates to the performance goals in 08_TELEMETRY_AND_OBSERVABILITY.md.

TASK:
Optimize the following code to [IMPROVEMENT_GOAL]:
[PASTE CURRENT IMPLEMENTATION]

CONSTRAINTS:
- Maintain exact same behavior
- Focus on [SPECIFIC_BOTTLENECK]
- Don't add complexity unless justified
- Include benchmarking code to verify improvement

EXAMPLE:
Similar optimization in [OTHER_MODULE] improved performance by [X%] using [TECHNIQUE].
```

## Tips for Effective Prompting

### 1. Be Specific About Versions
```text
# Good
"Using Elixir 1.14 and OTP 25"

# Bad  
"Using latest Elixir"
```

### 2. Include Actual Code
```text
# Good
"Here's the current implementation:
```elixir
defmodule Current do
  # actual code
end
```"

# Bad
"The current implementation uses the old pattern"
```

### 3. Reference Line Numbers
```text
# Good
"Following the pattern from lines 276-314 of 07_SIMPLIFIED_MACRO_IMPLEMENTATION.md"

# Bad
"Following the pattern from the macro implementation doc"
```

### 4. State Non-Goals Explicitly
```text
# Good
"Do NOT add caching or optimization - just the basic implementation"

# Bad
[Not mentioning what to avoid]
```

### 5. Provide Expected Output Format
```text
# Good
"The function should return {:ok, result} or {:error, reason}"

# Bad
"The function should handle errors"
```

## Common Pitfalls and Solutions

### Pitfall 1: Over-Engineering
**Problem**: AI adds unnecessary features
**Solution**: Use "ONLY implement X, do not add Y or Z"

### Pitfall 2: Wrong Patterns
**Problem**: AI uses patterns from wrong language/framework  
**Solution**: Explicitly state "This is Elixir, not Ruby/Python"

### Pitfall 3: Breaking Changes
**Problem**: AI changes public API
**Solution**: Always include "Maintain backward compatibility for all public functions"

### Pitfall 4: Missing Imports
**Problem**: AI forgets to include necessary imports
**Solution**: Show example with full module header including all imports

### Pitfall 5: Inconsistent Style
**Problem**: AI switches between styles
**Solution**: Provide style example: "Follow this exact style: [example]"

## Summary

Effective prompting requires:
1. **Clear Context**: What are we building and why
2. **Specific Tasks**: Exactly what to do
3. **Explicit Constraints**: What rules to follow
4. **Concrete Examples**: Show the pattern to follow

The templates in this document have been tested across dozens of migration tasks and consistently produce high-quality, architecture-compliant code.
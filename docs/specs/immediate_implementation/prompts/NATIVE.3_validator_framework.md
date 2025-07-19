# Task: NATIVE.3 - Validator Framework Implementation

## Context
You are implementing the validator framework for DSPex, which provides runtime validation for DSPy inputs and outputs. This framework ensures data integrity and provides clear error messages for invalid data.

## Required Reading

### 1. Core Architecture Documentation
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Read sections on "Native Signature Engine" and "Type System"
  - Focus on lines explaining validation requirements

### 2. Existing Validator Implementation
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/validator.ex`
  - Review the current structure and approach
  - Note any existing patterns to maintain consistency

### 3. Signature Module Integration
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/signature.ex`
  - Lines 1-50: Understand signature structure
  - Focus on how validators will integrate with signatures

### 4. Type System from libStaging
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 97-113: ML-specific types (embeddings, probability, confidence)
  - Lines 56-72: Variable types that need validation

### 5. Requirements Reference
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/REQUIREMENTS.md`
  - Section: "Functional Requirements" - FR.4 (Type validation)
  - Section: "Non-Functional Requirements" - NFR.1 (Performance targets)

## Implementation Requirements

### Core Validator Types
1. **String Validators**
   - Length constraints (min, max)
   - Pattern matching (regex)
   - Enum validation (allowed values)

2. **Numeric Validators**
   - Range validation (min, max)
   - Step validation
   - Type coercion (int/float)

3. **Collection Validators**
   - List length constraints
   - Element type validation
   - Uniqueness constraints

4. **ML-Specific Validators**
   - Probability (0.0-1.0)
   - Confidence scores
   - Embeddings (vector dimensions)
   - Tensor shapes

### Validator Protocol
```elixir
defprotocol DSPex.Validator do
  @spec validate(t(), any()) :: :ok | {:error, String.t()}
  def validate(validator, value)
  
  @spec describe(t()) :: String.t()
  def describe(validator)
end
```

### Implementation Structure
```
lib/dspex/native/
├── validator.ex              # Main module and protocol
├── validators/
│   ├── string.ex            # String validators
│   ├── numeric.ex           # Numeric validators
│   ├── collection.ex        # Collection validators
│   └── ml_specific.ex       # ML-specific validators
```

## Acceptance Criteria
- [ ] Validator protocol defined with validate/2 and describe/1
- [ ] All basic validators implemented (string, numeric, collection)
- [ ] ML-specific validators implemented
- [ ] Composable validators (combine multiple validators)
- [ ] Clear error messages with context
- [ ] Performance: <0.1ms for simple validations
- [ ] 100% test coverage for all validators
- [ ] Documentation with examples for each validator type

## Testing Requirements
Create comprehensive tests in:
- `test/dspex/native/validator_test.exs`
- `test/dspex/native/validators/` (one file per validator module)

Test cases must include:
- Valid inputs
- Invalid inputs with specific error messages
- Edge cases (nil, empty, extreme values)
- Performance benchmarks

## Example Implementation Pattern
```elixir
defmodule DSPex.Native.Validators.Probability do
  defstruct []
  
  defimpl DSPex.Validator do
    def validate(_validator, value) when is_number(value) and value >= 0.0 and value <= 1.0 do
      :ok
    end
    
    def validate(_validator, value) when is_number(value) do
      {:error, "probability must be between 0.0 and 1.0, got #{value}"}
    end
    
    def validate(_validator, _value) do
      {:error, "probability must be a number"}
    end
    
    def describe(_validator) do
      "a number between 0.0 and 1.0"
    end
  end
end
```

## Dependencies
- This task depends on CORE.1 being complete
- Coordinate with NATIVE.1 (Signature Parser) for integration points
- Will be used by ROUTER.1 for input validation

## Time Estimate
6 hours total:
- 2 hours: Core protocol and basic validators
- 2 hours: ML-specific validators
- 1 hour: Integration with signature system
- 1 hour: Comprehensive testing

## Notes
- Focus on clear, actionable error messages
- Consider using Ecto.Changeset patterns for familiarity
- Ensure validators are composable for complex validation scenarios
- Performance is critical - these will run on every DSPy call
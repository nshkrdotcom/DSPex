# Task: LLM.2 - InstructorLite Adapter Implementation

## Context
You are implementing the InstructorLite adapter for DSPex, which provides structured output generation using the InstructorLite library. This adapter is crucial for operations requiring validated, typed responses from LLMs.

## Required Reading

### 1. InstructorLite Documentation
- **Package**: Check the InstructorLite hex package documentation
- Focus on:
  - `InstructorLite.instruct/2` function
  - Schema definition patterns
  - Error handling

### 2. Existing InstructorLite Adapter
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapters/instructor_lite.ex`
  - Review current implementation
  - Note integration patterns with response_model

### 3. libStaging InstructorLite Example
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 127-131: InstructorLite integration example
  - Note structured output support pattern

### 4. LLM Adapter Protocol
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/prompts/LLM.1_adapter_protocol.md`
  - Review the protocol that must be implemented
  - Focus on structured output requirements

### 5. Test Examples
- **File**: `/home/home/p/g/n/dspex/test/dspex/llm/adapters/instructor_lite_test.exs`
  - Review existing test patterns
  - Note mock setup if present

### 6. Success Criteria
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Section: "Stage 6: Adaptive LLM Architecture"
  - Focus on InstructorLite selection criteria

## Implementation Requirements

### Adapter Module Structure
```elixir
defmodule DSPex.LLM.Adapters.InstructorLite do
  @behaviour DSPex.LLM.Adapter
  
  defstruct [
    :config,
    :client,
    :default_model,
    :retry_config
  ]
  
  # Required protocol implementations
  def capabilities(_adapter)
  def generate(adapter, prompt, opts)
  def stream(_adapter, _prompt, _opts)  # Not supported
  def validate_config(adapter)
  def format_messages(adapter, messages)
  def extract_content(adapter, response)
end
```

### Schema Conversion
Convert DSPex schemas to InstructorLite format:
```elixir
# DSPex schema format
%{
  name: :string,
  age: :integer,
  tags: {:array, :string},
  metadata: %{
    created_at: :datetime,
    score: :float
  }
}

# Convert to InstructorLite response_model
%{
  name: "string",
  age: "integer", 
  tags: ["string"],
  metadata: %{
    created_at: "datetime",
    score: "float"
  }
}
```

### Configuration Options
```elixir
%{
  # InstructorLite specific
  adapter_module: InstructorLite.Adapters.OpenAI,  # or Anthropic, etc.
  adapter_config: %{
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-3.5-turbo"
  },
  
  # Common options
  max_retries: 3,
  validation_retries: 2,
  timeout: 30_000,
  
  # Advanced options
  response_model_type: :simple | :detailed,
  include_raw_response: false
}
```

### Error Handling
Handle InstructorLite-specific errors:
```elixir
case InstructorLite.instruct(messages, config) do
  {:ok, result} ->
    {:ok, result}
    
  {:error, %{type: :validation_error, errors: errors}} ->
    {:error, format_validation_errors(errors)}
    
  {:error, %{type: :api_error, message: message}} ->
    {:error, {:api_error, message}}
    
  {:error, reason} ->
    {:error, {:instructor_error, reason}}
end
```

## Acceptance Criteria
- [ ] Implements all DSPex.LLM.Adapter protocol functions
- [ ] Converts DSPex schemas to InstructorLite format correctly
- [ ] Supports multiple underlying providers (OpenAI, Anthropic, etc.)
- [ ] Handles validation errors with clear messages
- [ ] Includes retry logic for transient failures
- [ ] Properly formats chat messages for the provider
- [ ] Extracts structured content from responses
- [ ] Includes comprehensive error handling
- [ ] Performance: <200ms overhead for structured parsing

## Testing Requirements
Create/update tests in:
- `test/dspex/llm/adapters/instructor_lite_test.exs`

Test scenarios:
- Simple structured output generation
- Complex nested schemas
- Array and optional field handling
- Validation error cases
- API error handling
- Retry behavior
- Multiple provider backends

## Example Usage
```elixir
# Create adapter
adapter = %DSPex.LLM.Adapters.InstructorLite{
  config: %{
    adapter_module: InstructorLite.Adapters.OpenAI,
    adapter_config: %{
      api_key: "...",
      model: "gpt-3.5-turbo"
    }
  }
}

# Generate structured output
{:ok, user} = DSPex.LLM.Adapter.generate(
  adapter,
  "Generate a user profile for a software developer",
  schema: %{
    name: :string,
    experience_years: :integer,
    skills: {:array, :string},
    contact: %{
      email: :string,
      github: {:optional, :string}
    }
  }
)

# Result
%{
  "name" => "Jane Smith",
  "experience_years" => 8,
  "skills" => ["Elixir", "Python", "React"],
  "contact" => %{
    "email" => "jane@example.com",
    "github" => "janesmith"
  }
}
```

## Dependencies
- Requires LLM.1 (Adapter Protocol) to be complete
- Depends on InstructorLite hex package
- May require environment variables for API keys

## Time Estimate
6 hours total:
- 2 hours: Core adapter implementation
- 1 hour: Schema conversion logic
- 1 hour: Error handling and retries
- 1 hour: Multi-provider support
- 1 hour: Comprehensive testing

## Notes
- InstructorLite already handles much complexity
- Focus on clean integration with DSPex schemas
- Ensure good error messages for schema mismatches
- Consider caching compiled schemas
- Add telemetry events for structured generation
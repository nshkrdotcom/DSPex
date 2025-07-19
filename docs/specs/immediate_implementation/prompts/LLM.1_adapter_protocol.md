# Task: LLM.1 - Adapter Protocol Definition

## Context
You are defining the adapter protocol that all LLM integrations will implement. This protocol enables DSPex to work with multiple LLM providers (OpenAI, Anthropic, Google, local models) through a unified interface while allowing provider-specific optimizations.

## Required Reading

### 1. Adaptive LLM Architecture Design
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/02_CORE_COMPONENTS_DETAILED.md`
  - Section: "Component 4: Adaptive LLM Architecture"
  - Focus on adapter behavior and selection logic

### 2. Existing Adapter Implementation
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapter.ex`
  - Review current protocol definition
  - Note any existing patterns to maintain

### 3. libStaging Adapter Patterns
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 117-136: LLM Adapter System examples
  - Lines 122-125: Protocol definition pattern
  - Lines 133-136: Client Manager integration

### 4. Existing Adapter Implementations
- **File**: `/home/home/p/g/n/dspex/lib/dspex/llm/adapters/`
  - Review existing adapters for common patterns:
    - `instructor_lite.ex`
    - `http.ex`
    - `python.ex`
    - `mock.ex`

### 5. Requirements Reference
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/REQUIREMENTS.md`
  - Section: "Functional Requirements" - FR.6 (Multi-provider LLM support)
  - Section: "Integration Requirements" - IR.2 (LLM providers)

## Protocol Definition Requirements

### Core Protocol Functions
```elixir
defprotocol DSPex.LLM.Adapter do
  @doc "Get adapter capabilities"
  @spec capabilities(t()) :: %{
    streaming: boolean(),
    structured_output: boolean(),
    max_tokens: integer(),
    supports_functions: boolean(),
    supports_vision: boolean()
  }
  def capabilities(adapter)

  @doc "Generate a completion"
  @spec generate(t(), prompt :: String.t(), opts :: keyword()) ::
    {:ok, String.t() | map()} | {:error, term()}
  def generate(adapter, prompt, opts)

  @doc "Stream a completion"
  @spec stream(t(), prompt :: String.t(), opts :: keyword()) ::
    {:ok, Enumerable.t()} | {:error, term()}
  def stream(adapter, prompt, opts)

  @doc "Validate configuration"
  @spec validate_config(t()) :: :ok | {:error, String.t()}
  def validate_config(adapter)

  @doc "Format messages for the provider"
  @spec format_messages(t(), messages :: list()) :: list()
  def format_messages(adapter, messages)

  @doc "Extract content from response"
  @spec extract_content(t(), response :: map()) :: String.t() | map()
  def extract_content(adapter, response)
end
```

### Adapter Configuration Structure
```elixir
defmodule DSPex.LLM.AdapterConfig do
  @type t :: %{
    # Common fields
    timeout: integer(),
    max_retries: integer(),
    retry_delay: integer(),
    
    # Provider-specific
    api_key: String.t() | nil,
    base_url: String.t() | nil,
    model: String.t(),
    
    # Advanced options
    headers: map(),
    middleware: list(),
    pool_config: keyword()
  }
end
```

### Selection Criteria Structure
```elixir
defmodule DSPex.LLM.Requirements do
  @type t :: %{
    structured_output: boolean() | nil,
    streaming: boolean() | nil,
    max_tokens: integer() | nil,
    latency_requirement: :low | :normal | :high | nil,
    cost_preference: :minimize | :balanced | :quality | nil,
    features_required: list(atom())
  }
end
```

## Implementation Structure
```
lib/dspex/llm/
├── adapter.ex              # Protocol definition
├── adapter_config.ex       # Configuration structure
├── requirements.ex         # Requirements structure
├── selector.ex            # Adapter selection logic
└── registry.ex            # Adapter registration
```

## Acceptance Criteria
- [ ] Protocol defined with all required functions
- [ ] Configuration structure supports all providers
- [ ] Requirements structure enables intelligent selection
- [ ] Registry for dynamic adapter registration
- [ ] Selector implements smart adapter choice logic
- [ ] All functions have proper typespecs
- [ ] Comprehensive documentation with examples
- [ ] Behavior tests for protocol compliance

## Example Usage Patterns
```elixir
# Basic usage
adapter = DSPex.LLM.Selector.select(
  requirements: %{structured_output: true},
  available: [:instructor_lite, :http, :python]
)

{:ok, response} = DSPex.LLM.Adapter.generate(
  adapter,
  "Generate a user profile",
  schema: %{name: :string, age: :integer}
)

# Streaming usage
{:ok, stream} = DSPex.LLM.Adapter.stream(
  adapter,
  "Tell me a story",
  max_tokens: 1000
)

# Provider-specific optimization
adapter = %DSPex.LLM.Adapters.OpenAI{
  config: %{
    model: "gpt-4",
    temperature: 0.7,
    functions: [...]  # OpenAI-specific
  }
}
```

## Testing Requirements
Create tests in:
- `test/dspex/llm/adapter_test.exs` - Protocol compliance tests
- `test/dspex/llm/selector_test.exs` - Selection logic tests

Test cases:
- Protocol implementation compliance
- Adapter selection based on requirements
- Configuration validation
- Error handling
- Fallback behavior

## Dependencies
- This is a foundational task - many others depend on it
- CORE.1 must be complete
- Will be implemented by LLM.2, LLM.3, LLM.4, LLM.5

## Time Estimate
4 hours total:
- 1 hour: Protocol definition and structures
- 1 hour: Registry and selector logic
- 1 hour: Documentation and examples
- 1 hour: Testing framework

## Notes
- Keep protocol minimal but extensible
- Support both simple string and structured outputs
- Consider future additions (vision, audio, embeddings)
- Ensure easy addition of new providers
- Include metadata in responses for telemetry
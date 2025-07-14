# DSPy Workflow Architecture in DSPex

## Core DSPy Concepts

### 1. Basic DSPy Workflow

```python
# Step 1: Configure Language Model
import dspy
lm = dspy.OpenAI(model='gpt-3.5-turbo')  # or dspy.Google('gemini-pro')
dspy.settings.configure(lm=lm)

# Step 2: Define Signature (Input/Output Schema)
class BasicQA(dspy.Signature):
    """Answer questions with short factual answers."""
    question = dspy.InputField()
    answer = dspy.OutputField(desc="often between 1 and 5 words")

# Step 3: Create Program
qa_program = dspy.Predict(BasicQA)

# Step 4: Execute Program (THIS CALLS THE LM!)
response = qa_program(question="What is the capital of France?")
print(response.answer)  # "Paris"
```

## What DSPex Currently Does vs What It Needs

### Current Implementation (Incomplete)
```elixir
# DSPex currently handles:
1. Creating program with signature
2. Storing program reference
3. Executing program with inputs
4. Returning outputs

# BUT it's missing:
- LM configuration before execution
- Model selection per program or globally
```

### What's Actually Happening

When DSPex executes a program:

```elixir
# Elixir side
{:ok, result} = DSPex.execute_program(program_id, %{question: "What is the capital of France?"})

# Python bridge receives:
# command: "execute_program"
# args: {program_id: "...", inputs: {question: "..."}}

# Python tries to execute:
program = self.programs[program_id]
result = program(**inputs)  # <- FAILS HERE because no LM configured!
```

## Required Architecture Changes

### 1. LM Configuration API

```elixir
# Option A: Global LM configuration
DSPex.configure_lm(%{
  provider: :openai,  # :openai, :google, :anthropic, :cohere
  model: "gpt-3.5-turbo",
  api_key: "...",
  temperature: 0.7
})

# Option B: Per-program LM configuration
{:ok, program_id} = DSPex.create_program(%{
  signature: @basic_qa,
  lm_config: %{
    provider: :google,
    model: "gemini-pro",
    api_key: System.get_env("GEMINI_API_KEY")
  }
})

# Option C: Per-execution LM override
{:ok, result} = DSPex.execute_program(program_id, inputs, %{
  lm_config: %{provider: :anthropic, model: "claude-3"}
})
```

### 2. Python Bridge LM Management

```python
class DSPyBridge:
    def __init__(self):
        self.programs = {}
        self.lm_configs = {}  # Store LM configurations
        self.active_lm = None  # Current active LM
    
    def configure_lm(self, args):
        """Configure language model for DSPy"""
        provider = args['provider']
        model = args['model']
        api_key = args.get('api_key')
        
        if provider == 'google':
            lm = dspy.Google(
                model=model,
                api_key=api_key,
                temperature=args.get('temperature', 0.7)
            )
        elif provider == 'openai':
            lm = dspy.OpenAI(
                model=model,
                api_key=api_key,
                temperature=args.get('temperature', 0.7)
            )
        # ... other providers
        
        dspy.settings.configure(lm=lm)
        self.active_lm = lm
        return {"status": "configured", "provider": provider, "model": model}
    
    def create_program(self, args):
        """Create program with optional LM config"""
        program_id = args['id']
        
        # Configure LM if provided
        if 'lm_config' in args:
            self.configure_lm(args['lm_config'])
            self.lm_configs[program_id] = args['lm_config']
        
        # Create program...
        
    def execute_program(self, args):
        """Execute with proper LM context"""
        program_id = args['program_id']
        
        # Switch to program's LM if different
        if program_id in self.lm_configs:
            self.configure_lm(self.lm_configs[program_id])
        elif not self.active_lm:
            raise RuntimeError("No LM is loaded")
        
        # Now execute...
```

### 3. Session-Based LM Configuration (with Pooling)

```python
class DSPyBridge:
    def __init__(self, mode='standalone'):
        self.mode = mode
        if mode == 'pool-worker':
            # Each worker maintains session-specific LM configs
            self.session_lms = {}  # {session_id: lm_config}
    
    def execute_in_session(self, session_id, command, args):
        # Restore session's LM configuration
        if session_id in self.session_lms:
            self.configure_lm(self.session_lms[session_id])
        
        # Execute command...
```

## Complete Workflow Example

```elixir
# 1. Start DSPex with LM configuration
{:ok, _} = DSPex.start_link(%{
  default_lm: %{
    provider: :google,
    model: "gemini-pro",
    api_key: System.get_env("GEMINI_API_KEY")
  }
})

# 2. Create a program (inherits default LM)
{:ok, qa_program} = DSPex.create_program(%{
  signature: %{
    name: "BasicQA",
    docstring: "Answer questions with short factual answers",
    inputs: [%{name: "question", type: "string"}],
    outputs: [%{name: "answer", type: "string", desc: "often between 1 and 5 words"}]
  }
})

# 3. Execute program (LM is already configured)
{:ok, result} = DSPex.execute_program(qa_program, %{
  question: "What is the capital of France?"
})
# => %{answer: "Paris"}

# 4. Switch models for different use case
{:ok, creative_program} = DSPex.create_program(%{
  signature: @creative_writing,
  lm_config: %{
    provider: :openai,
    model: "gpt-4",
    temperature: 0.9  # More creative
  }
})
```

## Test Environment Implications

```elixir
# For tests, we need mock LMs that don't make API calls
defmodule DSPex.Test.MockLM do
  def configure_test_lm(mode) do
    case mode do
      :deterministic ->
        %{
          provider: :mock,
          responses: %{
            "What is the capital of France?" => "Paris",
            "default" => "mock response"
          }
        }
      
      :random ->
        %{
          provider: :mock,
          response_generator: fn _input -> 
            "mock_#{:rand.uniform(1000)}"
          end
        }
    end
  end
end
```

## Implementation Priority

1. **Phase 1**: Add basic LM configuration
   - `configure_lm/1` function
   - Python bridge `configure_lm` handler
   - Default LM in application config

2. **Phase 2**: Per-program LM support
   - Store LM config with programs
   - Switch LMs on execution

3. **Phase 3**: Session-based LM management
   - LM config per session
   - Pool worker LM isolation

4. **Phase 4**: Advanced features
   - LM caching and connection pooling
   - Multi-model ensembles
   - Cost tracking per LM call
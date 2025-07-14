# Language Model Delegation - Minimum Implementation

## Overview
This document outlines the minimum implementation required to add LM delegation to DSPex, enabling the system to actually execute DSPy programs with configured language models.

## Supported Models (Hardcoded)

```elixir
@supported_models %{
  "gemini-2.0-flash-exp" => %{
    provider: :google,
    display_name: "Gemini 2.0 Flash (Experimental)",
    default_temperature: 0.7
  },
  "gemini-1.5-pro" => %{
    provider: :google,
    display_name: "Gemini 1.5 Pro",
    default_temperature: 0.7
  },
  "gemini-1.5-flash" => %{
    provider: :google,
    display_name: "Gemini 1.5 Flash",
    default_temperature: 0.7
  }
}
```

## Minimum API Design

### 1. Configure Default LM (Application Level)

```elixir
# In config/config.exs or runtime.exs
config :dspex,
  default_lm: %{
    model: "gemini-1.5-flash",
    api_key: System.get_env("GEMINI_API_KEY"),
    temperature: 0.7
  }
```

### 2. Set LM at Runtime

```elixir
# Set global default
DSPex.set_lm("gemini-1.5-pro", api_key: System.get_env("GEMINI_API_KEY"))

# Or with options
DSPex.set_lm("gemini-1.5-flash", 
  api_key: System.get_env("GEMINI_API_KEY"),
  temperature: 0.9
)
```

### 3. Execute with LM Context

```elixir
# Uses default LM
{:ok, result} = DSPex.execute_program(program_id, %{question: "What is 2+2?"})

# Override LM for this execution
{:ok, result} = DSPex.execute_program(program_id, 
  %{question: "What is 2+2?"}, 
  lm: "gemini-2.0-flash-exp"
)
```

## Implementation Details

### 1. Elixir Side Updates

#### DSPex Module Addition

```elixir
defmodule DSPex do
  @supported_models %{
    "gemini-2.0-flash-exp" => %{provider: :google, display_name: "Gemini 2.0 Flash (Experimental)"},
    "gemini-1.5-pro" => %{provider: :google, display_name: "Gemini 1.5 Pro"},
    "gemini-1.5-flash" => %{provider: :google, display_name: "Gemini 1.5 Flash"}
  }
  
  @doc """
  Sets the default language model for all operations.
  
  ## Examples
      
      DSPex.set_lm("gemini-1.5-pro", api_key: System.get_env("GEMINI_API_KEY"))
  """
  def set_lm(model_name, opts \\ []) when is_binary(model_name) do
    unless Map.has_key?(@supported_models, model_name) do
      raise ArgumentError, "Unsupported model: #{model_name}. Supported models: #{Map.keys(@supported_models) |> Enum.join(", ")}"
    end
    
    config = %{
      model: model_name,
      api_key: Keyword.get(opts, :api_key, get_default_api_key()),
      temperature: Keyword.get(opts, :temperature, 0.7)
    }
    
    # Store in application env
    Application.put_env(:dspex, :current_lm, config)
    
    # Configure in Python bridge
    adapter = get_adapter()
    adapter.configure_lm(config)
  end
  
  @doc """
  Gets the currently configured language model.
  """
  def get_lm do
    Application.get_env(:dspex, :current_lm) || 
      Application.get_env(:dspex, :default_lm) ||
      raise "No language model configured. Call DSPex.set_lm/2 first."
  end
  
  defp get_default_api_key do
    System.get_env("GEMINI_API_KEY") || 
      Application.get_env(:dspex, :gemini_api_key) ||
      raise "No API key found. Set GEMINI_API_KEY environment variable."
  end
end
```

#### Adapter Behavior Update

```elixir
defmodule DSPex.Adapters.Adapter do
  # Add to existing callbacks
  @callback configure_lm(config :: map()) :: :ok | {:error, String.t()}
end
```

#### PythonPort Adapter Update

```elixir
defmodule DSPex.Adapters.PythonPort do
  # Add new function
  def configure_lm(config) do
    request = %{
      command: "configure_lm",
      args: config
    }
    
    case DSPex.PythonBridge.call(request) do
      {:ok, %{"status" => "configured"}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

#### PythonPool Adapter Update

```elixir
defmodule DSPex.Adapters.PythonPool do
  # Add new function
  def configure_lm(config) do
    # Configure LM globally (all workers will use it)
    SessionPool.execute_anonymous(:configure_lm, config)
  end
end
```

### 2. Python Bridge Updates

#### dspy_bridge.py Modifications

```python
class DSPyBridge:
    def __init__(self, mode='standalone'):
        self.mode = mode
        self.programs = {}
        self.lm_configured = False
        self.current_lm_config = None
        
        # Add to command handlers
        self.handlers = {
            'ping': self.ping,
            'configure_lm': self.configure_lm,  # NEW
            'create_program': self.create_program,
            'execute_program': self.execute_program,
            # ... other handlers
        }
    
    def configure_lm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Configure the language model for DSPy"""
        try:
            model = args.get('model')
            api_key = args.get('api_key')
            temperature = args.get('temperature', 0.7)
            
            if not model:
                raise ValueError("Model name is required")
            if not api_key:
                raise ValueError("API key is required")
            
            # For now, we only support Google/Gemini models
            if model.startswith('gemini'):
                import dspy
                lm = dspy.Google(
                    model=model,
                    api_key=api_key,
                    temperature=temperature
                )
                dspy.settings.configure(lm=lm)
                
                self.lm_configured = True
                self.current_lm_config = args
                
                return {
                    "status": "configured",
                    "model": model,
                    "temperature": temperature
                }
            else:
                raise ValueError(f"Unsupported model: {model}")
                
        except Exception as e:
            return {"error": str(e)}
    
    def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new DSPy program with signature"""
        try:
            # Check if LM is configured
            if not self.lm_configured:
                # Try to use default from environment
                default_key = os.getenv('GEMINI_API_KEY')
                if default_key:
                    self.configure_lm({
                        'model': 'gemini-1.5-flash',
                        'api_key': default_key,
                        'temperature': 0.7
                    })
                else:
                    raise RuntimeError("No LM configured. Call configure_lm first.")
            
            # Rest of create_program implementation...
            
    def execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a program with inputs"""
        try:
            # Check LM configuration
            if not self.lm_configured:
                raise RuntimeError("No LM is loaded.")
            
            # Optional: Allow per-execution LM override
            if 'lm' in args:
                lm_config = {
                    'model': args['lm'],
                    'api_key': args.get('api_key', self.current_lm_config.get('api_key')),
                    'temperature': args.get('temperature', 0.7)
                }
                self.configure_lm(lm_config)
            
            # Execute program
            program_id = args['program_id']
            inputs = args['inputs']
            
            if program_id not in self.programs:
                raise ValueError(f"Program not found: {program_id}")
            
            program = self.programs[program_id]
            result = program(**inputs)
            
            # Extract outputs
            output_data = {}
            for field in result._asdict():
                output_data[field] = getattr(result, field)
            
            return {"result": output_data}
            
        except Exception as e:
            return {"error": str(e)}
```

### 3. Mock Adapter Updates (for tests)

```elixir
defmodule DSPex.Adapters.Mock do
  @behaviour DSPex.Adapters.Adapter
  
  # Add LM configuration tracking
  def configure_lm(config) do
    # Store for test assertions
    Agent.update(__MODULE__, fn state ->
      Map.put(state, :lm_config, config)
    end)
    :ok
  end
  
  # Update execute to check LM config
  def execute_program(program_id, inputs, opts \\ %{}) do
    lm_config = Agent.get(__MODULE__, & &1.lm_config)
    
    if lm_config do
      # Return mock response
      {:ok, %{"answer" => "mock response"}}
    else
      {:error, "No LM is loaded."}
    end
  end
end
```

### 4. Test Environment Setup

```elixir
# test/test_helper.exs additions
case System.get_env("TEST_MODE") do
  "full_integration" ->
    # Configure real LM for integration tests
    if api_key = System.get_env("GEMINI_API_KEY") do
      Application.put_env(:dspex, :default_lm, %{
        model: "gemini-1.5-flash",
        api_key: api_key,
        temperature: 0.5  # Lower for more consistent tests
      })
    end
    
  _ ->
    # Configure mock LM for unit tests
    Application.put_env(:dspex, :default_lm, %{
      model: "mock",
      responses: %{
        "default" => %{"answer" => "test response"}
      }
    })
end
```

## Usage Examples

### Basic Usage

```elixir
# 1. Configure LM (once at startup)
DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))

# 2. Create program (LM must be configured first)
{:ok, program_id} = DSPex.create_program(%{
  signature: %{
    name: "QuestionAnswer",
    inputs: [%{name: "question", type: "string"}],
    outputs: [%{name: "answer", type: "string"}]
  }
})

# 3. Execute program
{:ok, result} = DSPex.execute_program(program_id, %{
  question: "What is the capital of France?"
})
# => %{"answer" => "Paris"}
```

### Switching Models

```elixir
# Use fast model for simple queries
DSPex.set_lm("gemini-1.5-flash")
{:ok, simple_result} = DSPex.execute_program(qa_program, %{
  question: "What is 2+2?"
})

# Switch to pro model for complex queries
DSPex.set_lm("gemini-1.5-pro", temperature: 0.3)
{:ok, complex_result} = DSPex.execute_program(analysis_program, %{
  text: "Analyze this complex document..."
})
```

### Session-Based Usage (with pooling)

```elixir
# Each session can have different LM settings
{:ok, session_id} = DSPex.start_session("user_123")

# Configure LM for this session
DSPex.configure_session_lm(session_id, "gemini-2.0-flash-exp")

# Execute in session context
{:ok, result} = DSPex.execute_in_session(session_id, program_id, inputs)
```

## Migration Path

1. **Phase 1**: Basic LM configuration (this doc)
   - Add `configure_lm` to Python bridge
   - Add `set_lm/2` to DSPex module
   - Update adapters with `configure_lm/1`

2. **Phase 2**: Per-program LM config
   - Store LM preferences with programs
   - Allow LM override in create_program

3. **Phase 3**: Session-based LM management
   - LM config per session in pool workers
   - Session-specific model selection

## Error Handling

```elixir
# Check if LM is configured
case DSPex.get_lm() do
  nil -> 
    {:error, "No language model configured"}
  config ->
    {:ok, config}
end

# Handle API key errors
try do
  DSPex.set_lm("gemini-1.5-pro")
rescue
  e in RuntimeError ->
    {:error, "API key not found: #{e.message}"}
end
```

## Testing Strategy

```elixir
# Unit tests - use mock
test "executes program with mock LM" do
  DSPex.set_lm("mock", responses: %{"test" => "response"})
  assert {:ok, %{"answer" => "response"}} = DSPex.execute_program(...)
end

# Integration tests - use real LM with caching
@tag :integration
test "executes program with real LM" do
  DSPex.set_lm("gemini-1.5-flash", api_key: System.get_env("GEMINI_API_KEY"))
  assert {:ok, %{"answer" => answer}} = DSPex.execute_program(...)
  assert is_binary(answer)
end
```

## Success Criteria

1. All existing tests pass with mock LM configured
2. Integration tests work with real Gemini API
3. Can switch between models at runtime
4. Clear error messages when LM not configured
5. API key management is secure
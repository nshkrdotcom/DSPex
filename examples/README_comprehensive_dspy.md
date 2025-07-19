# Comprehensive DSPy + DSPex with Gemini Integration

This example demonstrates the full power of combining DSPex native features with Python DSPy using Gemini 2.5 Flash model.

## What This Example Shows

### 🔧 Part 1: Native DSPex Features
- **Signature Parsing**: Parse DSPy-style signatures natively in Elixir
- **Template Engine**: EEx-based template compilation and rendering  
- **Validation**: Type-safe output validation
- **Router Decisions**: Smart routing between native and Python implementations

### 🐍 Part 2: Python DSPy Integration
- **Basic DSPy Modules**: Predict, ChainOfThought, ProgramOfThought, ReAct
- **Advanced Patterns**: 
  - Multi-hop reasoning with sub-question generation
  - Self-reflection with critique and refinement
  - Ensemble methods with consensus building
- **DSPy Optimizers**: BootstrapFewShot optimization demonstration

### 🔄 Part 3: Mixed Native/Python Pipeline
- Seamless combination of native Elixir and Python DSPy operations
- Example: Document analysis pipeline
  1. Parse signature (Native)
  2. Create template (Native) 
  3. Run DSPy analysis (Python)
  4. Validate results (Native)

### 🔬 Part 4: Real-world Research Assistant
Complete workflow demonstrating:
- Research question generation
- Multi-question analysis 
- Synthesis of findings
- Structured research reports

## Setup

### Prerequisites

1. **Gemini API Key**: Get one from [Google AI Studio](https://makersuite.google.com/app/apikey)
2. **Python with DSPy**: Install DSPy in your Python environment
   ```bash
   pip install dspy
   ```

### Environment Setup

```bash
export GEMINI_API_KEY=your_gemini_api_key_here
```

### Running the Example

```bash
# Full comprehensive example
elixir examples/comprehensive_dspy_gemini.exs

# Basic connectivity test (to troubleshoot)
elixir examples/test_dspy_basic.exs
```

## Key Features Demonstrated

### Advanced DSPy Patterns

1. **Multi-hop Reasoning**
   ```python
   class MultiHopQA(dspy.Module):
       def forward(self, question):
           # Generate sub-questions
           # Answer each sub-question  
           # Synthesize final answer
   ```

2. **Self-Reflection**
   ```python
   class SelfReflectiveQA(dspy.Module):
       def forward(self, question):
           # Initial answer
           # Self-critique
           # Refined answer
   ```

3. **Ensemble Methods**
   ```python
   class EnsembleQA(dspy.Module):
       def forward(self, question):
           # Multiple reasoning approaches
           # Consensus building
   ```

### Native/Python Interop

The example shows how to seamlessly mix native Elixir operations with Python DSPy:

```elixir
pipeline_steps = [
  {:native, :signature_parse, %{signature: "document -> summary, keywords, sentiment"}},
  {:native, :template_create, %{template: "..."}},
  {:python, :dspy_predict, %{signature: "...", module: "ChainOfThought"}},
  {:native, :validate, %{signature: "..."}}
]
```

## Model Configuration

The example uses Gemini 2.5 Flash but can be easily adapted for other models:

```elixir
config = [
  adapter: :gemini,
  provider: :gemini,  
  api_key: api_key,
  model: "gemini-2.0-flash-exp",  # or gemini-1.5-flash, etc.
  temperature: 0.7,
  max_tokens: 2048
]
```

## Troubleshooting

### Common Issues

1. **"No GEMINI_API_KEY"**: Set the environment variable
2. **"DSPy not available"**: Install DSPy with `pip install dspy`
3. **Snakepit connection issues**: Check that Python is available and working
4. **Dependency conflicts**: Ensure consistent versions in mix.exs

### Testing Components Individually

Use the basic test to verify each component:

```bash
elixir examples/test_dspy_basic.exs
```

This will test:
- DSPex native features
- Snakepit Python integration  
- DSPy availability
- Gemini LLM connectivity

## Extending the Example

### Adding New DSPy Modules

```python
class CustomModule(dspy.Module):
    def __init__(self):
        super().__init__()
        self.predictor = dspy.ChainOfThought("your_signature")
    
    def forward(self, **kwargs):
        return self.predictor(**kwargs)
```

### Adding Native Operations

```elixir
defp execute_pipeline_step({:native, :custom_operation, params}, data, _session) do
  # Your custom native logic here
  {:ok, updated_data}
end
```

### Using Different Models

The example can work with any model supported by DSPy:

- OpenAI GPT models
- Anthropic Claude
- Local models via Ollama
- Azure OpenAI
- And more...

Just update the DSPy configuration in the Python code sections.

## Performance Notes

- Native operations are faster for simple tasks
- Python DSPy excels at complex reasoning patterns
- Mixed pipelines provide the best of both worlds
- Session management enables stateful workflows

## See Also

- [DSPy Documentation](https://dspy.readthedocs.io/)
- [DSPex Architecture](../CLAUDE.md)
- [Gemini API Documentation](https://ai.google.dev/docs)
- [Snakepit Examples](../snakepit/examples/)
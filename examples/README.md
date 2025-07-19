# DSPex Examples

A comprehensive collection of examples demonstrating the power of DSPex - the native Elixir implementation of DSPy concepts with seamless Python DSPy integration.

## 🎯 Quick Start

```bash
# Set your Gemini API key (get one at https://makersuite.google.com/app/apikey)
export GEMINI_API_KEY="your-api-key-here"

# Run any example
elixir examples/dspex_native_showcase.exs
```

## 📚 Example Categories

### 1. Native DSPex Features

#### **[dspex_native_showcase.exs](./dspex_native_showcase.exs)** ⭐ Start Here
The best introduction to DSPex's native Elixir capabilities.

**Features demonstrated:**
- Signature parsing with complex types (`list[str]`, `float`, etc.)
- Template compilation with EEx
- Output validation against signatures
- End-to-end workflow with Gemini LLM

```elixir
# Parse a signature
{:ok, signature} = Native.Signature.parse("question -> answer: str, confidence: float")

# Compile a template
{:ok, template} = Native.Template.compile("Question: <%= @question %>\nAnswer:")

# Validate outputs
:ok = Native.Validator.validate_output(%{"answer" => "Paris", "confidence" => 0.95}, signature)
```

#### **[advanced_signature_example.exs](./advanced_signature_example.exs)**
Real-world business scenarios using native features.

**Use cases covered:**
- Document Intelligence Pipeline
- Customer Support Assistant
- Financial Risk Assessment
- Product Recommendation Engine

### 2. Python DSPy Integration

#### **[dspy_working_demo.exs](./dspy_working_demo.exs)** ⭐ Essential
A clean, working example of Python DSPy integration through Snakepit.

**What it shows:**
- Enhanced bridge configuration
- DSPy module creation (Predict, ChainOfThought)
- Making predictions with real responses
- Proper result extraction

```elixir
# Configure DSPy with Gemini
Snakepit.execute("configure_lm", %{
  "provider" => "google",
  "api_key" => api_key,
  "model" => "gemini-2.0-flash-exp"
})

# Create and use DSPy modules
Snakepit.execute("call", %{
  "target" => "dspy.ChainOfThought",
  "args" => ["question -> reasoning, answer"],
  "store_as" => "cot_predictor"
})
```

#### **[dspy_python_integration.exs](./dspy_python_integration.exs)**
Comprehensive Python environment testing and DSPy integration.

**Includes:**
- Python environment verification
- DSPy availability checking
- Module creation patterns
- Error handling strategies

### 3. Comprehensive Examples

#### **[comprehensive_dspy_gemini.exs](./comprehensive_dspy_gemini.exs)** ⭐ Showcase
The ultimate demonstration combining native DSPex and Python DSPy.

**Three-part structure:**
1. **Native Features** - Signatures, templates, validation
2. **Python DSPy** - Predict, ChainOfThought with Gemini
3. **Mixed Pipeline** - Combining native speed with Python power

### 4. LLM Adapter Examples

#### **[qa_with_gemini_ex.exs](./qa_with_gemini_ex.exs)**
Direct Gemini adapter usage for Q&A tasks.

**Shows:**
- Gemini adapter configuration
- Structured output handling
- Error management

#### **[qa_with_instructor_lite.exs](./qa_with_instructor_lite.exs)**
InstructorLite adapter for structured outputs.

**Note:** InstructorLite has compatibility issues with Gemini. Better to use direct Gemini adapter or mock for testing.

## 🏗️ Project Structure

### Standalone Mix Projects
These are complete Elixir applications demonstrating DSPex in larger contexts:

- **[simple_dspy_example/](./simple_dspy_example/)** - Minimal DSPy integration
- **[concurrent_pool_example/](./concurrent_pool_example/)** - Concurrent processing patterns
- **[signature_example/](./signature_example/)** - Advanced signature patterns
- **[pool_example/](./pool_example/)** - Pool management examples

## 🚀 Running Examples

### Prerequisites

1. **Elixir 1.15+** and **Erlang/OTP 25+**
2. **Python 3.8+** (for DSPy integration)
3. **DSPy** installed: `pip install dspy-ai`
4. **Gemini API key** from [Google AI Studio](https://makersuite.google.com/app/apikey)

### Basic Usage

```bash
# Native features only (no API key needed with mock)
elixir examples/dspex_native_showcase.exs

# With Gemini API
export GEMINI_API_KEY="your-key"
elixir examples/comprehensive_dspy_gemini.exs

# Python DSPy integration
pip install dspy-ai
elixir examples/dspy_working_demo.exs
```

## 💡 Key Concepts

### Signatures
Define input/output contracts for LLM interactions:
```elixir
"question: str -> answer: str"
"document: str -> summary: str, keywords: list[str], sentiment: str"
```

### Templates
EEx-based prompt templates with variable interpolation:
```elixir
template = """
Context: <%= @context %>
Question: <%= @question %>
Answer:
"""
```

### Validation
Type-safe output validation against signatures:
```elixir
# Validates types, required fields, and structure
Native.Validator.validate_output(output, signature)
```

## 🔧 Configuration

### Mock Mode (for testing)
```elixir
{:ok, client} = LLM.Client.new([
  adapter: :mock,
  mock_responses: %{"answer" => "Paris"}
])
```

### Gemini Mode
```elixir
{:ok, client} = LLM.Client.new([
  adapter: :gemini,
  api_key: System.get_env("GEMINI_API_KEY"),
  model: "gemini-2.0-flash-exp"
])
```

### Enhanced Python Bridge
```elixir
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
```

## 📖 Learning Path

1. **Start with native features**: Run `dspex_native_showcase.exs` to understand signatures, templates, and validation
2. **Try Python integration**: Run `dspy_working_demo.exs` to see DSPy modules in action
3. **Explore business scenarios**: Check `advanced_signature_example.exs` for real-world patterns
4. **See it all together**: Run `comprehensive_dspy_gemini.exs` for the full experience

## 🤝 Common Patterns

### Error Handling
```elixir
case LLM.Client.generate(client, prompt) do
  {:ok, response} -> 
    # Handle response
  {:error, reason} -> 
    # Graceful fallback
end
```

### Mixed Execution
```elixir
# Use native for speed
{:ok, signature} = Native.Signature.parse(sig_str)

# Use Python for complex reasoning
{:ok, result} = Snakepit.execute("call", %{
  "target" => "stored.cot_predictor.__call__",
  "kwargs" => %{"question" => question}
})

# Validate with native
:ok = Native.Validator.validate_output(output, signature)
```

## 🐛 Troubleshooting

### "DSPy not available"
```bash
pip install dspy-ai
```

### "No process" errors
Ensure Snakepit is properly configured:
```elixir
Application.ensure_all_started(:snakepit)
```

### Mock responses for testing
Set adapter to `:mock` when API keys aren't available.

## 📝 Notes

- Examples use Gemini 2.0 Flash (`gemini-2.0-flash-exp`) by default
- Native features are always available (no external dependencies)
- Python integration requires `dspy-ai` package
- Most examples support both mock and real LLM modes

## 🎉 Next Steps

1. Experiment with different signatures and templates
2. Try combining multiple DSPy modules in pipelines
3. Build your own business-specific examples
4. Contribute improvements back to the project!

---

Happy prompting with DSPex! 🚀
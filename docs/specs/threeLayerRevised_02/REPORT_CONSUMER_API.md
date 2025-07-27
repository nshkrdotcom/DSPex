# REPORT_CONSUMER_API.md
## Sub-Agent 3: The Consumer & API Designer

**Persona:** A developer experience (DX) engineer who will be a user of the final platform.  
**Scope:** Analyze the high-level APIs in the *current* `dspex` (`dspex.ex`, `predict.ex`, etc.) and the examples in `./examples/dspy` and the `snakepit_showcase`.  
**Mission:** Define the "before and after" for the consumer experience. What is the current API surface, and what will the new, simplified API offered by the thin `DSPex` layer look like?

---

## 1. Current API Surface Analysis

### Core DSPex Module (`lib/dspex.ex`)

The main entry point provides:

#### Signature Operations
- `DSPex.signature/1` - Parse DSPy signatures
- `DSPex.compile_signature/1` - Compile for performance

#### Core ML Operations
- `DSPex.predict/3` - Basic prediction
- `DSPex.chain_of_thought/3` - CoT reasoning
- `DSPex.react/3` - ReAct pattern with tools
- `DSPex.program_of_thought/3` - Program synthesis
- `DSPex.retrieve/3` - Retrieval operations

#### Pipeline Operations
- `DSPex.pipeline/1` - Create pipelines
- `DSPex.run_pipeline/3` - Execute pipelines

#### Advanced Features
- `DSPex.evaluate/3` - Evaluate performance
- `DSPex.optimize/3` - Optimize with examples
- `DSPex.assert/3` - Add assertions

### Module-Specific APIs

#### Predict Module (`lib/dspex/predict.ex`)
- `DSPex.Predict.create/2` - Create predictor
- `DSPex.Predict.predict/3` - Execute prediction
- `DSPex.Predict.call/2` - One-shot prediction
- Deprecated: `new/2`, `execute/3`

#### Other Modules
Similar patterns for:
- `DSPex.ChainOfThought`
- `DSPex.React`
- `DSPex.ProgramOfThought`
- `DSPex.Retrieve`

### Supporting APIs

#### Session Management
- `DSPex.Session.new/0` - Create session
- `DSPex.Session.with_session/2` - Session context

#### Variable Management
- `DSPex.Variables.defvariable/5` - Define variables
- `DSPex.Variables.get/2` - Get values
- `DSPex.Variables.set/3` - Set values
- `DSPex.Variables.update/3` - Update values

#### Language Model Configuration
- `DSPex.LM.configure/2` - Configure LM
- `DSPex.Settings` - Various settings

#### Bridge Tools
- `DSPex.Bridge.Tools.register_tool/4` - Register Elixir tools
- `DSPex.Bridge.Tools.list_tools/1` - List available tools

## 2. Analysis of Example Usage

### Pattern 1: Direct Module Usage (simple_qa_demo.exs)
```elixir
# Complex setup required
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Configure LM
{:ok, _} = DSPex.Config.init()
DSPex.LM.configure(config.model, api_key: config.api_key)

# Create and use predictor
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "..."})

# Complex result extraction
answer = get_in(result, ["result", "prediction_data", "answer"])
```

### Pattern 2: Session-Based Usage (01_question_answering_pipeline.exs)
```elixir
# Direct Snakepit calls mixed with DSPex
Snakepit.execute_in_session("pipeline_session", "check_dspy", %{})
Snakepit.execute_in_session("pipeline_session", "configure_lm", %{...})
```

### Common Pain Points

1. **Complex Initialization** - Multiple application configs and startups
2. **Mixed Abstractions** - Direct Snakepit calls alongside DSPex
3. **Deep Result Nesting** - `get_in(result, ["result", "prediction_data", "answer"])`
4. **Adapter Configuration** - Manual adapter selection and config
5. **Session Management** - Unclear when to use sessions
6. **Error Handling** - Inconsistent error patterns
7. **Configuration Confusion** - Multiple ways to configure (Config, LM, Settings)

## 3. Proposed "Thin DSPex" API

### Design Principles

1. **Zero Configuration Start** - Works out of the box with sensible defaults
2. **Single Entry Point** - All operations through `DSPex` module
3. **Flat Results** - Direct access to values without deep nesting
4. **Implicit Sessions** - Automatic session management
5. **Pipeline First** - Everything is a composable operation
6. **Type Safe** - Leverage Elixir's type system

### Core API

```elixir
defmodule DSPex do
  @moduledoc """
  Simple, powerful API for ML workflows.
  
  ## Quick Start
  
      # Just works - no config needed
      DSPex.ask("What is the capital of France?")
      # => "Paris"
      
      # With reasoning
      DSPex.think("Explain quantum computing")
      # => %{reasoning: "...", answer: "..."}
      
      # With tools
      DSPex.solve("Calculate the area of a circle with radius 5", 
        tools: [&Math.pi/0, &:math.pow/2])
      # => %{steps: [...], answer: 78.54}
  """
  
  # Simple operations that just work
  
  @doc "Ask a simple question"
  def ask(question, opts \\ [])
  
  @doc "Think through a problem step-by-step"  
  def think(question, opts \\ [])
  
  @doc "Solve using tools and reasoning"
  def solve(question, opts \\ [])
  
  @doc "Extract structured data"
  def extract(text, schema, opts \\ [])
  
  @doc "Classify into categories"
  def classify(text, categories, opts \\ [])
  
  @doc "Generate text from template"
  def generate(template, params, opts \\ [])
  
  # Advanced operations
  
  @doc "Create a reusable operation"
  def operation(signature, opts \\ [])
  
  @doc "Compose operations into a pipeline"
  def pipeline(operations)
  
  @doc "Run a pipeline"
  def run(pipeline, input, opts \\ [])
  
  # Configuration (optional)
  
  @doc "Configure language model (optional - uses defaults)"
  def configure(opts \\ [])
  
  @doc "Use a specific model for this call"
  def with_model(operation, model)
  
  @doc "Add custom tools"
  def with_tools(operation, tools)
end
```

### Clean Module APIs

```elixir
# Instead of complex module creation, use functions
result = DSPex.ask("What is 2+2?")
# => "4"

result = DSPex.think("Why is the sky blue?")  
# => %{reasoning: "Light scattering...", answer: "Due to Rayleigh scattering"}

result = DSPex.extract(
  "John Doe, 30 years old, john@example.com",
  %{name: :string, age: :integer, email: :string}
)
# => %{name: "John Doe", age: 30, email: "john@example.com"}
```

### Pipeline Composition

```elixir
# Define reusable operations
summarizer = DSPex.operation("text -> summary")
analyzer = DSPex.operation("summary -> sentiment, key_points")

# Compose into pipeline
pipeline = DSPex.pipeline([summarizer, analyzer])

# Run pipeline
result = DSPex.run(pipeline, %{text: "Long article..."})
# => %{summary: "...", sentiment: "positive", key_points: [...]}
```

### Tool Integration

```elixir
# Register Elixir functions as tools
defmodule MyTools do
  def calculate_tax(amount, rate), do: amount * rate
  def fetch_weather(city), do: WeatherAPI.get(city)
end

# Use in operations
result = DSPex.solve(
  "What's the tax on $1000 at 8.5% rate?",
  tools: [MyTools]
)
# => %{steps: ["Using calculate_tax tool..."], answer: "$85.00"}
```

## 4. Example Refactoring

### Before (simple_qa_demo.exs)
```elixir
# 25+ lines of setup code...
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)
{:ok, _} = DSPex.Config.init()
DSPex.LM.configure(config.model, api_key: config.api_key)

# Create predictor
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")

# Ask questions
questions = ["What is the capital of France?", "What is 25 * 4?"]
Enum.each(questions, fn question ->
  case DSPex.Modules.Predict.execute(predictor, %{question: question}) do
    {:ok, result} ->
      answer = get_in(result, ["result", "prediction_data", "answer"])
      IO.puts("Q: #{question}\nA: #{answer}")
    {:error, error} ->
      IO.puts("Error: #{inspect(error)}")
  end
end)
```

### After (with new API)
```elixir
# Optional config (uses defaults if not specified)
DSPex.configure(api_key: System.get_env("GEMINI_API_KEY"))

# Ask questions - that's it!
questions = ["What is the capital of France?", "What is 25 * 4?"]
for question <- questions do
  answer = DSPex.ask(question)
  IO.puts("Q: #{question}\nA: #{answer}")
end
```

### Advanced Example - Before
```elixir
# Complex multi-stage pipeline with manual orchestration
{:ok, keyword_extractor} = DSPex.Modules.Predict.create("query -> keywords: list[str]")
{:ok, summarizer} = DSPex.ChainOfThought.new("keywords -> summary")

{:ok, keywords_result} = DSPex.Modules.Predict.execute(keyword_extractor, %{query: input})
keywords = get_in(keywords_result, ["result", "prediction_data", "keywords"])

{:ok, summary_result} = DSPex.ChainOfThought.execute(summarizer, %{keywords: keywords})
summary = summary_result.summary
```

### Advanced Example - After
```elixir
# Clean pipeline composition
pipeline = DSPex.pipeline([
  DSPex.operation("query -> keywords: list[str]"),
  DSPex.operation("keywords -> summary", mode: :think)
])

result = DSPex.run(pipeline, %{query: input})
# => %{keywords: [...], summary: "..."}
```

## Summary

The new thin DSPex API will provide:

1. **Dramatic Simplification** - 80% less boilerplate code
2. **Intuitive Functions** - `ask`, `think`, `solve` instead of module management
3. **Clean Composition** - Everything is a composable operation
4. **Smart Defaults** - Works without configuration
5. **Flat Results** - Direct access to values
6. **Type Safety** - Leverages Elixir's type system
7. **Progressive Disclosure** - Simple things simple, complex things possible

The API hides all complexity of:
- Application startup and configuration
- Adapter selection and management  
- Session lifecycle
- Result extraction and transformation
- Error handling patterns
- Platform communication details

Users can focus on their ML workflows, not infrastructure.
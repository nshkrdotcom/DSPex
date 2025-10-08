# What DSPex Needs - Complete Implementation Roadmap
**Date**: 2025-10-07
**Current Version**: v0.2.0
**Status**: Core working, optimization layer incomplete
**Goal**: Production-ready DSPy implementation for Elixir by mid-May 2025

---

## Executive Summary

DSPex is **60% complete**. You have:
- ✅ Python DSPy bridge (via snakepit)
- ✅ 70+ DSPy classes discovered
- ✅ Schema introspection working
- ✅ Basic signatures and modules

**What's Missing**:
- ❌ Compile-time optimization (the core DSPy value prop!)
- ❌ ALTAR tool integration
- ❌ Teleprompt/MIPRO optimizers
- ❌ Example datasets and evaluation
- ❌ Structured output parsing with sinter

---

## Current State Analysis

### **What Works** ✅

#### 1. **Python Bridge** (via Snakepit v0.4.2)
```elixir
# Universal DSPy access
DSPex.Bridge.call_dspy("dspy.Predict", "__init__", %{"signature" => "question -> answer"})

# Schema discovery
{:ok, schema} = DSPex.Bridge.discover_schema("dspy")
# Returns 70+ classes: Predict, ChainOfThought, ReAct, etc.
```

**Status**: ✅ Production-ready
**Dependencies**: snakepit (working)

#### 2. **High-Level Modules**
```elixir
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{"question" => "What is AI?"})
```

**Status**: ✅ Working for basic cases
**Limitations**: No optimization, just pass-through to Python

#### 3. **Signatures** (Type System)
```elixir
defmodule MySignature do
  use DSPex.Signature

  signature "question -> answer" do
    input :question, :string, desc: "The question to answer"
    output :answer, :string, desc: "The answer"
  end
end
```

**Status**: ✅ Parsing works
**Limitations**: Not used for optimization yet

### **What's Broken/Missing** ❌

#### 1. **No Compile-Time Optimization** (CRITICAL)

This is **THE** core value of DSPy - and it's missing!

**What DSPy Does**:
```python
# Python DSPy
class CoT(dspy.Module):
    def __init__(self):
        self.generate = dspy.ChainOfThought("question -> answer")

    def forward(self, question):
        return self.generate(question=question)

# Compile/optimize with training data
compiled = teleprompter.compile(CoT(), trainset=examples)
# → Optimized prompts, better few-shot examples, improved reasoning
```

**What DSPex Does** (Currently):
```elixir
# Just calls Python - NO optimization
defmodule CoT do
  use DSPex.Module

  def forward(question) do
    # Literally just calls Python DSPy (no Elixir optimization)
    DSPex.Bridge.call_dspy("dspy.ChainOfThought", ...)
  end
end
```

**Missing**: The entire `DSPex.Teleprompt` optimization layer!

#### 2. **No ALTAR Integration**

**Current**:
```elixir
# DSPex doesn't know about ALTAR tools
# Can't use Elixir tools in DSPy chains
```

**Needed**:
```elixir
# Use ALTAR tools in DSPy modules
defmodule WeatherTool do
  use Altar.Tool
  def get_weather(city), do: {:ok, "Sunny"}
end

defmodule WeatherChain do
  use DSPex.Module

  # Should be able to call ALTAR tools!
  def forward(question) do
    weather = Altar.execute(WeatherTool, city: "SF")
    DSPex.generate("Answer #{question} given weather: #{weather}")
  end
end
```

#### 3. **No Evaluation Framework**

**Python DSPy**:
```python
# Evaluate model performance
from dspy.evaluate import Evaluate

evaluator = Evaluate(devset=test_data, metric=exact_match)
score = evaluator(compiled_program)
```

**DSPex**: ❌ Doesn't exist

#### 4. **No Optimizers** (Bootstrap, MIPRO, etc.)

**Python DSPy Optimizers**:
- `BootstrapFewShot`: Learn few-shot examples from data
- `MIPRO`: Multi-prompt instruction optimization
- `KNNFewShot`: K-nearest-neighbors example selection
- `LabeledFewShot`: Use labeled data

**DSPex**: ❌ None implemented

#### 5. **No Integration with sinter** (Schema Library)

**Current**: DSPex has its own signature system
**Problem**: Duplicates sinter's schema functionality
**Needed**: Use sinter as the schema backend

---

## What DSPex NEEDS (Priority Order)

### **Phase 1: Critical Missing Features** (4-6 weeks with Claude 5.0)

#### **1.1 ALTAR Tool Integration** (Week 1)

**Goal**: DSPy modules can call ALTAR tools

**Implementation**:
```elixir
# lib/dspex/altar_bridge.ex
defmodule DSPex.AltarBridge do
  @moduledoc """
  Exposes ALTAR tools to DSPy modules for bidirectional tool execution.
  """

  @doc """
  Registers ALTAR tool modules with the DSPy session.
  """
  def register_tools(session_id, tool_modules) when is_list(tool_modules) do
    # Convert ALTAR tools to Python tool definitions
    python_tools = Enum.map(tool_modules, &altar_to_python_tool/1)

    # Register with snakepit session
    Snakepit.execute(session_id, "register_elixir_tools", %{
      tools: python_tools
    })
  end

  defp altar_to_python_tool(module) do
    # Extract ALTAR tool metadata
    {:ok, spec} = Altar.Tool.spec(module)

    %{
      name: spec.name,
      description: spec.description,
      parameters: spec.parameters,
      callback: {module, :execute}  # Elixir callback
    }
  end
end

# Usage in DSPex modules
defmodule WeatherRAG do
  use DSPex.Module

  altar_tools [WeatherTool, SearchTool]  # ← New macro

  signature "question -> answer" do
    input :question, :string
    output :answer, :string
  end

  def forward(question) do
    # DSPy can now call WeatherTool and SearchTool!
    dspy_chain(question)
  end
end
```

**Tests**:
```elixir
test "DSPy chain can call ALTAR tools" do
  defmodule TestTool do
    use Altar.Tool
    def execute(args), do: {:ok, "tool result"}
  end

  {:ok, chain} = WeatherRAG.create(tools: [TestTool])
  {:ok, result} = WeatherRAG.forward(chain, "test question")

  assert result =~ "tool result"
end
```

**Deliverable**: ALTAR tools callable from DSPy Python code

---

#### **1.2 Sinter Schema Integration** (Week 2)

**Goal**: Replace custom signature system with sinter

**Implementation**:
```elixir
# Before (custom signatures)
defmodule MySignature do
  use DSPex.Signature
  signature "question -> answer" do
    input :question, :string
    output :answer, :string
  end
end

# After (sinter-based)
defmodule MySignature do
  use Sinter.Schema

  @schema %{
    inputs: %{
      question: %{type: :string, required: true}
    },
    outputs: %{
      answer: %{type: :string}
    }
  }
end

# DSPex.Module automatically uses sinter schemas
defmodule MyModule do
  use DSPex.Module, schema: MySignature

  def forward(inputs) do
    # Sinter validates inputs/outputs
    # ...
  end
end
```

**Benefits**:
- Unified schema system across ecosystem
- Runtime validation
- Better error messages
- Interop with other projects using sinter

**Migration**: Update DSPex.Signature to be a sinter macro

**Tests**: All existing signature tests must still pass

---

#### **1.3 Structured Output Parsing** (Week 2-3)

**Goal**: Parse LLM outputs into Elixir structs automatically

**Implementation**:
```elixir
# lib/dspex/output_parser.ex
defmodule DSPex.OutputParser do
  @moduledoc """
  Parses LLM outputs into typed Elixir structs using sinter schemas.
  """

  def parse(output, schema) when is_binary(output) do
    # Try to extract JSON from LLM response
    with {:ok, json} <- extract_json(output),
         {:ok, data} <- Jason.decode(json),
         {:ok, validated} <- Sinter.validate(data, schema) do
      {:ok, validated}
    else
      {:error, :no_json} ->
        # Fallback: Ask LLM to convert to JSON
        retry_with_json_prompt(output, schema)

      {:error, reason} ->
        {:error, {:parse_failed, reason}}
    end
  end

  defp extract_json(text) do
    # Use regex to find JSON blocks
    case Regex.run(~r/```json\s*(\{.*?\})\s*```/s, text) do
      [_, json] -> {:ok, json}
      nil ->
        case Regex.run(~r/(\{.*\})/s, text) do
          [_, json] -> {:ok, json}
          nil -> {:error, :no_json}
        end
    end
  end
end

# Usage
defmodule UserExtractor do
  use DSPex.Module

  schema do
    output :name, :string
    output :age, :integer
    output :occupation, :string
  end

  def forward(text) do
    result = dspy_predict("Extract user info from: #{text}")
    DSPex.OutputParser.parse(result, __MODULE__)
  end
end

{:ok, user} = UserExtractor.forward("John is 30, works as engineer")
# => %{name: "John", age: 30, occupation: "engineer"}
```

**Tests**:
- JSON extraction from various formats
- Schema validation
- Error handling for malformed outputs
- Integration with json_remedy for repair

---

#### **1.4 Native Elixir Predict Module** (Week 3-4)

**Goal**: Implement core DSPy.Predict purely in Elixir (no Python dependency)

**Implementation**:
```elixir
# lib/dspex/native/predict.ex
defmodule DSPex.Native.Predict do
  @moduledoc """
  Pure Elixir implementation of DSPy's Predict module.

  Uses gemini_ex for LLM calls instead of Python DSPy.
  """

  defstruct [:signature, :lm, :demos, :config]

  def create(signature, opts \\ []) do
    %__MODULE__{
      signature: parse_signature(signature),
      lm: opts[:lm] || :gemini_2_0_flash,
      demos: opts[:demos] || [],
      config: opts[:config] || %{}
    }
  end

  def forward(%__MODULE__{} = predictor, inputs) do
    # Build prompt from signature + demos
    prompt = build_prompt(predictor, inputs)

    # Call gemini_ex
    {:ok, response} = Gemini.chat(
      prompt,
      model: predictor.lm,
      tools: predictor.config[:tools] || []  # ALTAR tools!
    )

    # Parse output according to signature
    DSPex.OutputParser.parse(response, predictor.signature.outputs)
  end

  defp build_prompt(predictor, inputs) do
    """
    #{build_instructions(predictor.signature)}

    #{build_demos(predictor.demos)}

    Input:
    #{format_inputs(inputs, predictor.signature)}

    Output:
    """
  end

  defp build_instructions(signature) do
    input_desc = Enum.map_join(signature.inputs, "\n", fn {name, field} ->
      "- #{name}: #{field.description}"
    end)

    output_desc = Enum.map_join(signature.outputs, "\n", fn {name, field} ->
      "- #{name}: #{field.description}"
    end)

    """
    You are given inputs and must produce outputs.

    Inputs:
    #{input_desc}

    Outputs:
    #{output_desc}
    """
  end
end
```

**Benefits**:
- No Python dependency for basic prediction
- Faster (no gRPC overhead for simple cases)
- Full Elixir control (can inspect/modify prompts)
- Can use ALTAR tools natively

**Tests**:
- Compare output with Python DSPy Predict
- Verify ALTAR tool integration
- Performance benchmarks

---

### **Phase 2: Optimization Layer** (6-8 weeks)

This is **THE CORE VALUE** of DSPy that's currently missing!

#### **2.1 BootstrapFewShot Optimizer** (Week 5-7)

**Goal**: Learn few-shot examples from training data

**Python DSPy**:
```python
# Learn examples from data
teleprompter = BootstrapFewShot(metric=exact_match)
compiled = teleprompter.compile(student=CoT(), trainset=examples)
```

**DSPex Implementation**:
```elixir
# lib/dspex/optimizers/bootstrap_few_shot.ex
defmodule DSPex.Optimizers.BootstrapFewShot do
  @moduledoc """
  Bootstrap few-shot examples from training data.

  Learns which examples help the model perform best by:
  1. Running student program on trainset
  2. Keeping examples where it succeeds
  3. Using successful (input, output) pairs as demonstrations
  """

  defstruct [:metric, :max_bootstrapped_demos, :max_labeled_demos, :teacher, :student]

  def compile(student_module, opts) do
    trainset = Keyword.fetch!(opts, :trainset)
    metric = Keyword.fetch!(opts, :metric)

    optimizer = %__MODULE__{
      metric: metric,
      max_bootstrapped_demos: opts[:max_bootstrapped_demos] || 4,
      max_labeled_demos: opts[:max_labeled_demos] || 16,
      student: student_module
    }

    # Bootstrap process
    demos = bootstrap_demos(optimizer, trainset)

    # Create optimized version with demos
    student_module.with_demos(demos)
  end

  defp bootstrap_demos(optimizer, trainset) do
    Enum.reduce(trainset, [], fn example, acc ->
      # Run student on example
      case run_example(optimizer.student, example) do
        {:ok, prediction} ->
          # Check if correct using metric
          if optimizer.metric.(prediction, example.output) do
            # Success! Keep this example as demo
            [%{input: example.input, output: prediction} | acc]
          else
            acc
          end

        {:error, _} ->
          acc
      end
    end)
    |> Enum.take(optimizer.max_bootstrapped_demos)
  end
end

# Usage
defmodule QA do
  use DSPex.Module

  signature "question -> answer"

  def forward(question) do
    DSPex.predict(question)
  end
end

# Training data
trainset = [
  %{question: "What is 2+2?", answer: "4"},
  %{question: "Capital of France?", answer: "Paris"},
  # ... more examples
]

# Compile/optimize!
optimized_qa = DSPex.Optimizers.BootstrapFewShot.compile(
  QA,
  trainset: trainset,
  metric: &exact_match/2,
  max_bootstrapped_demos: 3
)

# Use optimized version (has learned demos)
{:ok, result} = optimized_qa.forward("What is 2+3?")
# Better accuracy due to few-shot examples!
```

**Tests**:
- Verify demo selection (only successful examples)
- Metric function integration
- Improved accuracy on holdout set
- Serialization (save/load optimized modules)

---

#### **2.2 MIPRO Optimizer** (Week 8-10)

**Goal**: Multi-prompt instruction optimization (the advanced optimizer)

**What MIPRO Does**:
- Generates candidate instructions
- Tests combinations
- Selects best-performing prompts
- Optimizes both instructions AND examples

**Implementation**:
```elixir
# lib/dspex/optimizers/mipro.ex
defmodule DSPex.Optimizers.MIPRO do
  @moduledoc """
  Multi-Instruction Prompt Optimizer.

  Searches for optimal combination of:
  - System instructions
  - Few-shot demonstrations
  - Output formatting
  """

  def compile(student_module, opts) do
    trainset = Keyword.fetch!(opts, :trainset)
    valset = Keyword.fetch!(opts, :valset)
    metric = Keyword.fetch!(opts, :metric)

    # Step 1: Generate instruction candidates
    instruction_candidates = generate_instructions(student_module, trainset)

    # Step 2: Generate demo candidates (bootstrap)
    demo_candidates = bootstrap_demos(student_module, trainset)

    # Step 3: Search for best combination
    best = grid_search(
      student_module,
      instruction_candidates,
      demo_candidates,
      valset,
      metric
    )

    # Return optimized module with best config
    student_module
    |> with_instruction(best.instruction)
    |> with_demos(best.demos)
  end

  defp generate_instructions(module, trainset) do
    # Use LLM to generate instruction variants
    prompt = """
    Given this task: #{module.signature}
    And these examples: #{inspect(Enum.take(trainset, 3))}

    Generate 10 different instruction phrasings that could improve performance.
    """

    {:ok, instructions} = Gemini.chat(prompt, model: "gemini-2.0-flash-thinking-exp")
    parse_instruction_list(instructions)
  end

  defp grid_search(module, instructions, demos, valset, metric) do
    # Try all combinations (or use bayesian optimization)
    combinations = for i <- instructions, d <- demos, do: {i, d}

    Enum.max_by(combinations, fn {instruction, demo_set} ->
      # Test this combination on validation set
      score = evaluate_combination(module, instruction, demo_set, valset, metric)
      score
    end)
  end
end
```

**Tests**:
- Instruction generation quality
- Grid search finds improvements
- Validation set not in training set (no leakage)
- Serialization of optimized prompts

---

#### **1.3 Evaluation Framework** (Week 4-5)

**Goal**: Measure model performance with metrics

**Implementation**:
```elixir
# lib/dspex/evaluate.ex
defmodule DSPex.Evaluate do
  @moduledoc """
  Evaluation framework for DSPex modules.

  Provides metrics and dataset management for measuring performance.
  """

  defstruct [:metric, :devset, :display_progress]

  @doc """
  Create evaluator with metric function.

  ## Example
      metric = fn prediction, example ->
        String.downcase(prediction.answer) == String.downcase(example.answer)
      end

      evaluator = DSPex.Evaluate.new(
        devset: test_data,
        metric: metric,
        display_progress: true
      )
  """
  def new(opts) do
    %__MODULE__{
      metric: Keyword.fetch!(opts, :metric),
      devset: Keyword.fetch!(opts, :devset),
      display_progress: Keyword.get(opts, :display_progress, false)
    }
  end

  @doc """
  Evaluate a DSPex module on the devset.

  Returns {score, results} where:
  - score: Percentage of examples that passed metric
  - results: List of individual results
  """
  def evaluate(%__MODULE__{} = evaluator, module) do
    results = Enum.map(evaluator.devset, fn example ->
      # Run module on example
      {:ok, prediction} = module.forward(example.inputs)

      # Check metric
      passed = evaluator.metric.(prediction, example)

      if evaluator.display_progress do
        IO.write(if passed, do: "✓", else: "✗")
      end

      %{
        example: example,
        prediction: prediction,
        passed: passed
      }
    end)

    if evaluator.display_progress, do: IO.puts("")

    score = Enum.count(results, & &1.passed) / length(results)

    {:ok, score, results}
  end
end

# Built-in metrics
defmodule DSPex.Metrics do
  def exact_match(prediction, example) do
    prediction.answer == example.answer
  end

  def fuzzy_match(prediction, example) do
    String.jaro_distance(prediction.answer, example.answer) > 0.8
  end

  def contains(prediction, example) do
    String.contains?(
      String.downcase(prediction.answer),
      String.downcase(example.answer)
    )
  end
end
```

**Usage**:
```elixir
# Evaluate module
evaluator = DSPex.Evaluate.new(
  devset: test_data,
  metric: &DSPex.Metrics.exact_match/2,
  display_progress: true
)

{:ok, score, _results} = DSPex.Evaluate.evaluate(evaluator, MyQAModule)
IO.puts("Accuracy: #{score * 100}%")
```

**Tests**:
- Metric functions work correctly
- Evaluation produces consistent scores
- Progress display works
- Results include predictions and ground truth

---

### **Phase 2: Advanced Features** (8-12 weeks)

#### **2.1 Native ChainOfThought** (Week 11-12)

**Goal**: Pure Elixir CoT without Python dependency

**Implementation**:
```elixir
defmodule DSPex.Native.ChainOfThought do
  @moduledoc """
  Chain of Thought reasoning in pure Elixir.

  Prompts LLM to show reasoning before answering.
  """

  def create(signature, opts \\ []) do
    %{
      signature: signature,
      lm: opts[:lm] || :gemini_2_0_flash_thinking,
      demos: opts[:demos] || []
    }
  end

  def forward(cot, inputs) do
    # Build CoT prompt
    prompt = """
    #{build_instruction(cot.signature)}

    Think step by step:
    1. First, explain your reasoning
    2. Then, provide your answer

    #{build_demos(cot.demos)}

    Input: #{format_inputs(inputs)}

    Reasoning:
    """

    # Get response with reasoning
    {:ok, response} = Gemini.chat(prompt, model: cot.lm)

    # Parse reasoning + answer
    parse_cot_response(response, cot.signature)
  end

  defp parse_cot_response(response, signature) do
    # Extract reasoning and final answer
    parts = String.split(response, ~r/Answer:|Final Answer:/i, parts: 2)

    case parts do
      [reasoning, answer] ->
        {:ok, %{
          reasoning: String.trim(reasoning),
          answer: String.trim(answer)
        }}

      [_] ->
        # No explicit answer section, use whole response
        {:ok, %{reasoning: "", answer: String.trim(response)}}
    end
  end
end
```

**Benefits**:
- No Python dependency
- Faster (direct gemini_ex call)
- Can use gemini thinking models natively
- Full Elixir introspection

---

#### **2.2 ReAct Implementation** (Week 13-14)

**Goal**: Reasoning + Acting loop (tool-using agent)

**Implementation**:
```elixir
defmodule DSPex.Native.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) implementation.

  Alternates between reasoning and tool use until answer is found.
  """

  def create(signature, opts) do
    %{
      signature: signature,
      tools: opts[:tools] || [],  # ALTAR tools
      max_iterations: opts[:max_iterations] || 5,
      lm: opts[:lm] || :gemini_2_0_flash
    }
  end

  def forward(react, inputs) do
    execute_loop(react, inputs, [], 0)
  end

  defp execute_loop(react, inputs, history, iteration) do
    if iteration >= react.max_iterations do
      {:error, :max_iterations_reached}
    else
      # Ask LLM to think and act
      prompt = build_react_prompt(react, inputs, history)

      {:ok, response} = Gemini.chat(
        prompt,
        model: react.lm,
        tools: react.tools  # ALTAR tools available
      )

      # Parse thought/action/observation
      case parse_react_step(response) do
        {:thought, reasoning} ->
          # Continue thinking
          execute_loop(react, inputs, [{:thought, reasoning} | history], iteration + 1)

        {:action, tool, args} ->
          # Execute tool (ALTAR)
          {:ok, observation} = Altar.execute(tool, args)
          execute_loop(react, inputs, [{:action, tool, observation} | history], iteration + 1)

        {:finish, answer} ->
          {:ok, %{answer: answer, trajectory: Enum.reverse(history)}}
      end
    end
  end
end
```

---

#### **2.3 Compilation & Serialization** (Week 15-16)

**Goal**: Save optimized modules to disk

**Implementation**:
```elixir
# lib/dspex/compiler.ex
defmodule DSPex.Compiler do
  @moduledoc """
  Compiles and serializes optimized DSPex modules.

  Allows saving/loading optimized prompts and demos.
  """

  def compile(module, opts) do
    optimizer = opts[:optimizer] || DSPex.Optimizers.BootstrapFewShot

    # Run optimization
    optimized = optimizer.compile(module, opts)

    # Serialize
    if opts[:save_to] do
      save(optimized, opts[:save_to])
    end

    optimized
  end

  def save(module, path) do
    compiled = %{
      module: module.__struct__,
      version: "0.2.0",
      signature: module.signature,
      demos: module.demos,
      instructions: module.instructions,
      config: module.config,
      metadata: %{
        compiled_at: DateTime.utc_now(),
        optimizer: module.metadata[:optimizer]
      }
    }

    json = Jason.encode!(compiled, pretty: true)
    File.write!(path, json)
  end

  def load(path) do
    json = File.read!(path)
    {:ok, data} = Jason.decode(json, keys: :atoms)

    # Reconstruct module
    module = data.module
    struct(module, Map.take(data, [:signature, :demos, :instructions, :config]))
  end
end

# Usage
optimized = DSPex.Compiler.compile(
  MyModule,
  trainset: train_data,
  valset: val_data,
  optimizer: DSPex.Optimizers.MIPRO,
  save_to: "priv/compiled/my_module_v1.json"
)

# Later, load it
loaded = DSPex.Compiler.load("priv/compiled/my_module_v1.json")
```

---

### **Phase 3: Ecosystem Integration** (4-6 weeks)

#### **3.1 Foundation Integration** (Week 17-18)

**Goal**: DSPex modules as Foundation agents

**Implementation**:
```elixir
# lib/dspex/foundation_agent.ex
defmodule DSPex.FoundationAgent do
  @moduledoc """
  Adapter to run DSPex modules as Foundation agents.
  """

  defmacro __using__(dspex_module: module) do
    quote do
      use Foundation.Agent

      @dspex_module unquote(module)

      def handle_task(:execute, inputs) do
        # Run DSPex module
        case @dspex_module.forward(inputs) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end
end

# Usage
defmodule QAAgent do
  use DSPex.FoundationAgent, dspex_module: MyQAModule
end

{:ok, agent} = Foundation.start_agent(QAAgent)
Foundation.Agent.execute(agent, :execute, %{question: "What is AI?"})
```

**Benefits**:
- DSPex modules get Foundation supervision
- Foundation agents get DSPy optimization
- Unified agent model

---

#### **3.2 Telemetry Integration** (Week 19)

**Goal**: Complete observability for DSPex operations

**Events to emit**:
```elixir
# Every DSPex operation emits telemetry
:telemetry.execute(
  [:dspex, :predict, :start],
  %{system_time: System.system_time()},
  %{module: MyModule, signature: "question -> answer"}
)

:telemetry.execute(
  [:dspex, :predict, :stop],
  %{duration: duration, tokens: token_count},
  %{module: MyModule, result: :success}
)

# Optimization events
:telemetry.execute(
  [:dspex, :optimize, :complete],
  %{duration: duration, score_improvement: 0.15},
  %{optimizer: :bootstrap_few_shot, examples_used: 42}
)

# Tool execution
:telemetry.execute(
  [:dspex, :tool, :execute],
  %{duration: duration},
  %{tool: WeatherTool, result: :success}
)
```

**AITrace Integration**:
```elixir
# AITrace subscribes to DSPex events
AITrace.subscribe([
  [:dspex, :predict],
  [:dspex, :optimize],
  [:dspex, :tool]
])
```

---

### **Phase 4: Documentation & Examples** (2-3 weeks)

#### **4.1 Complete Examples** (Week 20)

**Examples Needed**:

1. **Simple QA** (getting started)
```elixir
# examples/01_simple_qa.exs
defmodule SimpleQA do
  use DSPex.Module
  signature "question -> answer"
  def forward(q), do: DSPex.predict(q)
end
```

2. **RAG Pipeline** (realistic use case)
```elixir
# examples/02_rag_pipeline.exs
defmodule RAGPipeline do
  use DSPex.Module

  signature "question, context -> answer"

  altar_tools [VectorSearchTool]

  def forward(question) do
    {:ok, docs} = Altar.execute(VectorSearchTool, query: question)
    DSPex.generate("Answer #{question} using: #{docs}")
  end
end
```

3. **Multi-Agent Research** (advanced)
```elixir
# examples/03_multi_agent.exs
defmodule ResearchTeam do
  defmodule Researcher do
    use DSPex.Module
    signature "topic -> research_data"
    altar_tools [SearchTool, ScrapeTool]
  end

  defmodule Writer do
    use DSPex.Module
    signature "research_data -> article"
  end

  def research(topic) do
    {:ok, data} = Researcher.forward(topic)
    Writer.forward(data)
  end
end
```

4. **Optimization Tutorial** (showing the value)
```elixir
# examples/04_optimization.exs

# Before optimization
qa = SimpleQA.create()
{:ok, score, _} = DSPex.Evaluate.evaluate(evaluator, qa)
IO.puts("Before: #{score * 100}%")  # → 60%

# After optimization
optimized = DSPex.Optimizers.BootstrapFewShot.compile(
  SimpleQA,
  trainset: train_data,
  metric: &exact_match/2
)

{:ok, score, _} = DSPex.Evaluate.evaluate(evaluator, optimized)
IO.puts("After: #{score * 100}%")  # → 85%!
```

---

#### **4.2 Documentation** (Week 21)

**Guides Needed**:

1. **Getting Started**
   - Installation
   - First DSPex module
   - Running predictions
   - Basic evaluation

2. **Optimization Guide**
   - How optimization works
   - BootstrapFewShot walkthrough
   - MIPRO for advanced cases
   - Saving/loading compiled modules

3. **Integration Guide**
   - Using with Foundation (agents)
   - ALTAR tool integration
   - Snakepit for Python models
   - Telemetry/AITrace

4. **Migration from Python DSPy**
   - API comparison
   - Feature parity matrix
   - Porting guide
   - Gradual migration strategy

5. **Architecture Deep Dive**
   - How DSPex works internally
   - Native vs Python execution
   - When to use each
   - Performance characteristics

---

### **Phase 5: Production Hardening** (4-6 weeks)

#### **5.1 Error Handling** (Week 22-23)

**Improvements Needed**:
```elixir
# Current: Bare {:error, reason}
# Needed: Structured error types

defmodule DSPex.Error do
  defexception [:type, :message, :context]

  def exception(opts) do
    %__MODULE__{
      type: opts[:type],
      message: opts[:message],
      context: opts[:context] || %{}
    }
  end
end

# Specific error types
defmodule DSPex.OptimizationError do
  defexception [:optimizer, :reason, :trainset_size]
end

defmodule DSPex.ToolExecutionError do
  defexception [:tool, :args, :reason]
end
```

**Benefits**:
- Better error messages
- Structured logging
- Error recovery strategies

---

#### **5.2 Performance Optimization** (Week 24)

**Benchmarks Needed**:
```elixir
# benchmark/dspex_vs_python.exs
Benchee.run(%{
  "DSPex Native Predict" => fn ->
    DSPex.Native.Predict.forward(predictor, inputs)
  end,

  "DSPex Python Bridge" => fn ->
    DSPex.Bridge.call_dspy("dspy.Predict", ...)
  end,

  "Direct gemini_ex" => fn ->
    Gemini.chat(prompt)
  end
})
```

**Optimizations**:
- Cache compiled prompts
- Batch predictions
- Parallel evaluation
- Connection pooling (snakepit)

---

#### **5.3 Production Checklist** (Week 25-26)

- [ ] All core modules have native Elixir implementations
- [ ] BootstrapFewShot optimizer working
- [ ] MIPRO optimizer working (optional)
- [ ] Evaluation framework complete
- [ ] ALTAR tool integration working
- [ ] Sinter schema integration complete
- [ ] Foundation agent adapter working
- [ ] Telemetry events emitted
- [ ] AITrace integration tested
- [ ] 5+ complete examples
- [ ] Full documentation
- [ ] Performance benchmarks
- [ ] 90%+ test coverage
- [ ] Dialyzer clean
- [ ] HexDocs published

---

## Dependencies & Integration Points

### **Current Dependencies** ✅
```elixir
{:snakepit, "~> 0.4.2"}     # Python bridge - WORKING
{:sinter, "~> 0.0.1"}       # Schemas - WORKING
{:instructor_lite, "~> 1.0"} # Structured outputs - WORKING
{:gemini_ex, "~> 0.0.3"}    # LLM client - WORKING
```

### **Missing Dependencies** ❌
```elixir
{:altar, "~> 0.1"}          # Tool protocol - NEEDED
{:foundation, "~> 0.1"}     # Agent framework - OPTIONAL
```

### **Integration Priority**

1. **ALTAR** (Week 1) - CRITICAL
   - Enables tool calling from DSPy
   - Foundation for all agent work

2. **sinter** (Week 2) - HIGH
   - Replace custom signature system
   - Unified schemas across ecosystem

3. **gemini_ex** (Week 3-4) - HIGH
   - Native Predict/CoT implementations
   - Better than Python bridge for simple cases

4. **foundation** (Week 17-18) - MEDIUM
   - DSPex modules as agents
   - Nice-to-have, not critical

5. **AITrace** (Week 19) - LOW
   - Telemetry integration
   - Important for production, not for MVP

---

## Timeline to Production-Ready

### **Aggressive (With Claude 5.0 in January)**

**January**: Phase 1 (Critical features)
- Week 1: ALTAR integration
- Week 2: Sinter integration
- Week 3-4: Native Predict + structured outputs
- Week 5-7: BootstrapFewShot
- Week 8: Evaluation framework

**February-March**: Phase 2 (Advanced features)
- Week 9-10: MIPRO optimizer
- Week 11-12: Native ChainOfThought
- Week 13-14: ReAct implementation

**April**: Phase 3 (Integration)
- Week 15-16: Compilation/serialization
- Week 17-18: Foundation integration
- Week 19: Telemetry/AITrace

**May**: Phase 4-5 (Polish & Launch)
- Week 20: Complete examples
- Week 21: Documentation
- Week 22-26: Production hardening

**Total**: 26 weeks (Jan-May)

### **Realistic (Accounting for Interruptions)**

Add 50% buffer: **39 weeks** (Jan-Aug)

### **With Focused Effort + Claude 5.0**

Claude 5.0 could provide **5-10x speedup** on:
- Optimizer implementation (complex logic)
- Test generation (hundreds of test cases)
- Documentation writing (guides, examples)

**Realistic aggressive**: **16-20 weeks** (Jan-mid May) ✅ **ACHIEVABLE**

---

## Success Metrics

### **Technical**
- [ ] Native Predict matches Python DSPy accuracy (±2%)
- [ ] BootstrapFewShot shows improvement (>10% accuracy gain)
- [ ] ALTAR tools work in DSPy chains
- [ ] Performance: <100ms for simple predictions
- [ ] Memory: <50MB for compiled module

### **Adoption**
- [ ] 3+ production users
- [ ] 50+ GitHub stars
- [ ] Featured in ElixirWeekly
- [ ] ElixirConf talk accepted

### **Quality**
- [ ] 90%+ test coverage
- [ ] Dialyzer clean
- [ ] Credo clean
- [ ] Full HexDocs
- [ ] 10+ examples

---

## Risks & Mitigation

### **Risk 1: Optimization Doesn't Work**
**Probability**: Medium (30%)
**Impact**: High (it's the core value prop)
**Mitigation**:
- Start with BootstrapFewShot (simpler)
- Validate on known datasets from DSPy papers
- Compare results with Python DSPy (should match)
- If Elixir optimization fails, use Python optimizers via bridge

### **Risk 2: Performance Too Slow**
**Probability**: Low (20%)
**Impact**: Medium (users care about speed)
**Mitigation**:
- Native implementations avoid gRPC overhead
- Connection pooling (snakepit already does this)
- Caching compiled prompts
- Benchmark early, optimize hotspots

### **Risk 3: ALTAR Integration Complexity**
**Probability**: Low (20%)
**Impact**: Medium (needed for tool use)
**Mitigation**:
- ALTAR is already proven (gemini_ex uses it)
- Just need to bridge to Python
- Snakepit bidirectional bridge already supports this

### **Risk 4: Claude 5.0 Delayed**
**Probability**: Medium (30%)
**Impact**: High (timeline depends on it)
**Mitigation**:
- Anthropic has good track record (unlikely delay)
- Can use Claude 4.5 + more manual work
- Start core work now (doesn't need Claude 5.0)

---

## Immediate Next Steps (This Week)

### **Step 1: Add ALTAR Dependency**
```bash
cd ~/p/g/n/DSPex
# mix.exs
{:altar, "~> 0.1.7"}
```

### **Step 2: Create Integration Stubs**
```elixir
# lib/dspex/altar_bridge.ex
defmodule DSPex.AltarBridge do
  def register_tools(session_id, modules) do
    # TODO: Implement
  end
end

# lib/dspex/optimizers/bootstrap_few_shot.ex
defmodule DSPex.Optimizers.BootstrapFewShot do
  def compile(module, opts) do
    # TODO: Implement
  end
end

# lib/dspex/evaluate.ex
defmodule DSPex.Evaluate do
  def new(opts), do: %__MODULE__{...}
  def evaluate(evaluator, module) do
    # TODO: Implement
  end
end
```

### **Step 3: Write Tests First** (TDD)
```elixir
# test/dspex/optimizers/bootstrap_few_shot_test.exs
test "learns from successful examples" do
  # Given training data with known answers
  trainset = [...]

  # When we compile with bootstrap
  optimized = BootstrapFewShot.compile(SimpleQA, trainset: trainset, ...)

  # Then accuracy improves
  assert optimized.demos |> length() > 0
  assert evaluate(optimized) > evaluate(SimpleQA)
end
```

### **Step 4: Document Plan**
This document! ✅ Done.

---

## Dependencies on Other Projects

### **Blocks DSPex**:
- ❌ ALTAR v0.1.8+ with tool execution API
- ⚠️ sinter v0.1+ with schema validation improvements
- ✅ snakepit v0.4.2 (already released!)
- ✅ gemini_ex v0.2.2 (already released!)

### **Blocked By DSPex**:
- Foundation agent integration (needs DSPex modules to work as agents)
- Citadel/AITrace (need DSPex telemetry)
- Assessor (needs DSPex evaluation framework)

**Critical Path**: Get ALTAR + sinter integrated ASAP (Week 1-2)

---

## Comparison: DSPex vs Python DSPy

### **Feature Parity Matrix**

| Feature | Python DSPy | DSPex v0.2.0 | DSPex Target (v1.0) |
|---------|-------------|--------------|---------------------|
| Signatures | ✅ | ✅ | ✅ |
| Predict | ✅ | ✅ (Python) | ✅ (Native) |
| ChainOfThought | ✅ | ✅ (Python) | ✅ (Native) |
| ReAct | ✅ | ❌ | ✅ (Native) |
| ProgramOfThought | ✅ | ❌ | ⚠️ (Python bridge) |
| BootstrapFewShot | ✅ | ❌ | ✅ (Native) |
| MIPRO | ✅ | ❌ | ✅ (Native) |
| Evaluation | ✅ | ❌ | ✅ (Native) |
| Metrics | ✅ | ❌ | ✅ (Native) |
| Tool Calling | ✅ | ⚠️ (Limited) | ✅ (ALTAR) |
| Compile/Save | ✅ | ❌ | ✅ (Native) |
| Streaming | ✅ | ❌ | ✅ (gemini_ex) |
| Multi-LLM | ✅ | ⚠️ (Gemini only) | ✅ (req_llm) |

**Current Parity**: ~40%
**Target Parity**: ~90% (some features Python-only, like retrieval models)

---

## Why DSPex Matters (The Value Prop)

### **For Elixir Developers**

**Problem**: Want to use DSPy but stuck in Python land
**Solution**: DSPex brings DSPy to Elixir with better:
- Concurrency (BEAM)
- Fault tolerance (OTP)
- Production reliability (supervision trees)
- Telemetry (built-in)

### **For Python DSPy Users**

**Problem**: DSPy works for prototypes but production is hard
**Solution**: DSPex provides:
- Production deployment (OTP supervision)
- Distributed execution (Elixir clustering)
- Observability (AITrace integration)
- Gradual migration (use Python DSPy via bridge)

### **For the Ecosystem**

DSPex is the **bridge** between:
- Python ML (models, libraries)
- Elixir production (reliability, scale)
- ALTAR tools (unified protocol)
- Foundation agents (orchestration)

**It's the linchpin.** Get DSPex to v1.0 and everything else connects.

---

## Conclusion

**DSPex needs**:
1. ✅ **Week 1-2**: ALTAR + sinter integration
2. ✅ **Week 3-7**: Native Predict + BootstrapFewShot optimizer
3. ✅ **Week 8**: Evaluation framework
4. ⚠️ **Week 9-14**: Advanced features (MIPRO, CoT, ReAct)
5. ⚠️ **Week 15-21**: Integration + docs
6. ⚠️ **Week 22-26**: Production hardening

**Timeline**: 26 weeks (Jan-Jun) aggressive, 39 weeks (Jan-Aug) realistic

**With Claude 5.0**: Could hit **20 weeks** (Jan-mid May) ✅

**This is your flagship project.** Get this right and the ecosystem falls into place.

---

**Next Action**: Start with ALTAR integration (this week). Everything else depends on it.

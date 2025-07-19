# DSPex V2: Clean Architecture with Mixed Native/Python Execution

## Vision

DSPex V2 is a ground-up redesign that treats Snakepit as the core dependency for Python interop while building a clean API that can seamlessly route between native Elixir and Python implementations. The design embraces Python processes as first-class citizens in the pipeline.

## Core Design Principles

1. **Implementation Agnostic API**: Users don't need to know if a feature is native or Python
2. **First-Class Python Processes**: Python components can be mixed freely in pipelines
3. **Gradual Native Adoption**: Implement native versions only where it makes sense
4. **Pipeline Composition**: Mix and match native and Python components seamlessly
5. **Performance Pragmatism**: Native for hot paths, Python for complex algorithms

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         DSPex Public API                         │
│              (Implementation-agnostic interface)                 │
└─────────────────────┬───────────────────────────────────────────┘
                      │
         ┌────────────▼────────────────────────────┐
         │         Execution Router                │
         │  (Routes based on availability & config) │
         └────┬──────────────────────┬─────────────┘
              │                      │
    ┌─────────▼──────────┐  ┌───────▼──────────────┐
    │   Native Registry  │  │   Python Registry   │
    │  (Elixir impls)    │  │  (Snakepit pools)   │
    └────────────────────┘  └────────────────────┘
              │                      │
    ┌─────────▼──────────┐  ┌───────▼──────────────┐
    │   Native Modules   │  │    Snakepit Core    │
    │ • Signatures       │  │ • Process pools     │
    │ • Templates        │  │ • Python bridge     │
    │ • Simple LLMs      │  │ • Session mgmt      │
    └────────────────────┘  └────────────────────┘
```

## API Design

### Unified Module Interface

```elixir
defmodule DSPex do
  @moduledoc """
  Clean, implementation-agnostic API for DSPy in Elixir.
  """
  
  # Signature operations - can be native or Python
  defdelegate signature(spec), to: DSPex.Router
  defdelegate compile_signature(string), to: DSPex.Router
  
  # Predictor operations - mixed implementations
  defdelegate predict(signature, inputs, opts \\ []), to: DSPex.Router
  defdelegate predictor(type, config \\ []), to: DSPex.Router
  
  # Module operations - always Python for now
  defdelegate chain_of_thought(signature, opts \\ []), to: DSPex.Router
  defdelegate react(signature, tools, opts \\ []), to: DSPex.Router
  
  # Optimizer operations - Python-only (MIPROv2)
  defdelegate optimize(module, examples, opts \\ []), to: DSPex.Router
  
  # Pipeline composition - the key innovation
  def pipeline(steps) do
    %DSPex.Pipeline{steps: steps}
  end
end
```

### Router Implementation

```elixir
defmodule DSPex.Router do
  @moduledoc """
  Routes operations to native or Python implementations based on availability.
  """
  
  @native_registry %{
    signature: DSPex.Native.Signature,
    compile_signature: DSPex.Native.Signature,
    predict: DSPex.Native.Predictor,
    # Templates make sense native - just string manipulation
    template: DSPex.Native.Template
  }
  
  @python_registry %{
    # Complex algorithms stay in Python
    chain_of_thought: "dspy.ChainOfThought",
    react: "dspy.ReAct", 
    optimize: "dspy.MIPROv2",
    # Some predictors might be Python-only
    predict_anthropic: "dspy.Claude"
  }
  
  def signature(spec) do
    # Check if native implementation exists
    if impl = @native_registry[:signature] do
      impl.create(spec)
    else
      # Fallback to Python via Snakepit
      python_call(:signature, spec)
    end
  end
  
  defp python_call(operation, args) do
    # Get or create Snakepit pool for DSPy operations
    pool = DSPex.PoolManager.get_pool(:dspy)
    
    Snakepit.call(pool, %{
      module: @python_registry[operation],
      operation: operation,
      args: args
    })
  end
end
```

## Pipeline Composition - The Key Innovation

This is where DSPex shines - seamlessly mixing native and Python components:

```elixir
defmodule DSPex.Pipeline do
  @moduledoc """
  Composable pipelines that mix native and Python execution.
  """
  
  defstruct [:steps, :session_id]
  
  def new(steps) do
    %__MODULE__{
      steps: steps,
      session_id: generate_session_id()
    }
  end
  
  def run(pipeline, input) do
    # Each step can be native or Python
    Enum.reduce(pipeline.steps, {:ok, input}, fn
      step, {:ok, data} -> execute_step(step, data, pipeline.session_id)
      _, error -> error
    end)
  end
  
  defp execute_step({:native, module, opts}, input, _session_id) do
    # Direct Elixir execution
    apply(module, :run, [input, opts])
  end
  
  defp execute_step({:python, module, opts}, input, session_id) do
    # Python execution through Snakepit with session affinity
    pool = DSPex.PoolManager.get_pool(:dspy)
    
    Snakepit.call(pool, %{
      module: module,
      method: "run",
      args: [input],
      kwargs: opts
    }, session_id: session_id)
  end
  
  defp execute_step({:parallel, steps}, input, session_id) do
    # Run steps in parallel, mixing native and Python!
    steps
    |> Task.async_stream(fn step -> 
      execute_step(step, input, session_id)
    end)
    |> Enum.reduce({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, acc} -> {:ok, [result | acc]}
      _, _ -> {:error, "Parallel execution failed"}
    end)
  end
end
```

## Real-World Example: Mixed Execution Pipeline

```elixir
defmodule MyApp.ComplexPipeline do
  import DSPex
  
  def research_assistant_pipeline do
    pipeline([
      # Step 1: Native signature parsing (fast)
      {:native, DSPex.Native.Signature, 
        spec: "question -> search_queries: list[str]"},
      
      # Step 2: Python ChainOfThought (complex reasoning)
      {:python, "dspy.ChainOfThought", 
        signature: "search_queries -> refined_queries"},
      
      # Step 3: Parallel execution mixing native and Python
      {:parallel, [
        {:native, MyApp.VectorSearch, index: "documents"},
        {:python, "dspy.ColBERTv2", collection: "papers"},
        {:native, MyApp.WebSearch, engine: :google}
      ]},
      
      # Step 4: Python-only MIPROv2 for synthesis
      {:python, "dspy.MIPROv2", 
        task: "synthesize_answer",
        max_examples: 10},
      
      # Step 5: Native post-processing
      {:native, MyApp.ResponseFormatter, format: :markdown}
    ])
  end
  
  def run(question) do
    research_assistant_pipeline()
    |> DSPex.Pipeline.run(%{question: question})
  end
end
```

## Native vs Python Decision Matrix

### Always Native
- **Signatures**: Just parsing and data structures
- **Templates**: String manipulation
- **Simple Predictors**: Direct HTTP calls to LLMs
- **Response Parsing**: JSON/text processing
- **Caching**: ETS-based caching layer

### Always Python
- **MIPROv2**: Complex optimization algorithm
- **ColBERTv2**: Specialized retrieval model
- **Advanced Optimizers**: Bootstrap, COPRO, etc.
- **Research Features**: Experimental DSPy features

### Depends on Requirements
- **Chain of Thought**: Simple version native, advanced Python
- **RAG**: Native for simple, Python for advanced
- **Assertions**: Native for basic, Python for complex

## Pool Management with Snakepit

```elixir
defmodule DSPex.PoolManager do
  @moduledoc """
  Manages Snakepit pools for different Python components.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Start default DSPy pool
    {:ok, dspy_pool} = start_pool(:dspy, 
      python_path: "python3",
      script: "priv/python/dspy_bridge.py",
      pool_size: 4
    )
    
    # Start specialized pools for heavy components
    {:ok, mipro_pool} = start_pool(:mipro,
      python_path: "python3", 
      script: "priv/python/mipro_bridge.py",
      pool_size: 2  # MIPROv2 is memory intensive
    )
    
    {:ok, %{pools: %{dspy: dspy_pool, mipro: mipro_pool}}}
  end
  
  defp start_pool(name, config) do
    Snakepit.start_pool(name, Snakepit.Adapters.Python, config)
  end
end
```

## Python Bridge Scripts

```python
# priv/python/dspy_bridge.py
import json
import dspy
from dspy import ChainOfThought, ReAct, Predict

class DSPyBridge:
    def __init__(self):
        self.modules = {}
        self.programs = {}
    
    def handle_request(self, request):
        """Route requests to appropriate DSPy components."""
        operation = request["operation"]
        
        if operation == "chain_of_thought":
            return self.create_cot(request["args"])
        elif operation == "optimize":
            return self.run_mipro(request["args"])
        # ... other operations
    
    def create_cot(self, args):
        """Create and cache a ChainOfThought module."""
        signature = args["signature"]
        module_id = f"cot_{id(signature)}"
        
        self.modules[module_id] = ChainOfThought(signature)
        return {"module_id": module_id}

# priv/python/mipro_bridge.py
import dspy
from dspy.teleprompt import MIPROv2

class MIPROBridge:
    """Dedicated bridge for MIPROv2 optimization."""
    
    def optimize(self, module, trainset, **kwargs):
        optimizer = MIPROv2(
            metric=kwargs.get("metric"),
            num_candidates=kwargs.get("num_candidates", 10),
            init_temperature=kwargs.get("init_temperature", 1.0)
        )
        
        return optimizer.compile(
            module,
            trainset=trainset,
            requires_permission_to_run=False
        )
```

## Benefits of This Architecture

### 1. **Flexibility**
- Add native implementations incrementally
- Keep using Python for complex algorithms
- Mix and match in pipelines

### 2. **Performance**
- Native for hot paths (parsing, templates)
- Python for complex but less frequent operations
- Parallel execution across native and Python

### 3. **Maintainability**
- Clear separation of concerns
- Easy to add new implementations
- Single API regardless of implementation

### 4. **Pragmatism**
- Don't reimplement complex Python algorithms
- Focus native efforts where they matter
- Embrace Python as first-class citizen

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)
- Set up Snakepit as dependency
- Create Router and PoolManager
- Basic native Signature implementation
- Python bridge for everything else

### Phase 2: Native Hot Paths (Week 3-4)
- Native template engine
- Native simple predictors (OpenAI, Anthropic)
- Native response parsing
- Benchmark vs Python

### Phase 3: Pipeline Composition (Week 5-6)
- Pipeline execution engine
- Mixed parallel execution
- Session management across native/Python
- Real-world pipeline examples

### Phase 4: Optimization (Week 7-8)
- Performance profiling
- Identify next native candidates
- Pool tuning for Python components
- Production readiness

## Example Usage

```elixir
# Simple usage - implementation transparent
{:ok, signature} = DSPex.signature("question -> answer")
{:ok, result} = DSPex.predict(signature, %{question: "What is DSPy?"})

# Advanced pipeline - explicit about implementation
pipeline = DSPex.pipeline([
  {:native, DSPex.Native.Signature, spec: "question -> queries: list"},
  {:python, "dspy.ChainOfThought", signature: "queries -> answer"}, 
  {:native, DSPex.Native.Cache, ttl: 3600}
])

{:ok, result} = DSPex.Pipeline.run(pipeline, %{question: "Complex question"})

# Python-only features remain Python
{:ok, optimized} = DSPex.optimize(my_module, trainset, 
  optimizer: :miprov2,
  metric: my_metric,
  num_candidates: 20
)
```

This architecture gives you the best of both worlds - native performance where it matters and Python's rich ecosystem where complexity lives.
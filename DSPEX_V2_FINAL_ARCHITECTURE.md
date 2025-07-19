# DSPex V2: Final Architecture with Complete DSPy Feature Set

## Executive Summary

Based on the comprehensive DSPy API analysis, this document presents the final architecture for DSPex V2 - a clean-slate implementation using Snakepit as the Python bridge while strategically implementing native Elixir components where they provide the most value.

## Key Insights from Full DSPy Analysis

The complete DSPy framework includes:
- **8 Major Module Types**: Predict, ChainOfThought, ReAct, ProgramOfThought, MultiChainComparison, BestOfN, Refine, Parallel
- **5+ Optimizers**: BootstrapFewShot, MIPRO/MIPROv2, COPRO, Ensemble, BootstrapFinetune
- **25+ Vector Databases**: Through unified retrieval interface
- **30+ LLM Providers**: Via LiteLLM integration
- **Advanced Features**: Multi-modal support, streaming, synthesis, evaluation framework

## Revised Native vs Python Strategy

### 🟢 Definitely Native (High Impact, Low Complexity)

1. **Signatures** - Pure data structures and validation
2. **Basic Templates** - String manipulation with EEx
3. **LLM Client Interface** - Direct HTTP calls to providers
4. **Caching Layer** - ETS-based with distributed support
5. **Evaluation Metrics** - Simple computations (exact_match, f1, etc.)
6. **Pipeline Orchestration** - Elixir's strength in coordination

### 🔴 Keep in Python (Complex Algorithms, Research Code)

1. **All Optimizers** - MIPRO/v2, COPRO, BootstrapFewShot, etc.
2. **Advanced Modules** - ReAct, ProgramOfThought, MultiChainComparison
3. **Vector Databases** - 25+ integrations already in DSPy
4. **ColBERTv2** - Specialized retrieval model
5. **Multi-Modal Processing** - Image/audio handling
6. **Synthesizer** - Training data generation

### 🟡 Hybrid Approach (Mix Native and Python)

1. **Predict Module** - Native for simple cases, Python for complex
2. **ChainOfThought** - Native wrapper, Python reasoning extraction  
3. **Parallel Module** - Native orchestration, Python execution
4. **Streaming** - Native event handling, Python generation

## Final Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         DSPex Public API                         │
│                    (Clean, Elixir-idiomatic)                     │
└─────────────────────┬───────────────────────────────────────────┘
                      │
         ┌────────────▼────────────────────────────┐
         │          Execution Router               │
         │   (Smart routing based on capability)   │
         └────┬──────────────────────┬─────────────┘
              │                      │
    ┌─────────▼──────────┐  ┌───────▼──────────────┐
    │   Native Engine    │  │  Snakepit Manager   │
    │                    │  │                      │
    │ • Signatures       │  │ • Module Pools       │
    │ • Templates        │  │ • Optimizer Pools    │
    │ • LLM Clients      │  │ • Retriever Pools    │
    │ • Metrics          │  │ • Stateful Sessions  │
    │ • Pipeline Orch    │  │                      │
    └────────────────────┘  └──────────┬───────────┘
                                       │
                            ┌──────────▼───────────┐
                            │   Python DSPy        │
                            │  (Full Framework)    │
                            └──────────────────────┘
```

## Implementation Modules

### 1. Core API (lib/dspex.ex)

```elixir
defmodule DSPex do
  @moduledoc """
  Main API matching DSPy's structure but with Elixir idioms.
  """
  
  # Signatures - Native implementation
  defdelegate signature(spec), to: DSPex.Native.Signature
  defdelegate compile_signature(string), to: DSPex.Native.Signature
  
  # Modules - Routed based on complexity
  defdelegate predict(signature, inputs, opts \\ []), to: DSPex.Router
  defdelegate chain_of_thought(signature, opts \\ []), to: DSPex.Router
  defdelegate react(signature, tools, opts \\ []), to: DSPex.Router
  defdelegate program_of_thought(signature, opts \\ []), to: DSPex.Router
  
  # Optimizers - Always Python
  defdelegate bootstrap_few_shot(program, trainset, opts \\ []), to: DSPex.Python.Optimizers
  defdelegate mipro(program, trainset, opts \\ []), to: DSPex.Python.Optimizers
  defdelegate mipro_v2(program, trainset, opts \\ []), to: DSPex.Python.Optimizers
  
  # Retrievers - Always Python (25+ integrations)
  defdelegate retriever(type, config), to: DSPex.Python.Retrievers
  
  # LLM Clients - Native interface, provider-specific impl
  defdelegate lm(provider, config), to: DSPex.Native.LMClient
  
  # Evaluation - Mixed (metrics native, framework Python)
  defdelegate evaluate(program, dataset, metrics, opts \\ []), to: DSPex.Router
  
  # Pipeline composition - Native orchestration
  defdelegate pipeline(steps), to: DSPex.Native.Pipeline
end
```

### 2. Native Implementations

```elixir
defmodule DSPex.Native.Signature do
  @moduledoc """
  Native signature implementation with full DSPy compatibility.
  """
  
  defstruct [:name, :instructions, :fields, :metadata]
  
  def parse(spec) when is_binary(spec) do
    # Parse DSPy signature syntax natively
    with {:ok, tokens} <- tokenize(spec),
         {:ok, ast} <- build_ast(tokens),
         {:ok, signature} <- validate_and_build(ast) do
      {:ok, signature}
    end
  end
  
  def parse(spec) when is_map(spec) do
    # Support map-based definitions
    %__MODULE__{
      fields: parse_fields(spec),
      metadata: Map.get(spec, :metadata, %{})
    }
  end
end

defmodule DSPex.Native.LMClient do
  @moduledoc """
  Native LLM client with provider abstraction.
  """
  
  @providers %{
    openai: DSPex.Native.Providers.OpenAI,
    anthropic: DSPex.Native.Providers.Anthropic,
    google: DSPex.Native.Providers.Google,
    # ... more providers
  }
  
  def configure(provider, config) do
    module = @providers[provider] || DSPex.Python.Providers.LiteLLM
    module.configure(config)
  end
  
  def generate(client, prompt, opts \\ []) do
    client.module.generate(client.config, prompt, opts)
  end
end

defmodule DSPex.Native.Pipeline do
  @moduledoc """
  Native pipeline orchestration leveraging Elixir's strengths.
  """
  
  defstruct [:steps, :context, :metrics]
  
  def new(steps) do
    %__MODULE__{
      steps: compile_steps(steps),
      context: %{},
      metrics: init_metrics()
    }
  end
  
  def run(pipeline, input) do
    pipeline.steps
    |> Enum.reduce({:ok, input}, &execute_step/2)
    |> tap(fn _ -> report_metrics(pipeline.metrics) end)
  end
  
  defp execute_step(_step, {:error, _} = error), do: error
  defp execute_step(step, {:ok, input}) do
    with {:ok, result} <- run_step(step, input) do
      {:ok, result}
    end
  end
end
```

### 3. Snakepit Integration

```elixir
defmodule DSPex.Python do
  @moduledoc """
  Snakepit-based Python integration for complex DSPy features.
  """
  
  defmodule Pools do
    use Supervisor
    
    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def init(_opts) do
      children = [
        # Lightweight pool for simple operations
        pool_spec(:modules, size: 8, script: "dspy_modules.py"),
        
        # Heavy pool for optimizers
        pool_spec(:optimizers, size: 2, memory: "4GB", script: "dspy_optimizers.py"),
        
        # Specialized pool for retrievers
        pool_spec(:retrievers, size: 4, gpu: true, script: "dspy_retrievers.py"),
        
        # Multi-modal pool
        pool_spec(:multimodal, size: 2, memory: "8GB", script: "dspy_multimodal.py")
      ]
      
      Supervisor.init(children, strategy: :one_for_one)
    end
    
    defp pool_spec(name, opts) do
      {Snakepit.Pool,
        name: name,
        adapter: Snakepit.Adapters.Python,
        python_path: python_env(name),
        script: Path.join("priv/python", opts[:script]),
        pool_size: opts[:size],
        max_memory: opts[:memory],
        gpu_enabled: opts[:gpu] || false}
    end
  end
  
  defmodule Modules do
    @moduledoc """
    Python implementation of complex DSPy modules.
    """
    
    def chain_of_thought(signature, opts) do
      Snakepit.call(:modules, %{
        module: "dspy.ChainOfThought",
        method: "forward",
        args: [serialize_signature(signature)],
        kwargs: opts
      })
    end
    
    def react(signature, tools, opts) do
      Snakepit.call(:modules, %{
        module: "dspy.ReAct",
        method: "forward",
        args: [serialize_signature(signature), serialize_tools(tools)],
        kwargs: opts
      })
    end
    
    def program_of_thought(signature, opts) do
      Snakepit.call(:modules, %{
        module: "dspy.ProgramOfThought",
        method: "forward",
        args: [serialize_signature(signature)],
        kwargs: opts
      })
    end
  end
  
  defmodule Optimizers do
    @moduledoc """
    All DSPy optimizers through Python.
    """
    
    def mipro_v2(program, trainset, opts) do
      # Create stateful session for optimization
      with {:ok, session} <- Snakepit.create_session(:optimizers),
           {:ok, _} <- init_optimizer(session, "MIPROv2", opts),
           {:ok, result} <- run_optimization(session, program, trainset) do
        {:ok, result}
      end
    end
    
    defp run_optimization(session, program, trainset) do
      # Stream progress updates
      Snakepit.stream_call(session, %{
        method: "optimize",
        args: [program, trainset],
        stream_events: true
      })
      |> Stream.each(&handle_optimization_event/1)
      |> Stream.run()
    end
  end
end
```

### 4. Smart Router

```elixir
defmodule DSPex.Router do
  @moduledoc """
  Intelligently routes operations to native or Python implementations.
  """
  
  @native_capable [:predict, :evaluate_metrics]
  @python_only [:react, :program_of_thought, :multi_chain_comparison]
  @hybrid [:chain_of_thought, :parallel, :evaluate]
  
  def route(operation, args) do
    cond do
      operation in @native_capable and native_available?(operation) ->
        route_to_native(operation, args)
        
      operation in @python_only ->
        route_to_python(operation, args)
        
      operation in @hybrid ->
        route_hybrid(operation, args)
        
      true ->
        {:error, "Unknown operation: #{operation}"}
    end
  end
  
  defp route_hybrid(:chain_of_thought, [signature, opts]) do
    if opts[:reasoning_extraction] || opts[:advanced] do
      # Complex CoT needs Python
      DSPex.Python.Modules.chain_of_thought(signature, opts)
    else
      # Simple CoT can be native
      DSPex.Native.Modules.simple_cot(signature, opts)
    end
  end
end
```

### 5. Real-World Pipeline Example

```elixir
defmodule MyApp.ResearchAssistant do
  import DSPex
  
  def build_pipeline do
    pipeline([
      # Native: Parse user query
      {:native, DSPex.Native.QueryParser,
        signature: "query -> search_terms: list, filters: map"},
      
      # Python: Complex reasoning with CoT
      {:python, "dspy.ChainOfThought",
        signature: "search_terms -> refined_queries: list, strategy: str"},
      
      # Parallel retrieval (mixed)
      {:parallel, [
        # Native: PostgreSQL FTS
        {:native, MyApp.PostgresSearch, limit: 100},
        
        # Python: Neural retrieval
        {:python, "dspy.ColBERTv2", k: 50},
        
        # Python: Vector search via Pinecone
        {:python, retriever(:pinecone, index: "research-papers")}
      ]},
      
      # Python: Advanced reranking
      {:python, "dspy.Reranker", model: "cross-encoder/ms-marco"},
      
      # Python: Multi-chain reasoning
      {:python, "dspy.MultiChainComparison",
        chains: 3,
        aggregation: "weighted_vote"},
      
      # Native: Response formatting
      {:native, DSPex.Native.ResponseFormatter,
        format: :markdown,
        citations: true},
      
      # Native: Caching
      {:native, DSPex.Native.Cache, ttl: :timer.hours(1)}
    ])
  end
  
  def research(query) do
    pipeline = build_pipeline()
    
    # Run with progress tracking
    DSPex.Pipeline.run(pipeline, %{query: query},
      on_progress: fn event ->
        Logger.info("Pipeline progress: #{inspect(event)}")
      end
    )
  end
end
```

## Key Benefits of This Architecture

1. **Pragmatic Native Implementation**: Only implement what makes sense in Elixir
2. **Full DSPy Power**: Access to all 40+ modules, optimizers, and retrievers
3. **Seamless Integration**: Mix native and Python in the same pipeline
4. **Performance Where It Matters**: Native for hot paths, Python for complex ML
5. **Maintainability**: No need to track DSPy research updates for complex algorithms

## Implementation Phases

### Phase 1: Foundation (Week 1)
- Set up Snakepit dependency
- Implement native Signature module
- Create basic Router
- Set up Python pools

### Phase 2: Core Modules (Week 2)
- Native LMClient for OpenAI/Anthropic
- Native Pipeline orchestration
- Python bridge for complex modules
- Basic evaluate with native metrics

### Phase 3: Production Features (Week 3)
- Streaming support
- Progress tracking
- Error handling
- Distributed caching

### Phase 4: Polish (Week 4)
- Performance optimization
- Documentation
- Example pipelines
- Testing suite

This architecture gives you the best of both worlds - Elixir's strengths in orchestration and concurrency with Python's rich ML ecosystem.
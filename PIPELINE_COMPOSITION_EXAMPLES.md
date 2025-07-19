# DSPex Pipeline Composition Examples

## Overview

This document demonstrates how DSPex V2 enables seamless composition of native Elixir and Python components in complex ML pipelines. Each example shows real-world use cases where mixing implementations provides optimal performance and functionality.

## Example 1: Hybrid RAG Pipeline

A retrieval-augmented generation pipeline that uses native Elixir for fast operations and Python for complex ML models.

```elixir
defmodule MyApp.HybridRAG do
  import DSPex
  
  def build_pipeline(opts \\ []) do
    pipeline([
      # Native: Fast query parsing and expansion
      {:native, QueryParser, 
        signature: "user_query -> search_terms: list[str], filters: dict"},
      
      # Parallel retrieval: Mix native and Python
      {:parallel, [
        # Native: PostgreSQL full-text search (fast)
        {:native, PgSearch, index: "documents", limit: 100},
        
        # Python: Neural retrieval with ColBERTv2 (accurate)
        {:python, "dspy.ColBERTv2", 
          collection: "scientific_papers",
          top_k: 50},
        
        # Native: Elasticsearch for metadata filtering
        {:native, ElasticSearch, 
          index: "metadata",
          filters: :dynamic}  # Uses filters from step 1
      ]},
      
      # Python: Reranking with cross-encoder (complex ML)
      {:python, "dspy.Reranker",
        model: "cross-encoder/ms-marco-MiniLM-L-12-v2",
        top_k: 10},
      
      # Native: Context assembly (string manipulation)
      {:native, ContextBuilder,
        max_tokens: 4000,
        format: :markdown},
      
      # Mixed: Answer generation with fallback
      {:with_fallback,
        primary: {:native, GPT4, temperature: 0.7},
        fallback: {:python, "dspy.Claude", model: "claude-3-opus"}},
      
      # Native: Response caching
      {:native, ResponseCache, ttl: :timer.hours(1)}
    ])
  end
end
```

## Example 2: Multi-Stage Reasoning Pipeline

Complex reasoning that requires both fast native processing and sophisticated Python algorithms.

```elixir
defmodule MyApp.ReasoningPipeline do
  import DSPex
  
  def scientific_reasoning_pipeline do
    pipeline([
      # Stage 1: Problem decomposition
      {:native, ProblemParser,
        signature: "problem -> subproblems: list[str], constraints: list[str]"},
      
      # Stage 2: Parallel hypothesis generation
      {:map_over, :subproblems, [
        # Python: Chain-of-thought for each subproblem
        {:python, "dspy.ChainOfThought",
          signature: "subproblem -> hypothesis, confidence: float"},
        
        # Native: Quick validation
        {:native, HypothesisValidator,
          check_constraints: :dynamic}  # From stage 1
      ]},
      
      # Stage 3: Python-only MIPROv2 optimization
      {:python, "dspy.MIPROv2",
        task: "hypothesis_refinement",
        num_candidates: 20,
        metric: "scientific_accuracy"},
      
      # Stage 4: Synthesis
      {:branch,
        condition: {:native, ConfidenceChecker, threshold: 0.8},
        if_true: [
          {:native, FastSynthesis, format: :latex}
        ],
        if_false: [
          # Need more sophisticated reasoning
          {:python, "dspy.ProgramOfThought",
            signature: "hypotheses -> synthesis, proof"},
          {:python, "dspy.SelfRefine",
            iterations: 3}
        ]
      },
      
      # Stage 5: Formatting
      {:native, ScientificFormatter,
        include_citations: true,
        format: :pdf}
    ])
  end
end
```

## Example 3: Production ML Pipeline with Monitoring

A production-ready pipeline that demonstrates observability and error handling across native and Python components.

```elixir
defmodule MyApp.ProductionPipeline do
  import DSPex
  
  def monitored_pipeline do
    pipeline([
      # Wrap entire pipeline with monitoring
      {:with_telemetry, [
        
        # Input validation (native - fast)
        {:native, InputValidator,
          schema: MyApp.Schemas.UserQuery,
          sanitize: true},
        
        # Feature extraction with timeout
        {:with_timeout, :timer.seconds(5), [
          {:parallel, [
            {:native, TextFeatures, metrics: [:length, :complexity]},
            {:native, UserFeatures, history_limit: 10},
            {:python, "dspy.SentimentAnalyzer", model: "roberta"}
          ]}
        ]},
        
        # Main processing with circuit breaker
        {:with_circuit_breaker, :ml_processing, [
          # Try native first (fast)
          {:native, SimpleClassifier,
            model: :logistic_regression,
            threshold: 0.9},
          
          # If low confidence, use Python
          {:when, {:confidence, :<, 0.9}, [
            {:python, "dspy.ZeroShotClassifier",
              labels: MyApp.Config.labels(),
              hypothesis_template: "This text is about {}"}
          ]}
        ]},
        
        # A/B test different approaches
        {:ab_test, :response_generation,
          variants: [
            control: {:python, "dspy.Predict", signature: "context -> response"},
            treatment: {:native, LlamaPredictor, model: "llama3:70b"}
          ],
          split: 0.2},  # 20% get treatment
        
        # Response filtering (native - fast)
        {:native, ContentFilter,
          check_pii: true,
          check_toxicity: true},
        
        # Async logging (fire and forget)
        {:async, [
          {:native, AuditLogger, level: :info},
          {:python, "dspy.ResponseAnalyzer", metrics: :all}
        ]}
      ]}
    ])
  end
end
```

## Example 4: Streaming Pipeline

Real-time processing mixing native stream processing with Python ML models.

```elixir
defmodule MyApp.StreamingPipeline do
  import DSPex
  
  def realtime_pipeline do
    pipeline([
      # Native: Fast streaming ingestion
      {:stream_native, Tokenizer,
        delimiter: :sentence,
        buffer_size: 100},
      
      # Batch for efficiency
      {:batch, size: 10, timeout: 100, [
        
        # Native: Quick filtering
        {:filter_native, RelevanceFilter,
          min_score: 0.5},
        
        # Python: Batch embedding generation
        {:python, "dspy.BatchEmbedder",
          model: "sentence-transformers/all-MiniLM-L6-v2"},
        
        # Native: Fast vector similarity
        {:native, VectorSimilarity,
          index: :faiss,
          top_k: 5}
      ]},
      
      # Stream results back
      {:stream_each, [
        # Enrich with Python model
        {:python, "dspy.EntityExtractor",
          types: ["person", "organization", "location"]},
        
        # Native: Format and emit
        {:native, StreamEmitter,
          format: :server_sent_events,
          channel: :updates}
      ]}
    ])
  end
end
```

## Example 5: Advanced Optimization Pipeline

Demonstrates how MIPROv2 and other Python-only optimizers integrate with native components.

```elixir
defmodule MyApp.OptimizationPipeline do
  import DSPex
  
  def training_pipeline(trainset) do
    pipeline([
      # Stage 1: Data preparation (native - fast)
      {:native, DataPreprocessor,
        normalize: true,
        remove_outliers: true},
      
      # Stage 2: Feature engineering
      {:parallel, [
        {:native, StatisticalFeatures, metrics: [:mean, :std, :skew]},
        {:python, "dspy.TFIDFVectorizer", max_features: 1000},
        {:python, "dspy.WordEmbeddings", model: "glove-6B"}
      ]},
      
      # Stage 3: Initial model (native for speed)
      {:native, BaselineModel,
        algorithm: :gradient_boosting,
        cv_folds: 5},
      
      # Stage 4: Python-only MIPROv2 optimization
      {:python_session, session_id: "optimization_#{trainset.id}", [
        
        # Create DSPy module
        {:python, "dspy.ChainOfThought",
          signature: "features -> prediction, reasoning"},
        
        # Run MIPROv2 optimization
        {:python, "dspy.MIPROv2",
          metric: {:native, F1Score},  # Native metric calculation!
          num_candidates: 50,
          init_temperature: 1.4,
          track_stats: true},
        
        # Bootstrap additional examples
        {:python, "dspy.BootstrapFewShotWithRandomSearch",
          max_bootstrapped_demos: 8,
          max_rounds: 3}
      ]},
      
      # Stage 5: Ensemble native and optimized Python
      {:ensemble, [
        weight: 0.3, model: {:native, BaselineModel},
        weight: 0.7, model: {:python, :optimized_module}
      ]},
      
      # Stage 6: Native evaluation
      {:native, ModelEvaluator,
        metrics: [:accuracy, :precision, :recall, :f1],
        generate_report: true}
    ])
  end
end
```

## Example 6: Dynamic Pipeline Composition

Shows how pipelines can be composed dynamically based on runtime conditions.

```elixir
defmodule MyApp.DynamicPipeline do
  import DSPex
  
  def build_adaptive_pipeline(user_config) do
    base_steps = [
      {:native, InputNormalizer}
    ]
    
    # Add steps based on user configuration
    processing_steps = 
      case user_config.processing_level do
        :basic ->
          [{:native, BasicProcessor, threshold: 0.7}]
          
        :advanced ->
          [
            {:python, "dspy.ChainOfThought", signature: "input -> analysis"},
            {:python, "dspy.SelfAsk", follow_up_questions: 3}
          ]
          
        :premium ->
          [
            {:parallel, [
              {:python, "dspy.ReAct", tools: user_config.tools},
              {:python, "dspy.ProgramOfThought"},
              {:native, StructuredReasoning}
            ]},
            {:python, "dspy.MIPROv2", 
              optimize_for: user_config.optimization_target}
          ]
      end
    
    # Conditionally add features
    optional_steps = []
    
    if user_config.enable_caching do
      optional_steps = [{:native, ResponseCache, ttl: 3600} | optional_steps]
    end
    
    if user_config.enable_monitoring do
      optional_steps = [{:native, PerformanceMonitor} | optional_steps]
    end
    
    # Compose final pipeline
    pipeline(base_steps ++ processing_steps ++ optional_steps)
  end
  
  def execute_with_fallback(pipeline, input) do
    # Primary execution
    case DSPex.Pipeline.run(pipeline, input) do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, :python_unavailable} ->
        # Fallback to native-only pipeline
        fallback = build_native_only_pipeline()
        DSPex.Pipeline.run(fallback, input)
        
      error ->
        error
    end
  end
end
```

## Pipeline Patterns

### Pattern 1: Fast Path with Python Fallback
```elixir
{:with_fallback,
  primary: {:native, FastPredictor, confidence_threshold: 0.9},
  fallback: {:python, "dspy.AdvancedPredictor"}}
```

### Pattern 2: Parallel Native + Python
```elixir
{:parallel, [
  {:native, QuickSearch, limit: 100},
  {:python, "dspy.NeuralSearch", top_k: 20}
]}
```

### Pattern 3: Python Session for Stateful Operations
```elixir
{:python_session, session_id: "optimization_123", [
  {:python, "dspy.Module", config: :stateful},
  {:python, "dspy.Optimize", use_previous_state: true}
]}
```

### Pattern 4: Conditional Branching
```elixir
{:branch,
  condition: {:native, ComplexityChecker},
  if_simple: [{:native, SimpleSolver}],
  if_complex: [{:python, "dspy.AdvancedSolver"}]}
```

### Pattern 5: Map Over Collections
```elixir
{:map_over, :documents, [
  {:native, TextCleaner},
  {:python, "dspy.Embedder"},
  {:native, VectorStore, action: :upsert}
]}
```

## Performance Considerations

1. **Native First**: Use native for I/O, parsing, simple transforms
2. **Python for ML**: Complex models stay in Python
3. **Parallel When Possible**: Mix native and Python in parallel steps
4. **Session Affinity**: Keep stateful Python operations in same session
5. **Batch Operations**: Batch Python calls to amortize overhead

## Error Handling

```elixir
pipeline([
  {:try, [
    {:python, "dspy.ComplexModule"}
  ],
  catch: [
    {:native, ErrorHandler, log: true},
    {:native, FallbackProcessor}
  ]},
  
  {:ensure, [
    {:native, CleanupHandler}
  ]}
])
```

These examples demonstrate the power of DSPex V2's mixed execution model, where native Elixir and Python components work together seamlessly to create efficient, maintainable ML pipelines.
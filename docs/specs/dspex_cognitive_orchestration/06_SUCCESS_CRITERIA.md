# Success Criteria: Tests and Examples for Each Stage

## Overview

This document defines concrete success criteria for each implementation stage of DSPex. Each stage must pass specific tests and demonstrate working examples before moving to the next stage.

## Stage 1: Foundation with Snakepit Integration

### Success Tests

```elixir
defmodule DSPex.FoundationTest do
  use ExUnit.Case
  
  test "Snakepit pools are properly configured and started" do
    assert {:ok, pid} = Snakepit.checkout(:general)
    assert Process.alive?(pid)
    Snakepit.checkin(:general, pid)
  end
  
  test "All three pool types are available" do
    for pool <- [:general, :optimizer, :neural] do
      assert Snakepit.pool_exists?(pool)
      assert {:ok, stats} = Snakepit.get_pool_stats(pool)
      assert stats.size > 0
    end
  end
  
  test "Python DSPy is accessible through bridge" do
    {:ok, result} = Snakepit.execute(:general, "ping", %{})
    assert result["status"] == "ok"
    assert result["dspy_version"] =~ ~r/\d+\.\d+\.\d+/
  end
end
```

### Working Example

```elixir
# Basic DSPy operation through Snakepit
{:ok, result} = DSPex.Foundation.execute_raw("echo", %{message: "Hello DSPex"})
assert result == %{"message" => "Hello DSPex", "timestamp" => _}

# Verify pool health
{:ok, stats} = DSPex.Foundation.get_pool_stats()
assert stats.general.available == 8
assert stats.optimizer.available == 2
assert stats.neural.available == 4
```

## Stage 2: Native Signature Engine

### Success Tests

```elixir
defmodule DSPex.SignatureTest do
  use ExUnit.Case
  import DSPex.Signatures
  
  # Compile-time signature definition
  defsignature :qa_signature, "question: str, context: str -> answer: str, confidence: float"
  
  test "signatures are parsed at compile time" do
    sig = qa_signature()
    assert sig.inputs == [
      %{name: "question", type: :string},
      %{name: "context", type: :string}
    ]
    assert sig.outputs == [
      %{name: "answer", type: :string},
      %{name: "confidence", type: :float}
    ]
  end
  
  test "invalid inputs are caught with clear errors" do
    assert {:error, msg} = validate_qa_signature(%{question: 123})
    assert msg =~ "question must be a string"
  end
  
  test "signature transformation works correctly" do
    input = %{question: "What is DSPex?", context: "DSPex is..."}
    {:ok, transformed} = transform_qa_signature(input)
    assert transformed.question == "What is DSPex?"
  end
end
```

### Working Example

```elixir
# Define complex signatures
defsignature :classification, 
  "text: str, categories: list[str] -> category: str, score: float, explanation: str"

defsignature :summarization,
  "document: str, max_length: int = 100 -> summary: str, keywords: list[str]"

# Use in production code
defmodule MyApp.Classifier do
  import DSPex.Signatures
  
  defsignature :classify, "text: str -> category: str, confidence: float"
  
  def classify_text(text) do
    with {:ok, validated} <- validate_classify(%{text: text}),
         {:ok, result} <- DSPex.execute(:classify, validated) do
      {:ok, result}
    end
  end
end
```

## Stage 3: Basic Python Bridge

### Success Tests

```elixir
defmodule DSPex.BridgeTest do
  use ExUnit.Case
  
  test "core DSPy modules are accessible" do
    # Test Predict
    {:ok, result} = DSPex.Bridge.execute("dspy.Predict", %{
      signature: "question -> answer",
      inputs: %{question: "What is 2+2?"}
    })
    assert is_binary(result["answer"])
    
    # Test ChainOfThought
    {:ok, result} = DSPex.Bridge.execute("dspy.ChainOfThought", %{
      signature: "question -> answer",
      inputs: %{question: "Why is the sky blue?"}
    })
    assert is_binary(result["reasoning"])
    assert is_binary(result["answer"])
  end
  
  test "error handling works correctly" do
    {:error, error} = DSPex.Bridge.execute("invalid.module", %{})
    assert error.type == :module_not_found
    assert error.message =~ "invalid.module"
  end
  
  test "complex data types round-trip correctly" do
    complex_data = %{
      "nested" => %{"array" => [1, 2, 3]},
      "float" => 3.14,
      "unicode" => "Hello 世界 🌍"
    }
    {:ok, result} = DSPex.Bridge.execute("echo", complex_data)
    assert result == complex_data
  end
end
```

### Working Example

```elixir
# Execute various DSPy modules
{:ok, prediction} = DSPex.execute("dspy.Predict", %{
  signature: "sentiment analysis: text -> sentiment: str, score: float",
  inputs: %{text: "I love this new framework!"}
})
# => %{"sentiment" => "positive", "score" => 0.95}

{:ok, cot_result} = DSPex.execute("dspy.ChainOfThought", %{
  signature: "math problem: question -> answer: int",
  inputs: %{question: "If I have 5 apples and buy 3 more, how many do I have?"}
})
# => %{"reasoning" => "Starting with 5 apples, adding 3 more...", "answer" => 8}

{:ok, react_result} = DSPex.execute("dspy.ReAct", %{
  signature: "research: query -> findings: str, sources: list[str]",
  inputs: %{query: "Latest developments in quantum computing"}
})
# => %{"findings" => "...", "sources" => ["arxiv...", "nature..."]}
```

## Stage 4: Intelligent Orchestration Engine

### Success Tests

```elixir
defmodule DSPex.OrchestratorTest do
  use ExUnit.Case
  
  test "orchestrator analyzes task complexity correctly" do
    analysis = DSPex.Orchestrator.analyze_task("simple_predict", %{text: "hello"})
    assert analysis.complexity == :low
    assert analysis.estimated_duration < 100
    
    analysis = DSPex.Orchestrator.analyze_task("complex_reasoning", %{
      documents: Enum.map(1..100, &"doc#{&1}"),
      analysis_depth: "comprehensive"
    })
    assert analysis.complexity == :high
    assert analysis.recommended_pool == :optimizer
  end
  
  test "orchestrator learns from execution patterns" do
    # Execute same operation multiple times
    for _ <- 1..10 do
      DSPex.execute("predict", %{text: "test"})
    end
    
    strategy = DSPex.Orchestrator.get_learned_strategy("predict", %{text: "test"})
    assert strategy.execution_mode == :native  # Should learn native is faster
    assert strategy.average_duration < 10
  end
  
  test "orchestrator handles failures with fallback" do
    # Simulate native implementation failure
    :meck.new(DSPex.Native.Predict, [:passthrough])
    :meck.expect(DSPex.Native.Predict, :execute, fn _ -> {:error, :internal_error} end)
    
    # Should fallback to Python
    {:ok, result} = DSPex.execute("predict", %{text: "test"})
    assert result["answer"] != nil
    assert DSPex.Telemetry.get_last_execution().fallback_used == true
    
    :meck.unload()
  end
end
```

### Working Example

```elixir
# Orchestrator intelligently routes based on task
task1 = %{operation: "simple_template", template: "Hello {{name}}"}
{:ok, meta1} = DSPex.execute_with_metadata(task1)
assert meta1.execution_path == :native
assert meta1.duration_ms < 1

task2 = %{operation: "complex_optimization", iterations: 1000}
{:ok, meta2} = DSPex.execute_with_metadata(task2)
assert meta2.execution_path == :python
assert meta2.pool_used == :optimizer

# Orchestrator adapts based on performance
for i <- 1..100 do
  DSPex.execute("dynamic_task", %{complexity: i})
end

# Check adaptation occurred
adaptations = DSPex.Orchestrator.get_adaptations("dynamic_task")
assert length(adaptations) > 0
assert hd(adaptations).reason == :performance_degradation
assert hd(adaptations).new_strategy.timeout_ms > 5000
```

## Stage 5: Variable Coordination System

### Success Tests

```elixir
defmodule DSPex.VariablesTest do
  use ExUnit.Case
  
  test "variables can be registered and tracked" do
    {:ok, var_id} = DSPex.Variables.register("temperature", :float, 0.7,
      constraints: [min: 0.0, max: 1.0])
    
    {:ok, var} = DSPex.Variables.get(var_id)
    assert var.name == "temperature"
    assert var.value == 0.7
    assert var.constraints.min == 0.0
  end
  
  test "multiple optimizers can coordinate" do
    {:ok, var_id} = DSPex.Variables.register("learning_rate", :float, 0.01)
    
    # Start two optimizers
    {:ok, opt1} = DSPex.Variables.optimize(var_id, DSPex.Optimizers.GridSearch)
    {:ok, opt2} = DSPex.Variables.optimize(var_id, DSPex.Optimizers.Bayesian)
    
    # Second should be queued
    assert opt2.status == :queued
    
    # When first completes, second runs
    DSPex.Variables.complete_optimization(var_id, opt1.id, 0.001)
    :timer.sleep(100)
    
    {:ok, var} = DSPex.Variables.get(var_id)
    assert var.value == 0.001
    assert var.optimizer_pid == opt2.pid
  end
  
  test "observers are notified of changes" do
    {:ok, var_id} = DSPex.Variables.register("batch_size", :integer, 32)
    
    # Register observer
    test_pid = self()
    DSPex.Variables.observe(var_id, test_pid)
    
    # Update variable
    DSPex.Variables.update(var_id, 64, :manual)
    
    # Should receive notification
    assert_receive {:variable_updated, ^var_id, 64, _metadata}, 1000
  end
end
```

### Working Example

```elixir
# Register ML hyperparameters as variables
{:ok, temp_var} = DSPex.Variables.register("temperature", :float, 0.7,
  constraints: [min: 0.0, max: 1.0, step: 0.1],
  metadata: %{affects: ["creativity", "consistency"]}
)

{:ok, token_var} = DSPex.Variables.register("max_tokens", :integer, 256,
  constraints: [min: 10, max: 2048],
  dependencies: [:model_type]
)

# Coordinate optimization across system
defmodule MyApp.MLPipeline do
  def optimize_pipeline do
    # Multiple components can optimize same variables
    DSPex.Variables.optimize(:temperature, DSPex.Optimizers.GridSearch,
      metric: :quality_score,
      trials: 10
    )
    
    DSPex.Variables.optimize(:temperature, DSPex.Optimizers.UserFeedback,
      collect_samples: 50
    )
    
    # System coordinates both optimizations
  end
end

# Check optimization history
{:ok, history} = DSPex.Variables.get_history(:temperature)
assert length(history) == 60  # 10 grid + 50 feedback
assert List.last(history).value == 0.8  # Converged value
```

## Stage 6: Adaptive LLM Architecture

### Success Tests

```elixir
defmodule DSPex.LLMTest do
  use ExUnit.Case
  
  test "adapter selection based on requirements" do
    # Structured output -> InstructorLite
    {:ok, result, meta} = DSPex.LLM.predict("Generate user", 
      schema: %{name: :string, age: :integer})
    assert meta.adapter == DSPex.LLM.Adapters.InstructorLite
    assert is_map(result)
    assert is_binary(result["name"])
    
    # Simple completion -> HTTP
    {:ok, result, meta} = DSPex.LLM.predict("Hello", max_tokens: 10)
    assert meta.adapter == DSPex.LLM.Adapters.HTTP
    assert is_binary(result)
    
    # Complex DSPy operation -> Python
    {:ok, result, meta} = DSPex.LLM.predict("Complex reasoning",
      module: "dspy.ChainOfThought")
    assert meta.adapter == DSPex.LLM.Adapters.Python
  end
  
  test "adapter fallback on failure" do
    # Simulate InstructorLite failure
    :meck.new(DSPex.LLM.Adapters.InstructorLite, [:passthrough])
    :meck.expect(DSPex.LLM.Adapters.InstructorLite, :generate, 
      fn _, _ -> {:error, :timeout} end)
    
    # Should fallback to Python
    {:ok, result, meta} = DSPex.LLM.predict("Generate data",
      schema: %{value: :string})
    assert meta.adapter == DSPex.LLM.Adapters.Python
    assert meta.fallback_reason == :instructor_timeout
    
    :meck.unload()
  end
  
  test "streaming support" do
    stream = DSPex.LLM.stream("Tell me a story", max_tokens: 100)
    
    chunks = Enum.take(stream, 5)
    assert length(chunks) == 5
    assert Enum.all?(chunks, &is_binary/1)
  end
end
```

### Working Example

```elixir
# Automatic adapter selection
defmodule MyApp.Assistant do
  # Structured extraction uses InstructorLite
  def extract_entities(text) do
    DSPex.LLM.predict(text,
      schema: %{
        entities: {:array, %{
          name: :string,
          type: {:enum, ["person", "place", "thing"]},
          confidence: :float
        }}
      }
    )
  end
  
  # Simple completion uses HTTP
  def complete_sentence(prompt) do
    DSPex.LLM.predict(prompt, 
      max_tokens: 50,
      temperature: 0.7
    )
  end
  
  # Complex reasoning uses Python DSPy
  def analyze_document(doc) do
    DSPex.LLM.predict(doc,
      module: "dspy.ChainOfThought",
      signature: "document -> summary, key_points, sentiment"
    )
  end
end

# Monitor adapter performance
stats = DSPex.LLM.get_adapter_stats()
assert stats.instructor_lite.avg_latency < 100
assert stats.http.avg_latency < 50
assert stats.python.success_rate > 0.95
```

## Stage 7: Pipeline Orchestration Engine

### Success Tests

```elixir
defmodule DSPex.PipelineTest do
  use ExUnit.Case
  
  test "pipeline with parallel execution" do
    pipeline = DSPex.Pipeline.new()
    |> DSPex.Pipeline.add_parallel([
      {:fetch_data, %{source: "api"}},
      {:fetch_data, %{source: "database"}},
      {:fetch_data, %{source: "cache"}}
    ])
    |> DSPex.Pipeline.add_stage(:merge_data)
    |> DSPex.Pipeline.add_stage(:analyze)
    
    {:ok, result} = DSPex.Pipeline.execute(pipeline, %{})
    assert map_size(result.data) == 3
    assert result.execution_time < 1000  # Parallel execution
  end
  
  test "pipeline with conditional branches" do
    pipeline = DSPex.Pipeline.new()
    |> DSPex.Pipeline.add_stage(:classify)
    |> DSPex.Pipeline.add_conditional(
      fn ctx -> ctx.classification == "urgent" end,
      :immediate_action,
      :normal_processing
    )
    
    {:ok, result1} = DSPex.Pipeline.execute(pipeline, %{text: "URGENT: System down"})
    assert result1.path_taken == :immediate_action
    
    {:ok, result2} = DSPex.Pipeline.execute(pipeline, %{text: "Regular update"})
    assert result2.path_taken == :normal_processing
  end
  
  test "pipeline streaming" do
    pipeline = DSPex.Pipeline.new()
    |> DSPex.Pipeline.add_stage(:generate_items, count: 100)
    |> DSPex.Pipeline.add_stage(:process_item)
    |> DSPex.Pipeline.add_stage(:format_output)
    
    stream = DSPex.Pipeline.stream(pipeline, %{})
    
    # Should get results as they're ready
    first_10 = Enum.take(stream, 10)
    assert length(first_10) == 10
    assert Enum.all?(first_10, &(&1.processed == true))
  end
end
```

### Working Example

```elixir
# Complex ML pipeline
defmodule MyApp.DocumentProcessor do
  def process_documents(docs) do
    DSPex.Pipeline.new()
    # Parallel preprocessing
    |> DSPex.Pipeline.add_parallel(
      Enum.map(docs, fn doc ->
        {:preprocess, %{doc_id: doc.id, text: doc.content}}
      end)
    )
    # Sequential analysis
    |> DSPex.Pipeline.add_stage(:extract_entities,
      adapter: :instructor_lite,
      schema: entity_schema()
    )
    |> DSPex.Pipeline.add_stage(:sentiment_analysis,
      module: "dspy.Predict",
      signature: "text -> sentiment, confidence"
    )
    # Conditional summarization
    |> DSPex.Pipeline.add_conditional(
      fn ctx -> length(ctx.entities) > 10 end,
      {:summarize, %{module: "dspy.ChainOfThought"}},
      {:simple_summary, %{adapter: :native}}
    )
    # Final formatting
    |> DSPex.Pipeline.add_stage(:format_results)
    |> DSPex.Pipeline.execute(%{docs: docs},
      timeout: 30_000,
      stream: true
    )
  end
end

# Monitor pipeline performance
{:ok, result, metrics} = MyApp.DocumentProcessor.process_documents(documents)
assert metrics.total_time < 5000
assert metrics.parallel_speedup > 3.5
assert metrics.stage_times.extract_entities < 1000
```

## Stage 8: Intelligent Session Management

### Success Tests

```elixir
defmodule DSPex.SessionTest do
  use ExUnit.Case
  
  test "session maintains state across operations" do
    {:ok, session} = DSPex.Sessions.create("test_session")
    
    # First operation sets context
    {:ok, _} = DSPex.Sessions.execute(session.id, :set_context, %{
      user: "Alice",
      preferences: %{style: "formal"}
    })
    
    # Second operation uses context
    {:ok, result} = DSPex.Sessions.execute(session.id, :generate_response, %{
      prompt: "Hello"
    })
    
    assert result.response =~ "formal"
    assert result.response =~ "Alice"
  end
  
  test "session tracks performance metrics" do
    {:ok, session} = DSPex.Sessions.create("perf_session")
    
    # Execute multiple operations
    for i <- 1..10 do
      DSPex.Sessions.execute(session.id, :process, %{item: i})
    end
    
    # Check metrics
    {:ok, insights} = DSPex.Sessions.get_insights(session.id)
    assert insights.total_operations == 10
    assert insights.avg_duration < 100
    assert insights.performance_trend == :stable
  end
  
  test "session cleanup after TTL" do
    {:ok, session} = DSPex.Sessions.create("temp_session", ttl: 100)
    assert DSPex.Sessions.exists?(session.id)
    
    :timer.sleep(150)
    
    assert not DSPex.Sessions.exists?(session.id)
  end
end
```

### Working Example

```elixir
# Conversational AI with session state
defmodule MyApp.ChatBot do
  def start_conversation(user_id) do
    {:ok, session} = DSPex.Sessions.create("chat_#{user_id}",
      ttl: 3600,  # 1 hour
      metadata: %{user_id: user_id}
    )
    
    # Initialize conversation context
    DSPex.Sessions.execute(session.id, :initialize_chat, %{
      system_prompt: "You are a helpful assistant",
      user_profile: fetch_user_profile(user_id)
    })
    
    session.id
  end
  
  def chat(session_id, message) do
    {:ok, response} = DSPex.Sessions.execute(session_id, :chat_turn, %{
      message: message,
      module: "dspy.ChainOfThought",
      signature: "conversation_history, user_message -> assistant_response"
    })
    
    # Session automatically maintains conversation history
    response.assistant_response
  end
  
  def get_conversation_insights(session_id) do
    {:ok, insights} = DSPex.Sessions.get_insights(session_id)
    
    %{
      message_count: insights.operations_count,
      avg_response_time: insights.avg_duration,
      topics_discussed: insights.extracted_topics,
      sentiment_trend: insights.sentiment_analysis
    }
  end
end
```

## Stage 9: Cognitive Telemetry Layer

### Success Tests

```elixir
defmodule DSPex.TelemetryTest do
  use ExUnit.Case
  
  test "telemetry detects performance patterns" do
    # Simulate degrading performance
    for i <- 1..20 do
      :meck.new(DSPex.Native.Predict, [:passthrough])
      :meck.expect(DSPex.Native.Predict, :execute, fn _ -> 
        :timer.sleep(i * 10)  # Increasing latency
        {:ok, %{}}
      end)
      
      DSPex.execute(:predict, %{})
      :meck.unload()
    end
    
    # Check pattern detection
    patterns = DSPex.Telemetry.get_patterns(:predict)
    assert :performance_degradation in patterns
    assert DSPex.Telemetry.get_trend(:predict) == :degrading
  end
  
  test "telemetry triggers adaptations" do
    # Subscribe to adaptation events
    DSPex.Telemetry.subscribe(self(), [:adaptation, :triggered])
    
    # Simulate repeated failures
    for _ <- 1..5 do
      DSPex.execute(:failing_operation, %{})
    end
    
    # Should receive adaptation trigger
    assert_receive {:adaptation_triggered, %{
      operation: :failing_operation,
      reason: :high_failure_rate,
      action: :switch_to_fallback
    }}, 1000
  end
  
  test "telemetry provides actionable insights" do
    # Execute various operations
    for _ <- 1..100, do: DSPex.execute(:fast_op, %{})
    for _ <- 1..50, do: DSPex.execute(:slow_op, %{})
    for _ <- 1..10, do: DSPex.execute(:failing_op, %{})
    
    insights = DSPex.Telemetry.get_insights()
    
    assert insights.recommendations == [
      {:cache_results, :fast_op, "High frequency, deterministic results"},
      {:increase_timeout, :slow_op, "Consistent but slow"},
      {:add_retry, :failing_op, "Intermittent failures detected"}
    ]
  end
end
```

### Working Example

```elixir
# Real-time monitoring dashboard
defmodule MyApp.Dashboard do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    # Subscribe to telemetry events
    DSPex.Telemetry.subscribe(self(), [:operation, :completed])
    DSPex.Telemetry.subscribe(self(), [:adaptation, :triggered])
    
    {:ok, assign(socket,
      operations: [],
      adaptations: [],
      performance_map: %{}
    )}
  end
  
  def handle_info({:operation_completed, event}, socket) do
    # Update real-time metrics
    {:noreply, update(socket, :operations, &([event | &1] |> Enum.take(100)))}
  end
  
  def handle_info({:adaptation_triggered, adaptation}, socket) do
    # Show adaptation in UI
    {:noreply, update(socket, :adaptations, &[adaptation | &1])}
  end
end

# Anomaly detection
defmodule MyApp.AnomalyMonitor do
  def check_system_health do
    case DSPex.Telemetry.detect_anomalies(window: :last_5_minutes) do
      [] -> 
        :ok
      anomalies ->
        Enum.each(anomalies, fn anomaly ->
          Logger.warning("Anomaly detected: #{inspect(anomaly)}")
          maybe_trigger_alert(anomaly)
        end)
    end
  end
end
```

## Stage 10: Production Reliability Features

### Success Tests

```elixir
defmodule DSPex.ReliabilityTest do
  use ExUnit.Case
  
  test "circuit breaker prevents cascade failures" do
    # Configure circuit breaker
    DSPex.CircuitBreaker.configure(:external_api,
      failure_threshold: 3,
      timeout: 1000,
      reset_timeout: 5000
    )
    
    # Simulate failures
    for _ <- 1..3 do
      {:error, _} = DSPex.execute(:external_api, %{}, timeout: 100)
    end
    
    # Circuit should be open
    {:error, :circuit_breaker_open} = DSPex.execute(:external_api, %{})
    
    # Wait for reset
    :timer.sleep(5100)
    
    # Should try again
    {:ok, _} = DSPex.execute(:external_api, %{})
  end
  
  test "request queuing handles overload" do
    # Flood system with requests
    tasks = for i <- 1..100 do
      Task.async(fn ->
        DSPex.execute(:process, %{id: i})
      end)
    end
    
    results = Task.await_many(tasks, 10_000)
    
    # All should complete
    assert length(results) == 100
    assert Enum.all?(results, fn
      {:ok, _} -> true
      {:error, :queue_timeout} -> true
      _ -> false
    end)
    
    # Check queue stats
    stats = DSPex.Queue.get_stats()
    assert stats.max_queue_depth > 0
    assert stats.rejected_count == 0  # None rejected, just queued
  end
  
  test "graceful degradation under load" do
    # Simulate high load
    DSPex.LoadSimulator.start(requests_per_second: 1000)
    :timer.sleep(1000)
    
    # System should degrade gracefully
    config = DSPex.get_current_config()
    assert config.mode == :degraded
    assert config.disabled_features == [:complex_reasoning, :optimization]
    assert config.simple_operations == :enabled
    
    DSPex.LoadSimulator.stop()
  end
end
```

### Working Example

```elixir
# Production configuration
config :dspex,
  reliability: %{
    circuit_breakers: %{
      llm_api: %{threshold: 5, timeout: 30_000},
      python_bridge: %{threshold: 3, timeout: 60_000}
    },
    retry_policies: %{
      default: %{max_attempts: 3, backoff: :exponential},
      critical: %{max_attempts: 5, backoff: {:exponential, 1000}}
    },
    queue_limits: %{
      max_queue_size: 1000,
      queue_timeout: 30_000
    },
    degradation_thresholds: %{
      cpu: 80,
      memory: 90,
      queue_depth: 500
    }
  }

# Health check endpoint
defmodule MyApp.HealthCheck do
  def check do
    %{
      status: overall_status(),
      components: %{
        pools: check_pools(),
        queues: check_queues(),
        circuit_breakers: check_circuit_breakers(),
        memory: check_memory()
      },
      metrics: %{
        uptime: DSPex.uptime(),
        requests_processed: DSPex.Stats.total_requests(),
        error_rate: DSPex.Stats.error_rate(:last_5_minutes),
        p99_latency: DSPex.Stats.percentile(:latency, 99)
      }
    }
  end
end
```

## Final Integration Test Suite

### Success Tests

```elixir
defmodule DSPex.IntegrationTest do
  use ExUnit.Case
  
  test "end-to-end cognitive orchestration" do
    # Create a complex task that exercises all components
    pipeline = DSPex.Pipeline.new()
    |> DSPex.Pipeline.add_stage(:analyze_request, %{
      module: "dspy.ChainOfThought",
      signature: "request -> intent, complexity, requirements"
    })
    |> DSPex.Pipeline.add_parallel([
      {:optimize_temperature, %{
        variable: "temperature",
        optimizer: DSPex.Optimizers.Bayesian,
        trials: 10
      }},
      {:optimize_tokens, %{
        variable: "max_tokens", 
        optimizer: DSPex.Optimizers.GridSearch,
        range: [100, 500, 1000]
      }}
    ])
    |> DSPex.Pipeline.add_stage(:generate_response, %{
      adapter: :auto,  # Let system choose
      use_optimized_variables: true
    })
    |> DSPex.Pipeline.add_stage(:validate_quality, %{
      validators: [:grammar, :coherence, :relevance]
    })
    
    # Execute in session with monitoring
    {:ok, session} = DSPex.Sessions.create("integration_test")
    
    {:ok, result, metrics} = DSPex.Sessions.execute(session.id, pipeline, %{
      request: "Explain quantum computing to a 10-year-old"
    })
    
    # Verify all components worked together
    assert result.intent == "educational_explanation"
    assert result.optimized_temperature between 0.6..0.8
    assert result.response =~ "quantum"
    assert result.quality_score > 0.8
    
    # Check cognitive features activated
    assert metrics.adaptations_made > 0
    assert metrics.learned_patterns != []
    assert metrics.optimization_improvements.temperature > 0
    
    # Verify telemetry captured everything
    events = DSPex.Telemetry.get_events(session.id)
    assert length(events) > 20
    assert Enum.any?(events, &(&1.type == :optimization_completed))
    assert Enum.any?(events, &(&1.type == :adapter_selected))
  end
end
```

### Production Example

```elixir
# Full production usage
defmodule MyApp.CognitiveAssistant do
  def process_user_request(user_id, request_text) do
    # Start session for conversation continuity
    session_id = "user_#{user_id}_#{System.unique_integer()}"
    {:ok, session} = DSPex.Sessions.create(session_id, ttl: 3600)
    
    # Build adaptive pipeline
    pipeline = DSPex.Pipeline.new()
    |> add_understanding_stage()
    |> add_optimization_stage()
    |> add_generation_stage()
    |> add_quality_stage()
    
    # Execute with full monitoring
    case DSPex.Sessions.execute(session_id, pipeline, %{
      text: request_text,
      user_context: get_user_context(user_id)
    }) do
      {:ok, result, metrics} ->
        # Log performance for learning
        log_execution(session_id, metrics)
        
        # Return enhanced response
        %{
          response: result.final_response,
          confidence: result.confidence,
          session_id: session_id,
          improvements: metrics.adaptations_made
        }
        
      {:error, reason} ->
        # Graceful error handling
        handle_error(reason, request_text)
    end
  end
  
  defp add_understanding_stage(pipeline) do
    DSPex.Pipeline.add_stage(pipeline, :understand, %{
      module: "dspy.ChainOfThought",
      signature: "user_input -> intent, entities, context_needed",
      fallback: :simple_classification
    })
  end
  
  defp add_optimization_stage(pipeline) do
    DSPex.Pipeline.add_conditional(pipeline,
      fn ctx -> ctx.intent in [:creative, :analytical] end,
      {:optimize_parameters, %{
        variables: [:temperature, :top_p, :frequency_penalty],
        metric: :response_quality,
        budget: 10  # Max optimization attempts
      }},
      :skip_optimization
    )
  end
  
  defp add_generation_stage(pipeline) do
    DSPex.Pipeline.add_stage(pipeline, :generate, %{
      adapter: :auto,
      stream: true,
      use_optimized_variables: true,
      timeout: 30_000
    })
  end
  
  defp add_quality_stage(pipeline) do
    DSPex.Pipeline.add_parallel(pipeline, [
      {:validate_factual, %{checker: :fact_validator}},
      {:validate_safety, %{checker: :safety_filter}},
      {:validate_coherence, %{checker: :coherence_scorer}}
    ])
  end
end
```

## Success Metrics Summary

Each stage is considered successful when:

1. **All unit tests pass** with >95% coverage
2. **Integration tests** demonstrate component interaction
3. **Performance benchmarks** meet targets:
   - Native operations: <1ms latency
   - Simple operations: <100ms latency
   - Complex operations: <5s latency
   - Throughput: >1000 req/s for cached operations
4. **Reliability metrics** achieved:
   - 99.9% uptime in stress tests
   - Graceful degradation under load
   - Automatic recovery from failures
5. **Cognitive features** demonstrate:
   - 20%+ performance improvement through adaptation
   - Successful pattern learning
   - Intelligent routing decisions
6. **Developer experience** validated:
   - Clean, intuitive API
   - Clear error messages
   - Comprehensive documentation

The examples provided demonstrate real-world usage patterns and validate that DSPex truly functions as a cognitive orchestration platform, not just a simple bridge.
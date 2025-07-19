# Native DSPy Features Implementation Roadmap

## Overview

This document identifies DSPy features to implement natively in Elixir, prioritized by impact and complexity. Each feature includes implementation details and benefits of native implementation.

## Feature Prioritization Matrix

| Feature | Impact | Complexity | Priority | Native Benefits |
|---------|--------|------------|----------|-----------------|
| Signatures | High | Low | P0 | Type safety, compile-time validation |
| Basic Predictors | High | Medium | P0 | Direct LLM integration, lower latency |
| Prompt Templates | High | Low | P0 | String manipulation efficiency |
| Chain-of-Thought | High | Medium | P1 | Native async/streaming |
| Few-Shot Learning | Medium | Low | P1 | Elixir pattern matching |
| Assertions | Medium | Low | P1 | Integration with Elixir testing |
| Optimizers | Medium | High | P2 | Nx integration potential |
| Advanced RAG | Medium | High | P2 | Native vector DB integration |
| Multi-hop Reasoning | Low | High | P3 | Complex state management |

## Phase 1: Core Features (P0)

### 1. Native Signatures

**Current Python Implementation:**
```python
class Signature:
    def __init__(self, signature_string):
        self.parse(signature_string)
```

**Native Elixir Implementation:**
```elixir
defmodule DSPex.Signature do
  @moduledoc """
  Native implementation of DSPy signatures with compile-time validation.
  """
  
  defstruct [:name, :docstring, :inputs, :outputs, :constraints]
  
  # Macro for compile-time signature definition
  defmacro defsignature(name, signature_string) do
    parsed = parse_at_compile_time(signature_string)
    
    quote do
      def unquote(name)() do
        %DSPex.Signature{unquote_splicing(Macro.escape(parsed))}
      end
    end
  end
  
  # Runtime parsing for dynamic signatures
  def parse(signature_string) do
    with {:ok, tokens} <- tokenize(signature_string),
         {:ok, ast} <- build_ast(tokens),
         {:ok, signature} <- validate_ast(ast) do
      {:ok, signature}
    end
  end
  
  # Pattern matching for field extraction
  def extract_field(line) do
    case Regex.run(~r/^(\w+)\s*\(([^)]+)\):\s*(.+)$/, line) do
      [_, name, type, description] ->
        %Field{name: name, type: parse_type(type), description: description}
      _ ->
        {:error, "Invalid field format"}
    end
  end
end
```

**Benefits:**
- Compile-time validation
- Native pattern matching
- Zero serialization overhead
- Direct integration with Elixir structs

### 2. Basic Predictors

**Native Implementation Plan:**
```elixir
defmodule DSPex.Predictor do
  @moduledoc """
  Behavior for LLM predictors with native Elixir implementations.
  """
  
  @callback predict(signature :: Signature.t(), inputs :: map(), opts :: keyword()) :: 
    {:ok, map()} | {:error, term()}
  
  @callback batch_predict(signature :: Signature.t(), batch :: [map()], opts :: keyword()) ::
    {:ok, [map()]} | {:error, term()}
    
  defmacro __using__(opts) do
    quote do
      @behaviour DSPex.Predictor
      
      def predict(signature, inputs, opts \\ []) do
        prompt = DSPex.PromptBuilder.build(signature, inputs, opts)
        
        with {:ok, response} <- call_llm(prompt, opts),
             {:ok, parsed} <- parse_response(response, signature) do
          {:ok, parsed}
        end
      end
      
      # Concurrent batch processing
      def batch_predict(signature, batch, opts \\ []) do
        batch
        |> Task.async_stream(&predict(signature, &1, opts), 
             max_concurrency: opts[:max_concurrency] || 10)
        |> Enum.reduce({:ok, []}, fn
          {:ok, {:ok, result}}, {:ok, acc} -> {:ok, [result | acc]}
          {:ok, {:error, reason}}, _ -> {:error, reason}
          {:error, reason}, _ -> {:error, reason}
        end)
        |> case do
          {:ok, results} -> {:ok, Enum.reverse(results)}
          error -> error
        end
      end
      
      defoverridable predict: 3, batch_predict: 3
    end
  end
end

# Example predictor implementation
defmodule DSPex.Predictors.OpenAI do
  use DSPex.Predictor
  
  defp call_llm(prompt, opts) do
    # Direct HTTP call to OpenAI
    # No Python serialization needed
  end
end
```

**Benefits:**
- Direct HTTP calls (no IPC overhead)
- Native concurrency with Task.async_stream
- Streaming support with GenStage
- Built-in rate limiting with Elixir patterns

### 3. Prompt Templates

**Native Template Engine:**
```elixir
defmodule DSPex.PromptTemplate do
  @moduledoc """
  EEx-based prompt templating with DSPy compatibility.
  """
  
  defstruct [:template, :variables, :examples]
  
  def compile(template_string) do
    # Use EEx for template compilation
    EEx.compile_string(template_string)
  end
  
  def render(template, context) do
    # Leverage Elixir's powerful string interpolation
    template
    |> apply_context(context)
    |> format_examples()
    |> optimize_whitespace()
  end
  
  # DSPy-specific formatting
  def format_field({name, value, field_def}) do
    formatted_value = case field_def.type do
      :string -> value
      :integer -> Integer.to_string(value)
      :list -> Enum.join(value, ", ")
      :json -> Jason.encode!(value)
    end
    
    "#{String.capitalize(name)}: #{formatted_value}"
  end
end
```

**Benefits:**
- EEx template compilation
- Native string manipulation
- Compile-time template validation
- Memory-efficient rendering

## Phase 2: Intermediate Features (P1)

### 4. Chain-of-Thought (CoT)

**Native Implementation:**
```elixir
defmodule DSPex.ChainOfThought do
  @moduledoc """
  Native implementation of Chain-of-Thought prompting.
  """
  
  def extend_signature(signature, opts \\ []) do
    rationale_field = %Field{
      name: "rationale",
      type: :string,
      description: "Step-by-step reasoning",
      prefix: opts[:rationale_prefix] || "Let's think step by step:"
    }
    
    %{signature | 
      outputs: [rationale_field | signature.outputs],
      metadata: Map.put(signature.metadata, :cot_enabled, true)
    }
  end
  
  def extract_rationale(response) do
    # Native regex processing
    case Regex.run(~r/Rationale:(.*?)(?=\n[A-Z]|\z)/s, response) do
      [_, rationale] -> {:ok, String.trim(rationale)}
      _ -> {:error, "No rationale found"}
    end
  end
end
```

### 5. Few-Shot Learning

**Native Implementation:**
```elixir
defmodule DSPex.FewShot do
  @moduledoc """
  Native few-shot example management and formatting.
  """
  
  defstruct [:examples, :signature, :format]
  
  def bootstrap(signature, examples, opts \\ []) do
    examples
    |> validate_examples(signature)
    |> format_examples(opts[:format] || :default)
    |> optimize_order(opts[:strategy] || :random)
  end
  
  # Leverage pattern matching for example validation
  defp validate_example(example, signature) do
    required_inputs = MapSet.new(signature.inputs)
    required_outputs = MapSet.new(signature.outputs)
    
    example_inputs = MapSet.new(Map.keys(example.inputs))
    example_outputs = MapSet.new(Map.keys(example.outputs))
    
    cond do
      not MapSet.subset?(required_inputs, example_inputs) ->
        {:error, "Missing required inputs"}
      not MapSet.subset?(required_outputs, example_outputs) ->
        {:error, "Missing required outputs"}
      true ->
        {:ok, example}
    end
  end
end
```

### 6. Assertions

**Native Implementation:**
```elixir
defmodule DSPex.Assert do
  @moduledoc """
  Native assertion system integrated with Elixir's testing.
  """
  
  defmacro assert_output(predictor_call, assertions) do
    quote do
      result = unquote(predictor_call)
      
      Enum.each(unquote(assertions), fn assertion ->
        case assertion do
          {:contains, field, expected} ->
            actual = get_in(result, [field])
            unless String.contains?(actual, expected) do
              raise "Assertion failed: #{field} should contain #{expected}"
            end
            
          {:matches, field, regex} ->
            actual = get_in(result, [field])
            unless Regex.match?(regex, actual) do
              raise "Assertion failed: #{field} should match #{inspect(regex)}"
            end
            
          {:satisfies, field, predicate} ->
            actual = get_in(result, [field])
            unless predicate.(actual) do
              raise "Assertion failed: #{field} does not satisfy predicate"
            end
        end
      end)
      
      result
    end
  end
end
```

## Phase 3: Advanced Features (P2)

### 7. Optimizers

**Integration with Nx:**
```elixir
defmodule DSPex.Optimizer do
  @moduledoc """
  Native optimizer using Nx for numerical computation.
  """
  
  import Nx.Defn
  
  defn compute_metrics(predictions, labels) do
    # Leverages Nx for efficient tensor operations
    accuracy = Nx.mean(Nx.equal(predictions, labels))
    {accuracy}
  end
  
  def optimize_prompt(signature, examples, opts \\ []) do
    # Use Elixir's GenServer for stateful optimization
    {:ok, optimizer} = OptimizerServer.start_link(signature, examples)
    
    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(opts[:max_iterations] || 10)
    |> Stream.map(fn iteration ->
      OptimizerServer.step(optimizer)
    end)
    |> Enum.to_list()
    
    OptimizerServer.get_best_prompt(optimizer)
  end
end
```

### 8. RAG (Retrieval-Augmented Generation)

**Native Vector Search Integration:**
```elixir
defmodule DSPex.RAG do
  @moduledoc """
  Native RAG implementation with Elixir vector databases.
  """
  
  def retrieve_and_generate(query, signature, opts \\ []) do
    with {:ok, embeddings} <- embed_query(query),
         {:ok, documents} <- search_similar(embeddings, opts[:top_k] || 5),
         {:ok, context} <- format_context(documents),
         {:ok, response} <- generate_with_context(query, context, signature) do
      {:ok, response}
    end
  end
  
  # Direct integration with Pgvector or other vector DBs
  defp search_similar(embeddings, top_k) do
    Ecto.Query.from(d in Document,
      order_by: fragment("embedding <-> ?", ^embeddings),
      limit: ^top_k
    )
    |> Repo.all()
  end
end
```

## Implementation Benefits Summary

### Performance Benefits
1. **Eliminated IPC Overhead**: No Python process communication
2. **Native Concurrency**: Leverage BEAM's actor model
3. **Compile-time Optimization**: Signatures and templates compiled
4. **Direct LLM Integration**: No serialization/deserialization

### Developer Experience Benefits
1. **Type Safety**: Leverage Elixir's type system
2. **Better Debugging**: Native stack traces
3. **Testing Integration**: ExUnit integration
4. **Hot Code Reloading**: No Python restart needed

### Operational Benefits
1. **Simplified Deployment**: No Python dependencies
2. **Unified Monitoring**: Single application metrics
3. **Resource Efficiency**: One runtime, not two
4. **Better Error Handling**: Elixir's fault tolerance

## Migration Priority

1. **Immediate Value** (Month 1-2):
   - Signatures
   - Basic Predictors
   - Prompt Templates

2. **Enhanced Functionality** (Month 3-4):
   - Chain-of-Thought
   - Few-Shot Learning
   - Assertions

3. **Advanced Features** (Month 5-6):
   - Optimizers (with Nx)
   - RAG Integration
   - Custom Modules

## Success Metrics

- **Performance**: 10x latency reduction for basic operations
- **Adoption**: 50% of operations using native features within 6 months
- **Reliability**: 90% reduction in Python-related errors
- **Developer Satisfaction**: Simplified API and better debugging
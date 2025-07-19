# DSPex V2 Foundation - Design Specification

## Document Information
- **Version**: 1.0.0
- **Date**: 2025-01-19
- **Status**: Draft
- **Phase**: Foundation (Initial Phase)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Application Layer                         │
│                   (User-facing Elixir API)                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      DSPex Public API                           │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐         │
│  │  Signatures  │  │   Modules    │  │   Pipelines   │         │
│  │  (Native)    │  │  (Routed)    │  │ (Orchestrator)│         │
│  └─────────────┘  └──────────────┘  └───────────────┘         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                     Execution Router                            │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐         │
│  │   Native    │  │    Python     │  │    Hybrid     │         │
│  │  Registry   │  │   Registry    │  │   Patterns    │         │
│  └─────────────┘  └──────────────┘  └───────────────┘         │
└────────┬────────────────────┬────────────────────┬─────────────┘
         │                    │                    │
┌────────▼──────────┐ ┌──────▼──────────┐ ┌──────▼──────────┐
│  Native Engine    │ │ Snakepit Bridge │ │ Pipeline Engine │
│                   │ │                 │ │                 │
│ • Signatures      │ │ • Pool Manager  │ │ • Composition   │
│ • Templates       │ │ • Session Mgmt  │ │ • Parallel Exec │
│ • Metrics         │ │ • Protocol      │ │ • Monitoring    │
│ • Validators      │ │ • Health Check  │ │ • Streaming     │
└───────────────────┘ └─────────────────┘ └─────────────────┘
                              │
                      ┌───────▼────────┐
                      │    Snakepit    │
                      │  (Python Pools) │
                      └────────────────┘
```

## Core Components

### 1. DSPex Public API

The public API provides a clean, Elixir-idiomatic interface that hides implementation details:

```elixir
defmodule DSPex do
  @moduledoc """
  Main entry point for DSPex functionality.
  Implementation details are hidden behind this unified API.
  """
  
  # Signatures - always native
  defdelegate signature(spec), to: DSPex.Native.Signature, as: :parse
  defdelegate compile_signature(string), to: DSPex.Native.Signature, as: :compile
  
  # Modules - routed based on implementation
  defdelegate predict(signature, inputs, opts \\ []), to: DSPex.Router
  defdelegate chain_of_thought(signature, opts \\ []), to: DSPex.Router
  defdelegate react(signature, tools, opts \\ []), to: DSPex.Router
  
  # Pipelines - native orchestration
  defdelegate pipeline(steps), to: DSPex.Pipeline
  defdelegate run_pipeline(pipeline, input, opts \\ []), to: DSPex.Pipeline
  
  # Utility functions
  defdelegate validate(data, signature), to: DSPex.Native.Validator
  defdelegate render_template(template, context), to: DSPex.Native.Template
end
```

### 2. Execution Router

The router intelligently directs operations to the appropriate implementation:

```elixir
defmodule DSPex.Router do
  @moduledoc """
  Routes operations to native or Python implementations.
  Maintains registries and handles fallback logic.
  """
  
  defstruct [
    :native_registry,
    :python_registry,
    :routing_strategy,
    :fallback_enabled,
    :metrics_collector
  ]
  
  # Registry entries
  @native_implementations %{
    signature: DSPex.Native.Signature,
    template: DSPex.Native.Template,
    validator: DSPex.Native.Validator,
    metrics: DSPex.Native.Metrics
  }
  
  @python_modules %{
    predict: "dspy.Predict",
    chain_of_thought: "dspy.ChainOfThought",
    react: "dspy.ReAct",
    program_of_thought: "dspy.ProgramOfThought"
  }
  
  def route(operation, args, opts \\ []) do
    start_time = System.monotonic_time()
    
    result = case routing_decision(operation, opts) do
      :native -> execute_native(operation, args)
      :python -> execute_python(operation, args)
      :hybrid -> execute_hybrid(operation, args)
    end
    
    record_metrics(operation, start_time)
    result
  end
end
```

### 3. Native Engine

High-performance native implementations for suitable operations:

```elixir
defmodule DSPex.Native do
  @moduledoc """
  Native Elixir implementations of DSPex functionality.
  """
  
  defmodule Signature do
    @moduledoc """
    Native signature parsing and validation.
    """
    
    defstruct [:name, :docstring, :inputs, :outputs, :metadata]
    
    # Type definitions
    @type field_type :: :string | :integer | :float | :boolean | 
                       {:list, field_type} | {:dict, field_type} |
                       {:optional, field_type}
    
    @type field :: %{
      name: atom(),
      type: field_type(),
      description: String.t(),
      constraints: map()
    }
    
    @type t :: %__MODULE__{
      name: String.t() | nil,
      docstring: String.t() | nil,
      inputs: [field()],
      outputs: [field()],
      metadata: map()
    }
    
    # Parse DSPy signature syntax
    def parse(spec) when is_binary(spec) do
      with {:ok, tokens} <- tokenize(spec),
           {:ok, ast} <- build_ast(tokens),
           {:ok, signature} <- transform_ast(ast) do
        {:ok, signature}
      end
    end
    
    # Compile for performance
    def compile(spec) do
      with {:ok, signature} <- parse(spec) do
        compiled = %{
          signature: signature,
          validator: build_validator(signature),
          serializer: build_serializer(signature)
        }
        {:ok, compiled}
      end
    end
  end
  
  defmodule Template do
    @moduledoc """
    EEx-based template engine for prompt generation.
    """
    
    def render(template, context) when is_binary(template) do
      EEx.eval_string(template, assigns: context)
    end
    
    def compile(template) do
      EEx.compile_string(template)
    end
  end
  
  defmodule Metrics do
    @moduledoc """
    Native metric calculations for evaluation.
    """
    
    def exact_match(prediction, ground_truth) do
      String.trim(prediction) == String.trim(ground_truth)
    end
    
    def f1_score(prediction, ground_truth) do
      pred_tokens = tokenize(prediction)
      truth_tokens = tokenize(ground_truth)
      
      precision = calculate_precision(pred_tokens, truth_tokens)
      recall = calculate_recall(pred_tokens, truth_tokens)
      
      if precision + recall == 0 do
        0.0
      else
        2 * (precision * recall) / (precision + recall)
      end
    end
  end
end
```

### 4. Snakepit Bridge

Integration layer between DSPex and Snakepit:

```elixir
defmodule DSPex.Python do
  @moduledoc """
  Snakepit-based Python integration for DSPy operations.
  """
  
  defmodule PoolManager do
    @moduledoc """
    Manages specialized Snakepit pools for different workloads.
    """
    
    use Supervisor
    
    def start_link(opts) do
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def init(_opts) do
      children = [
        # Lightweight pool for simple operations
        pool_spec(:general, 
          size: 8,
          script: "priv/python/dspy_general.py",
          max_memory: "512MB"
        ),
        
        # Heavy pool for optimization
        pool_spec(:optimizer,
          size: 2,
          script: "priv/python/dspy_optimizer.py", 
          max_memory: "4GB",
          env: %{"PYTORCH_THREADS" => "4"}
        ),
        
        # GPU pool for neural operations
        pool_spec(:neural,
          size: 4,
          script: "priv/python/dspy_neural.py",
          gpu: true,
          max_memory: "8GB"
        )
      ]
      
      Supervisor.init(children, strategy: :one_for_one)
    end
    
    defp pool_spec(name, opts) do
      config = [
        name: name,
        adapter: Snakepit.Adapters.Python,
        python_path: python_env_path(name),
        pool_size: opts[:size],
        max_memory: opts[:max_memory],
        gpu_enabled: opts[:gpu] || false,
        env: opts[:env] || %{},
        script_path: opts[:script]
      ]
      
      {Snakepit.Pool, config}
    end
  end
  
  defmodule Bridge do
    @moduledoc """
    Bridge between DSPex operations and Snakepit pools.
    """
    
    def execute(pool_name, operation, args, opts \\ []) do
      pool = get_pool(pool_name)
      
      request = build_request(operation, args, opts)
      
      case opts[:stream] do
        true -> stream_execute(pool, request)
        _ -> sync_execute(pool, request)
      end
    end
    
    defp build_request(operation, args, opts) do
      %{
        id: generate_request_id(),
        operation: operation,
        args: prepare_args(args),
        opts: prepare_opts(opts),
        timestamp: DateTime.utc_now()
      }
    end
    
    defp sync_execute(pool, request) do
      with {:ok, response} <- Snakepit.call(pool, request, timeout: 30_000) do
        handle_response(response)
      end
    end
    
    defp stream_execute(pool, request) do
      Stream.resource(
        fn -> Snakepit.stream_start(pool, request) end,
        fn stream_ref ->
          case Snakepit.stream_next(stream_ref) do
            {:chunk, data} -> {[{:chunk, data}], stream_ref}
            :done -> {:halt, stream_ref}
            {:error, reason} -> raise "Stream error: #{reason}"
          end
        end,
        fn stream_ref -> Snakepit.stream_close(stream_ref) end
      )
    end
  end
  
  defmodule Session do
    @moduledoc """
    Stateful session management for complex operations.
    """
    
    defstruct [:id, :pool, :worker_ref, :state, :created_at, :last_activity]
    
    def create(pool_name, initial_state \\ %{}) do
      session_id = UUID.uuid4()
      
      with {:ok, worker_ref} <- Snakepit.checkout_exclusive(pool_name),
           {:ok, _} <- initialize_session(worker_ref, session_id, initial_state) do
        {:ok, %__MODULE__{
          id: session_id,
          pool: pool_name,
          worker_ref: worker_ref,
          state: initial_state,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }}
      end
    end
    
    def call(session, operation, args) do
      request = %{
        session_id: session.id,
        operation: operation,
        args: args
      }
      
      with {:ok, response} <- Snakepit.call(session.worker_ref, request) do
        touch_activity(session)
        {:ok, response}
      end
    end
  end
end
```

### 5. Pipeline Engine

Orchestrates complex workflows mixing native and Python:

```elixir
defmodule DSPex.Pipeline do
  @moduledoc """
  Pipeline orchestration for complex workflows.
  """
  
  defstruct [:id, :steps, :context, :metrics, :options]
  
  @type step :: 
    {:native, module(), keyword()} |
    {:python, String.t(), keyword()} |
    {:parallel, [step()]} |
    {:conditional, condition(), step(), step()}
  
  def new(steps, opts \\ []) do
    %__MODULE__{
      id: UUID.uuid4(),
      steps: compile_steps(steps),
      context: %{},
      metrics: init_metrics(),
      options: opts
    }
  end
  
  def run(pipeline, input, opts \\ []) do
    initial_state = %{
      input: input,
      context: pipeline.context,
      results: [],
      metrics: pipeline.metrics
    }
    
    pipeline.steps
    |> execute_steps(initial_state, opts)
    |> finalize_results()
  end
  
  defp execute_steps([], state, _opts), do: state
  defp execute_steps([step | rest], state, opts) do
    case execute_step(step, state, opts) do
      {:ok, new_state} -> 
        execute_steps(rest, new_state, opts)
      {:error, reason} when opts[:continue_on_error] ->
        state = record_error(state, step, reason)
        execute_steps(rest, state, opts)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp execute_step({:native, module, step_opts}, state, _opts) do
    start_time = System.monotonic_time()
    
    result = apply(module, :execute, [state.input, step_opts])
    
    new_state = state
    |> update_results(result)
    |> record_step_metrics(module, start_time)
    
    {:ok, new_state}
  end
  
  defp execute_step({:python, module_name, step_opts}, state, _opts) do
    DSPex.Python.Bridge.execute(:general, module_name, state.input, step_opts)
  end
  
  defp execute_step({:parallel, steps}, state, opts) do
    tasks = Enum.map(steps, fn step ->
      Task.async(fn -> execute_step(step, state, opts) end)
    end)
    
    results = Task.await_many(tasks, opts[:timeout] || 30_000)
    
    merged_state = merge_parallel_results(state, results)
    {:ok, merged_state}
  end
end
```

### 6. Protocol Definitions

Communication protocols for extensibility:

```elixir
defprotocol DSPex.Serializable do
  @doc "Convert data to format suitable for Python bridge"
  def to_python(data)
  
  @doc "Convert data from Python format"
  def from_python(data)
end

defprotocol DSPex.Executable do
  @doc "Execute the operation with given inputs"
  def execute(operation, inputs, opts)
  
  @doc "Check if operation can be executed"
  def can_execute?(operation)
end
```

## Data Flow

### 1. Request Flow
```
User Request → Public API → Router → Implementation → Response
                              ↓
                     Routing Decision
                         ↙    ↓    ↘
                   Native  Python  Hybrid
```

### 2. Python Execution Flow
```
Router → Bridge → Snakepit Pool → Python Process → DSPy
                      ↓                               ↑
                  Protocol ←──────────────────────────┘
```

### 3. Pipeline Flow
```
Pipeline Definition → Compilation → Step Execution → Result Aggregation
                          ↓              ↓
                     Optimization   Parallel/Sequential
```

## Error Handling Strategy

### Error Classification
```elixir
defmodule DSPex.Errors do
  defmodule SignatureError do
    defexception [:message, :signature, :field]
  end
  
  defmodule PythonError do
    defexception [:message, :traceback, :error_type]
  end
  
  defmodule PipelineError do
    defexception [:message, :step, :accumulated_errors]
  end
  
  defmodule ConfigurationError do
    defexception [:message, :config_key, :expected, :actual]
  end
end
```

### Error Recovery
1. **Automatic Retry**: Transient failures with exponential backoff
2. **Fallback**: Try alternative implementation if available
3. **Graceful Degradation**: Return partial results when possible
4. **Circuit Breaker**: Prevent cascading failures

## Performance Optimizations

### 1. Caching Strategy
- Compiled signatures cached in ETS
- Template compilation cached
- Python module initialization cached per session
- Result caching with TTL

### 2. Pool Optimization
- Pre-warmed Python processes
- Connection pooling for LLM APIs
- Batch request aggregation
- Resource-based pool selection

### 3. Protocol Optimization
- Automatic protocol selection based on data size
- Binary protocols for large payloads
- Streaming for long responses
- Compression for network transfer

## Security Considerations

### 1. Input Validation
- All inputs validated against signatures
- Template injection prevention
- Python code execution sandboxing
- Resource limits enforcement

### 2. Process Isolation
- Python processes run with limited permissions
- Memory and CPU limits enforced
- Network access controlled
- File system access restricted

## Monitoring and Observability

### 1. Telemetry Events
```elixir
# Execution events
[:dspex, :router, :route]
[:dspex, :native, :execute]
[:dspex, :python, :execute]
[:dspex, :pipeline, :step]

# Performance events
[:dspex, :cache, :hit | :miss]
[:dspex, :pool, :checkout | :checkin]

# Error events
[:dspex, :error, :native | :python | :pipeline]
```

### 2. Metrics Collection
- Request latency histograms
- Throughput counters
- Error rate tracking
- Resource utilization

## Extension Points

### 1. Custom Native Modules
Implement the `DSPex.Native.Module` behaviour

### 2. Custom Python Bridges
Implement the `DSPex.Python.Bridge` behaviour

### 3. Custom Routers
Implement the `DSPex.Router.Strategy` behaviour

### 4. Custom Protocols
Implement the `DSPex.Protocol` behaviour
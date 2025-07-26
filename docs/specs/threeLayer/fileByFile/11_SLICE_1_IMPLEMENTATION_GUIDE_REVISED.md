# Vertical Slice 1: Basic Predict Implementation Guide

## Overview

This guide provides conversation-by-conversation instructions for implementing the Basic Predict functionality using our reconciled architecture. Each conversation focuses on a specific deliverable to maintain context and clarity.

**Prerequisites**: Stage 0 (Architectural Reconciliation) must be complete
**Estimated Time**: 2 weeks (10-15 focused conversations)
**Success Metric**: Basic predict works end-to-end with new architecture

## Conversation Breakdown

### Conversation 1: Contract Definition
**Goal**: Create and finalize `DSPex.Contracts.Predict`
**Duration**: 30-45 minutes

```elixir
# Deliverable: lib/dspex/contracts/predict.ex
defmodule DSPex.Contracts.Predict do
  use DSPex.Contract
  
  @moduledoc """
  Contract for dspy.Predict - the foundational DSPy component.
  
  This contract defines the interface between Elixir and Python
  for basic prediction functionality.
  """
  
  @python_class "dspy.Predict"
  @contract_version "1.0.0"
  @compatible_with_dspy "~> 2.1"
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string}
    ],
    returns: :reference,
    doc: "Creates a new Predict instance with the given signature"
    
  defmethod :predict, :__call__,
    params: [
      question: {:required, :string}
    ],
    returns: {:struct, DSPex.Types.Prediction},
    doc: "Executes prediction on the given question"
    
  defmethod :forward, :forward,
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.Prediction},
    doc: "Alternative prediction interface with flexible inputs"
    
  # Contract validation
  def validate_compatibility(python_version) do
    Version.match?(python_version, @compatible_with_dspy)
  end
end
```

**Key Discussion Points**:
- Parameter validation strategy
- Return type transformations
- Version compatibility approach
- Error handling philosophy

### Conversation 2: Type Definitions
**Goal**: Implement `DSPex.Types.Prediction` and related types
**Duration**: 30 minutes

```elixir
# Deliverable: lib/dspex/types/prediction.ex
defmodule DSPex.Types.Prediction do
  @moduledoc """
  Represents a prediction result from DSPy.
  
  Handles transformation from Python dict to Elixir struct
  with proper validation and type safety.
  """
  
  @type t :: %__MODULE__{
    answer: String.t(),
    confidence: float() | nil,
    reasoning: String.t() | nil,
    metadata: map(),
    raw_result: map()
  }
  
  defstruct [:answer, :confidence, :reasoning, metadata: %{}, raw_result: %{}]
  
  @doc """
  Transforms Python result to typed struct.
  Validates required fields and handles optional data.
  """
  def from_python_result(%{"answer" => answer} = result) when is_binary(answer) do
    prediction = %__MODULE__{
      answer: answer,
      confidence: extract_confidence(result),
      reasoning: Map.get(result, "reasoning"),
      metadata: extract_metadata(result),
      raw_result: result
    }
    
    {:ok, prediction}
  end
  
  def from_python_result(%{"completion" => answer} = result) when is_binary(answer) do
    # Handle alternative response format
    from_python_result(Map.put(result, "answer", answer))
  end
  
  def from_python_result(result) do
    {:error, {:invalid_prediction_format, result}}
  end
  
  defp extract_confidence(%{"confidence" => conf}) when is_number(conf), do: conf
  defp extract_confidence(_), do: nil
  
  defp extract_metadata(result) do
    result
    |> Map.drop(["answer", "confidence", "reasoning"])
    |> Map.take(["model", "temperature", "max_tokens", "prompt"])
  end
end
```

### Conversation 3: Contract Infrastructure
**Goal**: Implement core `DSPex.Contract` behavior
**Duration**: 45-60 minutes

```elixir
# Deliverable: lib/dspex/contract.ex
defmodule DSPex.Contract do
  @moduledoc """
  Defines the contract behavior for DSPy component wrappers.
  
  Contracts are explicit, version-controlled specifications
  of Python class interfaces.
  """
  
  @callback python_class() :: String.t()
  @callback contract_version() :: String.t()
  @callback __methods__() :: [{atom(), map()}]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour DSPex.Contract
      
      Module.register_attribute(__MODULE__, :methods, accumulate: true)
      @before_compile DSPex.Contract
      
      import DSPex.Contract, only: [defmethod: 4]
    end
  end
  
  defmacro defmethod(name, python_name, opts) do
    quote do
      @methods {unquote(name), %{
        python_name: unquote(python_name),
        params: unquote(opts[:params]),
        returns: unquote(opts[:returns]),
        doc: unquote(opts[:doc])
      }}
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      def __methods__, do: @methods
      
      def python_class, do: @python_class
      
      def contract_version, do: @contract_version
    end
  end
end
```

### Conversation 4: ContractBased Macro
**Goal**: Implement `DSPex.Bridge.ContractBased` macro
**Duration**: 60 minutes

```elixir
# Deliverable: lib/dspex/bridge/contract_based.ex
defmodule DSPex.Bridge.ContractBased do
  @moduledoc """
  Macro for creating type-safe wrappers from contracts.
  
  Generates functions with proper validation and error handling
  based on explicit contract definitions.
  """
  
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge.ContractBased
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :contract_based
    end
  end
  
  defmacro use_contract(contract_module) do
    quote do
      @contract_module unquote(contract_module)
      @python_class @contract_module.python_class()
      
      # Generate functions from contract
      for {method_name, method_def} <- @contract_module.__methods__() do
        DSPex.Bridge.ContractBased.__generate_method__(__MODULE__, method_name, method_def)
      end
      
      # Metadata functions
      def __contract_module__, do: @contract_module
      def __python_class__, do: @python_class
    end
  end
  
  def __generate_method__(module, method_name, method_def) do
    # This is called at compile time
    # Generate the actual function definition
    ast = build_method_ast(module, method_name, method_def)
    Module.eval_quoted(module, ast)
  end
  
  defp build_method_ast(module, method_name, method_def) do
    # Complex AST generation for typed functions
    # Handles parameter validation, type checking, result transformation
  end
end
```

### Conversation 5: Session Management
**Goal**: Implement basic session management in SnakepitGrpcBridge
**Duration**: 45 minutes

```elixir
# Deliverable: lib/snakepit_grpc_bridge/session/manager.ex
defmodule SnakepitGrpcBridge.Session.Manager do
  @moduledoc """
  Manages session lifecycle for Python bridge operations.
  
  Sessions provide isolated execution contexts with
  persistent state across multiple operations.
  """
  
  use GenServer
  require Logger
  
  @session_timeout :timer.minutes(30)
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def create_session(opts \\ %{}) do
    GenServer.call(__MODULE__, {:create_session, opts})
  end
  
  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end
  
  def close_session(session_id) do
    GenServer.cast(__MODULE__, {:close_session, session_id})
  end
  
  # Server callbacks
  
  def init(_opts) do
    # Start session cleanup timer
    Process.send_after(self(), :cleanup_expired, :timer.minutes(5))
    
    {:ok, %{
      sessions: %{},
      session_refs: %{}
    }}
  end
  
  def handle_call({:create_session, opts}, _from, state) do
    session_id = generate_session_id()
    
    session = %{
      id: session_id,
      created_at: System.system_time(:millisecond),
      last_accessed: System.system_time(:millisecond),
      metadata: opts,
      worker_pid: nil
    }
    
    # Monitor the calling process
    ref = Process.monitor(elem(_from, 0))
    
    new_state = state
      |> put_in([:sessions, session_id], session)
      |> put_in([:session_refs, ref], session_id)
    
    # Emit telemetry
    :telemetry.execute(
      [:snakepit_grpc_bridge, :session, :created],
      %{count: map_size(new_state.sessions)},
      %{session_id: session_id}
    )
    
    {:reply, {:ok, session_id}, new_state}
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
```

### Conversation 6: Basic Bridge Operations
**Goal**: Implement core bridge functions using new patterns
**Duration**: 60 minutes

```elixir
# Deliverable: lib/snakepit_grpc_bridge/bridge/core.ex
defmodule SnakepitGrpcBridge.Bridge.Core do
  @moduledoc """
  Core bridge operations for Python interaction.
  
  Implements create_instance and call_method with
  proper session management and telemetry.
  """
  
  alias SnakepitGrpcBridge.Session
  alias SnakepitGrpcBridge.Python
  
  @doc """
  Creates a Python class instance within a session.
  """
  def create_instance(python_class, args, opts \\ %{}) do
    with {:ok, session_id} <- ensure_session(opts),
         {:ok, worker} <- Session.Worker.get_or_create(session_id) do
      
      :telemetry.span(
        [:bridge, :create_instance],
        %{python_class: python_class, session_id: session_id},
        fn ->
          result = Python.Worker.create_instance(worker, python_class, args)
          {result, %{}}
        end
      )
    end
  end
  
  @doc """
  Calls a method on a Python instance.
  """
  def call_method(ref, method, args, opts \\ %{}) do
    with {:ok, session_id} <- get_session_from_ref(ref),
         {:ok, worker} <- Session.Worker.get(session_id) do
      
      :telemetry.span(
        [:bridge, :call_method],
        %{method: method, session_id: session_id},
        fn ->
          result = Python.Worker.call_method(worker, ref, method, args)
          {result, %{}}
        end
      )
    end
  end
  
  defp ensure_session(%{session_id: id}), do: {:ok, id}
  defp ensure_session(_), do: Session.Manager.create_session()
end
```

### Conversation 7: Observable Worker Implementation
**Goal**: Replace "Cognitive" worker with Observable worker
**Duration**: 45 minutes

```elixir
# Deliverable: lib/snakepit_grpc_bridge/observable/worker.ex
defmodule SnakepitGrpcBridge.Observable.Worker do
  @moduledoc """
  Worker with comprehensive observability features.
  
  Emits detailed telemetry for monitoring and optimization.
  No magic, just metrics.
  """
  
  use GenServer
  require Logger
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def execute(worker, command, args) do
    GenServer.call(worker, {:execute, command, args}, :timer.seconds(30))
  end
  
  # Callbacks
  
  def init(opts) do
    # Start Python process
    port = start_python_port(opts)
    
    # Emit startup telemetry
    :telemetry.execute(
      [:snakepit, :worker, :spawned],
      %{startup_time: System.monotonic_time()},
      %{worker_id: self(), python_version: get_python_version()}
    )
    
    {:ok, %{
      port: port,
      requests: %{},
      metrics: init_metrics()
    }}
  end
  
  def handle_call({:execute, command, args}, from, state) do
    request_id = generate_request_id()
    start_time = System.monotonic_time(:microsecond)
    
    # Track request
    state = put_in(state.requests[request_id], %{
      from: from,
      command: command,
      start_time: start_time
    })
    
    # Send to Python
    message = encode_request(request_id, command, args)
    send(state.port, {self(), {:command, message}})
    
    # Don't block - we'll reply when Python responds
    {:noreply, state}
  end
  
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case decode_response(data) do
      {:ok, request_id, result} ->
        handle_response(request_id, result, state)
        
      {:error, reason} ->
        Logger.error("Failed to decode Python response: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  defp handle_response(request_id, result, state) do
    case Map.pop(state.requests, request_id) do
      {nil, _} ->
        Logger.warn("Received response for unknown request: #{request_id}")
        {:noreply, state}
        
      {request, new_requests} ->
        # Calculate metrics
        duration = System.monotonic_time(:microsecond) - request.start_time
        
        # Emit telemetry
        :telemetry.execute(
          [:snakepit, :worker, :request, :complete],
          %{duration: duration},
          %{
            command: request.command,
            success: match?({:ok, _}, result),
            worker_id: self()
          }
        )
        
        # Reply to caller
        GenServer.reply(request.from, result)
        
        # Update state
        {:noreply, %{state | requests: new_requests}}
    end
  end
end
```

### Conversation 8: Integration Tests
**Goal**: Write comprehensive integration tests for Slice 1
**Duration**: 60 minutes

```elixir
# Deliverable: test/integration/slice_1_predict_test.exs
defmodule Integration.Slice1PredictTest do
  use ExUnit.Case, async: false
  
  alias DSPex.Contracts.Predict
  alias DSPex.Types.Prediction
  
  setup do
    # Ensure clean environment
    Application.ensure_all_started(:snakepit_grpc_bridge)
    :ok
  end
  
  describe "Basic Predict Contract" do
    test "contract defines expected methods" do
      methods = Predict.__methods__()
      
      assert {:create, %{python_name: :__init__}} = 
        Enum.find(methods, &match?({:create, _}, &1))
        
      assert {:predict, %{python_name: :__call__}} = 
        Enum.find(methods, &match?({:predict, _}, &1))
    end
    
    test "contract validates compatibility" do
      assert Predict.validate_compatibility("2.1.5")
      refute Predict.validate_compatibility("1.0.0")
    end
  end
  
  describe "End-to-End Prediction" do
    defmodule TestPredictor do
      use DSPex.Bridge.ContractBased
      use DSPex.Bridge.Observable
      
      use_contract DSPex.Contracts.Predict
      
      @impl DSPex.Bridge.Observable
      def telemetry_metadata(:create, _args) do
        %{test_run: true}
      end
    end
    
    test "creates predictor and executes prediction" do
      # Capture telemetry
      {events, result} = with_telemetry(fn ->
        # Create predictor
        {:ok, predictor} = TestPredictor.create(
          signature: "question -> answer"
        )
        
        # Execute prediction
        TestPredictor.predict(predictor, question: "What is 2+2?")
      end)
      
      # Verify result
      assert {:ok, %Prediction{} = prediction} = result
      assert prediction.answer =~ "4"
      
      # Verify telemetry
      assert_telemetry_emitted(events, [:bridge, :create_instance, :start])
      assert_telemetry_emitted(events, [:bridge, :create_instance, :stop])
      assert_telemetry_emitted(events, [:bridge, :call_method, :start])
      assert_telemetry_emitted(events, [:bridge, :call_method, :stop])
    end
    
    test "handles errors gracefully" do
      {:ok, predictor} = TestPredictor.create(signature: "test")
      
      # Invalid input
      assert {:error, {:invalid_type, :string, nil}} = 
        TestPredictor.predict(predictor, question: nil)
    end
    
    test "session persists across calls" do
      {:ok, predictor} = TestPredictor.create(signature: "qa")
      
      # Multiple predictions should reuse session
      {:ok, result1} = TestPredictor.predict(predictor, 
        question: "What is the capital of France?")
      {:ok, result2} = TestPredictor.predict(predictor, 
        question: "What is the capital of Germany?")
      
      assert result1.answer =~ "Paris"
      assert result2.answer =~ "Berlin"
      
      # Verify same session was used
      # (implementation depends on session tracking)
    end
  end
  
  defp with_telemetry(fun) do
    # Test helper to capture telemetry events
    # Implementation...
  end
end
```

### Conversation 9: Performance Benchmarks
**Goal**: Establish performance baselines
**Duration**: 30 minutes

```elixir
# Deliverable: bench/slice_1_predict_bench.exs
Benchee.run(%{
  "simple_prediction" => fn ->
    {:ok, predictor} = BenchPredictor.create(signature: "qa")
    BenchPredictor.predict(predictor, question: "What is AI?")
  end,
  
  "parallel_predictions" => fn ->
    {:ok, predictor} = BenchPredictor.create(signature: "qa")
    
    tasks = for i <- 1..10 do
      Task.async(fn ->
        BenchPredictor.predict(predictor, 
          question: "Question #{i}")
      end)
    end
    
    Task.await_many(tasks)
  end,
  
  "session_creation_overhead" => fn ->
    # Force new session each time
    {:ok, predictor} = BenchPredictor.create(
      signature: "qa",
      session_id: generate_unique_id()
    )
    BenchPredictor.predict(predictor, question: "test")
  end
})

# Expected baselines:
# - Simple prediction: < 100ms
# - Parallel predictions: < 200ms total
# - Session overhead: < 10ms
```

### Conversation 10: Documentation and Handoff
**Goal**: Complete documentation for Slice 1
**Duration**: 45 minutes

```markdown
# Deliverable: docs/vertical_slices/slice_1_complete.md

# Slice 1: Basic Predict - Implementation Summary

## Overview

Slice 1 successfully implements the foundational DSPy Predict functionality using our new contract-based architecture.

## Completed Components

### 1. Contract System
- ✅ `DSPex.Contract` behavior
- ✅ `DSPex.Contracts.Predict` implementation
- ✅ `DSPex.Bridge.ContractBased` macro

### 2. Type System  
- ✅ `DSPex.Types.Prediction` struct
- ✅ Python result transformation
- ✅ Validation and error handling

### 3. Session Management
- ✅ `SnakepitGrpcBridge.Session.Manager`
- ✅ Session lifecycle handling
- ✅ Process monitoring

### 4. Observable Infrastructure
- ✅ Comprehensive telemetry
- ✅ Performance metrics
- ✅ Error tracking

## Performance Metrics

| Operation | Target | Actual | Status |
|-----------|--------|--------|--------|
| Simple Prediction | < 100ms | 87ms | ✅ |
| Parallel (10) | < 200ms | 156ms | ✅ |
| Session Overhead | < 10ms | 7ms | ✅ |

## API Example

```elixir
defmodule MyApp.Predictor do
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Observable
  
  use_contract DSPex.Contracts.Predict
end

# Usage
{:ok, predictor} = MyApp.Predictor.create(signature: "question -> answer")
{:ok, result} = MyApp.Predictor.predict(predictor, question: "What is 2+2?")
IO.puts(result.answer) # "4"
```

## Lessons Learned

1. **Contract validation at compile time catches many errors**
2. **Telemetry from the start provides immediate insights**
3. **Session management adds ~7ms overhead but enables stateful operations**
4. **Type transformation layer prevents runtime surprises**

## Next Steps

Ready for Slice 2: Session Variables
- Build on session infrastructure
- Add variable storage
- Enable cross-request state
```

## Success Validation Checklist

### Code Quality
- [ ] All modules < 200 lines
- [ ] 100% @doc coverage
- [ ] No compiler warnings
- [ ] Dialyzer passes

### Functionality
- [ ] Basic predict works end-to-end
- [ ] Errors handled gracefully
- [ ] Sessions managed properly
- [ ] Telemetry emitted correctly

### Performance
- [ ] Meets latency targets
- [ ] No memory leaks
- [ ] Handles concurrent requests

### Integration
- [ ] Works with existing DSPex code
- [ ] Python bridge stable
- [ ] Tests comprehensive

## Summary

This implementation guide breaks down Slice 1 into manageable conversations, each with a clear deliverable. The focus on contracts, types, and observability from the start ensures we build on a solid foundation.

The modular approach allows for parallel work where possible and maintains clear boundaries between components. Each conversation builds on the previous ones, gradually constructing the complete Basic Predict functionality.
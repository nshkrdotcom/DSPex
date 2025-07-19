# DSPex Core Components - Detailed Design

## Overview

This document provides detailed design specifications for each core component of DSPex, focusing on practical implementation while maintaining the vision of cognitive orchestration.

## Component 1: Cognitive Orchestration Engine

### Purpose
The Orchestrator is the intelligent brain that analyzes tasks, selects strategies, and coordinates execution across the system.

### Key Responsibilities
- Task analysis and requirements extraction
- Execution strategy selection
- Work distribution and coordination
- Real-time monitoring and adaptation
- Failure handling and recovery

### Implementation Design

```elixir
defmodule DSPex.Orchestrator do
  use GenServer
  require Logger
  
  defstruct [
    :strategy_cache,      # ETS table for learned strategies
    :performance_history, # Recent performance metrics
    :active_executions,   # Currently running tasks
    :adaptation_rules     # Rules for dynamic adaptation
  ]
  
  # Public API
  def execute(operation, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute, operation, args, opts})
  end
  
  # Callbacks
  def handle_call({:execute, operation, args, opts}, from, state) do
    # 1. Analyze the operation
    analysis = analyze_operation(operation, args, opts)
    
    # 2. Select execution strategy based on analysis and history
    strategy = select_strategy(analysis, state.strategy_cache)
    
    # 3. Create execution plan
    plan = create_execution_plan(strategy, operation, args)
    
    # 4. Execute with monitoring
    task = Task.Supervisor.async(DSPex.TaskSupervisor, fn ->
      execute_with_monitoring(plan, state)
    end)
    
    # 5. Track execution
    state = track_execution(task, from, state)
    
    {:noreply, state}
  end
  
  defp analyze_operation(operation, args, opts) do
    %{
      type: categorize_operation(operation),
      complexity: estimate_complexity(operation, args),
      resource_requirements: estimate_resources(operation, args),
      has_native?: DSPex.Router.has_native?(operation),
      has_python?: DSPex.Router.has_python?(operation),
      priority: Keyword.get(opts, :priority, :normal)
    }
  end
  
  defp select_strategy(analysis, cache) do
    # Check cache for similar operations
    case lookup_cached_strategy(analysis, cache) do
      {:ok, strategy} -> 
        maybe_adapt_strategy(strategy, analysis)
      :miss ->
        create_new_strategy(analysis)
    end
  end
end
```

### Strategy Selection Algorithm

```elixir
defmodule DSPex.Orchestrator.Strategy do
  defstruct [
    :execution_mode,      # :native, :python, :hybrid
    :parallelism_level,   # 1..N
    :timeout_ms,          # Dynamic timeout
    :retry_policy,        # Retry configuration
    :fallback_chain,      # Fallback strategies
    :monitoring_level     # :basic, :detailed, :trace
  ]
  
  def create_new_strategy(analysis) do
    %__MODULE__{
      execution_mode: select_execution_mode(analysis),
      parallelism_level: calculate_parallelism(analysis),
      timeout_ms: calculate_timeout(analysis),
      retry_policy: determine_retry_policy(analysis),
      fallback_chain: build_fallback_chain(analysis),
      monitoring_level: determine_monitoring_level(analysis)
    }
  end
  
  defp select_execution_mode(%{has_native?: true, complexity: :low}), 
    do: :native
  defp select_execution_mode(%{has_native?: false}), 
    do: :python
  defp select_execution_mode(%{has_native?: true, has_python?: true}), 
    do: :hybrid
end
```

## Component 2: Variable Coordination System

### Purpose
Transform DSPy parameters into system-wide coordination points that can be optimized by any component.

### Key Features
- Distributed variable registry
- Optimization coordination
- Dependency tracking
- Historical learning

### Implementation Design

```elixir
defmodule DSPex.Variables do
  use GenServer
  
  defmodule Variable do
    defstruct [
      :id,
      :name,
      :type,
      :value,
      :constraints,
      :dependencies,
      :observers,
      :optimizer_pid,
      :optimization_history,
      :metadata,
      :lock_version
    ]
  end
  
  # Public API
  def register(name, type, initial_value, opts \\ []) do
    GenServer.call(__MODULE__, {:register, name, type, initial_value, opts})
  end
  
  def optimize(variable_id, optimizer_module, opts \\ []) do
    GenServer.call(__MODULE__, {:optimize, variable_id, optimizer_module, opts})
  end
  
  def observe(variable_id, observer_pid) do
    GenServer.cast(__MODULE__, {:observe, variable_id, observer_pid})
  end
  
  def update(variable_id, new_value, optimizer_pid) do
    GenServer.call(__MODULE__, {:update, variable_id, new_value, optimizer_pid})
  end
  
  # Callbacks
  def handle_call({:register, name, type, initial_value, opts}, _from, state) do
    variable = %Variable{
      id: generate_id(),
      name: name,
      type: type,
      value: initial_value,
      constraints: Keyword.get(opts, :constraints, []),
      dependencies: Keyword.get(opts, :dependencies, []),
      observers: [],
      optimization_history: [],
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    state = store_variable(state, variable)
    notify_observers(variable, :registered)
    
    {:reply, {:ok, variable.id}, state}
  end
  
  def handle_call({:optimize, variable_id, optimizer_module, opts}, from, state) do
    case get_variable(state, variable_id) do
      {:ok, variable} ->
        if variable.optimizer_pid == nil do
          # Start optimization
          task = Task.Supervisor.async(DSPex.TaskSupervisor, fn ->
            optimizer_module.optimize(variable, opts)
          end)
          
          variable = %{variable | optimizer_pid: task.pid}
          state = update_variable(state, variable)
          
          {:reply, {:ok, task}, state}
        else
          {:reply, {:error, :already_optimizing}, state}
        end
      
      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end
end
```

### Variable Types

```elixir
defmodule DSPex.Variables.Types do
  # Define variable type behaviors
  defmodule Type do
    @callback validate(value :: any()) :: :ok | {:error, reason :: String.t()}
    @callback cast(value :: any()) :: {:ok, any()} | {:error, reason :: String.t()}
    @callback constraints() :: list()
  end
  
  defmodule FloatType do
    @behaviour Type
    
    def validate(value) when is_float(value), do: :ok
    def validate(value) when is_integer(value), do: :ok
    def validate(_), do: {:error, "must be a number"}
    
    def cast(value) when is_number(value), do: {:ok, float(value)}
    def cast(_), do: {:error, "cannot cast to float"}
    
    def constraints, do: [:min, :max, :step]
  end
  
  defmodule ChoiceType do
    @behaviour Type
    
    def validate(value, choices) when value in choices, do: :ok
    def validate(_, _), do: {:error, "must be one of the allowed choices"}
    
    def cast(value), do: {:ok, value}
    
    def constraints, do: [:choices]
  end
end
```

## Component 3: Native Signature Engine

### Purpose
Provide compile-time parsing and validation of DSPy signatures with zero runtime overhead.

### Implementation Design

```elixir
defmodule DSPex.Signatures do
  defmacro defsignature(name, spec) do
    # Parse at compile time
    {:ok, parsed} = DSPex.Signatures.Parser.parse(spec)
    
    # Generate efficient code
    quote do
      def unquote(name)() do
        unquote(Macro.escape(parsed))
      end
      
      def unquote(:"validate_#{name}")(input) do
        DSPex.Signatures.Validator.validate(unquote(Macro.escape(parsed)), input)
      end
      
      def unquote(:"transform_#{name}")(input) do
        DSPex.Signatures.Transformer.transform(unquote(Macro.escape(parsed)), input)
      end
    end
  end
end

defmodule DSPex.Signatures.Parser do
  # Parses DSPy signature syntax at compile time
  def parse(spec) when is_binary(spec) do
    spec
    |> tokenize()
    |> parse_tokens()
    |> build_signature()
  end
  
  defp tokenize(spec) do
    # Tokenize "question: str, context: str -> answer: str, confidence: float"
    Regex.scan(~r/(\w+):\s*(\w+(?:\[[\w,\s]+\])?)/, spec)
    |> Enum.map(fn [_, name, type] -> {name, parse_type(type)} end)
  end
  
  defp parse_type("str"), do: :string
  defp parse_type("int"), do: :integer
  defp parse_type("float"), do: :float
  defp parse_type("bool"), do: :boolean
  defp parse_type("list[" <> rest) do
    inner = String.trim_trailing(rest, "]")
    {:list, parse_type(inner)}
  end
  defp parse_type("dict"), do: :map
  defp parse_type(other), do: {:custom, other}
end
```

### Signature Validator

```elixir
defmodule DSPex.Signatures.Validator do
  def validate(signature, input) do
    # Validate input against signature
    with :ok <- validate_required_fields(signature, input),
         :ok <- validate_types(signature, input),
         :ok <- validate_constraints(signature, input) do
      :ok
    end
  end
  
  defp validate_required_fields(signature, input) do
    required = signature.inputs |> Enum.map(&(&1.name))
    provided = Map.keys(input)
    
    missing = required -- provided
    if missing == [] do
      :ok
    else
      {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end
  
  defp validate_types(signature, input) do
    Enum.reduce_while(signature.inputs, :ok, fn field, _acc ->
      case validate_field_type(field, Map.get(input, field.name)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
```

## Component 4: Adaptive LLM Architecture

### Purpose
Provide flexible LLM integration with automatic adapter selection based on requirements.

### Implementation Design

```elixir
defmodule DSPex.LLM do
  @behaviour DSPex.LLM.Adapter
  
  defmodule AdapterRegistry do
    use GenServer
    
    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end
    
    def register(name, module, capabilities) do
      GenServer.call(__MODULE__, {:register, name, module, capabilities})
    end
    
    def select_adapter(requirements) do
      GenServer.call(__MODULE__, {:select, requirements})
    end
  end
  
  # Main LLM interface
  def predict(prompt, opts \\ []) do
    # Analyze requirements
    requirements = analyze_requirements(prompt, opts)
    
    # Select optimal adapter
    {:ok, adapter} = AdapterRegistry.select_adapter(requirements)
    
    # Execute with telemetry
    :telemetry.span(
      [:dspex, :llm, :predict],
      %{adapter: adapter},
      fn ->
        result = adapter.generate(prompt, opts)
        {result, %{adapter: adapter, prompt_size: byte_size(prompt)}}
      end
    )
  end
  
  defp analyze_requirements(prompt, opts) do
    %{
      structured_output: Keyword.get(opts, :structured, false),
      streaming: Keyword.get(opts, :stream, false),
      max_tokens: Keyword.get(opts, :max_tokens, 2048),
      complexity: estimate_complexity(prompt),
      latency_requirement: Keyword.get(opts, :max_latency, :normal)
    }
  end
end

# Example adapter implementation
defmodule DSPex.LLM.Adapters.InstructorLite do
  @behaviour DSPex.LLM.Adapter
  
  def capabilities do
    %{
      structured_output: true,
      streaming: false,
      max_throughput: :high,
      latency: :low
    }
  end
  
  def generate(prompt, opts) do
    schema = Keyword.get(opts, :schema)
    
    InstructorLite.instruct(
      model: Keyword.get(opts, :model, "gpt-3.5-turbo"),
      messages: [%{role: "user", content: prompt}],
      response_model: schema,
      max_tokens: Keyword.get(opts, :max_tokens, 2048)
    )
  end
end
```

## Component 5: Pipeline Orchestration Engine

### Purpose
Orchestrate complex workflows with automatic parallelization and fault tolerance.

### Implementation Design

```elixir
defmodule DSPex.Pipeline do
  use GenServer
  
  defmodule Stage do
    defstruct [
      :id,
      :type,           # :sequential, :parallel, :conditional
      :operations,     # List of operations to execute
      :dependencies,   # IDs of stages that must complete first
      :error_handler,  # Function to handle errors
      :timeout_ms
    ]
  end
  
  def execute(pipeline_def, input, opts \\ []) do
    # Create execution context
    context = %{
      input: input,
      pipeline: compile_pipeline(pipeline_def),
      opts: opts,
      results: %{},
      telemetry_ref: make_ref()
    }
    
    # Start execution
    GenServer.call(__MODULE__, {:execute, context}, :infinity)
  end
  
  # Compile pipeline definition into executable stages
  defp compile_pipeline(pipeline_def) do
    pipeline_def
    |> analyze_dependencies()
    |> create_stages()
    |> optimize_execution_order()
  end
  
  # Execute stages respecting dependencies
  def handle_call({:execute, context}, from, state) do
    # Start telemetry span
    :telemetry.start([:dspex, :pipeline, :execution], %{}, %{
      pipeline_id: context.pipeline.id,
      stage_count: length(context.pipeline.stages)
    })
    
    # Execute stages
    Task.start(fn ->
      result = execute_stages(context)
      GenServer.reply(from, result)
    end)
    
    {:noreply, state}
  end
  
  defp execute_stages(context) do
    # Group stages by dependency level
    stages_by_level = group_by_dependency_level(context.pipeline.stages)
    
    # Execute each level
    Enum.reduce_while(stages_by_level, context, fn stage_group, ctx ->
      case execute_stage_group(stage_group, ctx) do
        {:ok, new_ctx} -> {:cont, new_ctx}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  defp execute_stage_group(stages, context) when length(stages) == 1 do
    # Sequential execution
    [stage] = stages
    execute_single_stage(stage, context)
  end
  
  defp execute_stage_group(stages, context) do
    # Parallel execution
    tasks = Enum.map(stages, fn stage ->
      Task.async(fn -> execute_single_stage(stage, context) end)
    end)
    
    # Wait for all with timeout
    timeout = calculate_group_timeout(stages)
    
    case Task.yield_many(tasks, timeout) do
      results when all_successful?(results) ->
        {:ok, merge_results(context, results)}
      _ ->
        {:error, :stage_execution_failed}
    end
  end
end
```

## Component 6: Intelligent Session Management

### Purpose
Provide stateful execution contexts that learn from interactions.

### Implementation Design

```elixir
defmodule DSPex.Sessions do
  use GenServer
  
  defmodule Session do
    defstruct [
      :id,
      :created_at,
      :last_accessed,
      :state,
      :execution_history,
      :performance_metrics,
      :optimization_state,
      :worker_affinity,
      :learning_data
    ]
    
    def new(id) do
      %__MODULE__{
        id: id,
        created_at: DateTime.utc_now(),
        last_accessed: DateTime.utc_now(),
        state: %{},
        execution_history: [],
        performance_metrics: %{},
        optimization_state: %{},
        learning_data: %{}
      }
    end
  end
  
  # Public API
  def create(session_id) do
    GenServer.call(__MODULE__, {:create, session_id})
  end
  
  def execute_in_session(session_id, operation, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute, session_id, operation, args, opts})
  end
  
  def get_learning_insights(session_id) do
    GenServer.call(__MODULE__, {:get_insights, session_id})
  end
  
  # Implementation
  def handle_call({:execute, session_id, operation, args, opts}, from, state) do
    case get_session(state, session_id) do
      {:ok, session} ->
        # Update last accessed
        session = %{session | last_accessed: DateTime.utc_now()}
        
        # Check worker affinity
        worker = select_worker_with_affinity(session)
        
        # Execute with session context
        Task.start(fn ->
          result = execute_with_session_context(
            worker, 
            operation, 
            args, 
            session,
            opts
          )
          
          # Update session with results
          updated_session = update_session_from_execution(session, result)
          
          # Learn from execution
          learning_data = extract_learning_data(updated_session, result)
          
          GenServer.reply(from, result)
          GenServer.cast(__MODULE__, {:update_session, updated_session, learning_data})
        end)
        
        {:noreply, state}
        
      :error ->
        {:reply, {:error, :session_not_found}, state}
    end
  end
  
  defp extract_learning_data(session, result) do
    %{
      pattern: categorize_execution_pattern(session.execution_history),
      performance_trend: analyze_performance_trend(session.performance_metrics),
      optimization_effectiveness: measure_optimization_impact(session),
      resource_usage: result.metadata.resource_usage
    }
  end
end
```

## Component 7: Cognitive Telemetry Layer

### Purpose
Monitor system behavior and trigger adaptations based on patterns.

### Implementation Design

```elixir
defmodule DSPex.Telemetry do
  use GenServer
  
  defmodule Analyzer do
    defstruct [
      :window_size,
      :metrics_buffer,
      :patterns,
      :adaptation_rules,
      :triggers
    ]
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Attach to all DSPex telemetry events
    attach_handlers()
    
    state = %{
      analyzer: %Analyzer{
        window_size: 1000,
        metrics_buffer: :queue.new(),
        patterns: %{},
        adaptation_rules: load_adaptation_rules(),
        triggers: []
      }
    }
    
    {:ok, state}
  end
  
  defp attach_handlers do
    events = [
      [:dspex, :orchestrator, :execute],
      [:dspex, :llm, :predict],
      [:dspex, :pipeline, :stage],
      [:dspex, :variable, :optimize],
      [:dspex, :session, :execute]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "#{__MODULE__}-#{Enum.join(event, "-")}",
        event,
        &handle_event/4,
        nil
      )
    end)
  end
  
  def handle_event(event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:analyze, event, measurements, metadata})
  end
  
  def handle_cast({:analyze, event, measurements, metadata}, state) do
    # Add to metrics buffer
    metric = %{
      event: event,
      measurements: measurements,
      metadata: metadata,
      timestamp: System.monotonic_time()
    }
    
    state = update_metrics_buffer(state, metric)
    
    # Analyze patterns
    patterns = detect_patterns(state.analyzer.metrics_buffer)
    
    # Check adaptation rules
    adaptations = check_adaptation_rules(patterns, state.analyzer.adaptation_rules)
    
    # Trigger adaptations if needed
    Enum.each(adaptations, &trigger_adaptation/1)
    
    {:noreply, %{state | analyzer: %{state.analyzer | patterns: patterns}}}
  end
  
  defp detect_patterns(metrics_buffer) do
    %{
      performance_trend: analyze_performance_trend(metrics_buffer),
      error_patterns: detect_error_patterns(metrics_buffer),
      resource_usage: analyze_resource_usage(metrics_buffer),
      bottlenecks: identify_bottlenecks(metrics_buffer)
    }
  end
  
  defp trigger_adaptation(%{type: :performance_degradation, target: target, action: action}) do
    Logger.info("Triggering adaptation: #{action} for #{target}")
    DSPex.Orchestrator.adapt(target, action)
  end
end
```

## Integration Example

Here's how all components work together:

```elixir
# 1. Define a signature
DSPex.Signatures.defsignature(:qa_signature, 
  "question: str, context: str -> answer: str, confidence: float")

# 2. Create a pipeline with variables
pipeline = DSPex.Pipeline.new()
|> DSPex.Pipeline.add_stage(:predict, %{
  module: DSPex.Modules.ChainOfThought,
  signature: :qa_signature,
  variables: [
    {:temperature, :float, 0.7, constraints: [min: 0.0, max: 1.0]},
    {:max_tokens, :integer, 256, constraints: [min: 1, max: 2048]}
  ]
})

# 3. Execute in a session with orchestration
{:ok, session} = DSPex.Sessions.create("user_123")

result = DSPex.execute_in_session(session, pipeline, %{
  question: "What is DSPex?",
  context: "DSPex is a cognitive orchestration platform..."
})

# 4. The orchestrator:
#    - Analyzes the task
#    - Selects execution strategy
#    - Routes to appropriate components
#    - Monitors execution
#    - Adapts based on performance

# 5. Variables can be optimized
DSPex.Variables.optimize(:temperature, DSPex.Optimizers.GridSearch, 
  range: {0.1, 1.0}, 
  step: 0.1,
  metric: :answer_quality
)

# 6. Telemetry analyzes patterns and triggers adaptations
# 7. Sessions learn from interactions for future improvements
```

## Summary

These core components work together to create a cognitive orchestration platform that:
- Intelligently routes and executes DSPy operations
- Learns from execution patterns
- Adapts strategies in real-time
- Provides production-grade reliability
- Enables new patterns beyond standard DSPy

The key is that each component is focused and composable, avoiding overengineering while enabling sophisticated orchestration capabilities.
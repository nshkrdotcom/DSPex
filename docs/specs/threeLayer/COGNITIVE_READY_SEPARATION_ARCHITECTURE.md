# Cognitive-Ready Separation Architecture

## Executive Summary

This document outlines the separation of current DSPy bridge functionality into a **cognitive-ready architecture** that can evolve into the revolutionary cognitive framework later, while initially just containing our existing functionality in the proper structure.

**Core Strategy**: Build the revolutionary structure now, populate it with current functionality, enable future cognitive evolution.

## Current State → Cognitive-Ready Architecture

### What We're Actually Building Now

**Snakepit Core**: Pure infrastructure (pooling, sessions, adapters) - stays minimal
**SnakepitGrpcBridge**: All current DSPy functionality moved into cognitive-ready structure

### Future Evolution Path

The architecture is designed so that when we're ready for cognitive features, we simply:
1. Enable feature flags 
2. Replace placeholder implementations with real cognitive algorithms
3. Activate learning and optimization systems

No architectural changes needed - just implementation upgrades.

## Target Architecture

### Snakepit Core (Pure Infrastructure)
```
snakepit/
├── lib/snakepit.ex                    # Core public API
├── lib/snakepit/
│   ├── pool/                          # Process pooling (current logic)
│   ├── session_helpers.ex             # Session management (current logic)  
│   └── adapter.ex                     # Adapter behavior definition
├── test/
└── README.md
```

**Responsibilities**: 
- Worker process management
- Session affinity
- Adapter pattern for bridges
- Performance monitoring infrastructure

### SnakepitGrpcBridge (Cognitive-Ready Structure)
```
snakepit_grpc_bridge/
├── lib/snakepit_grpc_bridge.ex        # Main bridge API
├── lib/snakepit_grpc_bridge/
│   ├── adapter.ex                     # Snakepit adapter implementation
│   ├── cognitive/                     # COGNITIVE-READY STRUCTURE
│   │   ├── worker.ex                  # Enhanced worker (current logic + hooks)
│   │   ├── scheduler.ex               # Enhanced scheduler (current routing + telemetry)
│   │   ├── evolution.ex               # Implementation selection (rule-based now, ML later)
│   │   └── collaboration.ex           # Single worker now, multi-worker later
│   ├── schema/                        # COGNITIVE-READY STRUCTURE  
│   │   ├── dspy.ex                    # Current DSPy schema discovery
│   │   ├── universal.ex               # Framework abstraction (DSPy only now)
│   │   └── optimization.ex            # Schema optimization (caching now, ML later)
│   ├── codegen/                       # COGNITIVE-READY STRUCTURE
│   │   ├── dspy.ex                    # Current defdsyp macro + telemetry hooks
│   │   ├── intelligent.ex             # Placeholder for AI-powered generation
│   │   └── optimization.ex            # Usage tracking (foundation for optimization)
│   └── bridge/                        # Current bridge functionality
│       ├── variables.ex               # Current variables (moved from DSPex)
│       ├── context.ex                 # Current context (moved from DSPex)
│       └── tools.ex                   # Current tools (moved from DSPex)
├── priv/python/                       # Current Python bridge code
├── grpc/                              # Current gRPC definitions  
└── test/
```

## Detailed Module Design

### SnakepitGrpcBridge.Cognitive.Worker
```elixir
defmodule SnakepitGrpcBridge.Cognitive.Worker do
  @moduledoc """
  Enhanced worker with cognitive-ready structure.
  
  CURRENT: Same worker logic as today + telemetry collection
  FUTURE: Add learning algorithms, task specialization, collaboration
  """
  
  use GenServer
  
  defstruct [
    # Current worker fields (implementation now)
    :pid,
    :adapter, 
    :session_store,
    :health_status,
    
    # Cognitive-ready fields (telemetry collection now, learning later)
    :telemetry_collector,
    :performance_history,
    :task_metadata_cache,
    
    # Future cognitive fields (placeholders now)
    :learning_state,           # nil now, learning algorithms later
    :specialization_profile,   # nil now, task specialization later  
    :collaboration_network,    # nil now, worker network later
    :optimization_engine       # nil now, performance optimization later
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  def init(opts) do
    # Current worker initialization + telemetry setup
    state = %__MODULE__{
      adapter: opts[:adapter],
      session_store: :ets.new(:sessions, [:set, :private]),
      health_status: :healthy,
      
      # Telemetry collection (foundation for future learning)
      telemetry_collector: TelemetryCollector.new(),
      performance_history: CircularBuffer.new(1000),
      task_metadata_cache: %{}
    }
    
    # Current adapter initialization logic
    case initialize_adapter(state.adapter) do
      {:ok, adapter_state} ->
        {:ok, %{state | adapter: adapter_state}}
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  def execute_task(worker, task, context) do
    start_time = System.monotonic_time(:microsecond)
    
    # Current execution logic (unchanged)
    result = GenServer.call(worker, {:execute, task, context})
    
    # Collect telemetry for future cognitive use
    duration = System.monotonic_time(:microsecond) - start_time
    collect_execution_telemetry(worker, task, result, duration, context)
    
    result
  end
  
  # Current GenServer implementation (same as today)
  def handle_call({:execute, task, context}, _from, state) do
    result = execute_adapter_task(state.adapter, task, context)
    {:reply, result, state}
  end
  
  # Telemetry collection (foundation for future learning)
  defp collect_execution_telemetry(worker, task, result, duration, context) do
    telemetry_data = %{
      task_type: task.type,
      execution_duration: duration,
      result_success: match?({:ok, _}, result),
      timestamp: DateTime.utc_now()
    }
    
    GenServer.cast(worker, {:collect_telemetry, telemetry_data})
  end
  
  # Current implementation (moved from existing worker)
  defp initialize_adapter(adapter_config), do: # ... current logic
  defp execute_adapter_task(adapter, task, context), do: # ... current logic
end
```

### SnakepitGrpcBridge.Cognitive.Evolution
```elixir
defmodule SnakepitGrpcBridge.Cognitive.Evolution do
  @moduledoc """
  Implementation selection engine with cognitive-ready structure.
  
  CURRENT: Simple rule-based selection + telemetry collection
  FUTURE: ML-powered evolutionary selection
  """
  
  use GenServer
  
  defstruct [
    # Current selection state
    :implementation_strategies,
    :current_strategy, 
    :selection_history,
    
    # Cognitive-ready infrastructure (telemetry now, ML later)
    :performance_tracker,
    :selection_telemetry,
    
    # Future cognitive capabilities (placeholders)
    :evolution_algorithm,      # nil now, genetic algorithms later
    :performance_predictor,    # nil now, ML prediction later
    :a_b_testing_engine       # nil now, automated A/B testing later
  ]
  
  def select_implementation(signature, context, available_implementations) do
    GenServer.call(__MODULE__, {:select_implementation, signature, context, available_implementations})
  end
  
  def handle_call({:select_implementation, signature, context, available_implementations}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Current: Simple rule-based selection (exactly what we do today)
    selected_implementation = select_implementation_current(signature, context, available_implementations)
    
    # Collect telemetry for future ML training
    selection_record = %{
      signature: signature,
      context: context,
      available_implementations: available_implementations,
      selected_implementation: selected_implementation,
      selection_method: :rule_based,  # Future: :ml_powered
      timestamp: DateTime.utc_now(),
      selection_duration: System.monotonic_time(:microsecond) - start_time
    }
    
    # Store for future learning (foundation for ML)
    updated_state = record_selection(state, selection_record)
    
    {:reply, {:ok, selected_implementation}, updated_state}
  end
  
  # Current selection logic (exactly what we do today)
  defp select_implementation_current(signature, context, available_implementations) do
    # Current heuristics (same as today)
    complexity_score = String.length(signature) / 100.0
    
    cond do
      complexity_score < 0.3 and :native_elixir in available_implementations ->
        :native_elixir
      :python_dspy in available_implementations ->
        :python_dspy  
      true ->
        List.first(available_implementations) || :default
    end
  end
  
  # Future: ML-powered selection (placeholder)
  defp select_implementation_intelligent(_signature, _context, _available_implementations, _ml_models) do
    # Future: Use ML models trained on selection_history
    :not_implemented_yet
  end
  
  # Store selections for future ML training
  defp record_selection(state, selection_record) do
    updated_history = CircularBuffer.push(state.selection_history, selection_record)
    TelemetryCollector.record(state.selection_telemetry, selection_record)
    %{state | selection_history: updated_history}
  end
end
```

### SnakepitGrpcBridge.Schema.DSPy
```elixir
defmodule SnakepitGrpcBridge.Schema.DSPy do
  @moduledoc """
  Enhanced DSPy schema discovery with cognitive-ready structure.
  
  CURRENT: Current schema discovery + caching + telemetry
  FUTURE: Advanced schema analysis and runtime optimization
  """
  
  def discover_schema(module_path \\ "dspy", opts \\ []) do
    cache_key = {module_path, opts}
    
    case get_cached_schema(cache_key) do
      {:ok, cached_schema} -> 
        {:ok, cached_schema}
      :not_found ->
        discover_and_cache_schema(module_path, opts, cache_key)
    end
  end
  
  defp discover_and_cache_schema(module_path, opts, cache_key) do
    start_time = System.monotonic_time(:microsecond)
    
    # Current schema discovery logic (moved from DSPex.Bridge)
    result = perform_current_schema_discovery(module_path, opts)
    
    discovery_time = System.monotonic_time(:microsecond) - start_time
    
    case result do
      {:ok, schema} ->
        # Cache successful discovery (performance optimization)
        cache_schema(cache_key, schema, discovery_time)
        
        # Record telemetry for future optimization
        record_discovery_telemetry(module_path, schema, discovery_time)
        
        {:ok, schema}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def call_dspy(class_path, method, args, kwargs, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    
    # Current call_dspy logic (moved from DSPex.Bridge)
    result = perform_current_dspy_call(class_path, method, args, kwargs, opts)
    
    call_time = System.monotonic_time(:microsecond) - start_time
    
    # Record performance telemetry (foundation for optimization)
    record_call_telemetry(class_path, method, result, call_time)
    
    result
  end
  
  # Current implementation (exact same logic as today)
  defp perform_current_schema_discovery(module_path, _opts) do
    # Move existing DSPex.Bridge.discover_schema implementation here
    # [Exact current implementation]
  end
  
  defp perform_current_dspy_call(class_path, method, args, kwargs, _opts) do
    # Move existing DSPex.Bridge.call_dspy implementation here  
    # [Exact current implementation]
  end
  
  # Caching and telemetry (performance optimization + learning foundation)
  defp get_cached_schema(cache_key) do
    case :ets.lookup(:schema_cache, cache_key) do
      [{^cache_key, schema, cached_at}] ->
        if schema_cache_valid?(cached_at) do
          {:ok, schema}
        else
          :not_found
        end
      [] ->
        :not_found
    end
  end
  
  defp cache_schema(cache_key, schema, discovery_time) do
    cache_entry = {cache_key, schema, DateTime.utc_now(), discovery_time}
    :ets.insert(:schema_cache, cache_entry)
  end
  
  defp record_discovery_telemetry(module_path, schema, discovery_time) do
    telemetry_data = %{
      module_path: module_path,
      schema_size: calculate_schema_size(schema),
      discovery_time: discovery_time,
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :schema, :discovery], telemetry_data)
  end
  
  defp record_call_telemetry(class_path, method, result, call_time) do
    telemetry_data = %{
      class_path: class_path,
      method: method, 
      success: match?({:ok, _}, result),
      call_time: call_time,
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :schema, :call], telemetry_data)
  end
end
```

### SnakepitGrpcBridge.Codegen.DSPy
```elixir
defmodule SnakepitGrpcBridge.Codegen.DSPy do
  @moduledoc """
  Enhanced DSPy metaprogramming with cognitive-ready structure.
  
  CURRENT: Current defdsyp macro + usage telemetry  
  FUTURE: AI-powered wrapper optimization based on usage patterns
  """
  
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    generation_id = generate_unique_id()
    
    quote bind_quoted: [
      module_name: module_name,
      class_path: class_path,
      config: config,
      generation_id: generation_id
    ] do
      
      # Record wrapper generation for future optimization learning
      SnakepitGrpcBridge.Codegen.DSPy.record_wrapper_generation(
        module_name, class_path, config, generation_id
      )
      
      defmodule module_name do
        @class_path class_path
        @config config
        @generation_id generation_id
        
        # Current create function + telemetry hooks
        def create(signature, opts \\ []) do
          start_time = System.monotonic_time(:microsecond)
          
          # Current creation logic (same as today)
          result = create_current_dspy_instance(signature, opts)
          
          creation_time = System.monotonic_time(:microsecond) - start_time
          
          # Record telemetry for future optimization
          SnakepitGrpcBridge.Codegen.DSPy.record_instance_creation(
            @generation_id, signature, opts, result, creation_time
          )
          
          result
        end
        
        # Current execute function + telemetry hooks
        def execute(instance, inputs, opts \\ []) do
          start_time = System.monotonic_time(:microsecond)
          
          # Current execution logic (same as today)
          result = execute_current_dspy_instance(instance, inputs, opts)
          
          execution_time = System.monotonic_time(:microsecond) - start_time
          
          # Record telemetry for future optimization
          SnakepitGrpcBridge.Codegen.DSPy.record_instance_execution(
            @generation_id, instance, inputs, result, execution_time
          )
          
          result
        end
        
        # Current implementation functions (exact same as today)
        defp create_current_dspy_instance(signature, opts) do
          # Move current DSPex.Bridge instance creation logic here
          SnakepitGrpcBridge.Schema.DSPy.call_dspy(@class_path, "__init__", [signature], Map.new(opts))
        end
        
        defp execute_current_dspy_instance(instance, inputs, opts) do
          # Move current DSPex.Bridge execution logic here
          execute_method = Map.get(@config, :execute_method, "__call__")
          SnakepitGrpcBridge.Schema.DSPy.call_dspy("stored.#{instance}", execute_method, [], Map.merge(inputs, Map.new(opts)))
        end
      end
    end
  end
  
  # Telemetry collection (foundation for future AI-powered optimization)
  def record_wrapper_generation(module_name, class_path, config, generation_id) do
    generation_record = %{
      generation_id: generation_id,
      module_name: module_name,
      class_path: class_path,
      config: config,
      generated_at: DateTime.utc_now(),
      optimization_level: :current_functionality  # Future: :ai_optimized
    }
    
    :ets.insert(:wrapper_generations, {generation_id, generation_record})
    :telemetry.execute([:snakepit_grpc_bridge, :codegen, :wrapper_generated], generation_record)
  end
  
  def record_instance_creation(generation_id, signature, opts, result, creation_time) do
    creation_record = %{
      generation_id: generation_id,
      signature: signature,
      opts: opts,
      success: match?({:ok, _}, result),
      creation_time: creation_time,
      timestamp: DateTime.utc_now()
    }
    
    :ets.insert(:instance_creations, {generate_unique_id(), creation_record})
    :telemetry.execute([:snakepit_grpc_bridge, :codegen, :instance_created], creation_record)
  end
  
  def record_instance_execution(generation_id, instance, inputs, result, execution_time) do
    execution_record = %{
      generation_id: generation_id,
      input_complexity: analyze_input_complexity(inputs),
      success: match?({:ok, _}, result),
      execution_time: execution_time,
      result_quality: analyze_result_quality(result),
      timestamp: DateTime.utc_now()
    }
    
    :ets.insert(:instance_executions, {generate_unique_id(), execution_record})
    :telemetry.execute([:snakepit_grpc_bridge, :codegen, :instance_executed], execution_record)
  end
  
  # Analysis functions (foundation for future AI optimization)
  defp analyze_input_complexity(inputs) when is_map(inputs) do
    %{
      parameter_count: map_size(inputs),
      total_string_length: calculate_total_string_length(inputs),
      nesting_depth: calculate_nesting_depth(inputs)
    }
  end
  
  defp analyze_result_quality(result) do
    case result do
      {:ok, data} ->
        %{success: true, data_size: calculate_data_size(data)}
      {:error, _reason} ->
        %{success: false, data_size: 0}
    end
  end
end
```

## Migration Strategy

### Step 1: Create Packages
1. Extract Snakepit Core (pure infrastructure)
2. Create SnakepitGrpcBridge with cognitive-ready structure
3. Move all current DSPy functionality into cognitive modules

### Step 2: Update DSPex  
1. Change dependency to SnakepitGrpcBridge
2. Update imports to use new module paths
3. No functionality changes - just new paths

### Step 3: Test & Validate
1. All current functionality works exactly the same
2. New telemetry collection working
3. Cognitive structure ready for future enhancement

## Cognitive Evolution Path

When ready for cognitive features:

### Phase 1: Enable Learning
```elixir
# Simply enable learning algorithms
config :snakepit_grpc_bridge, :cognitive_features, %{
  performance_learning: true,    # Enable in evolution.ex
  usage_optimization: true,      # Enable in codegen.ex  
  intelligent_routing: true      # Enable in scheduler.ex
}
```

### Phase 2: Add Advanced Features
```elixir
# Add new cognitive capabilities
config :snakepit_grpc_bridge, :cognitive_features, %{
  worker_collaboration: true,    # Enable in collaboration.ex
  multi_framework_support: true, # Enable in universal.ex
  ai_powered_optimization: true  # Enable throughout system
}
```

The architecture is designed so cognitive evolution requires **zero structural changes** - just implementation upgrades within the existing structure.

## Benefits

1. **Current Functionality Preserved**: Everything works exactly as today
2. **Cognitive-Ready Structure**: Ready for revolutionary features when needed  
3. **Clean Separation**: Clear boundaries between infrastructure and domain logic
4. **Telemetry Foundation**: Collecting data needed for future learning
5. **Zero Compatibility Issues**: Seamless upgrade path for users

This gives us the best of both worlds: working software now with revolutionary potential later.
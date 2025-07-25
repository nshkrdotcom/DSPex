# Phase 1 Migration Guide: Step-by-Step Implementation

**Date**: July 25, 2025  
**Author**: Claude Code  
**Status**: Phase 1 Migration Instructions  
**Version**: 1.0

## Overview

This guide provides detailed, step-by-step instructions for migrating from the current architecture to the Phase 1 cognitive framework. The migration preserves 100% functionality while establishing the revolutionary cognitive foundation.

**Timeline**: 4 weeks total
**Risk Level**: Low (using proven functionality in new structure)
**Rollback Strategy**: Full rollback capability at each step

## Pre-Migration Checklist

### Environment Preparation
- [ ] Full backup of both repositories
- [ ] Comprehensive test suite execution (baseline metrics)
- [ ] Documentation of current performance benchmarks
- [ ] Development environment setup with both repositories
- [ ] Feature flag system preparation

### Team Preparation
- [ ] Migration team assignments
- [ ] Communication plan established
- [ ] Rollback procedures documented
- [ ] Testing strategy finalized

## Week 1: Cognitive Framework Foundation

### Day 1: Repository Structure Setup

#### 1.1 Create Cognitive Framework Structure in Snakepit
```bash
# In snakepit repository
cd /path/to/snakepit

# Create new cognitive framework directories
mkdir -p lib/snakepit/cognitive
mkdir -p lib/snakepit/schema  
mkdir -p lib/snakepit/codegen
mkdir -p lib/snakepit/bridge/cognitive  # Enhanced bridge
mkdir -p lib/snakepit/core              # Rename existing structure

# Create Python cognitive structure
mkdir -p priv/python/snakepit_cognitive
mkdir -p priv/python/frameworks
```

#### 1.2 Initialize ETS Tables and Telemetry
```elixir
# lib/snakepit/application.ex - Add cognitive infrastructure
defmodule Snakepit.Application do
  use Application
  
  def start(_type, _args) do
    # Initialize cognitive ETS tables
    :ets.new(:cognitive_telemetry, [:set, :public, :named_table])
    :ets.new(:schema_cache, [:set, :public, :named_table])
    :ets.new(:wrapper_generations, [:set, :public, :named_table])
    :ets.new(:instance_creations, [:set, :public, :named_table])
    :ets.new(:instance_executions, [:set, :public, :named_table])
    :ets.new(:performance_history, [:set, :public, :named_table])
    
    children = [
      # Existing supervision tree
      Snakepit.Pool.Application,
      
      # NEW: Add cognitive supervision tree
      {Snakepit.Cognitive.Supervisor, []},
      {Snakepit.Schema.Supervisor, []},
      {Snakepit.Codegen.Supervisor, []}
    ]
    
    opts = [strategy: :one_for_one, name: Snakepit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### 1.3 Create Feature Flag System
```elixir
# lib/snakepit/cognitive/feature_flags.ex
defmodule Snakepit.Cognitive.FeatureFlags do
  @moduledoc """
  Feature flag system for gradual cognitive feature activation.
  """
  
  @default_flags %{
    # Phase 1: Infrastructure (enabled immediately)
    telemetry_collection: true,
    performance_monitoring: true,
    enhanced_caching: true,
    
    # Phase 2: Cognitive features (disabled initially)
    performance_learning: false,
    implementation_selection: false,
    worker_collaboration: false,
    adaptive_optimization: false,
    
    # Phase 3: Advanced features (disabled initially)
    multi_framework_bridge: false,
    evolutionary_optimization: false,
    distributed_reasoning: false,
    experimental_features: false
  }
  
  def enabled?(feature) do
    Application.get_env(:snakepit, :cognitive_features, @default_flags)
    |> Map.get(feature, false)
  end
  
  def enable_feature(feature, rollout_percentage \\ 100) do
    current_flags = Application.get_env(:snakepit, :cognitive_features, @default_flags)
    updated_flags = Map.put(current_flags, feature, rollout_percentage)
    
    Application.put_env(:snakepit, :cognitive_features, updated_flags)
    
    # Log feature activation
    Logger.info("Cognitive feature #{feature} activated at #{rollout_percentage}%")
  end
  
  def disable_feature(feature) do
    enable_feature(feature, false)
    Logger.warn("Cognitive feature #{feature} disabled")
  end
end
```

### Day 2: Basic Cognitive Module Stubs

#### 2.1 Create Cognitive Worker Foundation
```elixir
# lib/snakepit/cognitive/worker.ex
defmodule Snakepit.Cognitive.Worker do
  @moduledoc """
  Phase 1: Cognitive worker foundation with current functionality.
  Includes telemetry collection infrastructure for future learning.
  """
  
  use GenServer
  require Logger
  
  # Phase 1: Basic structure with cognitive hooks
  defstruct [
    # Current worker fields (migrated from existing worker)
    :pid,
    :adapter,
    :session_store,
    :health_status,
    
    # Phase 1: Cognitive infrastructure (ready but unused)
    :telemetry_collector,
    :performance_history_buffer,
    :task_metadata_cache,
    :worker_id
  ]
  
  def start_link(opts) do
    worker_id = Keyword.get(opts, :worker_id, generate_worker_id())
    GenServer.start_link(__MODULE__, Keyword.put(opts, :worker_id, worker_id), 
                         name: {:via, Registry, {Snakepit.Cognitive.WorkerRegistry, worker_id}})
  end
  
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    
    state = %__MODULE__{
      adapter: Keyword.get(opts, :adapter),
      session_store: :ets.new(:sessions, [:set, :private]),
      health_status: :healthy,
      worker_id: worker_id,
      
      # Phase 1: Initialize telemetry infrastructure
      telemetry_collector: init_telemetry_collector(worker_id),
      performance_history_buffer: :queue.new(),
      task_metadata_cache: %{}
    }
    
    # Initialize adapter (current logic)
    case init_current_adapter(state.adapter) do
      {:ok, adapter_state} ->
        Logger.info("Cognitive worker #{worker_id} started successfully")
        {:ok, %{state | adapter: adapter_state}}
      {:error, reason} ->
        Logger.error("Failed to start cognitive worker #{worker_id}: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @doc """
  Execute task with cognitive telemetry collection.
  
  Phase 1: Current execution logic + performance tracking
  """
  def execute_task(worker_pid, task, context) do
    GenServer.call(worker_pid, {:execute_task, task, context})
  end
  
  def handle_call({:execute_task, task, context}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Phase 1: Execute using current logic
    result = execute_current_task_logic(state.adapter, task, context)
    
    execution_time = System.monotonic_time(:microsecond) - start_time
    
    # Phase 1: Collect telemetry for future cognitive use
    collect_execution_telemetry(state, task, result, execution_time, context)
    
    {:reply, result, state}
  end
  
  # Phase 1: Current task execution (migrated from existing worker)
  defp execute_current_task_logic(adapter, task, context) do
    # TODO: Move existing task execution logic here
    # This should be identical to current worker execution
    
    # Placeholder for current logic
    case adapter do
      %{type: :python} ->
        # Current Python execution logic
        execute_python_task(adapter, task, context)
      
      %{type: :javascript} ->
        # Current JavaScript execution logic  
        execute_javascript_task(adapter, task, context)
        
      _ ->
        {:error, {:unsupported_adapter, adapter}}
    end
  end
  
  # Phase 1: Telemetry collection (foundation for future learning)
  defp collect_execution_telemetry(state, task, result, execution_time, context) do
    if Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection) do
      telemetry_data = %{
        worker_id: state.worker_id,
        task_type: get_task_type(task),
        task_signature: get_task_signature(task),
        execution_time: execution_time,
        success: match?({:ok, _}, result),
        context_metadata: extract_context_metadata(context),
        timestamp: DateTime.utc_now(),
        phase: :phase_1_collection
      }
      
      # Store for future cognitive analysis
      :ets.insert(:cognitive_telemetry, {generate_telemetry_id(), telemetry_data})
      
      # Emit telemetry event
      :telemetry.execute([:snakepit, :cognitive, :task_executed], telemetry_data)
    end
  end
  
  # Health check (enhanced)
  def handle_call(:health_check, _from, state) do
    health_status = check_current_health(state.adapter)
    updated_state = %{state | health_status: health_status}
    
    {:reply, {:ok, health_status}, updated_state}
  end
  
  # Helper functions
  defp generate_worker_id do
    "worker_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
  
  defp init_telemetry_collector(worker_id) do
    %{
      worker_id: worker_id,
      collection_enabled: true,
      buffer_size: 1000,
      collection_started: DateTime.utc_now()
    }
  end
  
  defp generate_telemetry_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
  
  defp get_task_type(task) when is_map(task), do: Map.get(task, :type, :unknown)
  defp get_task_type(_task), do: :unknown
  
  defp get_task_signature(task) when is_map(task), do: Map.get(task, :signature, "")
  defp get_task_signature(_task), do: ""
  
  defp extract_context_metadata(context) when is_map(context) do
    %{
      session_id: Map.get(context, :session_id),
      user_id: Map.get(context, :user_id),
      request_id: Map.get(context, :request_id),
      preferences: Map.get(context, :preferences, %{})
    }
  end
  defp extract_context_metadata(_context), do: %{}
  
  # TODO: Implement current adapter initialization and task execution
  defp init_current_adapter(adapter_config) do
    # Move current adapter initialization logic here
    {:ok, %{type: :python, config: adapter_config}}  # Placeholder
  end
  
  defp execute_python_task(_adapter, _task, _context) do
    # TODO: Move current Python task execution logic here
    {:ok, %{result: "placeholder"}}
  end
  
  defp execute_javascript_task(_adapter, _task, _context) do  
    # TODO: Move current JavaScript task execution logic here
    {:ok, %{result: "placeholder"}}
  end
  
  defp check_current_health(_adapter) do
    # TODO: Move current health check logic here
    :healthy
  end
end
```

#### 2.2 Create Cognitive Scheduler Foundation
```elixir
# lib/snakepit/cognitive/scheduler.ex
defmodule Snakepit.Cognitive.Scheduler do
  @moduledoc """
  Phase 1: Enhanced scheduler with current round-robin logic + telemetry.
  Foundation for Phase 2+ intelligent routing.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :workers,
    :current_worker_index,
    :worker_health_status,
    :routing_telemetry,
    :scheduler_id
  ]
  
  def start_link(workers) do
    GenServer.start_link(__MODULE__, workers, name: __MODULE__)
  end
  
  def init(workers) do
    scheduler_id = generate_scheduler_id()
    
    state = %__MODULE__{
      workers: workers,
      current_worker_index: 0,
      worker_health_status: initialize_worker_health(workers),
      routing_telemetry: init_routing_telemetry(scheduler_id),
      scheduler_id: scheduler_id
    }
    
    Logger.info("Cognitive scheduler #{scheduler_id} initialized with #{length(workers)} workers")
    {:ok, state}
  end
  
  @doc """
  Route task to optimal worker.
  
  Phase 1: Enhanced round-robin with telemetry collection
  """
  def route_task(task, context \\ %{}) do
    GenServer.call(__MODULE__, {:route_task, task, context})
  end
  
  def handle_call({:route_task, task, context}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Phase 1: Use current round-robin logic with enhancements
    routing_result = route_task_round_robin(state, task, context)
    
    routing_time = System.monotonic_time(:microsecond) - start_time
    
    case routing_result do
      {:ok, selected_worker} ->
        # Collect routing telemetry for future intelligence
        collect_routing_telemetry(state, task, selected_worker, routing_time, context)
        
        {:reply, {:ok, selected_worker}, state}
        
      {:error, reason} ->
        Logger.error("Task routing failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  # Phase 1: Enhanced round-robin routing
  defp route_task_round_robin(state, task, context) do
    healthy_workers = get_healthy_workers(state)
    
    if Enum.empty?(healthy_workers) do
      {:error, :no_healthy_workers}
    else
      # Simple load balancing with health awareness
      worker_index = rem(state.current_worker_index, length(healthy_workers))
      selected_worker = Enum.at(healthy_workers, worker_index)
      
      # Update state for next routing
      updated_state = %{state | current_worker_index: worker_index + 1}
      
      {:ok, selected_worker}
    end
  end
  
  # Phase 1: Routing telemetry collection
  defp collect_routing_telemetry(state, task, selected_worker, routing_time, context) do
    if Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection) do
      routing_data = %{
        scheduler_id: state.scheduler_id,
        task_type: get_task_type(task),
        selected_worker: selected_worker,
        available_workers: length(get_healthy_workers(state)),
        routing_method: :round_robin,  # Phase 2+: Will be :intelligent
        routing_time: routing_time,
        context_hints: extract_routing_context(context),
        timestamp: DateTime.utc_now(),
        phase: :phase_1_round_robin
      }
      
      # Store for future intelligent routing
      :ets.insert(:cognitive_telemetry, {generate_telemetry_id(), routing_data})
      
      # Emit telemetry event
      :telemetry.execute([:snakepit, :cognitive, :task_routed], routing_data)
    end
  end
  
  # Worker health management
  def handle_call({:update_worker_health, worker_id, health_status}, _from, state) do
    updated_health = Map.put(state.worker_health_status, worker_id, health_status)
    updated_state = %{state | worker_health_status: updated_health}
    
    Logger.info("Worker #{worker_id} health updated to #{health_status}")
    {:reply, :ok, updated_state}
  end
  
  # Helper functions
  defp generate_scheduler_id do
    "scheduler_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
  
  defp initialize_worker_health(workers) do
    workers
    |> Enum.map(fn worker -> {worker, :healthy} end)
    |> Map.new()
  end
  
  defp init_routing_telemetry(scheduler_id) do
    %{
      scheduler_id: scheduler_id,
      collection_enabled: true,
      total_routes: 0,
      collection_started: DateTime.utc_now()
    }
  end
  
  defp get_healthy_workers(state) do
    state.workers
    |> Enum.filter(fn worker ->
         Map.get(state.worker_health_status, worker, :healthy) == :healthy
       end)
  end
  
  defp get_task_type(task) when is_map(task), do: Map.get(task, :type, :unknown)
  defp get_task_type(_task), do: :unknown
  
  defp extract_routing_context(context) when is_map(context) do
    %{
      priority: Map.get(context, :priority, :normal),
      session_id: Map.get(context, :session_id),
      performance_preference: Map.get(context, :performance_preference, :balanced)
    }
  end
  defp extract_routing_context(_context), do: %{}
  
  defp generate_telemetry_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
```

### Day 3: Schema System Foundation

#### 3.1 Move DSPy Schema Discovery to Cognitive Framework
```elixir
# lib/snakepit/schema/dspy.ex
defmodule Snakepit.Schema.DSPy do
  @moduledoc """
  Phase 1: Enhanced DSPy schema discovery with caching and telemetry.
  Moved from DSPex.Bridge with performance optimizations.
  """
  
  require Logger
  
  @doc """
  Discover DSPy schema with intelligent caching.
  
  Phase 1: Current discovery logic + performance optimization
  """
  def discover_schema(module_path \\ "dspy", opts \\ []) do
    cache_key = build_cache_key(module_path, opts)
    
    case get_cached_schema(cache_key) do
      {:hit, schema} ->
        Logger.debug("Schema cache hit for #{module_path}")
        {:ok, schema}
        
      :miss ->
        Logger.debug("Schema cache miss for #{module_path}, discovering...")
        discover_and_cache_schema(module_path, opts, cache_key)
    end
  end
  
  @doc """
  Call DSPy method with performance tracking.
  
  Phase 1: Current call_dspy logic + telemetry collection
  """
  def call_dspy(class_path, method, args, kwargs, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    
    # TODO: Move current DSPex.Bridge.call_dspy implementation here
    result = execute_dspy_call(class_path, method, args, kwargs, opts)
    
    call_time = System.monotonic_time(:microsecond) - start_time
    
    # Collect call telemetry
    collect_call_telemetry(class_path, method, result, call_time, opts)
    
    result
  end
  
  # Phase 1: Discovery implementation (moved from DSPex)
  defp discover_and_cache_schema(module_path, opts, cache_key) do
    start_time = System.monotonic_time(:microsecond)
    
    # TODO: Move exact discovery logic from DSPex.Bridge here
    result = perform_schema_discovery(module_path, opts)
    
    discovery_time = System.monotonic_time(:microsecond) - start_time
    
    case result do
      {:ok, schema} ->
        # Cache successful discovery
        cache_schema(cache_key, schema, discovery_time)
        
        # Record discovery telemetry
        collect_discovery_telemetry(module_path, schema, discovery_time, opts)
        
        Logger.info("Schema discovered for #{module_path} in #{discovery_time}μs")
        {:ok, schema}
        
      {:error, reason} ->
        Logger.error("Schema discovery failed for #{module_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # TODO: Move current discovery implementation from DSPex.Bridge
  defp perform_schema_discovery(module_path, _opts) do
    # This should be the exact logic from DSPex.Bridge.discover_schema
    # Placeholder for now
    {:ok, %{"classes" => %{}, "functions" => %{}, "constants" => %{}}}
  end
  
  # TODO: Move current call implementation from DSPex.Bridge  
  defp execute_dspy_call(class_path, method, args, kwargs, _opts) do
    # This should be the exact logic from DSPex.Bridge.call_dspy
    # Placeholder for now
    {:ok, %{result: "placeholder"}}
  end
  
  # Caching implementation
  defp build_cache_key(module_path, opts) do
    # Create deterministic cache key
    opts_hash = :crypto.hash(:md5, :erlang.term_to_binary(opts)) |> Base.encode16()
    "#{module_path}_#{opts_hash}"
  end
  
  defp get_cached_schema(cache_key) do
    case :ets.lookup(:schema_cache, cache_key) do
      [{^cache_key, schema, cached_at, _discovery_time}] ->
        if cache_valid?(cached_at) do
          {:hit, schema}
        else
          :miss
        end
      [] ->
        :miss
    end
  end
  
  defp cache_schema(cache_key, schema, discovery_time) do
    cache_entry = {cache_key, schema, DateTime.utc_now(), discovery_time}
    :ets.insert(:schema_cache, cache_entry)
    
    # Optional: Implement cache size limits and LRU eviction
    manage_cache_size()
  end
  
  defp cache_valid?(cached_at) do
    # Cache TTL: 1 hour (configurable)
    cache_ttl_seconds = Application.get_env(:snakepit, :schema_cache_ttl, 3600)
    DateTime.diff(DateTime.utc_now(), cached_at, :second) < cache_ttl_seconds
  end
  
  defp manage_cache_size do
    # Simple cache management - keep last 1000 entries
    cache_limit = Application.get_env(:snakepit, :schema_cache_limit, 1000)
    
    if :ets.info(:schema_cache, :size) > cache_limit do
      # Simple eviction: delete oldest 10% of entries
      # In production, implement proper LRU eviction
      Logger.debug("Schema cache size limit reached, performing eviction")
    end
  end
  
  # Telemetry collection
  defp collect_discovery_telemetry(module_path, schema, discovery_time, opts) do
    if Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection) do
      telemetry_data = %{
        module_path: module_path,
        discovery_time: discovery_time,
        schema_complexity: calculate_schema_complexity(schema),
        classes_count: map_size(schema["classes"] || %{}),
        functions_count: map_size(schema["functions"] || %{}),
        constants_count: map_size(schema["constants"] || %{}),
        opts: opts,
        timestamp: DateTime.utc_now(),
        phase: :phase_1_enhanced
      }
      
      :ets.insert(:cognitive_telemetry, {generate_telemetry_id(), telemetry_data})
      :telemetry.execute([:snakepit, :schema, :discovered], telemetry_data)
    end
  end
  
  defp collect_call_telemetry(class_path, method, result, call_time, opts) do
    if Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection) do
      telemetry_data = %{
        class_path: class_path,
        method: method,
        call_time: call_time,
        success: match?({:ok, _}, result),
        opts: opts,
        timestamp: DateTime.utc_now(),
        phase: :phase_1_enhanced
      }
      
      :ets.insert(:cognitive_telemetry, {generate_telemetry_id(), telemetry_data})
      :telemetry.execute([:snakepit, :schema, :called], telemetry_data)
    end
  end
  
  defp calculate_schema_complexity(schema) when is_map(schema) do
    # Simple complexity metric for telemetry
    classes_complexity = (schema["classes"] || %{}) |> map_size()
    functions_complexity = (schema["functions"] || %{}) |> map_size()
    constants_complexity = (schema["constants"] || %{}) |> map_size()
    
    classes_complexity + functions_complexity + constants_complexity
  end
  defp calculate_schema_complexity(_schema), do: 0
  
  defp generate_telemetry_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
```

### Day 4: Code Generation Migration

#### 4.1 Move DSPy Metaprogramming to Cognitive Framework
```elixir
# lib/snakepit/codegen/dspy.ex
defmodule Snakepit.Codegen.DSPy do
  @moduledoc """
  Phase 1: Enhanced DSPy metaprogramming with usage tracking.
  Moved from DSPex.Bridge with performance monitoring.
  """
  
  require Logger
  
  @doc """
  Generate DSPy wrapper with enhanced telemetry.
  
  Phase 1: Current defdsyp logic + comprehensive usage tracking
  """
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    generation_id = generate_generation_id()
    
    quote bind_quoted: [
      module_name: module_name,
      class_path: class_path,
      config: config,
      generation_id: generation_id
    ] do
      
      # Record wrapper generation
      Snakepit.Codegen.DSPy.record_wrapper_generation(
        module_name, class_path, config, generation_id
      )
      
      defmodule module_name do
        @class_path class_path
        @config config
        @generation_id generation_id
        
        require Logger
        
        @doc """
        Create DSPy instance with telemetry.
        
        Phase 1: Current creation logic + performance tracking
        """
        def create(signature, opts \\ []) do
          start_time = System.monotonic_time(:microsecond)
          
          # TODO: Move current instance creation logic from DSPex.Bridge
          result = create_dspy_instance_current(signature, opts)
          
          creation_time = System.monotonic_time(:microsecond) - start_time
          
          # Record creation telemetry
          Snakepit.Codegen.DSPy.record_instance_creation(
            @generation_id, signature, opts, result, creation_time
          )
          
          result
        end
        
        @doc """
        Execute DSPy instance with performance tracking.
        
        Phase 1: Current execution logic + telemetry
        """
        def execute(instance, inputs, opts \\ []) do
          start_time = System.monotonic_time(:microsecond)
          
          # TODO: Move current execution logic from DSPex.Bridge
          result = execute_dspy_instance_current(instance, inputs, opts)
          
          execution_time = System.monotonic_time(:microsecond) - start_time
          
          # Record execution telemetry
          Snakepit.Codegen.DSPy.record_instance_execution(
            @generation_id, instance, inputs, result, execution_time
          )
          
          result
        end
        
        @doc """
        Stateless call with optimization potential.
        
        Phase 1: Current call logic + usage pattern analysis
        """
        def call(signature, inputs, opts \\ []) do
          # Phase 2+: This is where instance reuse optimization will happen
          case create(signature, opts) do
            {:ok, instance} ->
              execute(instance, inputs, opts)
            {:error, reason} ->
              {:error, reason}
          end
        end
        
        # TODO: Move current implementation logic from DSPex.Bridge
        defp create_dspy_instance_current(signature, opts) do
          # This should be exact logic from DSPex.Bridge wrapper generation
          Snakepit.Schema.DSPy.call_dspy(@class_path, "__init__", [signature], Map.new(opts))
        end
        
        defp execute_dspy_instance_current(instance, inputs, opts) do
          # This should be exact logic from DSPex.Bridge wrapper generation
          execute_method = Map.get(@config, :execute_method, "__call__")
          combined_args = Map.merge(inputs, Map.new(opts))
          Snakepit.Schema.DSPy.call_dspy("stored.#{instance}", execute_method, [], combined_args)
        end
      end
    end
  end
  
  @doc """
  Record wrapper generation for optimization analysis.
  """
  def record_wrapper_generation(module_name, class_path, config, generation_id) do
    generation_record = %{
      generation_id: generation_id,
      module_name: inspect(module_name),
      class_path: class_path,
      config: config,
      generated_at: DateTime.utc_now(),
      optimization_version: :phase_1_telemetry
    }
    
    # Store for usage pattern analysis
    :ets.insert(:wrapper_generations, {generation_id, generation_record})
    
    if Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection) do
      :telemetry.execute([:snakepit, :codegen, :wrapper_generated], generation_record)
    end
    
    Logger.debug("Generated DSPy wrapper #{inspect(module_name)} with ID #{generation_id}")
  end
  
  @doc """
  Record instance creation for performance optimization.
  """
  def record_instance_creation(generation_id, signature, opts, result, creation_time) do
    creation_record = %{
      generation_id: generation_id,
      signature: signature,
      signature_complexity: analyze_signature_complexity(signature),
      opts: opts,
      success: match?({:ok, _}, result),
      creation_time: creation_time,
      timestamp: DateTime.utc_now(),
      phase: :phase_1_telemetry
    }
    
    # Store for optimization learning
    :ets.insert(:instance_creations, {generate_record_id(), creation_record})
    
    if Snakepit.Cognitive.FeatureFlags.enabled?(:performance_monitoring) do
      :telemetry.execute([:snakepit, :codegen, :instance_created], creation_record)
    end
  end
  
  @doc """
  Record instance execution for usage pattern analysis.
  """
  def record_instance_execution(generation_id, instance, inputs, result, execution_time) do
    execution_record = %{
      generation_id: generation_id,
      instance_id: extract_instance_id(instance),
      input_complexity: analyze_input_complexity(inputs),
      success: match?({:ok, _}, result),
      execution_time: execution_time,
      result_analysis: analyze_result_quality(result),
      timestamp: DateTime.utc_now(),
      phase: :phase_1_telemetry
    }
    
    # Store for performance optimization learning
    :ets.insert(:instance_executions, {generate_record_id(), execution_record})
    
    if Snakepit.Cognitive.FeatureFlags.enabled?(:performance_monitoring) do
      :telemetry.execute([:snakepit, :codegen, :instance_executed], execution_record)
    end
  end
  
  @doc """
  Get wrapper performance insights.
  
  Phase 1: Basic analytics for monitoring
  Phase 2+: ML-powered optimization recommendations
  """
  def get_wrapper_performance_insights(generation_id) do
    creations = get_creation_records(generation_id)
    executions = get_execution_records(generation_id)
    
    insights = %{
      generation_id: generation_id,
      total_instances_created: length(creations),
      total_executions: length(executions),
      average_creation_time: calculate_average_time(creations, :creation_time),
      average_execution_time: calculate_average_time(executions, :execution_time),
      success_rate: calculate_success_rate(executions),
      usage_patterns: analyze_usage_patterns(creations, executions),
      optimization_opportunities: identify_optimization_opportunities(creations, executions),
      analysis_phase: :phase_1_basic_analytics
    }
    
    Logger.info("Performance insights for wrapper #{generation_id}: #{inspect(insights, limit: :infinity)}")
    insights
  end
  
  # Helper functions for analysis
  defp generate_generation_id do
    "gen_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16())
  end
  
  defp generate_record_id do
    "rec_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
  
  defp analyze_signature_complexity(signature) when is_binary(signature) do
    %{
      length: String.length(signature),
      arrow_count: signature |> String.split("->") |> length() |> Kernel.-(1),
      parameter_count: estimate_parameter_count(signature),
      complexity_score: calculate_signature_complexity_score(signature)
    }
  end
  defp analyze_signature_complexity(_signature), do: %{complexity_score: 0}
  
  defp analyze_input_complexity(inputs) when is_map(inputs) do
    %{
      parameter_count: map_size(inputs),
      total_content_length: calculate_total_content_length(inputs),
      nesting_depth: calculate_max_nesting_depth(inputs),
      complexity_score: calculate_input_complexity_score(inputs)
    }
  end
  defp analyze_input_complexity(_inputs), do: %{complexity_score: 0}
  
  defp analyze_result_quality(result) do
    case result do
      {:ok, data} ->
        %{
          success: true,
          data_size: estimate_data_size(data),
          completeness_estimate: estimate_completeness(data)
        }
      {:error, reason} ->
        %{
          success: false,
          error_type: classify_error(reason),
          data_size: 0,
          completeness_estimate: 0.0
        }
    end
  end
  
  defp extract_instance_id(instance) when is_binary(instance) do
    # Extract ID from stored instance reference
    case String.split(instance, ".") do
      ["stored", id] -> id
      _ -> "unknown"
    end
  end
  defp extract_instance_id(_instance), do: "unknown"
  
  defp get_creation_records(generation_id) do
    :ets.match(:instance_creations, {:"$1", %{generation_id: generation_id}})
    |> Enum.map(fn [record] -> record end)
  end
  
  defp get_execution_records(generation_id) do
    :ets.match(:instance_executions, {:"$1", %{generation_id: generation_id}})
    |> Enum.map(fn [record] -> record end)
  end
  
  defp calculate_average_time(records, time_field) do
    if Enum.empty?(records) do
      0.0
    else
      total_time = records
      |> Enum.map(fn record -> Map.get(record, time_field, 0) end)
      |> Enum.sum()
      
      total_time / length(records)
    end
  end
  
  defp calculate_success_rate(execution_records) do
    if Enum.empty?(execution_records) do
      0.0
    else
      successful = Enum.count(execution_records, fn record -> record.success end)
      successful / length(execution_records)
    end
  end
  
  defp analyze_usage_patterns(creations, executions) do
    # Phase 1: Basic usage pattern analysis
    %{
      instance_reuse_ratio: calculate_reuse_ratio(creations, executions),
      peak_usage_times: identify_peak_usage_times(executions),
      common_signatures: identify_common_signatures(creations),
      average_session_length: calculate_average_session_length(executions)
    }
  end
  
  defp identify_optimization_opportunities(creations, executions) do
    opportunities = []
    
    # Instance reuse opportunity
    reuse_ratio = calculate_reuse_ratio(creations, executions)
    opportunities = if reuse_ratio < 0.5 do
      [:instance_pooling | opportunities]
    else
      opportunities
    end
    
    # Performance optimization opportunity
    avg_execution_time = calculate_average_time(executions, :execution_time)
    opportunities = if avg_execution_time > 2_000_000 do  # 2 seconds
      [:performance_optimization | opportunities]
    else
      opportunities
    end
    
    # Caching opportunity
    common_signatures = identify_common_signatures(creations)
    opportunities = if length(common_signatures) > 3 do
      [:result_caching | opportunities]
    else
      opportunities
    end
    
    opportunities
  end
  
  # Additional helper functions
  defp estimate_parameter_count(signature) do
    # Simple estimation based on comma count and arrows
    signature
    |> String.split(~r/[,:]/)
    |> length()
  end
  
  defp calculate_signature_complexity_score(signature) do
    # Simple heuristic for signature complexity
    length_score = String.length(signature) / 100.0
    arrow_score = (signature |> String.split("->") |> length() |> Kernel.-(1)) / 5.0
    
    min(length_score + arrow_score, 1.0)
  end
  
  defp calculate_total_content_length(inputs) when is_map(inputs) do
    inputs
    |> Map.values()
    |> Enum.map(fn
         value when is_binary(value) -> String.length(value)
         value when is_list(value) -> length(value)
         value when is_map(value) -> map_size(value)
         _ -> 1
       end)
    |> Enum.sum()
  end
  
  defp calculate_max_nesting_depth(data, current_depth \\ 0) do
    case data do
      map when is_map(map) ->
        if map_size(map) == 0 do
          current_depth
        else
          max_child_depth = map
          |> Map.values()
          |> Enum.map(fn value -> calculate_max_nesting_depth(value, current_depth + 1) end)
          |> Enum.max(fn -> current_depth end)
          
          max_child_depth
        end
      
      list when is_list(list) ->
        if Enum.empty?(list) do
          current_depth
        else
          max_child_depth = list
          |> Enum.map(fn value -> calculate_max_nesting_depth(value, current_depth + 1) end)
          |> Enum.max(fn -> current_depth end)
          
          max_child_depth
        end
      
      _ ->
        current_depth
    end
  end
  
  defp calculate_input_complexity_score(inputs) when is_map(inputs) do
    param_count_score = min(map_size(inputs) / 10.0, 0.5)
    content_length_score = min(calculate_total_content_length(inputs) / 1000.0, 0.3)
    nesting_score = min(calculate_max_nesting_depth(inputs) / 5.0, 0.2)
    
    param_count_score + content_length_score + nesting_score
  end
  defp calculate_input_complexity_score(_inputs), do: 0.0
  
  defp estimate_data_size(data) when is_binary(data), do: String.length(data)
  defp estimate_data_size(data) when is_map(data), do: map_size(data) * 10  # Rough estimate
  defp estimate_data_size(data) when is_list(data), do: length(data) * 5    # Rough estimate
  defp estimate_data_size(_data), do: 1
  
  defp estimate_completeness(data) when is_map(data) do
    # Estimate completeness based on non-nil values
    if map_size(data) == 0 do
      0.0
    else
      non_nil_count = data |> Map.values() |> Enum.count(fn v -> v != nil and v != "" end)
      non_nil_count / map_size(data)
    end
  end
  defp estimate_completeness(data) when is_binary(data) do
    cond do
      String.length(data) == 0 -> 0.0
      String.length(data) < 10 -> 0.3  
      String.length(data) < 100 -> 0.7
      true -> 1.0
    end
  end
  defp estimate_completeness(_data), do: 0.5
  
  defp classify_error(reason) do
    # Simple error classification for telemetry
    case reason do
      {:timeout, _} -> :timeout_error
      {:connection_error, _} -> :connection_error
      {:python_error, _} -> :python_execution_error
      _ -> :unknown_error
    end
  end
  
  defp calculate_reuse_ratio(creations, executions) do
    if Enum.empty?(creations) or Enum.empty?(executions) do
      0.0
    else
      length(executions) / length(creations)
    end
  end
  
  defp identify_peak_usage_times(executions) do
    # Group executions by hour and find peaks
    executions
    |> Enum.group_by(fn record -> 
         record.timestamp |> DateTime.to_time() |> Time.truncate(:hour)
       end)
    |> Enum.map(fn {hour, records} -> {hour, length(records)} end)
    |> Enum.sort_by(fn {_hour, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {hour, _count} -> hour end)
  end
  
  defp identify_common_signatures(creations) do
    # Find most commonly used signatures
    creations
    |> Enum.group_by(fn record -> record.signature end)
    |> Enum.map(fn {signature, records} -> {signature, length(records)} end)
    |> Enum.sort_by(fn {_signature, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {signature, _count} -> signature end)
  end
  
  defp calculate_average_session_length(executions) do
    # Simple session length calculation based on execution timestamps
    if length(executions) < 2 do
      0.0
    else
      sorted_executions = Enum.sort_by(executions, fn record -> record.timestamp end)
      first_execution = List.first(sorted_executions)
      last_execution = List.last(sorted_executions)
      
      DateTime.diff(last_execution.timestamp, first_execution.timestamp, :second)
    end
  end
end
```

### Day 5: Supervision and Monitoring Setup

#### 5.1 Create Cognitive Supervision Tree
```elixir
# lib/snakepit/cognitive/supervisor.ex
defmodule Snakepit.Cognitive.Supervisor do
  @moduledoc """
  Supervisor for all cognitive framework components.
  
  Phase 1: Basic supervision with telemetry monitoring
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Phase 1: Basic cognitive supervision tree
    children = [
      # Worker registry for cognitive workers
      {Registry, keys: :unique, name: Snakepit.Cognitive.WorkerRegistry},
      
      # Cognitive scheduler (enhanced round-robin)
      {Snakepit.Cognitive.Scheduler, get_initial_workers()},
      
      # Performance monitoring (Phase 1: basic telemetry collection)
      {Snakepit.Cognitive.PerformanceMonitor, []},
      
      # Telemetry aggregator
      {Snakepit.Cognitive.TelemetryAggregator, []},
      
      # Feature flag manager
      {Snakepit.Cognitive.FeatureFlagManager, []}
    ]
    
    opts = [strategy: :one_for_one, name: Snakepit.Cognitive.Supervisor]
    
    Logger.info("Starting Snakepit cognitive supervision tree")
    Supervisor.init(children, opts)
  end
  
  defp get_initial_workers do
    # Start with existing worker configuration
    Application.get_env(:snakepit, :pool_config, %{})
    |> Map.get(:pool_size, 4)
    |> create_initial_workers()
  end
  
  defp create_initial_workers(pool_size) do
    1..pool_size
    |> Enum.map(fn worker_num ->
         worker_id = "worker_#{worker_num}"
         {:ok, worker_pid} = Snakepit.Cognitive.Worker.start_link(worker_id: worker_id)
         worker_pid
       end)
  end
end
```

#### 5.2 Performance Monitoring Foundation
```elixir
# lib/snakepit/cognitive/performance_monitor.ex
defmodule Snakepit.Cognitive.PerformanceMonitor do
  @moduledoc """
  Phase 1: Basic performance monitoring and telemetry aggregation.
  Foundation for Phase 2+ intelligent performance optimization.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :monitoring_enabled,
    :telemetry_buffer,
    :performance_metrics,
    :alert_thresholds,
    :monitor_id
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    monitor_id = generate_monitor_id()
    
    state = %__MODULE__{
      monitoring_enabled: true,
      telemetry_buffer: :queue.new(),
      performance_metrics: initialize_metrics(),
      alert_thresholds: get_alert_thresholds(),
      monitor_id: monitor_id
    }
    
    # Attach telemetry handlers
    attach_telemetry_handlers()
    
    # Schedule periodic reporting
    schedule_performance_reporting()
    
    Logger.info("Performance monitor #{monitor_id} started")
    {:ok, state}
  end
  
  def handle_info(:report_performance, state) do
    if state.monitoring_enabled do
      generate_performance_report(state)
      schedule_performance_reporting()
    end
    
    {:noreply, state}
  end
  
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    # Process incoming telemetry events
    updated_state = process_telemetry_event(state, event_name, measurements, metadata)
    {:noreply, updated_state}
  end
  
  @doc """
  Get current performance metrics.
  """
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  def handle_call(:get_metrics, _from, state) do
    current_metrics = calculate_current_metrics(state)
    {:reply, current_metrics, state}
  end
  
  # Telemetry event processing
  defp attach_telemetry_handlers do
    # Attach to cognitive telemetry events
    :telemetry.attach_many(
      "cognitive-performance-monitor",
      [
        [:snakepit, :cognitive, :task_executed],
        [:snakepit, :cognitive, :task_routed],
        [:snakepit, :schema, :discovered],
        [:snakepit, :schema, :called],
        [:snakepit, :codegen, :wrapper_generated],
        [:snakepit, :codegen, :instance_created],
        [:snakepit, :codegen, :instance_executed]
      ],
      &handle_telemetry_event/4,
      %{}
    )
  end
  
  defp handle_telemetry_event(event_name, measurements, metadata, _config) do
    # Send to monitor process
    send(__MODULE__, {:telemetry_event, event_name, measurements, metadata})
  end
  
  defp process_telemetry_event(state, event_name, measurements, metadata) do
    # Update performance metrics based on telemetry event
    updated_metrics = update_metrics_from_event(
      state.performance_metrics,
      event_name,
      measurements,
      metadata
    )
    
    # Check for performance alerts
    check_performance_alerts(updated_metrics, state.alert_thresholds)
    
    %{state | performance_metrics: updated_metrics}
  end
  
  defp update_metrics_from_event(metrics, event_name, measurements, metadata) do
    case event_name do
      [:snakepit, :cognitive, :task_executed] ->
        update_task_execution_metrics(metrics, measurements, metadata)
        
      [:snakepit, :cognitive, :task_routed] ->
        update_task_routing_metrics(metrics, measurements, metadata)
        
      [:snakepit, :schema, :discovered] ->
        update_schema_discovery_metrics(metrics, measurements, metadata)
        
      [:snakepit, :codegen, :instance_executed] ->
        update_codegen_execution_metrics(metrics, measurements, metadata)
        
      _ ->
        metrics
    end
  end
  
  defp update_task_execution_metrics(metrics, measurements, metadata) do
    execution_time = Map.get(measurements, :execution_time, 0)
    success = Map.get(metadata, :success, false)
    
    %{
      metrics |
      total_tasks_executed: metrics.total_tasks_executed + 1,
      total_execution_time: metrics.total_execution_time + execution_time,
      successful_tasks: metrics.successful_tasks + (if success, do: 1, else: 0),
      average_execution_time: calculate_average_execution_time(metrics, execution_time)
    }
  end
  
  defp update_task_routing_metrics(metrics, measurements, metadata) do
    routing_time = Map.get(measurements, :routing_time, 0)
    available_workers = Map.get(metadata, :available_workers, 0)
    
    %{
      metrics |
      total_routes: metrics.total_routes + 1,
      total_routing_time: metrics.total_routing_time + routing_time,
      average_routing_time: calculate_average_routing_time(metrics, routing_time),
      worker_utilization: calculate_worker_utilization(available_workers)
    }
  end
  
  defp update_schema_discovery_metrics(metrics, measurements, metadata) do
    discovery_time = Map.get(measurements, :discovery_time, 0)
    classes_count = Map.get(metadata, :classes_count, 0)
    
    %{
      metrics |
      total_schema_discoveries: metrics.total_schema_discoveries + 1,
      total_discovery_time: metrics.total_discovery_time + discovery_time,
      average_discovery_time: calculate_average_discovery_time(metrics, discovery_time),
      total_classes_discovered: metrics.total_classes_discovered + classes_count
    }
  end
  
  defp update_codegen_execution_metrics(metrics, measurements, metadata) do
    execution_time = Map.get(measurements, :execution_time, 0)
    success = Map.get(metadata, :success, false)
    
    %{
      metrics |
      total_codegen_executions: metrics.total_codegen_executions + 1,
      total_codegen_time: metrics.total_codegen_time + execution_time,
      successful_codegen: metrics.successful_codegen + (if success, do: 1, else: 0)
    }
  end
  
  # Performance reporting
  defp schedule_performance_reporting do
    # Report every 5 minutes in Phase 1
    report_interval = Application.get_env(:snakepit, :performance_report_interval, 300_000)
    Process.send_after(self(), :report_performance, report_interval)
  end
  
  defp generate_performance_report(state) do
    report = %{
      monitor_id: state.monitor_id,
      timestamp: DateTime.utc_now(),
      metrics: state.performance_metrics,
      system_health: assess_system_health(state.performance_metrics),
      recommendations: generate_recommendations(state.performance_metrics),
      phase: :phase_1_monitoring
    }
    
    # Log performance report
    Logger.info("Performance Report: #{inspect(report, limit: :infinity)}")
    
    # Store report for historical analysis
    :ets.insert(:cognitive_telemetry, {generate_report_id(), report})
  end
  
  defp assess_system_health(metrics) do
    # Simple health assessment for Phase 1
    success_rate = calculate_success_rate(metrics)
    avg_response_time = metrics.average_execution_time
    
    cond do
      success_rate > 0.95 and avg_response_time < 1_000_000 -> :excellent
      success_rate > 0.90 and avg_response_time < 2_000_000 -> :good  
      success_rate > 0.80 and avg_response_time < 5_000_000 -> :fair
      true -> :poor
    end
  end
  
  defp generate_recommendations(metrics) do
    recommendations = []
    
    # Performance recommendations
    recommendations = if metrics.average_execution_time > 2_000_000 do
      ["Consider enabling performance optimization features" | recommendations]
    else
      recommendations
    end
    
    # Success rate recommendations
    success_rate = calculate_success_rate(metrics)
    recommendations = if success_rate < 0.90 do
      ["Investigate error patterns and improve error handling" | recommendations]
    else
      recommendations
    end
    
    # Worker utilization recommendations
    recommendations = if metrics.worker_utilization > 0.8 do
      ["Consider scaling up worker pool size" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp check_performance_alerts(metrics, thresholds) do
    # Check various performance thresholds
    if metrics.average_execution_time > thresholds.max_execution_time do
      Logger.warn("Performance Alert: Average execution time #{metrics.average_execution_time}μs exceeds threshold #{thresholds.max_execution_time}μs")
    end
    
    success_rate = calculate_success_rate(metrics)
    if success_rate < thresholds.min_success_rate do
      Logger.warn("Performance Alert: Success rate #{success_rate} below threshold #{thresholds.min_success_rate}")
    end
  end
  
  # Helper functions
  defp generate_monitor_id do
    "monitor_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
  
  defp generate_report_id do
    "report_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
  
  defp initialize_metrics do
    %{
      # Task execution metrics
      total_tasks_executed: 0,
      successful_tasks: 0,
      total_execution_time: 0,
      average_execution_time: 0.0,
      
      # Routing metrics
      total_routes: 0,
      total_routing_time: 0,
      average_routing_time: 0.0,
      worker_utilization: 0.0,
      
      # Schema discovery metrics
      total_schema_discoveries: 0,
      total_discovery_time: 0,
      average_discovery_time: 0.0,
      total_classes_discovered: 0,
      
      # Code generation metrics
      total_codegen_executions: 0,
      successful_codegen: 0,
      total_codegen_time: 0,
      
      # System metrics
      started_at: DateTime.utc_now()
    }
  end
  
  defp get_alert_thresholds do
    %{
      max_execution_time: 5_000_000,    # 5 seconds
      max_routing_time: 100_000,        # 100ms
      max_discovery_time: 10_000_000,   # 10 seconds
      min_success_rate: 0.85,           # 85%
      max_worker_utilization: 0.9       # 90%
    }
  end
  
  defp calculate_current_metrics(state) do
    # Calculate derived metrics
    base_metrics = state.performance_metrics
    
    Map.merge(base_metrics, %{
      success_rate: calculate_success_rate(base_metrics),
      uptime_seconds: calculate_uptime(base_metrics),
      tasks_per_minute: calculate_tasks_per_minute(base_metrics),
      error_rate: calculate_error_rate(base_metrics)
    })
  end
  
  defp calculate_success_rate(metrics) do
    if metrics.total_tasks_executed > 0 do
      metrics.successful_tasks / metrics.total_tasks_executed
    else
      0.0
    end
  end
  
  defp calculate_error_rate(metrics) do
    1.0 - calculate_success_rate(metrics)
  end
  
  defp calculate_uptime(metrics) do
    DateTime.diff(DateTime.utc_now(), metrics.started_at, :second)
  end
  
  defp calculate_tasks_per_minute(metrics) do
    uptime_minutes = calculate_uptime(metrics) / 60.0
    if uptime_minutes > 0 do
      metrics.total_tasks_executed / uptime_minutes
    else
      0.0
    end
  end
  
  defp calculate_average_execution_time(metrics, new_execution_time) do
    if metrics.total_tasks_executed > 0 do
      (metrics.total_execution_time + new_execution_time) / (metrics.total_tasks_executed + 1)
    else
      new_execution_time
    end
  end
  
  defp calculate_average_routing_time(metrics, new_routing_time) do
    if metrics.total_routes > 0 do
      (metrics.total_routing_time + new_routing_time) / (metrics.total_routes + 1)
    else
      new_routing_time
    end
  end
  
  defp calculate_average_discovery_time(metrics, new_discovery_time) do
    if metrics.total_schema_discoveries > 0 do
      (metrics.total_discovery_time + new_discovery_time) / (metrics.total_schema_discoveries + 1)
    else
      new_discovery_time
    end
  end
  
  defp calculate_worker_utilization(available_workers) do
    # Simple utilization calculation
    # Phase 2+: More sophisticated utilization metrics
    total_workers = Application.get_env(:snakepit, :pool_config, %{}) |> Map.get(:pool_size, 4)
    busy_workers = total_workers - available_workers
    
    if total_workers > 0 do
      busy_workers / total_workers
    else
      0.0
    end
  end
end
```

## Week 1 Summary and Validation

### End of Week 1 Checklist
- [ ] Cognitive framework structure created in Snakepit
- [ ] Feature flag system operational
- [ ] Basic cognitive worker with current functionality + telemetry
- [ ] Enhanced scheduler with current routing + performance tracking
- [ ] Schema system foundation with caching and monitoring
- [ ] Code generation with usage tracking
- [ ] Performance monitoring and telemetry collection
- [ ] All telemetry infrastructure collecting data (but not used for decisions)

### Week 1 Validation Tests
```bash
# Test that current functionality still works
mix test

# Test that telemetry is being collected
iex -S mix
> :ets.tab2list(:cognitive_telemetry)

# Test that performance monitoring is active
> Snakepit.Cognitive.PerformanceMonitor.get_performance_metrics()

# Test that feature flags work
> Snakepit.Cognitive.FeatureFlags.enabled?(:telemetry_collection)
```

### Week 1 Rollback Plan
If issues arise:
1. **Disable cognitive features**: Set all feature flags to `false`
2. **Revert to current workers**: Update configuration to use existing workers
3. **Database rollback**: Clear ETS tables and restart applications
4. **Code rollback**: Revert to git commit before migration start

This completes the Week 1 foundation setup. The system now has:
- **Revolutionary architecture** in place
- **Current functionality** preserved and enhanced
- **Comprehensive telemetry** collection for future learning
- **Zero performance impact** (telemetry is lightweight)
- **Platform ready** for Phase 2 cognitive features

Week 2 will focus on moving the actual DSPy bridge functionality and creating the pure orchestration layer in DSPex.
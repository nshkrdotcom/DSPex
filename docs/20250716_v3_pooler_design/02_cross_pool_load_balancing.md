# DSPex V3 Pooler Design Document 2: Cross-Pool Load Balancing and Worker Distribution

**Document ID**: `20250716_v3_pooler_design_02`  
**Version**: 1.0  
**Date**: July 16, 2025  
**Status**: Design Phase  

## 🎯 Executive Summary

This document designs **Cross-Pool Load Balancing and Worker Distribution** for DSPex V3 Pooler. It extends the current single-pool architecture to support multiple specialized pools with intelligent load distribution, worker sharing, and cross-pool coordination for optimal resource utilization and performance.

## 🏗️ Current Architecture Analysis

### Current V3 Pool Design
- **Single Pool Instance**: One `DSPex.Python.Pool` per application
- **Queue-Based Distribution**: FIFO request handling within pool
- **Worker Isolation**: Workers tied to specific pool instance
- **Session Affinity**: Sessions can access any worker in the pool

### Limitations of Single-Pool Architecture
1. **Resource Isolation**: No specialized worker pools for different workload types
2. **Scalability Bottleneck**: Single pool becomes performance bottleneck
3. **No Load Balancing**: Can't distribute load across multiple pools
4. **Rigid Resource Allocation**: All workers have same capabilities
5. **Session Locality**: Sessions can't benefit from worker specialization

## 🚀 Multi-Pool Architecture Design

### 1. Pool Registry and Discovery

#### 1.1 Global Pool Registry
```elixir
defmodule DSPex.Python.PoolRegistry do
  @moduledoc """
  Central registry for managing multiple Python pools with different specializations.
  
  Features:
  - Pool registration and discovery
  - Load balancing across pools
  - Worker sharing coordination
  - Pool health monitoring
  """
  
  use GenServer
  
  defstruct [
    :pools,              # Map of pool_id -> pool_info
    :pool_types,         # Map of type -> [pool_ids]
    :load_balancer,      # Load balancing strategy
    :worker_distribution, # Worker sharing rules
    :health_monitor      # Pool health monitoring
  ]
  
  @pool_types [
    :general,           # General-purpose DSPy operations
    :embedding,         # Text embedding operations
    :classification,    # Classification tasks
    :generation,        # Text generation tasks
    :reasoning,         # Complex reasoning tasks
    :specialized        # Custom specialized operations
  ]
  
  def register_pool(pool_id, pool_pid, pool_config) do
    GenServer.call(__MODULE__, {:register_pool, pool_id, pool_pid, pool_config})
  end
  
  def get_optimal_pool(request_type, requirements \\ %{}) do
    GenServer.call(__MODULE__, {:get_optimal_pool, request_type, requirements})
  end
  
  def get_pools_by_type(pool_type) do
    GenServer.call(__MODULE__, {:get_pools_by_type, pool_type})
  end
  
  def rebalance_workers do
    GenServer.cast(__MODULE__, :rebalance_workers)
  end
end
```

#### 1.2 Pool Configuration Schema
```elixir
defmodule DSPex.Python.PoolConfig do
  @type pool_type :: :general | :embedding | :classification | :generation | :reasoning | :specialized
  @type pool_priority :: :high | :medium | :low
  @type sharing_policy :: :strict | :overflow | :adaptive
  
  defstruct [
    :pool_id,            # Unique identifier
    :pool_type,          # Type of operations this pool handles
    :size,               # Number of workers
    :priority,           # Pool priority for resource allocation
    :sharing_policy,     # How workers can be shared
    :specialization,     # Specific model or task specialization
    :resource_limits,    # Resource constraints
    :affinity_rules,     # Session affinity preferences
    :geographic_zone,    # Physical deployment zone
    :capabilities        # List of supported operations
  ]
  
  def create_pool_config(opts) do
    %__MODULE__{
      pool_id: opts[:pool_id] || generate_pool_id(),
      pool_type: opts[:pool_type] || :general,
      size: opts[:size] || 4,
      priority: opts[:priority] || :medium,
      sharing_policy: opts[:sharing_policy] || :overflow,
      specialization: opts[:specialization],
      resource_limits: opts[:resource_limits] || default_limits(),
      affinity_rules: opts[:affinity_rules] || %{},
      geographic_zone: opts[:geographic_zone] || :default,
      capabilities: opts[:capabilities] || [:all]
    }
  end
end
```

### 2. Intelligent Load Balancing

#### 2.1 Load Balancing Strategies
```elixir
defmodule DSPex.Python.LoadBalancer do
  @moduledoc """
  Implements multiple load balancing strategies for cross-pool distribution.
  """
  
  @type strategy :: :round_robin | :least_connections | :weighted_round_robin | 
                    :response_time | :resource_aware | :ml_optimized
  
  def select_pool(pools, request, strategy \\ :ml_optimized) do
    case strategy do
      :round_robin ->
        round_robin_selection(pools)
        
      :least_connections ->
        least_connections_selection(pools)
        
      :weighted_round_robin ->
        weighted_selection(pools)
        
      :response_time ->
        fastest_response_selection(pools)
        
      :resource_aware ->
        resource_aware_selection(pools, request)
        
      :ml_optimized ->
        ml_optimized_selection(pools, request)
    end
  end
  
  defp ml_optimized_selection(pools, request) do
    # Use ML model to predict optimal pool based on:
    # - Request type and complexity
    # - Historical performance data
    # - Current pool loads
    # - Worker specializations
    
    pool_scores = Enum.map(pools, fn pool ->
      score = compute_ml_score(pool, request)
      {pool, score}
    end)
    
    {best_pool, _score} = Enum.max_by(pool_scores, fn {_pool, score} -> score end)
    best_pool
  end
  
  defp compute_ml_score(pool, request) do
    # Factors for ML-based pool selection:
    base_score = 1.0
    
    # Pool specialization match
    specialization_score = compute_specialization_match(pool, request)
    
    # Current load factor
    load_score = compute_load_score(pool)
    
    # Historical performance for similar requests
    performance_score = compute_performance_score(pool, request)
    
    # Resource availability
    resource_score = compute_resource_availability(pool)
    
    # Worker health
    health_score = compute_average_worker_health(pool)
    
    # Geographic affinity (if applicable)
    geo_score = compute_geographic_affinity(pool, request)
    
    # Weighted combination
    base_score * 
    (0.25 * specialization_score +
     0.20 * load_score +
     0.20 * performance_score +
     0.15 * resource_score +
     0.15 * health_score +
     0.05 * geo_score)
  end
end
```

#### 2.2 Request Routing Engine
```elixir
defmodule DSPex.Python.RequestRouter do
  @moduledoc """
  Routes requests to optimal pools based on request characteristics.
  """
  
  def route_request(command, args, opts \\ []) do
    # Analyze request characteristics
    request_profile = analyze_request(command, args)
    
    # Get available pools that can handle this request
    candidate_pools = get_candidate_pools(request_profile)
    
    # Apply load balancing strategy
    selected_pool = DSPex.Python.LoadBalancer.select_pool(
      candidate_pools, 
      request_profile,
      opts[:strategy] || :ml_optimized
    )
    
    # Route to selected pool with fallback handling
    case execute_on_pool(selected_pool, command, args, opts) do
      {:ok, result} -> 
        record_successful_routing(selected_pool, request_profile)
        {:ok, result}
        
      {:error, :pool_overloaded} ->
        handle_pool_overload(candidate_pools, command, args, opts)
        
      {:error, reason} ->
        handle_routing_error(candidate_pools, command, args, opts, reason)
    end
  end
  
  defp analyze_request(command, args) do
    %{
      command: command,
      complexity: estimate_complexity(command, args),
      resource_requirements: estimate_resources(command, args),
      expected_duration: estimate_duration(command, args),
      specialization_needed: determine_specialization(command, args),
      session_id: Map.get(args, :session_id),
      priority: Map.get(args, :priority, :normal)
    }
  end
end
```

### 3. Worker Sharing and Migration

#### 3.1 Dynamic Worker Sharing
```elixir
defmodule DSPex.Python.WorkerSharing do
  @moduledoc """
  Manages dynamic worker sharing between pools based on load and policies.
  """
  
  defstruct [
    :sharing_agreements,  # Map of pool_id -> sharing_config
    :borrowed_workers,    # Map of worker_id -> {from_pool, to_pool}
    :sharing_metrics,     # Performance metrics for sharing decisions
    :active_migrations    # Currently active worker migrations
  ]
  
  def enable_sharing_between(pool_a, pool_b, sharing_config) do
    GenServer.call(__MODULE__, {:enable_sharing, pool_a, pool_b, sharing_config})
  end
  
  def request_worker_loan(requesting_pool, donor_pool, requirements) do
    GenServer.call(__MODULE__, {:request_loan, requesting_pool, donor_pool, requirements})
  end
  
  def return_borrowed_worker(worker_id, requesting_pool) do
    GenServer.call(__MODULE__, {:return_worker, worker_id, requesting_pool})
  end
  
  # Automated worker sharing based on load imbalance
  def evaluate_sharing_opportunities do
    pools = DSPex.Python.PoolRegistry.get_all_pools()
    
    # Calculate load imbalance
    load_metrics = Enum.map(pools, fn pool ->
      stats = DSPex.Python.Pool.get_stats(pool.pool_id)
      utilization = stats.busy / max(stats.workers, 1)
      {pool, utilization}
    end)
    
    # Find overloaded and underutilized pools
    {overloaded, underutilized} = categorize_pools_by_load(load_metrics)
    
    # Generate sharing recommendations
    Enum.flat_map(overloaded, fn overloaded_pool ->
      Enum.map(underutilized, fn underutilized_pool ->
        create_sharing_recommendation(overloaded_pool, underutilized_pool)
      end)
    end)
  end
  
  defp create_sharing_recommendation(overloaded_pool, underutilized_pool) do
    workers_to_share = calculate_optimal_sharing_count(overloaded_pool, underutilized_pool)
    
    %{
      from_pool: underutilized_pool.pool_id,
      to_pool: overloaded_pool.pool_id,
      worker_count: workers_to_share,
      expected_benefit: estimate_sharing_benefit(overloaded_pool, underutilized_pool),
      duration_estimate: estimate_sharing_duration(overloaded_pool),
      priority: calculate_sharing_priority(overloaded_pool, underutilized_pool)
    }
  end
end
```

#### 3.2 Live Worker Migration
```elixir
defmodule DSPex.Python.WorkerMigration do
  @moduledoc """
  Handles live migration of workers between pools without dropping connections.
  """
  
  def migrate_worker(worker_id, from_pool, to_pool, opts \\ []) do
    with :ok <- validate_migration_eligibility(worker_id, from_pool, to_pool),
         :ok <- prepare_migration(worker_id, from_pool, to_pool),
         :ok <- execute_migration(worker_id, from_pool, to_pool, opts),
         :ok <- verify_migration_success(worker_id, to_pool) do
      
      # Update registries and monitoring
      update_worker_registry(worker_id, from_pool, to_pool)
      record_migration_metrics(worker_id, from_pool, to_pool)
      
      {:ok, :migration_completed}
    else
      {:error, reason} ->
        rollback_migration(worker_id, from_pool, to_pool)
        {:error, reason}
    end
  end
  
  defp execute_migration(worker_id, from_pool, to_pool, opts) do
    # Strategy depends on migration type
    case opts[:strategy] || :graceful do
      :graceful ->
        graceful_migration(worker_id, from_pool, to_pool)
        
      :immediate ->
        immediate_migration(worker_id, from_pool, to_pool)
        
      :session_aware ->
        session_aware_migration(worker_id, from_pool, to_pool)
    end
  end
  
  defp graceful_migration(worker_id, from_pool, to_pool) do
    # Wait for current requests to complete
    wait_for_worker_idle(worker_id)
    
    # Temporarily block new requests to this worker
    block_new_requests(worker_id)
    
    # Transfer worker registration
    transfer_worker_registration(worker_id, from_pool, to_pool)
    
    # Update pool memberships
    remove_from_pool(worker_id, from_pool)
    add_to_pool(worker_id, to_pool)
    
    # Resume accepting requests
    unblock_requests(worker_id)
  end
end
```

### 4. Session-Aware Pool Selection

#### 4.1 Session Affinity Management
```elixir
defmodule DSPex.Python.SessionAffinity do
  @moduledoc """
  Manages session affinity across multiple pools for optimal performance.
  """
  
  defstruct [
    :session_pool_mappings,  # Map of session_id -> preferred_pool
    :pool_session_counts,    # Map of pool_id -> session_count
    :affinity_rules,         # Rules for session-pool affinity
    :migration_history       # History of session migrations
  ]
  
  def get_preferred_pool(session_id, request_type) do
    case get_existing_affinity(session_id) do
      {:ok, pool_id} ->
        # Verify pool can still handle the request
        if pool_supports_request?(pool_id, request_type) do
          {:ok, pool_id}
        else
          # Need to migrate session to compatible pool
          migrate_session_to_compatible_pool(session_id, request_type)
        end
        
      {:error, :no_affinity} ->
        # First request for this session - select optimal pool
        select_optimal_pool_for_new_session(session_id, request_type)
    end
  end
  
  def establish_session_affinity(session_id, pool_id, strength \\ :normal) do
    affinity_config = %{
      pool_id: pool_id,
      strength: strength,  # :weak | :normal | :strong | :pinned
      established_at: System.system_time(:second),
      request_count: 0,
      last_accessed: System.system_time(:second)
    }
    
    GenServer.call(__MODULE__, {:establish_affinity, session_id, affinity_config})
  end
  
  defp migrate_session_to_compatible_pool(session_id, request_type) do
    # Find pools that support the new request type
    compatible_pools = find_compatible_pools(request_type)
    
    # Select best pool considering current load and session data
    new_pool = select_migration_target(session_id, compatible_pools)
    
    # Migrate session data if needed
    with :ok <- migrate_session_data(session_id, new_pool),
         :ok <- update_affinity_mapping(session_id, new_pool) do
      {:ok, new_pool}
    end
  end
end
```

#### 4.2 Cross-Pool Session Management
```elixir
defmodule DSPex.Python.CrossPoolSessionManager do
  @moduledoc """
  Manages sessions that span multiple pools and coordinates session data.
  """
  
  def execute_in_session_cross_pool(session_id, command, args, opts \\ []) do
    # Determine optimal pool for this specific request
    pool_selector = opts[:pool_selector] || :affinity_aware
    
    target_pool = case pool_selector do
      :affinity_aware ->
        DSPex.Python.SessionAffinity.get_preferred_pool(session_id, command)
        
      :performance_optimized ->
        DSPex.Python.RequestRouter.route_request(command, args, 
          session_context: get_session_context(session_id))
        
      specific_pool when is_atom(specific_pool) ->
        {:ok, specific_pool}
    end
    
    case target_pool do
      {:ok, pool_id} ->
        # Ensure session data is available in target pool
        ensure_session_data_available(session_id, pool_id)
        
        # Execute request with session context
        DSPex.Python.Pool.execute_in_session(
          session_id, command, args, 
          Keyword.put(opts, :pool, pool_id)
        )
        
      {:error, reason} ->
        {:error, {:pool_selection_failed, reason}}
    end
  end
  
  defp ensure_session_data_available(session_id, pool_id) do
    # Check if session data exists in target pool
    case check_session_data_availability(session_id, pool_id) do
      :available -> 
        :ok
        
      :partial ->
        # Synchronize missing session data
        synchronize_session_data(session_id, pool_id)
        
      :missing ->
        # Create new session context in target pool
        create_session_context(session_id, pool_id)
    end
  end
end
```

## 🔧 Configuration and Integration

### 1. Multi-Pool Configuration
```elixir
# config/config.exs
config :dspex, DSPex.Python.MultiPool,
  # Pool definitions
  pools: [
    %{
      pool_id: :general_pool,
      pool_type: :general,
      size: 8,
      priority: :medium,
      sharing_policy: :overflow,
      capabilities: [:all]
    },
    %{
      pool_id: :embedding_pool,
      pool_type: :embedding,
      size: 4,
      priority: :high,
      sharing_policy: :strict,
      specialization: "text-embedding-ada-002",
      capabilities: [:embedding, :similarity, :clustering]
    },
    %{
      pool_id: :generation_pool,
      pool_type: :generation,
      size: 6,
      priority: :high,
      sharing_policy: :adaptive,
      specialization: "gpt-4",
      capabilities: [:generation, :completion, :reasoning]
    }
  ],
  
  # Load balancing configuration
  load_balancing: %{
    strategy: :ml_optimized,
    rebalance_interval: 30_000,     # 30 seconds
    worker_sharing_enabled: true,
    migration_threshold: 0.7        # Migrate when pool >70% utilized
  },
  
  # Session affinity configuration
  session_affinity: %{
    default_strength: :normal,
    affinity_timeout: 3600,         # 1 hour
    cross_pool_migration: true,
    session_data_sync: :lazy        # :eager | :lazy | :manual
  },
  
  # Worker sharing policies
  worker_sharing: %{
    max_shared_percentage: 0.3,     # Max 30% of workers can be shared
    sharing_duration_limit: 300,    # 5 minutes max sharing
    return_threshold: 0.4,          # Return workers when donor pool >40% utilized
    compatibility_check: true       # Verify worker compatibility before sharing
  }
```

### 2. Enhanced Pool Supervisor
```elixir
defmodule DSPex.Python.MultiPoolSupervisor do
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    pool_configs = Application.get_env(:dspex, DSPex.Python.MultiPool)[:pools]
    
    # Core infrastructure
    core_children = [
      {DSPex.Python.PoolRegistry, []},
      {DSPex.Python.LoadBalancer, []},
      {DSPex.Python.WorkerSharing, []},
      {DSPex.Python.SessionAffinity, []},
      {DSPex.Python.CrossPoolSessionManager, []}
    ]
    
    # Dynamic pool children
    pool_children = Enum.map(pool_configs, fn config ->
      pool_spec = {DSPex.Python.Pool, [
        name: config.pool_id,
        size: config.size,
        pool_config: config
      ]}
      
      Supervisor.child_spec(pool_spec, id: config.pool_id)
    end)
    
    children = core_children ++ pool_children
    
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
```

## 📊 Performance and Monitoring

### 1. Cross-Pool Metrics
```elixir
defmodule DSPex.Python.MultiPoolMetrics do
  def get_comprehensive_metrics do
    %{
      pool_distribution: get_pool_distribution_metrics(),
      load_balancing: get_load_balancing_metrics(),
      worker_sharing: get_worker_sharing_metrics(),
      session_affinity: get_session_affinity_metrics(),
      cross_pool_performance: get_cross_pool_performance()
    }
  end
  
  defp get_load_balancing_metrics do
    %{
      routing_decisions: get_routing_decision_stats(),
      pool_utilization_variance: calculate_pool_utilization_variance(),
      load_balancing_efficiency: calculate_load_balancing_efficiency(),
      request_distribution: get_request_distribution_by_pool(),
      average_response_time_by_pool: get_response_times_by_pool()
    }
  end
  
  defp get_worker_sharing_metrics do
    %{
      active_sharing_agreements: count_active_sharing(),
      workers_currently_shared: count_shared_workers(),
      sharing_efficiency: calculate_sharing_efficiency(),
      migration_success_rate: calculate_migration_success_rate(),
      sharing_duration_stats: get_sharing_duration_statistics()
    }
  end
end
```

### 2. Telemetry Events
```elixir
# Cross-pool load balancing events
:telemetry.execute(
  [:dspex, :multipool, :request_routed],
  %{pool_id: pool_id, routing_time: time, strategy: strategy},
  %{request_type: type, complexity: complexity}
)

# Worker sharing events
:telemetry.execute(
  [:dspex, :multipool, :worker_shared],
  %{worker_id: id, from_pool: from, to_pool: to, duration: duration},
  %{sharing_reason: reason, efficiency_gain: gain}
)

# Session affinity events
:telemetry.execute(
  [:dspex, :multipool, :session_migrated],
  %{session_id: id, from_pool: from, to_pool: to, reason: reason},
  %{migration_time: time, data_size: size}
)
```

## 🧪 Testing Strategy

### 1. Multi-Pool Load Testing
```elixir
defmodule DSPex.Python.MultiPoolLoadTest do
  use ExUnit.Case, async: false
  
  test "load balancing distributes requests efficiently" do
    # Start multiple pools with different capabilities
    start_multi_pool_setup()
    
    # Generate mixed workload
    tasks = generate_mixed_workload(1000)
    
    # Execute concurrent requests
    results = Task.await_many(tasks, 60_000)
    
    # Verify load distribution
    distribution = analyze_request_distribution()
    assert_balanced_distribution(distribution)
  end
  
  test "worker sharing improves overall throughput" do
    # Create load imbalance scenario
    {overloaded_pool, underutilized_pool} = create_load_imbalance()
    
    # Enable worker sharing
    enable_worker_sharing(overloaded_pool, underutilized_pool)
    
    # Verify throughput improvement
    before_throughput = measure_throughput(overloaded_pool)
    
    # Allow sharing to take effect
    Process.sleep(5_000)
    
    after_throughput = measure_throughput(overloaded_pool)
    assert after_throughput > before_throughput * 1.2  # 20% improvement
  end
end
```

### 2. Session Affinity Testing
```elixir
defmodule DSPex.Python.SessionAffinityTest do
  test "session maintains affinity across requests" do
    session_id = "test_session_#{:rand.uniform(1000)}"
    
    # First request establishes affinity
    {:ok, _result} = DSPex.Python.CrossPoolSessionManager.execute_in_session_cross_pool(
      session_id, "create_program", %{id: "test_program"}
    )
    
    initial_pool = get_session_affinity(session_id)
    
    # Subsequent requests should use same pool (unless forced migration)
    for _i <- 1..10 do
      {:ok, _result} = DSPex.Python.CrossPoolSessionManager.execute_in_session_cross_pool(
        session_id, "execute_program", %{program_id: "test_program"}
      )
      
      current_pool = get_session_affinity(session_id)
      assert current_pool == initial_pool
    end
  end
end
```

## 🚀 Migration Strategy

### 1. Phased Implementation
1. **Phase 1**: Basic multi-pool support (parallel pools, no sharing)
2. **Phase 2**: Load balancing and request routing
3. **Phase 3**: Worker sharing and migration
4. **Phase 4**: Advanced session affinity and optimization

### 2. Backwards Compatibility
- Single-pool API remains fully functional
- Existing sessions continue to work unchanged
- Gradual migration of sessions to multi-pool system
- Configuration-driven feature enablement

## 📈 Expected Benefits

### 1. Performance Improvements
- **40% better resource utilization** through worker sharing
- **25% reduction in average response time** via optimal routing
- **60% improvement in peak load handling** through load distribution

### 2. Scalability Enhancements
- Support for specialized worker pools
- Horizontal scaling through pool addition
- Geographic distribution capabilities

### 3. Operational Benefits
- Fine-grained resource allocation control
- Better isolation between workload types
- Improved system resilience through redundancy

---

**Next Document**: [Dynamic Pool Scaling and Adaptive Resource Management](./03_dynamic_pool_scaling.md)
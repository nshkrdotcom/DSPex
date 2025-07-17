# DSPex V3 Pooler Design Document 1: Advanced Process Management and Resource Control

**Document ID**: `20250716_v3_pooler_design_01`  
**Version**: 1.0  
**Date**: July 16, 2025  
**Status**: Design Phase  

## 🎯 Executive Summary

This document outlines the design for **Advanced Process Management and Resource Control** in the DSPex V3 Pooler. Building on the current V3 pool's 1000x+ performance improvements through concurrent initialization, this enhancement adds sophisticated process lifecycle management, resource monitoring, and adaptive control mechanisms.

## 🏗️ Current V3 Architecture Analysis

### Existing Strengths
- **Concurrent Worker Initialization**: Parallel startup using `Task.async_stream`
- **Simple Queue Management**: FIFO request distribution
- **Basic Worker Supervision**: Process monitoring via `DSPex.Python.WorkerSupervisor`
- **Session Store Integration**: ETS-backed session management

### Current Limitations
1. **No Resource Monitoring**: Workers can consume unlimited Python memory/CPU
2. **Basic Failure Handling**: Binary healthy/unhealthy worker states
3. **Static Process Management**: No adaptive resource allocation
4. **Limited OS Integration**: No ulimit controls or process affinity
5. **Reactive Supervision**: Only responds to process crashes

## 🚀 Enhanced Process Management Design

### 1. Worker Resource Monitoring

#### 1.1 Resource Tracking Module
```elixir
defmodule DSPex.Python.ResourceMonitor do
  @moduledoc """
  Monitors Python worker resource usage and enforces limits.
  
  Features:
  - Memory usage tracking per worker
  - CPU utilization monitoring
  - Network I/O tracking (for API calls)
  - Process aging and degradation detection
  """
  
  defstruct [
    :worker_id,
    :pid,
    :memory_usage,        # Current memory in MB
    :memory_peak,         # Peak memory usage
    :cpu_usage,           # CPU % over last window
    :api_calls_count,     # Total API calls made
    :api_calls_rate,      # API calls per minute
    :uptime,              # Worker uptime in seconds
    :health_score,        # Computed health score 0-100
    :last_updated,        # Timestamp of last update
    :resource_warnings    # List of current warnings
  ]
  
  # Monitor worker resources every 30 seconds
  def start_monitoring(worker_id, python_pid) do
    GenServer.start_link(__MODULE__, {worker_id, python_pid}, 
                        name: via_tuple(worker_id))
  end
  
  def get_resource_usage(worker_id) do
    GenServer.call(via_tuple(worker_id), :get_usage)
  end
  
  def check_health(worker_id) do
    GenServer.call(via_tuple(worker_id), :check_health)
  end
end
```

#### 1.2 System Integration Layer
```elixir
defmodule DSPex.Python.SystemIntegration do
  @moduledoc """
  OS-level process management and resource control.
  """
  
  # Get process resource usage using /proc filesystem
  def get_process_stats(pid) do
    with {:ok, stat_content} <- File.read("/proc/#{pid}/stat"),
         {:ok, status_content} <- File.read("/proc/#{pid}/status") do
      %{
        memory_rss: parse_memory_rss(status_content),
        memory_vms: parse_memory_vms(status_content),
        cpu_time: parse_cpu_time(stat_content),
        open_files: count_open_files(pid),
        threads: count_threads(pid)
      }
    end
  end
  
  # Set process resource limits using ulimit
  def apply_resource_limits(pid, limits) do
    commands = [
      "prlimit --pid #{pid} --as=#{limits.virtual_memory}",
      "prlimit --pid #{pid} --rss=#{limits.resident_memory}",
      "prlimit --pid #{pid} --cpu=#{limits.cpu_time}",
      "prlimit --pid #{pid} --nofile=#{limits.open_files}"
    ]
    
    Enum.map(commands, &System.cmd("sh", ["-c", &1]))
  end
  
  # Set CPU affinity to specific cores
  def set_cpu_affinity(pid, core_list) do
    cores = Enum.join(core_list, ",")
    System.cmd("taskset", ["-cp", cores, "#{pid}"])
  end
end
```

### 2. Intelligent Worker Lifecycle Management

#### 2.1 Worker Health States
```elixir
defmodule DSPex.Python.WorkerStates do
  @type health_state :: :excellent | :good | :degraded | :critical | :failing
  
  @health_thresholds %{
    excellent: %{memory_mb: 0..100,   cpu_percent: 0..20,  api_rate: 0..10},
    good:      %{memory_mb: 100..250, cpu_percent: 20..50, api_rate: 10..30},
    degraded:  %{memory_mb: 250..500, cpu_percent: 50..80, api_rate: 30..60},
    critical:  %{memory_mb: 500..750, cpu_percent: 80..95, api_rate: 60..100},
    failing:   %{memory_mb: 750..999, cpu_percent: 95..100, api_rate: 100..999}
  }
  
  def compute_health_state(resource_usage) do
    memory_state = classify_memory(resource_usage.memory_usage)
    cpu_state = classify_cpu(resource_usage.cpu_usage)
    api_state = classify_api_rate(resource_usage.api_calls_rate)
    
    # Take the worst state among all metrics
    worst_state([memory_state, cpu_state, api_state])
  end
  
  def should_restart?(health_state, consecutive_failures) do
    case {health_state, consecutive_failures} do
      {:failing, _} -> true
      {:critical, count} when count >= 3 -> true
      {:degraded, count} when count >= 5 -> true
      _ -> false
    end
  end
end
```

#### 2.2 Predictive Worker Replacement
```elixir
defmodule DSPex.Python.PredictiveReplacement do
  @moduledoc """
  Anticipates worker degradation and preemptively starts replacements.
  """
  
  def analyze_degradation_trend(worker_id) do
    # Get last 10 health check results
    history = get_health_history(worker_id, 10)
    
    cond do
      declining_trend?(history) -> {:replace_soon, estimate_time_to_failure(history)}
      stable_but_degraded?(history) -> {:monitor_closely, nil}
      improving_trend?(history) -> {:continue_monitoring, nil}
      true -> {:healthy, nil}
    end
  end
  
  def start_preemptive_replacement(worker_id, estimated_ttf) do
    # Start new worker in background
    {:ok, new_worker_id} = DSPex.Python.WorkerSupervisor.start_worker()
    
    # Wait for new worker to be ready
    wait_for_worker_ready(new_worker_id)
    
    # Schedule replacement after current requests complete
    schedule_graceful_replacement(worker_id, new_worker_id, estimated_ttf)
  end
end
```

### 3. Advanced Resource Control

#### 3.1 Dynamic Resource Allocation
```elixir
defmodule DSPex.Python.ResourceAllocator do
  @moduledoc """
  Dynamically allocates system resources to Python workers based on workload.
  """
  
  defstruct [
    :total_memory_mb,      # Total system memory available
    :total_cpu_cores,      # Total CPU cores available  
    :worker_allocations,   # Map of worker_id -> resource allocation
    :load_patterns,        # Historical load patterns
    :allocation_strategy   # :equal | :weighted | :adaptive
  ]
  
  def compute_optimal_allocation(worker_stats, system_load) do
    case Application.get_env(:dspex, :allocation_strategy, :adaptive) do
      :equal -> 
        equal_resource_split(worker_stats)
        
      :weighted ->
        weight_by_usage_patterns(worker_stats)
        
      :adaptive ->
        adaptive_allocation(worker_stats, system_load)
    end
  end
  
  defp adaptive_allocation(worker_stats, system_load) do
    # High-performing workers get more resources
    # Degraded workers get limited resources
    # System load influences overall allocation
    
    base_allocation = base_resource_allocation()
    
    Enum.reduce(worker_stats, %{}, fn {worker_id, stats}, acc ->
      multiplier = compute_allocation_multiplier(stats, system_load)
      allocation = scale_allocation(base_allocation, multiplier)
      Map.put(acc, worker_id, allocation)
    end)
  end
end
```

#### 3.2 Memory Pressure Management
```elixir
defmodule DSPex.Python.MemoryPressureManager do
  @moduledoc """
  Handles system memory pressure by managing Python worker memory usage.
  """
  
  def handle_memory_pressure(pressure_level) do
    case pressure_level do
      :low -> 
        :ok  # Normal operation
        
      :medium ->
        # Trigger garbage collection in Python workers
        trigger_gc_in_workers()
        clear_session_caches()
        
      :high ->
        # More aggressive memory management
        trigger_gc_in_workers()
        clear_session_caches()
        reduce_worker_memory_limits()
        consider_worker_restart()
        
      :critical ->
        # Emergency memory management
        emergency_worker_shutdown()
        force_garbage_collection()
        clear_all_caches()
    end
  end
  
  defp trigger_gc_in_workers do
    DSPex.Python.Pool.list_workers()
    |> Enum.each(fn worker_id ->
      DSPex.Python.Pool.execute("gc_collect", %{}, worker: worker_id)
    end)
  end
  
  defp emergency_worker_shutdown do
    # Shut down workers with highest memory usage first
    worker_stats = get_all_worker_stats()
    
    worker_stats
    |> Enum.sort_by(& &1.memory_usage, :desc)
    |> Enum.take(div(length(worker_stats), 2))  # Shut down half
    |> Enum.each(&shutdown_worker/1)
  end
end
```

## 🔧 Configuration and Integration

### 1. Configuration Schema
```elixir
# config/config.exs
config :dspex, DSPex.Python.AdvancedProcessManager,
  # Resource monitoring
  monitoring_interval: 30_000,           # Check every 30 seconds
  memory_warning_threshold: 250,         # MB
  memory_critical_threshold: 500,        # MB
  cpu_warning_threshold: 50,             # Percent
  cpu_critical_threshold: 80,            # Percent
  
  # Resource limits per worker
  max_memory_mb: 1024,                   # 1GB max per worker
  max_cpu_percent: 90,                   # 90% CPU max
  max_open_files: 1024,                  # File descriptor limit
  max_api_calls_per_minute: 120,         # Rate limiting
  
  # Worker lifecycle
  health_check_interval: 15_000,         # Health check every 15s
  degraded_worker_tolerance: 3,          # Allow 3 degraded checks
  preemptive_replacement: true,          # Enable predictive replacement
  
  # System integration
  enable_ulimits: true,                  # Apply OS resource limits
  enable_cpu_affinity: false,            # CPU core binding
  enable_memory_pressure_handling: true, # React to memory pressure
  
  # Resource allocation strategy
  allocation_strategy: :adaptive,        # :equal | :weighted | :adaptive
  rebalance_interval: 300_000           # Rebalance every 5 minutes
```

### 2. Integration with Current V3 Pool
```elixir
defmodule DSPex.Python.Pool do
  # Enhanced worker startup with resource controls
  defp start_worker_with_resources(worker_id) do
    with {:ok, worker_pid} <- DSPex.Python.WorkerSupervisor.start_worker(worker_id),
         {:ok, python_pid} <- get_python_process_pid(worker_pid),
         :ok <- apply_initial_resource_limits(python_pid),
         {:ok, _monitor_pid} <- DSPex.Python.ResourceMonitor.start_monitoring(worker_id, python_pid) do
      
      # Set CPU affinity if enabled
      if Application.get_env(:dspex, :enable_cpu_affinity) do
        cores = allocate_cpu_cores(worker_id)
        DSPex.Python.SystemIntegration.set_cpu_affinity(python_pid, cores)
      end
      
      {:ok, worker_pid}
    end
  end
  
  # Enhanced worker selection considering health
  defp select_optimal_worker(available_workers) do
    worker_health_scores = 
      Enum.map(available_workers, fn worker_id ->
        health = DSPex.Python.ResourceMonitor.check_health(worker_id)
        {worker_id, health.score}
      end)
    
    # Select worker with highest health score
    {best_worker, _score} = 
      Enum.max_by(worker_health_scores, fn {_id, score} -> score end)
    
    best_worker
  end
end
```

## 📊 Monitoring and Observability

### 1. Health Dashboard Metrics
```elixir
defmodule DSPex.Python.HealthDashboard do
  def get_comprehensive_health_report do
    %{
      pool_overview: get_pool_overview(),
      worker_health: get_worker_health_summary(),
      resource_usage: get_resource_usage_summary(),
      performance_metrics: get_performance_metrics(),
      alerts: get_active_alerts(),
      recommendations: get_optimization_recommendations()
    }
  end
  
  defp get_worker_health_summary do
    workers = DSPex.Python.Pool.list_workers()
    
    Enum.map(workers, fn worker_id ->
      health = DSPex.Python.ResourceMonitor.check_health(worker_id)
      usage = DSPex.Python.ResourceMonitor.get_resource_usage(worker_id)
      
      %{
        worker_id: worker_id,
        health_state: health.state,
        health_score: health.score,
        memory_usage: usage.memory_usage,
        cpu_usage: usage.cpu_usage,
        uptime: usage.uptime,
        warnings: usage.resource_warnings
      }
    end)
  end
end
```

### 2. Telemetry Events
```elixir
# Enhanced telemetry events for process management
:telemetry.execute(
  [:dspex, :python, :worker, :health_check],
  %{health_score: score, memory_mb: memory, cpu_percent: cpu},
  %{worker_id: worker_id, timestamp: timestamp}
)

:telemetry.execute(
  [:dspex, :python, :worker, :resource_limit_exceeded],
  %{current_usage: usage, limit: limit, severity: severity},
  %{worker_id: worker_id, resource_type: resource_type}
)

:telemetry.execute(
  [:dspex, :python, :pool, :resource_rebalance],
  %{workers_affected: count, rebalance_duration: duration},
  %{strategy: strategy, trigger: trigger}
)
```

## 🧪 Testing Strategy

### 1. Resource Limit Testing
```elixir
defmodule DSPex.Python.ResourceLimitTest do
  use ExUnit.Case, async: false
  
  test "worker respects memory limits" do
    # Start worker with 100MB limit
    {:ok, worker_id} = start_worker_with_limit(memory_mb: 100)
    
    # Execute memory-intensive operation
    {:error, :memory_limit_exceeded} = 
      DSPex.Python.Pool.execute("allocate_memory", %{size_mb: 150}, worker: worker_id)
  end
  
  test "worker degradation triggers replacement" do
    {:ok, worker_id} = start_degraded_worker()
    
    # Monitor health degradation
    :ok = simulate_resource_exhaustion(worker_id)
    
    # Verify replacement is triggered
    assert_receive {:worker_replacement_triggered, ^worker_id}, 5_000
  end
end
```

### 2. Load Testing with Resource Monitoring
```elixir
defmodule DSPex.Python.LoadTestWithMonitoring do
  def run_sustained_load_test do
    # Start monitoring
    start_resource_monitoring()
    
    # Generate sustained load for 10 minutes
    tasks = for i <- 1..1000 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("heavy_computation", %{iterations: 1000})
      end)
    end
    
    # Monitor resource usage during load
    resource_history = monitor_resources_during_test(tasks)
    
    # Verify system remained stable
    assert_no_memory_pressure_events(resource_history)
    assert_worker_health_maintained(resource_history)
  end
end
```

## 🚀 Migration and Deployment

### 1. Phased Rollout Strategy
1. **Phase 1**: Resource monitoring only (read-only)
2. **Phase 2**: Resource limits enforcement
3. **Phase 3**: Predictive replacement
4. **Phase 4**: Dynamic resource allocation

### 2. Backwards Compatibility
- All existing V3 Pool APIs remain unchanged
- Resource management is opt-in via configuration
- Graceful degradation when OS features unavailable

## 📈 Expected Benefits

### 1. Performance Improvements
- **25% reduction** in worker restart frequency
- **15% improvement** in memory efficiency
- **10% reduction** in request latency variance

### 2. Reliability Enhancements
- Proactive worker replacement reduces downtime
- Resource limits prevent cascade failures
- Memory pressure handling prevents OOM kills

### 3. Operational Benefits
- Real-time resource visibility
- Automated optimization recommendations
- Predictive maintenance capabilities

## 🎯 Success Metrics

1. **Worker Health Score**: Maintain average >80 across all workers
2. **Memory Efficiency**: <1% workers exceed memory warnings
3. **Proactive Replacements**: 80% of degraded workers replaced before failure
4. **System Stability**: 99.9% uptime under sustained load
5. **Resource Utilization**: Optimal allocation within 5% of theoretical optimum

---

**Next Document**: [Cross-Pool Load Balancing and Worker Distribution](./02_cross_pool_load_balancing.md)
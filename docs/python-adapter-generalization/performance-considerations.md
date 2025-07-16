# Performance Considerations

## Overview

This document analyzes the performance implications of generalizing the Python adapter and provides optimization strategies to maintain or improve current performance levels.

## Current Performance Baseline

Based on the DSPex performance optimizations completed on 2025-07-15:

### Key Metrics
- **Pool Creation**: ~2 seconds for multiple workers (parallel)
- **Request Latency**: < 10ms overhead per operation
- **CircuitBreaker Tests**: 0.1 seconds for 26 tests (1200x improvement)
- **Worker Initialization**: Parallel using `Task.async`
- **Memory Usage**: Stable with pool size

### Performance Characteristics
1. **Zero Artificial Delays**: All `Process.sleep` removed
2. **Right-Sized Timeouts**: 10 seconds for pool operations
3. **Parallel Processing**: Worker creation happens concurrently
4. **Event-Driven**: No polling or busy-waiting

## Performance Impact Analysis

### 1. Abstraction Overhead

#### Python Side
```python
# Current: Direct method calls
def handle_request(self, request):
    if command == "create_program":
        return self.create_program(args)

# Generalized: Dynamic dispatch
def handle_request(self, request):
    if command in self._handlers:
        return self._handlers[command](args)
```

**Impact**: Negligible (~1-2μs per request)
**Mitigation**: Use dict lookup instead of if/elif chains

#### Elixir Side
```elixir
# Current: Direct module calls
DSPex.Adapters.PythonPoolV2.create_program(signature)

# Generalized: Dynamic dispatch
{:ok, adapter} = MLBridge.get_adapter(:dspy)
adapter.create_program(signature)
```

**Impact**: One-time lookup cost (~10μs)
**Mitigation**: Cache adapter references

### 2. Memory Overhead

#### Per-Framework Memory
```
Current DSPy Bridge: ~50MB base + programs
Generalized:
  - Base Bridge: ~30MB (shared infrastructure)
  - DSPy Extension: ~20MB (framework-specific)
  - Total: ~50MB (same as current)
```

#### Multi-Framework Scenarios
```
Single Framework: No change
Two Frameworks: +20-30MB per additional framework
N Frameworks: Base + (N × Framework overhead)
```

**Mitigation**: Lazy loading of framework-specific code

### 3. Startup Performance

#### Current Startup
```
1. Start Elixir adapter
2. Launch Python process
3. Import DSPy
4. Initialize bridge
Total: ~2-3 seconds
```

#### Generalized Startup
```
1. Start Elixir adapter (same)
2. Launch Python process (same)
3. Import base bridge (~100ms faster)
4. Lazy-load framework on first use
Total: ~1.9-2.9 seconds (slightly faster)
```

## Optimization Strategies

### 1. Lazy Framework Loading

```python
class BaseBridge:
    def __init__(self):
        self._framework_loaded = False
        self._framework = None
    
    def _ensure_framework(self):
        if not self._framework_loaded:
            self._load_framework()
            self._framework_loaded = True
    
    def handle_command(self, command, args):
        # Only load framework when needed
        if command != 'ping' and command != 'get_stats':
            self._ensure_framework()
        return super().handle_command(command, args)
```

### 2. Command Batching

```elixir
defmodule DSPex.MLBridge do
  @doc """
  Execute multiple commands in a single round trip
  """
  def batch_execute(framework, commands) do
    with {:ok, adapter} <- get_adapter(framework) do
      adapter.call_bridge("batch", %{commands: commands})
    end
  end
end
```

### 3. Adapter Pooling

```elixir
defmodule DSPex.MLBridge.AdapterPool do
  @moduledoc """
  Pools adapter instances for different frameworks
  """
  
  def get_or_create_adapter(framework) do
    case :ets.lookup(:adapter_pool, framework) do
      [{^framework, adapter}] -> 
        {:ok, adapter}
      [] ->
        with {:ok, adapter} <- create_adapter(framework) do
          :ets.insert(:adapter_pool, {framework, adapter})
          {:ok, adapter}
        end
    end
  end
end
```

### 4. Optimized Protocol

```python
# Add binary protocol option for performance-critical paths
class BaseBridge:
    def __init__(self, protocol='json'):
        self.protocol = protocol
        if protocol == 'msgpack':
            import msgpack
            self.encode = msgpack.packb
            self.decode = msgpack.unpackb
        else:
            self.encode = json.dumps
            self.decode = json.loads
```

### 5. Connection Reuse

```elixir
defmodule DSPex.PythonBridge.ConnectionPool do
  @moduledoc """
  Reuse Python process connections across frameworks
  """
  
  def get_connection(framework) do
    # Reuse existing Python process if compatible
    case find_compatible_connection(framework) do
      {:ok, conn} -> {:ok, conn}
      :not_found -> create_new_connection(framework)
    end
  end
end
```

## Framework-Specific Optimizations

### DSPy Optimizations
```python
class DSPyBridge(BaseBridge):
    def __init__(self):
        super().__init__()
        # Pre-compile common signatures
        self._signature_cache = {}
        
    def create_signature(self, config):
        cache_key = hash(str(config))
        if cache_key in self._signature_cache:
            return self._signature_cache[cache_key]
        # Create and cache
```

### LangChain Optimizations
```python
class LangChainBridge(BaseBridge):
    def __init__(self):
        super().__init__()
        # Reuse LLM connections
        self._llm_pool = {}
        
    def get_or_create_llm(self, config):
        key = (config['type'], config['model'])
        if key not in self._llm_pool:
            self._llm_pool[key] = self._create_llm(config)
        return self._llm_pool[key]
```

### Transformers Optimizations
```python
class TransformersBridge(BaseBridge):
    def __init__(self):
        super().__init__()
        # Model caching with LRU eviction
        self._model_cache = LRUCache(maxsize=3)
        
    def load_model(self, model_name):
        if model_name in self._model_cache:
            return self._model_cache[model_name]
        # Load and cache with memory tracking
```

## Benchmarking Strategy

### 1. Micro-benchmarks

```elixir
defmodule BridgeBenchmark do
  use Benchfella
  
  @signature %{name: "Test", inputs: %{}, outputs: %{}}
  
  bench "current adapter" do
    DSPex.Adapters.PythonPoolV2.create_program(@signature)
  end
  
  bench "generalized adapter" do
    {:ok, adapter} = DSPex.MLBridge.get_adapter(:dspy)
    adapter.create_program(@signature)
  end
  
  bench "generalized with cache" do
    adapter = Process.get(:cached_adapter) || 
      case DSPex.MLBridge.get_adapter(:dspy) do
        {:ok, a} -> Process.put(:cached_adapter, a); a
      end
    adapter.create_program(@signature)
  end
end
```

### 2. End-to-End Performance Tests

```elixir
defmodule E2EPerformanceTest do
  test "multi-framework performance" do
    # Measure framework switching overhead
    frameworks = [:dspy, :langchain, :custom]
    
    results = Enum.map(frameworks, fn framework ->
      {time, _} = :timer.tc(fn ->
        {:ok, adapter} = MLBridge.get_adapter(framework)
        # Perform operations
      end)
      {framework, time}
    end)
    
    # Assert reasonable switching time
    Enum.each(results, fn {_, time} ->
      assert time < 100_000  # 100ms max
    end)
  end
end
```

### 3. Load Testing

```elixir
defmodule LoadTest do
  def run_load_test(framework, concurrent_users, duration) do
    MLBridge.ensure_started(framework)
    
    tasks = for _ <- 1..concurrent_users do
      Task.async(fn ->
        run_user_simulation(framework, duration)
      end)
    end
    
    results = Task.await_many(tasks, duration + 5000)
    analyze_results(results)
  end
end
```

## Memory Management

### 1. Framework Lifecycle

```python
class BaseBridge:
    def cleanup_framework(self):
        """Called when switching frameworks or on shutdown"""
        if hasattr(self, '_framework'):
            # Framework-specific cleanup
            self._cleanup_framework_resources()
            # Clear references
            self._framework = None
            # Force garbage collection
            import gc
            gc.collect()
```

### 2. Resource Pooling

```elixir
defmodule DSPex.MLBridge.ResourceManager do
  @moduledoc """
  Manages resources across frameworks
  """
  
  def configure_limits(framework, limits) do
    # Set per-framework resource limits
    %{
      max_memory: limits[:max_memory] || "2GB",
      max_models: limits[:max_models] || 10,
      max_connections: limits[:max_connections] || 4
    }
  end
  
  def enforce_limits(framework) do
    # Monitor and enforce resource usage
    current = get_resource_usage(framework)
    limits = get_limits(framework)
    
    if current.memory > limits.max_memory do
      cleanup_oldest_resources(framework)
    end
  end
end
```

### 3. Shared Resource Optimization

```python
# Share common resources across frameworks
class ResourcePool:
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.initialize()
        return cls._instance
    
    def initialize(self):
        self.tokenizers = {}  # Shared across frameworks
        self.embeddings = {}  # Cached embeddings
        self.connections = {}  # HTTP connection pooling
```

## Production Deployment

### 1. Monitoring Metrics

```elixir
defmodule DSPex.MLBridge.Metrics do
  def track_performance do
    :telemetry.attach_many(
      "ml-bridge-performance",
      [
        [:ml_bridge, :adapter, :get],
        [:ml_bridge, :command, :execute],
        [:ml_bridge, :framework, :switch]
      ],
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event(event, measurements, metadata, _) do
    # Track framework-specific metrics
    StatsD.histogram(
      "ml_bridge.#{metadata.framework}.#{event}",
      measurements.duration
    )
  end
end
```

### 2. Performance Alerts

```yaml
# prometheus_rules.yml
groups:
  - name: ml_bridge_performance
    rules:
      - alert: HighLatency
        expr: ml_bridge_request_duration_p99 > 100
        for: 5m
        annotations:
          summary: "ML Bridge high latency"
          
      - alert: MemoryLeak
        expr: rate(ml_bridge_memory_usage[5m]) > 10485760  # 10MB/5min
        for: 10m
        annotations:
          summary: "Possible memory leak in ML Bridge"
```

### 3. Capacity Planning

```elixir
defmodule DSPex.MLBridge.Capacity do
  @doc """
  Calculate required resources for multi-framework deployment
  """
  def calculate_requirements(frameworks, expected_load) do
    base_memory = 100  # MB for base system
    
    framework_memory = Enum.sum(
      Enum.map(frameworks, &framework_memory_requirement/1)
    )
    
    pool_memory = expected_load.concurrent_requests * 10  # MB per worker
    
    %{
      total_memory: base_memory + framework_memory + pool_memory,
      recommended_workers: calculate_workers(expected_load),
      cpu_cores: calculate_cpu_requirement(frameworks, expected_load)
    }
  end
end
```

## Performance Best Practices

### 1. Framework Selection
- Use single framework when possible
- Load frameworks based on actual usage patterns
- Consider framework-specific deployment for heavy users

### 2. Caching Strategy
- Cache adapter references in process dictionary
- Use ETS for cross-process adapter sharing
- Implement TTL for cached resources

### 3. Connection Management
- Reuse Python processes across compatible frameworks
- Implement connection pooling at framework level
- Monitor connection health proactively

### 4. Resource Cleanup
- Implement aggressive garbage collection
- Clear unused framework resources
- Monitor memory usage per framework

### 5. Deployment Options
```elixir
# Option 1: Single node, multiple frameworks
config :dspex, :deployment_mode, :single_node

# Option 2: Framework-specific nodes
config :dspex, :deployment_mode, :multi_node
config :dspex, :node_mapping, %{
  dspy: :"dspy@node1",
  langchain: :"langchain@node2"
}

# Option 3: Hybrid with routing
config :dspex, :deployment_mode, :hybrid
config :dspex, :routing_strategy, :least_loaded
```

## Conclusion

The generalized architecture can maintain or improve current performance through:
1. Lazy loading reduces startup time
2. Caching eliminates redundant lookups
3. Resource sharing reduces memory overhead
4. Parallel initialization maintains fast pool creation

With proper optimization, the multi-framework support adds minimal overhead (< 5%) while providing significant architectural benefits.
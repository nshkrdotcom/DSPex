# DSPex to Snakepit Migration Guide

## Overview

This guide provides a detailed migration strategy for transitioning DSPex's Python bridge functionality to Snakepit while preserving all advanced features and maintaining backward compatibility.

## Migration Principles

1. **Zero Breaking Changes**: All existing DSPex APIs remain functional
2. **Feature Preservation**: Maintain all advanced error handling, circuit breakers, and optimizations
3. **Incremental Rollout**: Feature flags enable gradual migration
4. **Performance First**: No regression in performance metrics

## Pre-Migration Checklist

- [ ] Audit current DSPex Python bridge usage patterns
- [ ] Document all custom error handling scenarios
- [ ] Baseline performance metrics for comparison
- [ ] Inventory DSPy-specific optimizations
- [ ] Review Snakepit's current capabilities

## Migration Steps

### Step 1: Add Snakepit Dependency

```elixir
# mix.exs
defp deps do
  [
    # Existing dependencies...
    {:snakepit, "~> 0.1.0"},
    # Keep existing DSPex dependencies
  ]
end
```

### Step 2: Create Compatibility Layer

```elixir
defmodule DSPex.Adapters.SnakepitCompat do
  @moduledoc """
  Compatibility layer that provides DSPex's advanced features on top of Snakepit.
  """
  
  alias DSPex.PythonBridge.{CircuitBreaker, PoolErrorHandler, RetryLogic}
  
  defstruct [:snakepit_pool, :circuit_breaker, :error_handler, :session_affinity]
  
  def init(opts) do
    # Initialize Snakepit pool
    python_config = [
      adapter: Snakepit.Adapters.Python,
      python_path: opts[:python_path] || "python3",
      script_path: translate_script_path(opts),
      pool_size: opts[:pool_size] || 4,
      max_overflow: opts[:overflow] || 2
    ]
    
    {:ok, pool} = Snakepit.start_pool(:dspex_legacy, python_config)
    
    # Initialize DSPex's advanced features
    {:ok, circuit_breaker} = CircuitBreaker.start_link(name: {:via, Registry, {Registry.CircuitBreaker, pool}})
    
    state = %__MODULE__{
      snakepit_pool: pool,
      circuit_breaker: circuit_breaker,
      error_handler: PoolErrorHandler,
      session_affinity: init_session_affinity()
    }
    
    {:ok, state}
  end
  
  def execute_with_session(state, session_id, operation, params, opts \\ []) do
    # Maintain DSPex's session affinity
    worker = get_or_assign_worker(state.session_affinity, session_id)
    
    # Apply circuit breaker protection
    CircuitBreaker.call(state.circuit_breaker, fn ->
      execute_with_retry(state, worker, operation, params, opts)
    end)
  end
  
  defp execute_with_retry(state, worker, operation, params, opts) do
    retry_opts = Keyword.get(opts, :retry, [])
    
    RetryLogic.with_retry(retry_opts, fn ->
      case Snakepit.execute(state.snakepit_pool, operation, params, worker: worker) do
        {:ok, result} -> 
          {:ok, result}
        {:error, reason} ->
          # Classify error using DSPex's error handler
          error_info = state.error_handler.classify_error(reason)
          handle_classified_error(error_info, state)
      end
    end)
  end
  
  defp translate_script_path(opts) do
    # Map DSPex script paths to Snakepit format
    case opts[:script_path] do
      nil -> "priv/python/dspy_bridge.py"
      path -> path
    end
  end
end
```

### Step 3: Feature Flag Implementation

```elixir
defmodule DSPex.Config do
  # Add to existing config module
  
  def use_snakepit_backend? do
    Application.get_env(:dspex, :use_snakepit_backend, false)
  end
  
  def snakepit_migration_config do
    %{
      enabled: use_snakepit_backend?(),
      features: %{
        basic_operations: true,
        session_affinity: true,
        circuit_breaker: true,
        advanced_retry: true
      },
      rollback_on_error: Application.get_env(:dspex, :snakepit_rollback_on_error, true)
    }
  end
end
```

### Step 4: Adapter Router

```elixir
defmodule DSPex.AdapterRouter do
  @moduledoc """
  Routes operations to appropriate backend based on configuration.
  """
  
  def get_adapter(opts \\ []) do
    if DSPex.Config.use_snakepit_backend?() do
      get_snakepit_adapter(opts)
    else
      get_legacy_adapter(opts)
    end
  end
  
  defp get_snakepit_adapter(opts) do
    case Registry.lookup(Registry.Adapters, :snakepit_compat) do
      [{_pid, adapter}] -> 
        {:ok, adapter}
      [] ->
        # Initialize on demand
        {:ok, adapter} = DSPex.Adapters.SnakepitCompat.init(opts)
        Registry.register(Registry.Adapters, :snakepit_compat, adapter)
        {:ok, adapter}
    end
  end
  
  defp get_legacy_adapter(opts) do
    # Return existing DSPex adapter
    Registry.get_adapter(opts[:adapter_type] || :python_pool_v2)
  end
end
```

### Step 5: Preserve Advanced Features

#### 5.1 Circuit Breaker Integration

```elixir
defmodule DSPex.Snakepit.CircuitBreakerIntegration do
  @doc """
  Wraps Snakepit operations with DSPex's circuit breaker.
  """
  def wrap_operation(pool, operation, params, circuit_breaker) do
    DSPex.PythonBridge.CircuitBreaker.call(circuit_breaker, fn ->
      Snakepit.execute(pool, operation, params)
    end)
  end
end
```

#### 5.2 Error Classification

```elixir
defmodule DSPex.Snakepit.ErrorMapper do
  @doc """
  Maps Snakepit errors to DSPex's error classification system.
  """
  
  alias DSPex.PythonBridge.PoolErrorHandler
  
  def classify_snakepit_error({:error, {:port_error, details}}) do
    PoolErrorHandler.classify_error({:port_error, details})
  end
  
  def classify_snakepit_error({:error, {:timeout, _}}) do
    %{
      category: :timeout,
      severity: :high,
      retry_strategy: :backoff_retry,
      details: "Operation timed out in Snakepit pool"
    }
  end
  
  def classify_snakepit_error(error) do
    # Fallback to DSPex classification
    PoolErrorHandler.classify_error(error)
  end
end
```

### Step 6: Performance Monitoring

```elixir
defmodule DSPex.Snakepit.PerformanceMonitor do
  @moduledoc """
  Tracks performance metrics during migration.
  """
  
  def compare_backends(operation, params) do
    # Run operation on both backends
    legacy_result = time_operation(fn ->
      DSPex.execute_legacy(operation, params)
    end)
    
    snakepit_result = time_operation(fn ->
      DSPex.execute_snakepit(operation, params)
    end)
    
    # Report metrics
    :telemetry.execute(
      [:dspex, :migration, :performance],
      %{
        legacy_time: legacy_result.time,
        snakepit_time: snakepit_result.time,
        speedup: legacy_result.time / snakepit_result.time
      },
      %{operation: operation}
    )
    
    # Return based on configuration
    if DSPex.Config.use_snakepit_backend?() do
      snakepit_result.result
    else
      legacy_result.result
    end
  end
end
```

### Step 7: Gradual Rollout Strategy

```elixir
# config/config.exs
config :dspex, :migration,
  # Start with 0% Snakepit traffic
  snakepit_percentage: 0,
  # Operations to migrate first
  snakepit_operations: [:echo, :simple_predict],
  # Automatic rollback thresholds
  error_rate_threshold: 0.05,
  latency_threshold_ms: 1000

# Runtime traffic splitting
defmodule DSPex.TrafficSplitter do
  def should_use_snakepit?(operation) do
    percentage = Application.get_env(:dspex, :migration)[:snakepit_percentage]
    allowed_ops = Application.get_env(:dspex, :migration)[:snakepit_operations]
    
    operation in allowed_ops and :rand.uniform(100) <= percentage
  end
end
```

## Testing Strategy

### 1. Compatibility Tests

```elixir
defmodule DSPex.SnakepitCompatTest do
  use DSPex.Support.UnifiedTestFoundation, isolation: :full_integration
  
  describe "feature parity" do
    test "session affinity maintained" do
      # Test that sessions stick to workers
    end
    
    test "circuit breaker triggers correctly" do
      # Test circuit breaker behavior
    end
    
    test "error classification matches legacy" do
      # Compare error handling
    end
  end
end
```

### 2. Performance Benchmarks

```elixir
defmodule DSPex.MigrationBenchmark do
  use DSPex.Support.PoolPerformanceFramework
  
  @tag :benchmark
  test "compare backend performance" do
    benchmark_operation(:predict, %{
      legacy_adapter: DSPex.Adapters.PythonPoolV2,
      snakepit_adapter: DSPex.Adapters.SnakepitCompat,
      iterations: 1000,
      concurrent_clients: 10
    })
    
    assert_performance_maintained(:latency_p99)
    assert_performance_improved(:throughput)
  end
end
```

## Rollback Plan

1. **Immediate Rollback**: Feature flag disables Snakepit
2. **Gradual Rollback**: Reduce traffic percentage
3. **Operation-Specific**: Disable specific operations
4. **Monitoring**: Automatic rollback on error threshold

```elixir
defmodule DSPex.Migration.AutoRollback do
  def check_health do
    if error_rate_exceeded?() or latency_degraded?() do
      Logger.error("Migration health check failed, rolling back to legacy")
      Application.put_env(:dspex, :use_snakepit_backend, false)
      :telemetry.execute([:dspex, :migration, :rollback], %{reason: :health_check})
    end
  end
end
```

## Post-Migration Cleanup

Once migration is stable:

1. Remove legacy Python bridge code
2. Simplify adapter router
3. Move Snakepit compatibility features upstream
4. Update documentation
5. Archive migration code

## Success Criteria

- [ ] Zero increase in error rates
- [ ] No degradation in P99 latency
- [ ] All existing tests pass
- [ ] Session affinity maintained
- [ ] Circuit breakers functioning
- [ ] 30 days stable in production

## Timeline

- **Week 1-2**: Implement compatibility layer
- **Week 3-4**: Testing and benchmarking
- **Week 5-6**: Gradual rollout (1% → 10% → 50% → 100%)
- **Week 7-8**: Monitor and optimize
- **Week 9+**: Cleanup and documentation
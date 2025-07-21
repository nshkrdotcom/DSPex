# Unified gRPC Bridge: Variables Feature Addendum

## Overview

This addendum provides additional implementation details for the variables feature in the unified gRPC bridge, based on insights from the cognitive orchestration design, feasibility study, and phase 1 implementation that may not have been fully captured in the unified specification.

## Missing Implementation Details

### 1. Variable Observer and Optimization Infrastructure

#### Observer Pattern Implementation

The unified bridge mentions observers but doesn't detail the implementation. Based on the cognitive orchestration design:

```elixir
defmodule DSPex.Bridge.Variables.ObserverManager do
  @moduledoc """
  Manages variable observers with filtering, priorities, and lifecycle.
  """
  
  defstruct [:observers, :filters, :priorities]
  
  @type observer_callback :: (variable_id :: String.t(), old_value :: any(), new_value :: any() -> :ok)
  
  @spec add_observer(String.t(), pid(), observer_callback(), Keyword.t()) :: :ok
  def add_observer(variable_id, observer_pid, callback, opts \\ []) do
    filter = opts[:filter] || fn _, _, _ -> true end
    priority = opts[:priority] || 50
    debounce_ms = opts[:debounce_ms] || 0
    
    observer = %{
      pid: observer_pid,
      callback: callback,
      filter: filter,
      priority: priority,
      debounce_ms: debounce_ms,
      last_notification: nil
    }
    
    # Monitor the observer process for cleanup
    Process.monitor(observer_pid)
    
    # Store with priority ordering
    :ok
  end
  
  @spec notify_observers(String.t(), any(), any()) :: :ok
  def notify_observers(variable_id, old_value, new_value) do
    observers = get_observers(variable_id)
    |> Enum.filter(&apply_filter(&1, old_value, new_value))
    |> Enum.filter(&check_debounce(&1))
    |> Enum.sort_by(& &1.priority, :desc)
    
    # Notify in priority order
    Enum.each(observers, fn observer ->
      Task.start(fn ->
        observer.callback.(variable_id, old_value, new_value)
      end)
    end)
    
    :ok
  end
end
```

#### Optimizer Protocol

```elixir
defprotocol DSPex.Bridge.Variables.Optimizer do
  @doc "Initialize optimizer with variable specification"
  def init(optimizer, variable_spec)
  
  @doc "Propose next value based on feedback"
  def propose_update(optimizer, current_value, feedback)
  
  @doc "Handle conflicts with other optimizers"
  def resolve_conflict(optimizer, proposals)
  
  @doc "Check if optimization has converged"
  def converged?(optimizer, history)
end

defmodule DSPex.Bridge.Variables.OptimizationManager do
  @moduledoc """
  Coordinates multiple optimizers working on variables.
  """
  
  def start_optimization(variable_id, optimizer_module, opts \\ []) do
    with {:ok, lock} <- acquire_optimization_lock(variable_id),
         {:ok, variable} <- get_variable(variable_id),
         {:ok, optimizer} <- optimizer_module.init(variable) do
      
      # Start optimization process
      {:ok, optimization_id}
    end
  end
  
  def update_with_feedback(optimization_id, feedback) do
    # Apply optimizer protocol to generate new value
    # Handle conflicts if multiple optimizers active
    # Update variable and notify observers
  end
end
```

### 2. Complex Variable Types

#### Embedding/Vector Type

```elixir
defmodule DSPex.Bridge.Variables.Types.Embedding do
  @behaviour DSPex.Bridge.Variables.Type
  
  defstruct [:dimensions, :normalize, :distance_metric]
  
  @impl true
  def validate(%{dimensions: dims} = spec, value) when is_list(value) do
    if length(value) == dims and Enum.all?(value, &is_number/1) do
      normalized = if spec.normalize, do: normalize_vector(value), else: value
      {:ok, normalized}
    else
      {:error, "Invalid embedding dimensions"}
    end
  end
  
  @impl true
  def serialize(value) do
    # Efficient binary serialization for protobuf
    {:ok, :erlang.term_to_binary(value)}
  end
  
  @impl true
  def deserialize(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  end
  
  defp normalize_vector(vec) do
    magnitude = :math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))
    Enum.map(vec, &(&1 / magnitude))
  end
end
```

#### Tensor Type

```elixir
defmodule DSPex.Bridge.Variables.Types.Tensor do
  @behaviour DSPex.Bridge.Variables.Type
  
  defstruct [:shape, :dtype]
  
  @impl true
  def validate(%{shape: shape, dtype: dtype}, value) do
    # Validate tensor shape and data type
    # Integration with Nx for tensor operations
    case Nx.tensor(value) do
      {:ok, tensor} ->
        if Nx.shape(tensor) == shape and Nx.type(tensor) == dtype do
          {:ok, tensor}
        else
          {:error, "Shape or dtype mismatch"}
        end
      error -> error
    end
  end
end
```

### 3. Variable Dependency Tracking

```elixir
defmodule DSPex.Bridge.Variables.DependencyGraph do
  @moduledoc """
  Tracks and manages variable dependencies.
  """
  
  use GenServer
  
  defstruct [:graph, :reverse_graph, :cycle_detector]
  
  def add_dependency(from_var_id, to_var_id) do
    GenServer.call(__MODULE__, {:add_dependency, from_var_id, to_var_id})
  end
  
  def get_dependencies(var_id) do
    GenServer.call(__MODULE__, {:get_dependencies, var_id})
  end
  
  def get_dependents(var_id) do
    GenServer.call(__MODULE__, {:get_dependents, var_id})
  end
  
  def detect_cycles do
    GenServer.call(__MODULE__, :detect_cycles)
  end
  
  # Implementation
  def handle_call({:add_dependency, from, to}, _from, state) do
    # Check for cycles before adding
    if would_create_cycle?(state.graph, from, to) do
      {:reply, {:error, :would_create_cycle}, state}
    else
      updated_graph = add_edge(state.graph, from, to)
      updated_reverse = add_edge(state.reverse_graph, to, from)
      
      new_state = %{state | 
        graph: updated_graph,
        reverse_graph: updated_reverse
      }
      
      {:reply, :ok, new_state}
    end
  end
  
  defp would_create_cycle?(graph, from, to) do
    # DFS to check if 'to' can reach 'from'
    reachable?(graph, to, from)
  end
end
```

### 4. Access Control and Security

```elixir
defmodule DSPex.Bridge.Variables.AccessControl do
  @moduledoc """
  Fine-grained access control for variables.
  """
  
  @type permission :: :read | :write | :observe | :optimize
  @type access_rule :: %{
    session_pattern: String.t() | :any,
    permissions: [permission()],
    conditions: map()
  }
  
  def check_access(session_id, variable_id, operation) do
    with {:ok, rules} <- get_access_rules(variable_id),
         {:ok, session_info} <- get_session_info(session_id) do
      
      allowed = Enum.any?(rules, fn rule ->
        matches_session?(rule.session_pattern, session_id) and
        operation in rule.permissions and
        check_conditions(rule.conditions, session_info)
      end)
      
      if allowed do
        audit_access(session_id, variable_id, operation, :granted)
        :ok
      else
        audit_access(session_id, variable_id, operation, :denied)
        {:error, :access_denied}
      end
    end
  end
  
  defp audit_access(session_id, variable_id, operation, result) do
    event = %{
      timestamp: DateTime.utc_now(),
      session_id: session_id,
      variable_id: variable_id,
      operation: operation,
      result: result
    }
    
    # Send to audit log
    :telemetry.execute(
      [:dspex, :bridge, :variables, :access],
      %{count: 1},
      event
    )
  end
end
```

### 5. Advanced Caching Strategy

```python
class VariableCache:
    """Advanced caching with invalidation subscriptions and batch operations."""
    
    def __init__(self, ttl: float = 1.0, max_size: int = 1000):
        self._cache: Dict[str, CacheEntry] = {}
        self._lru = OrderedDict()
        self._ttl = ttl
        self._max_size = max_size
        self._invalidation_callbacks: Dict[str, List[Callable]] = {}
        self._lock = asyncio.Lock()
        
    async def get_batch(self, var_ids: List[str]) -> Dict[str, Any]:
        """Efficiently fetch multiple variables."""
        async with self._lock:
            results = {}
            missing = []
            
            for var_id in var_ids:
                entry = self._cache.get(var_id)
                if entry and not entry.is_expired():
                    results[var_id] = entry.value
                    self._update_lru(var_id)
                else:
                    missing.append(var_id)
            
            if missing:
                # Fetch missing in batch from gRPC
                fetched = await self._fetch_batch(missing)
                for var_id, value in fetched.items():
                    self._set(var_id, value)
                    results[var_id] = value
            
            return results
    
    def subscribe_invalidation(self, var_id: str, callback: Callable):
        """Subscribe to cache invalidation events."""
        if var_id not in self._invalidation_callbacks:
            self._invalidation_callbacks[var_id] = []
        self._invalidation_callbacks[var_id].append(callback)
    
    async def invalidate(self, var_id: str, reason: str = ""):
        """Invalidate cache entry and notify subscribers."""
        async with self._lock:
            if var_id in self._cache:
                del self._cache[var_id]
                
            # Notify subscribers
            for callback in self._invalidation_callbacks.get(var_id, []):
                await callback(var_id, reason)
```

### 6. Variable Persistence

```elixir
defmodule DSPex.Bridge.Variables.Persistence do
  @moduledoc """
  Save and restore variable state.
  """
  
  def save_snapshot(session_id, path) do
    with {:ok, variables} <- get_all_variables(session_id),
         {:ok, serialized} <- serialize_variables(variables),
         :ok <- File.write(path, serialized) do
      {:ok, %{
        variables_count: length(variables),
        timestamp: DateTime.utc_now(),
        size_bytes: byte_size(serialized)
      }}
    end
  end
  
  def load_snapshot(session_id, path) do
    with {:ok, data} <- File.read(path),
         {:ok, variables} <- deserialize_variables(data),
         :ok <- restore_variables(session_id, variables) do
      {:ok, length(variables)}
    end
  end
  
  def export_history(session_id, variable_id, format \\ :json) do
    with {:ok, history} <- get_optimization_history(session_id, variable_id) do
      case format do
        :json -> Jason.encode(history)
        :csv -> export_history_csv(history)
        :parquet -> export_history_parquet(history)
      end
    end
  end
end
```

### 7. Integration with DSPy Optimization

```python
class DSPyOptimizationBridge:
    """Bridge between DSPex variables and DSPy optimization."""
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
        self._optimization_tasks = {}
        
    async def create_dspy_optimizer(self, optimizer_class, 
                                   variable_mappings: Dict[str, str],
                                   **kwargs):
        """Create DSPy optimizer that uses DSPex variables."""
        
        class VariableAwareOptimizer(optimizer_class):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self._variable_mappings = variable_mappings
                self._session_context = session_context
            
            async def compile(self, student, trainset, **compile_kwargs):
                # Inject current variable values
                for param_name, var_id in self._variable_mappings.items():
                    value = await self._session_context.get_variable(var_id)
                    compile_kwargs[param_name] = value
                
                # Run optimization
                result = await super().compile(student, trainset, **compile_kwargs)
                
                # Update variables with optimized values
                if hasattr(result, 'get_parameters'):
                    params = result.get_parameters()
                    for param_name, value in params.items():
                        if param_name in self._variable_mappings:
                            var_id = self._variable_mappings[param_name]
                            await self._session_context.set_variable(
                                var_id, value,
                                metadata={"optimized_by": optimizer_class.__name__}
                            )
                
                return result
        
        return VariableAwareOptimizer(**kwargs)
```

### 8. Variable Usage Analytics

```elixir
defmodule DSPex.Bridge.Variables.Analytics do
  @moduledoc """
  Track and analyze variable usage patterns.
  """
  
  def analyze_usage_patterns(session_id, time_range) do
    with {:ok, events} <- get_usage_events(session_id, time_range) do
      %{
        most_used: compute_most_used(events),
        update_frequency: compute_update_frequency(events),
        access_patterns: analyze_access_patterns(events),
        optimization_effectiveness: measure_optimization_impact(events),
        correlations: find_variable_correlations(events)
      }
    end
  end
  
  def generate_optimization_report(session_id, variable_id) do
    with {:ok, history} <- get_optimization_history(session_id, variable_id),
         {:ok, metrics} <- get_associated_metrics(session_id, variable_id) do
      %{
        convergence_rate: calculate_convergence_rate(history),
        best_value: find_best_performing_value(history, metrics),
        stability: measure_value_stability(history),
        impact_on_metrics: correlate_with_metrics(history, metrics)
      }
    end
  end
end
```

## Protocol Buffer Extensions

Add these message types to the unified bridge protocol:

```protobuf
// Variable dependency information
message VariableDependency {
    string from_variable_id = 1;
    string to_variable_id = 2;
    string dependency_type = 3;  // "data", "constraint", "optimization"
    map<string, google.protobuf.Any> metadata = 4;
}

// Batch variable operations
message BatchGetVariablesRequest {
    string session_id = 1;
    repeated string variable_ids = 2;
    bool include_metadata = 3;
    bool include_dependencies = 4;
}

message BatchSetVariablesRequest {
    string session_id = 1;
    map<string, google.protobuf.Any> variables = 2;
    map<string, VariableMetadata> metadata = 3;
    bool atomic = 4;  // All or nothing
}

// Optimization feedback
message OptimizationFeedback {
    string variable_id = 1;
    string optimization_id = 2;
    double metric_value = 3;
    map<string, double> gradients = 4;
    repeated string correlated_variables = 5;
    google.protobuf.Timestamp timestamp = 6;
}

// Access control
message VariableAccessRule {
    string variable_id = 1;
    repeated string allowed_sessions = 2;
    repeated string permissions = 3;  // "read", "write", "observe", "optimize"
    map<string, string> conditions = 4;
}
```

## Performance Optimizations

### Variable Update Coalescing

```python
class UpdateCoalescer:
    """Coalesce high-frequency variable updates."""
    
    def __init__(self, max_delay_ms: int = 100, max_batch_size: int = 50):
        self._pending_updates: Dict[str, Any] = {}
        self._timers: Dict[str, asyncio.Task] = {}
        self._max_delay_ms = max_delay_ms
        self._max_batch_size = max_batch_size
        
    async def update_variable(self, var_id: str, value: Any):
        """Queue update for coalescing."""
        self._pending_updates[var_id] = value
        
        # Cancel existing timer
        if var_id in self._timers:
            self._timers[var_id].cancel()
        
        # Start new timer
        self._timers[var_id] = asyncio.create_task(
            self._flush_after_delay(var_id)
        )
        
        # Flush if batch is full
        if len(self._pending_updates) >= self._max_batch_size:
            await self._flush_all()
    
    async def _flush_after_delay(self, var_id: str):
        await asyncio.sleep(self._max_delay_ms / 1000)
        await self._flush_variable(var_id)
```

## Conclusion

This addendum provides the missing implementation details for a production-ready variables system in the unified gRPC bridge. The additions focus on:

1. **Robustness**: Observer lifecycle management, dependency tracking, and conflict resolution
2. **Performance**: Advanced caching, batch operations, and update coalescing
3. **Security**: Fine-grained access control and audit logging
4. **Integration**: Seamless DSPy optimizer integration and analytics
5. **Extensibility**: Support for complex types and custom extensions

These enhancements ensure the variables feature can handle complex optimization workflows, multi-user environments, and production-scale deployments while maintaining the elegant design of the unified bridge.
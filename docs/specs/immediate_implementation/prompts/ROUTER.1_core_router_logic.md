# Task: ROUTER.1 - Core Router Logic

## Context
You are implementing the core router that intelligently directs DSPex operations to the appropriate implementation (native Elixir or Python via Snakepit). This router is the brain that makes execution decisions based on availability, performance, and requirements.

## Required Reading

### 1. Router Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/router.ex`
  - Current router structure
  - Routing decision patterns

### 2. Cognitive Orchestration Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Section: "Cognitive Orchestration Engine"
  - Intelligence through observation

### 3. Detailed Router Design
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/02_CORE_COMPONENTS_DETAILED.md`
  - Section: "Component 1: Cognitive Orchestration Engine"
  - Strategy selection algorithm

### 4. Registry Integration
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/registry.ex`
  - Native module registry
- **File**: Previous prompt PYTHON.2
  - Python module registry design

### 5. Success Criteria
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Stage 4: Intelligent Orchestration tests

## Implementation Requirements

### Core Router Structure
```elixir
defmodule DSPex.Router do
  use GenServer
  require Logger
  
  @moduledoc """
  Intelligent router for DSPex operations.
  Routes to native or Python implementations based on:
  - Availability
  - Performance characteristics
  - Current system load
  - Historical performance
  """
  
  defstruct [
    :native_registry,
    :python_registry,
    :performance_history,
    :routing_rules,
    :fallback_enabled,
    :metrics_collector
  ]
  
  # Routing decision result
  defmodule Route do
    defstruct [
      :implementation,     # :native | :python
      :module,            # Module to execute
      :pool_type,         # For Python: :general | :optimizer | :neural
      :timeout,           # Recommended timeout
      :reason,            # Why this route was chosen
      :alternatives,      # Other possible routes
      :confidence         # Confidence in this decision (0.0-1.0)
    ]
  end
end
```

### Routing Decision Engine
```elixir
defmodule DSPex.Router do
  def route(operation, args, context \\ %{}) do
    GenServer.call(__MODULE__, {:route, operation, args, context})
  end
  
  def handle_call({:route, operation, args, context}, _from, state) do
    # 1. Check what's available
    native_available = check_native_availability(operation, state)
    python_available = check_python_availability(operation, state)
    
    # 2. Analyze requirements
    requirements = analyze_requirements(operation, args, context)
    
    # 3. Check performance history
    performance = get_performance_history(operation, state)
    
    # 4. Make routing decision
    route = make_routing_decision(
      operation,
      %{
        native_available: native_available,
        python_available: python_available,
        requirements: requirements,
        performance: performance,
        context: context
      },
      state
    )
    
    # 5. Record decision
    record_routing_decision(route, state)
    
    {:reply, {:ok, route}, state}
  end
  
  defp make_routing_decision(operation, analysis, state) do
    cond do
      # Force native if specified
      analysis.context[:force_native] && analysis.native_available ->
        build_route(:native, operation, analysis, "forced by context")
        
      # Force Python if specified
      analysis.context[:force_python] && analysis.python_available ->
        build_route(:python, operation, analysis, "forced by context")
        
      # Only one available
      analysis.native_available && not analysis.python_available ->
        build_route(:native, operation, analysis, "only native available")
        
      not analysis.native_available && analysis.python_available ->
        build_route(:python, operation, analysis, "only python available")
        
      # Both available - use intelligence
      analysis.native_available && analysis.python_available ->
        intelligent_routing(operation, analysis, state)
        
      # Neither available
      true ->
        {:error, :no_implementation_available}
    end
  end
end
```

### Intelligent Routing Logic
```elixir
defp intelligent_routing(operation, analysis, state) do
  # Calculate scores for each option
  native_score = calculate_implementation_score(:native, operation, analysis)
  python_score = calculate_implementation_score(:python, operation, analysis)
  
  # Adjust based on current system state
  native_score = adjust_for_system_state(native_score, :native, state)
  python_score = adjust_for_system_state(python_score, :python, state)
  
  # Make decision
  if native_score > python_score do
    build_route(:native, operation, analysis, 
      "native scored #{native_score} vs python #{python_score}")
  else
    build_route(:python, operation, analysis,
      "python scored #{python_score} vs native #{native_score}")
  end
end

defp calculate_implementation_score(impl, operation, analysis) do
  base_score = 50.0
  
  # Performance history (±30 points)
  perf_score = case analysis.performance[impl] do
    %{avg_duration: avg, success_rate: rate} ->
      speed_score = calculate_speed_score(avg)
      reliability_score = rate * 20
      speed_score + reliability_score
      
    nil -> 0
  end
  
  # Requirements match (±20 points)
  req_score = calculate_requirements_score(impl, analysis.requirements)
  
  # Implementation characteristics (±10 points)
  char_score = case impl do
    :native -> 
      # Native is better for simple, frequent operations
      if analysis.requirements.complexity == :low, do: 10, else: -5
      
    :python ->
      # Python is better for complex ML operations
      if analysis.requirements.complexity == :high, do: 10, else: -5
  end
  
  base_score + perf_score + req_score + char_score
end
```

### Performance Tracking
```elixir
defmodule DSPex.Router.PerformanceTracker do
  @window_size 100  # Keep last 100 executions per operation
  
  def record_execution(operation, implementation, duration, success) do
    :ets.insert(
      :router_performance,
      {
        {operation, implementation, System.monotonic_time()},
        %{
          duration: duration,
          success: success,
          timestamp: DateTime.utc_now()
        }
      }
    )
    
    # Trim old records
    trim_old_records(operation, implementation)
  end
  
  def get_stats(operation, implementation) do
    records = get_recent_records(operation, implementation)
    
    if Enum.empty?(records) do
      nil
    else
      %{
        avg_duration: calculate_average_duration(records),
        p95_duration: calculate_percentile(records, 95),
        success_rate: calculate_success_rate(records),
        sample_size: length(records)
      }
    end
  end
  
  defp calculate_average_duration(records) do
    successful = Enum.filter(records, & &1.success)
    if Enum.empty?(successful) do
      nil
    else
      avg = Enum.sum(Enum.map(successful, & &1.duration)) / length(successful)
      round(avg)
    end
  end
end
```

### Fallback Handling
```elixir
defmodule DSPex.Router.Fallback do
  def handle_execution_failure(route, error, state) do
    case route.implementation do
      :native when route.alternatives[:python] ->
        Logger.warning("Native execution failed, falling back to Python: #{inspect(error)}")
        
        # Build Python route
        python_route = build_fallback_route(route, :python)
        
        # Record fallback
        :telemetry.execute(
          [:dspex, :router, :fallback],
          %{},
          %{from: :native, to: :python, reason: error}
        )
        
        {:fallback, python_route}
        
      :python when route.alternatives[:native] ->
        Logger.warning("Python execution failed, falling back to native: #{inspect(error)}")
        
        native_route = build_fallback_route(route, :native)
        
        :telemetry.execute(
          [:dspex, :router, :fallback],
          %{},
          %{from: :python, to: :native, reason: error}
        )
        
        {:fallback, native_route}
        
      _ ->
        {:error, :no_fallback_available}
    end
  end
end
```

### Registry Integration
```elixir
defp check_native_availability(operation, state) do
  case DSPex.Native.Registry.get(operation) do
    {:ok, module_info} -> 
      %{
        available: true,
        module: module_info.module,
        estimated_duration: module_info.estimated_duration
      }
    :error -> 
      %{available: false}
  end
end

defp check_python_availability(operation, state) do
  case DSPex.Python.Registry.get_module(operation) do
    {:ok, module_info} ->
      %{
        available: true,
        module: module_info.name,
        pool_type: module_info.pool_type,
        estimated_duration: module_info.estimated_duration
      }
    :error ->
      %{available: false}
  end
end
```

## Acceptance Criteria
- [ ] Routes operations based on availability
- [ ] Tracks performance history for decisions
- [ ] Implements intelligent routing when both available
- [ ] Supports fallback on failure
- [ ] Integrates with both registries
- [ ] Emits telemetry events for monitoring
- [ ] Handles forced routing (context overrides)
- [ ] Thread-safe concurrent routing
- [ ] Configurable routing rules

## Testing Requirements
Create tests in:
- `test/dspex/router_test.exs`
- `test/dspex/router/performance_tracker_test.exs`

Test scenarios:
- Route when only native available
- Route when only Python available
- Intelligent routing based on performance
- Fallback handling
- Concurrent routing requests
- Performance tracking accuracy
- Context overrides

## Example Usage
```elixir
# Basic routing
{:ok, route} = DSPex.Router.route("predict", %{
  text: "Hello world",
  max_tokens: 50
})

route
# %Route{
#   implementation: :native,
#   module: DSPex.Native.Predict,
#   timeout: 1000,
#   reason: "native faster for simple predictions",
#   confidence: 0.85
# }

# Force Python implementation
{:ok, route} = DSPex.Router.route(
  "chain_of_thought",
  %{question: "Complex question"},
  %{force_python: true}
)

# Route with requirements
{:ok, route} = DSPex.Router.route(
  "optimize",
  %{iterations: 1000},
  %{require_gpu: true}
)
# Routes to Python neural pool

# After execution, record performance
DSPex.Router.record_execution(
  "predict",
  :native,
  duration_ms: 45,
  success: true
)
```

## Dependencies
- Requires registries (NATIVE.*, PYTHON.2) to be implemented
- Integrates with telemetry system
- No circular dependencies

## Time Estimate
6 hours total:
- 2 hours: Core routing logic
- 1 hour: Performance tracking
- 1 hour: Intelligent routing algorithm  
- 1 hour: Fallback handling
- 1 hour: Testing

## Notes
- Start with simple routing, add intelligence incrementally
- Use ETS for performance tracking
- Consider caching routing decisions briefly
- Monitor routing patterns for optimization
- Document routing decision reasons
- Plan for routing rule customization
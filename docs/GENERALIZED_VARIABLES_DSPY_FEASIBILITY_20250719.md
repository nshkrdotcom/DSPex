# DSPex Generalized Variables: Feasibility Analysis & Native Implementation Strategy

## Executive Summary

DSPy's current architecture does not support generalized variables as module-type parameters that can be optimized across different module boundaries. This document analyzes the feasibility of implementing this feature in DSPex, identifies the minimum native components needed, and outlines how SIMBA would need to adapt.

## The Generalized Variables Problem

### Current DSPy Limitations

1. **Module-Scoped Parameters**: DSPy modules (Predict, ChainOfThought, etc.) have their own internal parameters (prompts, few-shot examples) that are optimized in isolation.

2. **No Cross-Module Optimization**: There's no mechanism to share and optimize parameters across different module instances or types.

3. **Static Module Boundaries**: Each module is a black box with its own optimization space, preventing unified variable management.

4. **Limited Parameter Types**: DSPy primarily optimizes string-based prompts and example sets, not arbitrary module configurations.

### What Generalized Variables Would Enable

```elixir
# Hypothetical example of what we want:
temperature_var = DSPex.Variable.create(:temperature, 
  type: :float, 
  range: {0.0, 2.0},
  shared_across: [:predict_1, :cot_1, :react_1]
)

prompt_style_var = DSPex.Variable.create(:prompt_style,
  type: :module,
  options: [Formal, Casual, Technical],
  affects_rendering: true
)

# These variables would be optimized together across all modules
```

## Feasibility Analysis

### Option 1: Fork DSPy (Not Recommended)

**Pros:**
- Complete control over architecture
- Can redesign module system from ground up

**Cons:**
- Massive maintenance burden
- Lose compatibility with DSPy ecosystem
- Need to reimplement all optimizers
- Diverge from community improvements

### Option 2: Wrapper Layer (Recommended)

Build a generalized variable system on top of DSPy without modifying its core:

**Pros:**
- Maintain DSPy compatibility
- Can evolve independently
- Leverage existing optimizers
- Clean separation of concerns

**Cons:**
- Some efficiency loss
- Need translation layer
- Limited by DSPy's execution model

### Option 3: Native Implementation with DSPy Bridge

Implement core variable-aware modules natively in Elixir while maintaining DSPy compatibility:

**Pros:**
- Maximum flexibility
- Optimal performance
- Can pioneer new optimization approaches
- Gradual migration path

**Cons:**
- More implementation work
- Need to maintain parity
- Complex routing logic

## Minimum Native Components for Generalized Variables

### 1. Variable Registry & Management

```elixir
defmodule DSPex.Native.Variables do
  @moduledoc """
  Core variable system that tracks and manages generalized parameters.
  """
  
  defstruct [:id, :name, :type, :value, :constraints, :affects, :metadata]
  
  def create(name, type, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      type: type,
      value: opts[:initial_value],
      constraints: opts[:constraints] || %{},
      affects: MapSet.new(opts[:affects] || []),
      metadata: %{
        created_at: DateTime.utc_now(),
        optimization_history: []
      }
    }
  end
  
  def bind_to_module(variable, module_id) do
    update_in(variable.affects, &MapSet.put(&1, module_id))
  end
end
```

### 2. Variable-Aware Module Protocol

```elixir
defprotocol DSPex.Native.VariableAware do
  @doc "Get all variables this module depends on"
  def get_variables(module)
  
  @doc "Apply variable values to module configuration"
  def apply_variables(module, variable_values)
  
  @doc "Get variable gradients/feedback after execution"
  def get_variable_feedback(module, execution_result)
end
```

### 3. Native Evaluation Framework

**This is the most critical component** - without native evaluation, we can't properly measure the impact of variable changes:

```elixir
defmodule DSPex.Native.Evaluation do
  @moduledoc """
  Native evaluation engine that understands variable impacts.
  """
  
  def evaluate_with_variables(program, dataset, variables, metrics) do
    # Track variable values across executions
    # Measure impact on metrics
    # Return variable-aware results
    
    results = Enum.map(dataset, fn example ->
      # Apply current variable values
      configured_program = apply_variables(program, variables)
      
      # Execute and track
      {output, trace} = execute_with_trace(configured_program, example)
      
      # Evaluate metrics
      scores = evaluate_metrics(output, example, metrics)
      
      %{
        example: example,
        output: output,
        scores: scores,
        variable_trace: extract_variable_impacts(trace, variables)
      }
    end)
    
    aggregate_variable_impacts(results)
  end
end
```

### 4. Variable-Aware Optimizer Base

```elixir
defmodule DSPex.Native.Optimizers.VariableAware do
  @moduledoc """
  Base optimizer that understands generalized variables.
  """
  
  def optimize(program, dataset, variables, opts \\ []) do
    initial_values = get_initial_values(variables)
    
    # Optimization loop
    Enum.reduce_while(1..opts[:max_iterations], initial_values, fn iteration, current_values ->
      # Apply variables
      configured_program = apply_variables(program, current_values)
      
      # Evaluate
      results = DSPex.Native.Evaluation.evaluate_with_variables(
        configured_program, 
        dataset, 
        variables,
        opts[:metrics]
      )
      
      # Update variables based on feedback
      new_values = update_variables(current_values, results, variables)
      
      if converged?(current_values, new_values) do
        {:halt, new_values}
      else
        {:cont, new_values}
      end
    end)
  end
end
```

### 5. Execution Trace System

```elixir
defmodule DSPex.Native.Trace do
  @moduledoc """
  Captures execution traces with variable attribution.
  """
  
  defstruct [:module_calls, :variable_uses, :decision_points, :metrics]
  
  def track_variable_use(trace, variable_id, context) do
    update_in(trace.variable_uses[variable_id], fn uses ->
      [%{timestamp: now(), context: context} | uses || []]
    end)
  end
  
  def track_decision(trace, decision_type, chosen_value, alternatives) do
    # Track how variables influenced decisions
  end
end
```

## SIMBA Adaptation Requirements

SIMBA (Sampling, Initializing, Mutating, Bootstrapping, and Amplifying) would need significant adaptations:

### 1. Variable-Aware Sampling

```elixir
defmodule DSPex.Native.SIMBA.VariableSampling do
  def sample_with_variables(dataset, variables, strategy) do
    # Sample based on variable coverage
    # Ensure samples exercise different variable ranges
    case strategy do
      :variable_coverage ->
        sample_for_variable_diversity(dataset, variables)
        
      :gradient_based ->
        sample_high_gradient_regions(dataset, variables)
        
      :uncertainty ->
        sample_uncertain_variable_regions(dataset, variables)
    end
  end
end
```

### 2. Variable-Aware Mutations

```elixir
defmodule DSPex.Native.SIMBA.VariableMutation do
  def mutate_variables(current_values, feedback, opts) do
    # Mutate based on variable interdependencies
    Enum.map(current_values, fn {var_id, value} ->
      gradient = feedback[var_id][:gradient]
      correlation = feedback[var_id][:correlation_with_others]
      
      new_value = case gradient do
        g when g > 0 -> increase_intelligently(value, g, correlation)
        g when g < 0 -> decrease_intelligently(value, g, correlation)
        _ -> explore_randomly(value, opts[:exploration_rate])
      end
      
      {var_id, constrain(new_value, variables[var_id].constraints)}
    end)
  end
end
```

### 3. Cross-Module Bootstrap

```elixir
defmodule DSPex.Native.SIMBA.CrossModuleBootstrap do
  def bootstrap_with_shared_variables(modules, dataset, variables) do
    # Bootstrap examples that work well across all modules
    # sharing the same variables
    
    candidates = generate_candidates(dataset)
    
    scored_candidates = Enum.map(candidates, fn candidate ->
      scores = Enum.map(modules, fn module ->
        evaluate_with_candidate(module, candidate, variables)
      end)
      
      {candidate, aggregate_cross_module_score(scores)}
    end)
    
    select_best_bootstraps(scored_candidates, opts[:n_bootstraps])
  end
end
```

## Implementation Roadmap

### Phase 1: Core Variable System (Week 1-2)
1. Variable registry and management
2. Variable-aware module protocol
3. Basic variable application mechanism

### Phase 2: Native Evaluation (Week 3-4)
1. Trace system implementation
2. Variable impact measurement
3. Native metric calculation
4. Cross-module evaluation

### Phase 3: Variable-Aware Optimizer (Week 5-6)
1. Base optimizer framework
2. Gradient estimation for variables
3. Variable update strategies
4. Convergence detection

### Phase 4: SIMBA Integration (Week 7-8)
1. Variable-aware sampling
2. Smart mutation strategies
3. Cross-module bootstrap
4. Amplification with variables

### Phase 5: DSPy Bridge Enhancement (Week 9-10)
1. Variable translation layer
2. Hybrid execution (native vars + DSPy modules)
3. Performance optimization
4. Compatibility testing

## Critical Success Factors

### 1. Native Evaluation is Essential
Without native evaluation, we cannot:
- Measure variable impacts accurately
- Compute gradients efficiently
- Track cross-module effects
- Optimize at the speed needed

### 2. Trace System Must Be Comprehensive
The trace system needs to capture:
- Which variables were used when
- How variables affected decisions
- Cross-module variable dependencies
- Performance attribution to variables

### 3. SIMBA Must Understand Variable Geometry
SIMBA's effectiveness depends on understanding:
- Variable interaction patterns
- Constraint satisfaction
- Multi-objective optimization across modules
- Exploration vs exploitation in variable space

## Example: Generalized Temperature Variable

```elixir
# Define a temperature variable shared across modules
temp_var = DSPex.Variable.create(:temperature,
  type: :float,
  range: {0.0, 2.0},
  initial_value: 0.7,
  affects: [:reasoning_style, :creativity, :consistency]
)

# Create variable-aware modules
predict = DSPex.Native.Predict.create("question -> answer",
  variables: %{temperature: temp_var}
)

cot = DSPex.Native.ChainOfThought.create("question -> answer",  
  variables: %{temperature: temp_var}
)

# SIMBA optimizes the shared temperature
{:ok, optimal_temp} = DSPex.Native.SIMBA.optimize(
  modules: [predict, cot],
  variables: [temp_var],
  dataset: training_data,
  metric: &combined_quality_diversity_metric/2
)

# Result: Found temperature=1.2 works best across both modules
```

## Conclusion

Building generalized variables for DSPex requires:

1. **Native implementation** of core components (evaluation, tracing, optimization)
2. **SIMBA adaptations** to handle variable-aware optimization
3. **Clean abstraction layer** over DSPy to maintain compatibility
4. **Focus on evaluation** as the key enabler

The approach is feasible but requires significant native Elixir implementation. The payoff is a truly novel system that goes beyond current DSPy capabilities while maintaining compatibility where useful.
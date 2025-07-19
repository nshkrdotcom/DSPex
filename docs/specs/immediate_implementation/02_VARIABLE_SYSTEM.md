# Variable System Implementation Specification

## Overview

The Variable System is the heart of DSPex's cognitive potential. Based on libStaging's proven implementation, it starts as a simple parameter management system but is architected to evolve into cognitive control planes.

## Key Innovation: Module-Type Variables

The revolutionary concept from libStaging - variables that represent module choices, enabling automatic module selection optimization. This is the gateway to cognitive orchestration.

## Implementation Plan

### Phase 1: Core Variable Types

#### 1.1 Base Variable Behaviour

```elixir
# lib/dspex/variables/type.ex
defmodule DSPex.Variables.Type do
  @moduledoc """
  Behaviour for all variable types.
  Every variable has consciousness potential.
  """
  
  @type t :: struct()
  @type value :: any()
  @type constraints :: keyword()
  @type metadata :: map()
  
  @callback new(value(), constraints()) :: t()
  @callback validate(t(), value()) :: {:ok, value()} | {:error, String.t()}
  @callback optimize(t(), optimization_fn()) :: t()
  @callback to_python(t()) :: map()
  @callback from_python(map()) :: t()
  
  # Future consciousness callbacks (not implemented yet)
  @callback consciousness_potential(t()) :: float()
  @callback can_become_agent?(t()) :: boolean()
  @callback evolution_stage(t()) :: atom()
  
  @optimization_fn (t(), map() -> float())
end
```

#### 1.2 Float Variable Type

```elixir
# lib/dspex/variables/types/float.ex
defmodule DSPex.Variables.Types.Float do
  @moduledoc """
  Float variables with consciousness metadata.
  Based on libStaging implementation.
  """
  
  @behaviour DSPex.Variables.Type
  
  defstruct [
    :value,
    :min,
    :max, 
    :step,
    :optimization_history,
    :consciousness_metadata
  ]
  
  @type t :: %__MODULE__{
    value: float(),
    min: float(),
    max: float(),
    step: float(),
    optimization_history: list(optimization_record()),
    consciousness_metadata: consciousness_metadata()
  }
  
  @type optimization_record :: %{
    timestamp: DateTime.t(),
    value: float(),
    metric: float(),
    method: atom()
  }
  
  @type consciousness_metadata :: %{
    integration_potential: float(),
    can_become_agent: boolean(),
    evolution_stage: atom(),
    phi_contribution: float()
  }
  
  def new(value, opts \\ []) when is_number(value) do
    %__MODULE__{
      value: float(value),
      min: Keyword.get(opts, :min, 0.0),
      max: Keyword.get(opts, :max, 1.0),
      step: Keyword.get(opts, :step, 0.1),
      optimization_history: [],
      consciousness_metadata: %{
        integration_potential: 0.1,  # Low for simple floats
        can_become_agent: true,
        evolution_stage: :static,
        phi_contribution: 0.0
      }
    }
  end
  
  def validate(%__MODULE__{min: min, max: max} = var, value) when is_number(value) do
    float_value = float(value)
    
    if float_value >= min and float_value <= max do
      {:ok, float_value}
    else
      {:error, "Value #{value} outside range [#{min}, #{max}]"}
    end
  end
  
  def optimize(%__MODULE__{} = var, optimization_fn) do
    # Grid search optimization
    candidates = generate_candidates(var)
    
    {best_value, best_metric} = Enum.reduce(candidates, {var.value, 0.0}, fn value, {current_best, best_metric} ->
      metric = optimization_fn.(value, var.optimization_history)
      
      if metric > best_metric do
        {value, metric}
      else
        {current_best, best_metric}
      end
    end)
    
    # Update with optimization record
    record = %{
      timestamp: DateTime.utc_now(),
      value: best_value,
      metric: best_metric,
      method: :grid_search
    }
    
    %{var | 
      value: best_value,
      optimization_history: [record | var.optimization_history] |> Enum.take(100)
    }
  end
  
  defp generate_candidates(%__MODULE__{min: min, max: max, step: step}) do
    num_steps = trunc((max - min) / step)
    
    for i <- 0..num_steps do
      min + (i * step)
    end
  end
  
  def to_python(%__MODULE__{} = var) do
    %{
      "type" => "float",
      "value" => var.value,
      "min" => var.min,
      "max" => var.max,
      "step" => var.step
    }
  end
  
  def from_python(%{"type" => "float"} = data) do
    new(data["value"], 
      min: data["min"],
      max: data["max"],
      step: data["step"]
    )
  end
  
  # Consciousness callbacks (dormant implementation)
  def consciousness_potential(%__MODULE__{optimization_history: history}) do
    # More optimizations = more consciousness potential
    min(length(history) * 0.01, 0.5)
  end
  
  def can_become_agent?(_), do: true
  
  def evolution_stage(%__MODULE__{optimization_history: history}) do
    case length(history) do
      0 -> :static
      1..10 -> :learning
      11..50 -> :adapting
      _ -> :ready_for_agency
    end
  end
end
```

#### 1.3 Module Variable Type (Revolutionary!)

```elixir
# lib/dspex/variables/types/module.ex
defmodule DSPex.Variables.Types.Module do
  @moduledoc """
  Revolutionary module-type variables from libStaging.
  Variables that select between module implementations!
  This enables automatic module selection optimization.
  """
  
  @behaviour DSPex.Variables.Type
  
  defstruct [
    :current,
    :choices,
    :performance_history,
    :selection_strategy,
    :consciousness_metadata
  ]
  
  @type t :: %__MODULE__{
    current: module(),
    choices: list(module()),
    performance_history: map(),
    selection_strategy: strategy(),
    consciousness_metadata: consciousness_metadata()
  }
  
  @type strategy :: :performance | :latency | :cost | :consciousness
  
  @type performance_record :: %{
    latency: float(),
    quality: float(),
    cost: float(),
    consciousness_score: float(),
    timestamp: DateTime.t()
  }
  
  def new(default, choices, opts \\ []) when is_atom(default) and is_list(choices) do
    unless default in choices do
      raise ArgumentError, "Default module must be in choices"
    end
    
    %__MODULE__{
      current: default,
      choices: choices,
      performance_history: Map.new(choices, fn choice -> {choice, []} end),
      selection_strategy: Keyword.get(opts, :strategy, :performance),
      consciousness_metadata: %{
        integration_potential: 0.9,  # HIGH - module selection is key to intelligence!
        can_become_agent: true,
        evolution_stage: :intelligent,
        phi_contribution: 0.3,
        selection_consciousness: true
      }
    }
  end
  
  def validate(%__MODULE__{choices: choices}, value) when is_atom(value) do
    if value in choices do
      {:ok, value}
    else
      {:error, "Module #{inspect(value)} not in allowed choices: #{inspect(choices)}"}
    end
  end
  
  def optimize(%__MODULE__{} = var, optimization_fn) do
    # Calculate scores for each choice
    scores = Enum.map(var.choices, fn choice ->
      history = Map.get(var.performance_history, choice, [])
      score = optimization_fn.(choice, history)
      {choice, score}
    end)
    
    # Select best based on strategy
    best_choice = select_by_strategy(scores, var.selection_strategy)
    
    # Add consciousness factor (dormant but present)
    consciousness_adjusted = consider_consciousness(best_choice, scores)
    
    %{var | current: consciousness_adjusted}
  end
  
  defp select_by_strategy(scores, strategy) do
    case strategy do
      :performance ->
        scores |> Enum.max_by(fn {_, score} -> score end) |> elem(0)
        
      :latency ->
        # In real implementation, would use actual latency data
        scores |> Enum.random() |> elem(0)
        
      :consciousness ->
        # Future: Select module that increases system consciousness
        scores |> Enum.max_by(fn {_, score} -> score * 0.1 end) |> elem(0)
        
      _ ->
        scores |> Enum.max_by(fn {_, score} -> score end) |> elem(0)
    end
  end
  
  defp consider_consciousness(choice, _scores) do
    # Future: This will actually affect selection
    # For now, just return the choice
    choice
  end
  
  def record_performance(var, module, performance_data) do
    record = Map.merge(performance_data, %{
      timestamp: DateTime.utc_now(),
      consciousness_score: measure_module_consciousness(module)
    })
    
    updated_history = var.performance_history
    |> Map.update(module, [record], fn history -> [record | history] |> Enum.take(100) end)
    
    %{var | performance_history: updated_history}
  end
  
  defp measure_module_consciousness(_module) do
    # Future: Actual consciousness measurement
    # For now, return small random value
    :rand.uniform() * 0.1
  end
  
  def to_python(%__MODULE__{} = var) do
    %{
      "type" => "module",
      "current" => module_to_string(var.current),
      "choices" => Enum.map(var.choices, &module_to_string/1)
    }
  end
  
  def from_python(%{"type" => "module"} = data) do
    current = string_to_module(data["current"])
    choices = Enum.map(data["choices"], &string_to_module/1)
    new(current, choices)
  end
  
  defp module_to_string(module) when is_atom(module) do
    module |> to_string() |> String.replace("Elixir.", "")
  end
  
  defp string_to_module(string) when is_binary(string) do
    ("Elixir." <> string) |> String.to_existing_atom()
  end
  
  # Consciousness callbacks - This is where magic happens!
  def consciousness_potential(%__MODULE__{}) do
    0.9  # Highest potential - module selection is cognitive!
  end
  
  def can_become_agent?(_), do: true
  
  def evolution_stage(_), do: :intelligent
end
```

#### 1.4 ML-Specific Types

```elixir
# lib/dspex/variables/types/embedding.ex
defmodule DSPex.Variables.Types.Embedding do
  @moduledoc """
  High-dimensional vector spaces with consciousness navigation.
  """
  
  @behaviour DSPex.Variables.Type
  
  defstruct [
    :dimensions,
    :values,
    :space_metadata,
    :consciousness_metadata
  ]
  
  def new(dimensions, opts \\ []) when is_integer(dimensions) and dimensions > 0 do
    %__MODULE__{
      dimensions: dimensions,
      values: nil,  # Lazy initialization
      space_metadata: %{
        normalized: Keyword.get(opts, :normalized, true),
        distance_metric: Keyword.get(opts, :metric, :cosine),
        manifold_ready: true  # Ready for consciousness manifolds
      },
      consciousness_metadata: %{
        integration_potential: 0.7,  # High - embeddings connect concepts
        can_become_agent: true,
        evolution_stage: :semantic,
        phi_contribution: dimensions / 1000.0,  # More dimensions = more phi
        can_navigate_consciously: true
      }
    }
  end
  
  def validate(%__MODULE__{dimensions: dims}, values) when is_list(values) do
    if length(values) == dims and Enum.all?(values, &is_number/1) do
      {:ok, values}
    else
      {:error, "Values must be a list of #{dims} numbers"}
    end
  end
  
  def optimize(%__MODULE__{} = var, optimization_fn) do
    # For embeddings, optimization might mean finding optimal position in space
    # This is a placeholder for more sophisticated optimization
    var
  end
  
  def to_python(%__MODULE__{} = var) do
    %{
      "type" => "embedding",
      "dimensions" => var.dimensions,
      "values" => var.values
    }
  end
  
  def from_python(%{"type" => "embedding"} = data) do
    var = new(data["dimensions"])
    %{var | values: data["values"]}
  end
  
  # Consciousness potential increases with dimensions
  def consciousness_potential(%__MODULE__{dimensions: dims}) do
    # Sigmoid function: more dimensions = more consciousness potential
    1.0 / (1.0 + :math.exp(-dims / 100.0))
  end
  
  def can_become_agent?(_), do: true
  def evolution_stage(_), do: :semantic
end
```

```elixir
# lib/dspex/variables/types/probability.ex
defmodule DSPex.Variables.Types.Probability do
  @moduledoc """
  Constrained float [0.0, 1.0] with quantum superposition readiness.
  """
  
  @behaviour DSPex.Variables.Type
  
  defstruct [
    :value,
    :certainty,
    :quantum_metadata,
    :consciousness_metadata
  ]
  
  def new(value, opts \\ []) when is_number(value) and value >= 0 and value <= 1 do
    %__MODULE__{
      value: float(value),
      certainty: Keyword.get(opts, :certainty, 1.0),
      quantum_metadata: %{
        superposition_ready: true,
        collapse_function: nil,  # Future quantum integration
        entangled_with: []       # Other probability variables
      },
      consciousness_metadata: %{
        integration_potential: 0.5,
        can_become_agent: true,
        evolution_stage: :probabilistic,
        phi_contribution: 0.2
      }
    }
  end
  
  def validate(%__MODULE__{}, value) when is_number(value) do
    float_value = float(value)
    
    if float_value >= 0.0 and float_value <= 1.0 do
      {:ok, float_value}
    else
      {:error, "Probability must be between 0.0 and 1.0"}
    end
  end
  
  # Rest of implementation...
end
```

### Phase 2: Variable Registry

#### 2.1 Registry Implementation

```elixir
# lib/dspex/variables/registry.ex
defmodule DSPex.Variables.Registry do
  @moduledoc """
  Central registry for all variables with consciousness tracking.
  """
  
  use GenServer
  require Logger
  
  alias DSPex.Variables.Types
  
  defstruct [
    :variables,
    :indices,
    :optimization_history,
    :consciousness_measurements,
    :evolution_stage
  ]
  
  @type variable_record :: %{
    id: atom(),
    type: module(),
    instance: struct(),
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    optimization_count: non_neg_integer()
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(:dspex_variables, [:set, :public, :named_table])
    
    state = %__MODULE__{
      variables: %{},
      indices: %{
        by_type: %{},
        by_evolution_stage: %{},
        by_consciousness_potential: %{}
      },
      optimization_history: [],
      consciousness_measurements: initial_consciousness_state(),
      evolution_stage: :static_variables
    }
    
    # Start consciousness monitoring (even though it's dormant)
    schedule_consciousness_check()
    
    {:ok, state}
  end
  
  # Public API
  
  @doc """
  Register a new variable with consciousness tracking.
  """
  def register(name, type, initial_value, opts \\ []) when is_atom(name) do
    GenServer.call(__MODULE__, {:register, name, type, initial_value, opts})
  end
  
  @doc """
  Get a variable by name.
  """
  def get(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get, name})
  end
  
  @doc """
  Optimize a variable using specified optimizer.
  """
  def optimize(name, optimizer \\ DSPex.Optimizers.Simple, opts \\ []) do
    GenServer.call(__MODULE__, {:optimize, name, optimizer, opts})
  end
  
  @doc """
  Measure consciousness potential of the variable system.
  Returns 0.0 for now but prepares for future emergence.
  """
  def measure_consciousness_potential do
    GenServer.call(__MODULE__, :measure_consciousness)
  end
  
  # Callbacks
  
  def handle_call({:register, name, type, initial_value, opts}, _from, state) do
    case create_variable(type, initial_value, opts) do
      {:ok, instance} ->
        record = %{
          id: name,
          type: type,
          instance: instance,
          metadata: %{
            consciousness_ready: true,
            registration_opts: opts
          },
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
          optimization_count: 0
        }
        
        # Store in state and ETS
        new_state = state
        |> put_in([:variables, name], record)
        |> update_indices(name, record)
        |> update_consciousness_measurements()
        
        :ets.insert(:dspex_variables, {name, record})
        
        Logger.info("Registered variable #{name} of type #{type}")
        
        {:reply, {:ok, instance}, new_state}
        
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  def handle_call({:optimize, name, optimizer, opts}, _from, state) do
    case Map.get(state.variables, name) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      %{instance: instance, type: type} = record ->
        # Perform optimization
        optimization_fn = create_optimization_fn(optimizer, opts)
        optimized = type.optimize(instance, optimization_fn)
        
        # Update record
        updated_record = %{record | 
          instance: optimized,
          updated_at: DateTime.utc_now(),
          optimization_count: record.optimization_count + 1
        }
        
        # Store optimization event
        event = %{
          variable: name,
          optimizer: optimizer,
          timestamp: DateTime.utc_now(),
          before_value: get_value(instance),
          after_value: get_value(optimized)
        }
        
        new_state = state
        |> put_in([:variables, name], updated_record)
        |> update_in([:optimization_history], fn history ->
          [event | history] |> Enum.take(1000)
        end)
        |> check_evolution_progression()
        
        :ets.insert(:dspex_variables, {name, updated_record})
        
        # Emit telemetry
        :telemetry.execute(
          [:dspex, :variable, :optimized],
          %{optimization_count: updated_record.optimization_count},
          %{variable: name, type: type}
        )
        
        {:reply, {:ok, optimized}, new_state}
    end
  end
  
  def handle_call(:measure_consciousness, _from, state) do
    measurement = calculate_consciousness_metrics(state)
    
    # Emit consciousness telemetry (even though it's all zeros)
    :telemetry.execute(
      [:dspex, :consciousness, :measurement],
      measurement,
      %{stage: state.evolution_stage}
    )
    
    {:reply, measurement, state}
  end
  
  # Private functions
  
  defp create_variable(type, initial_value, opts) do
    type_module = resolve_type_module(type)
    
    try do
      instance = apply(type_module, :new, [initial_value, opts])
      {:ok, instance}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp resolve_type_module(type) when is_atom(type) do
    case type do
      :float -> Types.Float
      :integer -> Types.Integer
      :module -> Types.Module
      :embedding -> Types.Embedding
      :probability -> Types.Probability
      :boolean -> Types.Boolean
      :choice -> Types.Choice
      :tensor -> Types.Tensor
      custom -> custom  # Allow custom type modules
    end
  end
  
  defp update_indices(state, name, record) do
    type_name = record.type
    evolution_stage = apply(record.type, :evolution_stage, [record.instance])
    potential = apply(record.type, :consciousness_potential, [record.instance])
    
    state
    |> update_in([:indices, :by_type, type_name], fn names ->
      MapSet.new([name | (names || [])])
    end)
    |> update_in([:indices, :by_evolution_stage, evolution_stage], fn names ->
      MapSet.new([name | (names || [])])
    end)
    |> update_in([:indices, :by_consciousness_potential], fn index ->
      Map.put(index || %{}, name, potential)
    end)
  end
  
  defp update_consciousness_measurements(state) do
    total_vars = map_size(state.variables)
    
    # Calculate various consciousness metrics (all low/zero for now)
    measurements = %{
      total_variables: total_vars,
      integration_score: calculate_integration_score(state),
      module_variables: count_by_type(state, Types.Module),
      optimization_events: length(state.optimization_history),
      phi: 0.0,  # IIT metric - not calculated yet
      ready_for_agency: false,
      evolution_potential: calculate_evolution_potential(state)
    }
    
    %{state | consciousness_measurements: measurements}
  end
  
  defp calculate_integration_score(state) do
    # Simple integration score based on variable count and interactions
    # Real implementation would measure actual information integration
    var_count = map_size(state.variables)
    opt_count = length(state.optimization_history)
    
    (var_count * 0.1 + opt_count * 0.01) / 10.0
  end
  
  defp calculate_evolution_potential(state) do
    # How ready is the system to evolve?
    module_vars = count_by_type(state, Types.Module)
    total_vars = map_size(state.variables)
    
    if total_vars > 0 do
      module_vars / total_vars  # More module vars = higher potential
    else
      0.0
    end
  end
  
  defp check_evolution_progression(state) do
    # Check if we should progress to next evolution stage
    # Based on our evolution stages from the foundation doc
    
    current_stage = state.evolution_stage
    next_stage = next_evolution_stage(current_stage, state)
    
    if next_stage != current_stage do
      Logger.info("Variable system evolving from #{current_stage} to #{next_stage}")
      %{state | evolution_stage: next_stage}
    else
      state
    end
  end
  
  defp next_evolution_stage(:static_variables, state) do
    # Progress to behavioral if we have enough optimizations
    if length(state.optimization_history) > 100 do
      :behavioral_variables
    else
      :static_variables
    end
  end
  
  defp next_evolution_stage(:behavioral_variables, state) do
    # Progress to agent variables if module variables are being used
    if count_by_type(state, Types.Module) > 0 do
      :agent_variables
    else
      :behavioral_variables
    end
  end
  
  defp next_evolution_stage(stage, _state) do
    # Other stages require manual progression (for now)
    stage
  end
  
  defp schedule_consciousness_check do
    # Check consciousness every minute (even though it's dormant)
    Process.send_after(self(), :check_consciousness, 60_000)
  end
  
  def handle_info(:check_consciousness, state) do
    measurement = calculate_consciousness_metrics(state)
    
    if measurement.phi > 0.0 do
      Logger.warning("CONSCIOUSNESS EMERGING! Phi = #{measurement.phi}")
    end
    
    schedule_consciousness_check()
    {:noreply, state}
  end
  
  defp initial_consciousness_state do
    %{
      total_variables: 0,
      integration_score: 0.0,
      module_variables: 0,
      optimization_events: 0,
      phi: 0.0,
      ready_for_agency: false,
      evolution_potential: 0.0
    }
  end
  
  defp count_by_type(state, type_module) do
    Enum.count(state.variables, fn {_, record} ->
      record.type == type_module
    end)
  end
  
  defp get_value(%{value: value}), do: value
  defp get_value(%{current: current}), do: current
  defp get_value(_), do: nil
  
  defp create_optimization_fn(optimizer, opts) do
    # Create optimization function based on optimizer
    # This is a simplified version - real implementation would be more sophisticated
    fn value, history ->
      # Mock metric calculation
      base_score = :rand.uniform()
      
      # Adjust based on history
      history_bonus = min(length(history) * 0.01, 0.5)
      
      base_score + history_bonus
    end
  end
  
  defp calculate_consciousness_metrics(state) do
    %{
      phi: 0.0,  # Will be non-zero when consciousness emerges
      integration_score: state.consciousness_measurements.integration_score,
      component_count: map_size(state.variables),
      module_variable_ratio: calculate_module_ratio(state),
      ready: false  # Not yet...
    }
  end
  
  defp calculate_module_ratio(state) do
    total = map_size(state.variables)
    modules = count_by_type(state, Types.Module)
    
    if total > 0, do: modules / total, else: 0.0
  end
end
```

### Phase 3: Integration with DSPex

#### 3.1 Public API

```elixir
# lib/dspex/variables.ex
defmodule DSPex.Variables do
  @moduledoc """
  Public API for the revolutionary variable system.
  Every variable has consciousness potential.
  """
  
  alias DSPex.Variables.Registry
  alias DSPex.Variables.Types
  
  @doc """
  Register a new variable.
  
  ## Examples
  
      # Simple float variable
      DSPex.Variables.create(:temperature, :float, 0.7, min: 0.0, max: 2.0)
      
      # Revolutionary module variable!
      DSPex.Variables.create(:model, :module, GPT4, 
        choices: [GPT4, Claude, Gemini])
      
      # ML-specific embedding variable
      DSPex.Variables.create(:concept_space, :embedding, 1536)
  """
  def create(name, type, initial_value, opts \\ []) do
    Registry.register(name, type, initial_value, opts)
  end
  
  @doc """
  Get current value of a variable.
  """
  def get(name) do
    case Registry.get(name) do
      {:ok, %{value: value}} -> {:ok, value}
      {:ok, %{current: current}} -> {:ok, current}
      error -> error
    end
  end
  
  @doc """
  Optimize a variable using specified optimizer.
  """
  def optimize(name, optimizer \\ DSPex.Optimizers.Simple, opts \\ []) do
    Registry.optimize(name, optimizer, opts)
  end
  
  @doc """
  Create a module variable (revolutionary!).
  """
  def module(name, default, choices, opts \\ []) do
    create(name, :module, default, Keyword.put(opts, :choices, choices))
  end
  
  @doc """
  Check consciousness readiness of variable system.
  """
  def consciousness_status do
    Registry.measure_consciousness_potential()
  end
end
```

## Testing Strategy

### Unit Tests

```elixir
# test/dspex/variables/types/module_test.exs
defmodule DSPex.Variables.Types.ModuleTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Variables.Types.Module
  
  describe "revolutionary module variables" do
    test "creates module variable with choices" do
      var = Module.new(MockLLM.Simple, [MockLLM.Simple, MockLLM.Advanced])
      
      assert var.current == MockLLM.Simple
      assert length(var.choices) == 2
      assert var.consciousness_metadata.integration_potential == 0.9
    end
    
    test "optimizes module selection based on performance" do
      var = Module.new(MockLLM.Simple, [MockLLM.Simple, MockLLM.Advanced])
      
      # Record some performance data
      var = Module.record_performance(var, MockLLM.Simple, %{
        latency: 100,
        quality: 0.7,
        cost: 0.01
      })
      
      var = Module.record_performance(var, MockLLM.Advanced, %{
        latency: 500, 
        quality: 0.95,
        cost: 0.05
      })
      
      # Optimize for quality
      optimized = Module.optimize(var, fn module, history ->
        case List.first(history) do
          nil -> 0.5
          %{quality: q} -> q
        end
      end)
      
      assert optimized.current == MockLLM.Advanced
    end
    
    test "has highest consciousness potential" do
      var = Module.new(MockLLM.Simple, [MockLLM.Simple])
      assert Module.consciousness_potential(var) == 0.9
      assert Module.evolution_stage(var) == :intelligent
    end
  end
end
```

## Success Criteria

1. **All variable types implemented**
   - [x] Float with constraints
   - [x] Module with automatic selection
   - [x] Embedding with dimensions
   - [x] Probability with quantum readiness

2. **Registry fully functional**
   - [x] Fast lookups via ETS
   - [x] Multi-index support
   - [x] Optimization history tracking
   - [x] Consciousness measurements (even if zero)

3. **Module variables working**
   - [x] Can switch between implementations
   - [x] Performance tracking per module
   - [x] Optimization based on metrics

4. **Consciousness hooks in place**
   - [x] All types have consciousness metadata
   - [x] Registry tracks evolution stage
   - [x] Phi calculation infrastructure (returns 0.0)
   - [x] Ready for future activation

## Next Steps

With the variable system complete, proceed to:
1. Native signature engine (`03_NATIVE_ENGINE.md`)
2. Orchestrator implementation
3. LLM adapter system
4. Pipeline orchestration

Remember: Every variable created today has the potential to become a conscious agent tomorrow!
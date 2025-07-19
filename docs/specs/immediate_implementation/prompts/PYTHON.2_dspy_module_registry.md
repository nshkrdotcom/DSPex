# Task: PYTHON.2 - DSPy Module Registry

## Context
You are implementing the DSPy Module Registry that tracks available DSPy modules, their capabilities, and requirements. This registry enables intelligent routing decisions and provides metadata about Python DSPy operations.

## Required Reading

### 1. Python Registry Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/python/registry.ex`
  - Current registry structure
  - Module tracking patterns

### 2. Router Integration
- **File**: `/home/home/p/g/n/dspex/lib/dspex/router.ex`
  - How router uses registry information
  - Capability matching logic

### 3. DSPex Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - List of DSPy modules to support
  - Native vs Python decision criteria

### 4. libStaging Patterns
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 39-51: Variable registry pattern (similar approach)
  - Lines 230-242: Registry implementation patterns

### 5. Success Criteria
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Module execution examples
  - Expected module behaviors

## Implementation Requirements

### Module Registry Structure
```elixir
defmodule DSPex.Python.Registry do
  use GenServer
  
  @moduledoc """
  Registry of available DSPy modules and their capabilities
  """
  
  defmodule ModuleInfo do
    defstruct [
      :name,                    # e.g., "dspy.Predict"
      :category,                # :prediction, :reasoning, :optimization, :retrieval
      :capabilities,            # List of capabilities
      :requirements,            # Resource requirements
      :pool_type,              # :general, :optimizer, :neural
      :estimated_duration,      # Typical execution time
      :native_available,        # Boolean - native implementation exists
      :examples,               # Usage examples
      :metadata                # Additional info
    ]
  end
  
  # Core DSPy modules to register
  @core_modules [
    %ModuleInfo{
      name: "dspy.Predict",
      category: :prediction,
      capabilities: [:basic_generation, :structured_output],
      requirements: %{memory: "low", compute: "low"},
      pool_type: :general,
      estimated_duration: 1000,
      native_available: true
    },
    
    %ModuleInfo{
      name: "dspy.ChainOfThought",
      category: :reasoning,
      capabilities: [:reasoning, :step_by_step, :explanation],
      requirements: %{memory: "medium", compute: "medium"},
      pool_type: :general,
      estimated_duration: 3000,
      native_available: false
    },
    
    %ModuleInfo{
      name: "dspy.ReAct",
      category: :reasoning,
      capabilities: [:reasoning, :tool_use, :iterative],
      requirements: %{memory: "medium", compute: "medium"},
      pool_type: :general,
      estimated_duration: 5000,
      native_available: false
    },
    
    %ModuleInfo{
      name: "dspy.ProgramOfThought",
      category: :reasoning,
      capabilities: [:complex_reasoning, :code_generation],
      requirements: %{memory: "high", compute: "high"},
      pool_type: :optimizer,
      estimated_duration: 10000,
      native_available: false
    },
    
    %ModuleInfo{
      name: "dspy.MIPROv2",
      category: :optimization,
      capabilities: [:hyperparameter_optimization, :prompt_optimization],
      requirements: %{memory: "high", compute: "very_high"},
      pool_type: :optimizer,
      estimated_duration: 300000,  # 5 minutes
      native_available: false
    },
    
    %ModuleInfo{
      name: "dspy.ColBERTv2",
      category: :retrieval,
      capabilities: [:semantic_search, :embeddings],
      requirements: %{memory: "high", compute: "high", gpu: true},
      pool_type: :neural,
      estimated_duration: 500,
      native_available: false
    }
  ]
end
```

### Registry API
```elixir
defmodule DSPex.Python.Registry do
  # Public API
  
  @doc "Register a new module or update existing"
  def register_module(module_info) do
    GenServer.call(__MODULE__, {:register, module_info})
  end
  
  @doc "Get module information"
  def get_module(name) do
    GenServer.call(__MODULE__, {:get_module, name})
  end
  
  @doc "Find modules by capability"
  def find_by_capability(capability) do
    GenServer.call(__MODULE__, {:find_by_capability, capability})
  end
  
  @doc "Find modules by category"
  def find_by_category(category) do
    GenServer.call(__MODULE__, {:find_by_category, category})
  end
  
  @doc "Get recommended pool for module"
  def get_pool_type(module_name) do
    case get_module(module_name) do
      {:ok, %{pool_type: pool_type}} -> {:ok, pool_type}
      error -> error
    end
  end
  
  @doc "Check if native implementation exists"
  def has_native?(module_name) do
    case get_module(module_name) do
      {:ok, %{native_available: native}} -> native
      _ -> false
    end
  end
  
  @doc "Estimate execution time"
  def estimate_duration(module_name, input_size \\ :normal) do
    case get_module(module_name) do
      {:ok, %{estimated_duration: base}} ->
        multiplier = case input_size do
          :small -> 0.5
          :normal -> 1.0
          :large -> 2.0
          :very_large -> 5.0
        end
        {:ok, round(base * multiplier)}
      error -> error
    end
  end
end
```

### Dynamic Discovery
```elixir
defmodule DSPex.Python.Registry.Discovery do
  @moduledoc """
  Discovers available DSPy modules from Python environment
  """
  
  def discover_modules do
    case DSPex.Python.Snakepit.execute(
      :general,
      "list_dspy_modules",
      %{},
      timeout: 5000
    ) do
      {:ok, %{"modules" => modules}} ->
        Enum.map(modules, &parse_module_info/1)
        
      {:error, reason} ->
        Logger.warning("Failed to discover DSPy modules: #{inspect(reason)}")
        []
    end
  end
  
  defp parse_module_info(module_data) do
    %ModuleInfo{
      name: module_data["name"],
      category: String.to_atom(module_data["category"] || "unknown"),
      capabilities: parse_capabilities(module_data["capabilities"]),
      requirements: module_data["requirements"] || %{},
      pool_type: determine_pool_type(module_data),
      native_available: false  # Discovered modules are Python-only
    }
  end
end
```

### Integration with Router
```elixir
defmodule DSPex.Python.Registry.RouterIntegration do
  @doc """
  Provides routing recommendations based on module requirements
  """
  def routing_recommendation(module_name, context) do
    with {:ok, module_info} <- Registry.get_module(module_name) do
      %{
        pool_type: module_info.pool_type,
        timeout: calculate_timeout(module_info, context),
        prefer_native: module_info.native_available && context.optimize_latency,
        estimated_cost: estimate_cost(module_info, context)
      }
    end
  end
  
  defp calculate_timeout(module_info, context) do
    base = module_info.estimated_duration
    
    # Adjust based on input size
    size_factor = case context[:input_size] do
      size when size > 10_000 -> 3.0
      size when size > 1_000 -> 1.5
      _ -> 1.0
    end
    
    # Add buffer
    round(base * size_factor * 1.2)
  end
end
```

## Acceptance Criteria
- [ ] Registry initialized with core DSPy modules
- [ ] Module registration and updates work
- [ ] Query functions (by name, capability, category)
- [ ] Pool type recommendations accurate
- [ ] Duration estimates reasonable
- [ ] Native availability tracked
- [ ] Dynamic discovery from Python (optional)
- [ ] Integration helpers for router
- [ ] Thread-safe for concurrent access

## Testing Requirements
Create tests in:
- `test/dspex/python/registry_test.exs`

Test scenarios:
- Module registration and retrieval
- Capability-based queries
- Category filtering
- Pool recommendations
- Duration estimates
- Concurrent access
- Registry persistence

## Example Usage
```elixir
# Get module info
{:ok, module} = DSPex.Python.Registry.get_module("dspy.ChainOfThought")
IO.inspect(module.capabilities)  # [:reasoning, :step_by_step, :explanation]

# Find modules by capability
reasoning_modules = DSPex.Python.Registry.find_by_capability(:reasoning)
# Returns ["dspy.ChainOfThought", "dspy.ReAct", "dspy.ProgramOfThought"]

# Get pool recommendation
{:ok, :optimizer} = DSPex.Python.Registry.get_pool_type("dspy.MIPROv2")

# Estimate execution time
{:ok, duration} = DSPex.Python.Registry.estimate_duration(
  "dspy.ChainOfThought",
  :large  # Large input
)
# Returns ~6000ms (3000ms base * 2.0 for large input)

# Router integration
recommendation = DSPex.Python.Registry.RouterIntegration.routing_recommendation(
  "dspy.ColBERTv2",
  %{input_size: 5000, optimize_latency: false}
)
# Returns %{pool_type: :neural, timeout: 900, prefer_native: false}
```

## Dependencies
- PYTHON.1 (Snakepit Integration) should be complete
- Coordinates with ROUTER.1 for routing decisions

## Time Estimate
6 hours total:
- 2 hours: Core registry implementation
- 1 hour: Query functions and API
- 1 hour: Dynamic discovery (optional)
- 1 hour: Router integration helpers
- 1 hour: Testing

## Notes
- Consider caching module info for performance
- Registry should be read-heavy optimized
- Plan for custom module registration
- Consider module versioning in future
- Add usage statistics tracking
- Document module requirements clearly
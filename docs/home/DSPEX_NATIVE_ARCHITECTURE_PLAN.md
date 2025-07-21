# DSPex Native DSPy Architecture Plan

## Executive Summary

This document proposes a strategic evolution of DSPex from a Python bridge library to a native Elixir implementation of DSPy, with Snakepit handling legacy Python DSPy operations. This approach enables gradual migration while maintaining backward compatibility.

## Current State Analysis

### DSPex Today
- **Primary Function**: Python bridge library for DSPy
- **Architecture**: NimblePool-based worker management with sophisticated error handling
- **No Native Implementation**: All DSPy functionality executed through Python processes
- **Strong Foundation**: Excellent test infrastructure, error handling, and performance optimizations

### Snakepit Capabilities
- **General Purpose**: Language-agnostic process pool management
- **Extracted from DSPex V3**: Similar architecture but generalized
- **Production Ready**: Used in production environments
- **Simpler Feature Set**: Lacks DSPex's advanced error handling and DSPy-specific optimizations

## Proposed Architecture

### Phase 1: Dual-Mode Architecture (3-6 months)

```
┌─────────────────────────────────────────────────────────────┐
│                        DSPex API                            │
│  (Unified interface for native and Python DSPy operations)  │
└─────────────────────┬───────────────────────┬───────────────┘
                      │                       │
         ┌────────────▼────────────┐    ┌────▼──────────────┐
         │   Native DSPy Engine    │    │  Legacy Adapter   │
         │  (Pure Elixir impl)     │    │  (Snakepit-based) │
         └─────────────────────────┘    └───────────────────┘
                                                 │
                                        ┌────────▼──────────┐
                                        │    Snakepit       │
                                        │  (Python DSPy)    │
                                        └───────────────────┘
```

### Key Components

#### 1. **DSPex API Layer**
- Maintains current public API for backward compatibility
- Routes operations to native or legacy implementation based on:
  - Feature availability
  - Configuration flags
  - Performance requirements

#### 2. **Native DSPy Engine**
Core modules to implement natively:
- `DSPex.Signature` - Signature definition and validation
- `DSPex.Predictor` - LLM interface abstraction
- `DSPex.Module` - Composable DSPy modules
- `DSPex.Optimizer` - Training and optimization
- `DSPex.Prompt` - Prompt templating engine

#### 3. **Legacy Adapter**
- Thin wrapper around Snakepit for Python DSPy operations
- Maintains DSPex's advanced features:
  - Circuit breakers
  - Sophisticated error handling
  - Session affinity
  - Performance optimizations

## Implementation Roadmap

### Phase 1: Foundation (Months 1-2)

**1.1 Core Native Modules**
```elixir
# Native signature implementation
defmodule DSPex.Signature do
  defstruct [:name, :docstring, :inputs, :outputs, :metadata]
  
  def compile(signature_string) do
    # Parse DSPy signature syntax
  end
  
  def validate(signature, data) do
    # Validate inputs/outputs against signature
  end
end

# Native predictor interface
defmodule DSPex.Predictor do
  @callback predict(signature :: DSPex.Signature.t(), inputs :: map()) :: {:ok, map()} | {:error, term()}
  
  # Implementations for different LLM providers
  defmodule OpenAI do
    @behaviour DSPex.Predictor
    # OpenAI-specific implementation
  end
  
  defmodule Anthropic do
    @behaviour DSPex.Predictor
    # Anthropic-specific implementation
  end
end
```

**1.2 Snakepit Integration**
```elixir
defmodule DSPex.Adapters.SnakepitLegacy do
  @behaviour DSPex.Adapter
  
  def init(opts) do
    # Configure Snakepit with Python adapter
    python_config = [
      python_path: "python3",
      script_path: "priv/python/dspy_bridge.py",
      pool_size: opts[:pool_size] || 4
    ]
    
    {:ok, pool} = Snakepit.start_pool(:dspy_legacy, Snakepit.Adapters.Python, python_config)
    {:ok, %{pool: pool}}
  end
  
  def execute(state, operation, params) do
    # Delegate to Snakepit with DSPex error handling
    with {:ok, result} <- Snakepit.execute(state.pool, operation, params) do
      {:ok, result}
    else
      {:error, reason} -> handle_snakepit_error(reason)
    end
  end
end
```

### Phase 2: Core DSPy Features (Months 3-4)

**2.1 Native Implementations**
- Chain-of-Thought (CoT) prompting
- Few-shot learning
- Signature optimization
- Basic retrieval-augmented generation (RAG)

**2.2 Feature Parity Tracking**
```elixir
defmodule DSPex.FeatureRouter do
  @native_features [:signature, :basic_predictor, :cot]
  @legacy_features [:optimizer, :complex_modules, :advanced_rag]
  
  def route(feature, params) do
    if feature in @native_features do
      DSPex.Native.execute(feature, params)
    else
      DSPex.Legacy.execute(feature, params)
    end
  end
end
```

### Phase 3: Advanced Features (Months 5-6)

**3.1 Optimizer Implementation**
- Native implementation of DSPy's optimization algorithms
- Integration with Nx for numerical computations
- Support for custom metrics and objectives

**3.2 Migration Tools**
```elixir
defmodule DSPex.Migration do
  def validate_compatibility(python_program) do
    # Check if Python program can run natively
  end
  
  def suggest_migration_path(python_program) do
    # Analyze and suggest migration steps
  end
  
  def benchmark_native_vs_legacy(program, test_data) do
    # Performance comparison
  end
end
```

## Migration Strategy

### Step 1: Parallel Implementation
1. Add Snakepit as dependency
2. Create `SnakepitLegacy` adapter alongside existing adapters
3. Implement feature flag system for gradual rollout

### Step 2: Incremental Migration
```elixir
# Configuration for gradual migration
config :dspex, :feature_flags,
  use_native_signatures: true,
  use_native_predictors: true,
  use_legacy_optimizer: true,
  fallback_to_legacy: true  # Safety net
```

### Step 3: Performance Validation
- Benchmark native vs Python implementation
- A/B testing in production
- Gradual traffic shifting

## Benefits of This Approach

### 1. **Performance**
- Native operations eliminate IPC overhead
- Direct integration with Elixir ecosystem
- Potential for compilation optimizations

### 2. **Reliability**
- Fewer moving parts (no Python processes for native features)
- Better error handling in native code
- Simplified debugging

### 3. **Ecosystem Integration**
- Direct use of Elixir libraries
- Native integration with Phoenix, LiveView
- Leverages BEAM concurrency model

### 4. **Gradual Migration**
- No breaking changes
- Feature-by-feature migration
- Rollback capability

## Technical Considerations

### 1. **Maintaining Compatibility**
- Keep identical API surface
- Ensure behavior parity with Python DSPy
- Comprehensive test suite comparing outputs

### 2. **Snakepit Enhancements**
Contribute back to Snakepit:
- Circuit breaker functionality
- Advanced error classification
- Performance monitoring hooks

### 3. **Documentation Strategy**
- Clear feature availability matrix
- Migration guides for each component
- Performance comparison documentation

## Success Metrics

1. **Performance**: 10x improvement for native operations
2. **Reliability**: 50% reduction in error rates
3. **Adoption**: 80% of operations using native implementation within 1 year
4. **Developer Experience**: Simplified setup (no Python required for basic features)

## Next Steps

1. **Proof of Concept**: Implement native Signature module
2. **Snakepit Integration**: Create minimal legacy adapter
3. **Benchmarking**: Compare native vs Python performance
4. **Community Feedback**: RFC on approach
5. **Incremental Rollout**: Start with signature validation

## Conclusion

This architecture positions DSPex as the premier Elixir implementation of DSPy concepts while maintaining perfect backward compatibility through Snakepit. The gradual migration path ensures stability while delivering immediate performance benefits for implemented features.
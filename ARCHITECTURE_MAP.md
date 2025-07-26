# DSPex Codebase Architecture Map

## Overview

This document provides a comprehensive map of the DSPex codebase structure, identifying all modules for refactoring, documenting test patterns, dependencies, and coupling points.

## Current Architecture State

### 1. DSPex Core (`/home/home/p/g/n/dspex`)

#### Core Modules
```
lib/dspex/
├── dspex.ex                    # Main API entry point (204 lines)
├── application.ex              # OTP Application supervision
├── config.ex                   # DSPy configuration management
├── settings.ex                 # Runtime settings management
├── pipeline.ex                 # Pipeline orchestration
├── lm.ex                      # Language model abstractions
├── models.ex                  # Model management
├── examples.ex                # Example generation
├── assertions.ex              # Assertion system
└── utils/
    └── id.ex                  # ID generation utilities
```

#### Bridge Components (TO BE MOVED TO SNAKEPIT)
```
lib/dspex/
├── bridge.ex                  # DSPy bridge metaprogramming (451+ lines)
├── bridge/
│   └── tools.ex              # Tool registration system
├── python/
│   └── bridge.ex             # Python execution bridge
├── modules/                  # DSPy module implementations
│   ├── predict.ex            # Basic prediction module
│   ├── chain_of_thought.ex  # Chain of thought reasoning
│   ├── react.ex              # ReAct pattern implementation
│   ├── program_of_thought.ex # Program of thought module
│   ├── multi_chain_comparison.ex # Multi-chain comparison
│   └── retry.ex              # Retry with different prompts
└── native/                   # Native Elixir DSPy features
    ├── signature.ex          # Signature parsing
    ├── template.ex           # Template rendering
    ├── validator.ex          # Data validation
    ├── metrics.ex            # Performance metrics
    └── registry.ex           # Module registry
```

#### Delegated Components (ALREADY MOVED TO SNAKEPIT)
```
lib/dspex/
├── variables.ex              # Delegates to Snakepit.Bridge.Variables
├── context.ex               # Delegates to Snakepit.Bridge.SessionStore
└── context/
    └── monitor.ex           # Context monitoring
```

#### LLM Adapter Infrastructure (KEEP IN DSPEX)
```
lib/dspex/llm/
├── adapter.ex               # Adapter behavior definition
├── client.ex                # LLM client implementation
└── adapters/
    ├── gemini.ex            # Google Gemini adapter
    ├── http.ex              # Generic HTTP adapter
    ├── instructor_lite.ex   # InstructorLite adapter
    ├── mock.ex              # Mock adapter for testing
    └── python.ex            # Python-based LLM adapter
```

### 2. Snakepit Core (`/home/home/p/g/n/dspex/snakepit`)

#### Infrastructure Components
```
lib/snakepit/
├── snakepit.ex              # Main API (execute, execute_in_session)
├── application.ex           # OTP application setup
├── adapter.ex               # Adapter behavior definition
├── session_helpers.ex       # Session management utilities
├── telemetry.ex            # Telemetry events
├── utils.ex                # Utility functions
└── pool/                   # Process pool management
    ├── pool.ex             # Main pool implementation
    ├── registry.ex         # Worker registry
    ├── worker_supervisor.ex # Worker supervision
    ├── worker_starter.ex   # Worker startup logic
    ├── worker_starter_registry.ex # Starter registry
    ├── process_registry.ex # Process tracking
    └── application_cleanup.ex # Cleanup on shutdown
```

### 3. Snakepit gRPC Bridge (`/home/home/p/g/n/dspex/snakepit_grpc_bridge`)

#### Bridge Components
```
lib/snakepit_grpc_bridge/
├── snakepit_grpc_bridge.ex  # Main module
├── application.ex           # Application setup
├── adapter.ex               # gRPC adapter implementation
├── telemetry.ex            # Telemetry integration
├── bridge/                  # Bridge functionality
│   ├── variables.ex         # Variable system
│   ├── session_store.ex     # Session management
│   ├── tool_registry.ex     # Tool registration
│   └── programs.ex          # DSPy program management
├── grpc/                    # gRPC infrastructure
│   ├── server.ex           # gRPC server
│   └── client.ex           # gRPC client
├── schema/                  # Schema management
│   ├── dspy.ex             # DSPy schema
│   └── dspy/
│       └── cache.ex        # Schema caching
└── cognitive/              # Advanced features
    ├── evolution.ex        # Model evolution
    ├── scheduler.ex        # Task scheduling
    └── worker.ex           # Cognitive workers
```

## Dependency Analysis

### Current Dependency Flow
```
DSPex → Snakepit → SnakepitGrpcBridge → Python/gRPC
  ↓        ↓              ↓
  └────────┴──────────────┴──→ External Services (LLMs)
```

### Key Coupling Points

#### 1. DSPex → Snakepit Dependencies
- **Direct Calls**: 50+ instances of `Snakepit.*` calls in DSPex
- **Main APIs Used**:
  - `Snakepit.Python.call/3` - Direct Python execution
  - `Snakepit.execute_in_session/4` - Session-based execution
  - `Snakepit.execute/3` - Stateless execution
  - `Snakepit.get_stats/0` - Pool statistics

#### 2. Module Dependencies
- All DSPex.Modules.* depend on Snakepit for Python execution
- DSPex.Bridge heavily uses Snakepit for DSPy operations
- DSPex.Context delegates entirely to Snakepit.Bridge.SessionStore
- DSPex.Variables delegates entirely to Snakepit.Bridge.Variables

#### 3. Configuration Dependencies
- DSPex relies on Snakepit pool configuration
- Adapter selection happens at Snakepit level
- Session management is handled by Snakepit

## Test Patterns to Preserve

### 1. Unit Test Patterns
```elixir
# Standard ExUnit pattern with async
defmodule Module.Test do
  use ExUnit.Case, async: true
  
  setup do
    # Setup context/session
    {:ok, ctx} = Context.start_link()
    {:ok, ctx: ctx}
  end
  
  describe "feature" do
    test "specific behavior", %{ctx: ctx} do
      # Test implementation
    end
  end
end
```

### 2. Integration Test Patterns
- Python bridge integration tests
- gRPC communication tests
- Session management tests
- Variable system tests

### 3. Property-Based Tests
- Found in `snakepit/test_bridge_quarantine/bridge/property_test.exs`
- Tests invariants of the bridge system

### 4. Mock vs Real Adapter Tests
- Mock adapter for unit testing
- Real adapters for integration testing
- Clear separation between test types

## Modules Requiring Refactoring

### Phase 1: Move DSPy Bridge to Snakepit
1. **DSPex.Bridge** → Snakepit.DSPy.Bridge
2. **DSPex.Bridge.Tools** → Snakepit.Bridge.Tools
3. **DSPex.Python.Bridge** → Snakepit.DSPy.PythonBridge
4. **DSPex.Modules.*** → Snakepit.DSPy.Modules.*
5. **DSPex.Native.*** → Snakepit.DSPy.Native.*

### Phase 2: Update Dependencies
1. Create compatibility layer in DSPex
2. Update all internal references
3. Delegate from DSPex to Snakepit modules

### Phase 3: Clean Architecture
1. Remove deprecated modules from DSPex
2. Update documentation
3. Clean up Python bridge code

## Migration Points

### 1. Namespace Changes
```elixir
# Before
defmodule DSPex.Modules.Predict
defmodule DSPex.Bridge
defmodule DSPex.Native.Signature

# After
defmodule Snakepit.DSPy.Modules.Predict
defmodule Snakepit.DSPy.Bridge
defmodule Snakepit.DSPy.Native.Signature
```

### 2. API Changes
```elixir
# Compatibility layer in DSPex
defmodule DSPex.Modules.Predict do
  @deprecated "Use Snakepit.DSPy.Modules.Predict"
  defdelegate create(signature, opts), to: Snakepit.DSPy.Modules.Predict
end
```

### 3. Configuration Changes
```elixir
# Move DSPy-specific config to Snakepit
config :snakepit,
  dspy_enabled: true,
  dspy_adapters: [...]
```

## Python Components

### DSPex Python Code
```
priv/python/
├── dspy_config.py           # DSPy configuration
├── dspex_helper.py          # Helper functions
└── dspex_adapters/          # Custom adapters
    ├── __init__.py
    └── dspy_grpc.py         # gRPC adapter for DSPy
```

### Snakepit Python Infrastructure
```
snakepit/priv/python/
├── snakepit_bridge/         # Core bridge infrastructure
│   ├── __init__.py
│   ├── base_adapter.py      # Base adapter class
│   ├── serialization.py     # Binary serialization
│   ├── session_context.py   # Session management
│   ├── dspy_integration.py  # DSPy integration
│   ├── variable_aware_mixin.py # Variable system
│   └── adapters/            # Adapter implementations
├── grpc_server.py           # gRPC server
└── setup.py                 # Package setup
```

## Documentation Structure

### Current Documentation
- `/docs/` - Main documentation directory
- `/docs/specs/` - Detailed specifications
- `/docs/prompts/` - Development prompts
- `/README*.md` - Various README files

### Key Architecture Documents
1. `SNAKEPIT_INTEGRATION_PLAN.md` - Integration strategy
2. `SNAKEPIT_CONSOLIDATION_PLAN.md` - Consolidation roadmap
3. `SNAKEPIT_SEPARATION_ARCHITECTURE.md` - Separation plan
4. `SNAKEPIT_CORE_SPECIFICATION.md` - Core specs
5. `SNAKEPIT_GRPC_BRIDGE_SPECIFICATION.md` - Bridge specs

## Summary

The architecture consists of three main components:
1. **DSPex**: High-level orchestration and LLM adapters
2. **Snakepit**: Core infrastructure for pooling and sessions
3. **SnakepitGrpcBridge**: gRPC bridge with DSPy integration

The refactoring plan involves moving all DSPy-specific functionality from DSPex to Snakepit, maintaining compatibility through delegation, and achieving clean architectural separation with single responsibilities for each component.
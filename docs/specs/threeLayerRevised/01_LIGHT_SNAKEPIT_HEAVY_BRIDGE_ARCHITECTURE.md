# Light Snakepit + Heavy Bridge Architecture

## Executive Summary

This document defines the **Light Snakepit + Heavy Bridge** architecture that provides clean separation of concerns between infrastructure, platform, and consumer layers.

**Core Strategy**: Ultra-light infrastructure + Heavy ML platform + Thin orchestration layer

## Architectural Principles

### Clear Separation of Concerns

1. **Snakepit**: Pure infrastructure (process pooling, gRPC transport, session management)
2. **SnakepitGRPCBridge**: Complete ML execution platform (variables, tools, DSPy, Python)
3. **DSPex**: Thin orchestration layer (macros, convenience APIs)

### Single Responsibility

- **Snakepit**: "I manage external processes and gRPC communication"
- **SnakepitGRPCBridge**: "I am the ML execution platform"  
- **DSPex**: "I orchestrate ML workflows"

### Independent Evolution

- **Snakepit**: Stable infrastructure (changes rarely)
- **SnakepitGRPCBridge**: Fast-moving ML platform (changes frequently)
- **DSPex**: User-facing API (evolves based on user needs)

## Target Architecture

### Snakepit (Light Infrastructure)
```
snakepit/
├── lib/snakepit/
│   ├── pool.ex                    # Generic process pooling
│   ├── grpc/
│   │   ├── server.ex             # Generic gRPC server
│   │   ├── client.ex             # Generic gRPC client
│   │   └── endpoint.ex           # gRPC endpoint management
│   ├── session.ex                # Basic session lifecycle
│   ├── adapter.ex                # Adapter behavior/interface
│   └── application.ex            # OTP application
├── priv/proto/
│   └── snakepit.proto            # Basic gRPC protocol
├── test/
├── mix.exs                       # NO dependencies on ML stuff
└── NO PYTHON CODE               # Pure Elixir infrastructure
```

### SnakepitGRPCBridge (Heavy ML Platform)
```
snakepit_grpc_bridge/
├── lib/snakepit_grpc_bridge/
│   ├── adapter.ex                # ML-specific adapter for Snakepit
│   ├── api/                      # Clean API for DSPex
│   │   ├── variables.ex          # Variable management API
│   │   ├── tools.ex              # Tool bridge API
│   │   └── dspy.ex               # DSPy integration API
│   ├── variables/                # Complete variable system
│   │   ├── manager.ex            # Variable lifecycle management
│   │   ├── types.ex              # ML data types (tensor, embedding, etc.)
│   │   └── storage.ex            # Variable storage and serialization
│   ├── tools/                    # Complete tool bridge
│   │   ├── registry.ex           # Tool registration and discovery
│   │   ├── executor.ex           # Tool execution engine
│   │   └── bridge.ex             # Python ↔ Elixir bridge
│   ├── dspy/                     # Complete DSPy integration
│   │   ├── integration.ex        # Core DSPy bridge logic
│   │   ├── workflows.ex          # DSPy workflow patterns
│   │   └── enhanced.ex           # Enhanced DSPy features
│   └── application.ex            # OTP application
├── priv/
│   ├── proto/
│   │   └── ml_bridge.proto       # ML-specific gRPC protocol
│   └── python/                   # ALL Python code
│       └── snakepit_bridge/
│           ├── core/             # Core bridge functionality
│           ├── variables/        # Python variable management
│           ├── tools/            # Python tool execution
│           └── dspy/             # Python DSPy integration
├── test/
└── mix.exs                       # Depends on snakepit
```

### DSPex (Ultra-Thin Consumer)
```
dspex/
├── lib/dspex/
│   ├── bridge.ex                 # defdsyp macro only
│   └── api.ex                    # High-level convenience functions
├── test/
├── mix.exs                       # Depends on snakepit_grpc_bridge
└── NO PYTHON CODE               # Pure orchestration
```

## Key Benefits

### 1. Architectural Clarity
Each layer has a single, clear responsibility:
- **Infrastructure**: Process management and communication
- **Platform**: ML execution capabilities  
- **Consumer**: User-facing orchestration

### 2. Prevents "Disorganized Reality"
- Clear boundaries prevent random code from ending up in wrong layer
- Forced organization through separate projects
- Single responsibility principle enforced at project level

### 3. Future Flexibility
```elixir
# Other bridges can be built on same infrastructure
snakepit_r_bridge/        # R statistics platform
snakepit_node_bridge/     # Node.js platform  
snakepit_go_bridge/       # Go platform
```

### 4. Independent Teams and Evolution
- Different teams can own different layers
- Infrastructure team focuses on performance and reliability
- ML platform team focuses on capabilities and features
- API team focuses on developer experience

## User Experience

### Simple Setup (Most Users)
```elixir
# mix.exs - Users get everything
def deps do
  [{:dspex, "~> 0.2.0"}]  # Pulls snakepit + snakepit_grpc_bridge
end

# config/config.exs - Simple configuration
config :snakepit,
  adapter_module: SnakepitGRPCBridge.Adapter

# Usage - Same clean API
DSPex.predict("question -> answer", %{question: "What is Elixir?"})
```

### Advanced Setup (Power Users)
```elixir
# For users who want just the ML platform
def deps do
  [{:snakepit_grpc_bridge, "~> 0.1.0"}]
end

# Direct API access
SnakepitGRPCBridge.API.DSPy.enhanced_predict(session_id, signature, inputs)
SnakepitGRPCBridge.API.Variables.create(session_id, name, type, value)
SnakepitGRPCBridge.API.Tools.register_elixir_function(session_id, name, fun)
```

### Infrastructure-Only Setup (Other Domains)
```elixir
# For non-ML use cases
def deps do
  [{:snakepit, "~> 0.1.0"}]
end

config :snakepit,
  adapter_module: MyCustomBridge.Adapter

# Use Snakepit for any external process management
Snakepit.execute_in_session(session_id, "my_command", args)
```

## Migration Benefits

### 1. Clean Extraction
- Move all ML-specific code out of infrastructure
- Infrastructure becomes truly generic and reusable
- ML platform contains all domain knowledge

### 2. Clear Dependencies
- `snakepit` has no ML dependencies
- `snakepit_grpc_bridge` depends on `snakepit`
- `dspex` depends on `snakepit_grpc_bridge`

### 3. Forced Organization
- Can't put variable logic in infrastructure layer
- Can't put gRPC transport logic in consumer layer
- Each piece has obvious home

### 4. Future Evolution
- Infrastructure changes rarely (stable API)
- ML platform changes frequently (new features)
- Consumer layer adapts to user needs
- No conflicts between evolution speeds

This architecture addresses the original concern: "*unless we have a clean implementation of the variables, tool bridge and grpc in snakepit that's extensible and configurable*" by putting the variables, tool bridge, and gRPC **in the ML platform layer** where they belong, while keeping snakepit as pure, extensible infrastructure.
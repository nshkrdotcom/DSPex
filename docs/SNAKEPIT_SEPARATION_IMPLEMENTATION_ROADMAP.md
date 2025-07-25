# Snakepit Separation Implementation Roadmap

## Executive Summary

This roadmap outlines the detailed implementation timeline for separating Snakepit into two focused packages: Snakepit Core (infrastructure) and SnakepitGrpcBridge (domain logic). The implementation spans 4 weeks with parallel development tracks and comprehensive validation.

## Timeline Overview

```
Week 1: Core Separation & Package Creation
Week 2: Integration & API Stabilization  
Week 3: Testing & Performance Validation
Week 4: Documentation & Release Preparation
```

**Total Effort**: ~80 hours (2 full-time weeks equivalent)  
**Risk Level**: Medium (breaking changes, but clean separation)  
**Success Criteria**: Zero regression, clean architecture, backward compatibility

## Week 1: Core Separation & Package Creation

### Day 1: Analysis & Planning
**Focus**: Deep codebase analysis and separation planning  
**Duration**: 8 hours

#### Morning (4 hours): Codebase Analysis
```bash
# Analyze current Snakepit structure
find snakepit -name "*.ex" -exec wc -l {} + | sort -n
# Expected: ~2500 lines total

# Identify dependencies
cd snakepit && mix deps.tree
# Document all external dependencies

# Analyze module interdependencies  
mix xref graph --format dot
# Generate dependency visualization
```

**Tasks**:
- [ ] Complete file inventory with line counts
- [ ] Document all module interdependencies
- [ ] Identify shared utilities and constants
- [ ] Map configuration dependencies
- [ ] Catalog all test files and fixtures

**Deliverables**:
- Detailed separation matrix (which files go where)
- Dependency graph visualization
- Risk assessment for each module move
- Test coverage impact analysis

#### Afternoon (4 hours): Package Structure Design
```bash
# Create package structure templates
mkdir -p /tmp/snakepit_separation/{snakepit_core,snakepit_grpc_bridge}

# Design directory structures
tree snakepit_core/
tree snakepit_grpc_bridge/
```

**Tasks**:
- [ ] Design Snakepit Core directory structure
- [ ] Design SnakepitGrpcBridge directory structure  
- [ ] Plan module namespace mappings
- [ ] Design adapter interface specifications
- [ ] Create configuration migration plan

**Deliverables**:
- Complete directory structure designs
- Module mapping spreadsheet
- Adapter interface specification
- Configuration migration checklist

### Day 2: Snakepit Core Extraction
**Focus**: Extract and clean up core infrastructure  
**Duration**: 8 hours

#### Morning (4 hours): Module Extraction
```bash
# Create new Snakepit Core package
cd snakepit
git checkout -b core-extraction

# Remove bridge modules (backup first)
mkdir -p ../temp_extracted_modules
mv lib/snakepit/bridge ../temp_extracted_modules/
mv lib/snakepit/variables.ex ../temp_extracted_modules/
mv priv/python ../temp_extracted_modules/
mv grpc ../temp_extracted_modules/
```

**Tasks**:
- [ ] Remove bridge-specific modules from core
- [ ] Clean up imports and references  
- [ ] Update main Snakepit module interface
- [ ] Remove bridge-specific configuration
- [ ] Create adapter behavior definition

**Code Changes**:
```elixir
# lib/snakepit.ex - Cleaned up interface
defmodule Snakepit do
  # Remove: discover_schema, call_dspy, variables functions
  # Keep: execute, execute_in_session, execute_stream, get_stats
  
  # Add deprecation warnings for removed functions
  def discover_schema(_path, _opts \\ []) do
    raise "Moved to SnakepitGrpcBridge.discover_schema/2"
  end
end
```

#### Afternoon (4 hours): Core Infrastructure Polish
```elixir
# lib/snakepit/adapter.ex - New behavior definition
defmodule Snakepit.Adapter do
  @callback execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback uses_grpc?() :: boolean()
  @callback supports_streaming?() :: boolean()
  
  @optional_callbacks [uses_grpc?: 0, supports_streaming?: 0]
end
```

**Tasks**:
- [ ] Implement adapter behavior and validation
- [ ] Update pool management for adapter pattern
- [ ] Clean up session helpers (remove domain logic)
- [ ] Update configuration validation
- [ ] Create migration helper functions

**Deliverables**:
- Working Snakepit Core package (infrastructure only)
- Complete adapter behavior definition
- Updated tests for core functionality
- Migration helper utilities

### Day 3: SnakepitGrpcBridge Creation
**Focus**: Create bridge package with moved functionality  
**Duration**: 8 hours

#### Morning (4 hours): Package Bootstrap
```bash
# Create new bridge package
mkdir -p ../snakepit_grpc_bridge
cd ../snakepit_grpc_bridge
mix new . --app snakepit_grpc_bridge --module SnakepitGrpcBridge

# Create directory structure
mkdir -p lib/snakepit_grpc_bridge/{dspy,variables,tools,grpc,session}
mkdir -p priv/python
mkdir -p test/{snakepit_grpc_bridge,integration,support}
```

**Tasks**:
- [ ] Initialize bridge package with Mix
- [ ] Create complete directory structure
- [ ] Setup dependencies in mix.exs
- [ ] Configure application environment
- [ ] Create basic module skeletons

**mix.exs Configuration**:
```elixir
defp deps do
  [
    {:snakepit, "~> 0.4"},
    {:grpc, "~> 0.8"},
    {:protobuf, "~> 0.11"},
    {:jason, "~> 1.4"},
    {:httpoison, "~> 2.0"}
  ]
end
```

#### Afternoon (4 hours): Move Bridge Modules
```bash
# Move extracted modules to bridge package
mv ../temp_extracted_modules/bridge/* lib/snakepit_grpc_bridge/
mv ../temp_extracted_modules/variables.ex lib/snakepit_grpc_bridge/variables.ex
mv ../temp_extracted_modules/python/* priv/python/
mv ../temp_extracted_modules/grpc grpc/
```

**Tasks**:
- [ ] Move all bridge modules to new package
- [ ] Update module namespaces (Snakepit.Bridge → SnakepitGrpcBridge)
- [ ] Fix all internal imports and references
- [ ] Update module documentation
- [ ] Create adapter implementation

**Key Module Updates**:
```elixir
# lib/snakepit_grpc_bridge.ex - Main interface
defmodule SnakepitGrpcBridge do
  def start_bridge(opts \\ []) do
    Application.put_env(:snakepit, :adapter_module, __MODULE__.Adapter)
    # ... initialization logic
  end
end

# lib/snakepit_grpc_bridge/adapter.ex - Snakepit integration
defmodule SnakepitGrpcBridge.Adapter do
  @behaviour Snakepit.Adapter
  
  def execute(command, args, opts) do
    # Route commands to appropriate modules
  end
end
```

### Day 4: Basic Integration
**Focus**: Connect packages and basic functionality testing  
**Duration**: 8 hours

#### Morning (4 hours): Adapter Implementation
```elixir
# Complete adapter implementation
defmodule SnakepitGrpcBridge.Adapter do
  @impl Snakepit.Adapter
  def execute(command, args, opts) do
    case command do
      "call_dspy_bridge" -> SnakepitGrpcBridge.DSPy.execute_command(args, opts)
      "discover_dspy_schema" -> SnakepitGrpcBridge.DSPy.discover_schema(args["module_path"], opts)
      "get_variable" -> SnakepitGrpcBridge.Variables.get(opts[:session_id], args["identifier"])
      "set_variable" -> SnakepitGrpcBridge.Variables.set(opts[:session_id], args["identifier"], args["value"])
      # ... all other command mappings
      _ -> {:error, {:unknown_command, command}}
    end
  end
  
  @impl Snakepit.Adapter
  def uses_grpc?, do: true
  
  @impl Snakepit.Adapter
  def supports_streaming?, do: true
end
```

**Tasks**:
- [ ] Complete adapter command routing
- [ ] Implement bridge initialization logic
- [ ] Test basic package compilation
- [ ] Verify dependency resolution
- [ ] Create integration test scaffold

#### Afternoon (4 hours): Smoke Testing
```bash
# Test Snakepit Core
cd snakepit
mix deps.get && mix compile && mix test

# Test SnakepitGrpcBridge  
cd ../snakepit_grpc_bridge
mix deps.get && mix compile && mix test
```

**Tasks**:
- [ ] Fix all compilation errors
- [ ] Resolve dependency conflicts
- [ ] Basic smoke tests for both packages
- [ ] Document known issues and limitations
- [ ] Create integration testing plan

**Deliverables**:
- Both packages compile without errors
- Basic functionality tests pass
- Clear documentation of remaining work
- Integration test plan for Week 2

### Day 5: Buffer Day & Documentation
**Focus**: Address any blockers and create initial documentation  
**Duration**: 8 hours

**Tasks**:
- [ ] Fix any remaining compilation issues
- [ ] Address failed tests from Day 4
- [ ] Create initial README files for both packages
- [ ] Document API changes and migration notes
- [ ] Plan Week 2 integration work

## Week 2: Integration & API Stabilization

### Day 6-7: DSPex Integration
**Focus**: Update DSPex to use new architecture  
**Duration**: 16 hours

#### Update Dependencies and Configuration
```elixir
# dspex/mix.exs
defp deps do
  [
    # Remove: {:snakepit, path: "../snakepit"},
    {:snakepit_grpc_bridge, path: "../snakepit_grpc_bridge"},
    # ... other deps unchanged
  ]
end
```

```elixir
# config/config.exs  
config :snakepit,
  adapter_module: SnakepitGrpcBridge.Adapter,
  pooling_enabled: true,
  pool_size: 4

config :snakepit_grpc_bridge,
  python_executable: "python3",
  grpc_port: 0,
  enable_telemetry: true
```

#### Update DSPex.Bridge Module
```elixir
# Major refactoring of lib/dspex/bridge.ex
defmodule DSPex.Bridge do
  # Update all function calls to use SnakepitGrpcBridge APIs
  
  def call_dspy(module_path, function_name, positional_args, keyword_args, opts) do
    session_id = opts[:session_id] || ID.generate("session")
    
    SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
      "class_path" => module_path,
      "method" => function_name,
      "args" => positional_args,
      "kwargs" => keyword_args
    })
  end
  
  def discover_schema(module_path, opts \\ []) do
    SnakepitGrpcBridge.discover_schema(module_path, opts)
  end
  
  # Update all other functions...
end
```

**Daily Tasks**:
- Day 6: Update dependencies, configuration, and core bridge functions
- Day 7: Update variables delegation, test all examples, fix integration issues

### Day 8-9: API Stabilization  
**Focus**: Clean up APIs and ensure backward compatibility  
**Duration**: 16 hours

#### API Compatibility Layer
```elixir
# Maintain backward compatibility where possible
defmodule DSPex.Variables do
  @deprecated "Use SnakepitGrpcBridge.Variables instead"
  defdelegate get(session_id, identifier, default \\ nil), to: SnakepitGrpcBridge.Variables
  
  @deprecated "Use SnakepitGrpcBridge.Variables instead"  
  defdelegate set(session_id, identifier, value, opts \\ []), to: SnakepitGrpcBridge.Variables
  
  # Continue for all functions...
end
```

#### Integration Testing Framework
```elixir
defmodule DSPex.IntegrationTestHelpers do
  def setup_bridge_for_testing do
    {:ok, bridge_info} = SnakepitGrpcBridge.start_bridge([
      python_executable: "python3",
      grpc_port: 0,
      enable_debug_logging: true
    ])
    
    bridge_info
  end
  
  def cleanup_bridge do
    SnakepitGrpcBridge.stop_bridge()
  end
end
```

**Daily Tasks**:
- Day 8: Create compatibility layers, stabilize public APIs, comprehensive error handling
- Day 9: Integration testing framework, test all DSPex functionality, fix discovered issues

### Day 10: End-to-End Validation
**Focus**: Complete integration testing and bug fixes  
**Duration**: 8 hours

**Tasks**:
- [ ] Run complete DSPex test suite
- [ ] Test all example files
- [ ] Verify Python bridge integration
- [ ] Fix any remaining integration bugs
- [ ] Performance comparison with pre-migration

## Week 3: Testing & Performance Validation

### Day 11-12: Comprehensive Testing
**Focus**: Complete test coverage and reliability  
**Duration**: 16 hours

#### Test Suite Organization
```
test/
├── snakepit_core/
│   ├── pool_test.exs
│   ├── session_test.exs
│   └── adapter_test.exs
├── snakepit_grpc_bridge/
│   ├── dspy_test.exs
│   ├── variables_test.exs
│   ├── tools_test.exs
│   └── integration_test.exs
└── dspex/
    ├── bridge_integration_test.exs
    └── end_to_end_test.exs
```

#### Performance Test Suite
```elixir
defmodule PerformanceValidation do
  def run_comprehensive_benchmarks do
    # Basic operations
    benchmark_basic_pooling()
    benchmark_session_affinity()
    
    # Bridge operations  
    benchmark_dspy_operations()
    benchmark_variables_operations()
    benchmark_tool_calling()
    
    # End-to-end workflows
    benchmark_complete_workflows()
  end
end
```

**Daily Tasks**:
- Day 11: Unit tests for all core modules, bridge module tests, mock Python server for testing
- Day 12: Integration tests, performance benchmarks, stress testing under load

### Day 13-14: Performance Optimization
**Focus**: Optimize performance and resource usage  
**Duration**: 16 hours

#### Performance Targets
| Metric | Target | Current | Optimization Needed |
|--------|--------|---------|-------------------|
| Pool startup | < 2s | TBD | Connection pooling |
| DSPy call latency | < 50ms | TBD | Request batching |
| Memory usage | < 200MB | TBD | Resource cleanup |
| Variable ops | < 5ms | TBD | In-memory caching |

#### Optimization Areas
```elixir
# Connection pooling for gRPC
defmodule SnakepitGrpcBridge.GRPC.Pool do
  def get_connection(opts \\ []) do
    # Reuse persistent connections
  end
end

# Request batching
defmodule SnakepitGrpcBridge.RequestBatcher do
  def batch_requests(requests, timeout \\ 100) do
    # Batch multiple requests for efficiency
  end
end
```

**Daily Tasks**:
- Day 13: Profile performance bottlenecks, implement connection pooling, optimize gRPC communication
- Day 14: Memory optimization, request batching, final performance validation

### Day 15: Load Testing & Reliability
**Focus**: Stress testing and reliability validation  
**Duration**: 8 hours

#### Load Testing Scenarios
```elixir
defmodule LoadTesting do
  def run_load_tests do
    # Concurrent sessions
    test_concurrent_sessions(100)
    
    # High-frequency operations
    test_high_frequency_calls(1000, per_second: 100)
    
    # Memory stress test
    test_memory_pressure()
    
    # Failure recovery
    test_python_bridge_restart()
  end
end
```

**Tasks**:
- [ ] 100 concurrent sessions test
- [ ] 1000 requests/second sustained load
- [ ] Memory leak detection
- [ ] Bridge failure recovery testing
- [ ] Long-running stability test (4+ hours)

## Week 4: Documentation & Release Preparation

### Day 16-17: Documentation
**Focus**: Complete documentation for both packages  
**Duration**: 16 hours

#### Documentation Structure
```
docs/
├── snakepit_core/
│   ├── README.md
│   ├── API_REFERENCE.md
│   ├── CONFIGURATION.md
│   └── ADAPTER_GUIDE.md
├── snakepit_grpc_bridge/
│   ├── README.md
│   ├── API_REFERENCE.md
│   ├── DSPY_INTEGRATION.md
│   ├── VARIABLES_GUIDE.md
│   └── TOOLS_REFERENCE.md
└── migration/
    ├── MIGRATION_GUIDE.md
    ├── BREAKING_CHANGES.md
    └── FAQ.md
```

#### API Documentation Generation
```bash
# Generate comprehensive API docs
cd snakepit && mix docs
cd ../snakepit_grpc_bridge && mix docs

# Validate documentation completeness
mix docs --formatter html --output doc
# Should show 100% module documentation coverage
```

**Daily Tasks**:
- Day 16: Core package documentation, bridge package documentation, API reference generation
- Day 17: Migration guides, example updates, FAQ creation, documentation review

### Day 18-19: Release Preparation
**Focus**: Prepare packages for release  
**Duration**: 16 hours

#### Release Checklist - Snakepit Core
- [ ] Version bump to 0.4.0 (breaking change)
- [ ] CHANGELOG.md with breaking changes documented
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Performance within targets
- [ ] Security review completed

#### Release Checklist - SnakepitGrpcBridge  
- [ ] Version set to 0.1.0 (initial release)
- [ ] CHANGELOG.md created
- [ ] All functionality tested
- [ ] Python dependencies documented
- [ ] gRPC protocols validated
- [ ] Tool system working

#### Release Process
```bash
# Snakepit Core release
cd snakepit
git tag v0.4.0
git push origin v0.4.0
mix hex.publish --dry-run
mix hex.publish

# SnakepitGrpcBridge release
cd ../snakepit_grpc_bridge  
git tag v0.1.0
git push origin v0.1.0
mix hex.publish --dry-run
mix hex.publish

# DSPex update
cd ../dspex
# Update to use published packages
git tag v0.4.0
git push origin v0.4.0
```

**Daily Tasks**:
- Day 18: Release preparation, version management, publishing dry runs
- Day 19: Final testing, official releases, documentation deployment

### Day 20: Final Validation & Deployment
**Focus**: Final validation and production readiness  
**Duration**: 8 hours

#### Final Validation Checklist
- [ ] All packages published successfully
- [ ] Example applications work with published packages
- [ ] Migration guide tested on fresh installation
- [ ] Performance targets met
- [ ] No regressions from pre-migration functionality
- [ ] Documentation deployed and accessible

#### Post-Release Tasks
- [ ] Update project README files
- [ ] Create release announcements
- [ ] Update example applications
- [ ] Monitor for community feedback
- [ ] Plan future development roadmap

## Resource Requirements

### Development Environment
- **Hardware**: 16GB RAM, SSD storage for fast compilation
- **Software**: Elixir 1.14+, Python 3.9+, Git, Mix
- **Network**: Stable internet for dependency resolution

### Dependencies
- **Elixir Packages**: Mix, ExUnit, ExDoc, Credo
- **Python Packages**: dspy-ai, grpcio, protobuf
- **Tools**: Docker (optional for isolated testing)

### Team Allocation
- **Primary Developer**: 40 hours/week for 4 weeks
- **Testing Support**: 10 hours/week for weeks 2-3
- **Documentation Review**: 5 hours in week 4

## Risk Management

### High Risk Items
1. **Python Bridge Integration**: Complex gRPC setup
   - **Mitigation**: Extensive testing, fallback to simpler implementation
2. **Performance Regression**: Additional abstraction layers
   - **Mitigation**: Continuous benchmarking, optimization sprint
3. **Breaking Changes**: User code modifications required
   - **Mitigation**: Comprehensive compatibility layer, migration tools

### Medium Risk Items
1. **Dependency Conflicts**: New package dependency tree
   - **Mitigation**: Careful version management, testing matrix
2. **Documentation Gaps**: Complex migration process
   - **Mitigation**: Step-by-step guides, worked examples

### Low Risk Items
1. **Release Timing**: Coordination between packages
   - **Mitigation**: Staged release process, clear versioning

## Success Metrics

### Technical Metrics
- **Performance**: < 10% regression in any benchmark
- **Reliability**: 99.9% test pass rate
- **Coverage**: > 90% test coverage for new code
- **Documentation**: 100% public API documented

### Architectural Metrics
- **Separation**: Snakepit Core < 1000 lines of code
- **Coupling**: Zero direct dependencies from Core to Bridge
- **Extensibility**: At least 2 different bridge types possible
- **Maintainability**: Clear module boundaries, single responsibility

### User Experience Metrics
- **Migration**: Zero breaking changes for typical DSPex usage
- **Documentation**: Complete migration guide with worked examples
- **Performance**: User-perceived performance maintained or improved
- **Reliability**: No regression in functionality

## Conclusion

This roadmap provides a systematic approach to separating Snakepit while maintaining functionality and performance. The 4-week timeline allows for thorough testing and validation while minimizing risk to existing users.

The resulting architecture creates a solid foundation for future development with clean separation of concerns, improved testability, and extensibility for multiple bridge types.
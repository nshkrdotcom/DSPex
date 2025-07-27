# MIGRATION_PLAN.md
## The Master Migration Plan

**Objective:** High-level, staged plan for refactoring the existing codebase into the target 3-layer architecture.

---

## Executive Summary

This migration plan transforms the current mixed-concern architecture into a clean 3-layer system:

1. **Snakepit** - Pure infrastructure for process lifecycle management
2. **SnakepitGRPCBridge** - Complete ML platform with all domain logic
3. **DSPex** - Thin consumer layer with intuitive APIs

The migration follows a careful 4-stage approach to minimize risk and maintain functionality throughout the transition.

---

## Stage 0: Purify Infrastructure Layer
**Duration:** 1-2 weeks  
**Risk Level:** Low  
**Rollback Strategy:** Git revert

### Objectives
- Remove all ML-specific code from Snakepit
- Establish clean adapter boundaries
- Ensure infrastructure remains fully functional

### Actions

#### 0.1 Create Migration Branch
```bash
git checkout -b feature/three-layer-migration
git checkout -b stage-0-purify-snakepit
```

#### 0.2 Move Python Code (from REPORT_INFRASTRUCTURE.md)
1. Create directory structure in snakepit_grpc_bridge:
   ```bash
   mkdir -p snakepit_grpc_bridge/priv/python
   mkdir -p snakepit_grpc_bridge/priv/proto
   ```

2. Move all Python code:
   ```bash
   mv snakepit/priv/python/* snakepit_grpc_bridge/priv/python/
   mv snakepit/priv/proto/* snakepit_grpc_bridge/priv/proto/
   ```

3. Remove Python artifacts:
   ```bash
   rm -rf snakepit/priv/python
   rm -rf snakepit/priv/proto
   rm snakepit/priv/python/server.log
   ```

#### 0.3 Clean Adapter Contract
1. Update `snakepit/lib/snakepit/adapter.ex`:
   - Remove `uses_grpc?/0` callback
   - Remove cognitive-specific callbacks
   - Keep only generic process management callbacks

2. Update all references to removed callbacks in:
   - `snakepit/lib/snakepit/pool/pool.ex`
   - `snakepit/lib/snakepit/generic_worker.ex`

#### 0.4 Update Documentation
1. Move bridge-specific docs to platform:
   ```bash
   mv snakepit/README_BIDIRECTIONAL_TOOL_BRIDGE.md snakepit_grpc_bridge/docs/
   mv snakepit/README_GRPC.md snakepit_grpc_bridge/docs/
   mv snakepit/README_UNIFIED_GRPC_BRIDGE.md snakepit_grpc_bridge/docs/
   ```

2. Update `snakepit/README.md` to reflect pure infrastructure focus

### Validation Criteria
- [ ] Snakepit contains zero Python files
- [ ] Snakepit contains zero .proto files  
- [ ] All tests in snakepit/test pass
- [ ] Adapter contract is protocol-agnostic
- [ ] Documentation reflects infrastructure focus

---

## Stage 1: Establish Platform Foundation
**Duration:** 2-3 weeks  
**Risk Level:** Medium  
**Rollback Strategy:** Feature flag

### Objectives
- Create complete platform structure
- Establish clean APIs
- Ensure platform can function independently

### Actions

#### 1.1 Create Platform Structure (from REPORT_PLATFORM.md)
```bash
# Create directory structure
mkdir -p snakepit_grpc_bridge/lib/snakepit_grpc_bridge/{api,bridge,contracts,grpc,python,schema,session,variables}
mkdir -p snakepit_grpc_bridge/priv/python/{snakepit_bridge,dspex}
```

#### 1.2 Move Elixir Platform Code
1. From DSPex to SnakepitGRPCBridge:
   ```elixir
   # Move bridge implementation
   mv lib/dspex/bridge/* snakepit_grpc_bridge/lib/snakepit_grpc_bridge/bridge/
   
   # Move contracts
   mv lib/dspex/contract* snakepit_grpc_bridge/lib/snakepit_grpc_bridge/contracts/
   
   # Move Python bridge
   mv lib/dspex/python/* snakepit_grpc_bridge/lib/snakepit_grpc_bridge/python/
   ```

2. Update module names and references

#### 1.3 Implement Clean APIs
Create public API modules as identified in REPORT_PLATFORM.md:
```elixir
# snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/
- dspy.ex         # DSPy operations
- sessions.ex     # Session management  
- tools.ex        # Tool bridge
- variables.ex    # Variable management
```

#### 1.4 Update Adapter Implementation
1. Move current adapter from snakepit to platform
2. Update to use new internal structure
3. Ensure adapter properly implements Snakepit.Adapter behaviour

#### 1.5 Integrate Process Backend (from REPORT_PROCESS_MANAGEMENT.md)
1. Implement ProcessBackend behaviour in platform
2. Create Systemd and Setsid backends
3. Wire backends into adapter's start_worker callback

### Validation Criteria
- [ ] Platform has complete directory structure
- [ ] All Python code consolidated in platform
- [ ] Clean API modules exist and compile
- [ ] Platform adapter passes Snakepit.Adapter validation
- [ ] Basic integration test passes

---

## Stage 2: Migrate Core Functionality
**Duration:** 3-4 weeks  
**Risk Level:** High  
**Rollback Strategy:** Parallel run

### Objectives
- Migrate all ML functionality to platform
- Update DSPex to use platform APIs
- Maintain backward compatibility

### Actions

#### 2.1 Migrate Variable System
1. Consolidate variable implementations:
   - Merge DSPex.Variables functionality into platform
   - Enhance platform's variable store with DSPex types
   - Create unified variable API

2. Update DSPex.Variables to delegate:
   ```elixir
   defmodule DSPex.Variables do
     defdelegate get(session_id, key, default), to: SnakepitGRPCBridge.API.Variables
     # ... other delegations
   end
   ```

#### 2.2 Migrate Tool System
1. Move tool registry and executor to platform
2. Implement bidirectional tool discovery
3. Update DSPex.Bridge.Tools to use platform API

#### 2.3 Migrate DSPy Integration
1. Consolidate Python DSPy helpers
2. Move schema discovery to platform
3. Update bridge macros to use platform

#### 2.4 Create Compatibility Layer
1. Maintain existing DSPex APIs
2. Route all operations through platform
3. Add deprecation warnings where appropriate

### Validation Criteria
- [ ] All DSPex tests still pass
- [ ] Platform handles all ML operations
- [ ] No direct Python calls from DSPex
- [ ] Examples run without modification
- [ ] Performance benchmarks show no regression

---

## Stage 3: Refactor Consumer Layer
**Duration:** 2 weeks  
**Risk Level:** Medium  
**Rollback Strategy:** API versioning

### Objectives
- Simplify DSPex to thin orchestration layer
- Implement new consumer-friendly API
- Remove all implementation code

### Actions

#### 3.1 Implement New API (from REPORT_CONSUMER_API.md)
```elixir
defmodule DSPex do
  # Simple, intuitive functions
  def ask(question, opts \\ [])
  def think(question, opts \\ [])
  def solve(question, opts \\ [])
  def extract(text, schema, opts \\ [])
  def classify(text, categories, opts \\ [])
  
  # Composition
  def operation(signature, opts \\ [])
  def pipeline(operations)
  def run(pipeline, input, opts \\ [])
end
```

#### 3.2 Remove Implementation Code
1. Delete all implementation modules from DSPex
2. Keep only thin delegation/orchestration code
3. Remove Python code from DSPex

#### 3.3 Update Examples
1. Create new examples using simplified API
2. Keep old examples with compatibility layer
3. Add migration guide for users

#### 3.4 Optimize Startup
1. Remove complex configuration requirements
2. Implement smart defaults
3. Enable zero-config usage

### Validation Criteria
- [ ] New API is fully functional
- [ ] DSPex contains <1000 lines of code
- [ ] Examples are dramatically simpler
- [ ] Zero configuration required for basic usage
- [ ] Old API still works with deprecation warnings

---

## Stage 4: Production Hardening
**Duration:** 2 weeks  
**Risk Level:** Low  
**Rollback Strategy:** Configuration

### Objectives
- Optimize performance
- Add production features
- Complete documentation

### Actions

#### 4.1 Performance Optimization
1. Implement connection pooling for gRPC
2. Add caching layers where appropriate
3. Optimize serialization/deserialization
4. Profile and eliminate bottlenecks

#### 4.2 Production Features
1. Implement comprehensive telemetry
2. Add health checks and monitoring
3. Configure resource limits
4. Set up proper logging

#### 4.3 Documentation
1. Complete API documentation
2. Create architecture diagrams
3. Write deployment guides
4. Add troubleshooting guides

#### 4.4 Testing
1. Comprehensive integration tests
2. Load testing and benchmarks
3. Chaos testing for fault tolerance
4. End-to-end example validation

### Validation Criteria
- [ ] All tests pass (unit, integration, e2e)
- [ ] Performance meets or exceeds current system
- [ ] Documentation is complete
- [ ] Monitoring and alerting configured
- [ ] Production deployment successful

---

## Implementation Timeline

```
Week 1-2:   Stage 0 - Purify Infrastructure
Week 3-5:   Stage 1 - Platform Foundation  
Week 6-9:   Stage 2 - Migrate Functionality
Week 10-11: Stage 3 - Refactor Consumer
Week 12-13: Stage 4 - Production Hardening
Week 14:    Buffer & Final Testing
```

## Success Metrics

### Technical Metrics
- **Code Separation**: Each layer has clear boundaries with no cross-contamination
- **API Simplicity**: 80% reduction in consumer boilerplate code
- **Performance**: No degradation in throughput or latency
- **Reliability**: Zero increase in error rates

### Architecture Metrics
- **Coupling**: Layers communicate only through defined contracts
- **Cohesion**: Each layer has a single, clear responsibility  
- **Extensibility**: New adapters can be added without touching core
- **Maintainability**: Each layer can be modified independently

### Developer Experience
- **Onboarding Time**: New developers productive in <1 day
- **API Intuitiveness**: Common tasks require <5 lines of code
- **Error Messages**: Clear, actionable error messages
- **Documentation**: Complete, accurate, and helpful

## Risk Management

### Critical Path Items
1. Python code migration (Stage 0)
2. Adapter implementation (Stage 1)
3. Backward compatibility (Stage 2)
4. API design (Stage 3)

### Mitigation Strategies
- Feature flags for gradual rollout
- Parallel run capability
- Comprehensive test coverage
- Regular architecture reviews
- Clear rollback procedures

## Communication Plan

### Stakeholders
- Development team
- DevOps team  
- Product owners
- End users

### Updates
- Weekly progress reports
- Stage completion announcements
- Migration guides for users
- Architecture decision records

---

This migration plan provides a systematic approach to achieving the target 3-layer architecture while minimizing risk and maintaining system functionality throughout the transition.
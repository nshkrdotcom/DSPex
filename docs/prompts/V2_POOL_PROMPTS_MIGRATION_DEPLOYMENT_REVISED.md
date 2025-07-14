# V2 Pool Implementation Prompts - Migration & Deployment (REVISED)

## Session M.1: Migration Planning

### Prompt M.1.1 - Assess Current State
```
We're implementing the migration and deployment phase of the V2 Pool design.

First, read these files to understand requirements:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md section "Migration Strategy"
2. Check current pool usage: grep -r "SessionPool" lib/
3. Review existing configurations: ls config/
4. Check: ls lib/dspex/python_bridge/migration/

Analyze current state:
1. List all modules using the old pool
2. Identify configuration dependencies
3. Find hardcoded pool references
4. Check test dependencies
5. Document integration points

Show me:
1. Complete usage analysis
2. Dependency graph
3. Migration complexity assessment
```

### Prompt M.1.2 - Create Migration Plan
```
Let's create a detailed migration plan.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md migration phases
2. Your usage analysis from previous prompt
3. Risk assessment criteria

Create docs/V2_POOL_MIGRATION_PLAN.md with:
1. Executive summary
2. Phase breakdown (Preparation, Parallel Run, Switchover, Cleanup)
3. Timeline with milestones
4. Risk mitigation strategies
5. Rollback procedures
6. Success criteria

Show me:
1. Complete migration plan
2. Critical path items
3. Go/no-go decision points
```

### Prompt M.1.3 - Compatibility Analysis
```
Let's analyze compatibility requirements.

First, check:
1. Current pool API: read lib/dspex/python_bridge/session_pool.ex
2. New pool API: read lib/dspex/python_bridge/session_pool_v2.ex
3. Interface differences
4. Behavioral changes

Document compatibility:
1. API differences table
2. Behavior changes list
3. Breaking changes identified
4. Compatibility layer needs
5. Migration effort per module

Show me:
1. Compatibility analysis
2. Required adapter functions
3. Estimated effort
```

## Session M.2: Feature Flags

### Prompt M.2.1 - Implement Feature Flag System
```
Let's implement feature flags for gradual rollout.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md section "Feature Flags"
2. Check existing config patterns: grep -r "Application.get_env" lib/
3. Check: ls lib/dspex/python_bridge/feature_flags.ex

Create lib/dspex/python_bridge/feature_flags.ex with:
1. Module with flag definitions
2. Runtime flag checking functions
3. Environment-based overrides
4. Percentage rollout support
5. Flag state caching

Show me:
1. Complete feature flag module
2. How flags are checked
3. Configuration approach
```

### Prompt M.2.2 - Integrate Flags with Pool
```
Let's integrate feature flags with pool selection.

First, read:
1. Current factory pattern: lib/dspex/factory.ex
2. How adapters are selected
3. Your feature_flags.ex module

Update pool selection to:
1. Check v2_pool_enabled flag
2. Support percentage rollout
3. Allow per-session overrides
4. Log flag decisions
5. Emit telemetry for monitoring

Show me:
1. Updated factory code
2. How rollout percentage works
3. Override mechanisms
```

### Prompt M.2.3 - Test Feature Flags
```
Let's test the feature flag system.

Create test/dspex/python_bridge/feature_flags_test.exs:
1. Test flag checking logic
2. Test percentage rollout distribution
3. Test environment overrides
4. Test caching behavior
5. Test telemetry emission

Also test integration:
1. Pool selection with flags
2. Gradual rollout simulation
3. Flag state changes

Run tests and show results.
```

## Session M.3: Compatibility Layer

### Prompt M.3.1 - Create Adapter Module
```
Let's create a compatibility adapter.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md compatibility section
2. API differences identified earlier
3. Check: ls lib/dspex/python_bridge/pool_adapter.ex

Create lib/dspex/python_bridge/pool_adapter.ex:
1. Behaviour matching old pool interface
2. Translation to V2 pool calls
3. Response format conversion
4. Error mapping
5. Deprecation warnings

Show me:
1. Complete adapter module
2. How translation works
3. Deprecation approach
```

### Prompt M.3.2 - Implement Response Translation
```
Let's implement response format translation.

First, understand:
1. Old pool response formats
2. New pool response formats
3. Edge cases to handle

Implement translation functions:
1. translate_response/2 main function
2. Handle success responses
3. Handle error responses
4. Preserve backward compatibility
5. Add migration hints in logs

Show me:
1. All translation functions
2. Format conversion examples
3. How errors are mapped
```

### Prompt M.3.3 - Test Compatibility
```
Let's test the compatibility layer.

Create test/dspex/python_bridge/pool_adapter_test.exs:
1. Test old API calls work
2. Test response translation
3. Test error compatibility
4. Test deprecation warnings
5. Compare behaviors

Include integration tests:
1. Real operations through adapter
2. Performance overhead measurement
3. Edge case handling

Run tests and show results.
```

## Session M.4: Parallel Run Implementation

### Prompt M.4.1 - Dual Pool Operation
```
Let's implement parallel pool operation.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md parallel run section
2. Current supervisor structure
3. Resource considerations

Implement dual pool support:
1. Update supervisor to start both pools
2. Configure pool sizes for parallel run
3. Add pool selection logic
4. Implement comparison mode
5. Add metrics for both pools

Show me:
1. Supervisor updates
2. Configuration approach
3. Selection logic
```

### Prompt M.4.2 - Shadow Mode
```
Let's implement shadow mode operation.

First, understand:
1. Shadow mode requirements
2. Result comparison needs
3. Performance impact limits

Implement shadow mode:
1. Route traffic to both pools
2. Use V1 result as primary
3. Compare V2 result async
4. Log differences
5. Emit comparison metrics

Show me:
1. Shadow mode implementation
2. How comparisons work
3. Performance safeguards
```

### Prompt M.4.3 - Comparison Framework
```
Let's create result comparison framework.

Create lib/dspex/python_bridge/migration/result_comparator.ex:
1. Compare operation results
2. Ignore timing differences
3. Detect semantic differences
4. Categorize differences
5. Generate comparison reports

Include:
1. Configurable comparison rules
2. Difference aggregation
3. Alerting for anomalies

Show me implementation and tests.
```

## Session M.5: Monitoring & Validation

### Prompt M.5.1 - Migration Metrics
```
Let's add migration-specific metrics.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md monitoring section
2. Existing telemetry setup
3. Critical metrics needed

Add migration metrics:
1. Pool selection distribution
2. Operation success rates by pool
3. Performance comparison
4. Error rate differences
5. Resource usage comparison

Show me:
1. New telemetry events
2. Metric definitions
3. Dashboard updates
```

### Prompt M.5.2 - Create Validation Suite
```
Let's create migration validation tests.

First, check:
1. Critical business operations
2. Performance requirements
3. Correctness criteria

Create test/dspex/python_bridge/migration/validation_test.exs:
1. Functional equivalence tests
2. Performance benchmarks
3. Error handling validation
4. Load test comparisons
5. Edge case verification

Show me:
1. Complete validation suite
2. How to run comparisons
3. Success criteria
```

### Prompt M.5.3 - Health Checks
```
Let's implement migration health checks.

Create lib/dspex/python_bridge/migration/health_checker.ex:
1. Monitor both pool health
2. Compare error rates
3. Check performance metrics
4. Validate resource usage
5. Generate health reports

Include:
1. Automated alerts
2. Rollback triggers
3. Daily reports

Show me implementation and example output.
```

## Session M.6: Switchover Process

### Prompt M.6.1 - Switchover Preparation
```
Let's prepare for switchover.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md switchover section
2. Current validation results
3. Rollback requirements

Create switchover checklist:
1. All validation tests passing?
2. Performance metrics acceptable?
3. No increase in errors?
4. Resource usage stable?
5. Rollback plan tested?

Document:
1. Go/no-go criteria
2. Switchover steps
3. Communication plan
4. Monitoring during switch

Show me checklist and procedures.
```

### Prompt M.6.2 - Implement Switchover
```
Let's implement the switchover mechanism.

First, understand:
1. Zero-downtime requirements
2. Gradual vs instant switch
3. Safety mechanisms

Implement switchover:
1. Gradual percentage increase
2. Circuit breaker integration
3. Automatic rollback triggers
4. Real-time monitoring
5. State persistence

Show me:
1. Switchover implementation
2. Safety features
3. Monitoring integration
```

### Prompt M.6.3 - Rollback Capability
```
Let's ensure rollback works properly.

Create rollback mechanisms:
1. Instant rollback function
2. State preservation
3. In-flight request handling
4. Metric snapshot
5. Automated triggers

Test rollback:
1. Mid-switchover rollback
2. Full rollback after switch
3. Performance during rollback
4. Data integrity

Show me implementation and test results.
```

## Session M.7: Production Deployment

### Prompt M.7.1 - Deployment Scripts
```
Let's create deployment automation.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_7_MIGRATION_DEPLOYMENT.md deployment section
2. Current deployment process
3. Environment configurations

Create deployment scripts:
1. scripts/deploy_v2_pool.sh
2. Pre-deployment checks
3. Configuration validation
4. Health check integration
5. Rollback automation

Show me:
1. Complete scripts
2. Safety checks included
3. How to run deployment
```

### Prompt M.7.2 - Environment Configuration
```
Let's set up environment configs.

First, check:
1. Current environments: ls config/
2. Environment-specific needs
3. Secret management

Create configurations for:
1. Development settings
2. Staging configuration
3. Production parameters
4. Feature flag defaults
5. Monitoring thresholds

Show me:
1. Configuration files
2. Environment differences
3. Secret handling
```

### Prompt M.7.3 - Runbook Creation
```
Let's create operational runbooks.

Create runbooks for:
1. Normal switchover procedure
2. Emergency rollback
3. Performance degradation
4. Error spike response
5. Capacity adjustment

Each runbook should have:
1. Symptom identification
2. Step-by-step procedures
3. Decision points
4. Escalation paths
5. Post-incident steps

Show me example runbook.
```

## Session M.8: Cleanup Phase

### Prompt M.8.1 - Identify Cleanup Tasks
```
Let's plan the cleanup phase.

First, analyze:
1. Old pool dependencies
2. Deprecated code paths
3. Unused configurations
4. Test dependencies
5. Documentation updates

Create cleanup plan:
1. Code removal list
2. Config cleanup items
3. Test updates needed
4. Documentation changes
5. Timeline for removal

Show me:
1. Complete cleanup inventory
2. Dependencies to check
3. Removal order
```

### Prompt M.8.2 - Code Cleanup
```
Let's remove deprecated code.

First, verify:
1. V2 pool fully adopted
2. No remaining V1 references
3. All tests updated

Remove:
1. Old pool implementation
2. Compatibility adapters
3. Feature flag checks
4. Parallel run code
5. Migration utilities

Show me:
1. Files to remove
2. Code sections to delete
3. Git commands to run
```

### Prompt M.8.3 - Final Validation
```
Let's validate the cleanup.

Run final checks:
1. All tests still passing?
2. No broken references?
3. Documentation accurate?
4. Performance maintained?
5. Clean architecture?

Create final report:
1. Migration summary
2. Performance improvements
3. Lessons learned
4. Future recommendations

Show me validation results and report.
```

## Session M.9: Post-Migration

### Prompt M.9.1 - Performance Analysis
```
Let's analyze post-migration performance.

First, collect:
1. Pre-migration baselines
2. Current performance metrics
3. Resource usage data
4. Error rates
5. User feedback

Analyze:
1. Latency improvements
2. Throughput changes
3. Resource efficiency
4. Stability metrics
5. Cost impact

Show me:
1. Performance comparison
2. Improvement areas
3. Optimization opportunities
```

### Prompt M.9.2 - Lessons Learned
```
Let's document lessons learned.

Create retrospective covering:
1. What went well
2. Challenges faced
3. Technical decisions
4. Process improvements
5. Tool effectiveness

Include:
1. Timeline analysis
2. Risk assessment accuracy
3. Testing effectiveness
4. Team feedback
5. Recommendations

Show me retrospective document.
```

## Session M.10: Long-term Maintenance

### Prompt M.10.1 - Maintenance Plan
```
Let's create a maintenance plan.

First, identify:
1. Regular maintenance tasks
2. Monitoring requirements
3. Update procedures
4. Performance tuning
5. Capacity planning

Create maintenance guide:
1. Daily operations
2. Weekly checks
3. Monthly reviews
4. Quarterly planning
5. Annual assessments

Show me:
1. Maintenance schedule
2. Task descriptions
3. Automation opportunities
```

### Prompt M.10.2 - Future Roadmap
```
Let's plan future enhancements.

Based on:
1. Performance data
2. User feedback
3. Technical debt
4. New requirements
5. Technology trends

Create roadmap for:
1. Near-term optimizations
2. Medium-term features
3. Long-term architecture
4. Research areas
5. Team development

Show me roadmap with priorities and timelines.
```
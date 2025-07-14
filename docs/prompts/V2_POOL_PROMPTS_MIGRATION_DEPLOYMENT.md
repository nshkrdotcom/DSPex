# V2 Pool Implementation Prompts - Migration and Deployment

## Pre-Migration Preparation

### Prompt M.1.1 - Feature Flag Setup
```
We're preparing for V2 Pool migration and deployment.
Current status: All development phases complete
Today's goal: Set up feature flag system

Create lib/dspex/feature_flags.ex from Design Doc 7. Implement:
1. GenServer for flag management
2. Default flags configuration
3. Gradual rollout percentage logic
4. Flag persistence mechanism

Test the feature flag system works correctly.
```

### Prompt M.1.2 - Compatibility Layer
```
Create lib/dspex/python_bridge/compatibility_adapter.ex from Design Doc 7:
1. Routes between V1 and V2 based on flags
2. Maintains API compatibility
3. Adds telemetry for routing decisions
4. Supports gradual rollout

Test both V1 and V2 paths work through the adapter.
```

### Prompt M.1.3 - Database Migrations
```
Create the migration file for V2 pool tables:
1. Pool configurations table
2. Pool metrics history table
3. Migration status tracking
4. Indexes for performance

Run the migration and verify tables are created.
```

## Migration Implementation

### Prompt M.2.1 - Migration Script
```
Create lib/dspex/migration/pool_migration.ex from Design Doc 7:
1. Environment validation
2. State backup functionality
3. V2 component deployment
4. Health verification
5. Gradual rollout enablement

Test the migration script in development.
```

### Prompt M.2.2 - Migration Monitor
```
Create lib/dspex/migration/migration_monitor.ex to track health during migration:
1. Health check scheduling
2. Metric comparison (V1 vs V2)
3. Alert threshold checking
4. Automatic rollback triggers

Test monitoring detects issues correctly.
```

### Prompt M.2.3 - Rollback Manager
```
Create lib/dspex/migration/rollback_manager.ex:
1. Rollback condition detection
2. Graceful rollback execution
3. Connection draining
4. Component cleanup
5. Notification system

Test rollback works cleanly.
```

## Gradual Rollout

### Prompt M.3.1 - Traffic Controller
```
Create lib/dspex/migration/traffic_controller.ex for staged rollout:
1. Rollout stage management
2. Automatic stage advancement
3. Health-based progression
4. Stage timing control

Test traffic routing at different percentages.
```

### Prompt M.3.2 - Rollout Validation
```
Create validation tests for each rollout stage:
1. 5% traffic validation
2. 25% traffic validation
3. 50% traffic validation
4. 100% traffic validation

Ensure metrics remain healthy at each stage.
```

## Production Validation

### Prompt M.4.1 - Validation Suite
```
Create lib/dspex/migration/validation_suite.ex:
1. Functional equivalence tests
2. Performance comparison tests
3. Error handling verification
4. Load test execution

Run full validation suite.
```

### Prompt M.4.2 - Production Checklist
```
Create and execute production validation checklist:
1. Verify all tests pass
2. Check performance meets SLAs
3. Confirm monitoring works
4. Validate rollback procedures
5. Review documentation

Document any issues found.
```

## Deployment Execution

### Prompt M.5.1 - Pre-deployment
```
Execute pre-deployment steps:
1. Run final test suite
2. Create deployment package
3. Backup current state
4. Notify stakeholders
5. Prepare rollback plan

Confirm ready for deployment.
```

### Prompt M.5.2 - Deploy Phase 1
```
Deploy with 5% traffic:
1. Enable feature flags
2. Start V2 components
3. Route 5% traffic to V2
4. Monitor metrics closely
5. Validate health

Document initial results.
```

### Prompt M.5.3 - Monitor and Advance
```
Monitor and advance through stages:
1. Check error rates
2. Compare latencies
3. Verify throughput
4. Monitor resource usage
5. Advance to next stage when stable

Continue until 100% traffic.
```

## Post-Deployment

### Prompt M.6.1 - V1 Decommission
```
Create lib/dspex/migration/decommission.ex:
1. Verify V2 fully operational
2. Archive V1 data
3. Remove V1 code
4. Clean up resources

Execute decommissioning safely.
```

### Prompt M.6.2 - Final Report
```
Create comprehensive migration report:
1. Migration timeline
2. Issues encountered
3. Performance improvements
4. Lessons learned
5. Future recommendations

Document complete migration journey.
```

## Emergency Procedures

### Prompt M.7.1 - Emergency Rollback
```
Test emergency rollback procedure:
1. Simulate critical failure
2. Execute emergency rollback
3. Verify V1 takes all traffic
4. Check data consistency
5. Document recovery time

Ensure rollback is reliable.
```

### Prompt M.7.2 - Incident Response
```
Create incident response procedures:
1. Alert escalation paths
2. Diagnostic commands
3. Mitigation steps
4. Communication templates
5. Post-mortem process

Test with simulated incidents.
```

## Operational Handoff

### Prompt M.8.1 - Operations Guide
```
Create comprehensive operations guide:
1. System architecture overview
2. Monitoring and alerts
3. Common procedures
4. Troubleshooting guide
5. Performance tuning

Review with operations team.
```

### Prompt M.8.2 - Training Materials
```
Create training materials:
1. V2 pool concepts
2. Operational procedures
3. Monitoring dashboards
4. Incident response
5. Hands-on exercises

Conduct training sessions.
```

## Final Validation

### Prompt M.9.1 - Success Criteria
```
Validate all success criteria met:
1. Zero customer impact ✓
2. Performance improved ✓
3. Error handling enhanced ✓
4. Monitoring comprehensive ✓
5. Team trained ✓

Create success report.
```

### Prompt M.9.2 - Project Closure
```
Complete project closure:
1. Archive project artifacts
2. Document lessons learned
3. Update system documentation
4. Close tracking tickets
5. Celebrate success!

The V2 Pool implementation is complete.
```
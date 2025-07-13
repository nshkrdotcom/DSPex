# Sleep Elimination Implementation Prompts

**Generated**: 2025-07-13  
**Context**: Step-by-step prompts for systematic elimination of Process.sleep() usage  
**Target**: Transform 31 sleep instances into event-driven patterns following UNIFIED_TESTING_GUIDE.md  

---

## Required Reading (MUST READ FIRST)

Before implementing any fixes, you MUST thoroughly read and understand these files:

### 1. Testing Standards Reference
```bash
# Read the comprehensive testing guide that defines all patterns
cat /home/home/p/g/n/ashframework/ash_dspex/code-standards/UNIFIED_TESTING_GUIDE.md
```

### 2. Implementation Plan Overview
```bash
# Read the complete fix plan with detailed analysis
cat /home/home/p/g/n/ashframework/ash_dspex/ash_dspex/TESTING_INFRASTRUCTURE_FIX_PLAN.md
```

### 3. Current Sleep Usage Analysis
```bash
# See all current Process.sleep instances that need fixing
rg "Process\.sleep" --type elixir -n
```

### 4. Test Failure Context
```bash
# Understand the broader test failure context
cat /home/home/p/g/n/ashframework/ash_dspex/ash_dspex/STAGE1_02_PYTHON_BRIDGE_FIXES_ROUND2.md
```

**⚠️ CRITICAL**: Do not proceed with any implementation until you have read and understood all four references above. The patterns in UNIFIED_TESTING_GUIDE.md are mandatory and must be followed exactly.

---

## Implementation Prompts

### PROMPT 1: Production Code Sleep Elimination (Week 1, Day 1-2)

**Task**: Fix the 3 critical Process.sleep() instances in production code that are causing reliability issues.

**Files to Fix**:
- `lib/ash_dspex/python_bridge/bridge.ex:393`
- `lib/ash_dspex/python_bridge/supervisor.ex:299` 
- `lib/ash_dspex/python_bridge/supervisor.ex:330`

**Implementation Requirements**:
1. Replace all Process.sleep() with event-driven coordination
2. Implement graceful shutdown protocol for bridge termination
3. Add process monitoring for supervisor operations
4. Ensure no timing assumptions remain in production code
5. Follow UNIFIED_TESTING_GUIDE.md patterns for process synchronization

**Success Criteria**:
- Zero Process.sleep() in lib/ directory
- All production operations use OTP guarantees
- Bridge termination uses acknowledgment-based shutdown
- Supervisor operations use process monitoring

**Test Command**: `rg "Process\.sleep" lib/ --type elixir` should return no results.

---

### PROMPT 2: Test Helper Infrastructure Setup (Week 1, Day 3-5)

**Task**: Create the foundational test helper modules that will replace all sleep-based testing patterns.

**Files to Create**:
- `test/support/supervision_test_helpers.ex`
- `test/support/bridge_test_helpers.ex`
- `test/support/monitor_test_helpers.ex`
- `test/support/unified_test_foundation.ex`

**Implementation Requirements**:
1. Implement all helper functions from TESTING_INFRASTRUCTURE_FIX_PLAN.md
2. Follow UNIFIED_TESTING_GUIDE.md patterns exactly
3. Use `:erlang.unique_integer([:positive])` for unique naming
4. Implement `wait_for/2` pattern for generic condition waiting
5. Add proper resource cleanup with `on_exit` callbacks
6. Support all isolation modes: basic, registry, supervision_testing

**Key Functions to Implement**:
- `wait_for_bridge_ready/3`
- `wait_for_process_restart/4`
- `bridge_call_with_retry/5`
- `wait_for_health_status/3`
- `wait_for_failure_count/3`

**Success Criteria**:
- All helper modules compile without warnings
- All functions follow event-driven patterns
- No Process.sleep() in any helper code
- Proper error handling and timeouts implemented

---

### PROMPT 3: Integration Test Migration (Week 2, Day 1-2)

**Task**: Replace all 10 Process.sleep() instances in integration tests with event-driven patterns.

**File to Fix**: `test/ash_dspex/python_bridge/integration_test.exs`

**Sleep Instances to Replace**:
- Line 21: `Process.sleep(500)` - Bridge startup wait
- Line 95: `Process.sleep(200)` - Response wait
- Line 109: `Process.sleep(1000)` - "Give Python bridge time to start"
- Line 138: `Process.sleep(500)` - Command execution wait
- Line 176: `Process.sleep(500)` - Bridge readiness wait
- Line 198: `Process.sleep(1000)` - "Give Python bridge time to start"
- Line 251: `Process.sleep(1000)` - Bridge startup wait
- Line 294: `Process.sleep(500)` - Operation completion wait
- Line 316: `Process.sleep(1000)` - Bridge startup wait
- Line 342: `Process.sleep(1000)` - Bridge startup wait

**Implementation Requirements**:
1. Use `AshDSPex.UnifiedTestFoundation` with `:supervision_testing` mode
2. Replace all sleeps with `wait_for_bridge_ready/3` calls
3. Use `bridge_call_with_retry/5` for all bridge communications
4. Implement proper test isolation with unique process names
5. Add comprehensive error handling and meaningful assertions

**Success Criteria**:
- All 14 integration tests pass reliably
- No Process.sleep() usage in file
- Tests use proper supervision isolation
- Bridge readiness verification before all operations

---

### PROMPT 4: Monitor Test Migration (Week 2, Day 3)

**Task**: Replace all 8 Process.sleep() instances in monitor tests with event-driven health coordination.

**File to Fix**: `test/ash_dspex/python_bridge/monitor_test.exs`

**Sleep Instances to Replace**:
- Line 93: `Process.sleep(100)` - Health check wait
- Line 113: `Process.sleep(100)` - Status verification wait
- Line 117: `Process.sleep(50)` - Quick status check
- Line 148: `Process.sleep(200)` - Multiple health checks
- Line 173: `Process.sleep(200)` - Failure accumulation wait
- Line 193: `Process.sleep(100)` - Bridge response wait
- Line 216: `Process.sleep(50)` - Health check loop
- Line 219: `Process.sleep(100)` - Final status check

**Implementation Requirements**:
1. Use `wait_for_health_status/3` for health state verification
2. Use `trigger_health_check_and_wait/3` for controlled health checks
3. Use `wait_for_failure_count/3` for failure tracking tests
4. Implement deterministic health check triggering
5. Follow event-driven coordination patterns from UNIFIED_TESTING_GUIDE.md

**Success Criteria**:
- All monitor tests pass reliably
- Health checks are deterministic, not timing-based
- Failure threshold tests work correctly
- Success rate calculations are accurate

---

### PROMPT 5: Supervisor Test Migration (Week 2, Day 4)

**Task**: Replace all 7 Process.sleep() instances in supervisor tests with process lifecycle coordination.

**File to Fix**: `test/ash_dspex/python_bridge/supervisor_test.exs`

**Sleep Instances to Replace**:
- Line 129: `Process.sleep(100)` - Child restart wait
- Line 172: `Process.sleep(100)` - Supervisor stop wait
- Line 210: `Process.sleep(100)` - Bridge initialization wait
- Line 256: `Process.sleep(100)` - Restart verification wait
- Line 299: `Process.sleep(100)` - Bridge restart wait
- Line 332: `Process.sleep(100)` - Stop sequence wait
- Line 351: `Process.sleep(200)` - Configuration reload wait

**Implementation Requirements**:
1. Use `wait_for_process_restart/4` for restart testing
2. Use process monitoring for termination verification
3. Use `wait_for_bridge_ready/3` for initialization testing
4. Implement proper supervision strategy testing
5. Follow one-for-one and rest-for-one patterns from UNIFIED_TESTING_GUIDE.md

**Success Criteria**:
- All supervisor tests pass reliably
- Process restart detection is event-driven
- Supervision strategy behavior is correctly verified
- Configuration changes are properly synchronized

---

### PROMPT 6: Bridge and Remaining Test Migration (Week 2, Day 5)

**Task**: Fix the remaining Process.sleep() instances in bridge tests and gemini integration test.

**Files to Fix**:
- `test/ash_dspex/python_bridge/bridge_test.exs` (2 instances)
- `test/ash_dspex/gemini_integration_test.exs` (1 instance)

**Sleep Instances**:
- `bridge_test.exs:80`: `Process.sleep(100)` - Initialization wait
- `bridge_test.exs:185`: `Process.sleep(100)` - "Let it initialize"
- `gemini_integration_test.exs:16`: `Process.sleep(1000)` - Integration test wait

**Implementation Requirements**:
1. Use bridge readiness verification for initialization waits
2. Use proper GenServer synchronization for bridge operations
3. Implement event-driven coordination for Gemini integration
4. Follow public API testing patterns from UNIFIED_TESTING_GUIDE.md
5. Add proper error handling and meaningful test assertions

**Success Criteria**:
- All remaining tests pass reliably
- Zero Process.sleep() usage across entire test suite
- Bridge initialization is properly synchronized
- Gemini integration uses event-driven coordination

---

### PROMPT 7: Advanced Testing Patterns Implementation (Week 3, Day 1-3)

**Task**: Implement chaos testing and performance benchmarking to validate the robustness of the event-driven approach.

**Files to Create**:
- `test/ash_dspex/python_bridge/chaos_test.exs`
- `test/ash_dspex/python_bridge/performance_test.exs`

**Implementation Requirements**:
1. Create chaos testing that randomly kills processes and verifies recovery
2. Implement performance benchmarks for restart times and throughput
3. Add load testing to verify system behavior under stress
4. Use advanced patterns from UNIFIED_TESTING_GUIDE.md
5. Implement property-based testing where appropriate

**Chaos Testing Features**:
- Random process termination with recovery verification
- Network failure simulation
- Resource exhaustion testing
- Multi-process coordination under failure

**Performance Testing Features**:
- Bridge restart time benchmarks (target: <2s average, <5s P95)
- Throughput testing under various loads
- Memory usage monitoring during extended operation
- Supervisor recovery time measurement

**Success Criteria**:
- System survives extended chaos testing
- Performance benchmarks meet targets
- All tests pass under high load
- No timing-dependent failures

---

### PROMPT 8: CI Integration and Validation (Week 3, Day 4-5)

**Task**: Set up automated validation to prevent future Process.sleep() introduction and ensure test reliability.

**Files to Create/Modify**:
- `.github/workflows/test-quality.yml` (or equivalent CI config)
- `scripts/test-quality-check.sh`
- Update existing CI to include sleep detection

**Implementation Requirements**:
1. Add automated Process.sleep() detection that fails CI
2. Add hardcoded process name detection
3. Implement multi-seed test execution to catch race conditions
4. Add performance regression testing
5. Create code review checklist automation

**CI Checks to Implement**:
```bash
# Sleep detection
rg "Process\.sleep\(" --type elixir && exit 1

# Hardcoded process names detection  
rg "name: :[a-z_]+\b" --type elixir | grep -v "unique_integer" && exit 1

# Multi-seed testing
for i in {1..5}; do mix test --seed $RANDOM || exit 1; done

# Performance benchmarks
mix test test/ash_dspex/python_bridge/performance_test.exs
```

**Success Criteria**:
- CI prevents any Process.sleep() commits
- Multi-seed testing catches race conditions
- Performance regressions are detected
- Code quality gates are enforced

---

## Final Validation Prompt

### PROMPT 9: Comprehensive System Validation

**Task**: Perform final validation that all sleep elimination objectives have been achieved.

**Validation Commands**:
```bash
# 1. Verify zero Process.sleep() usage
echo "=== CHECKING FOR PROCESS.SLEEP ==="
rg "Process\.sleep" --type elixir && echo "❌ SLEEP FOUND" || echo "✅ NO SLEEP DETECTED"

# 2. Run full test suite
echo "=== RUNNING FULL TEST SUITE ==="
mix test --trace

# 3. Run with multiple seeds to check for race conditions
echo "=== MULTI-SEED TESTING ==="
for i in {1..5}; do
  echo "Seed run $i"
  mix test --seed $RANDOM || (echo "❌ SEED $i FAILED" && exit 1)
done

# 4. Check test pass rate
echo "=== FINAL TEST RESULTS ==="
mix test --formatter ExUnit.CLIFormatter
```

**Final Success Criteria**:
- **✅ Zero Process.sleep() instances** across entire codebase
- **✅ 100% test pass rate** (up from 87%)
- **✅ Tests pass reliably with different seeds**
- **✅ All integration tests work with real Python bridge**
- **✅ Monitor tests accurately verify health behavior**
- **✅ Supervisor tests properly validate OTP behavior**
- **✅ Performance benchmarks meet targets**
- **✅ CI pipeline enforces quality standards**

---

## Implementation Guidelines

### General Principles
1. **Read UNIFIED_TESTING_GUIDE.md first** - All patterns must follow this standard
2. **Never guess timing** - Always wait for explicit events or conditions
3. **Use OTP guarantees** - Trust the platform, don't work around it
4. **Unique process names** - Always use `:erlang.unique_integer([:positive])`
5. **Proper cleanup** - Use `on_exit` callbacks for resource management
6. **Event-driven coordination** - Replace every sleep with explicit synchronization

### Error Handling Patterns
- Always specify reasonable timeouts (typically 2-5 seconds)
- Provide meaningful error messages that aid debugging
- Use pattern matching to verify expected states
- Implement retry logic only where appropriate

### Test Organization
- Group tests by isolation requirements
- Use appropriate async settings based on test type
- Implement proper setup and teardown
- Follow the test categorization from UNIFIED_TESTING_GUIDE.md

This systematic approach will transform the codebase from brittle, sleep-driven testing to robust, event-driven coordination that demonstrates proper Elixir OTP patterns and enterprise-grade reliability.
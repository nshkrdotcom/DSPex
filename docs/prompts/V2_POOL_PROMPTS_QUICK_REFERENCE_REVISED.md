# V2 Pool Implementation - Quick Reference Prompts (REVISED)

## 🚀 Quick Start Prompts

### Get Current Status
```
Show me the current V2 pool implementation status.

First, read these files:
1. Read CLAUDE.md for progress tracking
2. Check current git status: git status
3. Check recent commits: git log --oneline -5

Then show me:
1. Current implementation phase
2. Last completed task
3. Any uncommitted changes
4. Which phase we're in
```

### Resume Work
```
I need to resume V2 pool work.

First, gather context:
1. Read the last session notes from CLAUDE.md
2. Check uncommitted changes: git diff
3. Read current phase design doc section
4. Check failing tests: mix test 2>&1 | grep -A5 "test.*failure"

Show me:
1. Where we left off
2. Current work state
3. Next immediate task
4. Any blockers to resolve
```

## 🔧 Common Implementation Tasks

### Implement a Function
```
Implement [function_name] from Design Doc [X].

First, prepare by reading:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_[X]_*.md for the specification
2. Check existing patterns: grep -r "similar_function" lib/
3. Review related tests: ls test/**/[related]_test.exs

Then implement:
1. Function signature and docs
2. Core logic
3. Error handling
4. Logging/telemetry
5. Tests

Show me complete implementation.
```

### Fix a Test
```
Fix the failing test at [file:line].

First, understand the failure:
1. Run: mix test [file]:[line] --trace
2. Read the test implementation
3. Read the code being tested
4. Check recent changes: git log -p -- [file]

Fix approach:
1. Identify root cause
2. Determine if test or code needs fixing
3. Implement fix
4. Verify fix works

Show me the fix and verification.
```

### Add Error Handling
```
Add error handling to [module/function].

First, analyze error cases:
1. Read the function implementation
2. Check docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md
3. Find similar error handling: grep -r "PoolErrorHandler" lib/

Implement:
1. Identify all error cases
2. Use PoolErrorHandler.wrap_pool_error
3. Add appropriate logging
4. Include telemetry events
5. Test error scenarios

Show me updated code with error handling.
```

## 🧪 Testing Commands

### Run Tests by Layer
```
# First check which layer based on current phase or feature

# Layer 1 (Mock) - Unit tests
mix test --only layer_1

# Layer 2 (Bridge Mock) - Integration with mock bridge
TEST_MODE=bridge_mock mix test --only layer_2

# Layer 3 (Full Integration) - Real Python processes
TEST_MODE=full_integration mix test --only layer_3

# Specific module
mix test test/path/to/module_test.exs

# With coverage
mix coveralls.html
```

### Run Specific Test Types
```
# First determine test type needed

# Unit tests only
mix test test/unit/

# Integration tests
mix test test/integration/

# Performance tests
mix test --only performance

# Chaos tests
mix test --only chaos

# Single test
mix test test/file.exs:LINE
```

## 🐛 Debugging Prompts

### Debug Pool Issues
```
Debug pool issue: [describe problem].

First, gather information:
1. Check pool processes: :observer.start()
2. Read recent logs: grep -n "ERROR\|WARN" log/
3. Check worker states in observer
4. Review telemetry: check ETS tables

Debug approach:
1. Add IO.inspect at key points
2. Use :dbg for function tracing
3. Check telemetry events
4. Create minimal reproduction

Show me findings and fix approach.
```

### Trace Execution
```
Trace execution of [operation].

First, identify trace points:
1. Find the entry function
2. Map the call flow
3. Identify state changes

Add tracing:
1. IO.inspect(binding(), label: "POINT_NAME")
2. Use :dbg.tracer()
3. Add telemetry events
4. Create focused test

Show me trace results and analysis.
```

## 📊 Performance Prompts

### Check Performance
```
Check performance of [component].

First, measure current state:
1. Find or create benchmark: ls bench/
2. Check existing metrics: read telemetry data
3. Review design targets

Measure:
1. Run benchmarks with Benchee
2. Check current metrics
3. Compare with baseline
4. Profile with :fprof if needed

Show me performance analysis.
```

### Optimize Component
```
Optimize [component] performance.

First, profile the component:
1. Measure current performance
2. Run :fprof or :eprof
3. Check algorithmic complexity
4. Review data structures

Optimize:
1. Identify bottleneck
2. Implement optimization
3. Measure improvement
4. Ensure no regression

Show me before/after metrics.
```

## 🔍 Code Search Prompts

### Find Pattern
```
Find all instances of [pattern].

Search commands:
# Text search
grep -r "pattern" lib/ test/

# Function definitions
grep -r "def pattern" lib/

# Module references
grep -r "alias.*Pattern\|Pattern\." lib/

# Test examples
grep -r "pattern" test/

Show me all occurrences with context.
```

### Find Related Code
```
Find code related to [feature].

First, identify search terms:
1. Module names
2. Function names
3. Key variables
4. Error messages

Search:
1. grep -r "feature\|Feature" lib/
2. Check similar modules
3. Look in tests
4. Review docs

Show me related code organized by purpose.
```

## 📝 Documentation Prompts

### Update Documentation
```
Update documentation for [component].

First, check what needs updating:
1. Read current @moduledoc in file
2. Check function @doc strings
3. Review CLAUDE.md mentions
4. Check README if applicable

Update:
1. Module documentation
2. Function documentation
3. Add examples
4. Update CLAUDE.md
5. Update guides if needed

Show me documentation updates.
```

### Create Runbook
```
Create runbook for [scenario].

First, understand the scenario:
1. When does it occur?
2. What are symptoms?
3. What's the impact?

Document:
1. Scenario description
2. Detection methods
3. Step-by-step resolution
4. Verification steps
5. Prevention measures

Show me complete runbook.
```

## 🚢 Deployment Prompts

### Prepare Release
```
Prepare for release of current work.

First, check readiness:
1. Run full test suite: mix test
2. Check coverage: mix coveralls
3. Run formatter: mix format
4. Check credo: mix credo

Prepare:
1. Update version if needed
2. Create release notes
3. Document breaking changes
4. Update migration guide

Show me release checklist status.
```

### Validate Deployment
```
Validate deployment readiness.

Check:
□ All tests passing?
□ Performance targets met?
□ Documentation complete?
□ Rollback plan ready?
□ Monitoring configured?
□ Feature flags set?

Show me validation results.
```

## 💡 Architecture Decisions

### Evaluate Options
```
Evaluate options for [decision].

First, understand context:
1. Read relevant design doc section
2. Check existing patterns
3. Review constraints

Evaluate:
1. List all options
2. Compare pros/cons
3. Consider our design principles
4. Check performance impact
5. Assess maintenance burden

Show me recommendation with rationale.
```

### Review Design
```
Review design of [component].

First, read implementation:
1. Read the module/function
2. Check against design doc
3. Review test coverage

Assess:
□ Follows our patterns?
□ Error handling complete?
□ Edge cases covered?
□ Testable design?
□ Performance acceptable?

Show me review findings.
```

## 🛟 Emergency Prompts

### System Down
```
Pool system is down!

First, diagnose:
1. Check supervisor: Process.whereis(DSPex.PythonBridge.Supervisor)
2. Look for crashes: ls log/crash.log*
3. Check system resources: File.read!("/proc/meminfo")
4. Review recent changes: git log --oneline -10

Recover:
1. Restart supervisor if needed
2. Check pool configuration
3. Verify Python processes
4. Use fallback adapter

Show me diagnosis and recovery steps.
```

### Performance Crisis
```
Performance is severely degraded!

First, measure:
1. Check current metrics vs normal
2. Look at pool utilization
3. Check error rates
4. Monitor resource usage

Mitigate:
1. Identify bottleneck
2. Scale pool if needed
3. Enable circuit breakers
4. Reduce timeout values
5. Switch to degraded mode

Show me immediate actions to take.
```

## 📋 Checklists

### Before Committing
```
Pre-commit checklist:

First run these checks:
□ mix test - All tests pass?
□ mix format --check-formatted - Code formatted?
□ mix credo - No issues?
□ grep -r "IO.inspect\|TODO" lib/ - No debug code?
□ git diff - Changes look correct?

Show me any issues found.
```

### End of Day
```
End of day checklist:

Tasks to complete:
□ Commit current work
□ Update CLAUDE.md with progress
□ Push to branch: git push
□ Note tomorrow's first task
□ Clean up any temp files

Show me what's left to do.
```

## 🎯 Phase-Specific

### Current Phase Check
```
What phase am I in?

First, check indicators:
1. Read CLAUDE.md header section
2. Check recent commits: git log --grep="Phase"
3. Look at current branch name
4. Check which design doc we're using

Show me:
1. Current phase
2. Phase progress
3. Next milestone
```

### Phase Transition
```
Ready to move to next phase?

Validation checklist:
□ All current phase tests pass?
□ Documentation complete?
□ No critical issues?
□ Performance acceptable?
□ Design doc tasks done?

Show me validation results and next phase prep.
```

---

**Remember**: 
- Always read relevant files first before making changes
- Check existing patterns before implementing new code  
- Run tests after changes
- Update documentation as you go
- For detailed implementation, refer to the phase-specific prompt files
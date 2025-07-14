# V2 Pool Implementation - Quick Reference Prompts

## 🚀 Quick Start Prompts

### Get Current Status
```
Show me the current V2 pool implementation status by:
1. Checking CLAUDE.md
2. Running git status
3. Listing recent test failures
4. Showing which phase we're in
```

### Resume Work
```
I need to resume V2 pool work. Please:
1. Read the last session notes from CLAUDE.md
2. Show me any uncommitted changes
3. Run tests for the component we were working on
4. Tell me the next immediate task
```

## 🔧 Common Implementation Tasks

### Implement a Function
```
Implement [function_name] from Design Doc [X]:
1. Show the specification from the doc
2. Check for existing similar patterns
3. Write the implementation
4. Add appropriate error handling
5. Include logging and telemetry
```

### Fix a Test
```
Fix the failing test at [file:line]:
1. Show me the exact failure
2. Find the code being tested
3. Identify why it's failing
4. Implement the fix
5. Verify the test passes
```

### Add Error Handling
```
Add error handling to [module/function]:
1. Identify all error cases
2. Use PoolErrorHandler for wrapping
3. Add appropriate logging
4. Include telemetry events
5. Test error scenarios
```

## 🧪 Testing Commands

### Run Tests by Layer
```
# Layer 1 (Mock)
mix test --only layer_1

# Layer 2 (Bridge Mock)  
TEST_MODE=bridge_mock mix test --only layer_2

# Layer 3 (Full Integration)
TEST_MODE=full_integration mix test --only layer_3

# Specific module
mix test test/path/to/module_test.exs
```

### Run Specific Test Types
```
# Unit tests only
mix test test/unit/

# Integration tests
mix test test/integration/

# Performance tests
mix test --only performance

# Chaos tests
mix test --only chaos
```

## 🐛 Debugging Prompts

### Debug Pool Issues
```
Debug pool issue: [describe problem]
1. Check pool process with :observer.start()
2. Look at worker states
3. Check ETS tables for metrics
4. Review recent telemetry events
5. Add targeted logging
```

### Trace Execution
```
Trace execution of [operation]:
1. Add IO.inspect with labels at key points
2. Use :dbg to trace function calls
3. Check telemetry events
4. Review logs with grep
5. Create minimal reproduction case
```

## 📊 Performance Prompts

### Check Performance
```
Check performance of [component]:
1. Run benchmarks with Benchee
2. Check current metrics
3. Compare with baseline
4. Look for bottlenecks
5. Profile with :fprof if needed
```

### Optimize Component
```
Optimize [component]:
1. Measure current performance
2. Identify bottleneck
3. Implement optimization
4. Measure improvement
5. Ensure no regression
```

## 🔍 Code Search Prompts

### Find Pattern
```
Find all instances of [pattern] in the codebase:
1. Use grep for text search
2. Use ast_grep for AST patterns
3. Check similar modules
4. Look in test files too
5. Document findings
```

### Find Related Code
```
Find code related to [feature]:
1. Search for module names
2. Look for function calls
3. Check test files
4. Review documentation
5. Trace through call stack
```

## 📝 Documentation Prompts

### Update Documentation
```
Update documentation for [component]:
1. Update module @moduledoc
2. Add/update function @doc
3. Include examples
4. Update CLAUDE.md
5. Add to relevant guides
```

### Create Runbook
```
Create runbook for [scenario]:
1. Describe the scenario
2. List detection methods
3. Document steps to resolve
4. Include verification steps
5. Add to operations guide
```

## 🚢 Deployment Prompts

### Prepare Release
```
Prepare for release:
1. Run full test suite
2. Check code coverage
3. Run linter and formatter
4. Update version
5. Create release notes
```

### Validate Deployment
```
Validate deployment readiness:
1. All tests passing?
2. Performance targets met?
3. Documentation complete?
4. Rollback plan ready?
5. Monitoring configured?
```

## 💡 Architecture Decisions

### Evaluate Options
```
Evaluate options for [decision]:
1. List all options
2. Compare pros/cons
3. Consider our design principles
4. Check performance impact
5. Make recommendation
```

### Review Design
```
Review design of [component]:
1. Does it follow our patterns?
2. Is error handling complete?
3. Are there edge cases?
4. Is it testable?
5. Any improvements needed?
```

## 🛟 Emergency Prompts

### System Down
```
Pool system is down:
1. Check if supervisor is running
2. Look for crash dumps
3. Check system resources
4. Review recent changes
5. Use fallback if available
```

### Performance Crisis
```
Performance is degraded:
1. Check current metrics
2. Compare with normal
3. Look for bottlenecks
4. Check pool size/config
5. Consider emergency scaling
```

## 📋 Checklists

### Before Committing
```
Pre-commit checklist:
1. All tests pass? ✓
2. Code formatted? ✓
3. Documentation updated? ✓
4. No debug code? ✓
5. Commit message clear? ✓
```

### End of Day
```
End of day checklist:
1. Commit current work ✓
2. Update CLAUDE.md ✓
3. Push to branch ✓
4. Note tomorrow's task ✓
5. Clean up debug code ✓
```

## 🎯 Phase-Specific

### Current Phase Check
```
What phase am I in?
1. Check CLAUDE.md header
2. Look at recent commits
3. See which design doc we're following
4. Check completed components
5. Identify next milestone
```

### Phase Transition
```
Ready to move to next phase?
1. All current phase tests pass?
2. Documentation complete?
3. No known issues?
4. Performance acceptable?
5. Create phase summary
```

---

**Remember**: These are quick prompts. For detailed implementation, refer to the phase-specific prompt files.
# V2 Pool Implementation Prompts - Phase 1: Immediate Fixes (REVISED)

## Session 1.1: NimblePool Return Value Fixes

### Prompt 1.1.1 - Initial Analysis
```
We're implementing Phase 1 of the V2 Pool design, specifically fixing NimblePool return values.

First, read these files to understand the context:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md sections "Fix 1" and "Fix 2"
2. Read docs/V2_POOL_PHASE1_ANALYSIS_AND_RECOMMENDATIONS.md section "Pool Worker Lifecycle Errors"
3. Read lib/dspex/python_bridge/pool_worker_v2.ex

Now analyze the current implementation:
1. Find all instances where we return {:error, reason} in the handle_checkout callbacks
2. List each occurrence with line numbers
3. Identify which returns violate NimblePool's contract

Show me your findings.
```

### Prompt 1.1.2 - Implement Fix 1
```
Now let's implement Fix 1 from the design doc.

First, re-read:
1. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 1: NimblePool Return Value Corrections"
2. The current lib/dspex/python_bridge/pool_worker_v2.ex file

Then implement these changes:
1. Update handle_session_checkout at lines 205-206 to return {:remove, {:checkout_failed, reason}, pool_state}
2. Update handle_anonymous_checkout at lines 234-235 with the same pattern
3. Ensure all error paths return valid NimblePool tuples

Show me:
1. The complete updated handle_session_checkout function
2. The complete updated handle_anonymous_checkout function
3. A diff of your changes
```

### Prompt 1.1.3 - Enhance Error Handling
```
Let's enhance the Port.connect error handling.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section showing the enhanced catch block
2. Current error handling in lib/dspex/python_bridge/pool_worker_v2.ex lines 212-220

Now update the error handling to:
1. Catch :error with specific handling
2. Catch :exit with specific handling  
3. Catch all other exceptions with generic handling
4. Add appropriate logging for each error type
5. Return proper NimblePool responses for each case

Show me the complete updated try/catch block with all error cases handled.
```

### Prompt 1.1.4 - Test the Fixes
```
Let's test our NimblePool return value fixes.

First, check if test file exists:
1. Run: ls test/pool_worker_v2_return_values_test.exs
2. If it doesn't exist, we'll create it

Create test/pool_worker_v2_return_values_test.exs with tests for:
1. Successful checkout returning {:ok, client_state, worker_state, pool_state}
2. Connection failure returning {:remove, reason, pool_state}
3. Process not alive returning {:remove, reason, pool_state}
4. General exception returning {:remove, reason, pool_state}

After creating the test file:
1. Run: mix test test/pool_worker_v2_return_values_test.exs
2. Show me the complete test file
3. Show me the test results
```

## Session 1.2: Port Validation Enhancement

### Prompt 1.2.1 - Implement Port Validation
```
Let's add port validation functions.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 2: Port Validation Enhancement"
2. Current lib/dspex/python_bridge/pool_worker_v2.ex to find where to add the functions

Now implement these new functions after line 380 in pool_worker_v2.ex:
1. validate_port/1 - checks if port is valid and owned by current process
2. safe_port_connect/3 - safely connects port with full validation

Include:
- Proper @doc strings
- Type specifications  
- Comprehensive error handling
- Logging for debugging

Show me the complete implementation of both functions.
```

### Prompt 1.2.2 - Update Checkout Logic
```
Now let's update the checkout logic to use our new safe port connection.

First, read:
1. Current handle_session_checkout implementation in lib/dspex/python_bridge/pool_worker_v2.ex lines 196-208
2. The safe_port_connect/3 function we just implemented

Replace the current port validation logic with:
1. Call to safe_port_connect/3
2. Proper handling of all return values
3. Appropriate NimblePool responses for each case

Show me:
1. The complete updated handle_session_checkout function
2. How it handles each possible return from safe_port_connect
```

### Prompt 1.2.3 - Test Port Validation
```
Let's create comprehensive tests for port validation.

First, check existing test coverage:
1. Run: ls test/dspex/python_bridge/pool_worker_v2_test.exs
2. If it exists, read it to see current tests

Create or update tests to cover:
1. Valid port and process - should succeed
2. Closed port - should return error
3. Dead process - should return error  
4. Port not owned by current process - should return error
5. Race condition where process dies during connection

After creating/updating tests:
1. Run: mix test test/dspex/python_bridge/pool_worker_v2_test.exs
2. Show me the test implementation
3. Show me test results
```

## Session 1.3: Test Assertion Fixes

### Prompt 1.3.1 - Fix Concurrent Test Assertions
```
Let's fix test assertions that expect wrong data types.

First, read:
1. test/pool_v2_concurrent_test.exs - find assertions at lines 155 and 170
2. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 3: Test Assertion Corrections"

The issue: Tests expect 'programs' to be a list but it's actually a map with a "programs" key.

Update the assertions to:
1. First check result is a map
2. Extract the "programs" key
3. Then verify it's a list
4. Also check "total_count" if present

Show me:
1. The original assertions
2. The fixed assertions
3. The complete updated test functions
```

### Prompt 1.3.2 - Run and Verify
```
Let's run the fixed concurrent tests.

First, check the test environment:
1. Run: echo $TEST_MODE
2. If not set to "full_integration", set it: export TEST_MODE=full_integration

Now run the tests:
1. Run: TEST_MODE=full_integration mix test test/pool_v2_concurrent_test.exs --trace
2. Note which tests pass/fail
3. For any failures, show the full error message

Show me:
1. The command executed
2. Summary of test results (X passed, Y failed)
3. Full error messages for any failures
4. Next steps to fix remaining issues
```

## Session 1.4: Test Configuration Guards

### Prompt 1.4.1 - Add Test Guards
```
Let's add proper test configuration guards.

First, read:
1. test/pool_fixed_test.exs
2. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 4: Test Configuration Guards"

Now update test/pool_fixed_test.exs:
1. Add @moduletag :layer_3 after the module declaration
2. Add a setup block that checks TEST_MODE and pooling_enabled
3. Skip tests with a clear message if environment doesn't match
4. Remove any Application.put_env calls (they don't work after app starts)

Show me:
1. The complete updated module attributes and setup block
2. Any lines that need to be removed
```

### Prompt 1.4.2 - Create Test Helper
```
Let's create a reusable test helper module.

First, check if directory exists:
1. Run: ls test/support/
2. If it doesn't exist: mkdir -p test/support

Now create test/support/pool_test_helpers.ex based on:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 7"
2. Include the start_test_pool/1 function
3. Include wait_for_pool_ready/2 function
4. Add proper module documentation

After creating:
1. Run: mix compile
2. Show me the complete helper module
3. Show any compilation errors
```

## Session 1.5: Service Detection Fix

### Prompt 1.5.1 - Update Service Detection
```
Let's improve the service detection logic.

First, read:
1. lib/dspex/adapters/python_port.ex - find detect_running_service function (lines 55-68)
2. docs/V2_POOL_TECHNICAL_DESIGN_2_IMMEDIATE_FIXES.md section "Fix 5: Service Detection Improvement"

Now replace the detect_running_service function with an improved version that:
1. Uses Process.whereis first (more reliable than Registry)
2. Falls back to Registry.lookup if needed
3. Handles all possible states gracefully

Show me:
1. The current detect_running_service function
2. The complete new implementation
3. A diff of the changes
```

### Prompt 1.5.2 - Test Service Detection
```
Let's test the updated service detection.

First, check what tests exist:
1. Run: ls test/dspex/adapters/python_port_test.exs
2. If it doesn't exist, we'll create it

Create or update tests to verify:
1. Pool detection when pool is running
2. Bridge detection when single bridge is running  
3. Proper error when neither is available
4. Fallback from Process.whereis to Registry works

After creating/updating tests:
1. Run: mix test test/dspex/adapters/python_port_test.exs
2. Show me the test file
3. Show me test results
```

## Session 1.6: Integration Testing

### Prompt 1.6.1 - Run All Fixed Tests
```
Let's verify all our fixes work correctly.

First, check what we've modified:
1. Run: git status
2. Run: git diff --name-only

Now run the affected tests:
1. Run: TEST_MODE=full_integration mix test test/pool_v2_concurrent_test.exs
2. Run: TEST_MODE=full_integration mix test test/pool_fixed_test.exs  
3. Run: mix test test/pool_worker_v2_return_values_test.exs

For each test run, show me:
1. The command executed
2. The number of tests passed/failed
3. Any error messages in full
4. Overall test result
```

### Prompt 1.6.2 - Fix Remaining Issues
```
Based on test results, let's fix any remaining issues.

For each failing test:
1. Show me the specific error message
2. Find the related code by searching: grep -n "function_name" lib/
3. Read the failing test to understand expectations
4. Propose a fix based on our design docs
5. Implement and re-run just that test

Continue until all tests pass. Show me:
1. Each fix applied
2. Test result after fix
3. Running count of passing tests
```

## Session 1.7: Documentation and Commit

### Prompt 1.7.1 - Update Documentation
```
Let's update our progress documentation.

First, read the current CLAUDE.md file to see what's already documented.

Then update CLAUDE.md with a new section for Phase 1 containing:
1. List of all fixes implemented:
   - Fix 1: NimblePool return values (files modified)
   - Fix 2: Port validation enhancement (functions added)
   - Fix 3: Test assertions corrected (tests updated)
   - Fix 4: Test configuration guards (setup blocks added)
   - Fix 5: Service detection improved (logic updated)
2. Test commands that verify the fixes
3. Any architectural decisions or trade-offs made
4. Known limitations or edge cases
5. Clear starting point for Phase 2

Show me the complete new section to add to CLAUDE.md.
```

### Prompt 1.7.2 - Create Commit
```
Let's create a comprehensive commit for Phase 1.

First, review all changes:
1. Run: git status
2. Run: git diff --stat
3. Run: git diff (review actual changes)

Stage changes interactively:
1. Run: git add -p
2. Review each change and stage appropriately

Create commit with detailed message:
1. Use format: "Phase 1: Immediate fixes for V2 Pool implementation"
2. List all fixes in bullet points
3. Include test results summary
4. Note any breaking changes

Show me:
1. Files staged for commit
2. The complete commit message
3. Result of: git log --oneline -1 after committing
```

## Session 1.8: Phase 1 Validation

### Prompt 1.8.1 - Validate Completion
```
Let's validate that Phase 1 is complete.

First, let's check our progress:
1. Run: mix test to see overall test status
2. Run: grep -r "TODO" lib/dspex/python_bridge/ to find any TODOs
3. Run: git diff to review all changes

Now create a Phase 1 completion checklist:
- [ ] All {:error, reason} returns fixed in pool_worker_v2.ex
- [ ] Port validation functions implemented and tested
- [ ] Test assertions updated for correct data types
- [ ] Test configuration guards added
- [ ] Service detection improved
- [ ] All tests passing
- [ ] Documentation updated
- [ ] No regressions introduced

For each item, note if it's complete and provide evidence (test results, file changes, etc).
```

### Prompt 1.8.2 - Prepare Phase 2
```
Let's prepare for Phase 2 implementation.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md - get overview
2. Current CLAUDE.md to see Phase 1 status

Create a Phase 2 preparation checklist:
1. What new files need to be created?
   - List each with its purpose
2. What existing files need modification?
   - List each with expected changes
3. What tests need to be written?
   - List test categories
4. What are the dependencies on Phase 1?
   - Verify all are complete
5. What are the main risk areas?
   - List potential challenges

Save this as PHASE2_CHECKLIST.md for next session.
```
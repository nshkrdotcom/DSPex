# V2 Pool Implementation Prompts - Phase 1: Immediate Fixes

## Session 1.1: NimblePool Return Value Fixes

### Prompt 1.1.1 - Initial Analysis
```
We're implementing Phase 1 of the V2 Pool design, specifically fixing NimblePool return values.
Current status: Starting fresh with identified issues from the analysis
Today's goal: Fix all {:error, reason} returns to use proper NimblePool contract

First, read lib/dspex/python_bridge/pool_worker_v2.ex and find all instances where we return {:error, reason} in the handle_checkout callbacks. List each occurrence with line numbers.
```

### Prompt 1.1.2 - Implement Fix 1
```
Now implement Fix 1 from Design Doc 2. Update the handle_session_checkout function at lines 205-206 to return {:remove, {:checkout_failed, reason}, pool_state} instead of {:error, reason}.

Also update the error handling at lines 234-235 in handle_anonymous_checkout with the same pattern.

Show me the complete updated functions.
```

### Prompt 1.1.3 - Enhance Error Handling
```
Update the Port.connect error handling (lines 212-220) to catch all error types as specified in Design Doc 2. Add handlers for :exit and general exceptions.

Include appropriate logging for each error type. Show me the complete try/catch block.
```

### Prompt 1.1.4 - Test the Fixes
```
Create a test file test/pool_worker_v2_return_values_test.exs that specifically tests these return value fixes. Include tests for:
1. Successful checkout returning proper tuple
2. Connection failure returning :remove
3. Process not alive returning :remove
4. General exception returning :remove

Run the tests and show results.
```

## Session 1.2: Port Validation Enhancement

### Prompt 1.2.1 - Implement Port Validation
```
Add the validate_port/1 and safe_port_connect/3 helper functions from Design Doc 2 to pool_worker_v2.ex after line 380.

These functions should check if a port is valid before attempting connection and handle the race condition between Process.alive? and Port.connect.
```

### Prompt 1.2.2 - Update Checkout Logic
```
Update handle_session_checkout (lines 196-208) to use the new safe_port_connect function instead of the current port validation logic.

The new implementation should handle all error cases and return appropriate NimblePool responses.
```

### Prompt 1.2.3 - Test Port Validation
```
Create tests for the new port validation logic. Include test cases for:
1. Valid port and process
2. Closed port
3. Dead process
4. Port not owned by current process
5. Race condition where process dies during connection

Add these to the test file and run them.
```

## Session 1.3: Test Assertion Fixes

### Prompt 1.3.1 - Fix Concurrent Test Assertions
```
Read test/pool_v2_concurrent_test.exs and fix the test assertions at lines 155 and 170 that expect programs to be a list but receive a map.

Update the assertions to first check for a map, extract the "programs" key, then verify it's a list.
```

### Prompt 1.3.2 - Run and Verify
```
Run the concurrent tests with:
TEST_MODE=full_integration mix test test/pool_v2_concurrent_test.exs

Show me the results. If there are still failures, let's fix them one by one.
```

## Session 1.4: Test Configuration Guards

### Prompt 1.4.1 - Add Test Guards
```
Update test/pool_fixed_test.exs to add proper setup guards that skip tests when not in the correct TEST_MODE.

Add the module attribute and setup block from Design Doc 2 after line 6. Remove the ineffective Application.put_env calls.
```

### Prompt 1.4.2 - Create Test Helper
```
Create test/support/pool_test_helpers.ex based on Design Doc 2's Fix 7. This should include:
1. start_test_pool/1 function with eager initialization
2. wait_for_pool_ready/2 function
3. Proper configuration for test pools

Make sure the file is properly documented.
```

## Session 1.5: Service Detection Fix

### Prompt 1.5.1 - Update Service Detection
```
Read lib/dspex/adapters/python_port.ex and replace the detect_running_service function (lines 55-68) with the improved version from Design Doc 2.

The new version should use Process.whereis first, then fall back to Registry lookups.
```

### Prompt 1.5.2 - Test Service Detection
```
Create a test for the updated service detection that verifies:
1. Pool detection when pool is running
2. Bridge detection when single bridge is running  
3. Proper error when neither is available
4. Fallback from Process.whereis to Registry

Run the tests and show results.
```

## Session 1.6: Integration Testing

### Prompt 1.6.1 - Run All Fixed Tests
```
Let's run all the tests we've fixed to ensure everything works:

1. TEST_MODE=full_integration mix test test/pool_v2_concurrent_test.exs
2. TEST_MODE=full_integration mix test test/pool_fixed_test.exs  
3. mix test test/pool_worker_v2_return_values_test.exs

Show me the results of each test run.
```

### Prompt 1.6.2 - Fix Remaining Issues
```
Based on the test results, are there any remaining failures? If so, let's examine each one:
1. Show me the specific error
2. Find the related code
3. Propose a fix based on our design docs
4. Implement and test the fix
```

## Session 1.7: Documentation and Commit

### Prompt 1.7.1 - Update Documentation
```
Update CLAUDE.md with:
1. Summary of all Phase 1 fixes implemented
2. Test commands to verify the fixes
3. Any architectural decisions made
4. Known issues or limitations
5. Next phase starting point
```

### Prompt 1.7.2 - Create Commit
```
Create a comprehensive git commit for Phase 1:
1. Show me all modified files with git status
2. Review the changes with git diff
3. Create a commit message following the pattern:

"Phase 1: Immediate fixes for V2 Pool implementation

- Fixed NimblePool return values to use :remove instead of :error
- Added Port.info validation before Port.connect  
- Updated test assertions for map responses
- Added test configuration guards
- Improved service detection with Process.whereis

Tests: X/Y passing
Next: Phase 2 - Worker lifecycle management"
```

## Session 1.8: Phase 1 Validation

### Prompt 1.8.1 - Validate Completion
```
Let's validate Phase 1 completion:
1. Run the full test suite and count passed/failed
2. Check that all Design Doc 2 fixes are implemented
3. Verify no regressions were introduced
4. Create a Phase 1 completion report

Show me the validation results.
```

### Prompt 1.8.2 - Prepare Phase 2
```
Review Design Doc 3 (Worker Lifecycle) and create a checklist for Phase 2:
1. What files need to be created?
2. What existing files need modification?
3. What tests need to be written?
4. What are the key risk areas?

Save this as PHASE2_CHECKLIST.md
```
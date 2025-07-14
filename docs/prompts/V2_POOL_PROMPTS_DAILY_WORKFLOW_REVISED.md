# V2 Pool Implementation - Daily Workflow Prompts (REVISED)

## 🌅 Day Start Routine

### Check Status and Context
```
I'm starting work on V2 Pool implementation. Please:

First, read these files for context:
1. Read CLAUDE.md to see current progress and last session notes
2. Check current phase: grep "Phase" CLAUDE.md | head -5
3. Read the TODO section from the relevant design doc based on current phase

Then show me:
1. Current implementation phase
2. Last completed task
3. Next immediate task
4. Any blockers noted
```

### Review Uncommitted Work
```
Let's check for any uncommitted work from last session.

First, check repository state:
1. Run: git status
2. Run: git diff --stat
3. Run: git diff --cached

If there are uncommitted changes:
1. Review each file's changes
2. Determine if work was complete
3. Run relevant tests: mix test [changed_test_files]
4. Suggest whether to commit, continue, or discard

Show me findings and recommendations.
```

### Run Morning Test Suite
```
Let's verify system health before starting new work.

First, understand test requirements:
1. Check TEST_MODE: echo $TEST_MODE
2. If not set, determine from current work phase

Run appropriate tests:
1. For Phase 1-2: mix test test/dspex/python_bridge/
2. For Phase 3-4: TEST_MODE=full_integration mix test --only integration
3. For Phase 5: mix test --only monitoring
4. Check for any new failures

Show me:
1. Test command used
2. Summary of results
3. Any new failures to address
```

## 📋 Task Management

### Create Today's Task List
```
Let's plan today's work based on current phase.

First, read relevant sections:
1. Read current phase's design doc TODO section
2. Check CLAUDE.md for work in progress
3. Review any failing tests that need fixes

Create task list for today:
1. Immediate bug fixes (if any)
2. Next implementation task from design
3. Tests to write/update
4. Documentation to update
5. Code review items

Show me prioritized task list with time estimates.
```

### Select Next Task
```
I need to select the next task to work on.

First, check current context:
1. Read today's task list from CLAUDE.md
2. Check for any blocking issues
3. Review prerequisites for next task

Evaluate tasks by:
1. Dependencies satisfied?
2. Complexity vs available time
3. Impact on other work
4. Test coverage needs

Recommend:
1. Which task to tackle
2. Estimated completion time
3. Any prep work needed

Show me recommendation and why.
```

## 💻 Implementation Workflow

### Start Implementation Task
```
I'm starting work on [task_name]. Please:

First, prepare by reading:
1. Read the relevant design doc section for [task_name]
2. Check existing similar implementations: grep -r "similar_pattern" lib/
3. Review test requirements for this component

Set up work:
1. Create/update TODO list in CLAUDE.md
2. List files that need modification
3. Identify test files to create/update
4. Note any architectural decisions needed

Show me:
1. Implementation checklist
2. File creation/modification order
3. Key design decisions to make
```

### Implement with TDD
```
Let's implement [feature] using TDD approach.

First, understand requirements:
1. Read design doc section for [feature]
2. Check similar test patterns: ls test/dspex/python_bridge/*_test.exs
3. Identify test scenarios needed

Follow TDD cycle:
1. Write failing test for basic case
2. Run test to confirm failure
3. Implement minimal code to pass
4. Run test to confirm success
5. Refactor if needed

Show me:
1. Test file with first test
2. Run test showing failure
3. Minimal implementation
4. Test now passing
```

### Debug Failed Implementation
```
The implementation of [feature] is failing. Let's debug.

First, gather information:
1. Show exact error message
2. Read the failing code section
3. Check recent changes: git diff HEAD~ -- [file]
4. Look for similar working code

Debug steps:
1. Add IO.inspect at failure point
2. Check function inputs/outputs
3. Verify state at each step
4. Look for type mismatches
5. Check integration points

Show me:
1. Root cause analysis
2. Proposed fix
3. How to verify fix works
```

## 🧪 Testing Workflow

### Fix Failing Test
```
Test [test_name] is failing. Let's fix it.

First, understand the failure:
1. Run single test: mix test [file]:[line]
2. Read the test implementation
3. Read the code being tested
4. Check test assumptions

Diagnose issue:
1. Is test expectation wrong?
2. Is implementation buggy?
3. Has behavior changed?
4. Is test flaky?

Show me:
1. Failure analysis
2. Fix approach
3. Verification steps
```

### Write Integration Test
```
Let's write an integration test for [feature].

First, prepare:
1. Read integration test patterns: ls test/integration/
2. Check layer requirements: grep -r "@moduletag" test/
3. Review feature's integration points

Create integration test:
1. Set appropriate moduletag
2. Set up test environment
3. Test realistic scenarios
4. Verify error handling
5. Check resource cleanup

Show me:
1. Complete test implementation
2. How to run it
3. Expected output
```

### Run Test Coverage Check
```
Let's check test coverage for our changes.

First, if coverage tool available:
1. Run: mix coveralls.html
2. Open coverage report
3. Look for uncovered lines

Analyze coverage:
1. Identify uncovered branches
2. Find missing error cases
3. Check edge conditions
4. Look for dead code

Show me:
1. Coverage statistics
2. Key uncovered areas
3. Tests to add
```

## 🔍 Code Review

### Self-Review Changes
```
Let's review my changes before committing.

First, see what changed:
1. Run: git diff --stat
2. Run: git diff
3. Check for debug code: grep -r "IO.inspect\|TODO" [changed_files]

Review checklist:
1. Code follows patterns?
2. Error handling complete?
3. Tests comprehensive?
4. Documentation updated?
5. No debug artifacts?

Show me:
1. Files changed summary
2. Any issues found
3. Improvements needed
```

### Prepare Commit
```
Let's prepare changes for commit.

First, organize changes:
1. Run: git status
2. Group related changes
3. Check commit guidelines

Prepare commit:
1. Stage files: git add -p
2. Review staged changes
3. Write commit message
4. Include issue references
5. Note breaking changes

Show me:
1. Staged files
2. Commit message draft
3. Pre-commit checklist
```

## 📊 Progress Tracking

### Update Progress Documentation
```
Let's update our progress tracking.

First, gather today's accomplishments:
1. List completed tasks
2. Note any blockers resolved
3. Document decisions made
4. Record performance metrics

Update CLAUDE.md with:
1. Today's date section
2. Tasks completed
3. Tests written/fixed
4. Issues discovered
5. Tomorrow's priorities

Show me CLAUDE.md updates to add.
```

### Create Session Summary
```
Let's summarize this work session.

First, review what we did:
1. Check git log for commits
2. List tests added/fixed
3. Note implementation progress
4. Review any issues found

Create summary with:
1. Key accomplishments
2. Code statistics
3. Test results
4. Performance notes
5. Next steps

Show me formatted summary for CLAUDE.md.
```

## 🚨 Problem Resolution

### Investigate Performance Issue
```
There's a performance issue with [component].

First, measure the problem:
1. Create benchmark for operation
2. Profile with :fprof if severe
3. Check telemetry metrics
4. Compare with baseline

Investigate:
1. Look for N+1 queries
2. Check unnecessary work
3. Review data structures
4. Examine algorithms
5. Check pooling/caching

Show me:
1. Performance measurements
2. Bottleneck identified
3. Optimization approach
```

### Handle Blocking Issue
```
I'm blocked by [issue]. Let's resolve it.

First, understand the blocker:
1. Describe exact problem
2. Show error/failure
3. List what I've tried
4. Check documentation

Resolution approaches:
1. Search for similar issues
2. Check design docs
3. Review working examples
4. Try alternative approach
5. Document workaround

Show me:
1. Issue analysis
2. Potential solutions
3. Recommended approach
```

## 🏁 Day End Routine

### End of Day Checklist
```
Let's wrap up today's work.

First, check work state:
1. Any uncommitted changes?
2. All tests passing?
3. Documentation updated?
4. TODOs captured?

Complete checklist:
□ Commit all complete work
□ Push to remote branch
□ Update CLAUDE.md progress
□ Note tomorrow's first task
□ Clean up debug code
□ Close unnecessary files

Show me what needs attention.
```

### Prepare Handoff Notes
```
Let's prepare notes for next session.

First, document current state:
1. What was completed
2. What's in progress
3. Any blockers
4. Design decisions pending

Create handoff notes:
1. Current phase/task status
2. Next immediate steps
3. Any failing tests
4. Open questions
5. Time-sensitive items

Show me handoff notes for CLAUDE.md.
```

## 🔄 Context Switching

### Resume After Break
```
I'm resuming work after a break.

First, restore context:
1. Read last session notes in CLAUDE.md
2. Check git status
3. Review recent commits: git log --oneline -10
4. Run relevant tests

Determine:
1. What was I working on?
2. What's the current state?
3. Any failures to address?
4. Next immediate action?

Show me current context and next steps.
```

### Switch Between Tasks
```
I need to switch from [current_task] to [new_task].

First, save current state:
1. Commit or stash current work
2. Document stopping point
3. Note any pending items
4. Run tests if needed

Prepare for new task:
1. Read design doc section
2. Check prerequisites
3. Review related code
4. Plan approach

Show me transition steps.
```

## 📈 Weekly Planning

### Weekly Review
```
Let's do a weekly review of V2 Pool progress.

First, gather metrics:
1. Commits this week: git log --since="1 week ago"
2. Tests added/fixed
3. Components completed
4. Issues resolved

Analyze:
1. Progress vs plan
2. Velocity trends
3. Blocker patterns
4. Quality metrics

Show me:
1. Week's accomplishments
2. Metrics summary
3. Areas for improvement
```

### Plan Next Week
```
Let's plan next week's V2 Pool work.

First, assess current state:
1. Current phase progress
2. Remaining tasks in phase
3. Known blockers
4. Team dependencies

Plan week:
1. Priority objectives
2. Daily milestones
3. Risk mitigation
4. Buffer time
5. Success criteria

Show me weekly plan with daily breakdown.
```
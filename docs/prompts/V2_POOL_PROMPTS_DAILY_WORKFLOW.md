# V2 Pool Implementation - Daily Workflow Prompts

## Daily Session Structure

### Morning Session Start (Every Day)

#### Prompt D.1 - Context Loading
```
Good morning! I'm continuing the V2 Pool implementation.

Please load context by:
1. Reading CLAUDE.md for current progress
2. Checking git status for work in progress
3. Running test suite to see current state

Show me the current status summary.
```

#### Prompt D.2 - Daily Planning
```
Based on the current status, let's plan today's work:

1. What phase and session are we on?
2. What specific components need implementation?
3. Are there any failing tests to fix first?
4. What's our goal for today's session?

Create a specific task list for the next 2 hours.
```

### Code Implementation Flow

#### Prompt D.3 - Before Each Implementation
```
Before implementing [component name]:

1. Show me the current code that will be affected
2. Find similar patterns in the codebase we should follow
3. Review the relevant section in Design Doc [X]
4. List any risks or considerations

Then let's implement step by step.
```

#### Prompt D.4 - After Each Implementation
```
We just implemented [component name]. Now:

1. Run the specific tests for this component
2. Check for any compilation warnings
3. Verify no regressions with: mix test [related test file]
4. Update the documentation if needed

Show me the test results.
```

### Testing Workflow

#### Prompt D.5 - Test First Development
```
Let's write tests for [feature] before implementing:

1. Create test file: test/[path]/[feature]_test.exs
2. Write tests for happy path
3. Write tests for error cases
4. Write edge case tests
5. Run tests to see them fail

Then we'll implement to make them pass.
```

#### Prompt D.6 - Fix Failing Tests
```
We have failing tests. For each failure:

1. Show me the exact error message
2. Find the related code causing the failure
3. Propose a fix based on our design
4. Implement the fix
5. Re-run just that test

Continue until all tests pass.
```

### Mid-Session Checkpoint

#### Prompt D.7 - Progress Check
```
Let's checkpoint our progress:

1. What have we completed so far today?
2. Run all affected tests
3. Check code coverage if available
4. Any unexpected issues encountered?
5. Are we on track for today's goal?

Show me a progress summary.
```

### End of Session

#### Prompt D.8 - Session Wrap-up
```
Let's wrap up today's session:

1. Create a git commit with a descriptive message
2. Update CLAUDE.md with:
   - What we implemented
   - Key decisions made
   - Any pending issues
   - Next session starting point
3. Run full test suite one more time
4. Document any new commands or procedures

Show me the commit and documentation updates.
```

### Common Troubleshooting

#### Prompt D.9 - Debug Complex Error
```
We're seeing error: [paste error]

Let's debug systematically:
1. Show me the full stack trace
2. Find all code paths that could lead here
3. Add debug logging to trace execution
4. Check for similar issues in git history
5. Propose three potential fixes

Let's try the most likely fix first.
```

#### Prompt D.10 - Performance Issue
```
The [operation] seems slow. Let's investigate:

1. Add timing logs around the operation
2. Check for N+1 queries or loops
3. Look for unnecessary work
4. Compare with similar operations
5. Propose optimization strategies

Implement the easiest optimization first.
```

### Weekly Checkpoints

#### Prompt W.1 - Monday Planning
```
It's Monday, let's review and plan the week:

1. What phase are we in?
2. What's the goal for this week?
3. Any blockers from last week?
4. Review the implementation timeline
5. Set specific daily targets

Create a week plan with daily goals.
```

#### Prompt W.2 - Friday Review
```
It's Friday, let's review the week:

1. What did we complete this week?
2. Run full test suite and check coverage
3. Any technical debt introduced?
4. What went well vs challenges?
5. Plan for next week

Create a week summary report.
```

### Special Situations

#### Prompt S.1 - Major Refactor
```
We need to refactor [component]. Let's be systematic:

1. Document current behavior with tests
2. Create a refactoring plan
3. Make incremental changes
4. Run tests after each change
5. Keep commits small and focused

Start with the safest change first.
```

#### Prompt S.2 - Integration Point
```
We're integrating [component A] with [component B]:

1. Review both component interfaces
2. Write integration tests first
3. Implement minimal integration
4. Test error scenarios
5. Add monitoring/logging

Ensure clean separation of concerns.
```

#### Prompt S.3 - Performance Optimization
```
Let's optimize [component] performance:

1. Establish baseline metrics
2. Profile to find bottlenecks
3. Implement optimization
4. Measure improvement
5. Ensure no functional regression

Document before/after metrics.
```

### Quick Reference

#### Prompt Q.1 - Run Specific Tests
```
Run these specific tests:
- Unit tests for [module]: mix test test/[module]_test.exs
- Integration tests: TEST_MODE=full_integration mix test test/integration/
- Single test: mix test test/[file].exs:[line]
- With coverage: mix coveralls

Show me the results.
```

#### Prompt Q.2 - Code Quality Check
```
Let's check code quality:
1. Run formatter: mix format
2. Run credo: mix credo --strict
3. Run dialyzer: mix dialyzer
4. Check for TODOs: grep -r "TODO" lib/
5. Look for debug code: grep -r "IO.inspect" lib/

Fix any issues found.
```

#### Prompt Q.3 - Git Workflow
```
For git operations:
1. See changes: git status and git diff
2. Stage changes: git add -p (interactive)
3. Commit with message: git commit -m "Type: Description"
4. Check history: git log --oneline -10
5. Create branch: git checkout -b feature/v2-pool-[component]

Follow conventional commit format.
```

## Usage Instructions

1. Start each day with D.1 and D.2
2. Use D.3-D.4 for each component implementation
3. Use D.5-D.6 for test-driven development
4. Check progress with D.7 mid-session
5. Always end with D.8
6. Use troubleshooting prompts as needed
7. Weekly prompts on Monday/Friday
8. Special situation prompts when applicable

Remember: Small, focused sessions with clear goals lead to steady progress!
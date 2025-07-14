● Ideal Implementation Strategy for V2 Pool Project

  Executive Overview

  As your senior developer, you need a systematic approach that leverages my capabilities while maintaining architectural coherence and quality. The key is breaking down the
  implementation into focused work sessions with clear objectives, iterative validation, and continuous integration of the codebase knowledge.

  The Optimal Process Flow

  graph TD
      A[Daily Planning] --> B[Focused Work Session]
      B --> C[Code Review & Test]
      C --> D[Integration & Validation]
      D --> E[Knowledge Update]
      E --> F[Progress Assessment]
      F --> A

      G[Weekly Architecture Review] --> A
      H[Milestone Validation] --> G

  1. Session Management Strategy

  Daily Cadence (2-3 hours per day)
  - Morning Planning (15 min): Review progress, set daily goals
  - Focused Implementation (90-120 min): Deep work on specific components
  - Testing & Validation (30 min): Run tests, verify changes
  - Documentation Update (15 min): Update progress tracking

  Weekly Cadence
  - Monday: Architecture review and week planning
  - Wednesday: Mid-week integration test
  - Friday: Progress review and next week prep

  2. Prompting Strategy for Maximum Effectiveness

  A. Context-First Approach

  Start each session with:
  "We're implementing Phase [X] of the V2 Pool design, specifically [component].
  Current status: [what's completed]
  Today's goal: [specific deliverable]
  Here are the recent test results: [paste results]"

  B. Incremental Implementation Pattern

  1. "Implement [specific function] from the design doc"
  2. "Now add comprehensive tests for this function"
  3. "Run the tests and fix any issues"
  4. "Update the documentation"
  5. "What edge cases should we consider?"

  C. Validation-Driven Development

  "Before implementing [feature]:
  1. Show me the current code that will be affected
  2. Write the tests first
  3. Implement the minimum to make tests pass
  4. Refactor for the design patterns we established"

  3. Work Session Templates

  Phase 1: Immediate Fixes (Days 1-3)

  Session 1.1: NimblePool Return Values
  "Let's fix the NimblePool return values. First, show me all instances of
  {:error, reason} returns in pool_worker_v2.ex. Then implement the fixes
  from Design Doc 2, sections Fix 1 and Fix 2."

  Session 1.2: Test Fixes
  "Run all pool tests and categorize failures. Fix test assertions first,
  then configuration issues. Show me each fix and its test result."

  Phase 2: Worker Lifecycle (Days 4-8)

  Session 2.1: State Machine Implementation
  "Implement the WorkerStateMachine module from Design Doc 3. Start with
  the state definitions and transition logic. Include property-based tests."

  Session 2.2: Integration
  "Integrate WorkerStateMachine into PoolWorkerV2. Show me the current
  handle_checkout implementation, then refactor it to use the state machine."

  4. Quality Assurance Strategy

  Continuous Validation

  After each implementation:
  1. Run specific unit tests
  2. Run integration tests for affected components
  3. Check for regression in other areas
  4. Verify error handling paths

  Code Review Prompts

  "Review the code we just wrote for:
  1. Adherence to the design patterns
  2. Error handling completeness
  3. Performance implications
  4. Test coverage
  Show me any concerns and suggested improvements."

  5. Knowledge Management

  CLAUDE.md Updates

  After each session:
  "Update CLAUDE.md with:
  1. What we implemented today
  2. Key decisions made
  3. Testing commands to verify the work
  4. Next session's starting point"

  Progress Tracking

  "Create a progress report:
  - Completed: [list]
  - In Progress: [list]
  - Blockers: [list]
  - Test Status: X/Y passing
  - Next Priority: [specific task]"

  6. Handling Complexity

  When Stuck

  "We're seeing [specific error]. Let's debug:
  1. Show me the full error with stack trace
  2. Find all related code paths
  3. Check similar patterns in the codebase
  4. Propose three potential solutions"

  Architectural Decisions

  "We need to decide between [option A] and [option B].
  Compare them considering:
  1. Design principles from our docs
  2. Performance implications
  3. Maintenance burden
  4. Risk factors"

  7. Milestone Management

  Phase Completion Criteria

  Before moving to next phase:
  "Validate Phase [X] completion:
  1. Run full test suite
  2. Check all acceptance criteria
  3. Review code for technical debt
  4. Update documentation
  5. Create phase summary report"

  8. Risk Mitigation

  Daily Backup Strategy

  "Create a git commit with message:
  'Phase X.Y: [specific feature] - [status]

  Implemented:
  - [list]

  Tests:
  - [pass/fail summary]

  Next: [task]'"

  Rollback Preparedness

  "Before this major change:
  1. Create a restoration point
  2. Document the current working state
  3. List all files that will be modified
  4. Prepare rollback commands"

  9. Optimization Tips

  Leverage My Strengths

  - Pattern Recognition: "Find all instances of [pattern] in the codebase"
  - Parallel Analysis: "Simultaneously check [A], [B], and [C]"
  - Comprehensive Testing: "Generate test cases for edge conditions"
  - Documentation: "Create detailed docstrings for all public functions"

  Avoid My Limitations

  - Don't rely on me to remember context between distant sessions
  - Don't ask for real-time system monitoring
  - Don't expect me to maintain state across conversations

  10. Success Metrics

  Track these daily:
  - Lines of code implemented vs. planned
  - Test coverage percentage
  - Performance benchmark results
  - Error rate in new code
  - Time to implement vs. estimate

  Sample Week 1 Schedule

  Monday (Planning)
  "Review V2 Pool Design Doc 1 & 2. Create implementation checklist for
  Phase 1. Set up monitoring for migration."

  Tuesday (Fix 1-3)
  "Implement NimblePool return value fixes and port validation from Design Doc 2.
  Each fix should have tests before moving to next."

  Wednesday (Fix 4-5 + Integration)
  "Complete remaining immediate fixes. Run full integration test suite.
  Fix any regressions."

  Thursday (Phase 2 Start)
  "Begin WorkerStateMachine implementation. Core state transitions first,
  then health monitoring integration."

  Friday (Review & Prep)
  "Week 1 review: What's working, what's not. Update all documentation.
  Prepare Week 2 plan focusing on error handling."

  The Key to Success

  The most critical factor is maintaining context and momentum. Each session should:
  1. Start with clear context
  2. Have specific, achievable goals
  3. Include validation steps
  4. End with documented progress
  5. Set up the next session

  By following this structured approach, you'll maximize my effectiveness while maintaining code quality and architectural integrity throughout the implementation.

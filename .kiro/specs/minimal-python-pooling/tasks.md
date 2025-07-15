# Implementation Plan

- [x] 1. Set up core pool infrastructure and interfaces





  - Create directory structure for the minimal pooling components
  - Define core interfaces and data structures for the Golden Path architecture
  - Implement basic configuration handling for pool parameters
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 2. Implement PoolWorkerV2 with direct port communication





  - Create PoolWorkerV2 module with NimblePool callback implementations
  - Implement Python process initialization with health verification using ping command
  - Code direct port connection handling for checkout/checkin operations
  - Write unit tests for worker lifecycle and port communication
  - _Requirements: 1.1, 1.3, 6.1, 6.2, 6.3, 6.4_

- [ ] 3. Create SessionPoolV2 pool manager
  - Implement SessionPoolV2 GenServer with NimblePool integration
  - Code execute_in_session/4 and execute_anonymous/3 functions
  - Implement pool status and statistics collection
  - Write unit tests for pool management operations
  - _Requirements: 1.1, 1.2, 4.1, 4.2, 4.3_

- [ ] 4. Build PythonPoolV2 public API adapter
  - Create PythonPoolV2 module as the single entry point
  - Implement execute_program/3 with timeout handling
  - Code health_check/1 and get_stats/1 functions
  - Write unit tests for API layer functionality
  - _Requirements: 1.1, 1.4, 2.1, 2.2, 2.3_

- [ ] 5. Implement supervision tree with PoolSupervisor
  - Create PoolSupervisor with proper supervision strategy
  - Implement PoolMonitor for health checks and session cleanup
  - Code automatic worker restart and pool recovery logic
  - Write unit tests for supervision and failure recovery
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 6. Create structured error handling system
  - Implement structured error tuple format {category, type, message, context}
  - Code error categorization for timeout, resource, communication, and system errors
  - Implement error recovery strategies at worker and pool levels
  - Write unit tests for error handling and recovery scenarios
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 7. Implement session tracking for observability
  - Create ETS table for session monitoring and statistics
  - Code session_id inclusion in logs and telemetry without enforcing affinity
  - Implement session tracking that works with stateless architecture
  - Write unit tests for session tracking functionality
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 8. Create focused test suite with core_pool tags
  - Add @moduletag :core_pool to essential test modules
  - Create comprehensive test coverage for API, pool management, worker, and protocol layers
  - Implement test execution strategy using mix test --only core_pool
  - Verify all core functionality works correctly through tagged tests
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 9. Integrate and validate complete pooling system
  - Wire together all components in the supervision tree
  - Implement end-to-end integration tests for the complete Golden Path
  - Validate direct port communication flow from client to Python process
  - Test concurrent operations and pool behavior under load
  - _Requirements: 1.1, 1.2, 1.3, 6.1, 6.2, 6.3, 6.4_

- [ ] 10. Verify exclusion of complex enterprise features
  - Ensure no session state management or migration capabilities are included
  - Verify simple PoolWorkerV2 is used instead of enhanced variants
  - Confirm complex error orchestration beyond basic supervision is excluded
  - Validate the implementation focuses only on essential pooling functionality
  - _Requirements: 7.1, 7.2, 7.3, 7.4_
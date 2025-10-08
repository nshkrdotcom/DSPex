# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2025-10-07

### Added
- **Python Module**: `dspy_variable_integration.py` with variable-aware DSPy classes
  - Extracted from Snakepit v0.4.2 for clean separation of concerns
  - VariableAwarePredict, VariableAwareChainOfThought, VariableAwareReAct, VariableAwareProgramOfThought
  - ModuleVariableResolver and create_variable_aware_program helper
- **Architecture Documentation**: Comprehensive review in `docs/architecture_review_20251007/`
  - Complete analysis of Snakepit-DSPex coupling
  - Detailed decoupling plan and implementation guide
  - Architecture Decision Record (ADR-001)

### Changed
- **API Modernization**: All modules migrated to Snakepit v0.4.3 API
  - DSPex.Config now uses `check_dspy` tool instead of removed `Snakepit.Python.call/3`
  - DSPex.LM now uses `configure_lm` tool with proper session management
  - 9 total modules updated with modern API patterns
- **Dependency**: Updated Snakepit to v0.4.3 (with DSPy deprecation notice)

### Removed
- **Redundant Module**: Removed `lib/dspex/python/bridge.ex` (use DSPex.Bridge directly)

### Fixed
- **Examples Working**: Core DSPy examples functional after API migration
  - Fixed DSPex.Config.init() migration to new API
  - Fixed DSPex.LM.configure() using modern patterns
- **Test Suite**: All 82 tests passing with migrated modules

### Deprecated in Dependencies
- **Snakepit DSPy Integration**: Snakepit v0.4.3 deprecates its DSPy integration
  - DSPy-specific code moved to DSPex (this project)
  - See: `docs/architecture_review_20251007/` for details

### Documentation
- Added comprehensive architecture review (8 detailed documents)
- Added migration guide from Snakepit DSPy integration
- Updated README with architectural changes
- Documented clean separation of concerns (infrastructure vs. domain logic)

---

## [0.2.0] - 2025-07-23

### Added
- **Universal DSPy Bridge System**: Complete schema-driven bridge with automatic discovery of 70+ DSPy classes
- **DSPex.Bridge**: Metaprogramming system with `defdsyp` macro for generating custom DSPy wrappers
- **Comprehensive Variable Management**: Type-safe variable system with constraints, validation, and batch operations
- **Dual-Backend Architecture**: Automatic switching between LocalState (microsecond latency) and BridgedState (gRPC)
- **DSPex.Context**: Central execution context with seamless backend migration and program registration
- **Variable-Aware DSPy Integration**: Automatic parameter binding and synchronization between Elixir variables and Python modules
- **Production-Ready gRPC Integration**: Enhanced Snakepit v0.4.1 integration with 17 registered Python tools
- **Advanced State Management**: Pluggable backend abstraction with state migration and capability detection
- **3-Layer Testing Architecture**: Fast unit tests (~70ms), protocol tests, and full integration tests
- **Comprehensive Documentation**: 45+ implementation documents, specs, and testing strategies
- **Benchmarking Suite**: Performance comparison between local and bridged state backends
- **Enhanced Examples**: All 5 examples updated to use real Gemini API calls with working results

### Changed
- **Updated Snakepit dependency** to v0.4.1 with enhanced gRPC capabilities  
- **Reorganized project structure** - moved legacy code to `docs/home/` directory
- **Enhanced Python adapters** with `dspy_grpc.py` tool registration system
- **Improved error handling** with comprehensive Python traceback propagation
- **Updated all examples** to demonstrate real LLM API integration

### Fixed
- **Constructor parameter binding** - resolved Snakepit JSON serialization issues with DSPy-specific signature handling
- **Session affinity and instance storage** - proper gRPC session management with worker affinity
- **Result transformation pipeline** - seamless handling of DSPy completions, prediction_data, and reasoning/answer pairs
- **Automatic backend switching** - zero-downtime migration between LocalState and BridgedState
- **Type-safe variable operations** - comprehensive constraint validation with meaningful error messages

### Technical Innovations
- **Zero-Configuration DSPy Access**: Any DSPy class usable immediately without writing Elixir wrappers
- **Performance-Optimized Execution**: Automatic backend selection based on program requirements
- **Dynamic Program Configuration**: Runtime parameter adjustment through variable bindings without restart
- **Seamless State Migration**: Backend switching without data loss or service interruption
- **Schema-Driven Auto-Discovery**: Universal access to DSPy functionality through Python introspection

## [0.1.2] - 2025-07-20

### Added
- gRPC transport support for DSPy integration

### Changed
- Updated Snakepit dependency to v0.3.3
- Default Gemini model changed to gemini-2.0-flash-lite

### Fixed
- DSPy execution over gRPC transport
- Output extraction in gRPC demo

## [0.1.1] - 2025-07-20

### Added
- Enhanced Python bridge with stored object resolution
- Fixed DSPy LM configuration issue where "stored.default_lm" wasn't being resolved
- DSPy examples for Question Answering, Chain of Thought, and Code Generation
- Model registry system for managing LLM provider prefixes (e.g., "gemini/")
- Configuration system for examples using simple Elixir config files
- Adapter comparison examples showing EnhancedPython vs GRPCPython
- Simulated streaming demonstrations for better UX
- Comprehensive debugging tools for DSPy integration
- Tool Bridge specifications for Elixir-Python RPC communication
- Documentation for stored object resolution and debugging DSPy integration

### Changed
- Enhanced bridge now properly resolves stored references in both args and kwargs
- DSPex.LM.configure now uses model registry for provider prefixes
- Improved error messages and debugging output

### Fixed
- "No LM is loaded" error when using DSPy modules
- Stored object references (e.g., "stored.default_lm") not being resolved to actual objects
- Model configuration requiring manual "gemini/" prefix addition
- Config file path issues when running from different directories
- Result extraction paths for DSPy Prediction objects

## [0.1.0] - 2025-07-20

### Added
- Initial DSPex V2 architecture implementation
- Native Elixir DSPy signature parsing
- Smart routing system for native vs Python execution
- Pipeline orchestration with mixed execution support
- Snakepit integration for Python DSPy processes (pooling and session management)
- Multi-layer testing architecture (mock, protocol, integration)
- LLM adapter pattern with initial InstructorLite and Gemini support
- Native template engine using EEx
- Comprehensive Dialyzer type checking
- Performance monitoring and metrics collection
- Process manager for worker lifecycle
- Advanced signatures example with pooling
- Full DSPy API analysis and compatibility mapping
- gRPC streaming foundation for future streaming support
- Enhanced Python bridge for dynamic method invocation
- Example applications demonstrating DSPy integration

### Changed
- Complete rewrite from V1 architecture
- Moved from direct Python calls to Snakepit pooling
- Implemented protocol-agnostic bridge design
- Reorganized project structure (moved old implementation to /old)

### Fixed
- Compilation warnings and type issues
- Test infrastructure improvements
- Worker lifecycle management
- Pool worker debugging and reliability

### Security
- Improved process isolation
- Better error handling and recovery

## [0.0.1] - 2025-07-19

### Added
- Initial prototype implementation
- Basic project structure
- Stage 1 prompts and test infrastructure

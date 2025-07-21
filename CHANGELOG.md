# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

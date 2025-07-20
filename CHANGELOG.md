# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial DSPex V2 architecture implementation
- Native Elixir DSPy signature parsing
- Smart routing system for native vs Python execution
- Pipeline orchestration with mixed execution support
- Snakepit integration for Python DSPy processes
- Multi-layer testing architecture (mock, protocol, integration)
- LLM adapter pattern with InstructorLite, Gemini, and HTTP support
- Native template engine using EEx
- Comprehensive Dialyzer type checking
- Performance monitoring and metrics collection

### Changed
- Complete rewrite from V1 architecture
- Moved from direct Python calls to Snakepit pooling
- Implemented protocol-agnostic bridge design

### Deprecated
- Legacy V1 bridge implementation

### Removed
- Old direct Python integration approach

### Fixed
- Compilation warnings and type issues
- Test infrastructure improvements
- Worker lifecycle management

### Security
- Improved process isolation
- Better error handling and recovery

## [0.1.0] - 2025-01-XX

### Added
- Initial release of DSPex V2
- Core architecture and foundation modules
- Basic DSPy signature compatibility
- Python bridge via Snakepit
- Native Elixir implementations for core operations
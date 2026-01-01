# Changelog

All notable changes to DSPex will be documented in this file.

## [0.3.0] - 2026-01-02

### Changed
- Simplified to minimal wrapper architecture using SnakeBridge Universal FFI
- Single `DSPex` module with direct pass-through to SnakeBridge
- Updated documentation with comprehensive README

### Added
- Timeout helper functions: `with_timeout/2`, `timeout_profile/1`, `timeout_ms/1`
- 13 comprehensive examples covering all major use cases
- Assets configuration for hex.pm package
- Badges and improved documentation

## [0.2.1] - 2025-10-25

### Changed
- Updated to Snakepit 0.6.3
- SnakeBridge integration improvements

## [0.2.0] - 2025-10-08

### Added
- New professional SVG logo
- CI workflow with Python setup
- Python setup.py for dspex_adapters package
- Python requirements.txt for dependencies
- ALTAR integration roadmaps and v1.0 vision documentation

### Changed
- Migrated DSPy integration architecture
- Fixed compiler warnings in pipeline.ex

### Fixed
- Example result extraction
- Snakepit orphan process handling

## [0.1.1] - 2025-07-24

### Added
- Bidirectional tool calls support
- Example scripts with proper shutdown handling
- Performance test suite (excluded from default runs)

### Changed
- Removed DSPex state management layer in favor of Snakepit SessionStore
- Removed legacy JSON bridges
- Migrated to Snakepit 0.4

### Removed
- Obsolete lib modules and tests
- Legacy state management code

## [0.1.0] - 2025-07-13

Initial experimental release with direct Snakepit integration.

### Added
- Basic DSPy bridge via Snakepit gRPC
- Session management
- Pool-based Python process management
- Initial examples and test infrastructure

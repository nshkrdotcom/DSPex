# Stage 1: Foundation Implementation - Prompt Strategy Summary

## Overview

Stage 1 implements the foundational components for DSPy-Ash integration. Each prompt is designed to be completely self-contained with ALL necessary context embedded directly in the prompt file.

## 10 Detailed Prompts for Stage 1

### Prompt 1: Core Signature System Implementation
**File**: `prompts/stage1_01_signature_system.md`
**Focus**: Implement the core signature behavior, DSL, and compile-time processing
**Key Components**:
- `DSPex.Signature` behavior module
- `DSPex.Signature.DSL` macro system  
- `DSPex.Signature.Compiler` compile-time processing
- `DSPex.Signature.TypeParser` type system
- `DSPex.Signature.Validator` runtime validation

**Required Context**:
- Complete signature syntax from 1100-1102 docs
- Elixir macro system documentation
- Type parsing and validation patterns
- ExDantic basic integration patterns
- Compile-time code generation examples

### Prompt 2: ExDantic Integration and Validation
**File**: `prompts/stage1_02_exdantic_integration.md`
**Focus**: Deep integration with ExDantic for Pydantic-like validation
**Key Components**:
- ExDantic schema generation from signatures
- Runtime validation with type coercion
- Error formatting and handling
- Schema caching and performance optimization

**Required Context**:
- Complete ExDantic documentation and examples
- ExDantic.Runtime schema creation
- ExDantic.TypeAdapter usage patterns
- Validation configuration and error handling
- Performance optimization techniques

### Prompt 3: Python Bridge Foundation
**File**: `prompts/stage1_03_python_bridge.md`
**Focus**: Implement port-based communication with Python DSPy
**Key Components**:
- `DSPex.PythonBridge.Bridge` GenServer
- `DSPex.PythonBridge.Protocol` wire protocol
- Port management and supervision
- Request/response handling with timeouts

**Required Context**:
- Erlang port documentation and best practices
- GenServer patterns for external process management
- JSON protocol design and error handling
- Process supervision and recovery strategies
- Timeout and error recovery patterns

### Prompt 4: Adapter Pattern Implementation
**File**: `prompts/stage1_04_adapter_pattern.md`
**Focus**: Create pluggable adapter system for multiple DSPy backends
**Key Components**:
- `DSPex.Adapters.Adapter` behavior definition
- `DSPex.Adapters.PythonPort` implementation
- `DSPex.Adapters.Native` stub for future
- Configuration and registry system

**Required Context**:
- Elixir behavior patterns and best practices
- Plugin architecture design patterns
- Configuration management approaches
- Error handling and fallback strategies
- Testing patterns for pluggable systems

### Prompt 5: Basic Ash Resources
**File**: `prompts/stage1_05_ash_resources.md`
**Focus**: Create foundational Ash resources for ML operations
**Key Components**:
- `DSPex.ML.Domain` domain definition
- `DSPex.ML.Signature` resource
- `DSPex.ML.Program` resource
- `DSPex.ML.Execution` resource (basic)

**Required Context**:
- Complete Ash resource documentation
- Ash domain patterns and best practices
- Resource relationships and actions
- Data layer configuration
- Code interface generation

### Prompt 6: Python Bridge Script
**File**: `prompts/stage1_06_python_script.md`
**Focus**: Implement the Python side of the bridge communication
**Key Components**:
- DSPy bridge script with command handlers
- Packet protocol implementation
- DSPy program creation and execution
- Error handling and logging

**Required Context**:
- Python DSPy documentation and examples
- Python struct/json protocol handling
- DSPy signature creation patterns
- DSPy program execution examples
- Python error handling best practices

### Prompt 7: Application and Supervision Setup
**File**: `prompts/stage1_07_application_setup.md`
**Focus**: Set up the complete application structure and supervision
**Key Components**:
- `DSPex.Application` with proper supervision
- Configuration management
- Database setup and migrations
- Development/test environment setup

**Required Context**:
- Elixir application structure best practices
- Supervision tree design patterns
- Configuration management approaches
- Database migration patterns
- Development environment setup

### Prompt 8: Basic Testing Framework
**File**: `prompts/stage1_08_testing_framework.md`
**Focus**: Comprehensive testing setup for all Stage 1 components
**Key Components**:
- Signature compilation tests
- Python bridge communication tests
- Ash resource operation tests
- Integration test patterns

**Required Context**:
- ExUnit testing patterns and best practices
- Testing external processes and ports
- Ash resource testing approaches
- Mock and fixture patterns
- Integration testing strategies

### Prompt 9: Error Handling and Logging
**File**: `prompts/stage1_09_error_handling.md`
**Focus**: Robust error handling throughout the system
**Key Components**:
- Comprehensive error types and formatting
- Logging strategy and configuration
- Error recovery and graceful degradation
- User-friendly error messages

**Required Context**:
- Elixir error handling patterns
- Logger configuration and usage
- Error type design principles
- Recovery strategy patterns
- User experience for error states

### Prompt 10: Integration and Documentation
**File**: `prompts/stage1_10_integration.md`
**Focus**: Final integration, documentation, and Stage 1 completion
**Key Components**:
- End-to-end integration testing
- Performance benchmarking
- Documentation generation
- Stage 1 completion verification

**Required Context**:
- Integration testing strategies
- Performance measurement approaches
- Documentation generation tools
- Completion criteria and verification
- Handoff to Stage 2 preparation

## Prompt Design Principles

### 1. Complete Self-Containment
Each prompt contains ALL necessary context:
- Relevant documentation sections copied in full
- Code examples and patterns
- Configuration and setup instructions
- Testing approaches and examples

### 2. Incremental Implementation
Each prompt builds on the previous ones:
- Clear dependencies and prerequisites
- Integration points with previous components
- Verification steps to ensure correctness

### 3. Production Quality
All code should be production-ready:
- Comprehensive error handling
- Proper logging and monitoring
- Performance considerations
- Security best practices

### 4. Thorough Testing
Each component includes:
- Unit tests for individual functions
- Integration tests for component interaction
- Property-based testing where appropriate
- Performance and load testing

## Context Sources for Each Prompt

### Documentation Sources:
- **Root docs**: All .md files we created (STAGE_1_*, DSPy_ASH_MVP_*, etc.)
- **AshDocs**: Complete Ash framework documentation
- **ExDantic docs**: All ../../exdantic/**.md files and examples
- **Elixir docs**: Relevant language and OTP documentation
- **DSPy docs**: Python DSPy examples and patterns

### Code Sources:
- **ExDantic examples**: All example files and test cases
- **Ash examples**: Resource definitions and patterns
- **Elixir patterns**: Macro systems, GenServers, supervision
- **Python examples**: DSPy usage and integration patterns

## Implementation Strategy

### Phase 1: Research and Context Gathering
- Deep dive into all documentation sources
- Extract relevant code examples and patterns
- Organize context by prompt requirements
- Identify integration points and dependencies

### Phase 2: Prompt Construction
- Start with Prompt 1 (most fundamental)
- Include complete context for self-contained execution
- Add comprehensive examples and patterns
- Include testing and verification steps

### Phase 3: Validation and Refinement
- Verify all context is complete and accurate
- Ensure prompts can be executed independently
- Test integration between components
- Refine based on implementation results

This approach ensures each prompt is a complete implementation guide that can be executed without external research or context gathering.
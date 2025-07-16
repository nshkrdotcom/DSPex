# Requirements Document

## Introduction

This spec addresses the critical gap between DSPex's rich Elixir signature DSL and the Python bridge's hardcoded "question → answer" pattern. The current implementation discards signature metadata, preventing proper field mapping and limiting the system to basic Q&A operations.

The goal is to create a cohesive signature system that preserves field names and types across the Elixir-Python boundary, enabling dynamic signature execution with proper input/output mapping.

## Requirements

### Requirement 1

**User Story:** As a developer using DSPex, I want to define signatures with custom field names (like `text → sentiment`) and have them work correctly in the Python bridge, so that I can build applications beyond simple question-answer patterns.

#### Acceptance Criteria

1. WHEN I define a signature with custom fields THEN the Python bridge SHALL create a dynamic DSPy signature class with those exact field names
2. WHEN I execute a program with custom inputs THEN the Python bridge SHALL map inputs by field name rather than defaulting to "question"
3. WHEN the program returns results THEN the outputs SHALL be mapped by field name rather than defaulting to "answer"

### Requirement 2

**User Story:** As a developer, I want the signature system to maintain backward compatibility with existing Q&A patterns, so that current code continues working during migration.

#### Acceptance Criteria

1. WHEN no signature is specified THEN the system SHALL default to question → answer format
2. WHEN signature conversion fails THEN the system SHALL fall back gracefully to Q&A format with appropriate logging
3. WHEN using legacy Q&A format THEN all existing functionality SHALL continue working unchanged

### Requirement 3

**User Story:** As a developer, I want signature conversion to be performant and reliable, so that the dynamic system doesn't impact application performance.

#### Acceptance Criteria

1. WHEN the same signature is used multiple times THEN the Python bridge SHALL cache the generated signature class
2. WHEN signature conversion occurs THEN the overhead SHALL be less than 5ms per conversion
3. WHEN signature validation fails THEN the system SHALL provide clear error messages indicating the specific validation failure
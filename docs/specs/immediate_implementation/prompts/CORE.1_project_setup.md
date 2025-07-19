# Task CORE.1: Project Setup and Configuration

## Task Overview
**ID**: CORE.1  
**Component**: Core Infrastructure  
**Priority**: P0 (Critical)  
**Estimated Time**: 2 hours  
**Dependencies**: None  
**Status**: Not Started

## Objective
Validate and complete the Mix project structure, ensure all configuration files are properly set up, add necessary dependencies, and verify the project compiles without warnings or errors.

## Required Reading

### 1. Project Structure and Current State
- **File**: `/home/home/p/g/n/dspex/mix.exs`
  - Current dependencies and project configuration
  - Review lines 1-50 for project setup
  
- **File**: `/home/home/p/g/n/dspex/config/config.exs`
  - Base configuration file
  - Check existing configurations

### 2. Architecture Documentation
- **File**: `/home/home/p/g/n/dspex/CLAUDE.md`
  - Lines 145-155: Configuration section
  - Understand the expected configuration structure

### 3. Missing Configuration Files
The following files need to be created or validated:
- `/home/home/p/g/n/dspex/config/dev.exs`
- `/home/home/p/g/n/dspex/config/test.exs`
- `/home/home/p/g/n/dspex/config/runtime.exs`

## Implementation Steps

### Step 1: Validate mix.exs Dependencies
Add or verify the following dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:snakepit, "~> 0.1.0"},
    {:instructor_lite, "~> 0.1.0"},
    {:jason, "~> 1.4"},
    {:req, "~> 0.4.0"},
    {:telemetry, "~> 1.2"},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
    {:stream_data, "~> 0.6", only: [:dev, :test]}
  ]
end
```

### Step 2: Create Development Configuration
Create `/home/home/p/g/n/dspex/config/dev.exs`:

```elixir
import Config

# Development-specific configuration
config :dspex,
  router: [
    prefer_native: true,
    fallback_to_python: true,
    log_decisions: true
  ]

config :snakepit,
  python_path: System.get_env("PYTHON_PATH", "python3"),
  pool_size: 2,
  max_overflow: 2

# Configure logger for development
config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:request_id, :module]
```

### Step 3: Create Test Configuration
Create `/home/home/p/g/n/dspex/config/test.exs`:

```elixir
import Config

# Test-specific configuration
config :dspex,
  router: [
    prefer_native: true,
    fallback_to_python: false,
    log_decisions: false
  ]

config :snakepit,
  python_path: System.get_env("PYTHON_PATH", "python3"),
  pool_size: 1,
  max_overflow: 0

# Print only warnings and errors during test
config :logger, level: :warning
```

### Step 4: Create Runtime Configuration
Create `/home/home/p/g/n/dspex/config/runtime.exs`:

```elixir
import Config

# Runtime configuration for production
if config_env() == :prod do
  config :dspex,
    router: [
      prefer_native: true,
      fallback_to_python: true,
      log_decisions: false
    ]
  
  config :snakepit,
    python_path: System.get_env("PYTHON_PATH", "python3"),
    pool_size: System.get_env("SNAKEPIT_POOL_SIZE", "4") |> String.to_integer(),
    max_overflow: System.get_env("SNAKEPIT_MAX_OVERFLOW", "4") |> String.to_integer()
end
```

### Step 5: Set Up Dialyzer
Add dialyzer configuration to `mix.exs`:

```elixir
def project do
  [
    # ... existing configuration ...
    dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [:error_handling, :unknown]
    ]
  ]
end
```

### Step 6: Compile and Verify
Run the following commands:

```bash
# Get dependencies
mix deps.get

# Compile without warnings
mix compile --warnings-as-errors

# Run dialyzer (first run will be slow)
mix dialyzer

# Check code formatting
mix format --check-formatted

# Run credo
mix credo --strict
```

## Acceptance Criteria

- [ ] Mix project structure validated and correct
- [ ] All config files (dev.exs, test.exs, runtime.exs) created and properly configured
- [ ] All necessary dependencies added to mix.exs
- [ ] Project compiles without any warnings (`mix compile --warnings-as-errors` passes)
- [ ] Dialyzer configuration complete and `mix dialyzer` runs without errors
- [ ] Code formatting verified (`mix format --check-formatted` passes)
- [ ] Credo analysis passes (`mix credo --strict` shows no issues)

## Expected Deliverables

1. Updated `mix.exs` with all required dependencies and dialyzer configuration
2. Created `config/dev.exs` with development settings
3. Created `config/test.exs` with test settings
4. Created `config/runtime.exs` with runtime/production settings
5. Clean compilation output showing no warnings
6. Successful dialyzer run
7. All code quality checks passing

## Troubleshooting

### Common Issues:
1. **Dependency conflicts**: Check version constraints and use `mix deps.tree` to debug
2. **Compilation warnings**: Fix all warnings before proceeding
3. **Dialyzer PLT building**: First run takes time, be patient
4. **Missing environment variables**: Set PYTHON_PATH if needed

## Notes
- This is the foundation task - take time to get it right
- All subsequent tasks depend on clean project setup
- Ensure all tools (mix, dialyzer, credo) are properly configured
- Document any deviations from the standard setup
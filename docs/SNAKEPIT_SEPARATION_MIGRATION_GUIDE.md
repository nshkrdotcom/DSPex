# Snakepit Separation Migration Guide

## Overview

This guide provides step-by-step instructions for migrating from the current monolithic Snakepit to the separated two-package architecture:
- **Snakepit Core** (infrastructure only)
- **SnakepitGrpcBridge** (DSPy/gRPC domain logic)

The migration maintains backward compatibility for DSPex users while creating clean architectural boundaries for future development.

## Pre-Migration Checklist

### Environment Verification
```bash
# Verify current setup
cd /path/to/your/project
mix deps.get
mix compile
mix test

# Check Snakepit version
grep snakepit mix.exs
# Should show current development version

# Verify Python bridge functionality
mix run -e "IO.inspect(Snakepit.execute('ping', %{}))"
```

### Backup Strategy
```bash
# Create migration branch
git checkout -b snakepit-separation-migration
git add -A
git commit -m "Pre-migration snapshot"

# Backup current working state
cp -r . ../project-backup-$(date +%Y%m%d)
```

## Phase 1: Package Separation (Week 1)

### Step 1.1: Extract Snakepit Core

#### Remove Bridge-Specific Modules
```bash
# Navigate to snakepit directory
cd snakepit

# Move bridge modules to temporary location
mkdir -p ../temp_bridge_modules
mv lib/snakepit/bridge ../temp_bridge_modules/
mv lib/snakepit/variables.ex ../temp_bridge_modules/
mv priv/python ../temp_bridge_modules/
mv grpc ../temp_bridge_modules/

# Update lib/snakepit.ex to remove bridge references
```

#### Update Snakepit Core Files

**File**: `snakepit/lib/snakepit.ex`
```elixir
defmodule Snakepit do
  @moduledoc """
  Snakepit - High-performance pooler and session manager.
  
  BREAKING CHANGE v0.4.0: Bridge functionality moved to separate packages.
  For DSPy integration, add {:snakepit_grpc_bridge, "~> 0.1"} to your deps.
  """

  # Remove all bridge-specific functions
  # Keep only: execute/3, execute_in_session/4, execute_stream/4, etc.
  
  # Add deprecation warnings for removed functions
  def discover_schema(_module_path, _opts \\ []) do
    raise """
    Snakepit.discover_schema/2 has been moved to SnakepitGrpcBridge.
    
    Add to your mix.exs:
        {:snakepit_grpc_bridge, "~> 0.1"}
    
    Update your code:
        Snakepit.discover_schema("dspy")
        # becomes
        SnakepitGrpcBridge.discover_schema("dspy")
    """
  end

  # Similar for other moved functions...
end
```

**File**: `snakepit/lib/snakepit/adapter.ex` (new file)
```elixir
defmodule Snakepit.Adapter do
  @moduledoc """
  Behavior for external process adapters.
  
  Bridge packages implement this to integrate with Snakepit Core.
  """

  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}

  @callback uses_grpc?() :: boolean()
  @callback supports_streaming?() :: boolean()

  @optional_callbacks [uses_grpc?: 0, supports_streaming?: 0]
end
```

#### Update mix.exs
```elixir
# snakepit/mix.exs
defmodule Snakepit.MixProject do
  use Mix.Project

  def project do
    [
      app: :snakepit,
      version: "0.4.0",  # BREAKING CHANGE
      elixir: "~> 1.14",
      description: "High-performance pooler and session manager",
      package: package(),
      deps: deps()
    ]
  end

  defp deps do
    [
      # Remove all bridge-specific dependencies
      # Keep only core OTP/testing dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "snakepit",
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/your-org/snakepit"}
    ]
  end
end
```

### Step 1.2: Create SnakepitGrpcBridge Package

#### Initialize New Package
```bash
# Create new package directory
mkdir -p ../snakepit_grpc_bridge
cd ../snakepit_grpc_bridge

# Initialize mix project
mix new . --app snakepit_grpc_bridge --module SnakepitGrpcBridge
```

#### Setup Package Structure
```bash
# Create directory structure
mkdir -p lib/snakepit_grpc_bridge/{dspy,variables,tools,grpc,session}
mkdir -p priv/python
mkdir -p test/{snakepit_grpc_bridge,integration,support}
```

#### Move Bridge Modules
```bash
# Move modules from temp location
mv ../temp_bridge_modules/bridge/* lib/snakepit_grpc_bridge/
mv ../temp_bridge_modules/variables.ex lib/snakepit_grpc_bridge/variables.ex
mv ../temp_bridge_modules/python/* priv/python/
mv ../temp_bridge_modules/grpc grpc/

# Clean up temp directory
rm -rf ../temp_bridge_modules
```

#### Create Bridge mix.exs
```elixir
# snakepit_grpc_bridge/mix.exs
defmodule SnakepitGrpcBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :snakepit_grpc_bridge,
      version: "0.1.0",
      elixir: "~> 1.14",
      description: "gRPC bridge for DSPy integration with Snakepit",
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      # Core dependency
      {:snakepit, "~> 0.4"},
      
      # gRPC and protobuf
      {:grpc, "~> 0.8"},
      {:protobuf, "~> 0.11"},
      
      # JSON handling
      {:jason, "~> 1.4"},
      
      # HTTP client for tools
      {:httpoison, "~> 2.0"},
      
      # Development and testing
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "snakepit_grpc_bridge",
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/your-org/snakepit-grpc-bridge"}
    ]
  end
end
```

### Step 1.3: Implement Adapter Pattern

#### Create Bridge Adapter
**File**: `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/adapter.ex`
```elixir
defmodule SnakepitGrpcBridge.Adapter do
  @behaviour Snakepit.Adapter
  
  @impl Snakepit.Adapter
  def execute(command, args, opts) do
    # Route commands to appropriate bridge modules
    case command do
      "call_dspy_bridge" -> 
        SnakepitGrpcBridge.DSPy.execute_command(args, opts)
      
      "discover_dspy_schema" -> 
        SnakepitGrpcBridge.DSPy.discover_schema(args["module_path"], opts)
      
      # Add all other command mappings...
      
      _ -> 
        {:error, {:unknown_command, command}}
    end
  end

  @impl Snakepit.Adapter
  def uses_grpc?, do: true

  @impl Snakepit.Adapter
  def supports_streaming?, do: true
end
```

#### Create Main Bridge Module
**File**: `snakepit_grpc_bridge/lib/snakepit_grpc_bridge.ex`
```elixir
defmodule SnakepitGrpcBridge do
  @moduledoc """
  gRPC bridge for DSPy integration with Snakepit Core.
  """

  @doc """
  Start bridge and configure Snakepit to use this adapter.
  """
  def start_bridge(opts \\ []) do
    # Configure Snakepit to use our adapter
    Application.put_env(:snakepit, :adapter_module, SnakepitGrpcBridge.Adapter)
    
    # Start bridge-specific services
    with {:ok, grpc_server} <- start_grpc_server(opts),
         {:ok, python_bridge} <- start_python_bridge(opts) do
      
      bridge_info = %{
        grpc_port: grpc_server.port,
        python_pid: python_bridge.pid,
        started_at: DateTime.utc_now()
      }
      
      {:ok, bridge_info}
    end
  end

  # Implement all public API functions from specification...
end
```

## Phase 2: Update DSPex Integration (Week 2)

### Step 2.1: Update DSPex Dependencies

#### Update mix.exs
```elixir
# dspex/mix.exs
defp deps do
  [
    # Replace snakepit with bridge
    # {:snakepit, path: "../snakepit"},  # Remove this
    {:snakepit_grpc_bridge, path: "../snakepit_grpc_bridge"},
    
    # Other dependencies remain the same...
  ]
end
```

#### Update Configuration
```elixir
# config/config.exs
config :snakepit,
  # Remove bridge-specific config
  adapter_module: SnakepitGrpcBridge.Adapter,
  pooling_enabled: true,
  pool_size: 4

# Add bridge-specific config
config :snakepit_grpc_bridge,
  python_executable: "python3",
  grpc_port: 0,
  enable_telemetry: true
```

### Step 2.2: Update DSPex.Bridge

#### Modify Bridge Calls
**File**: `lib/dspex/bridge.ex`
```elixir
defmodule DSPex.Bridge do
  # Update calls to use SnakepitGrpcBridge
  
  def call_dspy(module_path, function_name, positional_args, keyword_args, opts) do
    session_id = opts[:session_id] || ID.generate("session")
    
    # Use SnakepitGrpcBridge instead of direct Snakepit calls
    SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
      "class_path" => module_path,
      "method" => function_name,
      "args" => positional_args,
      "kwargs" => keyword_args
    })
  end

  def discover_schema(module_path, opts \\ []) do
    # Delegate to bridge
    SnakepitGrpcBridge.discover_schema(module_path, opts)
  end

  # Update all other functions similarly...
end
```

#### Update Variables Delegation
**File**: `lib/dspex/variables.ex`
```elixir
defmodule DSPex.Variables do
  @moduledoc """
  DEPRECATED: Use SnakepitGrpcBridge.Variables instead.
  """

  @deprecated "Use SnakepitGrpcBridge.Variables instead"
  defdelegate get(session_id, identifier, default \\ nil), to: SnakepitGrpcBridge.Variables

  @deprecated "Use SnakepitGrpcBridge.Variables instead"
  defdelegate set(session_id, identifier, value, opts \\ []), to: SnakepitGrpcBridge.Variables

  # Continue for all other functions...
end
```

### Step 2.3: Update Tests

#### Modify Test Setup
```elixir
# test/support/test_helpers.ex
defmodule DSPex.TestHelpers do
  def setup_bridge do
    # Start bridge for testing
    {:ok, bridge_info} = SnakepitGrpcBridge.start_bridge([
      python_executable: "python3",
      grpc_port: 0
    ])
    
    bridge_info
  end

  def cleanup_bridge do
    SnakepitGrpcBridge.stop_bridge()
  end
end
```

#### Update Test Files
```elixir
# test/dspex/bridge_test.exs
defmodule DSPex.BridgeTest do
  use ExUnit.Case
  
  setup_all do
    DSPex.TestHelpers.setup_bridge()
    on_exit(&DSPex.TestHelpers.cleanup_bridge/0)
    :ok
  end

  # Tests remain largely the same, but now use bridge
end
```

## Phase 3: Testing and Validation (Week 3)

### Step 3.1: Comprehensive Testing

#### Run Core Tests
```bash
# Test Snakepit Core
cd snakepit
mix deps.get
mix compile
mix test

# Should pass all infrastructure tests
# Should show deprecation warnings for removed functions
```

#### Run Bridge Tests
```bash
# Test SnakepitGrpcBridge
cd ../snakepit_grpc_bridge
mix deps.get
mix compile
mix test

# Should pass all bridge functionality tests
```

#### Run Integration Tests
```bash
# Test DSPex with new architecture
cd ../dspex
mix deps.get
mix compile
mix test

# Should pass all existing functionality tests
```

### Step 3.2: Performance Validation

#### Benchmark Script
```elixir
# scripts/benchmark_migration.exs
defmodule MigrationBenchmark do
  def run do
    # Start bridge
    {:ok, _} = SnakepitGrpcBridge.start_bridge()
    
    # Test basic operations
    benchmark_basic_operations()
    benchmark_dspy_operations()
    benchmark_variables_operations()
    
    # Cleanup
    SnakepitGrpcBridge.stop_bridge()
  end

  defp benchmark_basic_operations do
    {time, _result} = :timer.tc(fn ->
      for _i <- 1..100 do
        {:ok, _} = Snakepit.execute("ping", %{})
      end
    end)
    
    IO.puts("Basic operations: #{time / 1000}ms for 100 calls")
  end

  # Additional benchmarks...
end

MigrationBenchmark.run()
```

```bash
# Run benchmark
cd dspex
mix run scripts/benchmark_migration.exs

# Compare with pre-migration benchmarks
# Should be within 10% of original performance
```

### Step 3.3: Migration Validation

#### Validate Examples
```bash
# Test all example files
cd examples/dspy
mix run 00_dspy_mock_demo.exs
mix run 01_question_answering_pipeline.exs
# ... test all examples

# All should work without modification
```

#### Validate Documentation
```bash
# Generate documentation
cd ../snakepit_grpc_bridge
mix docs

cd ../snakepit
mix docs

# Verify documentation builds correctly
```

## Phase 4: Release and Deployment (Week 4)

### Step 4.1: Package Publishing

#### Prepare Snakepit Core Release
```bash
cd snakepit

# Update CHANGELOG.md
cat << EOF >> CHANGELOG.md
## [0.4.0] - $(date +%Y-%m-%d)

### BREAKING CHANGES
- Bridge functionality moved to separate snakepit_grpc_bridge package
- Removed DSPy integration, variables, and gRPC functionality
- Added Snakepit.Adapter behavior for bridge implementations

### Added
- Clean adapter pattern for external process integration
- Improved documentation for core functionality

### Migration
- Add {:snakepit_grpc_bridge, "~> 0.1"} for DSPy functionality
- See MIGRATION_GUIDE.md for detailed instructions
EOF

# Create git tag
git add -A
git commit -m "Release Snakepit Core 0.4.0 - Remove bridge functionality"
git tag v0.4.0

# Publish to Hex (if applicable)
mix hex.publish --yes
```

#### Prepare Bridge Package Release
```bash
cd ../snakepit_grpc_bridge

# Create CHANGELOG.md
cat << EOF > CHANGELOG.md
# Changelog

## [0.1.0] - $(date +%Y-%m-%d)

### Added
- Initial release of SnakepitGrpcBridge
- Full DSPy integration support
- Variables management system
- Bidirectional tool calling
- gRPC communication infrastructure
- Session management
- Schema discovery and caching

### Migration
- Extracted from Snakepit Core v0.3.x
- Maintains full backward compatibility for DSPex users
EOF

# Create git tag
git add -A
git commit -m "Release SnakepitGrpcBridge 0.1.0 - Initial release"
git tag v0.1.0

# Publish to Hex (if applicable)
mix hex.publish --yes
```

### Step 4.2: Update DSPex

#### Release DSPex Update
```bash
cd ../dspex

# Update version in mix.exs
# Update CHANGELOG.md
cat << EOF >> CHANGELOG.md
## [0.4.0] - $(date +%Y-%m-%d)

### Changed
- Updated to use SnakepitGrpcBridge instead of Snakepit directly
- Improved architectural separation
- Updated dependencies

### Migration
- No user-facing changes - internal architecture improvement
- Automatic dependency resolution handles bridge package
EOF

# Update version and dependencies
# Commit and tag
git add -A
git commit -m "Release DSPex 0.4.0 - Use SnakepitGrpcBridge"
git tag v0.4.0
```

## Migration Troubleshooting

### Common Issues

#### 1. Missing Adapter Configuration
**Error**: `Snakepit: adapter_module must be configured`

**Solution**:
```elixir
# Add to config/config.exs
config :snakepit,
  adapter_module: SnakepitGrpcBridge.Adapter
```

#### 2. Python Bridge Startup Failures
**Error**: `Python bridge failed to start`

**Solution**:
```bash
# Check Python dependencies
cd snakepit_grpc_bridge/priv/python
pip install -r requirements.txt

# Test Python bridge manually
python bridge_server.py --test
```

#### 3. gRPC Port Conflicts
**Error**: `gRPC server failed to bind to port`

**Solution**:
```elixir
# Use dynamic port allocation
config :snakepit_grpc_bridge,
  grpc_port: 0  # 0 = dynamic port
```

#### 4. Missing Function Errors
**Error**: `function Snakepit.discover_schema/2 is undefined`

**Solution**:
```elixir
# Update function calls
# Old:
Snakepit.discover_schema("dspy")

# New:
SnakepitGrpcBridge.discover_schema("dspy")
```

### Rollback Procedure

If migration issues occur:

```bash
# 1. Switch to pre-migration branch
git checkout main  # or your pre-migration branch

# 2. Restore dependencies
mix deps.get
mix compile

# 3. Verify functionality
mix test

# 4. If needed, restore from backup
cp -r ../project-backup-YYYYMMDD/* .
```

## Post-Migration Validation

### Verification Checklist

- [ ] All existing DSPex functionality works
- [ ] Performance is within 10% of pre-migration
- [ ] All examples run successfully
- [ ] Documentation builds correctly
- [ ] Tests pass in all packages
- [ ] No deprecation warnings in user code
- [ ] Bridge starts and stops cleanly
- [ ] Python integration works correctly

### Success Criteria

#### Technical Validation
- [ ] Snakepit Core is < 1000 lines of code
- [ ] Clean dependency graph: Bridge → Snakepit → OTP
- [ ] Independent version management working
- [ ] Adapter pattern enables future bridges

#### User Experience
- [ ] Zero breaking changes for DSPex users
- [ ] Clear migration path for advanced users
- [ ] Improved documentation
- [ ] Faster development iteration

#### Architecture Quality
- [ ] Single Responsibility Principle maintained
- [ ] Clean module boundaries
- [ ] Testable components
- [ ] Extensible design

## Future Evolution

After successful migration:

### Planned Enhancements
1. **Additional Bridge Types**: JSON-RPC, Apache Arrow
2. **Enhanced Monitoring**: Detailed telemetry and metrics
3. **Performance Optimizations**: Connection pooling, caching
4. **Developer Tools**: Better debugging, profiling

### Community Development
1. **Documentation**: Comprehensive guides and tutorials
2. **Examples**: More complex use cases and patterns
3. **Third-Party Bridges**: Community bridge development
4. **Integration**: Framework-specific adapters

The migration creates a solid foundation for long-term architectural evolution while maintaining compatibility and performance.
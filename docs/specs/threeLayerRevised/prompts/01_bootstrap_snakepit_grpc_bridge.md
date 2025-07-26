# Prompt: Bootstrap SnakepitGRPCBridge Package

## Context

You are implementing the **Light Snakepit + Heavy Bridge** architecture as described in the three-layer architecture documentation. This prompt covers **Phase 1, Days 1-2** of the implementation plan.

## Required Reading

Before starting, read these documents in order:
1. `docs/specs/threeLayerRevised/01_LIGHT_SNAKEPIT_HEAVY_BRIDGE_ARCHITECTURE.md` - Overall architecture
2. `docs/specs/threeLayerRevised/03_SNAKEPIT_GRPC_BRIDGE_PLATFORM_SPECIFICATION.md` - Platform specification
3. `docs/specs/threeLayerRevised/07_DETAILED_IN_PLACE_IMPLEMENTATION_PLAN.md` - Implementation plan (Days 1-2)

## Current State Analysis

Examine the current codebase structure:
- `./lib/` (DSPex current implementation) 
- `./snakepit/lib/` (Current Snakepit implementation)
- `./snakepit/priv/python/` (Current Python code in Snakepit)

Identify:
1. All Python code that needs to be moved to the bridge
2. All ML-related Elixir code that should be in the bridge
3. Current variable, tool, and DSPy implementations

## Objective

Create the `snakepit_grpc_bridge` package with:
1. Complete directory structure for ML platform
2. Proper OTP application setup
3. All Python code moved and reorganized
4. Basic Snakepit adapter implementation
5. Foundation for clean API modules

## Implementation Tasks

### Task 1: Create Package Structure

Create `snakepit_grpc_bridge/` with this exact structure:

```
snakepit_grpc_bridge/
├── mix.exs
├── lib/
│   └── snakepit_grpc_bridge/
│       ├── application.ex
│       ├── adapter.ex
│       ├── api/
│       │   ├── variables.ex
│       │   ├── tools.ex
│       │   ├── dspy.ex
│       │   └── sessions.ex
│       ├── variables/
│       │   ├── manager.ex
│       │   ├── types.ex
│       │   ├── storage.ex
│       │   ├── registry.ex
│       │   └── ml_types/
│       │       ├── tensor.ex
│       │       ├── embedding.ex
│       │       └── model.ex
│       ├── tools/
│       │   ├── registry.ex
│       │   ├── executor.ex
│       │   ├── bridge.ex
│       │   ├── serialization.ex
│       │   └── validation.ex
│       ├── dspy/
│       │   ├── integration.ex
│       │   ├── workflows.ex
│       │   ├── enhanced.ex
│       │   ├── schema.ex
│       │   ├── optimization.ex
│       │   └── codegen.ex
│       ├── grpc/
│       │   ├── client.ex
│       │   ├── server.ex
│       │   └── protocols.ex
│       ├── python/
│       │   ├── bridge.ex
│       │   ├── process.ex
│       │   └── communication.ex
│       └── telemetry.ex
├── priv/
│   ├── proto/
│   │   └── ml_bridge.proto
│   └── python/
│       └── snakepit_bridge/
│           ├── __init__.py
│           ├── core/
│           │   ├── __init__.py
│           │   ├── bridge.py
│           │   ├── grpc_server.py
│           │   └── session.py
│           ├── variables/
│           │   ├── __init__.py
│           │   ├── manager.py
│           │   ├── types.py
│           │   └── serialization.py
│           ├── tools/
│           │   ├── __init__.py
│           │   ├── registry.py
│           │   ├── executor.py
│           │   └── bridge.py
│           └── dspy/
│               ├── __init__.py
│               ├── integration.py
│               ├── enhanced.py
│               └── adapters.py
├── test/
│   ├── api/
│   ├── variables/
│   ├── tools/
│   ├── dspy/
│   └── integration/
└── config/
    └── config.exs
```

### Task 2: Configure mix.exs

Create `snakepit_grpc_bridge/mix.exs`:

```elixir
defmodule SnakepitGRPCBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :snakepit_grpc_bridge,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: "Complete ML execution platform built on Snakepit infrastructure",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SnakepitGRPCBridge.Application, []}
    ]
  end

  defp deps do
    [
      {:snakepit, path: "../snakepit"},
      {:grpc, "~> 0.7"},
      {:protobuf, "~> 0.11"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end
end
```

### Task 3: Move All Python Code

1. **Move Python from DSPex**: Copy all Python code from `./priv/python/` to `snakepit_grpc_bridge/priv/python/snakepit_bridge/`

2. **Move Python from Snakepit**: Copy all Python code from `./snakepit/priv/python/` to `snakepit_grpc_bridge/priv/python/snakepit_bridge/`

3. **Reorganize Python Structure**: Organize the moved Python code into the appropriate subdirectories (core/, variables/, tools/, dspy/)

### Task 4: Create OTP Application

Create `lib/snakepit_grpc_bridge/application.ex`:

```elixir
defmodule SnakepitGRPCBridge.Application do
  @moduledoc """
  OTP Application for the SnakepitGRPCBridge ML platform.
  """
  
  use Application
  require Logger

  def start(_type, _args) do
    Logger.info("Starting SnakepitGRPCBridge ML platform")
    
    children = [
      {SnakepitGRPCBridge.Variables.Manager, []},
      {SnakepitGRPCBridge.Tools.Registry, []},
      {SnakepitGRPCBridge.DSPy.Integration, []},
      {SnakepitGRPCBridge.Python.Bridge, []},
      {SnakepitGRPCBridge.GRPC.Server, []}
    ]
    
    opts = [strategy: :one_for_one, name: SnakepitGRPCBridge.Supervisor]
    
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("SnakepitGRPCBridge ML platform started successfully")
        {:ok, pid}
      
      {:error, reason} ->
        Logger.error("Failed to start SnakepitGRPCBridge ML platform: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def stop(_state) do
    Logger.info("Stopping SnakepitGRPCBridge ML platform")
    :ok
  end
end
```

### Task 5: Create Basic Snakepit Adapter

Create `lib/snakepit_grpc_bridge/adapter.ex`:

```elixir
defmodule SnakepitGRPCBridge.Adapter do
  @moduledoc """
  Snakepit adapter that routes ML commands to platform modules.
  
  This is the integration point between Snakepit infrastructure and
  the ML platform capabilities.
  """
  
  @behaviour Snakepit.Adapter
  
  require Logger

  @impl Snakepit.Adapter
  def execute(command, args, opts) do
    start_time = System.monotonic_time(:microsecond)
    session_id = opts[:session_id]
    worker_pid = opts[:worker_pid]

    Logger.debug("Executing ML command", command: command, session_id: session_id)

    # Route command to appropriate ML platform module
    result = route_command(command, args, opts)
    
    # Collect execution telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_platform_telemetry(command, args, result, execution_time, session_id, worker_pid)
    
    result
  end

  @impl Snakepit.Adapter
  def execute_stream(command, args, callback_fn, opts) do
    session_id = opts[:session_id]
    
    Logger.debug("Executing streaming ML command", command: command, session_id: session_id)
    
    case command do
      "streaming_inference" -> 
        # Placeholder - will be implemented in later phases
        {:error, :not_implemented_yet}
      
      "batch_processing" -> 
        # Placeholder - will be implemented in later phases
        {:error, :not_implemented_yet}
      
      _ -> 
        {:error, {:streaming_not_supported, command}}
    end
  end

  @impl Snakepit.Adapter
  def init(config) do
    Logger.info("Initializing SnakepitGRPCBridge ML platform adapter")
    
    # Platform initialization - will be expanded in later phases
    adapter_state = %{
      initialized_at: DateTime.utc_now(),
      config: config,
      telemetry_collector: :ok  # Placeholder for telemetry
    }
    
    Logger.info("SnakepitGRPCBridge ML platform adapter initialized successfully")
    {:ok, adapter_state}
  end

  @impl Snakepit.Adapter
  def terminate(_reason, adapter_state) do
    Logger.info("Terminating SnakepitGRPCBridge ML platform adapter")
    
    # Cleanup - will be expanded in later phases
    Logger.info("SnakepitGRPCBridge ML platform adapter terminated successfully")
    :ok
  end

  @impl Snakepit.Adapter
  def start_worker(_adapter_state, worker_id) do
    # This callback will be implemented in a later phase to start our
    # Python.Process GenServer, which manages the Port to the Python OS process.
    # For now, we return a placeholder.
    Logger.debug("Adapter instructed to start ML worker", worker_id: worker_id)
    {:error, :not_implemented_yet}
  end

  # Private implementation functions
  
  defp route_command(command, args, opts) do
    case command do
      # Variables operations - will route to API modules once implemented
      "get_variable" -> 
        {:error, :not_implemented_yet}
      
      "set_variable" -> 
        {:error, :not_implemented_yet}
      
      "create_variable" -> 
        {:error, :not_implemented_yet}
      
      "list_variables" -> 
        {:error, :not_implemented_yet}
      
      # Tool operations - will route to API modules once implemented
      "register_elixir_tool" -> 
        {:error, :not_implemented_yet}
      
      "call_elixir_tool" -> 
        {:error, :not_implemented_yet}
      
      "list_elixir_tools" -> 
        {:error, :not_implemented_yet}
      
      # DSPy operations - will route to API modules once implemented
      "call_dspy" -> 
        {:error, :not_implemented_yet}
      
      "enhanced_predict" -> 
        {:error, :not_implemented_yet}
      
      "enhanced_chain_of_thought" -> 
        {:error, :not_implemented_yet}
      
      "discover_dspy_schema" -> 
        {:error, :not_implemented_yet}
      
      # Session operations - will route to API modules once implemented
      "initialize_session" -> 
        {:error, :not_implemented_yet}
      
      "cleanup_session" -> 
        {:error, :not_implemented_yet}
      
      "get_session_info" -> 
        {:error, :not_implemented_yet}
      
      # Unknown command
      _ -> 
        Logger.warning("Unknown ML command received: #{command}", command: command, session_id: opts[:session_id])
        {:error, {:unknown_command, command}}
    end
  end

  defp collect_platform_telemetry(command, args, result, execution_time, session_id, worker_pid) do
    telemetry_data = %{
      command: command,
      args_complexity: analyze_args_complexity(args),
      result_success: match?({:ok, _}, result),
      execution_time_microseconds: execution_time,
      session_id: session_id,
      worker_pid: worker_pid,
      timestamp: DateTime.utc_now(),
      platform: :ml_platform,
      command_category: categorize_ml_command(command)
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :adapter, :execution], telemetry_data)
  end

  defp analyze_args_complexity(args) when is_map(args) do
    %{
      parameter_count: map_size(args),
      total_data_size: :erlang.external_size(args)
    }
  end
  defp analyze_args_complexity(_args), do: %{complexity: :unknown}

  defp categorize_ml_command(command) do
    cond do
      String.contains?(command, "dspy") -> :dspy_operation
      String.contains?(command, "variable") -> :variable_operation
      String.contains?(command, "tool") -> :tool_operation
      String.contains?(command, "session") -> :session_operation
      true -> :unknown_operation
    end
  end
end
```

### Task 6: Create Placeholder API Modules

Create placeholder API modules that will be implemented in later phases:

**Variables API (`lib/snakepit_grpc_bridge/api/variables.ex`)**:
```elixir
defmodule SnakepitGRPCBridge.API.Variables do
  @moduledoc """
  Clean API for variable management operations.
  
  This module provides the primary interface that DSPex and other consumers use
  for variable operations.
  """

  # Placeholder implementations - will be completed in Phase 1, Day 3
  def create(session_id, name, type, value, opts \\ []) do
    {:error, :not_implemented_yet}
  end

  def get(session_id, identifier, default \\ nil) do
    {:error, :not_implemented_yet}
  end

  def set(session_id, identifier, value, opts \\ []) do
    {:error, :not_implemented_yet}
  end

  def list(session_id) do
    {:error, :not_implemented_yet}
  end

  def delete(session_id, identifier) do
    {:error, :not_implemented_yet}
  end
end
```

Create similar placeholder files for:
- `lib/snakepit_grpc_bridge/api/tools.ex`
- `lib/snakepit_grpc_bridge/api/dspy.ex`
- `lib/snakepit_grpc_bridge/api/sessions.ex`

### Task 7: Create Configuration

Create `config/config.exs`:

```elixir
import Config

config :snakepit_grpc_bridge,
  # Python configuration
  python_executable: "python3",
  python_bridge_path: :auto_detect,
  python_timeout: 60_000,
  
  # gRPC configuration  
  grpc_port: 0,
  grpc_timeout: 30_000,
  grpc_keepalive: true,
  
  # Variable system configuration
  variables: %{
    storage_backend: :ets,
    serialization_format: :erlang_binary,
    cache_ttl: 3600,
    max_variable_size: 100_000_000  # 100MB
  },
  
  # Tool system configuration
  tools: %{
    max_execution_time: 30_000,
    validation_enabled: true,
    serialization_format: :json
  },
  
  # DSPy configuration
  dspy: %{
    schema_cache_ttl: 3600,
    optimization_enabled: true,
    enhanced_features_enabled: true
  },
  
  # Performance optimization
  telemetry_enabled: true,
  telemetry_buffer_size: 1000

# Configure Snakepit to use this adapter
config :snakepit,
  adapter_module: SnakepitGRPCBridge.Adapter

# Environment-specific configuration
import_config "#{config_env()}.exs"
```

### Task 8: Basic Testing Setup

Create `test/test_helper.exs`:
```elixir
ExUnit.start()
```

Create `test/snakepit_grpc_bridge/adapter_test.exs`:
```elixir
defmodule SnakepitGRPCBridge.AdapterTest do
  use ExUnit.Case
  
  alias SnakepitGRPCBridge.Adapter

  test "implements Snakepit.Adapter behavior" do
    assert function_exported?(Adapter, :execute, 3)
    assert function_exported?(Adapter, :init, 1)
  end

  test "initializes successfully" do
    assert {:ok, state} = Adapter.init([])
    assert %{initialized_at: %DateTime{}} = state
  end

  test "handles unknown commands" do
    {:ok, state} = Adapter.init([])
    
    assert {:error, {:unknown_command, "unknown_command"}} = 
      Adapter.execute("unknown_command", %{}, [])
  end
end
```

## Validation

After completing this phase, verify:

1. ✅ `snakepit_grpc_bridge` package structure created
2. ✅ All Python code moved from DSPex and Snakepit
3. ✅ OTP application starts successfully
4. ✅ Snakepit adapter implements required behavior
5. ✅ Basic tests pass
6. ✅ Package compiles without errors

## Next Steps

This bootstrap phase creates the foundation. The next prompt will implement the core platform infrastructure (Variables system, Tools system, telemetry, etc.).

## Files Created

- `snakepit_grpc_bridge/mix.exs`
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/application.ex`
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/adapter.ex`
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/variables.ex` (placeholder)
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/tools.ex` (placeholder)
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/dspy.ex` (placeholder)
- `snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/sessions.ex` (placeholder)
- `snakepit_grpc_bridge/config/config.exs`
- `snakepit_grpc_bridge/test/test_helper.exs`
- `snakepit_grpc_bridge/test/snakepit_grpc_bridge/adapter_test.exs`
- Moved Python code in organized structure

This foundation enables the subsequent implementation phases to build the complete ML platform.
# Detailed In-Place Implementation Plan

## Overview

This plan implements the **Light Snakepit + Heavy Bridge** architecture by building in place without legacy support. We'll systematically transform the existing codebase into the clean three-layer architecture.

**Strategy**: Ruthless refactoring with clear boundaries and aggressive cleanup.

## Phase 1: Purify Snakepit & Bootstrap Bridge (Week 1)

### Day 1: Audit Snakepit Domain Logic
**Objective:** Identify all ML/DSPy/gRPC domain logic within the `snakepit` application.

**Morning: Systematic Codebase Audit**
```bash
# Audit all Elixir files for domain logic
find ./snakepit/lib -name "*.ex" -exec grep -l "dspy\|ml\|variable\|tool" {} \;

# Audit all Python files for ML/DSPy code
find ./snakepit/priv/python -name "*.py" -exec head -20 {} \; | grep -i "dspy\|ml\|torch\|tensor"

# Create kill list manifest
echo "SNAKEPIT PURIFICATION KILL LIST" > snakepit_purification_manifest.md
```

**Domain Logic Identification Process:**
1. **Python Files to Move/Delete:**
   - Any files containing DSPy imports or logic
   - ML model handling, tensor operations
   - Variable/session management specific to ML
   - Tool execution logic

2. **Elixir Modules to Review:**
   - Look for hardcoded Python script paths
   - Domain-specific command routing
   - ML-aware session management
   - gRPC service definitions tied to ML

**Afternoon: Document Current Architecture**
```bash
# Document current adapter implementation
find ./snakepit -name "*adapter*" -o -name "*bridge*" | xargs cat > current_adapter_analysis.txt

# Document current pool assumptions
grep -r "python\|dspy\|ml" ./snakepit/lib/snakepit/pool/ > pool_contamination_check.txt
```

### Day 2: Execute Snakepit Purification
**Objective:** Execute the removal of all domain logic from Snakepit.

**Morning: Delete Domain-Specific Files**
```bash
# Based on Day 1 audit, delete identified files
# Example (actual files depend on audit results):
rm -rf ./snakepit/priv/python/dspy_integration.py
rm -rf ./snakepit/priv/python/session_context.py
rm -rf ./snakepit/priv/python/ml_models/
rm -rf ./snakepit/priv/python/variables/

# Remove any domain-specific configuration
grep -v "dspy\|ml\|variable" ./snakepit/config/config.exs > temp_config.exs
mv temp_config.exs ./snakepit/config/config.exs

# Remove all gRPC-related modules and dependencies from snakepit
# The choice of communication protocol belongs to the adapter's implementation in the platform layer
rm -rf ./snakepit/lib/snakepit/grpc/
rm -rf ./snakepit/priv/proto/
grep -v "grpc" ./snakepit/mix.exs > temp_mix.exs
mv temp_mix.exs ./snakepit/mix.exs
```

**Afternoon: Refactor Contaminated Infrastructure**
```bash
# Clean up any Pool.ex contamination found on Day 1
# Ensure Adapter behavior is the ONLY contract
# Remove hardcoded assumptions about worker types

# Example refactoring (based on audit findings):
# Remove any hardcoded Python paths
# Remove ML-specific timeout values
# Remove domain-specific error handling
```

### Day 3: Prove Snakepit Generality
**Objective:** Confirm `snakepit` is completely domain-agnostic.

**Morning: Create MockAdapter Test**
```elixir
# test/support/mock_adapter.ex
defmodule MockAdapter do
  @behaviour Snakepit.Adapter

  @impl Snakepit.Adapter
  def start_worker(_adapter_state, worker_id) do
    # Start a simple GenServer that echoes commands
    {:ok, spawn_link(fn -> mock_worker_loop(worker_id) end)}
  end

  @impl Snakepit.Adapter
  def execute(command, args, opts) do
    worker_pid = opts[:worker_pid]
    send(worker_pid, {:execute, command, args, self()})

    receive do
      {:result, result} -> {:ok, result}
    after
      5000 -> {:error, :timeout}
    end
  end

  defp mock_worker_loop(worker_id) do
    receive do
      {:execute, command, args, from} ->
        # Simple echo response proving infrastructure works
        result = %{
          echo: "Worker #{worker_id} executed #{command}",
          args: args,
          timestamp: DateTime.utc_now()
        }
        send(from, {:result, result})
        mock_worker_loop(worker_id)
    end
  end
end
```

**Afternoon: Test Infrastructure with MockAdapter**
```elixir
# test/infrastructure_purity_test.exs
defmodule InfrastructurePurityTest do
  use ExUnit.Case

  setup do
    # Configure Snakepit to use MockAdapter
    Application.put_env(:snakepit, :adapter_module, MockAdapter)
    :ok
  end

  test "pool works with non-ML adapter" do
    # Test basic execution
    assert {:ok, result} = Snakepit.execute("test_command", %{data: "test"})
    assert result.echo =~ "executed test_command"
  end

  test "session affinity works with generic adapter" do
    session_id = "test_session_123"

    # Multiple calls with same session should work
    assert {:ok, _} = Snakepit.execute_in_session(session_id, "init", %{})
    assert {:ok, _} = Snakepit.execute_in_session(session_id, "process", %{})
  end

  test "worker lifecycle works without domain logic" do
    # Test that worker supervision works
    stats = Snakepit.get_stats()
    assert stats.total_workers > 0
    assert stats.available_workers > 0
  end
end
```

### Day 4: Bootstrap SnakepitGRPCBridge Package
**Objective:** Create the new SnakepitGRPCBridge package and move domain logic.

**Morning: Create New Package Structure**
```bash
# Create the ML platform package
mkdir snakepit_grpc_bridge
cd snakepit_grpc_bridge
mix new . --app snakepit_grpc_bridge

# Create ML platform directory structure
mkdir -p lib/snakepit_grpc_bridge/{api,variables,tools,dspy,python}
mkdir -p priv/python/snakepit_bridge/{core,variables,tools,dspy}
mkdir -p test/{variables,tools,dspy,integration}
```

**Afternoon: Move Domain Logic to New Package**
```bash
# Move all previously identified Python code
mv ../snakepit/DELETED_FILES/* priv/python/snakepit_bridge/ 2>/dev/null || true

# Move any domain-specific Elixir code identified in audit
# (Most will be newly written, but some might exist)

# Set up basic adapter stub that will integrate with purified Snakepit
```
```elixir
# lib/snakepit_grpc_bridge/adapter.ex
defmodule SnakepitGRPCBridge.Adapter do
  @moduledoc """
  Snakepit adapter that routes ML commands to platform modules.
  """

  @behaviour Snakepit.Adapter

  require Logger

## Phase 2: Build the ML Platform (Weeks 2-3)

### Day 5-7: Implement Python Bridge and Adapter
**Objective:** Implement the core communication layer that connects the generic `snakepit` infrastructure to the Python runtime.

*   **Action:** Follow the instructions in `prompts/05_implement_python_bridge_CORRECTED.md`.
    *   Implement `SnakepitGRPCBridge.Python.Process` to manage the `Port`.
    *   Implement the `SnakepitGRPCBridge.Adapter` callbacks to correctly start and communicate with the `Python.Process` worker.
    *   Implement the Python-side `worker.py` script.
*   **Validation:** A call to `Snakepit.execute` now successfully routes through your adapter to the Python process and back.

### Day 8-10: Implement the Variables System
**Objective:** Build the complete, session-aware variable management system.

*   **Action:** Follow the instructions in `prompts/02_implement_variables_system.md`.
*   **Validation:** The `Variables.Manager` is fully functional and all unit tests pass. Calls to `Snakepit.execute` with variable commands (e.g., "create_variable") work end-to-end.

### Day 11-13: Implement the Tools System
**Objective:** Build the bidirectional tool registry and execution system.

*   **Action:** Follow the instructions in `prompts/03_implement_tools_system.md`.
*   **Validation:** Both Elixir and Python functions can be registered as tools and called from the other language.

### Day 14-15: Implement the DSPy System
**Objective:** Build the high-level DSPy integration layer.

*   **Action:** Follow the instructions in `prompts/04_implement_dspy_system.md`.
*   **Validation:** High-level DSPy operations like `enhanced_predict` work correctly, leveraging the underlying variable and tool systems.

---

## Phase 3: Simplify DSPex Consumer Layer (Week 4)

### Day 16-18: Refactor DSPex
**Objective:** Transform `DSPex` into a pure orchestration layer.

*   **Action:** Update `dspex/mix.exs` to depend on `snakepit_grpc_bridge`.
*   **Action:** Remove all implementation logic (variables, tools, python bridge) from `dspex`.
*   **Action:** Rewrite the `DSPex` main module and the `defdsyp` macro to be thin wrappers that call the clean APIs provided by `SnakepitGRPCBridge.API.*`.

---

## Phase 4 & 5: Integration, Testing, and Release (Weeks 5-6)

### Day 19-25: Full-Stack Integration Testing
**Objective:** Ensure the complete three-layer system works flawlessly together.

*   **Action:** Create a comprehensive integration test suite that exercises user stories starting from `DSPex` down through the entire stack.
*   **Action:** Perform performance and benchmark testing to identify any regressions.
*   **Action:** Address bugs and polish the APIs based on testing feedback.

### Day 26-30: Documentation and Release
**Objective:** Update all documentation and prepare for release.

*   **Action:** Update all `README.md` files and module documentation to reflect the new architecture.
*   **Action:** Create a migration guide for existing users.
*   **Action:** Prepare and publish the packages in the correct dependency order: `snakepit`, then `snakepit_grpc_bridge`, then `dspex`.
# DSPex v0.3 Roadmap: ALTAR Integration & DSPy Tool Ecosystem

**Version:** Draft 1.0
**Date:** October 8, 2025
**Status:** Planning
**Target Release:** Q1 2026

---

## Executive Summary

DSPex v0.3 represents a strategic evolution from a **DSPy-to-Elixir bridge** to a comprehensive **ALTAR-enabled AI agent platform** that treats DSPy tools as first-class ADM-compliant citizens. This release positions DSPex as the reference implementation for integrating domain-specific ML libraries with the ALTAR ecosystem while maintaining seamless DSPy compatibility.

**Key Transformation:**
- **Current (v0.2.1):** DSPy bridge with variable-aware modules and gRPC integration
- **Target (v0.3):** ALTAR-native platform where DSPy tools are ADM-compliant and portable to GRID

**Strategic Value:**
- Enable DSPy workflows to benefit from ALTAR's promotion path
- Provide domain-specific (AI/ML) tool abstractions on top of Snakepit's generic infrastructure
- Create reference implementation for framework-specific ALTAR integrations
- Maintain backward compatibility with existing DSPy code

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [ALTAR Integration Vision](#altar-integration-vision)
3. [Core Features for v0.3](#core-features-for-v03)
4. [Implementation Phases](#implementation-phases)
5. [Technical Design](#technical-design)
6. [Migration Strategy](#migration-strategy)
7. [Timeline and Milestones](#timeline-and-milestones)
8. [Success Metrics](#success-metrics)

---

## Current State Analysis

### What DSPex Has (v0.2.1)

✅ **Strong DSPy Integration Foundation:**

1. **Universal DSPy Bridge**
   - Automatic discovery of 70+ DSPy classes
   - Schema-driven auto-discovery with `discover_schema`
   - Universal `call_dspy` for any DSPy function
   - Instance management with session affinity
   - **Gap:** DSPy schemas not ADM-compliant

2. **Variable-Aware Modules**
   - Extracted from Snakepit into `dspex_adapters/dspy_variable_integration.py`
   - VariableAwarePredict, ChainOfThought, ReAct, ProgramOfThought
   - Automatic variable binding and synchronization
   - **Gap:** Variable system separate from ADM parameters

3. **High-Level Elixir Modules**
   - DSPex.Modules.Predict
   - DSPex.Modules.ChainOfThought
   - Result transformation pipeline
   - **Gap:** Not ALTAR-aware

4. **gRPC Integration**
   - 17 registered Python tools via Snakepit
   - Session management and worker affinity
   - Real Gemini API integration working
   - **Gap:** Tools not ADM-registered

5. **Dual-Backend Architecture**
   - LocalState for fast operations
   - BridgedState for Python DSPy calls
   - Automatic backend switching
   - **Gap:** No GRID awareness

### What's Missing for ALTAR Integration

❌ **ALTAR-Specific Requirements:**

1. **DSPy Tools as ADM FunctionDeclarations**
   - Convert DSPy Signature to ADM Schema
   - Register DSPy modules in global tool registry
   - Validate DSPy inputs against ADM schemas

2. **Tool Composition Patterns**
   - Chain DSPy modules as ADM tool pipelines
   - DSPy-specific result transformers
   - Optimization as tool configuration

3. **Framework Adapter for DSPy**
   - DSPy → ALTAR adapter (export DSPy tools to ADM)
   - ALTAR → DSPy adapter (use ALTAR tools in DSPy)
   - Bidirectional compatibility

4. **GRID-Aware Optimization**
   - BootstrapFewShot with distributed execution
   - MIPRO optimization across GRID nodes
   - Teleprompter patterns for GRID

5. **Pydantic-AI Compatibility**
   - Support both DSPy and Pydantic-AI
   - Unified interface for both frameworks
   - Migration path between them

---

## ALTAR Integration Vision

### DSPex's Role in ALTAR Ecosystem

```
┌─────────────────────────────────────────────────────────┐
│              ALTAR Ecosystem                            │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Application Layer                              │   │
│  │  ┌─────────────────────────────────────────┐    │   │
│  │  │ 🧠 DSPex v0.3 - AI/ML Domain Layer      │    │   │
│  │  │ - DSPy module wrappers (Predict, CoT)   │    │   │
│  │  │ - Signature → ADM translation           │    │   │
│  │  │ - ML-specific result transformers       │    │   │
│  │  │ - Optimization patterns                 │    │   │
│  │  │ - Pydantic-AI compatibility             │    │   │
│  │  └────────────────┬────────────────────────┘    │   │
│  └───────────────────┼─────────────────────────────┘   │
│                      │                                  │
│                   Uses                                  │
│                      ↓                                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Infrastructure Layer                           │   │
│  │  ┌─────────────────────────────────────────┐    │   │
│  │  │ 🐍 Snakepit v0.5 - Python LATER Runtime │    │   │
│  │  │ - ADM FunctionDeclaration support       │    │   │
│  │  │ - Two-tier registry                     │    │   │
│  │  │ - Framework adapters (LangChain, etc.)  │    │   │
│  │  │ - gRPC bridge, mTLS, RBAC prep         │    │   │
│  │  └─────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────┘   │
│                      ↑                                  │
│                Implements                               │
│                      ↓                                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Layer 1: ADM (Universal Data Model)            │   │
│  │  - FunctionDeclaration, FunctionCall, Schema    │   │
│  │  - JSON serialization                           │   │
│  │  - Language-neutral contracts                   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Key Insight: DSPex is Domain Logic, Snakepit is Infrastructure

**Separation of Concerns:**

```elixir
# Snakepit (Infrastructure): Generic tool execution
Snakepit.LATER.Executor.execute_tool(session_id, %{
  "name" => "generic_function",
  "args" => %{"param1" => "value"}
})

# DSPex (Domain Logic): DSPy-specific abstractions
DSPex.Modules.ChainOfThought.execute(cot_instance, %{
  "question" => "Explain photosynthesis"
})
# Internally: Translates to ADM FunctionCall, uses Snakepit for execution
```

**Value Proposition:**
- **For Snakepit:** Remains generic, supports any Python library
- **For DSPex:** Provides DSPy-specific ergonomics on top of ALTAR
- **For Users:** Choose abstraction level (low-level Snakepit or high-level DSPex)

---

## Core Features for v0.3

### Feature 1: DSPy Signature → ADM Schema Translation

**Objective:** Convert DSPy signatures to ADM-compliant FunctionDeclarations

**DSPy Signature Format:**
```python
# DSPy uses string-based signatures
signature = "question -> reasoning, answer"

# Which internally becomes:
InputFields: {question: str}
OutputFields: {reasoning: str, answer: str}
```

**ADM Translation:**
```python
# dspex_adapters/altar/dspy_schema.py
from dspy import Signature
from snakepit_bridge.altar.adm import ADMSchemaGenerator

class DSPyToADM:
    """Translates DSPy Signatures to ADM FunctionDeclarations."""

    @staticmethod
    def signature_to_adm(signature_str: str, module_name: str = None) -> dict:
        """
        Convert DSPy signature string to ADM FunctionDeclaration.

        Args:
            signature_str: DSPy signature (e.g., "question -> answer")
            module_name: Optional name for the tool

        Returns:
            ADM FunctionDeclaration dict
        """
        # Parse DSPy signature
        sig = Signature(signature_str)

        # Build input parameters schema
        input_properties = {}
        required_inputs = []

        for field_name, field_info in sig.input_fields.items():
            field_type = field_info.annotation
            adm_type = _python_type_to_adm(field_type)

            input_properties[field_name] = {
                "type": adm_type,
                "description": field_info.desc or f"Input field: {field_name}"
            }
            required_inputs.append(field_name)

        # Build output schema
        output_properties = {}
        for field_name, field_info in sig.output_fields.items():
            field_type = field_info.annotation
            adm_type = _python_type_to_adm(field_type)

            output_properties[field_name] = {
                "type": adm_type,
                "description": field_info.desc or f"Output field: {field_name}"
            }

        # Create ADM FunctionDeclaration
        return {
            "name": module_name or f"dspy_{signature_str.replace(' ', '_')}",
            "description": f"DSPy module with signature: {signature_str}",
            "parameters": {
                "type": "OBJECT",
                "properties": input_properties,
                "required": required_inputs
            },
            "returns": {
                "type": "OBJECT",
                "properties": output_properties
            }
        }

    @staticmethod
    def from_module(dspy_module) -> dict:
        """Extract ADM declaration from instantiated DSPy module."""
        signature_str = str(dspy_module.signature)
        module_class = dspy_module.__class__.__name__

        return DSPyToADM.signature_to_adm(signature_str, f"dspy_{module_class}")
```

**Elixir Integration:**
```elixir
defmodule DSPex.ALTAR.SchemaConverter do
  @moduledoc """
  Converts DSPy signatures to ADM FunctionDeclarations.
  """

  @spec dspy_signature_to_adm(signature :: String.t(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}
  def dspy_signature_to_adm(signature, opts \\ []) do
    module_name = Keyword.get(opts, :name, nil)

    # Call Python converter
    result = Snakepit.execute("dspy_signature_to_adm", %{
      "signature" => signature,
      "module_name" => module_name
    })

    case result do
      {:ok, %{"declaration" => decl}} -> {:ok, decl}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec register_dspy_module_as_tool(module_instance :: tuple()) ::
    :ok | {:error, term()}
  def register_dspy_module_as_tool({session_id, instance_id}) do
    # Extract ADM declaration from DSPy module
    {:ok, decl} = Snakepit.execute_in_session(session_id, "dspy_module_to_adm", %{
      "instance_id" => instance_id
    })

    # Create wrapper that calls DSPy module
    impl = fn args ->
      Snakepit.execute_in_session(session_id, "call_dspy_instance", %{
        "instance_id" => instance_id,
        "method" => "__call__",
        "kwargs" => args
      })
    end

    # Register with Snakepit's global registry
    Snakepit.LATER.GlobalRegistry.register_tool(decl, impl)
  end
end
```

**Usage Example:**
```elixir
# Create DSPy ChainOfThought
{:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> reasoning, answer")

# Register as ADM tool
:ok = DSPex.ALTAR.SchemaConverter.register_dspy_module_as_tool(cot)

# Now it's available as a standard ALTAR tool
{:ok, result} = Snakepit.LATER.Executor.execute_tool("session_123", %{
  "name" => "dspy_ChainOfThought",
  "args" => %{"question" => "What is photosynthesis?"}
})
```

**Deliverables:**
- [ ] Python `DSPyToADM` class
- [ ] Elixir `DSPex.ALTAR.SchemaConverter` module
- [ ] Automatic registration of DSPy modules as tools
- [ ] Integration tests with all DSPy module types
- [ ] Documentation with examples

### Feature 2: DSPy Tool Composition Patterns

**Objective:** Enable composing DSPy modules as ADM tool pipelines

**Pattern 1: Sequential Pipeline**
```elixir
defmodule MyApp.ResearchPipeline do
  use DSPex.ALTAR.Pipeline

  @doc """
  Multi-step research pipeline using DSPy modules.
  """
  def create do
    pipeline([
      # Step 1: Generate search queries
      {:dspy, DSPex.Modules.Predict, %{
        signature: "topic -> search_queries",
        name: "query_generator"
      }},

      # Step 2: Search (custom tool)
      {:tool, "search_web", %{max_results: 10}},

      # Step 3: Analyze results
      {:dspy, DSPex.Modules.ChainOfThought, %{
        signature: "search_results -> key_findings, summary",
        name: "result_analyzer"
      }},

      # Step 4: Generate final report
      {:dspy, DSPex.Modules.Predict, %{
        signature: "key_findings, summary -> final_report",
        name: "report_generator"
      }}
    ])
  end

  def execute(pipeline, topic) do
    # Executes pipeline with ADM FunctionCalls under the hood
    DSPex.ALTAR.Pipeline.run(pipeline, %{"topic" => topic})
  end
end
```

**Pattern 2: Parallel Execution**
```elixir
defmodule MyApp.MultiSourceAnalysis do
  use DSPex.ALTAR.Pipeline

  def create do
    pipeline([
      # Step 1: Generate query
      {:dspy, DSPex.Modules.Predict, %{
        signature: "question -> optimized_query"
      }},

      # Step 2: Parallel searches
      {:parallel, [
        {:tool, "search_wikipedia"},
        {:tool, "search_arxiv"},
        {:tool, "search_github"}
      ]},

      # Step 3: Synthesize results
      {:dspy, DSPex.Modules.ChainOfThought, %{
        signature: "wikipedia_results, arxiv_results, github_results -> synthesized_answer, sources"
      }}
    ])
  end
end
```

**Implementation:**
```elixir
defmodule DSPex.ALTAR.Pipeline do
  @moduledoc """
  Composable pipelines of DSPy modules and ALTAR tools.
  """

  defmacro __using__(_opts) do
    quote do
      import DSPex.ALTAR.Pipeline
    end
  end

  @spec pipeline(steps :: list()) :: %DSPex.ALTAR.Pipeline{}
  def pipeline(steps) do
    %DSPex.ALTAR.Pipeline{
      steps: compile_steps(steps),
      session_id: nil
    }
  end

  @spec run(pipeline :: %DSPex.ALTAR.Pipeline{}, input :: map()) ::
    {:ok, term()} | {:error, term()}
  def run(pipeline, input) do
    # Ensure session exists
    session_id = pipeline.session_id || create_pipeline_session()

    # Execute each step
    Enum.reduce_while(pipeline.steps, {:ok, input}, fn step, {:ok, acc} ->
      case execute_step(step, acc, session_id) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_step({:dspy, module, opts}, input, session_id) do
    # Create DSPy module
    {:ok, instance} = apply(module, :create, [opts[:signature], session_id: session_id])

    # Execute and transform
    case apply(module, :execute, [instance, input]) do
      {:ok, result} -> {:ok, transform_result(result, opts)}
      error -> error
    end
  end

  defp execute_step({:tool, tool_name, opts}, input, session_id) do
    # Execute standard ALTAR tool
    function_call = %{
      "name" => tool_name,
      "args" => Map.merge(input, opts)
    }

    Snakepit.LATER.Executor.execute_tool(session_id, function_call)
  end

  defp execute_step({:parallel, substeps}, input, session_id) do
    # Execute substeps in parallel
    tasks = Enum.map(substeps, fn substep ->
      Task.async(fn -> execute_step(substep, input, session_id) end)
    end)

    # Collect results
    results = Task.await_many(tasks)

    # Merge results into single map
    merged = Enum.reduce(results, %{}, fn
      {:ok, result}, acc -> Map.merge(acc, result)
      {:error, _reason}, _acc -> {:halt, {:error, "Parallel step failed"}}
    end)

    {:ok, merged}
  end
end
```

**Deliverables:**
- [ ] `DSPex.ALTAR.Pipeline` module
- [ ] Sequential pipeline execution
- [ ] Parallel pipeline execution
- [ ] Conditional branching support
- [ ] Error handling and retry logic
- [ ] Documentation with real-world examples

### Feature 3: Framework Adapter for DSPy

**Objective:** Bidirectional compatibility between DSPy and ALTAR

**Export DSPy to ALTAR:**
```python
# dspex_adapters/altar/dspy_adapter.py
from dspy import Predict, ChainOfThought, ReAct
from snakepit_bridge.altar.adm import ADMSchemaGenerator

class DSPyALTARAdapter:
    """Export DSPy modules to ALTAR ecosystem."""

    @staticmethod
    def export_module(dspy_module, session_id: str) -> dict:
        """
        Export a DSPy module as an ALTAR-compliant tool.

        Returns ADM FunctionDeclaration.
        """
        # Generate ADM schema
        declaration = DSPyToADM.from_module(dspy_module)

        # Store instance for execution
        instance_id = _store_instance(session_id, dspy_module)

        # Add metadata about storage
        declaration["metadata"] = {
            "framework": "dspy",
            "session_id": session_id,
            "instance_id": instance_id,
            "module_class": dspy_module.__class__.__name__
        }

        return declaration

    @staticmethod
    def export_all_from_program(program, session_id: str) -> list[dict]:
        """
        Export all DSPy modules from a compiled program.

        Useful for exporting optimized programs.
        """
        declarations = []

        # Traverse program structure
        for module_name, module in program.named_predictors():
            decl = DSPyALTARAdapter.export_module(module, session_id)
            decl["name"] = f"{program.__class__.__name__}_{module_name}"
            declarations.append(decl)

        return declarations
```

**Import ALTAR to DSPy:**
```python
# dspex_adapters/altar/altar_to_dspy.py
import dspy
from dspy import Signature, InputField, OutputField

class ALTARToolWrapper:
    """Wraps an ALTAR tool as a DSPy-compatible module."""

    def __init__(self, tool_declaration: dict):
        self.name = tool_declaration["name"]
        self.declaration = tool_declaration

        # Build DSPy signature from ADM schema
        self.signature = self._build_signature(tool_declaration)

    def _build_signature(self, decl: dict) -> Signature:
        """Create DSPy Signature from ADM schema."""
        params = decl["parameters"]["properties"]
        returns = decl.get("returns", {}).get("properties", {"result": {"type": "STRING"}})

        # Build input fields
        input_fields = {
            name: InputField(desc=schema.get("description", ""))
            for name, schema in params.items()
        }

        # Build output fields
        output_fields = {
            name: OutputField(desc=schema.get("description", ""))
            for name, schema in returns.items()
        }

        # Create signature class dynamically
        sig_class = type(
            f"{self.name}Signature",
            (Signature,),
            {**input_fields, **output_fields}
        )

        return sig_class

    def __call__(self, **kwargs):
        """Execute the ALTAR tool via Snakepit bridge."""
        from snakepit_bridge.context import get_current_context

        ctx = get_current_context()

        # Execute via ALTAR
        result = ctx.execute_tool(self.name, kwargs)

        # Convert to DSPy Prediction format
        return dspy.Prediction(**result)

# Usage
def import_altar_tool(tool_name: str) -> ALTARToolWrapper:
    """Import an ALTAR tool for use in DSPy programs."""
    # Fetch declaration from Snakepit
    ctx = get_current_context()
    declaration = ctx.lookup_tool(tool_name)

    return ALTARToolWrapper(declaration)
```

**Elixir API:**
```elixir
defmodule DSPex.ALTAR.DSPyAdapter do
  @moduledoc """
  Bidirectional adapter between DSPy and ALTAR.
  """

  @spec export_dspy_program(program_instance :: tuple()) ::
    {:ok, [map()]} | {:error, term()}
  def export_dspy_program({session_id, instance_id}) do
    # Export all modules from DSPy program
    Snakepit.execute_in_session(session_id, "export_dspy_program", %{
      "instance_id" => instance_id
    })
  end

  @spec import_altar_tool_to_dspy(tool_name :: String.t(), session_id :: String.t()) ::
    {:ok, String.t()} | {:error, term()}
  def import_altar_tool_to_dspy(tool_name, session_id) do
    # Make ALTAR tool available in DSPy
    Snakepit.execute_in_session(session_id, "import_altar_to_dspy", %{
      "tool_name" => tool_name
    })
  end
end
```

**Deliverables:**
- [ ] `DSPyALTARAdapter` Python class (export)
- [ ] `ALTARToolWrapper` Python class (import)
- [ ] `DSPex.ALTAR.DSPyAdapter` Elixir module
- [ ] Integration tests with real DSPy programs
- [ ] Documentation and examples

### Feature 4: Pydantic-AI Compatibility Layer

**Objective:** Support both DSPy and Pydantic-AI workflows in DSPex

**Unified Interface:**
```elixir
defmodule DSPex.Agents do
  @moduledoc """
  Framework-agnostic agent interface.
  Supports both DSPy and Pydantic-AI under the hood.
  """

  @type framework :: :dspy | :pydantic_ai

  @spec create_agent(opts :: keyword()) :: {:ok, pid()} | {:error, term()}
  def create_agent(opts) do
    framework = Keyword.get(opts, :framework, :dspy)
    model = Keyword.fetch!(opts, :model)
    tools = Keyword.get(opts, :tools, [])
    system_prompt = Keyword.get(opts, :system_prompt, "")

    case framework do
      :dspy ->
        create_dspy_agent(model, tools, system_prompt)

      :pydantic_ai ->
        create_pydantic_agent(model, tools, system_prompt)
    end
  end

  @spec run(agent :: pid(), input :: String.t()) ::
    {:ok, String.t()} | {:error, term()}
  def run(agent, input) do
    # Unified execution regardless of framework
    GenServer.call(agent, {:run, input})
  end

  # Internal implementations

  defp create_dspy_agent(model, tools, system_prompt) do
    # Use DSPy Predict or ChainOfThought
    signature = "input -> output"

    {:ok, predictor} = DSPex.Modules.Predict.create(signature,
      model: model,
      instructions: system_prompt
    )

    # Register tools
    Enum.each(tools, fn tool_name ->
      DSPex.ALTAR.DSPyAdapter.import_altar_tool_to_dspy(tool_name, session_id(predictor))
    end)

    {:ok, predictor}
  end

  defp create_pydantic_agent(model, tools, system_prompt) do
    # Use Pydantic-AI Agent
    result = Snakepit.execute("create_pydantic_agent", %{
      "model" => model,
      "tools" => tools,
      "system_prompt" => system_prompt
    })

    case result do
      {:ok, %{"agent_id" => agent_id}} -> {:ok, agent_id}
      error -> error
    end
  end
end
```

**Python Pydantic-AI Integration:**
```python
# dspex_adapters/pydantic_ai_integration.py
from pydantic_ai import Agent
from snakepit_bridge.core import tool
from snakepit_bridge.altar.adm import ADMSchemaGenerator

@tool(description="Create a Pydantic-AI agent")
def create_pydantic_agent(model: str, tools: list[str], system_prompt: str) -> dict:
    """Create Pydantic-AI agent with ALTAR tools."""
    from pydantic_ai import Agent

    # Import ALTAR tools into Pydantic-AI
    tool_functions = []
    for tool_name in tools:
        wrapper = create_altar_tool_wrapper(tool_name)
        tool_functions.append(wrapper)

    # Create agent
    agent = Agent(
        model=model,
        system_prompt=system_prompt,
        tools=tool_functions
    )

    # Store agent
    agent_id = store_agent(agent)

    return {"agent_id": agent_id}

def create_altar_tool_wrapper(tool_name: str):
    """Create Pydantic-AI tool from ALTAR declaration."""
    from snakepit_bridge.context import get_current_context

    ctx = get_current_context()
    declaration = ctx.lookup_tool(tool_name)

    # Convert ADM to Pydantic-AI tool
    # (Similar to Pydantic-AI adapter in Snakepit roadmap)
    def wrapper(**kwargs):
        return ctx.execute_tool(tool_name, kwargs)

    wrapper.__name__ = tool_name
    wrapper.__doc__ = declaration["description"]

    return wrapper
```

**Configuration:**
```elixir
# config/config.exs
config :dspex,
  # Choose framework or auto-detect
  default_framework: :auto,  # :dspy | :pydantic_ai | :auto

  # Framework-specific settings
  dspy: [
    default_optimizer: "BootstrapFewShot",
    cache_compiled_programs: true
  ],

  pydantic_ai: [
    default_result_validator: true,
    retry_on_validation_error: true
  ]
```

**Deliverables:**
- [ ] `DSPex.Agents` unified interface
- [ ] Pydantic-AI integration in Python
- [ ] Framework auto-detection
- [ ] Migration guide between frameworks
- [ ] Comparison documentation (when to use which)

### Feature 5: GRID-Aware Optimization

**Objective:** Enable DSPy optimization (BootstrapFewShot, MIPRO) to work with GRID

**Challenge:** DSPy optimizers need to run multiple tool executions. In GRID mode, these should be distributed.

**Solution: Optimization-Aware Execution Backend**

```elixir
defmodule DSPex.ALTAR.OptimizationBackend do
  @moduledoc """
  Backend for DSPy optimization that works with both LATER and GRID.
  """

  @behaviour DSPex.Optimization.Backend

  @impl true
  def execute_batch(function_calls, opts) do
    mode = Application.get_env(:snakepit, :execution_mode, :later)

    case mode do
      :later ->
        # Execute locally in parallel
        execute_batch_local(function_calls)

      :grid ->
        # Distribute across GRID nodes
        execute_batch_distributed(function_calls, opts)
    end
  end

  defp execute_batch_local(function_calls) do
    # Use Task.async_stream for parallel local execution
    function_calls
    |> Task.async_stream(fn call ->
      Snakepit.LATER.Executor.execute_tool(call.session_id, call)
    end, max_concurrency: System.schedulers_online() * 2)
    |> Enum.to_list()
  end

  defp execute_batch_distributed(function_calls, opts) do
    # GRID distributes automatically
    # We just send all calls and wait for results
    correlation_id = opts[:correlation_id] || UUID.generate()

    # Send all calls with same correlation_id
    tasks = Enum.map(function_calls, fn call ->
      call_with_correlation = Map.put(call, "correlation_id", correlation_id)

      Task.async(fn ->
        Snakepit.GRID.RuntimeClient.execute_tool(call_with_correlation)
      end)
    end)

    # Wait for all results
    Task.await_many(tasks, timeout: opts[:timeout] || 60_000)
  end
end
```

**Python Optimizer Integration:**
```python
# dspex_adapters/dspy_grid_optimizer.py
import dspy
from dspy.teleprompt import BootstrapFewShot
from snakepit_bridge.context import get_current_context

class GRIDAwareBootstrapFewShot(BootstrapFewShot):
    """
    DSPy BootstrapFewShot optimizer that can distribute
    candidate evaluation across GRID nodes.
    """

    def compile(self, student, trainset, teacher=None, **kwargs):
        ctx = get_current_context()

        # Check if GRID is available
        if ctx.has_capability("distributed_execution"):
            # Use GRID-aware compilation
            return self._compile_distributed(student, trainset, teacher, **kwargs)
        else:
            # Fall back to local compilation
            return super().compile(student, trainset, teacher, **kwargs)

    def _compile_distributed(self, student, trainset, teacher, **kwargs):
        """Distribute candidate evaluation across GRID."""
        # Generate candidates
        candidates = self._generate_candidates(student, trainset, teacher)

        # Evaluate candidates in parallel via GRID
        ctx = get_current_context()

        evaluation_tasks = []
        for candidate in candidates:
            task_id = ctx.submit_batch_execution([
                {"tool": "evaluate_candidate", "args": {"candidate": candidate}}
            ])
            evaluation_tasks.append(task_id)

        # Wait for results
        results = ctx.wait_for_batch_results(evaluation_tasks)

        # Select best candidate
        best_candidate = self._select_best(candidates, results)

        return best_candidate
```

**Usage:**
```elixir
# In application code
defmodule MyApp.TrainingPipeline do
  def optimize_agent do
    # Create student program
    {:ok, student} = DSPex.Modules.Predict.create("question -> answer")

    # Load training data
    trainset = load_training_examples()

    # Run optimization (automatically GRID-aware)
    {:ok, optimized} = DSPex.Optimization.bootstrap_fewshot(
      student,
      trainset,
      backend: DSPex.ALTAR.OptimizationBackend  # Uses GRID if available
    )

    optimized
  end
end
```

**Deliverables:**
- [ ] `DSPex.ALTAR.OptimizationBackend` module
- [ ] GRID-aware BootstrapFewShot
- [ ] GRID-aware MIPRO
- [ ] Distributed evaluation metrics
- [ ] Documentation on optimization at scale

---

## Implementation Phases

### Phase 1: ADM-Compliant DSPy Tools (3 weeks)

**Goal:** DSPy modules generate ADM FunctionDeclarations

**Week 1: Schema Translation**
- [ ] Implement `DSPyToADM` Python class
- [ ] Implement `DSPex.ALTAR.SchemaConverter` Elixir module
- [ ] Unit tests for signature parsing
- [ ] Integration tests with all DSPy module types

**Week 2: Tool Registration**
- [ ] Auto-registration of DSPy modules
- [ ] Integration with Snakepit v0.5 global registry
- [ ] Session-scoped DSPy module availability
- [ ] Tests

**Week 3: End-to-End Integration**
- [ ] Update existing DSPex.Modules.* to use ADM
- [ ] Update examples to demonstrate ADM compliance
- [ ] Documentation
- [ ] Performance benchmarks

**Deliverables:**
- DSPy signatures → ADM schemas working
- All examples updated
- Documentation published

### Phase 2: Pipeline Composition (2 weeks)

**Goal:** Composable pipelines of DSPy + ALTAR tools

**Week 1: Pipeline Engine**
- [ ] Implement `DSPex.ALTAR.Pipeline` module
- [ ] Sequential execution
- [ ] Parallel execution
- [ ] Error handling

**Week 2: Real-World Patterns**
- [ ] Create 5 example pipelines
- [ ] Conditional branching support
- [ ] Result transformation
- [ ] Documentation

**Deliverables:**
- Pipeline system working
- Example pipelines
- Documentation

### Phase 3: Framework Adapters (3 weeks)

**Goal:** Bidirectional DSPy ↔ ALTAR compatibility

**Week 1: DSPy → ALTAR Export**
- [ ] Export single DSPy modules
- [ ] Export entire programs
- [ ] Metadata preservation
- [ ] Tests

**Week 2: ALTAR → DSPy Import**
- [ ] ALTARToolWrapper implementation
- [ ] Integration with DSPy programs
- [ ] Tests

**Week 3: Pydantic-AI Support**
- [ ] Unified `DSPex.Agents` interface
- [ ] Pydantic-AI integration
- [ ] Framework comparison docs

**Deliverables:**
- Bidirectional adapters working
- Pydantic-AI support
- Documentation

### Phase 4: GRID-Aware Optimization (2 weeks)

**Goal:** DSPy optimizers work with GRID

**Week 1: Optimization Backend**
- [ ] `DSPex.ALTAR.OptimizationBackend`
- [ ] Batch execution support
- [ ] GRID distribution logic

**Week 2: Optimizer Integration**
- [ ] GRID-aware BootstrapFewShot
- [ ] GRID-aware MIPRO
- [ ] Benchmarks showing speedup

**Deliverables:**
- Distributed optimization working
- Performance benchmarks
- Documentation

### Phase 5: Testing & Release (2 weeks)

**Goal:** Production-ready v0.3 release

**Week 1: Testing**
- [ ] Comprehensive test suite
- [ ] Integration tests with Snakepit v0.5
- [ ] Performance benchmarks
- [ ] Documentation review

**Week 2: Release**
- [ ] Beta release (v0.3.0-beta.1)
- [ ] Gather feedback
- [ ] Bug fixes
- [ ] Final release (v0.3.0)

**Deliverables:**
- DSPex v0.3.0 released
- Complete documentation
- Migration guide

---

## Technical Design

### Directory Structure

```
dspex/
├── lib/
│   ├── dspex/
│   │   ├── altar/              # NEW: ALTAR integration
│   │   │   ├── schema_converter.ex
│   │   │   ├── pipeline.ex
│   │   │   ├── dspy_adapter.ex
│   │   │   ├── optimization_backend.ex
│   │   │   └── types.ex
│   │   ├── agents.ex           # NEW: Unified agent interface
│   │   ├── modules/            # Existing, updated for ALTAR
│   │   │   ├── predict.ex
│   │   │   ├── chain_of_thought.ex
│   │   │   └── ...
│   │   ├── optimization/       # NEW: Optimization support
│   │   │   ├── backend.ex
│   │   │   ├── bootstrap_fewshot.ex
│   │   │   └── mipro.ex
│   │   └── ...
│   └── dspex.ex
├── priv/
│   └── python/
│       ├── dspex_adapters/
│       │   ├── altar/          # NEW: ALTAR-specific
│       │   │   ├── dspy_schema.py
│       │   │   ├── dspy_adapter.py
│       │   │   ├── altar_to_dspy.py
│       │   │   └── pydantic_ai_integration.py
│       │   ├── dspy_grid_optimizer.py  # NEW
│       │   └── ...
│       └── ...
├── docs/
│   ├── altar/                  # NEW: ALTAR documentation
│   │   ├── dspy_adm_mapping.md
│   │   ├── pipeline_patterns.md
│   │   ├── framework_comparison.md
│   │   └── grid_optimization.md
│   └── ...
└── examples/
    └── altar/                  # NEW: ALTAR examples
        ├── dspy_tool_registration.exs
        ├── research_pipeline.exs
        ├── pydantic_ai_agent.exs
        └── distributed_optimization.exs
```

### Configuration

```elixir
# config/config.exs

config :dspex,
  # Framework selection
  default_framework: :auto,  # :dspy | :pydantic_ai | :auto

  # ALTAR integration
  altar: [
    # Auto-register DSPy modules as ADM tools
    auto_register_modules: true,
    # Pipeline execution timeout
    pipeline_timeout: 300_000,
    # Optimization backend
    optimization_backend: DSPex.ALTAR.OptimizationBackend
  ],

  # DSPy-specific
  dspy: [
    default_optimizer: "BootstrapFewShot",
    cache_compiled_programs: true,
    # Use GRID for optimization if available
    distributed_optimization: true
  ],

  # Pydantic-AI specific
  pydantic_ai: [
    result_validation: true,
    retry_on_error: true
  ]
```

---

## Migration Strategy

### From v0.2.1 to v0.3

**Breaking Changes:**
- DSPy modules now auto-register as ADM tools
- Execution API updated to support both frameworks
- Optimization API changed to support GRID

**Migration Steps:**

1. **Update Dependencies**
   ```elixir
   # mix.exs
   {:snakepit, "~> 0.5.0"}  # Required for ALTAR support
   {:dspex, "~> 0.3.0"}
   ```

2. **Update Configuration**
   ```elixir
   # config/config.exs
   config :dspex,
     altar: [auto_register_modules: true]
   ```

3. **Update Code (Optional - backward compatible)**
   ```elixir
   # v0.2.1
   {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
   {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{"question" => "..."})

   # v0.3 (same API works, but now ALTAR-enabled)
   {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
   {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{"question" => "..."})

   # v0.3 (can also use as ADM tool)
   :ok = DSPex.ALTAR.SchemaConverter.register_dspy_module_as_tool(predictor)
   {:ok, result} = Snakepit.LATER.Executor.execute_tool(session, function_call)
   ```

**Compatibility:**
- All v0.2.1 APIs remain functional
- New ALTAR features are opt-in
- Examples continue to work

---

## Timeline and Milestones

### Q4 2025 (October - December)

**Milestone 1: ADM-Compliant DSPy (Oct 15 - Nov 5)**
- Schema translation working
- Auto-registration implemented
- All examples updated

**Milestone 2: Pipeline Composition (Nov 6 - Nov 20)**
- Pipeline engine complete
- 5 example pipelines
- Documentation

**Milestone 3: Framework Adapters (Nov 21 - Dec 12)**
- DSPy ↔ ALTAR bidirectional
- Pydantic-AI support
- Unified interface

### Q1 2026 (January - March)

**Milestone 4: GRID Optimization (Jan 1 - Jan 15)**
- Optimization backend
- Distributed BootstrapFewShot
- Benchmarks

**Milestone 5: Beta Release (Jan 16 - Jan 31)**
- v0.3.0-beta.1
- Community testing
- Bug fixes

**Milestone 6: Final Release (Feb 1 - Feb 15)**
- v0.3.0 released
- Documentation complete
- Migration guide

---

## Success Metrics

### Technical Metrics

1. **ADM Compliance:** 100% of DSPy modules generate valid ADM schemas
2. **Performance:** No regression from v0.2.1
3. **Test Coverage:** >85% for new ALTAR modules
4. **Framework Parity:** Both DSPy and Pydantic-AI working equally well

### Adoption Metrics

1. **Migration:** 80% of v0.2.1 users successfully migrate within 2 months
2. **Pipeline Usage:** At least 20 community-contributed pipeline examples
3. **GRID Optimization:** Demonstrable speedup on distributed optimization

### Community Metrics

1. **Examples:** 10+ real-world ALTAR-DSPy integration examples
2. **Issues:** <5 critical bugs in first month
3. **Feedback:** Positive sentiment from AI/ML community

---

## Appendix: Key Insights

### Why DSPex Needs ALTAR

1. **Portability:** DSPy tools can run anywhere ALTAR runs (local, GRID, cloud)
2. **Interoperability:** Mix DSPy with tools from other frameworks
3. **Enterprise Ready:** Leverage GRID's security, audit, and governance
4. **Future-Proof:** As ALTAR grows, DSPex inherits new capabilities

### How DSPex Complements Snakepit

- **Snakepit:** Generic Python bridge, supports any library
- **DSPex:** Domain-specific abstractions for AI/ML workflows
- **Together:** Best of both worlds - infrastructure + domain expertise

### The Three-Layer Cake

```
┌────────────────────────────────────┐
│  DSPex (Domain: AI/ML)             │  ← High-level, DSPy/Pydantic-AI
├────────────────────────────────────┤
│  Snakepit (Infrastructure: Python) │  ← Generic, LATER runtime
├────────────────────────────────────┤
│  ALTAR (Foundation: ADM)           │  ← Universal, language-agnostic
└────────────────────────────────────┘
```

---

**End of Roadmap**

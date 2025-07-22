Of course. Here are the detailed technical specifications for the first and most critical missing component layer: the **User-Facing API Layer**.

This document provides the complete design for the `DSPex` core API. It defines the primary structs and modules that developers will interact with, establishing an ergonomic and powerful interface that abstracts away the underlying complexity of the orchestration, evaluation, and bridge systems.

---

### **`08_SPEC_USER_FACING_API.md`**

# Technical Specification: The DSPex User-Facing API

## 1. Vision and Guiding Principles

The DSPex API is designed to be the primary interface for developers and scientists. It must be:

*   **Declarative and Intuitive:** Users should describe *what* they want to achieve (e.g., "optimize this program"), not *how* to achieve it (e.g., "manage this pool of workers").
*   **Cohesive and Integrated:** The concepts of Programs, Variables, Evaluation, and Optimization should feel like parts of a single, unified system.
*   **Powerful yet Progressive:** A user should be able to perform a simple evaluation with a single line of code, but also have access to the full depth of the scientific framework when needed.
*   **Abstracted from the Backend:** The API must remain consistent whether the underlying execution is happening in a local Elixir process or being orchestrated across a distributed pool of Python workers via gRPC.

## 2. Core API Components

The user-facing API consists of three primary components:

1.  **`DSPex.Context`**: The stateful runtime environment for all operations.
2.  **`DSPex.Program`**: The declarative specification of a `dspy.Module` to be executed.
3.  **`DSPex` (Top-Level Module)**: The clean, functional entry point for core actions like `evaluate/3` and `optimize/4`.

---

## 3. `DSPex.Context`: The Runtime Environment

The `Context` is a `GenServer` that represents an isolated workspace. It is the first thing a user creates and is passed to all major `dspex` functions.

### 3.1. Purpose

*   Manages the lifecycle of the state backend (local vs. bridged).
*   Acts as a registry for `Program` and `CognitiveConfiguration` specifications within a workflow.
*   Holds the session ID for communication with the gRPC bridge.
*   Ensures that all operations within a given workflow are consistent and isolated.

### 3.2. State (`defstruct`)

```elixir
defmodule DSPex.Context do
  use GenServer

  defstruct [
    :id,                 # Unique ID for this context, e.g., "ctx_..."
    :session_id,         # Corresponds to the SessionStore ID for bridged state
    :backend_module,     # The active state provider (e.g., DSPex.Bridge.State.Local)
    :backend_state,      # The internal state of the provider
    :program_specs,      # Map of %{program_name => %DSPex.Program{}}
    :config_spaces,      # Map of %{space_name => %DSPex.CognitiveConfiguration{}}
    :metadata            # User-defined metadata
  ]
end
```

### 3.3. Public API (`@spec`)

```elixir
@doc """
Starts a new, isolated DSPex context.

This is the entry point for any DSPex workflow. It initializes with the high-performance
local backend and will automatically upgrade to the bridged backend if Python-dependent
components are added.
"""
@spec start_link(opts :: keyword()) :: GenServer.on_start()
def start_link(opts \\ [])

@doc """
Stops the context and gracefully cleans up all associated resources,
including the state backend and any active gRPC connections.
"""
@spec stop(pid()) :: :ok
def stop(context_pid)

@doc """
(Internal & Advanced Usage)
Forces the context to upgrade to the bridged backend if it is not already.
This is typically called automatically when a Python-based program is registered.
"""
@spec ensure_bridged(pid()) :: :ok
def ensure_bridged(context_pid)

@doc """
Retrieves the current state backend and its status. Useful for debugging.
"""
@spec get_backend_info(pid()) :: {:ok, map()}
def get_backend_info(context_pid)```

### 3.4. Lifecycle and Backend Switching

*   A new `Context` **always** starts with the `DSPex.Bridge.State.Local` backend for maximum performance.
*   When a user registers a `DSPex.Program` that specifies a Python class (e.g., `python_class: "dspy.ReAct"`), the `Context` `GenServer` will detect this.
*   It will then autonomously trigger the `ensure_bridged` workflow:
    1.  It calls `export_state` on its current `Local` backend.
    2.  It terminates the `Local` backend (an `Agent` process).
    3.  It initializes a new `Bridged` backend, passing the exported state to its `init` function.
    4.  The `Bridged` backend will then use the gRPC bridge to register all the migrated variables and state in the `SessionStore`.
    5.  The `Context` updates its internal state to point to the new `Bridged` backend.
*   This entire process is **transparent** to the user. The `context_pid` remains the same, and all registered variables and programs are preserved.

---

## 4. `DSPex.Program`: The Program Specification

A `DSPex.Program` is an immutable Elixir struct that serves as a *declarative blueprint* for a Python `dspy.Module`. It contains all the information the orchestrator needs to instantiate and run the module on a Python worker.

### 4.1. Purpose

*   Decouples the program's *definition* from its *execution*.
*   Provides a language-agnostic way to describe a `dspy.Module`.
*   Acts as the central artifact for evaluation and optimization.

### 4.2. Definition (`defstruct`)

```elixir
defmodule DSPex.Program do
  @moduledoc "A declarative specification for a `dspy.Module`."
  @enforce_keys [:name, :python_class, :signature]
  defstruct [
    :name,              # Unique atom name for this program, e.g., :my_rag_pipeline
    :python_class,      # The fully qualified Python class to instantiate, e.g., "dspy.ReAct"
    :signature,         # A DSPex.Signature struct defining the inputs/outputs
    :config_space,      # (Optional) The atom name of the CognitiveConfiguration space it uses
    :dependencies,      # (Optional) Map of init args for the Python class, e.g., %{tools: ...}
    :description        # (Optional) A human-readable description
  ]
end
```

### 4.3. Public API (`@spec`)

The `DSPex.Program` module is primarily for creating and managing these specifications within a `Context`.

```elixir
@doc """
Defines a new program specification and registers it with a context.

This is the primary way developers will define the components of their AI system.
"""
@spec define(pid(), map() | keyword()) :: {:ok, %__MODULE__{}}
def define(context_pid, spec)

@doc "Retrieves a program specification from a context by name."
@spec get(pid(), atom()) :: {:ok, %__MODULE__{}} | {:error, :not_found}
def get(context_pid, program_name)

@doc "Lists all program specifications registered in a context."
@spec list(pid()) :: list(%__MODULE__{})
def list(context_pid)
```

### 4.4. Example Usage

```elixir
# Start a context
{:ok, ctx} = DSPex.Context.start_link()

# Define a simple ChainOfThought program
{:ok, cot_program} = DSPex.Program.define(ctx,
  name: :simple_qa,
  python_class: "dspy.ChainOfThought",
  signature: DSPex.Signature.new("question -> answer"),
  description: "A simple question-answering program."
)

# Define a more complex ReAct program with dependencies
search_tool = DSPex.Tool.new(...) # Assuming a Tool definition helper
{:ok, react_program} = DSPex.Program.define(ctx,
  name: :react_agent,
  python_class: "dspy.ReAct",
  signature: DSPex.Signature.new("question -> answer"),
  dependencies: %{tools: [search_tool]},
  config_space: :react_agent_config # Links to a CognitiveConfiguration space
)
```

---

## 5. `DSPex` Module: Top-Level Entry Points

This is the main module that brings everything together, providing simple, functional entry points for the most common workflows.

### 5.1. Purpose

*   To provide a clean, high-level API for the platform's core capabilities.
*   To abstract the details of the `ExperimentJournal` and `EvaluationHarness` for common use cases.

### 5.2. Public API (`@spec`)

```elixir
@doc """
Evaluates a DSPex program against a dataset using a specified metric.

This is the simplest entry point for getting a statistically sound performance
measurement. It orchestrates the creation of a temporary scientific experiment,
runs the evaluation, and returns a clean, comprehensive result.

## Returns
A `%DSPex.Evaluation.EvaluationResult{}` struct containing summary statistics,
cost analysis, and raw trial results.
"""
@spec evaluate(pid(), atom() | %DSPex.Program{}, list(%DSPex.Example{}), atom() | mfa()) ::
  {:ok, map()} | {:error, term()}
def evaluate(context_pid, program_or_name, dataset, metric)

@doc """
Optimizes a DSPex program using a specified optimization strategy.

This is the main entry point for running optimizers like SIMBA-C. It creates and
manages a full scientific experiment to find and validate the best program
configuration.

## Options
  - `valset`: The validation set to use for scoring candidates.
  - `optimizer`: The optimization module to use (default: `DSPex.Optimizers.SIMBA_C`).
  - `optimizer_config`: A map of settings for the optimizer.
  - `objective`: A complex objective struct for multi-objective optimization.

## Returns
An `%DSPex.Evaluation.Experiment{}` struct containing the best discovered program,
its validated performance, and a path to its reproducibility package.
"""
@spec optimize(pid(), atom() | %DSPex.Program{}, list(%DSPex.Example{}), map()) ::
  {:ok, map()} | {:error, term()}
def optimize(context_pid, program_or_name, trainset, opts \\ [])
```

### 5.3. Workflow Abstraction

*   **`DSPex.evaluate/4`**:
    1.  Receives a `context_pid`, `program_or_name`, `dataset`, and `metric`.
    2.  Starts a temporary, in-memory `ExperimentJournal`.
    3.  Registers a simple hypothesis: "Measure the performance of `program` on `dataset`."
    4.  Designs a simple experiment with the given metric.
    5.  Calls `execute_experiment` on the journal.
    6.  The journal uses the `EvaluationHarness` to run the program on the dataset.
    7.  Once complete, it extracts the final `EvaluationResult` and returns it to the user.
    8.  The temporary journal is terminated.

*   **`DSPex.optimize/4`**:
    1.  Receives a `context_pid`, `program_or_name`, `trainset`, and `opts`.
    2.  Starts a persistent `ExperimentJournal` (or uses one from the context).
    3.  The chosen `optimizer` (e.g., `SIMBA-C`) is started, which then takes over, using the `ExperimentJournal` API to manage its hypothesis-driven workflow as described in the `SIMBA-C` integration spec.
    4.  The function returns the final `Experiment` struct upon completion.

## 6. Conclusion

This User-Facing API Layer provides a robust and ergonomic foundation for `dspex`. It successfully hides the immense complexity of the underlying systems while exposing their power through clean, declarative abstractions.

By building these three core components—`DSPex.Context`, `DSPex.Program`, and the top-level `DSPex` functions—we create a complete, intuitive, and powerful platform that fulfills the vision of turning AI development into a rigorous science. This layer is the essential bridge between the user's intent and the platform's sophisticated capabilities.

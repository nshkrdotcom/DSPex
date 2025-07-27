Of course. Instead of a high-level plan, here is a detailed, actionable architectural blueprint. This defines the ideal file structure and the primary responsibilities (modules and functions) for each of the three layers.

This blueprint serves as a concrete target for the refactoring, showing exactly what code should live where.

---

## The Three-Layer Architectural Blueprint

This document outlines the target code structure for `snakepit`, `snakepit_grpc_bridge`, and `dspex`, adhering to a strict three-layer architecture.

### Layer 1: `snakepit` - The Pure Infrastructure Layer

**Role:** A generic, high-performance, and fault-tolerant process pooling and lifecycle management system. It knows *nothing* about Python, gRPC, or Machine Learning. It provides the engine.

**Key Principle:** **NO PYTHON CODE. NO ML-SPECIFIC LOGIC.**

```
snakepit/
├── lib/
│   ├── snakepit.ex                 # Public API: execute/3, execute_stream/4, run_as_script/2
│   └── snakepit/
│       ├── application.ex          # Starts the core infrastructure supervisors
│       ├── adapter.ex              # THE CORE CONTRACT: Defines the Snakepit.Adapter behaviour
│       ├── generic_worker.ex       # A GenServer that uses the adapter to manage one OS process
│       ├── pool/
│       │   ├── pool.ex             # GenServer for managing the worker queue and dispatching requests
│       │   ├── worker_supervisor.ex# DynamicSupervisor for starting/stopping worker starters
│       │   ├── worker_starter.ex   # "Permanent wrapper" supervisor for a single GenericWorker
│       │   ├── process_registry.ex # DETS-backed OS PID tracker for orphan cleanup
│       │   └── application_cleanup.ex# Final guarantee for process termination on app shutdown
│       └── telemetry.ex            # Generic infrastructure telemetry events
└── mix.exs
```

---
#### **File & Method Breakdown for `snakepit`**

<details>
<summary>Click to expand details for the Infrastructure Layer</summary>

**`lib/snakepit.ex`**
*   `@moduledoc`: Public API for the Snakepit process pooler.
*   `execute(command, args, opts)`: Executes a command on an available worker.
*   `execute_stream(command, args, callback, opts)`: Executes a streaming command.
*   `get_stats(pool)`: Retrieves pool statistics.
*   `run_as_script(fun, opts)`: Manages the entire app lifecycle for a script.

**`lib/snakepit/adapter.ex`**
*   `@moduledoc`: The behavior (interface) that all bridge implementations must adopt.
*   `@callback start_worker(adapter_state, worker_id)`: Starts one external OS process. Returns a handle.
*   `@callback execute(handle, command, args, opts)`: Sends a request to the OS process.
*   `@callback execute_stream(handle, command, args, callback, opts)`: Sends a streaming request.
*   `@callback terminate(handle)`: Terminates the OS process.
*   `@callback init(config)`: Initializes the adapter.
*   `@callback capabilities()`: Returns a map of adapter features (e.g., `%{streaming: true}`).

**`lib/snakepit/generic_worker.ex`**
*   `@moduledoc`: A `GenServer` that manages the lifecycle of a single OS process via the adapter.
*   `start_link(opts)`: Starts the worker.
*   `init(opts)`: Calls `Adapter.init/1` and `Adapter.start_worker/2`. Registers with `ProcessRegistry`.
*   `handle_call({:execute, ...})`: Delegates to `Adapter.execute/4`.
*   `terminate(reason, state)`: Calls `Adapter.terminate/1` and unregisters from `ProcessRegistry`.

**`lib/snakepit/pool/pool.ex`**
*   `@moduledoc`: The `GenServer` that manages the pool of workers.
*   `start_link(opts)`: Starts the pool manager.
*   `init(opts)`: Starts the initial set of workers via `WorkerSupervisor`.
*   `handle_call({:execute, ...})`: Checks out an available worker and dispatches the job.
*
*   `handle_cast({:checkin_worker, ...})`: Returns a worker to the available queue and processes the next request.

**`lib/snakepit/pool/process_registry.ex`**
*   `@moduledoc`: DETS-backed registry for tracking OS PIDs to prevent orphans.
*   `reserve_worker(worker_id)`: Reserves a slot before spawning.
*   `activate_worker(worker_id, elixir_pid, os_pid, fingerprint)`: Confirms a process is running.
*   `unregister_worker(worker_id)`: Removes a worker.
*   `get_all_process_pids()`: Returns all known OS PIDs.
*   `cleanup_orphaned_processes(dets_table, current_beam_run_id)`: Core logic for finding and killing zombies on startup.

</details>

---

### Layer 2: `snakepit_grpc_bridge` - The ML Platform Layer

**Role:** The complete, self-contained ML platform. It knows everything about Python, gRPC, DSPy, Variables, and Tools. It implements the `Snakepit.Adapter` behavior to connect to the infrastructure layer and provides a clean, high-level Elixir API for the consumer layer.

**Key Principle:** **ALL PYTHON CODE LIVES HERE. ALL ML LOGIC LIVES HERE.**

```
snakepit_grpc_bridge/
├── lib/
│   ├── snakepit_grpc_bridge.ex        # Facade for the API modules.
│   └── snakepit_grpc_bridge/
│       ├── adapter.ex                 # THE GLUE: Implements the Snakepit.Adapter behaviour.
│       ├── application.ex             # Starts the platform's services (e.g., gRPC server).
│       ├── api/                       # THE CONTRACT: Clean public APIs for the consumer layer.
│       │   ├── dspy.ex
│       │   ├── sessions.ex
│       │   ├── tools.ex
│       │   └── variables.ex
│       ├── dspy/                      # Elixir-side implementation for DSPy integration.
│       │   ├── integration.ex
│       │   └── schema.ex
│       ├── tools/                     # Elixir-side tool system implementation.
│       │   ├── registry.ex
│       │   └── executor.ex
│       ├── variables/                 # Elixir-side variable system implementation.
│       │   ├── manager.ex
│       │   └── store.ex
│       └── grpc/                      # Elixir gRPC server implementation and client logic.
│           ├── client.ex
│           └── server.ex
├── priv/
│   ├── proto/
│   │   └── snakepit_bridge.proto      # The gRPC contract for Elixir <-> Python communication.
│   └── python/                        # ALL PYTHON CODE.
│       ├── grpc_server.py
│       ├── requirements.txt
│       └── snakepit_bridge/
│           ├── __init__.py
│           ├── base_adapter.py
│           ├── dspy_integration.py
│           ├── serialization.py
│           ├── session_context.py
│           └── ... (all other python files)
└── mix.exs                          # Depends on `snakepit`.
```

---
#### **File & Method Breakdown for `snakepit_grpc_bridge`**

<details>
<summary>Click to expand details for the Platform Layer</summary>

**`lib/snakepit_grpc_bridge/adapter.ex`**
*   `@moduledoc`: Implements the `Snakepit.Adapter` behavior to manage Python gRPC processes.
*   `start_worker(state, worker_id)`: Constructs and executes the `python grpc_server.py ...` command. Manages ports and returns a handle containing the OS PID and gRPC channel.
*   `execute(handle, command, args, opts)`: Creates a `GRPC.Stub`, builds a protobuf message from `command` and `args`, makes the gRPC call, and deserializes the response.
*   `terminate(handle)`: Sends a shutdown signal to the Python process via its OS PID.

**`lib/snakepit_grpc_bridge/api/dspy.ex`**
*   `@moduledoc`: Public API for all DSPy-related operations.
*   `create_module(session_id, module_type, config)`: High-level function to create a DSPy module.
*   `execute_module(session_id, module_ref, inputs, opts)`: Executes a module.
*   `predict(session_id, signature, inputs, opts)`: A convenience for one-shot predictions.
*   `configure_lm(session_id, model_config)`: Configures the language model for a session.

**`lib/snakepit_grpc_bridge/api/tools.ex`**
*   `@moduledoc`: Public API for the bidirectional tool bridge.
*   `register_elixir_tool(session_id, tool_spec, function)`: Exposes an Elixir function to Python.
*   `call_python_tool(session_id, tool_name, args, opts)`: Executes a Python-defined tool from Elixir.
*   `list_tools(session_id)`: Lists all tools (both Elixir and Python) available in a session.

**`lib/snakepit_grpc_bridge/api/variables.ex`**
*   `@moduledoc`: Public API for the cross-language variable system.
*   `set_variable(session_id, name, value, metadata)`: Sets a variable.
*   `get_variable(session_id, name, default)`: Gets a variable.
*   `get_variables(session_id, [names])`: Batch gets multiple variables.

**`lib/snakepit_grpc_bridge/tools/registry.ex`**
*   `@moduledoc`: `GenServer` implementation for registering and looking up Elixir tools.
*   `register(session_id, name, fun, spec)`
*   `lookup(session_id, name)`

**`priv/python/grpc_server.py`**
*   `@moduledoc`: The stateless gRPC server.
*   `ExecuteTool(...)`: The main RPC endpoint. It creates an ephemeral `SessionContext` and an `Adapter` instance for each call, dispatches the request to the adapter's tool, and returns the result. It has no long-lived state.
*   `InitializeSession(...)`: Proxies session management calls back to the Elixir gRPC server.

</details>

---

### Layer 3: `dspex` - The Thin Consumer Layer

**Role:** A lightweight, developer-friendly orchestration layer. It provides high-level convenience functions, macros, and wrappers that make using the platform simple and intuitive.

**Key Principle:** **NO IMPLEMENTATION. NO PYTHON CODE. PURE ORCHESTRATION.**

```
dspex/
├── lib/
│   ├── dspex.ex                    # Main high-level API: ask/1, think/1, solve/2, pipeline/1
│   └── dspex/
│       ├── bridge/                 # Home of the `use DSPex.Bridge.*` macros
│       │   ├── bidirectional.ex
│       │   ├── contract_based.ex
│       │   ├── observable.ex
│       │   ├── result_transform.ex
│       │   └── simple_wrapper.ex
│       ├── config.ex               # Convenience functions for configuring the platform
│       └── session.ex              # Simple session struct and helpers
└── mix.exs                         # Depends on `snakepit_grpc_bridge`.
```

---
#### **File & Method Breakdown for `dspex`**

<details>
<summary>Click to expand details for the Consumer Layer</summary>

**`lib/dspex.ex`**
*   `@moduledoc`: The primary, user-facing API for DSPex.
*   `ask(question, opts)`: A simple, zero-config function that internally calls the platform's `predict` API.
*   `think(question, opts)`: A convenience wrapper around the platform's `ChainOfThought` module.
*   `solve(question, opts)`: A wrapper around the platform's `ReAct` module, simplifying tool setup.
*   `pipeline(operations)`: A macro for defining a sequence of operations that are then executed via the platform.

**`lib/dspex/bridge/simple_wrapper.ex`** (and other `bridge/` modules)
*   `@moduledoc`: Contains the `use DSPex.Bridge.SimpleWrapper` macro and its companions.
*   `wrap_dspy(python_class)`: This macro's implementation changes significantly. Instead of calling `snakepit` directly, it now generates functions that call the clean APIs in `SnakepitGRPCBridge.API.DSPy`.
    ```elixir
    # Inside the generated `create` function
    def create(args \\ %{}) do
      # New implementation:
      # Automatically manages session or uses one from opts
      session_id = DSPex.Session.get_or_create(opts)
      
      # Calls the clean platform API
      SnakepitGRPCBridge.API.DSPy.create_module(
        session_id,
        @python_class,
        %{signature: args.signature} # simplified args
      )
    end
    ```

**`lib/dspex/config.ex`**
*   `@moduledoc`: High-level configuration helpers.
*   `configure(opts)`: A single function that configures the underlying platform, including the language model, by calling `SnakepitGRPCBridge.API.DSPy.configure_lm/2`.

</details>
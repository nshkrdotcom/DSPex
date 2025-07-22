Of course. Here are the detailed technical specifications for the fourth of the five essential missing component layers: the **Python-Side Runtime**.

This document provides the complete design for the Python application that runs inside the `snakepit` worker pool. It is the crucial "other half" of the `dspex` platform, responsible for receiving commands from the Elixir orchestrator, dynamically instantiating and configuring `dspy` modules, executing them, and returning structured results.

---

### **`11_SPEC_PYTHON_SIDE_RUNTIME.md`**

# Technical Specification: The Python-Side Runtime

## 1. Vision and Guiding Principles

The Python-Side Runtime is the execution engine for `dspex`. It acts as a stateless, intelligent agent that is fully controlled and orchestrated by Elixir.

*   **Stateless by Default:** The Python worker should not maintain long-lived state between requests. All state (Cognitive Variables, program configurations) is considered canonical in the Elixir `SessionStore` and is pushed to the worker on-demand for each trial. This makes the system robust and scalable.
*   **Dynamic and Reflective:** The runtime must be ableto dynamically import and instantiate any user-defined `dspy.Module` class. It relies heavily on reflection to apply configurations and execute modules.
*   **Robust Error Handling:** Python-level exceptions (from `dspy`, model providers, or user code) are a primary source of failure. The runtime must catch all exceptions, serialize them into a structured error format, and return them to Elixir as a valid result, not a crash.
*   **Seamless Interoperability:** The runtime is responsible for translating between Elixir's data structures (received as JSON over gRPC) and Python's `dspy` objects (e.g., `dspy.Example`).
*   **Performance-Aware:** While orchestrated by Elixir, the Python runtime should be efficient, especially in its interaction with the `SessionContext` for fetching variable values.

## 2. Core Components

The Python runtime is a single, long-running process (`snakepit_bridge`) that contains two key components:

1.  **`ProgramExecutor`**: The primary gRPC handler class that contains the logic for hydrating, configuring, and executing program specifications sent from Elixir.
2.  **`@dspex.register` Decorator**: A simple decorator to make user-defined `dspy.Module` classes discoverable by the `ProgramExecutor`.

---

## 3. `ProgramExecutor`: The Execution Engine

The `ProgramExecutor` is the heart of the Python runtime. It's the gRPC service implementation that listens for commands from the `TrialRunner` in Elixir.

### 3.1. Purpose

*   To provide a gRPC endpoint (`ExecuteProgram`) that serves as the entry point for all trial executions.
*   To encapsulate the complex logic of dynamically building and running a `dspy` program based on a declarative specification.
*   To ensure that every execution is properly instrumented, timed, and that all results and errors are captured and returned in a structured format.

### 3.2. Public API (gRPC Service Definition)

The `ProgramExecutor` implements the `SnakepitBridge` gRPC service. Its most important RPC is `ExecuteProgram`.

```protobuf
// A simplified view of the gRPC service interaction
service SnakepitBridge {
    rpc ExecuteProgram(ExecuteProgramRequest) returns (ExecuteProgramResponse);
}

message ExecuteProgramRequest {
    string session_id = 1;
    ProgramSpecification program_spec = 2;
    map<string, google.protobuf.Any> inputs = 3;
}

message ExecuteProgramResponse {
    oneof result {
        TrialSuccess success = 1;
        TrialFailure failure = 2;
    }
}
```

### 3.3. Internal Logic and Workflow of `ExecuteProgram`

This is the detailed, step-by-step process the `ProgramExecutor` follows upon receiving a request from the Elixir `TrialRunner`.

**Input**: An `ExecuteProgramRequest` containing:
*   `session_id`: The ID of the session, used to connect to the correct `SessionContext`.
*   `program_spec`: A JSON object representing the `DSPex.Program` struct.
*   `inputs`: The input fields for this specific trial (e.g., `{"question": "What is DSPy?"}`).

**Workflow:**

1.  **Get Session Context:**
    *   It uses the `session_id` to look up the corresponding `SessionContext` instance. This gives it access to the variable cache and the gRPC stub for that session.

2.  **Hydrate Program:** This is the dynamic instantiation step.
    *   **Import Module:** It takes the `python_class` string from the `program_spec` (e.g., `"my_research.agents.CustomReAct"`) and uses Python's `importlib` to dynamically import the class.
    *   **Instantiate Module:** It calls the constructor of the imported class, passing any `dependencies` from the `program_spec` (e.g., `dspy.ReAct(tools=[...])`).
    *   **Apply Mixin:** It dynamically applies the `VariableAwareMixin` to the newly created module instance. This gives the instance the `.bind_to_variable()` and `.sync_variables()` methods.
    *   **Bind to Configuration Space:** If the `program_spec` specifies a `config_space`, it iterates through the parameters of the module and binds them to the corresponding variables in the `SessionContext` using `module.bind_to_variable(param_name, var_name)`.

3.  **Synchronize State:**
    *   It calls `await module.sync_variables()`.
    *   This crucial step triggers the `VariableAwareMixin` to fetch the *latest* values for all bound variables for this specific trial from the `SessionContext` (which in turn gets them from the `SessionStore` via gRPC). This ensures the program is configured exactly as the Elixir orchestrator intends for this trial.

4.  **Execute and Instrument:**
    *   It starts a timer.
    *   It wraps the execution in a `try...except` block to catch *all* possible exceptions.
    *   It calls the module's `forward()` or `__call__()` method with the `inputs` from the request.
    *   It stops the timer.

5.  **Capture and Serialize Results:**
    *   **On Success:**
        *   It captures the `dspy.Prediction` object returned by the module.
        *   It captures the full execution trace from `dspy.settings.trace`.
        *   It serializes the prediction, trace, latency, and cost into a `TrialSuccess` protobuf message.
    *   **On Failure:**
        *   It catches the exception.
        *   It captures the exception type, message, and a formatted traceback.
        *   It serializes this information into a `TrialFailure` protobuf message.

6.  **Return Response:**
    *   It sends the `TrialSuccess` or `TrialFailure` message back to the Elixir `TrialRunner`.

### 3.4. Code Sketch of `ProgramExecutor`

```python
# In snakepit_bridge/executor.py

import importlib
import traceback
from dspy.predict.predict import Predict
from .session_context import SessionContext
from .dspy_integration import VariableAwareMixin
from .serialization import serialize_dspy_prediction, serialize_dspy_trace

class ProgramExecutor:
    """Orchestrates the dynamic execution of dspy modules."""

    def __init__(self):
        # In a real implementation, this would be a map of session_id -> SessionContext
        self.sessions = {}

    def _get_session_context(self, session_id: str) -> SessionContext:
        # In reality, this would connect to the gRPC channel for that session
        if session_id not in self.sessions:
            self.sessions[session_id] = SessionContext(session_id, channel=None) # Channel would be managed
        return self.sessions[session_id]

    async def execute_program(self, request):
        """Main gRPC handler for running a single trial."""
        try:
            session_context = self._get_session_context(request.session_id)
            program_spec = request.program_spec
            inputs = request.inputs

            # 1. Hydrate Program
            module_instance = self._hydrate_program(program_spec, session_context)

            # 2. Synchronize State
            await module_instance.sync_variables()

            # 3. Execute and Instrument
            # This part needs to capture the trace correctly
            # dspy.settings.configure(trace=[])
            prediction = module_instance(**inputs)
            # trace = dspy.settings.trace

            # 4. Serialize and Return Success
            return {
                "success": {
                    "prediction": serialize_dspy_prediction(prediction),
                    # "trace": serialize_dspy_trace(trace)
                }
            }

        except Exception as e:
            # 5. Serialize and Return Failure
            return {
                "failure": {
                    "error_type": type(e).__name__,
                    "error_message": str(e),
                    "traceback": traceback.format_exc()
                }
            }

    def _hydrate_program(self, spec: dict, context: SessionContext) -> Predict:
        """Dynamically instantiates and configures a dspy module."""
        class_path = spec['python_class']
        module_name, class_name = class_path.rsplit('.', 1)
        
        # Import the class
        module = importlib.import_module(module_name)
        program_class = getattr(module, class_name)

        # Instantiate with dependencies
        dependencies = spec.get('dependencies', {})
        instance = program_class(**dependencies)

        # Apply the VariableAwareMixin dynamically
        # This is a bit of metaprogramming magic
        instance.__class__ = type(
            f"VariableAware{class_name}",
            (VariableAwareMixin, program_class),
            {}
        )
        instance.__init__(session_context=context, **dependencies) # Re-init with mixin

        # Bind to its configuration space
        if 'config_space' in spec:
            # In a real implementation, this would be more robust
            # and loop through defined parameters.
            asyncio.run(instance.bind_to_variable("temperature", "temperature"))
            asyncio.run(instance.bind_to_variable("max_tokens", "max_tokens"))

        return instance
```

---

## 4. `@dspex.register` Decorator: Module Discovery

This is a simple but crucial part of the developer experience, making custom modules available to the runtime.

### 4.1. Purpose

*   To create a simple, non-intrusive way for developers to make their custom `dspy.Module` classes discoverable by `dspex`.
*   To avoid complex configuration files or manual registration steps.

### 4.2. Implementation

```python
# In a new file, dspex_module_registry.py

MODULE_REGISTRY = {}

def register(name: str):
    """
    A decorator to register a custom dspy.Module with the DSPex runtime.
    
    Example:
    
    @dspex.register("MyCustomReAct")
    class MyCustomReAct(dspy.ReAct):
        ...
    """
    def decorator(cls):
        if not issubclass(cls, dspy.Module):
            raise TypeError("Only dspy.Module subclasses can be registered.")
        
        if name in MODULE_REGISTRY:
            raise ValueError(f"Module '{name}' is already registered.")
            
        MODULE_REGISTRY[name] = cls
        return cls
    return decorator

def get_module_class(name: str):
    """Retrieves a registered module class by name."""
    if name not in MODULE_REGISTRY:
        raise KeyError(f"No dspy.Module registered with name '{name}'.")
    return MODULE_REGISTRY[name]
```

The `ProgramExecutor` would be modified to use this registry: `program_class = get_module_class(class_name)` instead of a direct `importlib` call. This provides a more secure and managed way of instantiating code.

## 5. Conclusion

The Python-Side Runtime is the hands of the `dspex` brain. It is a sophisticated, dynamic, and resilient engine designed to execute instructions from the Elixir orchestrator with precision.

By implementing the `ProgramExecutor` with its dynamic hydration and state synchronization workflow, and providing a simple `@dspex.register` decorator for custom modules, we create a seamless and powerful bridge between the two languages. This layer is the final, essential piece that translates the high-level scientific and optimization goals defined in Elixir into concrete `dspy` executions in Python, enabling the entire `dspex` vision.

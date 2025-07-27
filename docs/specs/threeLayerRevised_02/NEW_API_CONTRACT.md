# NEW_API_CONTRACT.md
## The New API Contract

**Objective:** Formal contract defining the public API of the new `snakepit_grpc_bridge` platform layer.

---

## Overview

This document defines the complete public API surface of the SnakepitGRPCBridge platform layer. All consumer interactions with the ML platform must go through these APIs. The contract ensures clean separation between layers and enables independent evolution.

---

## Core API Modules

### SnakepitGRPCBridge.API.DSPy

Primary interface for DSPy operations.

```elixir
defmodule SnakepitGRPCBridge.API.DSPy do
  @moduledoc """
  High-level API for DSPy operations.
  
  Provides access to DSPy modules, predictions, and ML workflows
  through a clean, platform-agnostic interface.
  """

  @type session_id :: String.t()
  @type module_ref :: String.t()
  @type signature :: String.t() | map()
  @type prediction_result :: %{
    required(:result) => map(),
    optional(:metadata) => map(),
    optional(:usage) => usage_info()
  }
  @type usage_info :: %{
    optional(:tokens) => %{input: integer(), output: integer()},
    optional(:latency_ms) => integer()
  }
  @type error :: {:error, :session_not_found | :invalid_signature | :execution_failed | term()}

  @doc """
  Create a DSPy module instance.
  
  ## Parameters
    - session_id: Session identifier for state management
    - module_type: DSPy module class (e.g., "dspy.Predict", "dspy.ChainOfThought")
    - config: Module configuration including signature and options
    
  ## Examples
      iex> create_module("session-123", "dspy.Predict", %{signature: "question -> answer"})
      {:ok, "module_abc123"}
  """
  @spec create_module(session_id(), String.t(), map()) :: {:ok, module_ref()} | error()
  
  @doc """
  Execute a module with given inputs.
  
  ## Parameters
    - session_id: Session identifier
    - module_ref: Reference to created module
    - inputs: Input data matching module signature
    - opts: Execution options (timeout, streaming, etc.)
    
  ## Options
    - :timeout - Maximum execution time in milliseconds (default: 30000)
    - :stream - Enable streaming response (default: false)
    - :trace - Include execution trace (default: false)
  """
  @spec execute_module(session_id(), module_ref(), map(), keyword()) :: {:ok, prediction_result()} | error()
  
  @doc """
  Execute a one-shot prediction without creating a module.
  
  Convenience function for simple predictions.
  """
  @spec predict(session_id(), signature(), map(), keyword()) :: {:ok, prediction_result()} | error()
  
  @doc """
  Stream execution results.
  
  ## Parameters
    - session_id: Session identifier
    - module_ref: Module reference
    - inputs: Input data
    - callback: Function called for each streaming chunk
    - opts: Streaming options
    
  The callback receives: {:chunk, data} | {:done, final_result} | {:error, reason}
  """
  @spec execute_stream(session_id(), module_ref(), map(), function(), keyword()) :: :ok | error()
  
  @doc """
  Get module metadata including signature and configuration.
  """
  @spec get_module_info(session_id(), module_ref()) :: {:ok, map()} | error()
  
  @doc """
  List all modules in a session.
  """
  @spec list_modules(session_id()) :: {:ok, [module_ref()]} | error()
  
  @doc """
  Delete a module instance.
  """
  @spec delete_module(session_id(), module_ref()) :: :ok | error()
  
  @doc """
  Configure language model for a session.
  
  ## Parameters
    - session_id: Session identifier
    - model_config: Model configuration
    
  ## Model Config
    - :provider - "openai", "gemini", "anthropic", etc.
    - :model - Model name (e.g., "gpt-4", "gemini-pro")
    - :api_key - API key for the provider
    - :options - Provider-specific options
  """
  @spec configure_lm(session_id(), map()) :: :ok | error()
  
  @doc """
  Get current language model configuration.
  """
  @spec get_lm_config(session_id()) :: {:ok, map()} | error()
end
```

### SnakepitGRPCBridge.API.Variables

Variable management across language boundaries.

```elixir
defmodule SnakepitGRPCBridge.API.Variables do
  @moduledoc """
  Cross-language variable management API.
  
  Enables sharing of data between Elixir and Python, with automatic
  serialization and type conversion.
  """
  
  @type session_id :: String.t()
  @type var_name :: String.t()
  @type var_value :: term()
  @type var_type :: :string | :integer | :float | :boolean | :list | :map | 
                    :tensor | :embedding | :module_ref
  @type var_metadata :: %{
    optional(:type) => var_type(),
    optional(:shape) => [integer()],
    optional(:constraints) => map(),
    optional(:description) => String.t()
  }
  @type error :: {:error, :session_not_found | :variable_not_found | :type_mismatch | term()}

  @doc """
  Set a variable in the session.
  
  ## Parameters
    - session_id: Session identifier
    - name: Variable name
    - value: Variable value (automatically serialized)
    - metadata: Optional type and constraint information
    
  ## Examples
      iex> set_variable("session-123", "temperature", 0.7, %{type: :float, constraints: %{min: 0, max: 2}})
      :ok
  """
  @spec set_variable(session_id(), var_name(), var_value(), var_metadata()) :: :ok | error()
  
  @doc """
  Get a variable from the session.
  
  ## Parameters
    - session_id: Session identifier  
    - name: Variable name
    - default: Default value if variable not found
    
  ## Examples
      iex> get_variable("session-123", "temperature", 0.5)
      {:ok, 0.7}
  """
  @spec get_variable(session_id(), var_name(), var_value()) :: {:ok, var_value()} | error()
  
  @doc """
  Update a variable using a function.
  
  ## Parameters
    - session_id: Session identifier
    - name: Variable name  
    - update_fn: Function that takes current value and returns new value
    
  ## Examples
      iex> update_variable("session-123", "counter", &(&1 + 1))
      {:ok, 2}
  """
  @spec update_variable(session_id(), var_name(), (var_value() -> var_value())) :: {:ok, var_value()} | error()
  
  @doc """
  Delete a variable from the session.
  """
  @spec delete_variable(session_id(), var_name()) :: :ok | error()
  
  @doc """
  List all variables in a session.
  
  Returns a map of variable names to their metadata.
  """
  @spec list_variables(session_id()) :: {:ok, %{var_name() => var_metadata()}} | error()
  
  @doc """
  Get multiple variables at once.
  
  More efficient than multiple get_variable calls.
  """
  @spec get_variables(session_id(), [var_name()]) :: {:ok, %{var_name() => var_value()}} | error()
  
  @doc """
  Set multiple variables at once.
  
  Atomic operation - all succeed or all fail.
  """
  @spec set_variables(session_id(), %{var_name() => var_value()}) :: :ok | error()
  
  @doc """
  Clear all variables in a session.
  """
  @spec clear_variables(session_id()) :: :ok | error()
  
  @doc """
  Export variables for persistence.
  
  Returns a serialized representation of all variables.
  """
  @spec export_variables(session_id()) :: {:ok, binary()} | error()
  
  @doc """
  Import variables from a previous export.
  """
  @spec import_variables(session_id(), binary()) :: :ok | error()
end
```

### SnakepitGRPCBridge.API.Tools

Bidirectional tool bridge for cross-language function calls.

```elixir
defmodule SnakepitGRPCBridge.API.Tools do
  @moduledoc """
  Bidirectional tool bridge API.
  
  Enables Python to call Elixir functions and vice versa,
  with automatic serialization and error handling.
  """
  
  @type session_id :: String.t()
  @type tool_name :: String.t()
  @type tool_spec :: %{
    required(:name) => String.t(),
    required(:description) => String.t(),
    required(:parameters) => [param_spec()],
    optional(:returns) => return_spec(),
    optional(:examples) => [example()]
  }
  @type param_spec :: %{
    name: String.t(),
    type: String.t(),
    description: String.t(),
    required: boolean()
  }
  @type return_spec :: %{type: String.t(), description: String.t()}
  @type example :: %{inputs: map(), output: term()}
  @type error :: {:error, :session_not_found | :tool_not_found | :execution_failed | term()}

  @doc """
  Register an Elixir function as a tool callable from Python.
  
  ## Parameters
    - session_id: Session identifier
    - tool_spec: Tool specification
    - function: The Elixir function to expose
    
  ## Examples
      iex> register_tool("session-123", 
      ...>   %{name: "calculate_tax", description: "Calculate tax amount"},
      ...>   &MyModule.calculate_tax/2)
      :ok
  """
  @spec register_tool(session_id(), tool_spec(), function()) :: :ok | error()
  
  @doc """
  Execute a tool (can be called from Python via bridge).
  
  ## Parameters
    - session_id: Session identifier
    - tool_name: Name of the tool to execute
    - args: Arguments as a map
    - opts: Execution options
  """
  @spec execute_tool(session_id(), tool_name(), map(), keyword()) :: {:ok, term()} | error()
  
  @doc """
  List available tools in a session.
  
  Returns tool specifications that can be used for discovery.
  """
  @spec list_tools(session_id()) :: {:ok, [tool_spec()]} | error()
  
  @doc """
  Unregister a tool.
  """
  @spec unregister_tool(session_id(), tool_name()) :: :ok | error()
  
  @doc """
  Register a Python function as callable from Elixir.
  
  ## Parameters
    - session_id: Session identifier
    - tool_name: Name for the Python tool
    - python_spec: Python function specification
    
  ## Python Spec
    - :module - Python module name
    - :function - Function name
    - :description - What the function does
  """
  @spec register_python_tool(session_id(), tool_name(), map()) :: :ok | error()
  
  @doc """
  Call a Python tool from Elixir.
  
  ## Examples
      iex> call_python_tool("session-123", "sklearn_predict", %{data: [[1, 2, 3]]})
      {:ok, %{"predictions" => [0.95]}}
  """
  @spec call_python_tool(session_id(), tool_name(), map(), keyword()) :: {:ok, term()} | error()
  
  @doc """
  Enable tool discovery for DSPy ReAct/Tool use.
  
  Makes all registered tools available to DSPy modules that use tools.
  """
  @spec enable_tool_discovery(session_id()) :: :ok | error()
end
```

### SnakepitGRPCBridge.API.Sessions

Session lifecycle management.

```elixir
defmodule SnakepitGRPCBridge.API.Sessions do
  @moduledoc """
  Session management API.
  
  Sessions provide isolated contexts for ML workflows, maintaining
  state, variables, and configuration across operations.
  """
  
  @type session_id :: String.t()
  @type session_info :: %{
    id: session_id(),
    created_at: DateTime.t(),
    last_accessed: DateTime.t(),
    metadata: map(),
    stats: session_stats()
  }
  @type session_stats :: %{
    variable_count: integer(),
    module_count: integer(),
    tool_count: integer(),
    execution_count: integer()
  }
  @type session_options :: [
    ttl: integer(),
    metadata: map(),
    persist: boolean()
  ]
  @type error :: {:error, :session_not_found | :session_exists | term()}

  @doc """
  Create a new session.
  
  ## Options
    - :ttl - Time to live in seconds (default: 3600)
    - :metadata - Arbitrary metadata to store with session
    - :persist - Enable persistence across restarts
    
  ## Examples
      iex> create_session("my-session", ttl: 7200, metadata: %{user_id: "123"})
      {:ok, "my-session"}
  """
  @spec create_session(session_id(), session_options()) :: {:ok, session_id()} | error()
  
  @doc """
  Create a session with auto-generated ID.
  """
  @spec create_session(session_options()) :: {:ok, session_id()}
  
  @doc """
  Get session information.
  """
  @spec get_session(session_id()) :: {:ok, session_info()} | error()
  
  @doc """
  Update session metadata.
  """
  @spec update_session_metadata(session_id(), map()) :: :ok | error()
  
  @doc """
  Delete a session and all associated data.
  """
  @spec delete_session(session_id()) :: :ok | error()
  
  @doc """
  List all active sessions.
  """
  @spec list_sessions() :: {:ok, [session_info()]}
  
  @doc """
  Extend session TTL.
  """
  @spec touch_session(session_id()) :: :ok | error()
  
  @doc """
  Clone a session with all its state.
  
  Useful for creating variations or checkpoints.
  """
  @spec clone_session(session_id(), session_id()) :: {:ok, session_id()} | error()
  
  @doc """
  Export session state for backup or migration.
  """
  @spec export_session(session_id()) :: {:ok, binary()} | error()
  
  @doc """
  Import session from export.
  """
  @spec import_session(binary(), session_id()) :: {:ok, session_id()} | error()
  
  @doc """
  Set session affinity for worker routing.
  
  Ensures session requests go to the same worker for performance.
  """
  @spec set_worker_affinity(session_id(), String.t()) :: :ok | error()
end
```

---

## Integration Patterns

### Session-Based Workflow
```elixir
# Create session
{:ok, session_id} = SnakepitGRPCBridge.API.Sessions.create_session()

# Configure language model
:ok = SnakepitGRPCBridge.API.DSPy.configure_lm(session_id, %{
  provider: "gemini",
  model: "gemini-pro",
  api_key: System.get_env("GEMINI_API_KEY")
})

# Set variables
:ok = SnakepitGRPCBridge.API.Variables.set_variable(session_id, "context", context_data)

# Create module
{:ok, module_ref} = SnakepitGRPCBridge.API.DSPy.create_module(
  session_id,
  "dspy.ChainOfThought", 
  %{signature: "question, context -> answer"}
)

# Execute with variables
{:ok, result} = SnakepitGRPCBridge.API.DSPy.execute_module(
  session_id,
  module_ref,
  %{question: "What is the main topic?"}
)
```

### Tool Integration
```elixir
# Register Elixir tools
SnakepitGRPCBridge.API.Tools.register_tool(
  session_id,
  %{
    name: "fetch_data",
    description: "Fetch data from database",
    parameters: [%{name: "query", type: "string", required: true}]
  },
  &MyApp.fetch_data/1
)

# Enable for DSPy
SnakepitGRPCBridge.API.Tools.enable_tool_discovery(session_id)

# Use in ReAct module
{:ok, module_ref} = SnakepitGRPCBridge.API.DSPy.create_module(
  session_id,
  "dspy.ReAct",
  %{signature: "question -> answer", tools: :auto_discover}
)
```

---

## Error Handling

All API functions follow consistent error patterns:

```elixir
# Success
{:ok, result}

# Common errors
{:error, :session_not_found}      # Session doesn't exist
{:error, :invalid_arguments}      # Bad input data
{:error, :timeout}               # Operation timed out
{:error, {:execution_failed, details}}  # Runtime error

# Error metadata
{:error, {reason, %{
  session_id: "...",
  operation: :execute_module,
  details: "...",
  timestamp: ~U[2024-01-26 10:00:00Z]
}}}
```

---

## Telemetry Events

All API operations emit telemetry events:

```elixir
# Operation start
[:snakepit_grpc_bridge, :api, :operation, :start]
%{system_time: integer()}
%{session_id: String.t(), operation: atom()}

# Operation stop
[:snakepit_grpc_bridge, :api, :operation, :stop]
%{duration: integer()}
%{session_id: String.t(), operation: atom(), result: :ok | :error}

# Operation exception
[:snakepit_grpc_bridge, :api, :operation, :exception]
%{duration: integer()}
%{session_id: String.t(), operation: atom(), error: term()}
```

---

## Versioning

The API follows semantic versioning:
- Major version changes indicate breaking changes
- Minor version changes add functionality in a backward-compatible manner
- Patch version changes are backward-compatible bug fixes

Current version: 1.0.0

---

## Migration Path

For existing DSPex users:

1. DSPex functions will delegate to these APIs
2. Deprecation warnings will guide migration
3. A compatibility layer maintains existing behavior
4. Direct platform API usage offers more features and better performance

This contract ensures clean separation between layers while providing all necessary functionality for ML workflows.
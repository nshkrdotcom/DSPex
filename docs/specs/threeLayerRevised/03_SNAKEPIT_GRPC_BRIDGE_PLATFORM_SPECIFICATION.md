# SnakepitGRPCBridge ML Platform Specification

## Overview

SnakepitGRPCBridge is the **complete ML execution platform** built on Snakepit infrastructure. It contains all domain-specific functionality for machine learning workflows including variables, tools, DSPy integration, and Python bridge components.

## Core Principles

### 1. Complete ML Platform
- **All** ML-related functionality lives here
- Variables system with ML data types (tensors, embeddings, etc.)
- Complete tool bridge for Python ↔ Elixir communication
- Full DSPy integration with enhanced features
- **All** Python code

### 2. Clean APIs for Consumers
- Well-defined API modules for DSPex and other consumers
- Abstracts complexity of underlying ML operations
- Provides both simple and advanced usage patterns

### 3. Independent Evolution
- Fast-moving development (new ML features)
- Can evolve ML capabilities without affecting infrastructure
- Depends on stable Snakepit infrastructure

## Module Architecture

### Platform Structure
```
snakepit_grpc_bridge/
├── lib/snakepit_grpc_bridge/
│   ├── adapter.ex                    # Snakepit adapter implementation
│   ├── application.ex                # OTP application
│   ├── api/                          # CLEAN APIs FOR CONSUMERS
│   │   ├── variables.ex              # Variable management API
│   │   ├── tools.ex                  # Tool bridge API
│   │   ├── dspy.ex                   # DSPy integration API
│   │   └── sessions.ex               # Session management API
│   ├── variables/                    # COMPLETE VARIABLE SYSTEM
│   │   ├── manager.ex                # Variable lifecycle management
│   │   ├── types.ex                  # ML data types and serialization
│   │   ├── storage.ex                # Variable storage backend
│   │   ├── registry.ex               # Variable registry and discovery
│   │   └── ml_types/                 # Specialized ML type handlers
│   │       ├── tensor.ex             # Tensor variable type
│   │       ├── embedding.ex          # Embedding variable type
│   │       └── model.ex              # Model variable type
│   ├── tools/                        # COMPLETE TOOL BRIDGE
│   │   ├── registry.ex               # Tool registration and discovery
│   │   ├── executor.ex               # Tool execution engine
│   │   ├── bridge.ex                 # Python ↔ Elixir bridge
│   │   ├── serialization.ex          # Tool argument serialization
│   │   └── validation.ex             # Tool validation and type checking
│   ├── dspy/                         # COMPLETE DSPY INTEGRATION
│   │   ├── integration.ex            # Core DSPy bridge functionality
│   │   ├── workflows.ex              # DSPy workflow patterns
│   │   ├── enhanced.ex               # Enhanced DSPy features
│   │   ├── schema.ex                 # DSPy schema discovery
│   │   ├── optimization.ex           # DSPy optimization features
│   │   └── codegen.ex                # Code generation for DSPy
│   ├── grpc/                         # GRPC INFRASTRUCTURE
│   │   ├── client.ex                 # gRPC client for Python communication
│   │   ├── server.ex                 # gRPC server implementation
│   │   └── protocols.ex              # ML-specific protocol definitions
│   ├── python/                       # PYTHON WORKER MANAGEMENT
│   │   └── process.ex                # GenServer managing a Python OS process via a Port
│   └── telemetry.ex                  # Platform telemetry
├── priv/
│   ├── proto/
│   │   └── ml_bridge.proto           # ML-specific gRPC protocol
│   └── python/                       # ALL PYTHON CODE
│       └── snakepit_bridge/
│           ├── __init__.py
│           ├── core/                 # Core bridge functionality
│           │   ├── __init__.py
│           │   ├── bridge.py         # Main bridge implementation
│           │   ├── grpc_server.py    # gRPC server
│           │   └── session.py        # Session management
│           ├── variables/            # Python variable management
│           │   ├── __init__.py
│           │   ├── manager.py        # Variable management
│           │   ├── types.py          # Variable type system
│           │   └── serialization.py # Variable serialization
│           ├── tools/                # Python tool execution
│           │   ├── __init__.py
│           │   ├── registry.py       # Tool registry
│           │   ├── executor.py       # Tool execution
│           │   └── bridge.py         # Elixir communication
│           └── dspy/                 # Python DSPy integration
│               ├── __init__.py
│               ├── integration.py    # DSPy integration
│               ├── enhanced.py       # Enhanced DSPy features
│               └── adapters.py       # DSPy adapters
├── test/
└── mix.exs                           # Depends on snakepit
```

## Detailed Module Specifications

### 1. Snakepit Adapter (`lib/snakepit_grpc_bridge/adapter.ex`)

```elixir
defmodule SnakepitGRPCBridge.Adapter do
  @moduledoc """
  Snakepit adapter that routes commands to ML platform functionality.
  
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

    # Route command to appropriate ML platform module
    result = case command do
      # DSPy operations
      "call_dspy" -> 
        SnakepitGRPCBridge.DSPy.Integration.call_dspy(
          args["class_path"], 
          args["method"], 
          args["args"] || [], 
          args["kwargs"] || %{}, 
          opts
        )
      
      "discover_dspy_schema" -> 
        SnakepitGRPCBridge.DSPy.Schema.discover_schema(args["module_path"], opts)
      
      "enhanced_predict" -> 
        SnakepitGRPCBridge.DSPy.Enhanced.predict(session_id, args, opts)
      
      "enhanced_chain_of_thought" -> 
        SnakepitGRPCBridge.DSPy.Enhanced.chain_of_thought(session_id, args, opts)
      
      # Variable operations
      "get_variable" -> 
        SnakepitGRPCBridge.Variables.Manager.get(session_id, args["identifier"], args["default"])
      
      "set_variable" -> 
        SnakepitGRPCBridge.Variables.Manager.set(session_id, args["identifier"], args["value"], opts)
      
      "list_variables" -> 
        SnakepitGRPCBridge.Variables.Manager.list(session_id)
      
      "create_variable" -> 
        SnakepitGRPCBridge.Variables.Manager.create(
          session_id, args["name"], args["type"], args["value"], opts
        )
      
      # Tool operations
      "register_elixir_tool" -> 
        SnakepitGRPCBridge.Tools.Registry.register_tool(
          session_id, args["name"], args["function"], args["metadata"]
        )
      
      "list_elixir_tools" -> 
        SnakepitGRPCBridge.Tools.Registry.list_tools(session_id)
      
      "call_elixir_tool" -> 
        SnakepitGRPCBridge.Tools.Executor.execute_tool(
          session_id, args["tool_name"], args["parameters"]
        )
      
      # Session management
      "initialize_session" -> 
        SnakepitGRPCBridge.Variables.Manager.initialize_session(session_id, args, opts)
      
      "cleanup_session" -> 
        SnakepitGRPCBridge.Variables.Manager.cleanup_session(session_id)
      
      "get_session_info" -> 
        SnakepitGRPCBridge.Variables.Manager.get_session_info(session_id)
      
      # Unknown command
      _ -> 
        Logger.warning("Unknown ML command received: #{command}", command: command, session_id: session_id)
        {:error, {:unknown_command, command}}
    end

    # Collect execution telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_platform_telemetry(command, args, result, execution_time, session_id, worker_pid)

    result
  end

  @impl Snakepit.Adapter
  def execute_stream(command, args, callback_fn, opts) do
    session_id = opts[:session_id]
    
    case command do
      "streaming_inference" -> 
        SnakepitGRPCBridge.DSPy.Enhanced.streaming_inference(
          session_id, args, callback_fn, opts
        )
      
      "batch_processing" -> 
        SnakepitGRPCBridge.Tools.Executor.stream_batch(
          session_id, args, callback_fn, opts
        )
      
      _ -> 
        {:error, {:streaming_not_supported, command}}
    end
  end

  @impl Snakepit.Adapter
  def init(config) do
    Logger.info("Initializing SnakepitGRPCBridge ML platform")
    
    # Initialize platform components
    with {:ok, grpc_config} <- setup_grpc_infrastructure(config),
         {:ok, python_bridge} <- initialize_python_bridge(config),
         {:ok, variable_system} <- initialize_variable_system(config),
         {:ok, tool_system} <- initialize_tool_system(config),
         {:ok, dspy_system} <- initialize_dspy_system(config) do
      
      adapter_state = %{
        grpc_config: grpc_config,
        python_bridge: python_bridge,
        variable_system: variable_system,
        tool_system: tool_system,
        dspy_system: dspy_system,
        telemetry_collector: SnakepitGRPCBridge.Telemetry.new_collector(:platform),
        started_at: DateTime.utc_now()
      }
      
      Logger.info("SnakepitGRPCBridge ML platform initialized successfully")
      {:ok, adapter_state}
    else
      {:error, reason} -> 
        Logger.error("Failed to initialize SnakepitGRPCBridge platform: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Snakepit.Adapter
  def terminate(_reason, adapter_state) do
    Logger.info("Terminating SnakepitGRPCBridge ML platform")
    
    # Clean up platform components
    cleanup_dspy_system(adapter_state.dspy_system)
    cleanup_tool_system(adapter_state.tool_system)
    cleanup_variable_system(adapter_state.variable_system)
    cleanup_python_bridge(adapter_state.python_bridge)
    cleanup_grpc_infrastructure(adapter_state.grpc_config)
    
    Logger.info("SnakepitGRPCBridge ML platform terminated successfully")
    :ok
  end

  @impl Snakepit.Adapter
  def start_worker(adapter_state, worker_id) do
    # Start ML platform worker
    worker_config = %{
      worker_id: worker_id,
      grpc_config: adapter_state.grpc_config,
      python_bridge: adapter_state.python_bridge,
      variable_system: adapter_state.variable_system,
      tool_system: adapter_state.tool_system,
      dspy_system: adapter_state.dspy_system
    }
    
    case SnakepitGRPCBridge.Worker.start_link(worker_config) do
      {:ok, worker_pid} ->
        Logger.debug("Started ML platform worker #{worker_id}", worker_id: worker_id, worker_pid: worker_pid)
        {:ok, worker_pid}
      {:error, reason} ->
        Logger.error("Failed to start ML platform worker #{worker_id}: #{inspect(reason)}", 
                    worker_id: worker_id, reason: reason)
        {:error, reason}
    end
  end

  # Private implementation functions
  defp setup_grpc_infrastructure(config) do
    grpc_config = %{
      port: Keyword.get(config, :grpc_port, 0),
      timeout: Keyword.get(config, :grpc_timeout, 30_000)
    }
    
    case SnakepitGRPCBridge.GRPC.Client.start(grpc_config) do
      {:ok, client_state} ->
        {:ok, Map.put(grpc_config, :client_state, client_state)}
      {:error, reason} ->
        {:error, {:grpc_setup_failed, reason}}
    end
  end

  defp initialize_python_bridge(config) do
    python_config = %{
      executable: Keyword.get(config, :python_executable, "python3"),
      bridge_script: Keyword.get(config, :bridge_script, :auto_detect),
      timeout: Keyword.get(config, :python_timeout, 60_000)
    }
    
    case SnakepitGRPCBridge.Python.Bridge.start(python_config) do
      {:ok, bridge_state} ->
        {:ok, bridge_state}
      {:error, reason} ->
        {:error, {:python_bridge_failed, reason}}
    end
  end

  defp initialize_variable_system(config) do
    variable_config = Keyword.get(config, :variables, %{})
    
    case SnakepitGRPCBridge.Variables.Manager.start_link(variable_config) do
      {:ok, manager_pid} ->
        {:ok, %{manager_pid: manager_pid, config: variable_config}}
      {:error, reason} ->
        {:error, {:variable_system_failed, reason}}
    end
  end

  defp initialize_tool_system(config) do
    tool_config = Keyword.get(config, :tools, %{})
    
    case SnakepitGRPCBridge.Tools.Registry.start_link(tool_config) do
      {:ok, registry_pid} ->
        {:ok, %{registry_pid: registry_pid, config: tool_config}}
      {:error, reason} ->
        {:error, {:tool_system_failed, reason}}
    end
  end

  defp initialize_dspy_system(config) do
    dspy_config = Keyword.get(config, :dspy, %{})
    
    case SnakepitGRPCBridge.DSPy.Integration.start_link(dspy_config) do
      {:ok, integration_pid} ->
        {:ok, %{integration_pid: integration_pid, config: dspy_config}}
      {:error, reason} ->
        {:error, {:dspy_system_failed, reason}}
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
    
    :telemetry.execute([:snakepit_grpc_bridge, :platform, :execution], telemetry_data)
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

  # Cleanup functions (placeholders for now)
  defp cleanup_dspy_system(_system), do: :ok
  defp cleanup_tool_system(_system), do: :ok
  defp cleanup_variable_system(_system), do: :ok
  defp cleanup_python_bridge(_bridge), do: :ok
  defp cleanup_grpc_infrastructure(_config), do: :ok
end
```

### 2. Variables API (`lib/snakepit_grpc_bridge/api/variables.ex`)

```elixir
defmodule SnakepitGRPCBridge.API.Variables do
  @moduledoc """
  Clean API for variable management operations.
  
  This is the primary interface that DSPex and other consumers use
  for variable operations.
  """

  @doc """
  Create a new variable in the session.
  
  ## Examples
  
      {:ok, variable} = SnakepitGRPCBridge.API.Variables.create(
        session_id, 
        "temperature", 
        :float, 
        0.7,
        description: "LLM temperature parameter"
      )
  """
  @spec create(String.t(), String.t(), atom(), term(), keyword()) :: 
    {:ok, map()} | {:error, term()}
  def create(session_id, name, type, value, opts \\ []) do
    SnakepitGRPCBridge.Variables.Manager.create(session_id, name, type, value, opts)
  end

  @doc """
  Get variable value from session.
  
  ## Examples
  
      {:ok, 0.7} = SnakepitGRPCBridge.API.Variables.get(session_id, "temperature")
      {:ok, 1.0} = SnakepitGRPCBridge.API.Variables.get(session_id, "unknown", 1.0)
  """
  @spec get(String.t(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def get(session_id, identifier, default \\ nil) do
    SnakepitGRPCBridge.Variables.Manager.get(session_id, identifier, default)
  end

  @doc """
  Set variable value in session.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.API.Variables.set(session_id, "temperature", 0.9)
  """
  @spec set(String.t(), String.t(), term(), keyword()) :: :ok | {:error, term()}
  def set(session_id, identifier, value, opts \\ []) do
    SnakepitGRPCBridge.Variables.Manager.set(session_id, identifier, value, opts)
  end

  @doc """
  List all variables in session.
  
  ## Examples
  
      {:ok, variables} = SnakepitGRPCBridge.API.Variables.list(session_id)
  """
  @spec list(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list(session_id) do
    SnakepitGRPCBridge.Variables.Manager.list(session_id)
  end

  @doc """
  Delete variable from session.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.API.Variables.delete(session_id, "temperature")
  """
  @spec delete(String.t(), String.t()) :: :ok | {:error, term()}
  def delete(session_id, identifier) do
    SnakepitGRPCBridge.Variables.Manager.delete(session_id, identifier)
  end

  @doc """
  Create a tensor variable.
  
  ## Examples
  
      {:ok, tensor} = SnakepitGRPCBridge.API.Variables.create_tensor(
        session_id, 
        "embeddings", 
        [[1.0, 2.0], [3.0, 4.0]],
        shape: [2, 2],
        dtype: :float32
      )
  """
  @spec create_tensor(String.t(), String.t(), term(), keyword()) :: 
    {:ok, map()} | {:error, term()}
  def create_tensor(session_id, name, data, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Tensor.create(session_id, name, data, opts)
  end

  @doc """
  Create an embedding variable.
  
  ## Examples
  
      {:ok, embedding} = SnakepitGRPCBridge.API.Variables.create_embedding(
        session_id, 
        "document_embedding", 
        [0.1, 0.2, 0.3],
        model: "text-embedding-ada-002",
        dimensions: 3
      )
  """
  @spec create_embedding(String.t(), String.t(), [float()], keyword()) :: 
    {:ok, map()} | {:error, term()}
  def create_embedding(session_id, name, vector, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Embedding.create(session_id, name, vector, opts)
  end

  @doc """
  Create a model variable.
  
  ## Examples
  
      {:ok, model} = SnakepitGRPCBridge.API.Variables.create_model(
        session_id, 
        "predictor_model", 
        model_instance,
        type: :dspy_predictor,
        signature: "question -> answer"
      )
  """
  @spec create_model(String.t(), String.t(), term(), keyword()) :: 
    {:ok, map()} | {:error, term()}
  def create_model(session_id, name, model_instance, opts \\ []) do
    SnakepitGRPCBridge.Variables.MLTypes.Model.create(session_id, name, model_instance, opts)
  end
end
```

### 3. Tools API (`lib/snakepit_grpc_bridge/api/tools.ex`)

```elixir
defmodule SnakepitGRPCBridge.API.Tools do
  @moduledoc """
  Clean API for tool bridge operations.
  
  Enables seamless Python ↔ Elixir function calling.
  """

  @doc """
  Register an Elixir function as a tool callable from Python.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.API.Tools.register_elixir_function(
        session_id, 
        "validate_email", 
        &MyApp.Validators.validate_email/1,
        description: "Validate email address format",
        parameters: [%{name: "email", type: "string", required: true}]
      )
  """
  @spec register_elixir_function(String.t(), String.t(), function(), keyword()) :: 
    :ok | {:error, term()}
  def register_elixir_function(session_id, name, function, opts \\ []) do
    metadata = %{
      description: Keyword.get(opts, :description, ""),
      parameters: Keyword.get(opts, :parameters, []),
      returns: Keyword.get(opts, :returns, %{}),
      registered_at: DateTime.utc_now()
    }
    
    SnakepitGRPCBridge.Tools.Registry.register_tool(session_id, name, function, metadata)
  end

  @doc """
  Register a Python function as a tool callable from Elixir.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.API.Tools.register_python_function(
        session_id, 
        "calculate_similarity", 
        "similarity_module.cosine_similarity",
        parameters: [
          %{name: "vector1", type: "list", required: true},
          %{name: "vector2", type: "list", required: true}
        ]
      )
  """
  @spec register_python_function(String.t(), String.t(), String.t(), keyword()) :: 
    :ok | {:error, term()}
  def register_python_function(session_id, name, python_function_path, opts \\ []) do
    SnakepitGRPCBridge.Tools.Registry.register_python_tool(
      session_id, name, python_function_path, opts
    )
  end

  @doc """
  Call a registered tool.
  
  ## Examples
  
      {:ok, true} = SnakepitGRPCBridge.API.Tools.call(
        session_id, 
        "validate_email", 
        %{email: "user@example.com"}
      )
  """
  @spec call(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call(session_id, tool_name, parameters) do
    SnakepitGRPCBridge.Tools.Executor.execute_tool(session_id, tool_name, parameters)
  end

  @doc """
  List all registered tools in session.
  
  ## Examples
  
      {:ok, tools} = SnakepitGRPCBridge.API.Tools.list(session_id)
  """
  @spec list(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list(session_id) do
    SnakepitGRPCBridge.Tools.Registry.list_tools(session_id)
  end

  @doc """
  Unregister a tool.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.API.Tools.unregister(session_id, "validate_email")
  """
  @spec unregister(String.t(), String.t()) :: :ok | {:error, term()}
  def unregister(session_id, tool_name) do
    SnakepitGRPCBridge.Tools.Registry.unregister_tool(session_id, tool_name)
  end
end
```

### 4. DSPy API (`lib/snakepit_grpc_bridge/api/dspy.ex`)

```elixir
defmodule SnakepitGRPCBridge.API.DSPy do
  @moduledoc """
  Clean API for DSPy integration operations.
  
  Provides high-level interface for DSPy workflows and enhanced features.
  """

  @doc """
  Call DSPy class method directly.
  
  ## Examples
  
      {:ok, result} = SnakepitGRPCBridge.API.DSPy.call(
        session_id,
        "dspy.Predict", 
        "__call__", 
        %{question: "What is Elixir?"},
        signature: "question -> answer"
      )
  """
  @spec call(String.t(), String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def call(session_id, class_path, method, args, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Integration.call_dspy(
      class_path, method, [], args, Keyword.put(opts, :session_id, session_id)
    )
  end

  @doc """
  Enhanced predict with automatic optimization.
  
  ## Examples
  
      {:ok, result} = SnakepitGRPCBridge.API.DSPy.enhanced_predict(
        session_id,
        "question -> answer",
        %{question: "What is Elixir?"},
        optimization_level: :high
      )
  """
  @spec enhanced_predict(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def enhanced_predict(session_id, signature, inputs, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Enhanced.predict(session_id, 
      Map.merge(inputs, %{"signature" => signature}), opts)
  end

  @doc """
  Enhanced chain of thought with reasoning capture.
  
  ## Examples
  
      {:ok, result} = SnakepitGRPCBridge.API.DSPy.enhanced_chain_of_thought(
        session_id,
        "question -> reasoning, answer",
        %{question: "Explain photosynthesis"},
        reasoning_steps: 3
      )
  """
  @spec enhanced_chain_of_thought(String.t(), String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def enhanced_chain_of_thought(session_id, signature, inputs, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Enhanced.chain_of_thought(session_id, 
      Map.merge(inputs, %{"signature" => signature}), opts)
  end

  @doc """
  Discover DSPy module schema.
  
  ## Examples
  
      {:ok, schema} = SnakepitGRPCBridge.API.DSPy.discover_schema("dspy.teleprompt")
  """
  @spec discover_schema(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover_schema(module_path, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Schema.discover_schema(module_path, opts)
  end

  @doc """
  Create DSPy workflow with multiple steps.
  
  ## Examples
  
      {:ok, workflow} = SnakepitGRPCBridge.API.DSPy.create_workflow(
        session_id,
        [
          {:predict, "question -> keywords", %{name: "extract_keywords"}},
          {:chain_of_thought, "keywords -> analysis", %{name: "analyze"}},
          {:predict, "analysis -> summary", %{name: "summarize"}}
        ]
      )
  """
  @spec create_workflow(String.t(), [tuple()], keyword()) :: 
    {:ok, map()} | {:error, term()}
  def create_workflow(session_id, steps, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Workflows.create_workflow(session_id, steps, opts)
  end

  @doc """
  Execute DSPy workflow.
  
  ## Examples
  
      {:ok, results} = SnakepitGRPCBridge.API.DSPy.execute_workflow(
        session_id,
        workflow_id,
        %{question: "What are the benefits of renewable energy?"}
      )
  """
  @spec execute_workflow(String.t(), String.t(), map(), keyword()) :: 
    {:ok, map()} | {:error, term()}
  def execute_workflow(session_id, workflow_id, inputs, opts \\ []) do
    SnakepitGRPCBridge.DSPy.Workflows.execute_workflow(session_id, workflow_id, inputs, opts)
  end
end
```

### 5. Configuration

```elixir
# config/config.exs
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
```

## Key Features

### 1. Complete ML Platform
- **All** machine learning functionality in one place
- Comprehensive variable system with ML data types
- Full-featured tool bridge
- Complete DSPy integration with enhancements

### 2. Clean Consumer APIs
- Simple, well-documented APIs for DSPex
- Abstracts complexity of underlying systems
- Both simple and advanced usage patterns
- Consistent error handling and return values

### 3. Independent Evolution
- Can add ML features without affecting infrastructure
- Fast development cycle for ML capabilities
- Depends on stable Snakepit infrastructure
- Clear separation of concerns

### 4. Production Ready
- Comprehensive error handling and logging
- Performance monitoring and telemetry
- Proper resource management and cleanup
- Scalable architecture for high-throughput ML workloads

This specification defines SnakepitGRPCBridge as a complete, production-ready ML platform that provides all the functionality needed for machine learning workflows while maintaining clean separation from infrastructure concerns.
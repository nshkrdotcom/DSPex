# SnakepitGrpcBridge Technical Specification

## Overview

SnakepitGrpcBridge is a domain-specific bridge package that provides DSPy integration, gRPC communication, variables management, and bidirectional tool calling on top of Snakepit Core infrastructure.

This package contains all the functionality previously embedded in Snakepit, now cleanly separated and focused on ML/DSP workflows.

## Architecture Principles

### Domain-Specific Focus
SnakepitGrpcBridge handles **only** ML/DSP domain concerns:
- DSPy class integration and schema discovery
- Python ↔ Elixir bidirectional communication
- Variables and context management
- Tool calling infrastructure
- gRPC protocol implementation

### Clean Dependency
```
SnakepitGrpcBridge → Snakepit Core → OTP/Elixir
```
The bridge depends on Snakepit but never vice versa.

## Core Components

### 1. Main Bridge API (`SnakepitGrpcBridge`)

**File**: `lib/snakepit_grpc_bridge.ex`  
**Responsibility**: Primary public interface

```elixir
defmodule SnakepitGrpcBridge do
  @moduledoc """
  gRPC-based bridge for DSPy integration with Python processes.
  
  Provides high-level APIs for DSPy operations, variables management,
  and bidirectional tool calling built on Snakepit Core infrastructure.
  """

  @doc """
  Start the bridge with configuration.
  
  Automatically configures Snakepit to use this bridge's adapter.
  
  ## Options
  
    * `:python_executable` - Python interpreter path (default: "python3")
    * `:bridge_script` - Bridge script path (default: auto-detect)
    * `:grpc_port` - gRPC server port (default: 0 for dynamic)
    * `:timeout` - Bridge startup timeout (default: 30000)
    * `:enable_telemetry` - Enable detailed telemetry (default: true)
  
  ## Examples
  
      {:ok, bridge_info} = SnakepitGrpcBridge.start_bridge([
        python_executable: "/opt/python3.11/bin/python",
        grpc_port: 50051
      ])
  """
  @spec start_bridge(keyword()) :: {:ok, map()} | {:error, term()}
  def start_bridge(opts \\ [])

  @doc """
  Stop the bridge and clean up resources.
  """
  @spec stop_bridge() :: :ok
  def stop_bridge()

  @doc """
  Execute DSPy command with full context.
  
  ## Examples
  
      # Create DSPy predictor
      {:ok, result} = SnakepitGrpcBridge.execute_dspy("session_1", "create_instance", %{
        "class_path" => "dspy.Predict",
        "signature" => "question -> answer"
      })
      
      # Execute prediction
      {:ok, prediction} = SnakepitGrpcBridge.execute_dspy("session_1", "call_method", %{
        "instance_id" => result["instance_id"],
        "method" => "__call__",
        "args" => %{"question" => "What is DSPy?"}
      })
  """
  @spec execute_dspy(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_dspy(session_id, command, args)

  @doc """
  Discover DSPy module schema with caching.
  
  ## Examples
  
      {:ok, schema} = SnakepitGrpcBridge.discover_schema("dspy")
      {:ok, optimizers} = SnakepitGrpcBridge.discover_schema("dspy.teleprompt")
  """
  @spec discover_schema(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover_schema(module_path, opts \\ [])

  @doc """
  Get variable from session context.
  
  ## Examples
  
      {:ok, value} = SnakepitGrpcBridge.get_variable("session_1", "model_config")
      {:ok, nil} = SnakepitGrpcBridge.get_variable("session_1", "missing", nil)
  """
  @spec get_variable(String.t(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def get_variable(session_id, identifier, default \\ nil)

  @doc """
  Set variable in session context.
  
  ## Examples
  
      :ok = SnakepitGrpcBridge.set_variable("session_1", "temperature", 0.7)
      :ok = SnakepitGrpcBridge.set_variable("session_1", "model", "gpt-4", type: :string)
  """
  @spec set_variable(String.t(), String.t(), term(), keyword()) :: :ok | {:error, term()}
  def set_variable(session_id, identifier, value, opts \\ [])

  @doc """
  List all variables in session.
  
  ## Returns
  
      {:ok, %{
        "temperature" => %{value: 0.7, type: :float},
        "model" => %{value: "gpt-4", type: :string}
      }}
  """
  @spec list_variables(String.t()) :: {:ok, map()} | {:error, term()}
  def list_variables(session_id)

  @doc """
  Register Elixir function as tool callable from Python.
  
  ## Examples
  
      SnakepitGrpcBridge.register_elixir_tool("session_1", "validate_json", fn params ->
        case Jason.decode(params["json_string"]) do
          {:ok, _} -> %{valid: true}
          {:error, _} -> %{valid: false, error: "Invalid JSON"}
        end
      end, %{
        description: "Validate JSON string",
        parameters: [%{name: "json_string", type: "string", required: true}]
      })
  """
  @spec register_elixir_tool(String.t(), String.t(), function(), map()) :: 
    :ok | {:error, term()}
  def register_elixir_tool(session_id, name, function, metadata \\ %{})

  @doc """
  List registered Elixir tools for session.
  """
  @spec list_elixir_tools(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_elixir_tools(session_id)

  @doc """
  Initialize session with bridge-specific setup.
  
  Sets up variables store, tool registry, and Python worker context.
  """
  @spec initialize_session(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def initialize_session(session_id, opts \\ [])

  @doc """
  Clean up session resources.
  
  Removes variables, tools, and Python-side session state.
  """
  @spec cleanup_session(String.t()) :: :ok | {:error, term()}
  def cleanup_session(session_id)
end
```

### 2. Snakepit Adapter Implementation (`SnakepitGrpcBridge.Adapter`)

**File**: `lib/snakepit_grpc_bridge/adapter.ex`  
**Responsibility**: Snakepit.Adapter behavior implementation

```elixir
defmodule SnakepitGrpcBridge.Adapter do
  @moduledoc """
  Snakepit adapter for gRPC-based DSPy bridge.
  
  Implements Snakepit.Adapter behavior to integrate with Snakepit Core.
  Routes commands to appropriate bridge modules.
  """
  
  @behaviour Snakepit.Adapter
  
  require Logger

  @impl Snakepit.Adapter
  def execute(command, args, opts) do
    session_id = opts[:session_id]
    
    case command do
      # DSPy operations
      "call_dspy_bridge" -> 
        SnakepitGrpcBridge.DSPy.execute_command(args, opts)
      
      "discover_dspy_schema" -> 
        SnakepitGrpcBridge.DSPy.discover_schema(args["module_path"], opts)
      
      # Enhanced DSPy operations with bidirectional tools
      "enhanced_predict" -> 
        SnakepitGrpcBridge.DSPy.Enhanced.predict(session_id, args, opts)
      
      "enhanced_chain_of_thought" -> 
        SnakepitGrpcBridge.DSPy.Enhanced.chain_of_thought(session_id, args, opts)
      
      # Variables operations
      "get_variable" -> 
        SnakepitGrpcBridge.Variables.get(session_id, args["identifier"], args["default"])
      
      "set_variable" -> 
        SnakepitGrpcBridge.Variables.set(session_id, args["identifier"], args["value"], opts)
      
      "list_variables" -> 
        SnakepitGrpcBridge.Variables.list(session_id)
      
      # Tool operations
      "register_elixir_tool" -> 
        SnakepitGrpcBridge.Tools.register_tool(session_id, args["name"], args["function"], args["metadata"])
      
      "list_elixir_tools" -> 
        SnakepitGrpcBridge.Tools.list_tools(session_id)
      
      "call_elixir_tool" -> 
        SnakepitGrpcBridge.Tools.execute_tool(session_id, args["tool_name"], args["parameters"])
      
      # Session management
      "initialize_session" -> 
        SnakepitGrpcBridge.Session.initialize(session_id, args, opts)
      
      "cleanup_session" -> 
        SnakepitGrpcBridge.Session.cleanup(session_id)
      
      "get_session_info" -> 
        SnakepitGrpcBridge.Session.get_info(session_id)
      
      # Storage operations
      "list_stored_objects" -> 
        SnakepitGrpcBridge.Storage.list_objects(session_id)
      
      "get_stored_object" -> 
        SnakepitGrpcBridge.Storage.get_object(session_id, args["object_id"])
      
      # Unknown command
      _ -> 
        Logger.warning("Unknown command received: #{command}")
        {:error, {:unknown_command, command}}
    end
  end

  @impl Snakepit.Adapter
  def execute_stream(command, args, callback_fn, opts) do
    session_id = opts[:session_id]
    
    case command do
      "streaming_inference" -> 
        SnakepitGrpcBridge.DSPy.stream_inference(session_id, args, callback_fn, opts)
      
      "batch_processing" -> 
        SnakepitGrpcBridge.Processing.stream_batch(session_id, args, callback_fn, opts)
      
      _ -> 
        {:error, {:streaming_not_supported, command}}
    end
  end

  @impl Snakepit.Adapter
  def uses_grpc?, do: true

  @impl Snakepit.Adapter  
  def supports_streaming?, do: true

  @impl Snakepit.Adapter
  def init(config) do
    # Initialize gRPC client, Python bridge process, etc.
    with {:ok, grpc_config} <- setup_grpc_client(config),
         {:ok, python_bridge} <- start_python_bridge(config),
         {:ok, _} <- verify_bridge_connectivity() do
      
      state = %{
        grpc_config: grpc_config,
        python_bridge: python_bridge,
        started_at: DateTime.utc_now()
      }
      
      Logger.info("SnakepitGrpcBridge adapter initialized successfully")
      {:ok, state}
    else
      {:error, reason} -> 
        Logger.error("Failed to initialize SnakepitGrpcBridge: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Snakepit.Adapter
  def terminate(_reason, state) do
    # Clean up gRPC connections, Python processes, etc.
    cleanup_grpc_client(state.grpc_config)
    terminate_python_bridge(state.python_bridge)
    Logger.info("SnakepitGrpcBridge adapter terminated")
    :ok
  end

  # Private implementation functions
  defp setup_grpc_client(config), do: SnakepitGrpcBridge.GRPC.Client.start(config)
  defp start_python_bridge(config), do: SnakepitGrpcBridge.Python.Bridge.start(config)
  defp verify_bridge_connectivity(), do: SnakepitGrpcBridge.Health.check()
  defp cleanup_grpc_client(grpc_config), do: SnakepitGrpcBridge.GRPC.Client.stop(grpc_config)
  defp terminate_python_bridge(bridge), do: SnakepitGrpcBridge.Python.Bridge.stop(bridge)
end
```

### 3. DSPy Integration (`SnakepitGrpcBridge.DSPy`)

**File**: `lib/snakepit_grpc_bridge/dspy/bridge.ex`  
**Responsibility**: Core DSPy operations

```elixir
defmodule SnakepitGrpcBridge.DSPy do
  @moduledoc """
  DSPy integration module providing class instantiation, method calling,
  and schema discovery through gRPC communication with Python.
  """

  @doc """
  Execute DSPy bridge command.
  
  Handles class instantiation, method calling, and object management.
  """
  @spec execute_command(map(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute_command(args, opts) do
    %{
      "class_path" => class_path,
      "method" => method_name,
      "args" => positional_args,
      "kwargs" => keyword_args
    } = args
    
    grpc_request = %{
      class_path: class_path,
      method: method_name,
      args: positional_args || [],
      kwargs: keyword_args || %{},
      session_id: opts[:session_id] || "default"
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("execute_dspy", grpc_request) do
      {:ok, %{success: true, result: result}} -> 
        {:ok, transform_result(result)}
      
      {:ok, %{success: false, error: error, traceback: traceback}} -> 
        {:error, format_python_error(error, traceback)}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Discover DSPy module schema with intelligent caching.
  """
  @spec discover_schema(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def discover_schema(module_path, opts \\ []) do
    # Check cache first
    case SnakepitGrpcBridge.Cache.get_schema(module_path) do
      {:ok, cached_schema} when not is_nil(cached_schema) -> 
        {:ok, cached_schema}
      
      _ -> 
        discover_and_cache_schema(module_path, opts)
    end
  end

  defp discover_and_cache_schema(module_path, opts) do
    grpc_request = %{
      module_path: module_path,
      include_methods: Keyword.get(opts, :include_methods, true),
      include_docs: Keyword.get(opts, :include_docs, true)
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("discover_schema", grpc_request) do
      {:ok, %{success: true, schema: schema}} -> 
        # Cache for future requests
        SnakepitGrpcBridge.Cache.put_schema(module_path, schema)
        {:ok, schema}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Create DSPy instance with proper argument handling.
  """
  @spec create_instance(String.t(), map(), keyword()) :: {:ok, {String.t(), String.t()}} | {:error, term()}
  def create_instance(class_path, args, opts \\ []) do
    # Handle special cases for DSPy constructors
    {positional_args, keyword_args} = prepare_constructor_args(class_path, args)
    
    execute_args = %{
      "class_path" => class_path,
      "method" => "__init__",
      "args" => positional_args,
      "kwargs" => keyword_args
    }
    
    case execute_command(execute_args, opts) do
      {:ok, %{"success" => true, "instance_id" => instance_id}} -> 
        session_id = opts[:session_id] || "default"
        {:ok, {session_id, instance_id}}
      
      {:ok, %{"success" => false, "error" => error}} -> 
        {:error, error}
      
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  Call method on stored DSPy instance.
  """
  @spec call_method({String.t(), String.t()}, String.t(), map(), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def call_method({session_id, instance_id}, method_name, args, opts \\ []) do
    execute_args = %{
      "class_path" => "stored.#{instance_id}",
      "method" => method_name,
      "args" => [],
      "kwargs" => args
    }
    
    execute_command(execute_args, Keyword.put(opts, :session_id, session_id))
  end

  # Private helper functions
  defp prepare_constructor_args("dspy.Predict", %{"signature" => signature} = args) do
    # dspy.Predict expects signature as first positional argument
    {[signature], Map.delete(args, "signature")}
  end
  
  defp prepare_constructor_args("dspy.ChainOfThought", %{"signature" => signature} = args) do
    # dspy.ChainOfThought also expects signature as first positional
    {[signature], Map.delete(args, "signature")}
  end
  
  defp prepare_constructor_args(_class_path, args) do
    # Default: pass everything as keyword arguments
    {[], args}
  end

  defp transform_result(result) do
    # Handle different Python result formats
    case result do
      %{"type" => "constructor", "instance_id" => instance_id} -> 
        %{"success" => true, "instance_id" => instance_id}
      
      %{"type" => "method_call", "result" => method_result} -> 
        %{"success" => true, "result" => method_result}
      
      %{"completions" => completions} when is_list(completions) -> 
        # DSPy completion format
        %{"success" => true, "result" => %{"prediction_data" => List.first(completions)}}
      
      other -> 
        %{"success" => true, "result" => other}
    end
  end

  defp format_python_error(error, traceback) do
    case traceback do
      nil -> error
      tb -> "#{error}\n#{tb}"
    end
  end
end
```

### 4. Enhanced DSPy Operations (`SnakepitGrpcBridge.DSPy.Enhanced`)

**File**: `lib/snakepit_grpc_bridge/dspy/enhanced.ex`  
**Responsibility**: Bidirectional tool-enabled DSPy operations

```elixir
defmodule SnakepitGrpcBridge.DSPy.Enhanced do
  @moduledoc """
  Enhanced DSPy operations with bidirectional tool calling.
  
  Provides Predict and ChainOfThought implementations that can call back
  into Elixir functions during Python execution.
  """

  @doc """
  Enhanced prediction with Elixir tool access.
  
  ## Examples
  
      {:ok, result} = SnakepitGrpcBridge.DSPy.Enhanced.predict("session_1", %{
        "signature" => "question -> answer",
        "question" => "What is the weather in Paris?",
        "available_tools" => ["get_weather", "validate_location"]
      })
  """
  @spec predict(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict(session_id, args, opts \\ []) do
    signature = args["signature"] || "input -> output"
    
    # Ensure standard tools are registered
    :ok = SnakepitGrpcBridge.Tools.register_standard_tools(session_id)
    
    enhanced_args = %{
      "signature" => signature,
      "inputs" => Map.drop(args, ["signature"]),
      "session_id" => session_id,
      "enable_tools" => true
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("enhanced_predict", enhanced_args) do
      {:ok, %{success: true} = result} -> 
        {:ok, transform_enhanced_result(result)}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Enhanced chain of thought with tool access.
  """
  @spec chain_of_thought(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chain_of_thought(session_id, args, opts \\ []) do
    signature = args["signature"] || "input -> reasoning, answer"
    
    # Ensure standard tools are registered
    :ok = SnakepitGrpcBridge.Tools.register_standard_tools(session_id)
    
    enhanced_args = %{
      "signature" => signature,
      "inputs" => Map.drop(args, ["signature"]),
      "session_id" => session_id,
      "enable_tools" => true,
      "reasoning_depth" => args["reasoning_depth"] || "default"
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("enhanced_chain_of_thought", enhanced_args) do
      {:ok, %{success: true} = result} -> 
        {:ok, transform_cot_result(result)}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  defp transform_enhanced_result(result) do
    %{
      "success" => true,
      "result" => %{
        "prediction_data" => result["prediction"],
        "tool_calls" => result["tool_calls"] || [],
        "elixir_tools_used" => result["elixir_tools_used"] || [],
        "metadata" => result["metadata"] || %{}
      }
    }
  end

  defp transform_cot_result(result) do
    %{
      "success" => true,
      "result" => %{
        "prediction_data" => %{
          "reasoning" => result["reasoning"],
          "answer" => result["answer"]
        },
        "reasoning_steps" => result["reasoning_steps"] || [],
        "tool_calls" => result["tool_calls"] || [],
        "elixir_tools_used" => result["elixir_tools_used"] || []
      }
    }
  end
end
```

### 5. Variables Management (`SnakepitGrpcBridge.Variables`)

**File**: `lib/snakepit_grpc_bridge/variables.ex`  
**Responsibility**: Session-scoped variables with type support

```elixir
defmodule SnakepitGrpcBridge.Variables do
  @moduledoc """
  Variables management system for session-scoped data.
  
  Provides persistent storage for variables within sessions,
  with type validation and atomic operations.
  """

  @doc """
  Get variable from session store.
  """
  @spec get(String.t(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def get(session_id, identifier, default \\ nil) do
    case SnakepitGrpcBridge.GRPC.Client.call("get_variable", %{
      session_id: session_id,
      identifier: identifier,
      default: default
    }) do
      {:ok, %{success: true, value: value}} -> 
        {:ok, value}
      
      {:ok, %{success: false, error: "not_found"}} -> 
        {:ok, default}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Set variable in session store.
  
  ## Options
  
    * `:type` - Variable type for validation (:string, :integer, :float, :boolean, :map, :list)
    * `:metadata` - Additional metadata to store with variable
  """
  @spec set(String.t(), String.t(), term(), keyword()) :: :ok | {:error, term()}
  def set(session_id, identifier, value, opts \\ []) do
    grpc_request = %{
      session_id: session_id,
      identifier: identifier,
      value: value,
      type: opts[:type],
      metadata: opts[:metadata] || %{}
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("set_variable", grpc_request) do
      {:ok, %{success: true}} -> 
        :ok
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Update variable using function.
  """
  @spec update(String.t(), String.t(), (term() -> term()), keyword()) :: 
    {:ok, term()} | {:error, term()}
  def update(session_id, identifier, update_fn, opts \\ []) do
    case get(session_id, identifier) do
      {:ok, current_value} -> 
        new_value = update_fn.(current_value)
        case set(session_id, identifier, new_value, opts) do
          :ok -> {:ok, new_value}
          {:error, reason} -> {:error, reason}
        end
      
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  List all variables in session.
  """
  @spec list(String.t()) :: {:ok, map()} | {:error, term()}
  def list(session_id) do
    case SnakepitGrpcBridge.GRPC.Client.call("list_variables", %{
      session_id: session_id
    }) do
      {:ok, %{success: true, variables: variables}} -> 
        {:ok, variables}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Delete variable from session.
  """
  @spec delete(String.t(), String.t()) :: :ok | {:error, term()}
  def delete(session_id, identifier) do
    case SnakepitGrpcBridge.GRPC.Client.call("delete_variable", %{
      session_id: session_id,
      identifier: identifier
    }) do
      {:ok, %{success: true}} -> 
        :ok
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Check if variable exists in session.
  """
  @spec exists?(String.t(), String.t()) :: boolean()
  def exists?(session_id, identifier) do
    case get(session_id, identifier, :__not_found__) do
      {:ok, :__not_found__} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get multiple variables at once.
  """
  @spec get_many(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def get_many(session_id, identifiers) do
    case SnakepitGrpcBridge.GRPC.Client.call("get_variables", %{
      session_id: session_id,
      identifiers: identifiers
    }) do
      {:ok, %{success: true, variables: variables}} -> 
        {:ok, variables}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Update multiple variables atomically.
  """
  @spec update_many(String.t(), map(), keyword()) :: :ok | {:error, term()}
  def update_many(session_id, updates, opts \\ []) do
    grpc_request = %{
      session_id: session_id,
      updates: updates,
      atomic: Keyword.get(opts, :atomic, true)
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("update_variables", grpc_request) do
      {:ok, %{success: true}} -> 
        :ok
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end
end
```

### 6. Tool Calling System (`SnakepitGrpcBridge.Tools`)

**File**: `lib/snakepit_grpc_bridge/tools.ex`  
**Responsibility**: Bidirectional Python ↔ Elixir function calling

```elixir
defmodule SnakepitGrpcBridge.Tools do
  @moduledoc """
  Bidirectional tool calling system.
  
  Allows Python DSPy code to call Elixir functions and vice versa,
  enabling rich integration between the two environments.
  """

  @doc """
  Register Elixir function as tool callable from Python.
  
  ## Examples
  
      SnakepitGrpcBridge.Tools.register_tool("session_1", "validate_email", fn params ->
        email = params["email"]
        if String.contains?(email, "@") do
          %{valid: true, domain: String.split(email, "@") |> List.last()}
        else
          %{valid: false, error: "Invalid email format"}
        end
      end, %{
        description: "Validate email address format",
        parameters: [
          %{name: "email", type: "string", required: true, description: "Email to validate"}
        ],
        returns: %{type: "object", description: "Validation result with valid flag"}
      })
  """
  @spec register_tool(String.t(), String.t(), function(), map()) :: :ok | {:error, term()}
  def register_tool(session_id, tool_name, function, metadata \\ %{}) when is_function(function, 1) do
    # Store function locally for fast access
    tool_key = "#{session_id}:#{tool_name}"
    :persistent_term.put({__MODULE__, tool_key}, function)
    
    # Register with Python bridge
    grpc_request = %{
      session_id: session_id,
      tool_name: tool_name,
      metadata: Map.merge(%{
        "type" => "elixir_function",
        "callable" => true
      }, metadata)
    }
    
    case SnakepitGrpcBridge.GRPC.Client.call("register_elixir_tool", grpc_request) do
      {:ok, %{success: true}} -> 
        :ok
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Execute Elixir tool (called from Python via gRPC).
  
  This function is called by the Python bridge when DSPy code invokes
  an Elixir tool.
  """
  @spec execute_tool(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_tool(session_id, tool_name, parameters) do
    tool_key = "#{session_id}:#{tool_name}"
    
    case :persistent_term.get({__MODULE__, tool_key}, nil) do
      nil -> 
        {:error, {:tool_not_found, tool_name}}
      
      function when is_function(function, 1) -> 
        try do
          result = function.(parameters)
          {:ok, result}
        rescue
          exception -> 
            {:error, {:tool_execution_failed, Exception.message(exception)}}
        catch
          :throw, value -> 
            {:error, {:tool_threw, value}}
          
          :exit, reason -> 
            {:error, {:tool_exited, reason}}
        end
    end
  end

  @doc """
  Register standard tools for a session.
  
  Includes common utilities like JSON validation, HTTP requests, etc.
  """
  @spec register_standard_tools(String.t()) :: {:ok, integer()} | {:error, term()}
  def register_standard_tools(session_id) do
    tools = [
      {"validate_json", &validate_json/1, %{
        description: "Validate JSON string format",
        parameters: [%{name: "json_string", type: "string", required: true}]
      }},
      
      {"http_get", &http_get/1, %{
        description: "Make HTTP GET request",
        parameters: [%{name: "url", type: "string", required: true}]
      }},
      
      {"format_datetime", &format_datetime/1, %{
        description: "Format datetime string",
        parameters: [
          %{name: "datetime", type: "string", required: true},
          %{name: "format", type: "string", required: false, default: "%Y-%m-%d %H:%M:%S"}
        ]
      }},
      
      {"validate_regex", &validate_regex/1, %{
        description: "Validate string against regex pattern",
        parameters: [
          %{name: "text", type: "string", required: true},
          %{name: "pattern", type: "string", required: true}
        ]
      }}
    ]
    
    results = for {name, function, metadata} <- tools do
      register_tool(session_id, name, function, metadata)
    end
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> 
        {:ok, length(tools)}
      
      {:error, reason} -> 
        {:error, reason}
    end
  end

  @doc """
  List registered tools for session.
  """
  @spec list_tools(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_tools(session_id) do
    case SnakepitGrpcBridge.GRPC.Client.call("list_elixir_tools", %{
      session_id: session_id
    }) do
      {:ok, %{success: true, tools: tools}} -> 
        {:ok, tools}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  @doc """
  Remove tool registration.
  """
  @spec unregister_tool(String.t(), String.t()) :: :ok | {:error, term()}
  def unregister_tool(session_id, tool_name) do
    tool_key = "#{session_id}:#{tool_name}"
    :persistent_term.erase({__MODULE__, tool_key})
    
    case SnakepitGrpcBridge.GRPC.Client.call("unregister_elixir_tool", %{
      session_id: session_id,
      tool_name: tool_name
    }) do
      {:ok, %{success: true}} -> 
        :ok
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  # Standard tool implementations
  defp validate_json(%{"json_string" => json_string}) do
    case Jason.decode(json_string) do
      {:ok, parsed} -> %{valid: true, parsed: parsed}
      {:error, %Jason.DecodeError{} = error} -> %{valid: false, error: Exception.message(error)}
    end
  end

  defp http_get(%{"url" => url}) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> 
        %{success: true, body: body, status_code: 200}
      
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} -> 
        %{success: false, body: body, status_code: status_code}
      
      {:error, %HTTPoison.Error{reason: reason}} -> 
        %{success: false, error: to_string(reason)}
    end
  end

  defp format_datetime(%{"datetime" => datetime_str} = params) do
    format = params["format"] || "%Y-%m-%d %H:%M:%S"
    
    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, _offset} -> 
        %{success: true, formatted: Calendar.strftime(datetime, format)}
      
      {:error, reason} -> 
        %{success: false, error: to_string(reason)}
    end
  end

  defp validate_regex(%{"text" => text, "pattern" => pattern}) do
    case Regex.compile(pattern) do
      {:ok, regex} -> 
        matches = Regex.run(regex, text)
        %{valid: not is_nil(matches), matches: matches || []}
      
      {:error, reason} -> 
        %{valid: false, error: "Invalid regex: #{inspect(reason)}"}
    end
  end
end
```

### 7. Session Management (`SnakepitGrpcBridge.Session`)

**File**: `lib/snakepit_grpc_bridge/session.ex`  
**Responsibility**: Bridge-specific session lifecycle

```elixir
defmodule SnakepitGrpcBridge.Session do
  @moduledoc """
  Session management for bridge-specific resources.
  
  Handles initialization and cleanup of variables, tools, and 
  Python-side contexts for each session.
  """

  @doc """
  Initialize session with bridge-specific setup.
  """
  @spec initialize(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def initialize(session_id, args, opts \\ []) do
    config = Map.merge(%{
      "enable_variables" => true,
      "enable_tools" => true,
      "python_context" => %{}
    }, args)
    
    with {:ok, _} <- setup_variables_store(session_id, config),
         {:ok, tool_count} <- setup_tools_registry(session_id, config),
         {:ok, py_context} <- initialize_python_context(session_id, config) do
      
      session_info = %{
        "session_id" => session_id,
        "initialized_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "variables_enabled" => config["enable_variables"],
        "tools_enabled" => config["enable_tools"],
        "tool_count" => tool_count,
        "python_context" => py_context
      }
      
      {:ok, session_info}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clean up all session resources.
  """
  @spec cleanup(String.t()) :: :ok | {:error, term()}
  def cleanup(session_id) do
    # Clean up in reverse order of initialization
    cleanup_python_context(session_id)
    cleanup_tools_registry(session_id)
    cleanup_variables_store(session_id)
    
    # Notify Python bridge
    case SnakepitGrpcBridge.GRPC.Client.call("cleanup_session", %{
      session_id: session_id
    }) do
      {:ok, %{success: true}} -> :ok
      {:ok, %{success: false, error: error}} -> {:error, error}
      {:error, _} -> :ok  # Best effort cleanup
    end
  end

  @doc """
  Get session information and status.
  """
  @spec get_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_info(session_id) do
    case SnakepitGrpcBridge.GRPC.Client.call("get_session_info", %{
      session_id: session_id
    }) do
      {:ok, %{success: true, info: info}} -> 
        {:ok, info}
      
      {:ok, %{success: false, error: error}} -> 
        {:error, error}
      
      {:error, grpc_error} -> 
        {:error, {:grpc_error, grpc_error}}
    end
  end

  # Private helper functions
  defp setup_variables_store(session_id, config) do
    if config["enable_variables"] do
      SnakepitGrpcBridge.GRPC.Client.call("initialize_variables", %{
        session_id: session_id,
        initial_variables: config["initial_variables"] || %{}
      })
    else
      {:ok, %{enabled: false}}
    end
  end

  defp setup_tools_registry(session_id, config) do
    if config["enable_tools"] do
      case SnakepitGrpcBridge.Tools.register_standard_tools(session_id) do
        {:ok, count} -> {:ok, count}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, 0}
    end
  end

  defp initialize_python_context(session_id, config) do
    SnakepitGrpcBridge.GRPC.Client.call("initialize_python_context", %{
      session_id: session_id,
      context_config: config["python_context"] || %{}
    })
  end

  defp cleanup_python_context(session_id) do
    # Best effort cleanup - don't fail if Python side is already down
    SnakepitGrpcBridge.GRPC.Client.call("cleanup_python_context", %{
      session_id: session_id
    })
  end

  defp cleanup_tools_registry(session_id) do
    # Remove all persistent term entries for this session
    pattern = {SnakepitGrpcBridge.Tools, "#{session_id}:*"}
    
    for {{module, key}, _value} <- :persistent_term.get() do
      if module == SnakepitGrpcBridge.Tools and String.starts_with?(key, "#{session_id}:") do
        :persistent_term.erase({module, key})
      end
    end
    
    :ok
  end

  defp cleanup_variables_store(session_id) do
    SnakepitGrpcBridge.GRPC.Client.call("cleanup_variables", %{
      session_id: session_id
    })
  end
end
```

## Python Bridge Integration

### Python Package Structure
```
priv/python/snakepit_bridge/
├── __init__.py
├── bridge_server.py              # Main gRPC server
├── dspy_integration/
│   ├── __init__.py
│   ├── core.py                   # DSPy operations
│   ├── enhanced.py               # Bidirectional tools
│   └── schema_discovery.py       # Schema introspection
├── variables/
│   ├── __init__.py
│   ├── store.py                  # Variables management
│   └── types.py                  # Type validation
├── tools/
│   ├── __init__.py
│   ├── registry.py               # Tool management
│   └── elixir_caller.py          # Call back to Elixir
├── grpc_generated/
│   ├── __init__.py
│   ├── bridge_pb2.py             # Protocol definitions
│   └── bridge_pb2_grpc.py        # gRPC stubs
└── utils/
    ├── __init__.py
    ├── logging.py                # Python-side logging
    └── serialization.py          # Data conversion
```

### Configuration System

```elixir
config :snakepit_grpc_bridge,
  # Python configuration
  python_executable: "python3",
  python_bridge_path: :auto_detect,
  python_requirements: ["dspy-ai", "grpcio", "protobuf"],
  
  # gRPC configuration
  grpc_port: 0,  # 0 for dynamic port assignment
  grpc_timeout: 30_000,
  grpc_keepalive: true,
  
  # Bridge behavior
  startup_timeout: 60_000,
  health_check_interval: 30_000,
  auto_restart: true,
  
  # Feature flags
  enable_schema_caching: true,
  enable_telemetry: true,
  enable_debug_logging: false,
  
  # Performance tuning
  max_concurrent_sessions: 100,
  session_idle_timeout: 300_000,  # 5 minutes
  python_gc_interval: 60_000,     # 1 minute
  
  # Development options
  development_mode: Mix.env() == :dev,
  hot_reload_python: Mix.env() == :dev
```

## Testing Strategy

### Test Structure
```
test/
├── snakepit_grpc_bridge_test.exs         # Main API tests
├── snakepit_grpc_bridge/
│   ├── adapter_test.exs                  # Adapter behavior tests
│   ├── dspy/
│   │   ├── bridge_test.exs               # DSPy integration tests
│   │   ├── enhanced_test.exs             # Enhanced operations tests
│   │   └── schema_test.exs               # Schema discovery tests
│   ├── variables_test.exs                # Variables system tests
│   ├── tools_test.exs                    # Tool calling tests
│   └── session_test.exs                  # Session management tests
├── integration/
│   ├── end_to_end_test.exs               # Full workflow tests
│   ├── python_bridge_test.exs            # Python bridge integration
│   └── performance_test.exs              # Performance regression tests
├── support/
│   ├── bridge_test_helpers.ex            # Test utilities
│   ├── mock_python_server.ex             # Mock Python responses
│   └── test_fixtures.ex                  # Test data
└── python/
    ├── test_bridge_server.py             # Python-side unit tests
    ├── test_dspy_integration.py          # DSPy integration tests
    └── test_tools_system.py              # Tool calling tests
```

### Integration Testing
```elixir
defmodule SnakepitGrpcBridge.IntegrationTest do
  use ExUnit.Case
  
  setup_all do
    # Start bridge for integration tests
    {:ok, _} = SnakepitGrpcBridge.start_bridge([
      python_executable: "python3",
      grpc_port: 0
    ])
    
    on_exit(fn -> SnakepitGrpcBridge.stop_bridge() end)
    
    :ok
  end
  
  describe "full DSPy workflow" do
    test "create predictor, set variables, execute with tools" do
      session_id = "integration_test_#{:rand.uniform(10000)}"
      
      # Initialize session
      {:ok, session_info} = SnakepitGrpcBridge.initialize_session(session_id)
      assert session_info["session_id"] == session_id
      
      # Set up variables
      :ok = SnakepitGrpcBridge.set_variable(session_id, "temperature", 0.7)
      :ok = SnakepitGrpcBridge.set_variable(session_id, "model", "gpt-3.5-turbo")
      
      # Register custom tool
      :ok = SnakepitGrpcBridge.register_elixir_tool(session_id, "custom_validator", fn params ->
        %{valid: String.length(params["text"]) > 5}
      end)
      
      # Execute DSPy prediction with tools
      {:ok, result} = SnakepitGrpcBridge.execute_dspy(session_id, "enhanced_predict", %{
        "signature" => "question -> answer",
        "question" => "What is machine learning?",
        "use_tools" => true
      })
      
      assert result["success"] == true
      assert Map.has_key?(result["result"], "prediction_data")
      
      # Cleanup
      :ok = SnakepitGrpcBridge.cleanup_session(session_id)
    end
  end
end
```

## Performance Characteristics

### Benchmarks and Targets

| Operation | Target Latency | Target Throughput | Notes |
|-----------|----------------|-------------------|-------|
| DSPy Instance Creation | < 100ms | > 50/s | Cold start overhead |
| DSPy Method Call | < 50ms | > 100/s | Warm instance |
| Variable Get/Set | < 5ms | > 1000/s | In-memory operations |
| Tool Registration | < 10ms | > 200/s | One-time setup |
| Tool Execution | < 20ms | > 500/s | Elixir function call |
| Schema Discovery | < 200ms | > 20/s | With caching |

### Memory Usage
- Base bridge overhead: < 100MB
- Per session overhead: < 10MB
- Python worker memory: < 200MB
- Variable storage: < 1MB per 1000 variables

## Error Handling and Resilience

### Python Bridge Failures
```elixir
defmodule SnakepitGrpcBridge.Resilience do
  @doc """
  Handle Python bridge restart.
  """
  def handle_bridge_failure(reason) do
    Logger.error("Python bridge failed: #{inspect(reason)}")
    
    # Attempt restart
    case restart_python_bridge() do
      {:ok, _} -> 
        Logger.info("Python bridge restarted successfully")
        :ok
      
      {:error, restart_reason} -> 
        Logger.error("Failed to restart Python bridge: #{inspect(restart_reason)}")
        # Escalate to application supervisor
        {:error, {:bridge_restart_failed, restart_reason}}
    end
  end
end
```

### Session Recovery
```elixir
defmodule SnakepitGrpcBridge.Session.Recovery do
  @doc """
  Recover session state after bridge restart.
  """
  def recover_session(session_id) do
    # Sessions are ephemeral - clean recovery by reinitializing
    case SnakepitGrpcBridge.initialize_session(session_id) do
      {:ok, session_info} -> 
        Logger.info("Session #{session_id} recovered")
        {:ok, session_info}
      
      {:error, reason} -> 
        Logger.warning("Failed to recover session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

## Security Considerations

### Input Validation
```elixir
defmodule SnakepitGrpcBridge.Security do
  @doc """
  Validate DSPy class path to prevent code injection.
  """
  def validate_class_path(class_path) do
    # Only allow known safe patterns
    safe_patterns = [
      ~r/^dspy\.[A-Za-z][A-Za-z0-9_]*$/,           # dspy.ClassName
      ~r/^dspy\.[a-z]+\.[A-Za-z][A-Za-z0-9_]*$/   # dspy.module.ClassName
    ]
    
    if Enum.any?(safe_patterns, &Regex.match?(&1, class_path)) do
      :ok
    else
      {:error, :unsafe_class_path}
    end
  end
  
  @doc """
  Sanitize tool parameters to prevent injection.
  """
  def sanitize_tool_params(params) when is_map(params) do
    # Remove any keys that could be dangerous
    dangerous_keys = ["__class__", "__module__", "eval", "exec"]
    
    sanitized = Map.drop(params, dangerous_keys)
    
    # Validate parameter values
    case validate_param_values(sanitized) do
      :ok -> {:ok, sanitized}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

This specification provides the complete technical foundation for SnakepitGrpcBridge as a separate, focused package that builds on Snakepit Core infrastructure.
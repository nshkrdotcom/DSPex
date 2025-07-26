# Elixir API Design - Clean Interfaces & DSPex Integration

**Date:** July 25, 2025  
**Focus:** Designing clean Elixir API layer for Snakepit and ultra-thin DSPex integration

## 🎯 Current Elixir Architecture Issues

### Problems with Current Design

#### Tight Coupling
```elixir
# Current: DSPex directly calls Snakepit internals
defmodule DSPex.Bridge do
  def call_dspy(args) do
    Snakepit.execute_in_session(session_id, "call_dspy", args)  # Direct internal call
  end
end
```

#### Scattered Variables Logic
```elixir
# Variables scattered across multiple modules
DSPex.Variables                    # High-level API in DSPex
Snakepit.Bridge.Variables         # Implementation in Snakepit  
Snakepit.Bridge.SessionStore      # Storage in Snakepit
# No clean separation between API and implementation
```

#### Mixed Concerns
```elixir
# DSPex.Bridge contains both code generation AND runtime calls
defmodule DSPex.Bridge do
  defmacro defdsyp(...) do ... end      # Code generation (should stay)
  def call_dspy(...) do ... end         # Runtime call (should delegate)
  def discover_schema(...) do ... end   # Runtime call (should delegate)
end
```

## 🏗️ New Clean Architecture

### Design Principles

1. **Clean Interfaces**: DSPex only uses public APIs, never internals
2. **Single Responsibility**: Each module has one clear purpose
3. **Proper Layering**: API layer → Implementation layer → Infrastructure layer
4. **Loose Coupling**: Implementation changes don't break consumers

### Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     DSPex                               │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ defdsyp     │ │ Workflows    │ │ High-level API   │  │
│  │ (macro)     │ │ (orchestrate)│ │ (convenience)    │  │
│  └─────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────┬───────────────────────────────────┘
                      │ Uses clean APIs only
┌─────────────────────▼───────────────────────────────────┐
│                Snakepit.API.*                           │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Variables   │ │ Tools        │ │ DSPy             │  │
│  │ (CRUD)      │ │ (execution)  │ │ (integration)    │  │
│  └─────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────┬───────────────────────────────────┘
                      │ Clean implementation interface
┌─────────────────────▼───────────────────────────────────┐
│             Snakepit.Bridge.* (Internal)                │
│  ┌─────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Variables   │ │ ToolRegistry │ │ SessionStore     │  │
│  │ (storage)   │ │ (management) │ │ (persistence)    │  │
│  └─────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────┬───────────────────────────────────┘
                      │ Infrastructure
┌─────────────────────▼───────────────────────────────────┐
│                 Snakepit.Pool.*                         │
│             (gRPC, processes, pooling)                  │
└─────────────────────────────────────────────────────────┘
```

## 🔧 Snakepit API Layer Design

### Clean API Modules

#### Variables API (`snakepit/lib/snakepit/api/variables.ex`)

```elixir
defmodule Snakepit.API.Variables do
  @moduledoc """
  Clean API for variable operations.
  
  Provides CRUD operations for session-scoped variables with type validation
  and constraint checking. This is the public interface that DSPex uses.
  """
  
  alias Snakepit.Bridge.{Variables, SessionStore}
  
  @type variable_type :: :string | :integer | :float | :boolean | :list | :dict | 
                        :tensor | :embedding | :choice | :module
  
  @type constraint :: %{
    optional(:min) => number(),
    optional(:max) => number(),
    optional(:enum) => [term()],
    optional(:shape) => [pos_integer()],
    optional(:dimensions) => pos_integer()
  }
  
  @doc """
  Create a new variable in the given session.
  
  ## Parameters
  
    * `session_id` - Session identifier
    * `name` - Variable name (unique within session)
    * `type` - Variable type (see `t:variable_type/0`)
    * `value` - Initial value
    * `constraints` - Optional validation constraints
  
  ## Examples
  
      {:ok, _} = Variables.create("session_1", "temperature", :float, 0.7)
      {:ok, _} = Variables.create("session_1", "model_tensor", :tensor, [[1, 2], [3, 4]], 
                                  %{shape: [2, 2]})
  """
  @spec create(binary(), binary(), variable_type(), term(), constraint()) :: 
    {:ok, map()} | {:error, term()}
  def create(session_id, name, type, value, constraints \\ %{}) do
    with {:ok, _session} <- ensure_session(session_id),
         {:ok, validated_value} <- Variables.validate(value, type, constraints),
         :ok <- Variables.store(session_id, name, type, validated_value, constraints) do
      {:ok, %{
        session_id: session_id,
        name: name,
        type: type,
        value: validated_value,
        constraints: constraints,
        created_at: DateTime.utc_now()
      }}
    end
  end
  
  @doc """
  Read a variable value from the session.
  
  ## Examples
  
      {:ok, 0.7} = Variables.read("session_1", "temperature")
      {:error, :not_found} = Variables.read("session_1", "nonexistent")
  """
  @spec read(binary(), binary()) :: {:ok, term()} | {:error, :not_found | term()}
  def read(session_id, name) do
    case Variables.get(session_id, name) do
      {:ok, variable_data} -> {:ok, variable_data.value}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Update an existing variable's value.
  
  Validates the new value against the variable's type and constraints.
  """
  @spec update(binary(), binary(), term()) :: {:ok, map()} | {:error, term()}
  def update(session_id, name, new_value) do
    with {:ok, current_var} <- Variables.get(session_id, name),
         {:ok, validated_value} <- Variables.validate(new_value, current_var.type, current_var.constraints),
         :ok <- Variables.store(session_id, name, current_var.type, validated_value, current_var.constraints) do
      {:ok, %{
        session_id: session_id,
        name: name,
        type: current_var.type,
        value: validated_value,
        updated_at: DateTime.utc_now()
      }}
    end
  end
  
  @doc """
  Delete a variable from the session.
  """
  @spec delete(binary(), binary()) :: :ok | {:error, term()}
  def delete(session_id, name) do
    Variables.delete(session_id, name)
  end
  
  @doc """
  List all variables in a session.
  
  ## Examples
  
      {:ok, variables} = Variables.list("session_1")
      # Returns: [%{name: "temperature", type: :float, value: 0.7, ...}, ...]
  """
  @spec list(binary()) :: {:ok, [map()]} | {:error, term()}
  def list(session_id) do
    Variables.list_session_variables(session_id)
  end
  
  @doc """
  Get information about supported variable types.
  """
  @spec supported_types() :: [map()]
  def supported_types do
    Variables.supported_types()
    |> Enum.map(fn type ->
      %{
        type: type,
        description: Variables.type_description(type),
        constraints_schema: Variables.type_constraints_schema(type)
      }
    end)
  end
  
  @doc """
  Watch for variable changes in a session.
  
  Returns a stream of variable change events.
  """
  @spec watch(binary()) :: Enumerable.t()
  def watch(session_id) do
    Variables.watch_session(session_id)
  end
  
  # Private helper functions
  
  defp ensure_session(session_id) do
    case SessionStore.get_session(session_id) do
      {:ok, session} -> {:ok, session}
      {:error, :not_found} -> SessionStore.create_session(session_id)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

#### Tools API (`snakepit/lib/snakepit/api/tools.ex`)

```elixir
defmodule Snakepit.API.Tools do
  @moduledoc """
  Clean API for bidirectional tool calling.
  
  Enables registration and execution of tools that can be called across
  language boundaries (Elixir ↔ Python).
  """
  
  alias Snakepit.Bridge.ToolRegistry
  
  @type tool_metadata :: %{
    description: binary(),
    parameters: [parameter_spec()],
    returns: return_spec(),
    examples: [example()]
  }
  
  @type parameter_spec :: %{
    name: binary(),
    type: binary(),
    required: boolean(),
    description: binary(),
    default: term()
  }
  
  @type return_spec :: %{
    type: binary(),
    description: binary()
  }
  
  @type example :: %{
    description: binary(),
    input: map(),
    output: term()
  }
  
  @doc """
  Register an Elixir function that Python can call.
  
  ## Parameters
  
    * `session_id` - Session scope for the tool
    * `name` - Tool name (unique within session)
    * `function` - Function reference or capture
    * `metadata` - Tool documentation and schema
  
  ## Examples
  
      Tools.register_elixir_tool("session_1", "validate_email", &MyApp.validate_email/1, %{
        description: "Validate email address format",
        parameters: [%{name: "email", type: "string", required: true}],
        returns: %{type: "boolean", description: "True if valid email"}
      })
  """
  @spec register_elixir_tool(binary(), binary(), function(), tool_metadata()) :: 
    {:ok, binary()} | {:error, term()}
  def register_elixir_tool(session_id, name, function, metadata \\ %{}) do
    with :ok <- validate_function(function),
         :ok <- validate_metadata(metadata),
         {:ok, tool_id} <- ToolRegistry.register_elixir_tool(session_id, name, function, metadata) do
      # Notify Python that this tool is available
      :ok = notify_python_tool_available(session_id, name, metadata)
      {:ok, tool_id}
    end
  end
  
  @doc """
  Execute a Python tool from Elixir.
  
  ## Examples
  
      {:ok, result} = Tools.execute_python_tool("session_1", "process_tensor", %{
        "tensor_data" => [[1, 2], [3, 4]],
        "operation" => "normalize"
      })
  """
  @spec execute_python_tool(binary(), binary(), map()) :: {:ok, term()} | {:error, term()}
  def execute_python_tool(session_id, name, parameters \\ %{}) do
    ToolRegistry.execute_python_tool(session_id, name, parameters) 
  end
  
  @doc """
  List all available tools in a session.
  
  ## Examples
  
      {:ok, tools} = Tools.list("session_1")
      # Returns: [%{name: "validate_email", language: "elixir", ...}, ...]
  """
  @spec list(binary()) :: {:ok, [map()]} | {:error, term()}
  def list(session_id) do
    ToolRegistry.list_session_tools(session_id)
  end
  
  @doc """
  Get detailed information about a specific tool.
  """
  @spec get_tool_info(binary(), binary()) :: {:ok, map()} | {:error, :not_found}
  def get_tool_info(session_id, tool_name) do
    ToolRegistry.get_tool_info(session_id, tool_name)
  end
  
  @doc """
  Remove a tool registration.
  """
  @spec unregister_tool(binary(), binary()) :: :ok | {:error, term()}
  def unregister_tool(session_id, tool_name) do
    ToolRegistry.unregister_tool(session_id, tool_name)
  end
  
  @doc """
  Execute any tool (Elixir or Python) by name.
  
  This is the unified execution interface that handles routing to
  the appropriate handler based on the tool's registered language.
  """
  @spec execute(binary(), binary(), map()) :: {:ok, term()} | {:error, term()}
  def execute(session_id, tool_name, parameters \\ %{}) do
    ToolRegistry.execute_tool(session_id, tool_name, parameters)
  end
  
  # Private helper functions
  
  defp validate_function(function) do
    if is_function(function) do
      :ok
    else
      {:error, "Tool handler must be a function"}
    end
  end
  
  defp validate_metadata(metadata) do
    # Basic metadata validation
    required_fields = [:description]
    missing_fields = required_fields -- Map.keys(metadata)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required metadata fields: #{inspect(missing_fields)}"}
    end
  end
  
  defp notify_python_tool_available(session_id, name, metadata) do
    # Notify Python side that an Elixir tool is available
    Snakepit.execute_in_session(session_id, "register_elixir_tool", %{
      "tool_name" => name,
      "metadata" => metadata
    })
    :ok
  end
end
```

#### DSPy API (`snakepit/lib/snakepit/api/dspy.ex`)

```elixir
defmodule Snakepit.API.DSPy do
  @moduledoc """
  Clean API for DSPy operations.
  
  Provides high-level interface for DSPy functionality including module calling,
  schema discovery, and enhanced workflows with tool integration.
  """
  
  @doc """
  Call any DSPy function with automatic introspection.
  
  ## Parameters
  
    * `session_id` - Session for the call
    * `module_path` - Python module path (e.g., "dspy.Predict")
    * `function_name` - Function to call (e.g., "__init__", "__call__")
    * `args` - Positional arguments
    * `kwargs` - Keyword arguments
  
  ## Examples
  
      # Create a DSPy predictor
      {:ok, result} = DSPy.call("session_1", "dspy.Predict", "__init__", [], %{
        "signature" => "question -> answer"
      })
      
      # Call the predictor
      {:ok, prediction} = DSPy.call("session_1", "stored.predictor_id", "__call__", [], %{
        "question" => "What is machine learning?"
      })
  """
  @spec call(binary(), binary(), binary(), list(), map()) :: {:ok, map()} | {:error, term()}
  def call(session_id, module_path, function_name, args \\ [], kwargs \\ %{}) do
    Snakepit.execute_in_session(session_id, "call_dspy", %{
      "module_path" => module_path,
      "function_name" => function_name,
      "args" => args,
      "kwargs" => kwargs
    })
    |> handle_dspy_response()
  end
  
  @doc """
  Discover DSPy module schema and available classes.
  
  ## Examples
  
      {:ok, schema} = DSPy.discover_schema("dspy")
      {:ok, optimizers} = DSPy.discover_schema("dspy.teleprompt")
  """
  @spec discover_schema(binary()) :: {:ok, map()} | {:error, term()}
  def discover_schema(module_path \\ "dspy") do
    Snakepit.execute("discover_dspy_schema", %{
      "module_path" => module_path
    })
    |> handle_dspy_response()
  end
  
  @doc """
  Enhanced prediction with tool integration.
  
  This allows DSPy prediction modules to call back to registered Elixir tools
  during the reasoning process.
  
  ## Examples
  
      # First register some tools
      {:ok, _} = Tools.register_elixir_tool("session_1", "validate_reasoning", 
                                           &MyApp.validate_reasoning/1)
      
      # Then use enhanced prediction
      {:ok, result} = DSPy.enhanced_predict("session_1", "question -> reasoning, answer", %{
        "question" => "Explain quantum computing",
        "domain" => "physics"
      })
  """
  @spec enhanced_predict(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def enhanced_predict(session_id, signature, inputs \\ %{}) do
    Snakepit.execute_in_session(session_id, "enhanced_predict", %{
      "signature" => signature,
      "inputs" => inputs
    })
    |> handle_dspy_response()
  end
  
  @doc """
  Enhanced chain of thought with tool integration.
  
  Similar to enhanced_predict but uses DSPy's ChainOfThought module for
  step-by-step reasoning.
  """
  @spec enhanced_chain_of_thought(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def enhanced_chain_of_thought(session_id, signature, inputs \\ %{}) do
    Snakepit.execute_in_session(session_id, "enhanced_chain_of_thought", %{
      "signature" => signature,
      "inputs" => inputs
    })
    |> handle_dspy_response()
  end
  
  @doc """
  Configure DSPy with a language model.
  
  ## Examples
  
      {:ok, _} = DSPy.configure_model("session_1", "openai", %{
        "api_key" => System.get_env("OPENAI_API_KEY"),
        "model" => "gpt-4"
      })
      
      {:ok, _} = DSPy.configure_model("session_1", "gemini", %{
        "api_key" => System.get_env("GOOGLE_API_KEY"),
        "model" => "gemini-pro"
      })
  """
  @spec configure_model(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def configure_model(session_id, model_type, config \\ %{}) do
    Snakepit.execute_in_session(session_id, "configure_lm", %{
      "model_type" => model_type
    } |> Map.merge(config))
    |> handle_dspy_response()
  end
  
  @doc """
  Check if DSPy is available and get version information.
  """
  @spec check_availability() :: {:ok, map()} | {:error, term()}
  def check_availability do 
    Snakepit.execute("check_dspy", %{})
    |> handle_dspy_response()
  end
  
  @doc """
  Create a DSPy instance and return reference for later use.
  
  ## Examples
  
      {:ok, {session_id, instance_id}} = DSPy.create_instance("dspy.Predict", %{
        "signature" => "question -> answer"
      })
  """
  @spec create_instance(binary(), map(), keyword()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def create_instance(class_path, args \\ %{}, opts \\ []) do
    session_id = opts[:session_id] || generate_session_id()
    
    case call(session_id, class_path, "__init__", [], args) do
      {:ok, %{"instance_id" => instance_id}} ->
        {:ok, {session_id, instance_id}}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Call a method on a stored DSPy instance.
  """
  @spec call_instance_method({binary(), binary()}, binary(), map()) :: {:ok, term()} | {:error, term()}
  def call_instance_method({session_id, instance_id}, method_name, args \\ %{}) do
    call(session_id, "stored.#{instance_id}", method_name, [], args)
  end
  
  # Private helper functions
  
  defp handle_dspy_response({:ok, %{"success" => true} = response}), do: {:ok, response}
  defp handle_dspy_response({:ok, %{"success" => false, "error" => error}}), do: {:error, error}
  defp handle_dspy_response({:error, reason}), do: {:error, reason}
  
  defp generate_session_id do
    "dspy_session_#{System.unique_integer([:positive])}"
  end
end
```

#### Sessions API (`snakepit/lib/snakepit/api/sessions.ex`)

```elixir
defmodule Snakepit.API.Sessions do
  @moduledoc """
  Clean API for session management.
  
  Provides session lifecycle operations and metadata management.
  """
  
  alias Snakepit.Bridge.SessionStore
  
  @doc """
  Create a new session with optional configuration.
  
  ## Examples
  
      {:ok, session} = Sessions.create("ml_session_1", %{
        ttl: 7200, # 2 hours
        metadata: %{user_id: "user_123", project: "ml_experiment"}
      })
  """
  @spec create(binary(), map()) :: {:ok, map()} | {:error, term()}
  def create(session_id, config \\ %{}) do
    SessionStore.create_session(session_id, config)
  end
  
  @doc """
  Get session information.
  """
  @spec get(binary()) :: {:ok, map()} | {:error, :not_found}
  def get(session_id) do
    SessionStore.get_session(session_id)
  end
  
  @doc """
  Update session metadata.
  """
  @spec update_metadata(binary(), map()) :: {:ok, map()} | {:error, term()}
  def update_metadata(session_id, metadata) do
    SessionStore.update_session_metadata(session_id, metadata)
  end
  
  @doc """
  Extend session TTL.
  """
  @spec extend_ttl(binary(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def extend_ttl(session_id, additional_seconds) do
    SessionStore.extend_session_ttl(session_id, additional_seconds)
  end
  
  @doc """
  List all active sessions.
  """
  @spec list() :: {:ok, [map()]}
  def list do
    SessionStore.list_sessions()
  end
  
  @doc """
  Delete a session and clean up all associated data.
  """
  @spec delete(binary()) :: :ok | {:error, term()}
  def delete(session_id) do
    SessionStore.delete_session(session_id)
  end
  
  @doc """
  Get session statistics.
  """
  @spec stats() :: map()
  def stats do
    SessionStore.get_stats()
  end
end
```

## 🎯 Ultra-Thin DSPex Integration

### Refactored DSPex Structure

#### Main Module (`dspex/lib/dspex.ex`)

```elixir
defmodule DSPex do
  @moduledoc """
  DSPex - Elixir interface for DSPy functionality.
  
  This module provides high-level convenience functions that orchestrate
  DSPy workflows using the clean Snakepit APIs.
  """
  
  alias Snakepit.API.{DSPy, Variables, Tools, Sessions}
  
  @doc """
  Execute a simple prediction using DSPy.
  
  ## Examples
  
      {:ok, result} = DSPex.predict("question -> answer", %{
        question: "What is machine learning?"
      })
  """
  @spec predict(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || create_temp_session()
    
    # Use Snakepit's clean API
    DSPy.enhanced_predict(session_id, signature, inputs)
  end
  
  @doc """
  Execute chain of thought reasoning.
  """
  @spec chain_of_thought(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chain_of_thought(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || create_temp_session()
    
    DSPy.enhanced_chain_of_thought(session_id, signature, inputs)  
  end
  
  @doc """
  Discover available DSPy modules and classes.
  """
  @spec discover_modules(binary()) :: {:ok, map()} | {:error, term()}
  def discover_modules(module_path \\ "dspy") do
    DSPy.discover_schema(module_path)
  end
  
  @doc """
  Configure language model for DSPy operations.
  """
  @spec configure_model(binary(), map()) :: {:ok, map()} | {:error, term()}
  def configure_model(model_type, config \\ %{}) do
    session_id = create_temp_session()
    DSPy.configure_model(session_id, model_type, config)
  end
  
  @doc """
  Create a managed session for complex workflows.
  
  ## Examples
  
      {:ok, session_id} = DSPex.create_session(%{
        ttl: 7200,
        model_type: "openai",
        model_config: %{api_key: System.get_env("OPENAI_API_KEY")}
      })
      
      {:ok, result} = DSPex.predict("question -> answer", %{
        question: "Explain neural networks"
      }, session_id: session_id)
  """
  @spec create_session(map()) :: {:ok, binary()} | {:error, term()}
  def create_session(config \\ %{}) do
    session_id = "dspex_#{System.unique_integer([:positive])}"
    
    with {:ok, _session} <- Sessions.create(session_id, config),
         {:ok, _model} <- maybe_configure_model(session_id, config) do
      {:ok, session_id}
    end
  end
  
  @doc """
  Get system health information.
  """
  @spec health_check() :: map()
  def health_check do
    %{
      status: :ok,
      version: Application.spec(:dspex, :vsn) |> to_string(),
      snakepit_status: Snakepit.get_stats(),
      dspy_available: case DSPy.check_availability() do
        {:ok, info} -> info
        {:error, _} -> %{available: false}
      end
    }
  end
  
  # Private helper functions
  
  defp create_temp_session do
    session_id = "temp_#{System.unique_integer([:positive])}"
    {:ok, _} = Sessions.create(session_id, %{ttl: 300}) # 5 minutes
    session_id
  end
  
  defp maybe_configure_model(session_id, config) do
    case {config[:model_type], config[:model_config]} do
      {nil, _} -> {:ok, :not_configured}
      {model_type, model_config} when is_binary(model_type) ->
        DSPy.configure_model(session_id, model_type, model_config || %{})
      _ -> {:ok, :not_configured}
    end
  end
end
```

#### Bridge Module (`dspex/lib/dspex/bridge.ex`)

```elixir
defmodule DSPex.Bridge do
  @moduledoc """
  DSPy bridge with code generation capabilities.
  
  This module contains ONLY the defdsyp macro for generating DSPy wrapper modules.
  All runtime functionality delegates to Snakepit.API.* modules.
  """
  
  alias Snakepit.API.{DSPy, Variables, Tools}
  
  @doc false
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge, only: [defdsyp: 2, defdsyp: 3]
    end
  end
  
  @doc """
  Generate a DSPy wrapper module with automatic API integration.
  
  ## Usage
  
      defmodule MyApp.CustomPredictor do
        use DSPex.Bridge
        
        defdsyp __MODULE__, "dspy.Predict", %{
          execute_method: "__call__",
          result_transform: &transform_prediction/1,
          register_tools: ["validate_input", "format_output"]
        }
      end
  
  ## Generated Functions
  
    * `create/2` - Create instance using Snakepit.API.DSPy
    * `execute/2` - Execute using configured method
    * `call/2` - Stateless create and execute
  """
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    quote bind_quoted: [
      module_name: module_name,
      class_path: class_path,
      config: config
    ] do
      
      defmodule module_name do
        @class_path class_path
        @config config
        
        @doc """
        Create a new #{@class_path} instance.
        
        Returns `{:ok, {session_id, instance_id}}` for later use.
        """
        def create(args \\ %{}, opts \\ []) do
          session_id = opts[:session_id] || create_session_id()
          
          # Register any tools specified in config
          if @config[:register_tools] do
            register_configured_tools(session_id, @config[:register_tools])
          end
          
          # Create DSPy instance using clean API
          case DSPy.call(session_id, @class_path, "__init__", [], args) do
            {:ok, %{"instance_id" => instance_id}} ->
              {:ok, {session_id, instance_id}}
            {:error, reason} ->
              {:error, "#{@class_path} creation failed: #{reason}"}
          end
        end
        
        @doc """
        Execute the primary method on the instance.
        """
        def execute({session_id, instance_id}, inputs \\ %{}) do
          method_name = @config[:execute_method] || "__call__"
          
          case DSPy.call(session_id, "stored.#{instance_id}", method_name, [], inputs) do
            {:ok, %{"result" => result}} ->
              transformed_result = apply_result_transform(result)
              {:ok, transformed_result}
            {:error, reason} ->
              {:error, "#{@class_path}.#{method_name} failed: #{reason}"}
          end
        end
        
        @doc """
        Stateless create and execute in one call.
        """
        def call(args, inputs \\ %{}, opts \\ []) do
          with {:ok, instance_ref} <- create(args, opts),
               {:ok, result} <- execute(instance_ref, inputs) do
            {:ok, result}
          end
        end
        
        # Generate additional methods based on config
        unquote(
          for {python_method, elixir_method} <- config[:methods] || %{} do
            quote do
              @doc """
              Call #{unquote(python_method)} method on the instance.
              """
              def unquote(String.to_atom(elixir_method))({session_id, instance_id}, args \\ %{}) do
                case DSPy.call(session_id, "stored.#{instance_id}", unquote(python_method), [], args) do
                  {:ok, %{"result" => result}} -> {:ok, result}
                  {:error, reason} -> {:error, "#{@class_path}.#{unquote(python_method)} failed: #{reason}"}
                end
              end
            end
          end
        )
        
        # Private helper functions for the generated module
        
        defp create_session_id do
          "#{@class_path |> String.replace(".", "_")}_#{System.unique_integer([:positive])}"
        end
        
        defp register_configured_tools(session_id, tool_names) do
          for tool_name <- tool_names do
            case :erlang.function_exported(__MODULE__, String.to_atom(tool_name), 1) do
              true ->
                tool_func = &apply(__MODULE__, String.to_atom(tool_name), [&1])
                Tools.register_elixir_tool(session_id, tool_name, tool_func)
              false ->
                # Tool function not found - continue without registering
                :ok
            end
          end
        end
        
        defp apply_result_transform(result) do
          if @config[:result_transform] do
            @config[:result_transform].(result)
          else
            result
          end
        end
      end
    end
  end
  
  # Convenience delegation functions (thin wrappers around Snakepit.API)
  
  @doc """
  Call any DSPy function directly.
  """
  @spec call_dspy(binary(), binary(), list(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def call_dspy(module_path, function_name, args \\ [], kwargs \\ %{}, opts \\ []) do
    session_id = opts[:session_id] || create_temp_session()
    DSPy.call(session_id, module_path, function_name, args, kwargs)
  end
  
  @doc """
  Discover DSPy schema.
  """
  @spec discover_schema(binary()) :: {:ok, map()} | {:error, term()}
  def discover_schema(module_path \\ "dspy") do
    DSPy.discover_schema(module_path)
  end
  
  @doc """
  Create a DSPy instance.
  """
  @spec create_instance(binary(), map(), keyword()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def create_instance(class_path, args \\ %{}, opts \\ []) do
    DSPy.create_instance(class_path, args, opts)
  end
  
  @doc """
  Call method on stored instance.
  """
  @spec call_instance_method({binary(), binary()}, binary(), map()) :: {:ok, term()} | {:error, term()}
  def call_instance_method({session_id, instance_id}, method_name, args \\ %{}) do
    DSPy.call_instance_method({session_id, instance_id}, method_name, args)
  end
  
  # Private helper
  
  defp create_temp_session do
    session_id = "bridge_temp_#{System.unique_integer([:positive])}"
    {:ok, _} = Snakepit.API.Sessions.create(session_id, %{ttl: 300})
    session_id
  end
end
```

## 📊 Benefits of New Design

### Clean Separation of Concerns

```
DSPex Responsibilities:
✅ defdsyp macro (code generation)
✅ High-level workflow orchestration  
✅ Convenience functions for common patterns
✅ Example integrations and documentation

Snakepit Responsibilities:
✅ Variables system (storage, types, constraints)
✅ Tool bridge (bidirectional calling)
✅ DSPy integration (Python runtime)
✅ Session management (lifecycle, cleanup)
✅ Process pooling (infrastructure)
```

### Loose Coupling

```elixir
# Before: Direct internal calls
DSPex.Bridge.call_dspy() -> Snakepit.execute_in_session() -> Internal complexity

# After: Clean API calls  
DSPex.Bridge.call_dspy() -> Snakepit.API.DSPy.call() -> Clean interface
```

### Easy Testing

```elixir
# Test DSPex in isolation by mocking Snakepit.API
defmodule DSPexTest do
  use ExUnit.Case
  import Mox
  
  test "predict/2 calls DSPy API correctly" do
    expect(MockSnakepitAPI, :enhanced_predict, fn session_id, signature, inputs ->
      {:ok, %{prediction: "test result"}}
    end)
    
    assert {:ok, %{prediction: "test result"}} = DSPex.predict("q -> a", %{q: "test"})
  end
end
```

### Maintainability

- ✅ **DSPex changes**: Only affect orchestration logic
- ✅ **Snakepit changes**: Hidden behind stable API interfaces  
- ✅ **Python changes**: Isolated to Snakepit implementation
- ✅ **API versioning**: Can evolve APIs independently

This clean architecture provides proper separation while maintaining ease of use and enabling independent evolution of both projects.
# DSPex Consumer Layer Specification

## Overview

DSPex becomes an **ultra-thin orchestration layer** that provides a clean, user-friendly API for ML workflows. It contains only macros, convenience functions, and high-level abstractions - **no Python code, no bridge logic, no domain-specific functionality**.

## Core Principles

### 1. Pure Orchestration
- High-level convenience APIs for common ML patterns
- `defdsyp` macro for generating DSPy wrapper modules
- Simple configuration and setup
- **Zero domain-specific implementation**

### 2. Elegant Developer Experience
- Simple, intuitive APIs
- Minimal configuration required
- Clear documentation and examples
- Excellent error messages

### 3. Thin Layer Over Platform
- All heavy lifting delegated to SnakepitGRPCBridge
- Clean dependency on ML platform
- No direct infrastructure dependencies

## Module Architecture

### Consumer Structure
```
dspex/
├── lib/
│   ├── dspex.ex                      # Main convenience API
│   ├── dspex/
│   │   ├── bridge.ex                 # defdsyp macro and code generation
│   │   ├── api.ex                    # High-level convenience functions
│   │   ├── sessions.ex               # Session management helpers
│   │   ├── workflows.ex              # Workflow orchestration helpers
│   │   └── config.ex                 # Configuration helpers
├── test/
├── mix.exs                           # Depends on snakepit_grpc_bridge
├── README.md                         # Excellent documentation
└── NO PYTHON CODE                   # Pure Elixir orchestration
```

## Detailed Module Specifications

### 1. Main API (`lib/dspex.ex`)

```elixir
defmodule DSPex do
  @moduledoc """
  DSPex - Elegant Elixir interface for machine learning workflows.
  
  DSPex provides a clean, high-level API for ML operations built on the
  SnakepitGRPCBridge platform. Focus on your ML logic, not infrastructure.
  
  ## Quick Start
  
      # Simple prediction
      {:ok, result} = DSPex.predict("question -> answer", %{
        question: "What is the capital of France?"
      })
      
      # With variables
      DSPex.set_variable("temperature", 0.7)
      {:ok, result} = DSPex.predict("question -> answer", %{
        question: "Explain quantum computing"
      })
      
      # Chain of thought
      {:ok, result} = DSPex.chain_of_thought("question -> reasoning, answer", %{
        question: "Why is the sky blue?"
      })
  
  ## Advanced Usage
  
      # Custom session
      {:ok, session} = DSPex.start_session()
      DSPex.register_tool(session, "validate", &MyApp.validate_input/1)
      {:ok, result} = DSPex.enhanced_predict(session, signature, inputs)
      DSPex.stop_session(session)
  """

  alias SnakepitGRPCBridge.API

  @doc """
  Simple prediction with automatic session management.
  
  Perfect for one-off predictions where you don't need session state.
  
  ## Examples
  
      {:ok, result} = DSPex.predict("question -> answer", %{
        question: "What is Elixir?"
      })
      
      {:ok, result} = DSPex.predict(
        "context, question -> answer", 
        %{
          context: "Elixir is a functional programming language...",
          question: "What paradigm does Elixir follow?"
        }
      )
  """
  @spec predict(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def predict(signature, inputs, opts \\ []) do
    with_auto_session(fn session_id ->
      API.DSPy.enhanced_predict(session_id, signature, inputs, opts)
    end)
  end

  @doc """
  Chain of thought reasoning with automatic session management.
  
  Provides detailed reasoning steps along with the final answer.
  
  ## Examples
  
      {:ok, result} = DSPex.chain_of_thought("question -> reasoning, answer", %{
        question: "Why do leaves change color in autumn?"
      })
      
      # Result includes both reasoning and answer
      reasoning = result["reasoning"]
      answer = result["answer"]
  """
  @spec chain_of_thought(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chain_of_thought(signature, inputs, opts \\ []) do
    with_auto_session(fn session_id ->
      API.DSPy.enhanced_chain_of_thought(session_id, signature, inputs, opts)
    end)
  end

  @doc """
  Set a global variable that persists across predictions.
  
  Variables are automatically used by DSPy operations when relevant.
  
  ## Examples
  
      DSPex.set_variable("temperature", 0.7)
      DSPex.set_variable("model", "gpt-4")
      DSPex.set_variable("max_tokens", 150)
      
      # These variables will be used in subsequent predictions
      {:ok, result} = DSPex.predict("question -> answer", inputs)
  """
  @spec set_variable(String.t(), term()) :: :ok | {:error, term()}
  def set_variable(name, value) do
    with_global_session(fn session_id ->
      API.Variables.set(session_id, name, value)
    end)
  end

  @doc """
  Get a global variable value.
  
  ## Examples
  
      {:ok, 0.7} = DSPex.get_variable("temperature")
      {:ok, 1.0} = DSPex.get_variable("unknown_var", 1.0)  # with default
  """
  @spec get_variable(String.t(), term()) :: {:ok, term()} | {:error, term()}
  def get_variable(name, default \\ nil) do
    with_global_session(fn session_id ->
      API.Variables.get(session_id, name, default)
    end)
  end

  @doc """
  Register an Elixir function as a tool available to ML operations.
  
  Tools enable bidirectional communication between ML operations and Elixir code.
  
  ## Examples
  
      DSPex.register_tool("validate_email", &MyApp.Validators.email/1)
      DSPex.register_tool("fetch_data", &MyApp.Data.fetch/1)
      DSPex.register_tool("process_result", fn data ->
        data |> MyApp.process() |> MyApp.format()
      end)
      
      # Tools are automatically available in DSPy operations
      {:ok, result} = DSPex.predict("email -> validation_result", %{
        email: "user@example.com"
      })
  """
  @spec register_tool(String.t(), function(), keyword()) :: :ok | {:error, term()}
  def register_tool(name, function, opts \\ []) do
    with_global_session(fn session_id ->
      API.Tools.register_elixir_function(session_id, name, function, opts)
    end)
  end

  @doc """
  Call a registered tool directly.
  
  ## Examples
  
      {:ok, true} = DSPex.call_tool("validate_email", %{email: "test@example.com"})
  """
  @spec call_tool(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(name, parameters) do
    with_global_session(fn session_id ->
      API.Tools.call(session_id, name, parameters)
    end)
  end

  @doc """
  Start a new session for advanced operations.
  
  Sessions provide isolated state for complex workflows.
  
  ## Examples
  
      {:ok, session} = DSPex.start_session()
      DSPex.set_session_variable(session, "context", "financial analysis")
      {:ok, result} = DSPex.predict_with_session(session, signature, inputs)
      DSPex.stop_session(session)
  """
  @spec start_session(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_session(opts \\ []) do
    session_id = DSPex.Sessions.generate_session_id()
    
    case API.Variables.create(session_id, "_session_metadata", :map, %{
      created_at: DateTime.utc_now(),
      options: opts
    }) do
      {:ok, _} -> {:ok, session_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop a session and clean up resources.
  
  ## Examples
  
      DSPex.stop_session(session)
  """
  @spec stop_session(String.t()) :: :ok | {:error, term()}
  def stop_session(session_id) do
    # Implementation would clean up session
    :ok
  end

  @doc """
  Enhanced prediction with session state.
  
  ## Examples
  
      {:ok, result} = DSPex.predict_with_session(session, signature, inputs,
        optimization_level: :high,
        reasoning_enabled: true
      )
  """
  @spec predict_with_session(String.t(), String.t(), map(), keyword()) :: 
    {:ok, map()} | {:error, term()}
  def predict_with_session(session_id, signature, inputs, opts \\ []) do
    API.DSPy.enhanced_predict(session_id, signature, inputs, opts)
  end

  @doc """
  Set variable in specific session.
  
  ## Examples
  
      DSPex.set_session_variable(session, "temperature", 0.9)
  """
  @spec set_session_variable(String.t(), String.t(), term()) :: :ok | {:error, term()}
  def set_session_variable(session_id, name, value) do
    API.Variables.set(session_id, name, value)
  end

  @doc """
  Create a multi-step workflow.
  
  ## Examples
  
      {:ok, workflow} = DSPex.create_workflow([
        {:extract, "document -> keywords", %{name: "extract_keywords"}},
        {:analyze, "keywords -> themes", %{name: "find_themes"}},
        {:summarize, "themes -> summary", %{name: "create_summary"}}
      ])
      
      {:ok, results} = DSPex.execute_workflow(workflow, %{
        document: "Long document text..."
      })
  """
  @spec create_workflow([tuple()], keyword()) :: {:ok, map()} | {:error, term()}
  def create_workflow(steps, opts \\ []) do
    with_auto_session(fn session_id ->
      API.DSPy.create_workflow(session_id, steps, opts)
    end)
  end

  @doc """
  Execute a workflow with inputs.
  """
  @spec execute_workflow(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_workflow(%{session_id: session_id, workflow_id: workflow_id}, inputs, opts \\ []) do
    API.DSPy.execute_workflow(session_id, workflow_id, inputs, opts)
  end

  # Private helper functions for session management
  
  defp with_auto_session(fun) when is_function(fun, 1) do
    session_id = DSPex.Sessions.generate_temp_session_id()
    
    try do
      fun.(session_id)
    after
      # Clean up temporary session
      :ok
    end
  end

  defp with_global_session(fun) when is_function(fun, 1) do
    session_id = DSPex.Sessions.get_or_create_global_session()
    fun.(session_id)
  end
end
```

### 2. Bridge Macros (`lib/dspex/bridge.ex`)

```elixir
defmodule DSPex.Bridge do
  @moduledoc """
  Code generation macros for creating DSPy wrapper modules.
  
  The `defdsyp` macro generates clean Elixir modules that wrap DSPy classes,
  providing type safety and documentation.
  """

  @doc """
  Generate a DSPy wrapper module with clean Elixir interface.
  
  ## Usage
  
      defmodule MyApp.Predictor do
        use DSPex.Bridge
        
        defdsyp __MODULE__, "dspy.Predict", %{
          signature: "question -> answer",
          description: "General question answering",
          examples: [
            %{question: "What is Elixir?", answer: "A functional programming language..."}
          ]
        }
      end
      
      # Generated module provides clean interface:
      {:ok, predictor} = MyApp.Predictor.create()
      {:ok, result} = MyApp.Predictor.execute(predictor, %{question: "What is DSPy?"})
  """
  defmacro defdsyp(module_name, class_path, config \\ %{}) do
    quote bind_quoted: [
      module_name: module_name,
      class_path: class_path,
      config: config
    ] do
      
      @class_path class_path
      @config config
      @signature config[:signature] || "input -> output"
      @description config[:description] || "DSPy wrapper for #{class_path}"

      @doc """
      Create a new instance of #{@class_path}.
      
      #{@description}
      
      ## Examples
      
          {:ok, instance} = #{module_name}.create()
          {:ok, instance} = #{module_name}.create(session_id: "my_session")
      """
      def create(opts \\ []) do
        session_id = opts[:session_id] || DSPex.Sessions.generate_temp_session_id()
        
        # Create instance through platform API
        case SnakepitGRPCBridge.API.DSPy.call(
          session_id,
          @class_path,
          "__init__",
          %{signature: @signature},
          opts
        ) do
          {:ok, %{"instance_id" => instance_id}} ->
            {:ok, {session_id, instance_id}}
          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      Execute the DSPy module with given inputs.
      
      Signature: #{@signature}
      
      ## Examples
      
          {:ok, result} = #{module_name}.execute(instance, inputs)
      """
      def execute({session_id, instance_id}, inputs, opts \\ []) do
        # Use enhanced execution through platform
        SnakepitGRPCBridge.API.DSPy.enhanced_predict(
          session_id, 
          @signature, 
          inputs,
          Keyword.merge(opts, [instance_id: instance_id])
        )
      end

      @doc """
      One-shot execution (create instance and execute immediately).
      
      ## Examples
      
          {:ok, result} = #{module_name}.call(inputs)
      """
      def call(inputs, opts \\ []) do
        with {:ok, instance} <- create(opts),
             {:ok, result} <- execute(instance, inputs, opts) do
          {:ok, result}
        end
      end

      if @config[:enhanced_mode] do
        @doc """
        Enhanced execution with chain of thought reasoning.
        
        Available because enhanced_mode is enabled.
        """
        def chain_of_thought({session_id, _instance_id}, inputs, opts \\ []) do
          SnakepitGRPCBridge.API.DSPy.enhanced_chain_of_thought(
            session_id, 
            @signature, 
            inputs,
            opts
          )
        end
      end

      # Generate additional methods based on config
      for {method_name, elixir_name} <- (@config[:methods] || %{}) do
        @doc """
        Call #{method_name} method on the DSPy instance.
        """
        def unquote(String.to_atom(elixir_name))({session_id, instance_id}, args \\ %{}) do
          SnakepitGRPCBridge.API.DSPy.call(
            session_id,
            "stored.#{instance_id}",
            unquote(method_name),
            args
          )
        end
      end

      @doc """
      Get module metadata and configuration.
      """
      def __dspex_info__ do
        %{
          class_path: @class_path,
          signature: @signature,
          description: @description,
          config: @config,
          module: __MODULE__
        }
      end
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import DSPex.Bridge, only: [defdsyp: 2, defdsyp: 3]
    end
  end
end
```

### 3. High-Level API (`lib/dspex/api.ex`)

```elixir
defmodule DSPex.API do
  @moduledoc """
  High-level convenience functions for common ML patterns.
  
  These functions provide simple interfaces for the most common use cases,
  with sensible defaults and automatic optimization.
  """

  @doc """
  Quick question answering with automatic optimization.
  
  ## Examples
  
      {:ok, answer} = DSPex.API.ask("What is the capital of France?")
      {:ok, answer} = DSPex.API.ask("Explain photosynthesis", reasoning: true)
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    signature = if opts[:reasoning], do: "question -> reasoning, answer", else: "question -> answer"
    
    case DSPex.predict(signature, %{question: question}, opts) do
      {:ok, result} when is_map(result) ->
        answer = result["answer"] || result[:answer]
        {:ok, answer}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Text classification with configurable categories.
  
  ## Examples
  
      {:ok, category} = DSPex.API.classify(
        "I love this product!", 
        ["positive", "negative", "neutral"]
      )
      
      {:ok, category} = DSPex.API.classify(
        "This is about machine learning",
        ["technology", "business", "entertainment", "sports"]
      )
  """
  @spec classify(String.t(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def classify(text, categories, opts \\ []) do
    categories_str = Enum.join(categories, ", ")
    signature = "text, categories -> category"
    
    case DSPex.predict(signature, %{
      text: text,
      categories: categories_str
    }, opts) do
      {:ok, result} when is_map(result) ->
        category = result["category"] || result[:category]
        {:ok, category}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Text summarization with configurable length.
  
  ## Examples
  
      {:ok, summary} = DSPex.API.summarize("Long text to summarize...")
      {:ok, summary} = DSPex.API.summarize(text, max_length: 100)
  """
  @spec summarize(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def summarize(text, opts \\ []) do
    max_length = opts[:max_length] || 150
    signature = "text, max_length -> summary"
    
    case DSPex.predict(signature, %{
      text: text,
      max_length: max_length
    }, opts) do
      {:ok, result} when is_map(result) ->
        summary = result["summary"] || result[:summary]
        {:ok, summary}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract entities from text.
  
  ## Examples
  
      {:ok, entities} = DSPex.API.extract_entities(
        "Apple Inc. was founded by Steve Jobs in California."
      )
      # Returns: %{organizations: ["Apple Inc."], people: ["Steve Jobs"], locations: ["California"]}
  """
  @spec extract_entities(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def extract_entities(text, opts \\ []) do
    entity_types = opts[:types] || ["people", "organizations", "locations"]
    signature = "text, entity_types -> entities"
    
    case DSPex.predict(signature, %{
      text: text,
      entity_types: Enum.join(entity_types, ", ")
    }, opts) do
      {:ok, result} when is_map(result) ->
        entities = result["entities"] || result[:entities]
        {:ok, entities}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate text based on a prompt and style.
  
  ## Examples
  
      {:ok, story} = DSPex.API.generate(
        "A story about a robot learning to paint",
        style: "whimsical",
        length: 200
      )
  """
  @spec generate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    style = opts[:style] || "natural"
    length = opts[:length] || 150
    signature = "prompt, style, length -> generated_text"
    
    case DSPex.predict(signature, %{
      prompt: prompt,
      style: style,
      length: length
    }, opts) do
      {:ok, result} when is_map(result) ->
        text = result["generated_text"] || result[:generated_text]
        {:ok, text}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Question answering with context document.
  
  ## Examples
  
      {:ok, answer} = DSPex.API.answer_with_context(
        "What is the main benefit?",
        "Context: Elixir provides fault tolerance through the actor model..."
      )
  """
  @spec answer_with_context(String.t(), String.t(), keyword()) :: 
    {:ok, String.t()} | {:error, term()}
  def answer_with_context(question, context, opts \\ []) do
    signature = "context, question -> answer"
    
    case DSPex.predict(signature, %{
      context: context,
      question: question
    }, opts) do
      {:ok, result} when is_map(result) ->
        answer = result["answer"] || result[:answer]
        {:ok, answer}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 4. Session Management (`lib/dspex/sessions.ex`)

```elixir
defmodule DSPex.Sessions do
  @moduledoc """
  Session management utilities for DSPex.
  
  Provides convenient session management for both simple and advanced use cases.
  """

  @global_session_key :dspex_global_session
  @temp_session_prefix "temp_session_"

  @doc """
  Generate a unique session ID.
  
  ## Examples
  
      session_id = DSPex.Sessions.generate_session_id()
  """
  @spec generate_session_id() :: String.t()
  def generate_session_id do
    "session_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  @doc """
  Generate a temporary session ID for one-off operations.
  """
  @spec generate_temp_session_id() :: String.t()
  def generate_temp_session_id do
    @temp_session_prefix <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @doc """
  Get or create the global session for simple operations.
  """
  @spec get_or_create_global_session() :: String.t()
  def get_or_create_global_session do
    case Process.get(@global_session_key) do
      nil ->
        session_id = generate_session_id()
        Process.put(@global_session_key, session_id)
        session_id
      session_id ->
        session_id
    end
  end

  @doc """
  Clear the global session.
  """
  @spec clear_global_session() :: :ok
  def clear_global_session do
    Process.delete(@global_session_key)
    :ok
  end

  @doc """
  Check if a session ID is temporary.
  """
  @spec temp_session?(String.t()) :: boolean()
  def temp_session?(session_id) do
    String.starts_with?(session_id, @temp_session_prefix)
  end
end
```

### 5. Configuration (`lib/dspex/config.ex`)

```elixir
defmodule DSPex.Config do
  @moduledoc """
  Configuration utilities for DSPex.
  
  Provides simple configuration management for common settings.
  """

  @doc """
  Set default model configuration.
  
  ## Examples
  
      DSPex.Config.set_defaults(
        temperature: 0.7,
        model: "gpt-4",
        max_tokens: 150
      )
  """
  @spec set_defaults(keyword()) :: :ok
  def set_defaults(config) when is_list(config) do
    Enum.each(config, fn {key, value} ->
      DSPex.set_variable(to_string(key), value)
    end)
  end

  @doc """
  Get current configuration.
  
  ## Examples
  
      config = DSPex.Config.get_current()
  """
  @spec get_current() :: map()
  def get_current do
    # Implementation would gather current variable values
    %{}
  end

  @doc """
  Load configuration from file.
  
  ## Examples
  
      DSPex.Config.load_from_file("config/ml_config.exs")
  """
  @spec load_from_file(String.t()) :: :ok | {:error, term()}
  def load_from_file(file_path) do
    # Implementation would load and apply configuration
    :ok
  end
end
```

### 6. Main Configuration (`mix.exs`)

```elixir
defmodule DSPex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dspex,
      version: "0.2.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: "Elegant Elixir interface for machine learning workflows",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core dependency on ML platform
      {:snakepit_grpc_bridge, "~> 0.1.0"},
      
      # Development and testing
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "dspex",
      files: ~w(lib mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/your-org/dspex"}
    ]
  end

  defp docs do
    [
      main: "DSPex",
      extras: ["README.md"]
    ]
  end
end
```

## Key Features

### 1. Ultra-Thin Layer
- Only macros, convenience functions, and high-level abstractions
- All heavy lifting delegated to SnakepitGRPCBridge
- **Zero Python code or bridge logic**

### 2. Elegant Developer Experience
- Clean, intuitive APIs for common ML patterns
- Minimal configuration required
- Excellent documentation and examples
- Smart defaults with easy customization

### 3. Code Generation
- `defdsyp` macro generates clean wrapper modules
- Type-safe interfaces with documentation
- Automatic optimization hooks

### 4. Session Management
- Automatic session management for simple use cases
- Advanced session control for complex workflows
- Clean resource management

### 5. High-Level Patterns
- Question answering, classification, summarization
- Entity extraction, text generation
- Context-aware operations
- Workflow orchestration

This specification defines DSPex as a pure orchestration layer that provides an elegant developer experience while delegating all implementation to the underlying ML platform.
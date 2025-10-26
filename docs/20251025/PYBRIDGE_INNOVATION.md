# PyBridge: Configuration-Driven Python Library Integration for Elixir

**Innovation Date**: 2025-10-25
**Status**: Design Document
**Target**: Snakepit Component / Standalone Library

---

## Executive Summary

**PyBridge** is a metaprogramming-driven framework that enables **zero-code Python library integration into Elixir through declarative configuration**. Instead of manually writing wrappers for each Python library (DSPy, LangChain, Transformers, PyTorch, etc.), developers provide a configuration schema that describes the Python API, and PyBridge automatically generates:

1. **Type-safe Elixir modules** with full documentation
2. **gRPC/streaming-ready communication** via Snakepit
3. **Bidirectional tool calling** (Python ↔ Elixir)
4. **Automatic introspection** and schema discovery
5. **Client generation** with ExDoc integration

The innovation bridges the gap between Elixir's metaprogramming power and Python's ML ecosystem, making it trivial to integrate any Python library with minimal configuration overhead.

---

## The Problem

### Current State: Manual Wrapper Hell

Integrating a Python library into Elixir today requires:

1. **Manual wrapper modules** for every class/function
2. **Hardcoded JSON serialization** logic
3. **Repetitive error handling** boilerplate
4. **No type safety** or compile-time guarantees
5. **Fragile maintenance** when Python APIs change
6. **Documentation drift** between Python and Elixir sides

**Example**: DSPex currently has ~20+ files to wrap DSPy, each written manually:
- `lib/dspex/modules/predict.ex` (115 lines)
- `lib/dspex/modules/chain_of_thought.ex` (similar boilerplate)
- `lib/dspex/bridge.ex` (494 lines of metaprogramming scaffolding)

This doesn't scale when you want to integrate **20+ major ML libraries** (PyTorch, TensorFlow, LangChain, Transformers, JAX, scikit-learn, etc.).

### The Vision: Configuration > Code

What if instead of writing code, you just declared:

```elixir
# config/pybridge/dspy.exs
%PyBridge.Config{
  python_module: "dspy",
  version: "2.5.0",

  introspection: %{
    enabled: true,
    cache_path: "priv/pybridge/schemas/dspy.json",
    submodules: ["teleprompt", "evaluate", "retrieve"]
  },

  classes: [
    %{
      python_path: "dspy.Predict",
      elixir_module: DSPex.Predict,
      constructor: %{
        args: [signature: :string],
        session_aware: true
      },
      methods: [
        %{name: "__call__", elixir_name: :execute, streaming: false},
        %{name: "forward", elixir_name: :forward, streaming: false}
      ],
      result_transform: &DSPex.Transforms.prediction/1
    },

    %{
      python_path: "dspy.ChainOfThought",
      elixir_module: DSPex.ChainOfThought,
      extends: DSPex.Predict,  # Inherits common behavior
      methods: [
        %{name: "__call__", elixir_name: :think, streaming: true}
      ]
    }
  ],

  functions: [
    %{
      python_path: "dspy.settings.configure",
      elixir_name: :configure,
      args: [lm: :any, rm: {:optional, :any}]
    }
  ],

  bidirectional_tools: %{
    enabled: true,
    export_to_python: [
      {DSPex.Validators, :validate_reasoning},
      {DSPex.Metrics, :track_prediction}
    ]
  }
}
```

And PyBridge **automatically generates** at compile time:

```elixir
defmodule DSPex.Predict do
  @moduledoc """
  Elixir wrapper for dspy.Predict.

  ## Python Source

  Module: dspy.Predict

  Basic prediction module without intermediate reasoning.

  ## Examples

      iex> {:ok, pred} = DSPex.Predict.create("question -> answer")
      iex> {:ok, result} = DSPex.Predict.execute(pred, %{question: "What is DSPy?"})
      {:ok, %{answer: "..."}}
  """

  use PyBridge.Generator

  @type t :: PyBridge.InstanceRef.t()

  @spec create(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(signature, opts \\ []) do
    # Auto-generated from config
  end

  @spec execute(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(ref, inputs, opts \\ []) do
    # Auto-generated with streaming support
  end
end
```

---

## The Innovation: Three-Layer Architecture

### Layer 1: Configuration Schema (Declarative)

PyBridge configurations are Elixir schemas that describe:

```elixir
defmodule PyBridge.Config do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :python_module, :string
    field :version, :string

    embeds_one :introspection, Introspection do
      field :enabled, :boolean, default: true
      field :cache_path, :string
      field :discovery_depth, :integer, default: 2
      field :submodules, {:array, :string}, default: []
    end

    embeds_many :classes, Class do
      field :python_path, :string
      field :elixir_module, :atom
      field :extends, :atom
      field :singleton, :boolean, default: false

      embeds_one :constructor, Constructor do
        field :args, :map
        field :session_aware, :boolean, default: true
      end

      embeds_many :methods, Method do
        field :name, :string
        field :elixir_name, :atom
        field :streaming, :boolean, default: false
        field :async, :boolean, default: false
        field :args, :map
        field :returns, :string
      end

      field :result_transform, :any, virtual: true
      field :error_handler, :any, virtual: true
    end

    embeds_many :functions, Function do
      field :python_path, :string
      field :elixir_name, :atom
      field :args, :map
      field :pure, :boolean, default: true
    end

    embeds_one :bidirectional_tools, BidirectionalTools do
      field :enabled, :boolean, default: false
      embeds_many :export_to_python, ToolExport do
        field :module, :atom
        field :function, :atom
        field :arity, :integer
        field :python_name, :string
      end
    end

    embeds_one :grpc, GRPCConfig do
      field :service_name, :string
      field :streaming_methods, {:array, :string}, default: []
    end
  end
end
```

### Layer 2: Introspection Engine (Automated Discovery)

PyBridge can **automatically discover** Python APIs using reflection:

```elixir
defmodule PyBridge.Introspection do
  @moduledoc """
  Introspects Python modules to generate configuration automatically.
  """

  @doc """
  Discover the schema of a Python module and generate a config.

  ## Example

      iex> {:ok, config} = PyBridge.Introspection.discover("dspy")
      iex> File.write!("config/pybridge/dspy.exs", config)
  """
  def discover(module_path, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, PyBridge.Utils.ID.generate())
    depth = Keyword.get(opts, :depth, 2)

    # Use Snakepit to introspect the Python module
    case Snakepit.execute_program(session_id, "python", """
      import inspect
      import #{module_path}

      def introspect_module(mod, depth=0, max_depth=#{depth}):
          schema = {
              "classes": {},
              "functions": {},
              "submodules": {}
          }

          for name, obj in inspect.getmembers(mod):
              if name.startswith("_"):
                  continue

              if inspect.isclass(obj):
                  schema["classes"][name] = introspect_class(obj)
              elif inspect.isfunction(obj) or inspect.ismethod(obj):
                  schema["functions"][name] = introspect_function(obj)
              elif inspect.ismodule(obj) and depth < max_depth:
                  schema["submodules"][name] = introspect_module(obj, depth + 1, max_depth)

          return schema

      def introspect_class(cls):
          return {
              "docstring": inspect.getdoc(cls) or "",
              "module": cls.__module__,
              "bases": [b.__name__ for b in cls.__bases__],
              "methods": {
                  name: introspect_function(method)
                  for name, method in inspect.getmembers(cls, predicate=inspect.isfunction)
                  if not name.startswith("_") or name in ["__init__", "__call__"]
              },
              "signature": str(inspect.signature(cls.__init__)) if hasattr(cls, "__init__") else None
          }

      def introspect_function(func):
          sig = inspect.signature(func)
          return {
              "docstring": inspect.getdoc(func) or "",
              "signature": str(sig),
              "parameters": [
                  {
                      "name": param.name,
                      "kind": str(param.kind),
                      "default": str(param.default) if param.default != inspect.Parameter.empty else None,
                      "annotation": str(param.annotation) if param.annotation != inspect.Parameter.empty else None
                  }
                  for param in sig.parameters.values()
              ],
              "return_annotation": str(sig.return_annotation) if sig.return_annotation != inspect.Signature.empty else None
          }

      result = introspect_module(#{module_path})
      result
      """) do
      {:ok, %{"result" => schema}} ->
        config = generate_config_from_schema(module_path, schema, opts)
        {:ok, config}

      {:error, reason} ->
        {:error, "Introspection failed: #{inspect(reason)}"}
    end
  end

  defp generate_config_from_schema(module_path, schema, _opts) do
    # Convert Python schema to PyBridge config format
    classes =
      for {class_name, class_info} <- schema["classes"] do
        %{
          python_path: "#{module_path}.#{class_name}",
          elixir_module: Module.concat([String.capitalize(module_path), class_name]),
          constructor: %{
            args: infer_args_from_signature(class_info["signature"]),
            session_aware: true
          },
          methods:
            for {method_name, method_info} <- class_info["methods"] do
              %{
                name: method_name,
                elixir_name: elixir_method_name(method_name),
                streaming: false,
                args: infer_args_from_signature(method_info["signature"])
              }
            end
        }
      end

    %PyBridge.Config{
      python_module: module_path,
      version: "auto-discovered",
      introspection: %{
        enabled: true,
        cache_path: "priv/pybridge/schemas/#{module_path}.json"
      },
      classes: classes,
      functions: []
    }
  end

  defp elixir_method_name("__call__"), do: :call
  defp elixir_method_name("__init__"), do: :new
  defp elixir_method_name(name), do: String.to_atom(name)

  defp infer_args_from_signature(signature) do
    # Parse Python signature string and convert to Elixir types
    # This would use a proper parser in production
    %{}
  end
end
```

### Layer 3: Code Generation Engine (Compile-Time Metaprogramming)

The heart of PyBridge: **macro-based code generation** at compile time:

```elixir
defmodule PyBridge.Generator do
  @moduledoc """
  Compile-time code generation for Python library wrappers.

  This module uses Elixir macros to generate complete wrapper modules
  from PyBridge configurations.
  """

  defmacro __using__(opts) do
    config_module = Keyword.get(opts, :config)

    quote do
      import PyBridge.Generator
      Module.register_attribute(__MODULE__, :pybridge_config, persist: true)

      @before_compile PyBridge.Generator

      if unquote(config_module) do
        @pybridge_config unquote(config_module).config()
      end
    end
  end

  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :pybridge_config)

    if config do
      generate_wrapper_module(config, env)
    else
      quote do
        def __pybridge_config__, do: nil
      end
    end
  end

  def generate_wrapper_module(config, _env) do
    class_modules =
      for class_config <- config.classes do
        generate_class_module(class_config, config)
      end

    function_modules =
      for func_config <- config.functions do
        generate_function_wrapper(func_config, config)
      end

    quote do
      unquote_splicing(class_modules)
      unquote_splicing(function_modules)

      def __pybridge_config__, do: unquote(Macro.escape(config))
    end
  end

  defp generate_class_module(class_config, parent_config) do
    module_name = class_config.elixir_module
    python_path = class_config.python_path

    # Generate constructor
    constructor_fn = generate_constructor(class_config, parent_config)

    # Generate methods
    method_fns =
      for method <- class_config.methods do
        generate_method(method, class_config, parent_config)
      end

    # Generate documentation
    moduledoc = generate_moduledoc(class_config, parent_config)

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(moduledoc)

        alias PyBridge.InstanceRef

        @type t :: InstanceRef.t()
        @python_path unquote(python_path)
        @parent_config unquote(Macro.escape(parent_config))
        @class_config unquote(Macro.escape(class_config))

        unquote(constructor_fn)
        unquote_splicing(method_fns)

        # Introspection
        def __python_path__, do: @python_path
        def __class_config__, do: @class_config
      end
    end
  end

  defp generate_constructor(class_config, parent_config) do
    python_path = class_config.python_path
    session_aware = class_config.constructor.session_aware

    quote do
      @doc """
      Create a new instance of #{unquote(python_path)}.

      ## Options

        * `:session_id` - Reuse an existing Snakepit session (optional)
        * `:timeout` - Override default timeout (default: 30000ms)

      ## Returns

      `{:ok, instance_ref}` or `{:error, reason}`
      """
      @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
      def create(args \\ %{}, opts \\ []) do
        session_id =
          if unquote(session_aware) do
            Keyword.get(opts, :session_id) || PyBridge.Session.generate_id()
          else
            nil
          end

        PyBridge.Runtime.create_instance(
          unquote(python_path),
          args,
          session_id,
          opts
        )
      end
    end
  end

  defp generate_method(method_config, class_config, _parent_config) do
    method_name = method_config.name
    elixir_name = method_config.elixir_name
    streaming = method_config.streaming

    quote do
      @doc """
      Call #{unquote(method_name)} on the Python instance.

      Streaming: #{unquote(streaming)}
      """
      @spec unquote(elixir_name)(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
      def unquote(elixir_name)(instance_ref, args \\ %{}, opts \\ []) do
        if unquote(streaming) do
          PyBridge.Runtime.call_method_streaming(
            instance_ref,
            unquote(method_name),
            args,
            opts
          )
        else
          PyBridge.Runtime.call_method(
            instance_ref,
            unquote(method_name),
            args,
            opts
          )
        end
      end
    end
  end

  defp generate_moduledoc(class_config, parent_config) do
    """
    Elixir wrapper for #{class_config.python_path}.

    This module was automatically generated by PyBridge from configuration.

    **Python Module**: `#{parent_config.python_module}`
    **Version**: #{parent_config.version}

    ## Generated Methods

    #{Enum.map_join(class_config.methods, "\n", fn m -> "  * `#{m.elixir_name}/2` → `#{m.name}`" end)}
    """
  end

  defp generate_function_wrapper(func_config, parent_config) do
    # Similar pattern for standalone functions
    quote do
      # Generated function wrapper
    end
  end
end
```

---

## Key Innovations

### 1. **Zero-Code Integration**

Once configured, adding a new Python library requires **zero Elixir code**:

```bash
# Discover and generate config
mix pybridge.discover langchain --output config/pybridge/langchain.exs

# Add to your application
# config/config.exs
config :pybridge, :libraries, [
  DSPy: DSPyConfig,
  LangChain: LangChainConfig,
  Transformers: TransformersConfig
]

# Automatically available:
{:ok, chain} = LangChain.LLMChain.create(%{llm: llm, prompt: prompt})
{:ok, result} = LangChain.LLMChain.run(chain, %{input: "Hello"})
```

### 2. **Type Safety Through Introspection**

PyBridge uses Python's type hints to generate Elixir typespecs:

```python
# Python
def predict(signature: str, inputs: dict[str, Any]) -> dict[str, Any]:
    ...
```

↓ Generates ↓

```elixir
@spec predict(String.t(), map()) :: {:ok, map()} | {:error, term()}
def predict(signature, inputs, opts \\ [])
```

### 3. **Bidirectional Tool Registry**

Export Elixir functions to Python automatically:

```elixir
# config/pybridge/dspy.exs
bidirectional_tools: %{
  enabled: true,
  export_to_python: [
    {DSPex.Validators, :validate_reasoning, 1, "elixir_validate_reasoning"},
    {DSPex.Metrics, :track_prediction, 2, "elixir_track_prediction"}
  ]
}
```

Python code can then call:

```python
# Inside DSPy predictor
reasoning = self.think(question)
validation = elixir_validate_reasoning(reasoning)  # Calls Elixir!
if not validation["valid"]:
    reasoning = self.retry_with_feedback(validation["feedback"])
```

### 4. **Streaming and Async Support**

Declaratively enable streaming for any method:

```elixir
methods: [
  %{
    name: "stream_completion",
    elixir_name: :stream,
    streaming: true,
    async: true
  }
]
```

Auto-generates:

```elixir
def stream(instance_ref, args, opts \\ []) do
  PyBridge.Runtime.call_method_streaming(instance_ref, "stream_completion", args, opts)
end

# Usage:
{:ok, stream} = Model.stream(model, %{prompt: "..."})
for {:chunk, data} <- stream do
  IO.write(data)
end
```

### 5. **Smart Caching and Session Management**

PyBridge leverages Snakepit's session pooling:

```elixir
# Reuse sessions for performance
session_id = PyBridge.Session.checkout(:dspy_pool)

{:ok, pred1} = DSPex.Predict.create(sig1, session_id: session_id)
{:ok, pred2} = DSPex.ChainOfThought.create(sig2, session_id: session_id)

# Both share the same Python process, avoiding cold starts
```

### 6. **Compile-Time Optimization**

Configurations are processed at compile time, generating optimized code:

```elixir
# At compile time, PyBridge:
# 1. Validates configuration schema
# 2. Caches introspection results
# 3. Generates optimized modules with inlined constants
# 4. Creates ExDoc documentation
# 5. Builds gRPC service definitions (if enabled)
```

---

## DSPy Integration Example

### Configuration File

```elixir
# config/pybridge/dspy.exs
defmodule DSPyConfig do
  use PyBridge.Config

  def config do
    %PyBridge.Config{
      python_module: "dspy",
      version: "2.5.0",

      introspection: %{
        enabled: true,
        cache_path: "priv/pybridge/schemas/dspy.json",
        submodules: ["teleprompt", "evaluate", "retrieve", "primitives"]
      },

      classes: [
        # Core Predictors
        %{
          python_path: "dspy.Predict",
          elixir_module: DSPex.Predict,
          constructor: %{args: %{signature: :string}},
          methods: [
            %{name: "__call__", elixir_name: :call},
            %{name: "forward", elixir_name: :forward}
          ]
        },

        %{
          python_path: "dspy.ChainOfThought",
          elixir_module: DSPex.ChainOfThought,
          extends: DSPex.Predict,
          constructor: %{args: %{signature: :string, rationale_type: {:optional, :atom}}},
          methods: [
            %{name: "__call__", elixir_name: :think}
          ]
        },

        %{
          python_path: "dspy.ChainOfThoughtWithHint",
          elixir_module: DSPex.ChainOfThoughtWithHint,
          extends: DSPex.ChainOfThought
        },

        %{
          python_path: "dspy.ProgramOfThought",
          elixir_module: DSPex.ProgramOfThought,
          constructor: %{args: %{signature: :string}},
          methods: [
            %{name: "__call__", elixir_name: :reason},
            %{name: "execute_code", elixir_name: :execute_code}
          ]
        },

        %{
          python_path: "dspy.ReAct",
          elixir_module: DSPex.ReAct,
          constructor: %{args: %{signature: :string, tools: :list}},
          methods: [
            %{name: "__call__", elixir_name: :act}
          ]
        },

        # Retrieval
        %{
          python_path: "dspy.Retrieve",
          elixir_module: DSPex.Retrieve,
          constructor: %{args: %{k: {:optional, :integer}}},
          methods: [
            %{name: "__call__", elixir_name: :retrieve},
            %{name: "forward", elixir_name: :forward}
          ]
        },

        # Optimizers
        %{
          python_path: "dspy.teleprompt.BootstrapFewShot",
          elixir_module: DSPex.Optimizers.BootstrapFewShot,
          constructor: %{
            args: %{
              metric: {:optional, :function},
              max_bootstrapped_demos: {:optional, :integer},
              max_labeled_demos: {:optional, :integer}
            }
          },
          methods: [
            %{name: "compile", elixir_name: :compile}
          ]
        },

        %{
          python_path: "dspy.teleprompt.MIPRO",
          elixir_module: DSPex.Optimizers.MIPRO,
          constructor: %{
            args: %{
              metric: :function,
              num_candidates: {:optional, :integer},
              init_temperature: {:optional, :float}
            }
          },
          methods: [
            %{name: "compile", elixir_name: :compile}
          ]
        },

        # Language Models
        %{
          python_path: "dspy.OpenAI",
          elixir_module: DSPex.LM.OpenAI,
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string},
              max_tokens: {:optional, :integer}
            }
          },
          methods: [
            %{name: "generate", elixir_name: :generate},
            %{name: "__call__", elixir_name: :call, streaming: true}
          ]
        },

        %{
          python_path: "dspy.Anthropic",
          elixir_module: DSPex.LM.Anthropic,
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string}
            }
          }
        }
      ],

      functions: [
        %{
          python_path: "dspy.settings.configure",
          elixir_name: :configure,
          args: %{lm: :any, rm: {:optional, :any}, adapter: {:optional, :string}}
        },

        %{
          python_path: "dspy.Signature",
          elixir_name: :signature,
          args: %{spec: :string}
        },

        %{
          python_path: "dspy.Example",
          elixir_name: :example,
          args: %{data: :map}
        }
      ],

      bidirectional_tools: %{
        enabled: true,
        export_to_python: [
          {DSPex.Validators, :validate_reasoning, 1, "elixir_validate_reasoning"},
          {DSPex.Validators, :validate_output, 2, "elixir_validate_output"},
          {DSPex.Metrics, :track_prediction, 2, "elixir_track_prediction"},
          {DSPex.Transforms, :post_process, 1, "elixir_post_process"}
        ]
      },

      grpc: %{
        service_name: "dspy",
        streaming_methods: ["stream_completion", "generate_stream"]
      }
    }
  end
end
```

### Generated Usage

With the above configuration, DSPex becomes incredibly simple:

```elixir
# Configure DSPy
DSPex.configure(
  lm: DSPex.LM.OpenAI.create(%{model: "gpt-4", api_key: api_key})
)

# All these modules are auto-generated:

# 1. Basic prediction
{:ok, pred} = DSPex.Predict.create("question -> answer")
{:ok, result} = DSPex.Predict.call(pred, %{question: "What is DSPy?"})

# 2. Chain of thought
{:ok, cot} = DSPex.ChainOfThought.create("question -> reasoning, answer")
{:ok, result} = DSPex.ChainOfThought.think(cot, %{question: "Explain quantum computing"})

# 3. Program of thought
{:ok, pot} = DSPex.ProgramOfThought.create("problem -> code, solution")
{:ok, result} = DSPex.ProgramOfThought.reason(pot, %{problem: "Calculate 15th Fibonacci number"})

# 4. Optimization
{:ok, optimizer} = DSPex.Optimizers.BootstrapFewShot.create(%{
  metric: &DSPex.Metrics.accuracy/2,
  max_bootstrapped_demos: 4
})
{:ok, optimized_program} = DSPex.Optimizers.BootstrapFewShot.compile(optimizer, my_program, trainset)

# 5. Retrieval
{:ok, retriever} = DSPex.Retrieve.create(%{k: 5})
{:ok, docs} = DSPex.Retrieve.retrieve(retriever, %{query: "machine learning"})
```

**All without writing a single wrapper function manually.**

---

## Architecture Diagrams

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Elixir Application                       │
│                                                               │
│  ┌──────────────┐      ┌──────────────┐    ┌──────────────┐│
│  │   DSPex      │      │  LangChain   │    │ Transformers ││
│  │  (generated) │      │  (generated) │    │  (generated) ││
│  └──────┬───────┘      └──────┬───────┘    └──────┬───────┘│
│         │                     │                   │         │
│         └─────────────────────┼───────────────────┘         │
│                               │                             │
│                    ┌──────────▼──────────┐                  │
│                    │   PyBridge Runtime  │                  │
│                    │  - Session Manager  │                  │
│                    │  - Type Converter   │                  │
│                    │  - Error Handler    │                  │
│                    └──────────┬──────────┘                  │
└───────────────────────────────┼──────────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │      Snakepit         │
                    │  - Process Pooling    │
                    │  - gRPC Bridge        │
                    │  - Session Store      │
                    └───────────┬───────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
┌───────▼────────┐   ┌──────────▼─────────┐   ┌────────▼────────┐
│ Python Worker  │   │  Python Worker     │   │ Python Worker   │
│                │   │                    │   │                 │
│  import dspy   │   │ import langchain   │   │ import torch    │
│  import torch  │   │ import chromadb    │   │ import sklearn  │
└────────────────┘   └────────────────────┘   └─────────────────┘
```

### Code Generation Pipeline

```
┌──────────────────────┐
│  PyBridge Config     │
│  (dspy.exs)          │
└──────────┬───────────┘
           │
           │ At Compile Time
           │
           ▼
┌──────────────────────┐       ┌─────────────────────┐
│ Introspection Engine │──────▶│  Python Runtime     │
│ - Parse Config       │       │  - inspect module   │
│ - Discover Schema    │◀──────│  - Extract types    │
└──────────┬───────────┘       └─────────────────────┘
           │
           │ Schema + Config
           │
           ▼
┌──────────────────────┐
│   Code Generator     │
│ - Generate Modules   │
│ - Generate Types     │
│ - Generate Docs      │
│ - Generate Tests     │
└──────────┬───────────┘
           │
           │ Generated AST
           │
           ▼
┌──────────────────────┐
│   Compiled Modules   │
│ - DSPex.Predict      │
│ - DSPex.ChainOfThought│
│ - DSPex.Retrieve     │
│ - ...                │
└──────────────────────┘
```

---

## Comparison: Before vs. After

### Before PyBridge (Manual Wrappers)

**To integrate DSPy Predict:**

```elixir
# lib/dspex/modules/predict.ex (115 lines)
defmodule DSPex.Modules.Predict do
  def create(signature, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    case Snakepit.execute_in_session(session_id, "call_dspy", %{
      "module_path" => "dspy.Predict",
      "function_name" => "__init__",
      "kwargs" => %{"signature" => signature}
    }) do
      {:ok, %{"instance_id" => instance_id}} ->
        {:ok, {session_id, instance_id}}
      {:error, error} ->
        {:error, parse_error(error)}
    end
  end

  def execute({session_id, instance_id}, inputs, opts \\ []) do
    case Snakepit.execute_in_session(session_id, "call_dspy", %{
      "module_path" => "stored.#{instance_id}",
      "function_name" => "__call__",
      "kwargs" => inputs
    }) do
      {:ok, %{"result" => result}} ->
        {:ok, transform_result(result)}
      {:error, error} ->
        {:error, parse_error(error)}
    end
  end

  defp transform_result(raw), do: # ... custom logic
  defp parse_error(error), do: # ... error parsing
end
```

**Time to integrate 1 class**: ~30 minutes (writing + testing)
**Time to integrate 20 classes**: ~10 hours
**Maintenance burden**: High (every Python API change requires manual updates)

### After PyBridge (Configuration)

**To integrate DSPy Predict:**

```elixir
# config/pybridge/dspy.exs
classes: [
  %{
    python_path: "dspy.Predict",
    elixir_module: DSPex.Predict,
    constructor: %{args: %{signature: :string}},
    methods: [
      %{name: "__call__", elixir_name: :call}
    ]
  }
]
```

**Time to integrate 1 class**: ~2 minutes (config only)
**Time to integrate 20 classes**: ~20 minutes (or auto-discover in 30 seconds)
**Maintenance burden**: Minimal (re-run introspection on Python updates)

---

## Implementation Roadmap

### Phase 1: Core Framework (MVP)

**Goal**: Configuration-driven code generation for basic class/method wrapping

**Components**:
1. `PyBridge.Config` schema definition
2. `PyBridge.Generator` macro system
3. `PyBridge.Runtime` for instance management
4. Basic introspection via Snakepit
5. DSPy integration as proof-of-concept

**Deliverables**:
- [ ] `lib/pybridge/config.ex` - Config schema with Ecto
- [ ] `lib/pybridge/generator.ex` - Macro-based code generation
- [ ] `lib/pybridge/runtime.ex` - Instance lifecycle management
- [ ] `lib/pybridge/introspection.ex` - Python module discovery
- [ ] `lib/pybridge/session.ex` - Session pooling wrapper
- [ ] `config/pybridge/dspy.exs` - DSPy configuration
- [ ] Full DSPex rewrite using PyBridge
- [ ] Documentation and examples

**Timeline**: 2-3 weeks

### Phase 2: Advanced Features

**Goal**: Streaming, async, bidirectional tools, type safety

**Components**:
1. Streaming support via gRPC
2. Bidirectional tool registry
3. Type inference from Python annotations
4. ExDoc integration for generated modules
5. Mix tasks (`mix pybridge.discover`, `mix pybridge.generate`)

**Deliverables**:
- [ ] Streaming API with GenStage/Flow integration
- [ ] `PyBridge.Tools` for Elixir → Python function export
- [ ] Type mapper (Python types → Elixir typespecs)
- [ ] Auto-generated `@doc` from Python docstrings
- [ ] `mix pybridge.discover <module>` task
- [ ] LangChain integration as second example

**Timeline**: 2-3 weeks

### Phase 3: Production Hardening

**Goal**: Performance, reliability, ecosystem integration

**Components**:
1. Caching of introspection results
2. Hot code reloading for Python changes
3. Telemetry and observability
4. Error handling and retry logic
5. Integration with Nx/EXLA for tensor passing

**Deliverables**:
- [ ] Schema caching system (ETS + DETS)
- [ ] File watcher for Python code changes
- [ ] Telemetry events for all PyBridge operations
- [ ] Configurable retry/circuit breaker
- [ ] Nx tensor serialization support
- [ ] Transformers (Hugging Face) integration
- [ ] PyTorch integration

**Timeline**: 3-4 weeks

### Phase 4: Ecosystem & Community

**Goal**: Make PyBridge the standard for Python-Elixir integration

**Components**:
1. Public release as `pybridge` Hex package
2. Pre-built configs for top 20 ML libraries
3. Documentation site with examples
4. Blog posts and tutorials
5. Conference talks (ElixirConf, BEAM)

**Deliverables**:
- [ ] Hex package published
- [ ] Configs: DSPy, LangChain, Transformers, PyTorch, TensorFlow, JAX, scikit-learn, spaCy, FastAPI, Pydantic, etc.
- [ ] Documentation site (hexdocs + custom)
- [ ] Example apps (chatbot, ML pipeline, etc.)
- [ ] Blog post: "Zero-Code Python Integration in Elixir"
- [ ] Talk proposal for ElixirConf 2026

**Timeline**: Ongoing

---

## Top 20 Python Libraries for Integration

Based on research, here are the priority targets:

### Tier 1: Core ML/AI (Immediate)
1. **DSPy** - Prompt engineering framework ✅ (MVP)
2. **LangChain** - LLM application framework
3. **Transformers** (Hugging Face) - Pre-trained models
4. **PyTorch** - Deep learning framework
5. **TensorFlow** - Deep learning framework

### Tier 2: Specialized ML (Next)
6. **scikit-learn** - Classical ML algorithms
7. **JAX** - High-performance numerical computing
8. **Instructor** - Structured LLM outputs
9. **Guidance** - Controlled text generation
10. **LlamaIndex** - Data framework for LLMs

### Tier 3: Data & Utilities (Later)
11. **Pydantic** - Data validation
12. **FastAPI** - Web framework (for ML services)
13. **spaCy** - Industrial NLP
14. **Polars** - Fast dataframes
15. **NumPy** - Numerical arrays

### Tier 4: Domain-Specific (Community)
16. **OpenCV** - Computer vision
17. **Pandas** - Data manipulation
18. **Matplotlib** - Plotting
19. **Requests** - HTTP client
20. **Beautiful Soup** - HTML parsing

---

## Technical Deep Dive: How It Works

### 1. Configuration Loading

At compile time, PyBridge loads configurations:

```elixir
# In your mix.exs
def application do
  [
    extra_applications: [:pybridge],
    mod: {MyApp.Application, []}
  ]
end

# config/config.exs
config :pybridge, :libraries, [
  {DSPex, DSPyConfig},
  {LangChainEx, LangChainConfig}
]
```

PyBridge's application callback:

```elixir
defmodule PyBridge.Application do
  use Application

  def start(_type, _args) do
    # Load all configured libraries
    libraries = Application.get_env(:pybridge, :libraries, [])

    # Start Snakepit with Python worker pool
    children = [
      {Snakepit, [
        pool_size: 4,
        python_path: System.get_env("PYTHON_PATH", "python3"),
        python_modules: extract_python_modules(libraries)
      ]},

      {PyBridge.Session.Manager, []},
      {PyBridge.Cache, []}
    ]

    # Generate modules at runtime (dev mode) or use compiled (prod)
    if Mix.env() == :dev do
      for {_elixir_module, config_module} <- libraries do
        config = config_module.config()
        PyBridge.Generator.generate_and_load(config)
      end
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### 2. Introspection Workflow

When you run `mix pybridge.discover dspy`:

```elixir
defmodule Mix.Tasks.Pybridge.Discover do
  use Mix.Task

  @shortdoc "Discover and generate PyBridge config for a Python module"

  def run([module_path | args]) do
    opts = parse_args(args)

    # Start Snakepit temporarily
    {:ok, _} = Snakepit.start_link([pool_size: 1])

    # Discover schema
    {:ok, config} = PyBridge.Introspection.discover(module_path, opts)

    # Generate config file
    output_path = Keyword.get(opts, :output, "config/pybridge/#{module_path}.exs")
    config_code = PyBridge.ConfigFormatter.to_elixir_code(config)

    File.write!(output_path, config_code)

    Mix.shell().info("Generated config: #{output_path}")
    Mix.shell().info("Review and customize before using.")
  end
end
```

The introspection result is cached:

```elixir
# priv/pybridge/schemas/dspy.json
{
  "module": "dspy",
  "version": "2.5.0",
  "discovered_at": "2025-10-25T10:30:00Z",
  "classes": {
    "Predict": {
      "docstring": "Basic prediction module...",
      "constructor": {
        "signature": "(signature: str, **kwargs)",
        "parameters": [...]
      },
      "methods": {
        "__call__": {
          "signature": "(self, **kwargs) -> Prediction",
          "docstring": "Execute prediction..."
        }
      }
    }
  }
}
```

### 3. Code Generation Internals

The `__before_compile__` hook does the heavy lifting:

```elixir
defmacro __before_compile__(env) do
  config = Module.get_attribute(env.module, :pybridge_config)

  # Generate all wrapper modules
  quote do
    # For each class in config
    unquote(
      for class <- config.classes do
        generate_class_wrapper(class, config)
      end
    )

    # Module registry for reflection
    def __pybridge_modules__ do
      unquote(Enum.map(config.classes, & &1.elixir_module))
    end
  end
end

defp generate_class_wrapper(class, parent_config) do
  quote do
    defmodule unquote(class.elixir_module) do
      @moduledoc """
      Auto-generated wrapper for `#{unquote(class.python_path)}`.

      #{fetch_python_docstring(unquote(class.python_path))}
      """

      # Generate create/2
      unquote(generate_constructor(class))

      # Generate each method
      unquote_splicing(
        for method <- class.methods do
          generate_method_wrapper(method, class)
        end
      )
    end
  end
end
```

### 4. Runtime Execution Flow

When you call `DSPex.Predict.create("question -> answer")`:

```
1. Elixir: DSPex.Predict.create/2 (generated)
           ↓
2. Elixir: PyBridge.Runtime.create_instance/4
           ↓
3. Elixir: PyBridge.Session.checkout(:dspy_pool)
           ↓
4. Elixir: Snakepit.execute_in_session(session_id, "call_dspy", %{...})
           ↓
5. gRPC:  BridgeServer.execute_tool(request)
           ↓
6. Python: tools["call_dspy"](%{
             "module_path" => "dspy.Predict",
             "function_name" => "__init__",
             "kwargs" => %{"signature" => "question -> answer"}
           })
           ↓
7. Python: import dspy
           instance = dspy.Predict(signature="question -> answer")
           store["instance_123"] = instance
           return {"instance_id": "instance_123"}
           ↓
8. gRPC:  Response{result: %{"instance_id" => "instance_123"}}
           ↓
9. Elixir: {:ok, {session_id, "instance_123"}}
```

### 5. Type Conversion

PyBridge automatically converts between Elixir and Python types:

```elixir
defmodule PyBridge.TypeConverter do
  @doc """
  Convert Elixir data to Python-compatible JSON.
  """
  def to_python(data) do
    case data do
      # Atoms → strings
      atom when is_atom(atom) and atom not in [nil, true, false] ->
        Atom.to_string(atom)

      # Keyword lists → dicts
      [{key, _val} | _] = keyword when is_atom(key) ->
        Map.new(keyword, fn {k, v} -> {Atom.to_string(k), to_python(v)} end)

      # Maps (already compatible)
      %{} = map ->
        Map.new(map, fn {k, v} -> {to_python(k), to_python(v)} end)

      # Lists
      list when is_list(list) ->
        Enum.map(list, &to_python/1)

      # Primitives
      other ->
        other
    end
  end

  @doc """
  Convert Python JSON to idiomatic Elixir.
  """
  def from_python(data, opts \\ []) do
    atomize = Keyword.get(opts, :atomize_keys, true)

    case data do
      %{} = map when atomize ->
        Map.new(map, fn {k, v} ->
          {safe_to_atom(k), from_python(v, opts)}
        end)

      list when is_list(list) ->
        Enum.map(list, &from_python(&1, opts))

      other ->
        other
    end
  end

  defp safe_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> str
    end
  end
  defp safe_to_atom(other), do: other
end
```

---

## Performance Considerations

### Benchmarks (Projected)

Based on Snakepit's current performance:

| Operation | Manual Wrapper | PyBridge | Overhead |
|-----------|---------------|----------|----------|
| Instance creation | 5ms | 5.2ms | +4% |
| Method call (simple) | 2ms | 2.1ms | +5% |
| Method call (streaming) | 50ms (total) | 51ms | +2% |
| Session reuse | 1ms | 1ms | 0% |

**Conclusion**: PyBridge overhead is negligible (~2-5%) thanks to compile-time generation.

### Optimization Strategies

1. **Compile-time generation** eliminates runtime overhead
2. **Session pooling** avoids Python process restarts
3. **Result caching** for pure functions
4. **Batch operations** for multiple calls
5. **Direct gRPC** bypasses JSON for binary data (future)

---

## Security & Safety

### Sandboxing

PyBridge inherits Snakepit's security model:

- Each Python worker runs in isolated process
- Configurable timeouts prevent runaway code
- Resource limits (CPU, memory) per worker
- No filesystem access by default (can be enabled)

### Configuration Validation

All configs are validated at compile time:

```elixir
defmodule PyBridge.ConfigValidator do
  def validate!(config) do
    # Ensure no naming conflicts
    check_unique_elixir_modules!(config.classes)

    # Validate Python paths
    check_python_paths!(config.classes)

    # Ensure required fields
    check_required_fields!(config)

    # Validate method signatures
    check_method_signatures!(config.classes)

    :ok
  end
end
```

### Type Safety

PyBridge generates typespecs from Python annotations:

```python
# Python
def predict(signature: str, inputs: dict[str, Any]) -> dict[str, Any]:
    ...
```

↓

```elixir
@spec predict(String.t(), map()) :: {:ok, map()} | {:error, term()}
def predict(signature, inputs, opts \\ [])
```

Dialyzer catches type errors at compile time.

---

## Comparison to Alternatives

### vs. ErlPort

| Feature | PyBridge | ErlPort |
|---------|----------|---------|
| Communication | gRPC (streaming) | Erlang ports |
| Code generation | Yes (metaprogramming) | No (manual) |
| Type safety | Yes (specs + Dialyzer) | Limited |
| Bidirectional calls | Yes | Limited |
| Session management | Yes (pooling) | Manual |
| Streaming support | Yes | No |
| Documentation | Auto-generated | Manual |

### vs. Porcelain

| Feature | PyBridge | Porcelain |
|---------|----------|-----------|
| Target | Python libraries | CLI programs |
| Type safety | Yes | No |
| Stateful sessions | Yes | No |
| Code generation | Yes | No |

### vs. Manual Wrappers

| Feature | PyBridge | Manual |
|---------|----------|--------|
| Development time | Minutes | Hours/Days |
| Maintenance | Automatic | Manual |
| Consistency | Guaranteed | Varies |
| Testing | Auto-generated | Manual |
| Documentation | Auto-generated | Manual |

---

## Future Enhancements

### 1. Direct Tensor Passing

Integrate with Nx to pass tensors without serialization:

```elixir
# Zero-copy tensor passing
tensor = Nx.tensor([[1, 2], [3, 4]])
{:ok, result} = PyTorch.Model.forward(model, tensor)
# result is Nx.Tensor, no JSON roundtrip
```

### 2. WebAssembly Backend

Compile Python to WASM for in-process execution:

```elixir
config :pybridge, :backend, :wasm
# No separate Python process needed!
```

### 3. Distributed Python Workers

Run Python workers on separate nodes:

```elixir
config :pybridge, :workers, [
  gpu_node_1: [host: "gpu-1.cluster", gpus: [0, 1]],
  gpu_node_2: [host: "gpu-2.cluster", gpus: [0, 1]]
]
```

### 4. Automatic Test Generation

Generate tests from Python docstrings:

```elixir
# Auto-generated from Python doctest
test "DSPex.Predict with simple signature" do
  {:ok, pred} = DSPex.Predict.create("input -> output")
  assert {:ok, %{output: _}} = DSPex.Predict.call(pred, %{input: "test"})
end
```

---

## Conclusion

**PyBridge** represents a fundamental shift in how Elixir integrates with Python:

### The Innovation

- **Configuration over Code**: Describe the API, don't implement it
- **Metaprogramming at Scale**: Generate thousands of lines from dozens of config lines
- **Introspection-First**: Leverage Python's reflection to auto-discover APIs
- **Compile-Time Safety**: Catch errors before runtime with typespecs and validation
- **Bidirectional**: Python calls Elixir, Elixir calls Python, seamlessly

### The Impact

- **10x faster integration**: Minutes instead of hours/days
- **100% consistency**: All wrappers follow the same patterns
- **Zero maintenance drift**: Re-run introspection when Python updates
- **Ecosystem acceleration**: Make entire Python ML ecosystem available to Elixir
- **Developer experience**: Focus on solving problems, not writing boilerplate

### The Path Forward

1. **Build the MVP** with DSPy (2-3 weeks)
2. **Prove the concept** with LangChain integration (2-3 weeks)
3. **Harden for production** (3-4 weeks)
4. **Release to community** and gather feedback
5. **Expand to top 20 libraries** through community contributions

**PyBridge is not just a tool—it's a bridge between two powerful ecosystems, enabling Elixir developers to leverage the entire Python ML/AI world without sacrificing the reliability, concurrency, and elegance of the BEAM.**

---

## Appendix: Configuration Schema Reference

### Full Schema Definition

```elixir
defmodule PyBridge.Config do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :python_module, :string
    field :version, :string
    field :description, :string

    embeds_one :introspection, Introspection do
      field :enabled, :boolean, default: true
      field :cache_path, :string
      field :discovery_depth, :integer, default: 2
      field :submodules, {:array, :string}, default: []
      field :exclude_patterns, {:array, :string}, default: ["test_*", "*_test", "internal.*"]
    end

    embeds_many :classes, Class do
      field :python_path, :string
      field :elixir_module, :atom
      field :extends, :atom
      field :singleton, :boolean, default: false
      field :description, :string

      embeds_one :constructor, Constructor do
        field :args, :map
        field :session_aware, :boolean, default: true
        field :timeout, :integer, default: 30_000
      end

      embeds_many :methods, Method do
        field :name, :string
        field :elixir_name, :atom
        field :description, :string
        field :streaming, :boolean, default: false
        field :async, :boolean, default: false
        field :args, :map
        field :returns, :string
        field :timeout, :integer
      end

      embeds_many :properties, Property do
        field :name, :string
        field :elixir_name, :atom
        field :type, :string
        field :readonly, :boolean, default: false
      end

      field :result_transform, :any, virtual: true
      field :error_handler, :any, virtual: true
    end

    embeds_many :functions, Function do
      field :python_path, :string
      field :elixir_name, :atom
      field :description, :string
      field :args, :map
      field :returns, :string
      field :pure, :boolean, default: true
      field :cacheable, :boolean, default: false
      field :timeout, :integer
    end

    embeds_one :bidirectional_tools, BidirectionalTools do
      field :enabled, :boolean, default: false

      embeds_many :export_to_python, ToolExport do
        field :module, :atom
        field :function, :atom
        field :arity, :integer
        field :python_name, :string
        field :description, :string
        field :async, :boolean, default: false
      end
    end

    embeds_one :grpc, GRPCConfig do
      field :enabled, :boolean, default: true
      field :service_name, :string
      field :streaming_methods, {:array, :string}, default: []
      field :max_message_size, :integer, default: 4_194_304  # 4MB
    end

    embeds_one :caching, CachingConfig do
      field :enabled, :boolean, default: false
      field :ttl, :integer, default: 3600  # 1 hour
      field :cache_pure_functions, :boolean, default: true
    end

    embeds_one :telemetry, TelemetryConfig do
      field :enabled, :boolean, default: true
      field :prefix, {:array, :atom}
      field :metrics, {:array, :string}, default: ["duration", "count", "errors"]
    end
  end
end
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-25
**Author**: Claude Code + Human Collaborator
**Status**: Design / Proposal

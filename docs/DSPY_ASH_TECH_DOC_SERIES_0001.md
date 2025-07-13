Looking at the comprehensive analysis and requirements, I'll create the next series of technical documents for building a DSPy system in Ash. The goal is to create a clean, complete prototype that can execute real DSPy programs.

# DSPy-Ash Technical Document Series

## Document 1: Ash DSPy Core Architecture

```elixir
# File: docs/dspex_core_architecture.md

# Ash DSPy Core Architecture

## Overview

This document defines the core architecture for implementing DSPy in Ash, leveraging Ash's powerful domain modeling capabilities to create a clean, extensible DSPy framework.

## Core Domain Structure

```elixir
defmodule DSPyAsh.Core do
  use Ash.Domain
  
  resources do
    resource DSPyAsh.Core.Signature
    resource DSPyAsh.Core.Module
    resource DSPyAsh.Core.Predictor
    resource DSPyAsh.Core.Program
    resource DSPyAsh.Core.Example
    resource DSPyAsh.Core.Trace
    resource DSPyAsh.Core.Optimizer
    resource DSPyAsh.Core.Metric
  end
end
```

## Resource Architecture

### 1. Signature Resource

```elixir
defmodule DSPyAsh.Core.Signature do
  use Ash.Resource,
    domain: DSPyAsh.Core,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :docstring, :string
    attribute :input_fields, {:array, :map}, default: []
    attribute :output_fields, {:array, :map}, default: []
    attribute :metadata, :map, default: %{}
    
    timestamps()
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :create do
      primary? true
      
      argument :inputs, {:array, :map}, allow_nil?: false
      argument :outputs, {:array, :map}, allow_nil?: false
      argument :docstring, :string
      
      change DSPyAsh.Core.Changes.ParseSignature
      change DSPyAsh.Core.Changes.ValidateFields
    end
    
    action :compile, :map do
      argument :signature_string, :string, allow_nil?: false
      
      run DSPyAsh.Core.Actions.CompileSignature
    end
  end
  
  code_interface do
    define :create
    define :compile
  end
end
```

### 2. Module Resource

```elixir
defmodule DSPyAsh.Core.Module do
  use Ash.Resource,
    domain: DSPyAsh.Core,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :type, :atom, constraints: [
      one_of: [:predict, :chain_of_thought, :program_of_thought, :react, :custom]
    ]
    attribute :config, :map, default: %{}
    attribute :state, :map, default: %{}
    
    timestamps()
  end
  
  relationships do
    belongs_to :signature, DSPyAsh.Core.Signature
    has_many :traces, DSPyAsh.Core.Trace
  end
  
  actions do
    defaults [:read, :update, :destroy]
    
    create :create do
      primary? true
      accept [:name, :type, :config]
      
      argument :signature_id, :uuid, allow_nil?: false
      
      change manage_relationship(:signature_id, :signature, type: :append)
      change DSPyAsh.Core.Changes.InitializeModule
    end
    
    action :forward, :map do
      argument :inputs, :map, allow_nil?: false
      
      run DSPyAsh.Core.Actions.Forward
    end
  end
end
```

### 3. Program Resource

```elixir
defmodule DSPyAsh.Core.Program do
  use Ash.Resource,
    domain: DSPyAsh.Core,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :modules, {:array, :map}, default: []
    attribute :forward_fn, :string  # Serialized forward function
    attribute :compiled_state, :map
    attribute :metrics, :map, default: %{}
    
    timestamps()
  end
  
  relationships do
    has_many :modules, DSPyAsh.Core.Module
    has_many :traces, DSPyAsh.Core.Trace
    belongs_to :optimizer, DSPyAsh.Core.Optimizer
  end
  
  actions do
    defaults [:read, :update, :destroy]
    
    create :create do
      primary? true
      accept [:name, :description]
      
      change DSPyAsh.Core.Changes.InitializeProgram
    end
    
    update :compile do
      argument :optimizer_id, :uuid
      argument :trainset, {:array, :map}
      argument :metric, :string
      
      change DSPyAsh.Core.Changes.CompileProgram
    end
    
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      
      run DSPyAsh.Core.Actions.ExecuteProgram
    end
  end
end
```

## Key Design Decisions

1. **Resource-Based Architecture**: Each DSPy concept maps to an Ash resource
2. **Persistent State**: All state is persisted, enabling recovery and analysis
3. **Action-Oriented**: Core operations are implemented as Ash actions
4. **Relationship Modeling**: Clear relationships between signatures, modules, and programs
5. **Extensibility**: Easy to add new module types and optimizers

## Integration Points

- **AshGraphQL**: Automatic GraphQL API for all resources
- **AshJsonApi**: REST API generation
- **AshAuthentication**: User management for multi-tenant deployments
- **AshStateMachine**: State management for program execution
- **AshPaperTrail**: Audit logging for all operations
```

## Document 2: DSPy Signature Implementation in Ash

```elixir
# File: docs/dspex_signature_implementation.md

# DSPy Signature Implementation in Ash

## Overview

This document details how to implement DSPy's signature system using Ash's powerful DSL and validation capabilities.

## Signature DSL

```elixir
defmodule DSPyAsh.Signature do
  @moduledoc """
  DSL for defining DSPy signatures in Ash
  """
  
  defmacro __using__(opts) do
    quote do
      use Ash.Resource.Extension
      
      @signature_name unquote(opts[:name]) || __MODULE__
      @signature_fields %{inputs: [], outputs: []}
      
      import DSPyAsh.Signature
    end
  end
  
  defmacro signature(do: block) do
    quote do
      unquote(block)
      
      # After collecting fields, generate the signature resource
      @after_compile {DSPyAsh.Signature, :__after_compile__}
    end
  end
  
  defmacro input(name, type, opts \\ []) do
    quote do
      @signature_fields Map.update!(@signature_fields, :inputs, fn inputs ->
        inputs ++ [{unquote(name), unquote(type), unquote(opts)}]
      end)
    end
  end
  
  defmacro output(name, type, opts \\ []) do
    quote do
      @signature_fields Map.update!(@signature_fields, :outputs, fn outputs ->
        outputs ++ [{unquote(name), unquote(type), unquote(opts)}]
      end)
    end
  end
  
  def __after_compile__(env, _bytecode) do
    fields = Module.get_attribute(env.module, :signature_fields)
    
    # Create the signature in the database
    DSPyAsh.Core.Signature.create!(%{
      name: to_string(env.module),
      inputs: encode_fields(fields.inputs),
      outputs: encode_fields(fields.outputs)
    })
  end
  
  defp encode_fields(fields) do
    Enum.map(fields, fn {name, type, opts} ->
      %{
        name: to_string(name),
        type: to_string(type),
        description: opts[:desc] || "",
        optional: opts[:optional] || false,
        default: opts[:default]
      }
    end)
  end
end
```

## Example Signatures

```elixir
defmodule BasicQA do
  use DSPyAsh.Signature, name: "BasicQA"
  
  signature do
    input :question, :string, desc: "The question to answer"
    output :answer, :string, desc: "The answer to the question"
  end
end

defmodule ChainOfThoughtQA do
  use DSPyAsh.Signature, name: "ChainOfThoughtQA"
  
  signature do
    input :question, :string, desc: "The question to answer"
    input :context, :string, desc: "Optional context", optional: true
    
    output :reasoning, :string, desc: "Step-by-step reasoning"
    output :answer, :string, desc: "Final answer"
  end
end

defmodule RAG do
  use DSPyAsh.Signature, name: "RAG"
  
  signature do
    input :question, :string
    input :passages, {:array, :string}, desc: "Retrieved passages"
    
    output :answer, :string
    output :citations, {:array, :integer}, desc: "Passage indices used"
  end
end
```

## Signature Validation

```elixir
defmodule DSPyAsh.Core.Changes.ValidateFields do
  use Ash.Resource.Change
  
  def change(changeset, _, _) do
    changeset
    |> validate_field_types()
    |> validate_field_names()
    |> validate_field_descriptions()
  end
  
  defp validate_field_types(changeset) do
    input_fields = Ash.Changeset.get_attribute(changeset, :input_fields)
    output_fields = Ash.Changeset.get_attribute(changeset, :output_fields)
    
    all_fields = input_fields ++ output_fields
    
    Enum.reduce(all_fields, changeset, fn field, acc ->
      case validate_type(field["type"]) do
        :ok -> acc
        {:error, message} -> 
          Ash.Changeset.add_error(acc, field: :fields, message: message)
      end
    end)
  end
  
  defp validate_type(type) do
    valid_types = ~w(string integer float boolean array map any)
    
    cond do
      type in valid_types -> :ok
      String.starts_with?(type, "{:array,") -> :ok
      String.starts_with?(type, "{:map,") -> :ok
      true -> {:error, "Invalid type: #{type}"}
    end
  end
end
```

## Runtime Signature Usage

```elixir
defmodule DSPyAsh.Runtime.Signature do
  @moduledoc """
  Runtime utilities for working with signatures
  """
  
  def parse(signature_string) do
    # Parse "question -> answer" style signatures
    case String.split(signature_string, "->") do
      [inputs, outputs] ->
        %{
          inputs: parse_fields(inputs),
          outputs: parse_fields(outputs)
        }
      _ ->
        {:error, "Invalid signature format"}
    end
  end
  
  defp parse_fields(fields_string) do
    fields_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn field ->
      case String.split(field, ":") do
        [name] -> %{name: name, type: "string", optional: false}
        [name, type] -> %{name: name, type: type, optional: false}
      end
    end)
  end
  
  def validate_inputs(signature, inputs) do
    required_inputs = signature.input_fields
    |> Enum.reject(& &1["optional"])
    |> Enum.map(& &1["name"])
    
    missing = required_inputs -- Map.keys(inputs)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required inputs: #{Enum.join(missing, ", ")}"}
    end
  end
end
```
```

## Document 3: DSPy Module System in Ash

```elixir
# File: docs/dspex_module_system.md

# DSPy Module System in Ash

## Overview

This document describes the implementation of DSPy's module system (Predict, ChainOfThought, etc.) using Ash resources and actions.

## Base Module Behavior

```elixir
defmodule DSPyAsh.Module do
  @moduledoc """
  Base behavior for all DSPy modules
  """
  
  @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
  @callback forward(inputs :: map(), state :: map()) :: {:ok, outputs :: map(), new_state :: map()} | {:error, term()}
  @callback get_demos(state :: map()) :: list(map())
  @callback set_demos(demos :: list(map()), state :: map()) :: {:ok, new_state :: map()}
  
  defmacro __using__(opts) do
    quote do
      @behaviour DSPyAsh.Module
      
      @module_type unquote(opts[:type]) || :custom
      
      def create(signature, config \\ %{}) do
        DSPyAsh.Core.Module.create!(%{
          name: to_string(__MODULE__),
          type: @module_type,
          config: config,
          signature_id: signature.id
        })
      end
    end
  end
end
```

## Core Module Implementations

### Predict Module

```elixir
defmodule DSPyAsh.Modules.Predict do
  use DSPyAsh.Module, type: :predict
  
  alias DSPyAsh.LM
  
  @impl true
  def init(config) do
    {:ok, %{
      demos: [],
      temperature: config[:temperature] || 0.0,
      max_tokens: config[:max_tokens] || 1000
    }}
  end
  
  @impl true
  def forward(inputs, state) do
    with {:ok, prompt} <- build_prompt(inputs, state),
         {:ok, response} <- LM.generate(prompt, state),
         {:ok, outputs} <- parse_response(response, state) do
      
      # Record trace
      DSPyAsh.Core.Trace.create!(%{
        module_id: state.module_id,
        inputs: inputs,
        outputs: outputs,
        prompt: prompt,
        response: response
      })
      
      {:ok, outputs, state}
    end
  end
  
  @impl true
  def get_demos(state), do: state.demos
  
  @impl true
  def set_demos(demos, state) do
    {:ok, %{state | demos: demos}}
  end
  
  defp build_prompt(inputs, state) do
    signature = state.signature
    demos = state.demos
    
    prompt = """
    #{signature.docstring}
    
    #{format_demos(demos)}
    
    #{format_inputs(inputs, signature)}
    
    #{format_output_instructions(signature)}
    """
    
    {:ok, prompt}
  end
  
  defp format_demos([]), do: ""
  defp format_demos(demos) do
    demos
    |> Enum.map(fn demo ->
      """
      Example:
      #{format_example(demo)}
      """
    end)
    |> Enum.join("\n")
  end
end
```

### ChainOfThought Module

```elixir
defmodule DSPyAsh.Modules.ChainOfThought do
  use DSPyAsh.Module, type: :chain_of_thought
  
  alias DSPyAsh.LM
  
  @impl true
  def init(config) do
    # ChainOfThought extends Predict with reasoning field
    {:ok, %{
      demos: [],
      temperature: config[:temperature] || 0.7,
      max_tokens: config[:max_tokens] || 1500,
      reasoning_field: "reasoning"
    }}
  end
  
  @impl true
  def forward(inputs, state) do
    # Add reasoning field to signature
    extended_signature = add_reasoning_field(state.signature)
    
    with {:ok, prompt} <- build_cot_prompt(inputs, state, extended_signature),
         {:ok, response} <- LM.generate(prompt, state),
         {:ok, outputs} <- parse_cot_response(response, extended_signature) do
      
      # Record trace with reasoning
      DSPyAsh.Core.Trace.create!(%{
        module_id: state.module_id,
        inputs: inputs,
        outputs: outputs,
        prompt: prompt,
        response: response,
        metadata: %{reasoning: outputs[state.reasoning_field]}
      })
      
      {:ok, outputs, state}
    end
  end
  
  defp build_cot_prompt(inputs, state, signature) do
    prompt = """
    #{signature.docstring}
    
    Let's think step by step to answer this question.
    
    #{format_cot_demos(state.demos)}
    
    #{format_inputs(inputs, signature)}
    
    Reasoning: Let me think through this step by step.
    """
    
    {:ok, prompt}
  end
  
  defp add_reasoning_field(signature) do
    # Insert reasoning field before other outputs
    %{signature | 
      output_fields: [
        %{
          "name" => "reasoning",
          "type" => "string",
          "description" => "Step by step reasoning"
        } | signature.output_fields
      ]
    }
  end
end
```

### ReAct Module

```elixir
defmodule DSPyAsh.Modules.ReAct do
  use DSPyAsh.Module, type: :react
  
  @impl true
  def init(config) do
    {:ok, %{
      tools: config[:tools] || [],
      max_iterations: config[:max_iterations] || 5,
      temperature: config[:temperature] || 0.7
    }}
  end
  
  @impl true
  def forward(inputs, state) do
    run_react_loop(inputs, state, 0, [])
  end
  
  defp run_react_loop(inputs, state, iteration, history) do
    if iteration >= state.max_iterations do
      {:error, "Max iterations reached"}
    else
      with {:ok, thought} <- generate_thought(inputs, history, state),
           {:ok, action} <- generate_action(thought, state),
           {:ok, observation} <- execute_action(action, state) do
        
        new_history = history ++ [%{thought: thought, action: action, observation: observation}]
        
        if is_final_answer?(action) do
          {:ok, %{answer: observation}, state}
        else
          run_react_loop(inputs, state, iteration + 1, new_history)
        end
      end
    end
  end
  
  defp generate_thought(inputs, history, state) do
    prompt = build_thought_prompt(inputs, history, state)
    
    case LM.generate(prompt, state) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end
  
  defp generate_action(thought, state) do
    prompt = """
    Based on this thought: #{thought}
    
    Available tools: #{format_tools(state.tools)}
    
    What action should I take? (Use format: Action: tool_name[args])
    """
    
    case LM.generate(prompt, state) do
      {:ok, response} -> parse_action(response)
      error -> error
    end
  end
  
  defp execute_action(%{tool: "Finish", args: answer}, _state) do
    {:ok, answer}
  end
  
  defp execute_action(%{tool: tool_name, args: args}, state) do
    case find_tool(tool_name, state.tools) do
      nil -> {:error, "Unknown tool: #{tool_name}"}
      tool -> tool.execute(args)
    end
  end
end
```

## Module Actions

```elixir
defmodule DSPyAsh.Core.Actions.Forward do
  use Ash.Resource.Actions.Implementation
  
  def run(input, opts, context) do
    module = context.record
    
    # Load the module implementation
    module_impl = get_module_implementation(module.type)
    
    # Execute forward pass
    case module_impl.forward(input.arguments.inputs, module.state) do
      {:ok, outputs, new_state} ->
        # Update module state
        module
        |> Ash.Changeset.for_update(:update, %{state: new_state})
        |> Ash.update!()
        
        {:ok, outputs}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_module_implementation(type) do
    case type do
      :predict -> DSPyAsh.Modules.Predict
      :chain_of_thought -> DSPyAsh.Modules.ChainOfThought
      :react -> DSPyAsh.Modules.ReAct
      _ -> raise "Unknown module type: #{type}"
    end
  end
end
```

## Module Composition

```elixir
defmodule DSPyAsh.Modules.Composed do
  @moduledoc """
  Support for composing multiple modules
  """
  
  defstruct [:modules, :forward_fn]
  
  def new(modules, forward_fn) do
    %__MODULE__{
      modules: modules,
      forward_fn: forward_fn
    }
  end
  
  def forward(%__MODULE__{} = composed, inputs) do
    # Execute the forward function with modules
    composed.forward_fn.(composed.modules, inputs)
  end
end

# Example usage
defmodule QAWithRetrieval do
  def create do
    retrieve = DSPyAsh.Modules.Retrieve.create(RetrieveSignature)
    generate = DSPyAsh.Modules.ChainOfThought.create(GenerateSignature)
    
    DSPyAsh.Modules.Composed.new(
      %{retrieve: retrieve, generate: generate},
      fn modules, inputs ->
        with {:ok, passages} <- modules.retrieve.forward(%{query: inputs.question}),
             {:ok, answer} <- modules.generate.forward(%{
               question: inputs.question,
               context: Enum.join(passages, "\n")
             }) do
          {:ok, answer}
        end
      end
    )
  end
end
```
```

## Document 4: DSPy LM Integration with Ash

```elixir
# File: docs/dspex_lm_integration.md

# DSPy LM (Language Model) Integration with Ash

## Overview

This document describes how to integrate language models with the Ash-based DSPy implementation, providing a clean abstraction for multiple LM providers.

## LM Resource and Domain

```elixir
defmodule DSPyAsh.LM do
  use Ash.Domain
  
  resources do
    resource DSPyAsh.LM.Provider
    resource DSPyAsh.LM.Request
    resource DSPyAsh.LM.Response
    resource DSPyAsh.LM.Cache
  end
end

defmodule DSPyAsh.LM.Provider do
  use Ash.Resource,
    domain: DSPyAsh.LM,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :type, :atom, constraints: [
      one_of: [:openai, :anthropic, :cohere, :local]
    ]
    attribute :config, :map, sensitive?: true
    attribute :is_default, :boolean, default: false
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    action :generate, :map do
      argument :prompt, :string, allow_nil?: false
      argument :options, :map, default: %{}
      
      run DSPyAsh.LM.Actions.Generate
    end
  end
  
  code_interface do
    define :generate
  end
end
```

## LM Adapter Behavior

```elixir
defmodule DSPyAsh.LM.Adapter do
  @moduledoc """
  Behavior for LM adapters
  """
  
  @callback generate(prompt :: String.t(), config :: map(), options :: map()) ::
    {:ok, response :: String.t()} | {:error, term()}
    
  @callback generate_batch(prompts :: list(String.t()), config :: map(), options :: map()) ::
    {:ok, responses :: list(String.t())} | {:error, term()}
    
  @callback count_tokens(text :: String.t(), config :: map()) ::
    {:ok, count :: integer()} | {:error, term()}
end
```

## Provider Implementations

### OpenAI Adapter

```elixir
defmodule DSPyAsh.LM.Adapters.OpenAI do
  @behaviour DSPyAsh.LM.Adapter
  
  @impl true
  def generate(prompt, config, options) do
    model = options[:model] || config[:model] || "gpt-4"
    temperature = options[:temperature] || 0.0
    max_tokens = options[:max_tokens] || 1000
    
    request_body = %{
      model: model,
      messages: [
        %{role: "user", content: prompt}
      ],
      temperature: temperature,
      max_tokens: max_tokens
    }
    
    headers = [
      {"Authorization", "Bearer #{config[:api_key]}"},
      {"Content-Type", "application/json"}
    ]
    
    case HTTPoison.post(
      "https://api.openai.com/v1/chat/completions",
      Jason.encode!(request_body),
      headers
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, get_in(response, ["choices", Access.at(0), "message", "content"])}
        
      {:ok, %{status_code: status, body: body}} ->
        {:error, "OpenAI API error (#{status}): #{body}"}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def generate_batch(prompts, config, options) do
    # OpenAI doesn't have native batch support, so we'll do concurrent requests
    tasks = Enum.map(prompts, fn prompt ->
      Task.async(fn -> generate(prompt, config, options) end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    
    # Check if all succeeded
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, response} -> response end)}
      error -> error
    end
  end
  
  @impl true
  def count_tokens(text, _config) do
    # Simplified token counting - in production use tiktoken
    {:ok, div(String.length(text), 4)}
  end
end
```

### Anthropic Adapter

```elixir
defmodule DSPyAsh.LM.Adapters.Anthropic do
  @behaviour DSPyAsh.LM.Adapter
  
  @impl true
  def generate(prompt, config, options) do
    model = options[:model] || config[:model] || "claude-3-opus-20240229"
    temperature = options[:temperature] || 0.0
    max_tokens = options[:max_tokens] || 1000
    
    request_body = %{
      model: model,
      messages: [
        %{role: "user", content: prompt}
      ],
      temperature: temperature,
      max_tokens: max_tokens
    }
    
    headers = [
      {"x-api-key", config[:api_key]},
      {"anthropic-version", "2023-06-01"},
      {"Content-Type", "application/json"}
    ]
    
    case HTTPoison.post(
      "https://api.anthropic.com/v1/messages",
      Jason.encode!(request_body),
      headers
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, get_in(response, ["content", Access.at(0), "text"])}
        
      {:ok, %{status_code: status, body: body}} ->
        {:error, "Anthropic API error (#{status}): #{body}"}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def generate_batch(prompts, config, options) do
    # Similar to OpenAI, use concurrent requests
    tasks = Enum.map(prompts, fn prompt ->
      Task.async(fn -> generate(prompt, config, options) end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, response} -> response end)}
      error -> error
    end
  end
  
  @impl true
  def count_tokens(text, _config) do
    # Simplified - Anthropic uses similar tokenization to OpenAI
    {:ok, div(String.length(text), 4)}
  end
end
```

## LM Service

```elixir
defmodule DSPyAsh.LM.Service do
  @moduledoc """
  High-level service for LM operations with caching and retries
  """
  
  alias DSPyAsh.LM.{Provider, Request, Response, Cache}
  
  def generate(prompt, options \\ %{}) do
    provider = get_provider(options)
    
    # Check cache first
    cache_key = generate_cache_key(prompt, provider, options)
    
    case get_from_cache(cache_key) do
      {:ok, cached_response} ->
        {:ok, cached_response}
        
      :miss ->
        # Generate with retries
        with {:ok, response} <- generate_with_retries(prompt, provider, options) do
          # Cache the response
          cache_response(cache_key, response)
          
          # Record the request/response
          record_request_response(prompt, response, provider, options)
          
          {:ok, response}
        end
    end
  end
  
  defp get_provider(options) do
    case options[:provider_id] do
      nil -> get_default_provider()
      id -> Provider.get!(id)
    end
  end
  
  defp get_default_provider do
    Provider
    |> Ash.Query.filter(is_default == true)
    |> Ash.read_one!()
  end
  
  defp generate_with_retries(prompt, provider, options, attempts \\ 0) do
    adapter = get_adapter(provider.type)
    
    case adapter.generate(prompt, provider.config, options) do
      {:ok, response} ->
        {:ok, response}
        
      {:error, reason} when attempts < 3 ->
        # Exponential backoff
        Process.sleep(:math.pow(2, attempts) * 1000)
        generate_with_retries(prompt, provider, options, attempts + 1)
        
      error ->
        error
    end
  end
  
  defp get_adapter(type) do
    case type do
      :openai -> DSPyAsh.LM.Adapters.OpenAI
      :anthropic -> DSPyAsh.LM.Adapters.Anthropic
      :cohere -> DSPyAsh.LM.Adapters.Cohere
      _ -> raise "Unknown adapter type: #{type}"
    end
  end
  
  defp generate_cache_key(prompt, provider, options) do
    data = %{
      prompt: prompt,
      provider_id: provider.id,
      model: options[:model] || provider.config[:model],
      temperature: options[:temperature] || 0.0
    }
    
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16()
  end
  
  defp get_from_cache(key) do
    case Cache
         |> Ash.Query.filter(key == ^key)
         |> Ash.Query.filter(expires_at > ^DateTime.utc_now())
         |> Ash.read_one() do
      {:ok, nil} -> :miss
      {:ok, cache} -> {:ok, cache.value}
      _ -> :miss
    end
  end
  
  defp cache_response(key, response) do
    Cache.create!(%{
      key: key,
      value: response,
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
  end
  
  defp record_request_response(prompt, response, provider, options) do
    Request.create!(%{
      provider_id: provider.id,
      prompt: prompt,
      options: options,
      response_text: response,
      tokens_used: count_tokens(prompt, response, provider),
      latency_ms: 0  # Would be tracked in real implementation
    })
  end
end
```

## DSPy Integration

```elixir
defmodule DSPyAsh.LM do
  @moduledoc """
  Main interface for LM operations in DSPy
  """
  
  defdelegate generate(prompt, options \\ %{}), to: DSPyAsh.LM.Service
  
  def inspect_history(n \\ 10) do
    Request
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(n)
    |> Ash.read!()
  end
  
  def get_usage_stats(provider_id \\ nil) do
    query = Request
    
    query = if provider_id do
      Ash.Query.filter(query, provider_id == ^provider_id)
    else
      query
    end
    
    requests = Ash.read!(query)
    
    %{
      total_requests: length(requests),
      total_tokens: Enum.sum(Enum.map(requests, & &1.tokens_used)),
      average_latency: calculate_average_latency(requests)
    }
  end
  
  defp calculate_average_latency([]), do: 0
  defp calculate_average_latency(requests) do
    total = Enum.sum(Enum.map(requests, & &1.latency_ms))
    div(total, length(requests))
  end
end
```

## Configuration

```elixir
# config/config.exs
config :dspy_ash, :lm,
  default_provider: :openai,
  providers: [
    openai: [
      adapter: DSPyAsh.LM.Adapters.OpenAI,
      api_key: System.get_env("OPENAI_API_KEY"),
      model: "gpt-4"
    ],
    anthropic: [
      adapter: DSPyAsh.LM.Adapters.Anthropic,
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      model: "claude-3-opus-20240229"
    ]
  ],
  cache_ttl: 3600,
  max_retries: 3,
  retry_delay: 1000
```
```

## Document 5: DSPy Optimizer Implementation in Ash

```elixir
# File: docs/dspex_optimizer_implementation.md

# DSPy Optimizer Implementation in Ash

## Overview

This document describes how to implement DSPy's optimization framework (BootstrapFewShot, MIPRO, etc.) using Ash resources and the Python bridge.

## Optimizer Resource Architecture

```elixir
defmodule DSPyAsh.Core.Optimizer do
  use Ash.Resource,
    domain: DSPyAsh.Core,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :type, :atom, constraints: [
      one_of: [:bootstrap_fewshot, :bootstrap_fewshot_with_optuna, :mipro, :copro]
    ]
    attribute :config, :map, default: %{}
    attribute :state, :map, default: %{}
    attribute :metrics, :map, default: %{}
    
    timestamps()
  end
  
  relationships do
    has_many :optimization_runs, DSPyAsh.Core.OptimizationRun
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    action :compile, :map do
      argument :program_id, :uuid, allow_nil?: false
      argument :trainset, {:array, :map}, allow_nil?: false
      argument :metric, :string, allow_nil?: false
      argument :kwargs, :map, default: %{}
      
      run DSPyAsh.Core.Actions.CompileOptimizer
    end
  end
end

defmodule DSPyAsh.Core.OptimizationRun do
  use Ash.Resource,
    domain: DSPyAsh.Core,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    
    attribute :status, :atom, constraints: [
      one_of: [:running, :completed, :failed]
    ], default: :running
    
    attribute :trainset, {:array, :map}
    attribute :metric_name, :string
    attribute :score, :float
    attribute :best_program_state, :map
    attribute :traces, {:array, :map}
    attribute :error, :string
    
    timestamps()
  end
  
  relationships do
    belongs_to :optimizer, DSPyAsh.Core.Optimizer
    belongs_to :program, DSPyAsh.Core.Program
  end
end
```

## Optimizer Behaviors

```elixir
defmodule DSPyAsh.Optimizer do
  @moduledoc """
  Behavior for DSPy optimizers
  """
  
  @callback init(config :: map()) :: {:ok, state :: map()} | {:error, term()}
  
  @callback compile(
    program :: DSPyAsh.Core.Program.t(),
    trainset :: list(map()),
    metric :: function(),
    state :: map()
  ) :: {:ok, optimized_program :: map(), new_state :: map()} | {:error, term()}
  
  @callback get_traces(state :: map()) :: list(map())
end
```

## BootstrapFewShot Implementation

```elixir
defmodule DSPyAsh.Optimizers.BootstrapFewShot do
  @behaviour DSPyAsh.Optimizer
  
  @impl true
  def init(config) do
    {:ok, %{
      max_bootstrapped_demos: config[:max_bootstrapped_demos] || 4,
      max_labeled_demos: config[:max_labeled_demos] || 16,
      max_rounds: config[:max_rounds] || 1,
      max_errors: config[:max_errors] || 5,
      teacher_settings: config[:teacher_settings] || %{},
      config: config
    }}
  end
  
  @impl true
  def compile(program, trainset, metric, state) do
    # Create optimization run
    run = DSPyAsh.Core.OptimizationRun.create!(%{
      optimizer_id: state.optimizer_id,
      program_id: program.id,
      trainset: trainset,
      metric_name: inspect(metric)
    })
    
    # Use Python bridge for actual optimization
    case python_compile(program, trainset, metric, state) do
      {:ok, optimized_state} ->
        # Update program with optimized state
        program
        |> Ash.Changeset.for_update(:update, %{
          compiled_state: optimized_state,
          metrics: %{training_score: optimized_state.score}
        })
        |> Ash.update!()
        
        # Update optimization run
        run
        |> Ash.Changeset.for_update(:update, %{
          status: :completed,
          score: optimized_state.score,
          best_program_state: optimized_state
        })
        |> Ash.update!()
        
        {:ok, optimized_state, state}
        
      {:error, reason} ->
        # Update optimization run with error
        run
        |> Ash.Changeset.for_update(:update, %{
          status: :failed,
          error: inspect(reason)
        })
        |> Ash.update!()
        
        {:error, reason}
    end
  end
  
  defp python_compile(program, trainset, metric, state) do
    # Call Python bridge
    DSPyAsh.PythonBridge.call(:optimize, %{
      optimizer: "BootstrapFewShot",
      program: serialize_program(program),
      trainset: trainset,
      metric: serialize_metric(metric),
      config: state.config
    })
  end
  
  defp serialize_program(program) do
    %{
      id: program.id,
      modules: Enum.map(program.modules, &serialize_module/1),
      forward_fn: program.forward_fn
    }
  end
  
  defp serialize_module(module) do
    %{
      id: module.id,
      type: module.type,
      signature: serialize_signature(module.signature),
      state: module.state
    }
  end
  
  defp serialize_signature(signature) do
    %{
      inputs: signature.input_fields,
      outputs: signature.output_fields
    }
  end
  
  defp serialize_metric(metric) when is_function(metric) do
    # For now, we'll use predefined metrics
    case Function.info(metric)[:name] do
      :exact_match -> "exact_match"
      :f1_score -> "f1_score"
      _ -> "custom"
    end
  end
end
```

## MIPRO Implementation

```elixir
defmodule DSPyAsh.Optimizers.MIPRO do
  @behaviour DSPyAsh.Optimizer
  
  @impl true
  def init(config) do
    {:ok, %{
      num_candidates: config[:num_candidates] || 10,
      init_temperature: config[:init_temperature] || 1.0,
      verbose: config[:verbose] || false,
      track_stats: config[:track_stats] || true,
      view_data_batch_size: config[:view_data_batch_size] || 10,
      minibatch_size: config[:minibatch_size] || 25,
      minibatch_full_eval_steps: config[:minibatch_full_eval_steps] || 10,
      config: config
    }}
  end
  
  @impl true
  def compile(program, trainset, metric, state) do
    # MIPRO is more complex, requiring instruction optimization
    run = create_optimization_run(program, trainset, metric, state)
    
    # Execute MIPRO optimization via Python bridge
    case python_mipro_optimize(program, trainset, metric, state) do
      {:ok, result} ->
        # Update program with optimized instructions and examples
        update_program_with_mipro_results(program, result)
        
        # Complete optimization run
        complete_optimization_run(run, result)
        
        {:ok, result.optimized_program, state}
        
      {:error, reason} ->
        fail_optimization_run(run, reason)
        {:error, reason}
    end
  end
  
  defp python_mipro_optimize(program, trainset, metric, state) do
    DSPyAsh.PythonBridge.call(:optimize, %{
      optimizer: "MIPRO",
      program: serialize_program(program),
      trainset: trainset,
      metric: serialize_metric(metric),
      config: Map.merge(state.config, %{
        num_candidates: state.num_candidates,
        init_temperature: state.init_temperature
      })
    })
  end
  
  defp update_program_with_mipro_results(program, result) do
    # Update each module with optimized instructions
    Enum.each(result.module_instructions, fn {module_id, instructions} ->
      module = DSPyAsh.Core.Module.get!(module_id)
      
      module
      |> Ash.Changeset.for_update(:update, %{
        state: Map.merge(module.state, %{
          instructions: instructions,
          demos: result.module_demos[module_id] || []
        })
      })
      |> Ash.update!()
    end)
    
    # Update program with overall metrics
    program
    |> Ash.Changeset.for_update(:update, %{
      compiled_state: result.optimized_program,
      metrics: Map.merge(program.metrics, %{
        training_score: result.score,
        mipro_stats: result.stats
      })
    })
    |> Ash.update!()
  end
end
```

## Metric Functions

```elixir
defmodule DSPyAsh.Metrics do
  @moduledoc """
  Common metric functions for optimization
  """
  
  def exact_match(example, prediction, _trace \\ nil) do
    normalize(example.answer) == normalize(prediction.answer)
  end
  
  def f1_score(example, prediction, _trace \\ nil) do
    gold_tokens = tokenize(example.answer)
    pred_tokens = tokenize(prediction.answer)
    
    true_positives = MapSet.intersection(gold_tokens, pred_tokens) |> MapSet.size()
    
    precision = if MapSet.size(pred_tokens) > 0 do
      true_positives / MapSet.size(pred_tokens)
    else
      0.0
    end
    
    recall = if MapSet.size(gold_tokens) > 0 do
      true_positives / MapSet.size(gold_tokens)
    else
      0.0
    end
    
    if precision + recall > 0 do
      2 * precision * recall / (precision + recall)
    else
      0.0
    end
  end
  
  def passage_match(example, prediction, _trace \\ nil) do
    # Check if prediction cites correct passages
    cited_passages = prediction[:citations] || []
    gold_passages = example[:gold_passages] || []
    
    if length(gold_passages) == 0 do
      1.0
    else
      correct_citations = Enum.count(cited_passages, &(&1 in gold_passages))
      correct_citations / length(gold_passages)
    end
  end
  
  defp normalize(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[[:punct:]]/, "")
  end
  
  defp tokenize(text) do
    text
    |> normalize()
    |> String.split()
    |> MapSet.new()
  end
end
```

## Optimization Actions

```elixir
defmodule DSPyAsh.Core.Actions.CompileOptimizer do
  use Ash.Resource.Actions.Implementation
  
  def run(input, _opts, context) do
    optimizer = context.record
    program = DSPyAsh.Core.Program.get!(input.arguments.program_id)
    trainset = input.arguments.trainset
    metric = resolve_metric(input.arguments.metric)
    
    # Get optimizer implementation
    optimizer_impl = get_optimizer_implementation(optimizer.type)
    
    # Initialize optimizer state
    {:ok, optimizer_state} = optimizer_impl.init(optimizer.config)
    optimizer_state = Map.put(optimizer_state, :optimizer_id, optimizer.id)
    
    # Run optimization
    case optimizer_impl.compile(program, trainset, metric, optimizer_state) do
      {:ok, optimized_program, new_state} ->
        # Update optimizer state
        optimizer
        |> Ash.Changeset.for_update(:update, %{state: new_state})
        |> Ash.update!()
        
        {:ok, %{
          program: optimized_program,
          score: optimized_program.metrics.training_score,
          traces: optimizer_impl.get_traces(new_state)
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_optimizer_implementation(type) do
    case type do
      :bootstrap_fewshot -> DSPyAsh.Optimizers.BootstrapFewShot
      :mipro -> DSPyAsh.Optimizers.MIPRO
      :copro -> DSPyAsh.Optimizers.COPRO
      _ -> raise "Unknown optimizer type: #{type}"
    end
  end
  
  defp resolve_metric(metric_name) when is_binary(metric_name) do
    case metric_name do
      "exact_match" -> &DSPyAsh.Metrics.exact_match/3
      "f1_score" -> &DSPyAsh.Metrics.f1_score/3
      "passage_match" -> &DSPyAsh.Metrics.passage_match/3
      _ -> raise "Unknown metric: #{metric_name}"
    end
  end
  
  defp resolve_metric(metric_fn) when is_function(metric_fn) do
    metric_fn
  end
end
```

## Evaluation Module

```elixir
defmodule DSPyAsh.Core.Evaluate do
  @moduledoc """
  Evaluation utilities for optimized programs
  """
  
  def evaluate(program, testset, metric \\ &DSPyAsh.Metrics.exact_match/3) do
    results = Enum.map(testset, fn example ->
      case execute_program(program, example) do
        {:ok, prediction} ->
          score = metric.(example, prediction, nil)
          %{example: example, prediction: prediction, score: score, error: nil}
          
        {:error, reason} ->
          %{example: example, prediction: nil, score: 0.0, error: reason}
      end
    end)
    
    %{
      total: length(results),
      correct: Enum.count(results, & &1.score >= 1.0),
      score: Enum.sum(Enum.map(results, & &1.score)) / length(results),
      results: results
    }
  end
  
  defp execute_program(program, example) do
    DSPyAsh.Core.Program.execute(program, example)
  end
end
```
```

## Document 6: DSPy Python Bridge for Ash

```elixir
# File: docs/dspex_python_bridge.md

# DSPy Python Bridge for Ash

## Overview

This document describes the Python bridge implementation that allows the Ash-based DSPy system to leverage the original Python DSPy implementation for complex operations like optimization.

## Bridge Architecture

```elixir
defmodule DSPyAsh.PythonBridge do
  @moduledoc """
  Bridge to Python DSPy implementation using Erlang ports
  """
  
  use GenServer
  require Logger
  
  @python_script Path.join(:code.priv_dir(:dspy_ash), "python/dspy_bridge.py")
  
  defstruct [:port, :requests, :request_id]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    port = Port.open({:spawn_executable, python_path()}, [
      {:args, [@python_script]},
      {:packet, 4},
      :binary,
      :exit_status
    ])
    
    {:ok, %__MODULE__{
      port: port,
      requests: %{},
      request_id: 0
    }}
  end
  
  def call(command, args, timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:call, command, args}, timeout)
  end
  
  def handle_call({:call, command, args}, from, state) do
    request_id = state.request_id + 1
    
    request = %{
      id: request_id,
      command: to_string(command),
      args: args
    }
    
    # Send to Python
    send(state.port, {self(), {:command, Jason.encode!(request)}})
    
    # Store request
    new_requests = Map.put(state.requests, request_id, from)
    
    {:noreply, %{state | requests: new_requests, request_id: request_id}}
  end
  
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Jason.decode(data) do
      {:ok, %{"id" => id, "result" => result}} ->
        # Success response
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warn("Received response for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
            
          {from, requests} ->
            GenServer.reply(from, {:ok, atomize_keys(result)})
            {:noreply, %{state | requests: requests}}
        end
        
      {:ok, %{"id" => id, "error" => error}} ->
        # Error response
        case Map.pop(state.requests, id) do
          {nil, requests} ->
            Logger.warn("Received error for unknown request: #{id}")
            {:noreply, %{state | requests: requests}}
            
          {from, requests} ->
            GenServer.reply(from, {:error, error})
            {:noreply, %{state | requests: requests}}
        end
        
      {:error, reason} ->
        Logger.error("Failed to decode Python response: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, :python_process_died, state}
  end
  
  defp python_path do
    System.find_executable("python3") || System.find_executable("python")
  end
  
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> 
      {String.to_atom(k), atomize_keys(v)}
    end)
  end
  
  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end
  
  defp atomize_keys(value), do: value
end
```

## Python Bridge Script

```python
# priv/python/dspy_bridge.py
#!/usr/bin/env python3

import sys
import json
import struct
import traceback
import dspy
from typing import Dict, Any, List

class DSPyBridge:
    def __init__(self):
        self.programs = {}
        self.modules = {}
        self.optimizers = {}
        
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Route commands to appropriate handlers"""
        handlers = {
            'configure': self.configure,
            'create_module': self.create_module,
            'create_program': self.create_program,
            'optimize': self.optimize,
            'execute': self.execute,
            'forward': self.forward
        }
        
        if command not in handlers:
            raise ValueError(f"Unknown command: {command}")
            
        return handlers[command](args)
    
    def configure(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Configure DSPy settings"""
        if 'lm' in args:
            lm_config = args['lm']
            if lm_config['provider'] == 'openai':
                lm = dspy.OpenAI(
                    model=lm_config.get('model', 'gpt-4'),
                    api_key=lm_config['api_key'],
                    temperature=lm_config.get('temperature', 0.0)
                )
                dspy.settings.configure(lm=lm)
            elif lm_config['provider'] == 'anthropic':
                lm = dspy.Claude(
                    model=lm_config.get('model', 'claude-3-opus-20240229'),
                    api_key=lm_config['api_key'],
                    temperature=lm_config.get('temperature', 0.0)
                )
                dspy.settings.configure(lm=lm)
                
        return {"status": "configured"}
    
    def create_module(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a DSPy module"""
        module_type = args['type']
        signature_str = args['signature']
        module_id = args['id']
        
        # Create signature
        signature = self._parse_signature(signature_str)
        
        # Create module based on type
        if module_type == 'predict':
            module = dspy.Predict(signature)
        elif module_type == 'chain_of_thought':
            module = dspy.ChainOfThought(signature)
        elif module_type == 'program_of_thought':
            module = dspy.ProgramOfThought(signature)
        elif module_type == 'react':
            module = dspy.ReAct(signature, tools=args.get('tools', []))
        else:
            raise ValueError(f"Unknown module type: {module_type}")
            
        self.modules[module_id] = module
        
        return {"id": module_id, "type": module_type}
    
    def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a DSPy program"""
        program_id = args['id']
        modules = args['modules']
        forward_code = args['forward_fn']
        
        # Create a dynamic program class
        class DynamicProgram(dspy.Module):
            def __init__(self):
                super().__init__()
                # Add modules as attributes
                for module_config in modules:
                    module = self.modules.get(module_config['id'])
                    if module:
                        setattr(self, module_config['name'], module)
            
            def forward(self, **kwargs):
                # Execute the forward function
                # This is simplified - in practice we'd need safe execution
                local_vars = {'self': self}
                local_vars.update(kwargs)
                exec(forward_code, {}, local_vars)
                return local_vars.get('result', {})
        
        program = DynamicProgram()
        self.programs[program_id] = program
        
        return {"id": program_id}
    
    def optimize(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Run optimization on a program"""
        optimizer_type = args['optimizer']
        program_data = args['program']
        trainset = args['trainset']
        metric_name = args['metric']
        config = args.get('config', {})
        
        # Get or create program
        program = self._get_or_create_program(program_data)
        
        # Convert trainset to DSPy examples
        train_examples = [
            dspy.Example(**example).with_inputs(*self._get_input_fields(example))
            for example in trainset
        ]
        
        # Get metric function
        metric = self._get_metric(metric_name)
        
        # Create and run optimizer
        if optimizer_type == 'BootstrapFewShot':
            optimizer = dspy.BootstrapFewShot(
                metric=metric,
                max_bootstrapped_demos=config.get('max_bootstrapped_demos', 4),
                max_labeled_demos=config.get('max_labeled_demos', 16)
            )
        elif optimizer_type == 'MIPRO':
            optimizer = dspy.MIPRO(
                metric=metric,
                num_candidates=config.get('num_candidates', 10),
                init_temperature=config.get('init_temperature', 1.0)
            )
        else:
            raise ValueError(f"Unknown optimizer: {optimizer_type}")
        
        # Compile
        compiled_program = optimizer.compile(
            program,
            trainset=train_examples,
            **config
        )
        
        # Extract optimized state
        optimized_state = self._extract_program_state(compiled_program)
        
        # Calculate score on trainset
        score = sum(metric(example, compiled_program(**example.inputs()))
                   for example in train_examples) / len(train_examples)
        
        return {
            "optimized_program": optimized_state,
            "score": score,
            "traces": []  # Would extract traces in full implementation
        }
    
    def execute(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a program"""
        program_id = args['program_id']
        inputs = args['inputs']
        
        program = self.programs.get(program_id)
        if not program:
            raise ValueError(f"Program not found: {program_id}")
        
        # Execute program
        result = program(**inputs)
        
        # Convert result to dict
        if hasattr(result, 'toDict'):
            result_dict = result.toDict()
        else:
            result_dict = dict(result) if hasattr(result, '__dict__') else {"result": str(result)}
        
        return result_dict
    
    def forward(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a module forward pass"""
        module_id = args['module_id']
        inputs = args['inputs']
        
        module = self.modules.get(module_id)
        if not module:
            raise ValueError(f"Module not found: {module_id}")
        
        # Execute module
        result = module(**inputs)
        
        # Convert result
        if hasattr(result, 'toDict'):
            result_dict = result.toDict()
        else:
            result_dict = dict(result) if hasattr(result, '__dict__') else {"result": str(result)}
        
        return result_dict
    
    def _parse_signature(self, signature_str: str) -> type:
        """Parse a signature string into a DSPy signature class"""
        # This is a simplified parser
        parts = signature_str.split('->')
        if len(parts) != 2:
            return signature_str  # Assume it's already a class
        
        inputs = [inp.strip() for inp in parts[0].split(',')]
        outputs = [out.strip() for out in parts[1].split(',')]
        
        # Create dynamic signature class
        class DynamicSignature(dspy.Signature):
            pass
        
        # Add input fields
        for inp in inputs:
            if ':' in inp:
                name, desc = inp.split(':', 1)
                setattr(DynamicSignature, name.strip(), dspy.InputField(desc=desc.strip()))
            else:
                setattr(DynamicSignature, inp.strip(), dspy.InputField())
        
        # Add output fields
        for out in outputs:
            if ':' in out:
                name, desc = out.split(':', 1)
                setattr(DynamicSignature, name.strip(), dspy.OutputField(desc=desc.strip()))
            else:
                setattr(DynamicSignature, out.strip(), dspy.OutputField())
        
        return DynamicSignature
    
    def _get_or_create_program(self, program_data: Dict[str, Any]) -> dspy.Module:
        """Get existing program or create from data"""
        program_id = program_data['id']
        
        if program_id in self.programs:
            return self.programs[program_id]
        
        # Create modules first
        for module_data in program_data['modules']:
            if module_data['id'] not in self.modules:
                self.create_module(module_data)
        
        # Create program
        self.create_program(program_data)
        return self.programs[program_id]
    
    def _get_input_fields(self, example: Dict[str, Any]) -> List[str]:
        """Extract input field names from example"""
        # This would be more sophisticated in practice
        return [k for k in example.keys() if not k.startswith('_')]
    
    def _get_metric(self, metric_name: str):
        """Get metric function by name"""
        if metric_name == 'exact_match':
            return lambda example, pred: example.answer == pred.answer
        elif metric_name == 'f1_score':
            return self._f1_score
        else:
            # Default metric
            return lambda example, pred: 1.0 if example.answer == pred.answer else 0.0
    
    def _f1_score(self, example, pred):
        """Calculate F1 score"""
        gold_tokens = set(example.answer.lower().split())
        pred_tokens = set(pred.answer.lower().split())
        
        if not pred_tokens:
            return 0.0
            
        precision = len(gold_tokens & pred_tokens) / len(pred_tokens)
        recall = len(gold_tokens & pred_tokens) / len(gold_tokens) if gold_tokens else 0.0
        
        if precision + recall == 0:
            return 0.0
            
        return 2 * precision * recall / (precision + recall)
    
    def _extract_program_state(self, program: dspy.Module) -> Dict[str, Any]:
        """Extract state from compiled program"""
        state = {
            "modules": {}
        }
        
        # Extract state from each module
        for name, module in program.named_children():
            module_state = {}
            
            # Extract demos if present
            if hasattr(module, 'demos'):
                module_state['demos'] = [
                    demo.toDict() if hasattr(demo, 'toDict') else dict(demo)
                    for demo in module.demos
                ]
            
            # Extract other attributes
            for attr in ['signature', 'max_tokens', 'temperature']:
                if hasattr(module, attr):
                    value = getattr(module, attr)
                    if hasattr(value, '__dict__'):
                        module_state[attr] = dict(value.__dict__)
                    else:
                        module_state[attr] = value
            
            state["modules"][name] = module_state
        
        return state

def read_message():
    """Read a message from stdin using Erlang packet protocol"""
    # Read 4-byte length header
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        return None
    
    # Unpack length (big-endian)
    length = struct.unpack('>I', length_bytes)[0]
    
    # Read message
    message_bytes = sys.stdin.buffer.read(length)
    if len(message_bytes) < length:
        return None
    
    return json.loads(message_bytes.decode('utf-8'))

def write_message(message):
    """Write a message to stdout using Erlang packet protocol"""
    message_bytes = json.dumps(message).encode('utf-8')
    length = len(message_bytes)
    
    # Write 4-byte length header (big-endian)
    sys.stdout.buffer.write(struct.pack('>I', length))
    sys.stdout.buffer.write(message_bytes)
    sys.stdout.buffer.flush()

def main():
    """Main bridge loop"""
    bridge = DSPyBridge()
    
    while True:
        try:
            message = read_message()
            if message is None:
                break
            
            request_id = message.get('id')
            command = message.get('command')
            args = message.get('args', {})
            
            try:
                result = bridge.handle_command(command, args)
                write_message({
                    'id': request_id,
                    'result': result
                })
            except Exception as e:
                write_message({
                    'id': request_id,
                    'error': str(e)
                })
                
        except Exception as e:
            # Log error but continue
            sys.stderr.write(f"Bridge error: {e}\n")
            sys.stderr.write(traceback.format_exc())

if __name__ == '__main__':
    main()
```

## Document 7: Complete DSPy Example in Ash

```elixir
# File: docs/dspex_complete_example.md

# Complete DSPy Example in Ash

## Overview

This document provides a complete example of building a RAG (Retrieval-Augmented Generation) system using the Ash-based DSPy implementation.

## Step 1: Define Signatures

```elixir
defmodule Signatures.GenerateSearchQuery do
  use DSPyAsh.Signature, name: "GenerateSearchQuery"
  
  @moduledoc """
  Generate a search query to find information needed to answer a question.
  """
  
  signature do
    input :question, :string, desc: "The question to answer"
    output :query, :string, desc: "Search query to find relevant information"
  end
end

defmodule Signatures.GenerateAnswer do
  use DSPyAsh.Signature, name: "GenerateAnswer"
  
  @moduledoc """
  Answer a question based on retrieved context.
  """
  
  signature do
    input :question, :string, desc: "The question to answer"
    input :context, :string, desc: "Retrieved context passages"
    
    output :reasoning, :string, desc: "Step-by-step reasoning"
    output :answer, :string, desc: "Final answer to the question"
    output :confidence, :float, desc: "Confidence score (0-1)"
  end
end
```

## Step 2: Create RAG Program

```elixir
defmodule Programs.SimplifiedBaleen do
  @moduledoc """
  Simplified Baleen - a multi-hop RAG program
  """
  
  def create(max_hops \\ 2) do
    # Create signatures
    {:ok, search_sig} = Signatures.GenerateSearchQuery.create()
    {:ok, answer_sig} = Signatures.GenerateAnswer.create()
    
    # Create modules
    {:ok, search_module} = DSPyAsh.Modules.Predict.create(search_sig, %{
      temperature: 0.7,
      max_tokens: 100
    })
    
    {:ok, answer_module} = DSPyAsh.Modules.ChainOfThought.create(answer_sig, %{
      temperature: 0.7,
      max_tokens: 1000
    })
    
    # Create program
    {:ok, program} = DSPyAsh.Core.Program.create!(%{
      name: "SimplifiedBaleen",
      description: "Multi-hop retrieval and reasoning"
    })
    
    # Store configuration
    program
    |> Ash.Changeset.for_update(:update, %{
      modules: [
        %{id: search_module.id, name: "generate_query"},
        %{id: answer_module.id, name: "generate_answer"}
      ],
      config: %{max_hops: max_hops}
    })
    |> Ash.update!()
    
    program
  end
  
  def forward(program, inputs) do
    context = multi_hop_search(
      program,
      inputs.question,
      program.config.max_hops
    )
    
    # Generate answer with accumulated context
    answer_module = get_module(program, "generate_answer")
    
    DSPyAsh.Core.Module.forward(answer_module, %{
      question: inputs.question,
      context: context
    })
  end
  
  defp multi_hop_search(program, question, max_hops, context \\ "") do
    if max_hops == 0 do
      context
    else
      # Generate search query
      search_module = get_module(program, "generate_query")
      
      {:ok, search_result} = DSPyAsh.Core.Module.forward(search_module, %{
        question: question,
        context: context
      })
      
      # Retrieve passages (using mock retriever for example)
      passages = retrieve(search_result.query)
      
      # Add to context
      new_context = context <> "\n\n" <> Enum.join(passages, "\n")
      
      # Continue searching
      multi_hop_search(program, question, max_hops - 1, new_context)
    end
  end
  
  defp retrieve(query) do
    # Mock retriever - in practice, integrate with vector DB
    [
      "The Eiffel Tower is located in Paris, France.",
      "Construction of the Eiffel Tower began in 1887.",
      "The tower was designed by Gustave Eiffel."
    ]
  end
  
  defp get_module(program, name) do
    module_ref = Enum.find(program.modules, & &1.name == name)
    DSPyAsh.Core.Module.get!(module_ref.id)
  end
end
```

## Step 3: Prepare Training Data

```elixir
defmodule Data.HotPotQA do
  @moduledoc """
  Load and prepare HotPotQA dataset
  """
  
  def load_trainset(n \\ 20) do
    # In practice, load from file or API
    [
      %{
        question: "What is the capital of the country where the Eiffel Tower is located?",
        answer: "Paris",
        gold_passages: ["The Eiffel Tower is located in Paris, France.", "Paris is the capital of France."]
      },
      %{
        question: "Who designed the tower that was built in 1887 in Paris?",
        answer: "Gustave Eiffel",
        gold_passages: ["Construction of the Eiffel Tower began in 1887.", "The tower was designed by Gustave Eiffel."]
      }
      # ... more examples
    ]
    |> Enum.take(n)
  end
  
  def load_devset(n \\ 50) do
    # Load development set
    load_trainset(n)  # Using same data for example
  end
end
```

## Step 4: Configure LM Provider

```elixir
# Configure OpenAI
{:ok, openai_provider} = DSPyAsh.LM.Provider.create!(%{
  name: "OpenAI GPT-4",
  type: :openai,
  config: %{
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4"
  },
  is_default: true
})

# Or configure Anthropic
{:ok, claude_provider} = DSPyAsh.LM.Provider.create!(%{
  name: "Claude 3",
  type: :anthropic,
  config: %{
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    model: "claude-3-opus-20240229"
  }
})
```

## Step 5: Create and Optimize Program

```elixir
defmodule Workflows.RAGOptimization do
  def run do
    # Create program
    program = Programs.SimplifiedBaleen.create(max_hops: 2)
    
    # Load training data
    trainset = Data.HotPotQA.load_trainset(20)
    
    # Create optimizer
    {:ok, optimizer} = DSPyAsh.Core.Optimizer.create!(%{
      name: "RAG Optimizer",
      type: :bootstrap_fewshot,
      config: %{
        max_bootstrapped_demos: 3,
        max_labeled_demos: 10
      }
    })
    
    # Define metric
    metric = &DSPyAsh.Metrics.exact_match/3
    
    # Compile program
    {:ok, result} = DSPyAsh.Core.Optimizer.compile(
      optimizer,
      program.id,
      trainset,
      "exact_match"
    )
    
    IO.puts("Optimization complete!")
    IO.puts("Training score: #{result.score}")
    
    # The program is now optimized with demonstrations
    result.program
  end
end
```

## Step 6: Evaluate Optimized Program

```elixir
defmodule Workflows.RAGEvaluation do
  def run(program) do
    # Load test data
    devset = Data.HotPotQA.load_devset(50)
    
    # Evaluate
    results = DSPyAsh.Core.Evaluate.evaluate(
      program,
      devset,
      &DSPyAsh.Metrics.exact_match/3
    )
    
    IO.puts("Evaluation Results:")
    IO.puts("Total: #{results.total}")
    IO.puts("Correct: #{results.correct}")
    IO.puts("Accuracy: #{Float.round(results.score * 100, 2)}%")
    
    # Show some examples
    IO.puts("\nExample predictions:")
    
    results.results
    |> Enum.take(3)
    |> Enum.each(fn result ->
      IO.puts("\nQuestion: #{result.example.question}")
      IO.puts("Gold: #{result.example.answer}")
      IO.puts("Predicted: #{result.prediction.answer}")
      IO.puts("Correct: #{result.score >= 1.0}")
    end)
    
    results
  end
end
```

## Step 7: Use in Production

```elixir
defmodule API.QuestionAnswering do
  use Plug.Router
  
  plug :match
  plug :dispatch
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  
  post "/answer" do
    question = conn.body_params["question"]
    
    # Get optimized program
    program = get_optimized_program()
    
    # Execute
    case Programs.SimplifiedBaleen.forward(program, %{question: question}) do
      {:ok, result} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{
          answer: result.answer,
          reasoning: result.reasoning,
          confidence: result.confidence
        }))
        
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{error: reason}))
    end
  end
  
  defp get_optimized_program do
    # Load the latest optimized program
    DSPyAsh.Core.Program
    |> Ash.Query.filter(name == "SimplifiedBaleen")
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.read_one!()
  end
end
```

## Step 8: Monitor and Iterate

```elixir
defmodule Monitoring.ProgramMetrics do
  use GenServer
  
  def track_execution(program_id, execution_time, success) do
    GenServer.cast(__MODULE__, {:track, program_id, execution_time, success})
  end
  
  def get_metrics(program_id) do
    GenServer.call(__MODULE__, {:get_metrics, program_id})
  end
  
  def handle_cast({:track, program_id, execution_time, success}, state) do
    # Update metrics
    metrics = Map.get(state, program_id, %{
      total_executions: 0,
      successful_executions: 0,
      total_time: 0,
      errors: []
    })
    
    updated_metrics = %{
      metrics |
      total_executions: metrics.total_executions + 1,
      successful_executions: metrics.successful_executions + (if success, do: 1, else: 0),
      total_time: metrics.total_time + execution_time
    }
    
    {:noreply, Map.put(state, program_id, updated_metrics)}
  end
  
  def handle_call({:get_metrics, program_id}, _from, state) do
    metrics = Map.get(state, program_id, %{})
    
    avg_time = if metrics[:total_executions] > 0 do
      metrics[:total_time] / metrics[:total_executions]
    else
      0
    end
    
    success_rate = if metrics[:total_executions] > 0 do
      metrics[:successful_executions] / metrics[:total_executions]
    else
      0
    end
    
    {:reply, %{
      total_executions: metrics[:total_executions] || 0,
      success_rate: success_rate,
      average_execution_time: avg_time
    }, state}
  end
end
```

## Complete Workflow Script

```elixir
# scripts/run_rag_example.exs

# 1. Configure LM
IO.puts("Configuring language model...")
{:ok, _provider} = DSPyAsh.LM.Provider.create!(%{
  name: "OpenAI GPT-4",
  type: :openai,
  config: %{
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4"
  },
  is_default: true
})

# 2. Create program
IO.puts("Creating RAG program...")
program = Programs.SimplifiedBaleen.create(max_hops: 2)

# 3. Optimize
IO.puts("Optimizing program...")
optimized = Workflows.RAGOptimization.run()

# 4. Evaluate
IO.puts("Evaluating program...")
results = Workflows.RAGEvaluation.run(optimized)

# 5. Test with example
IO.puts("\nTesting with example question...")
{:ok, answer} = Programs.SimplifiedBaleen.forward(
  optimized,
  %{question: "What year was the Eiffel Tower completed?"}
)

IO.puts("Answer: #{answer.answer}")
IO.puts("Confidence: #{answer.confidence}")
```

## Benefits of Ash-Based DSPy

1. **Persistence**: All programs, modules, and optimizations are persisted
2. **Auditing**: Complete history of all operations with AshPaperTrail
3. **Multi-tenancy**: Built-in support with Ash
4. **APIs**: Automatic GraphQL/REST APIs
5. **Authorization**: Fine-grained access control
6. **Monitoring**: Built-in telemetry and metrics
7. **Scalability**: Leverage Elixir/BEAM for concurrent execution
```

This completes the technical document series for building a DSPy system in Ash. The implementation provides:

1. **Core Architecture** - Resource-based design using Ash domains
2. **Signature System** - Native DSL for defining signatures
3. **Module System** - Implementations of Predict, ChainOfThought, ReAct
4. **LM Integration** - Multi-provider support with caching
5. **Optimizer Implementation** - BootstrapFewShot and MIPRO with Python bridge
6. **Python Bridge** - Seamless integration with original DSPy
7. **Complete Example** - Full RAG implementation showing all components

The system is clean, extensible, and leverages Ash's powerful features while maintaining compatibility with DSPy's core concepts.

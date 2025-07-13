# DSPy-Ash MVP Vision: Native Signatures Meet Production Infrastructure

## Executive Summary

This document outlines the MVP for integrating DSPy with Ash, leveraging our signature innovation to create a production-ready ML infrastructure. The MVP combines:

1. **Native signature syntax** from our signature innovation (1100-1102 docs)
2. **ExDantic integration** for Pydantic-like validation in Elixir
3. **Ash resource architecture** for production ML operations
4. **Python bridge** for initial DSPy compatibility
5. **Automatic API generation** for ML workflow orchestration

## Core Innovation: Native Signatures + Ash Resources

### The Signature Innovation Integration

Our signature syntax from the 1100-1102 docs becomes the foundation for Ash resource definitions:

```elixir
# Native signature syntax (from our innovation)
defmodule QASignature do
  use AshDSPy.Signature
  
  @doc "Answer questions with detailed reasoning"
  signature question: :string, context: :string -> answer: :string, confidence: :float
end

# Automatically becomes an Ash resource
defmodule QAProgram do
  use AshDSPy.Program
  
  signature QASignature
  
  # Ash actions generated automatically
  actions do
    defaults [:read, :create, :update, :destroy]
    
    # ML-specific actions
    action :execute, :map do
      argument :question, :string, allow_nil?: false
      argument :context, :string, allow_nil?: false
      
      run AshDSPy.Actions.ExecuteProgram
    end
    
    action :optimize, :struct do
      argument :dataset, {:array, :map}, allow_nil?: false
      argument :metric, :string, allow_nil?: false
      
      run AshDSPy.Actions.OptimizeProgram
    end
  end
end
```

### ExDantic + Signatures = Perfect Validation

Using ExDantic for runtime validation that matches our signature definitions:

```elixir
defmodule QASignature do
  use AshDSPy.Signature
  
  # Native signature syntax
  signature question: :string, context: :string -> answer: :string, confidence: :float
  
  # ExDantic automatically generates validation schemas
  # This happens at compile time based on signature definition
end

# Usage with automatic validation
{:ok, result} = QAProgram.execute(%{
  question: "What is Elixir?",
  context: "Elixir is a functional programming language..."
})

# ExDantic validates inputs/outputs automatically
# Pydantic-like error messages for ML workflows
```

## MVP Architecture

### 1. Core Domain Structure

```elixir
defmodule MyApp.ML do
  use Ash.Domain, extensions: [AshGraphQL.Domain, AshJsonApi.Domain]
  
  resources do
    resource MyApp.ML.Signature
    resource MyApp.ML.Program
    resource MyApp.ML.Module
    resource MyApp.ML.Execution
    resource MyApp.ML.Dataset
  end
  
  # Automatic GraphQL API for all ML operations
  graphql do
    queries do
      get :get_program, :read
      list :list_programs, :read
      get :get_execution, :read
      list :list_executions, :read
    end
    
    mutations do
      create :create_program, :create
      create :execute_program, :execute
      create :optimize_program, :optimize
    end
    
    subscriptions do
      subscribe :execution_updates do
        actions [:create, :update]
        read_action :read
      end
    end
  end
end
```

### 2. Signature Resource (Foundation)

```elixir
defmodule MyApp.ML.Signature do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshDSPy.Resource]
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :signature_ast, :map, sensitive?: true  # Compiled signature
    attribute :input_schema, :map  # ExDantic schema for inputs
    attribute :output_schema, :map  # ExDantic schema for outputs
    attribute :json_schema, :map  # For LLM integration
    
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    # Compile signature from our native syntax
    action :compile_from_syntax, :struct do
      argument :syntax, :string, allow_nil?: false
      
      run MyApp.ML.Actions.CompileSignature
    end
    
    # Validate data against signature
    action :validate, :map do
      argument :data, :map, allow_nil?: false
      argument :type, :atom, constraints: [one_of: [:input, :output]]
      
      run MyApp.ML.Actions.ValidateSignature
    end
  end
  
  code_interface do
    define :compile_from_syntax
    define :validate
  end
end
```

### 3. Program Resource (Core ML Entity)

```elixir
defmodule MyApp.ML.Program do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshDSPy.DataLayer,  # Custom data layer!
    extensions: [AshStateMachine, AshPaperTrail.Resource]
    
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :version, :integer, default: 1
    attribute :status, :atom, constraints: [
      one_of: [:draft, :training, :optimized, :deployed, :deprecated]
    ], default: :draft
    
    # DSPy-specific attributes
    attribute :modules, {:array, :map}, default: []  # Module configurations
    attribute :compiled_state, :map  # Optimized parameters
    attribute :performance_metrics, :map, default: %{}
    
    timestamps()
  end
  
  relationships do
    belongs_to :signature, MyApp.ML.Signature
    has_many :executions, MyApp.ML.Execution
    has_many :modules, MyApp.ML.Module
    belongs_to :dataset, MyApp.ML.Dataset
  end
  
  # State machine for deployment lifecycle
  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    transitions do
      transition :train, from: :draft, to: :training
      transition :optimize, from: [:draft, :training], to: :optimized
      transition :deploy, from: :optimized, to: :deployed
      transition :deprecate, from: [:optimized, :deployed], to: :deprecated
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    # Core ML operations using custom data layer
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      
      # This will be handled by our custom AshDSPy.DataLayer
      run AshDSPy.Actions.ExecuteProgram
    end
    
    action :optimize, :struct do
      argument :dataset_id, :uuid, allow_nil?: false
      argument :optimizer, :string, default: "BootstrapFewShot"
      argument :metric, :string, default: "exact_match"
      argument :config, :map, default: %{}
      
      # Background job via AshOban
      run AshDSPy.Actions.OptimizeProgram
    end
    
    update :deploy do
      accept []
      require_atomic? false
      change transition_state(:deployed)
      change AshDSPy.Changes.DeployProgram
    end
  end
  
  code_interface do
    define :execute
    define :optimize
    define :deploy
  end
end
```

### 4. Custom Data Layer (The Bridge)

```elixir
defmodule AshDSPy.DataLayer do
  @behaviour Ash.DataLayer
  
  # This is where the magic happens - we bridge Ash with DSPy
  
  @impl true
  def run_query(query, resource, context) do
    case query.action.name do
      :execute ->
        # Use our adapter to execute DSPy programs
        handle_execute(query, resource, context)
        
      :optimize ->
        # Use Python bridge for optimization
        handle_optimize(query, resource, context)
        
      _ ->
        # Delegate to Postgres for standard CRUD
        AshPostgres.DataLayer.run_query(query, resource, context)
    end
  end
  
  defp handle_execute(query, resource, context) do
    program = query.resource_instance
    inputs = get_action_inputs(query)
    
    # Validate inputs using signature + ExDantic
    with {:ok, validated_inputs} <- validate_inputs(program, inputs),
         {:ok, result} <- execute_via_adapter(program, validated_inputs),
         {:ok, validated_outputs} <- validate_outputs(program, result) do
      
      # Create execution record
      execution = create_execution_record(program, inputs, result)
      
      {:ok, [validated_outputs], context}
    end
  end
  
  defp validate_inputs(program, inputs) do
    # Use ExDantic schemas generated from our signature syntax
    signature = get_signature(program)
    Exdantic.TypeAdapter.validate(signature.input_schema, inputs)
  end
  
  defp execute_via_adapter(program, inputs) do
    # Use our adapter pattern to call DSPy
    adapter = Application.get_env(:ash_dspy, :adapter, AshDSPy.Adapters.PythonPort)
    adapter.execute(program.id, inputs)
  end
end
```

### 5. Adapter Pattern (Pluggable Backends)

```elixir
defmodule AshDSPy.Adapter do
  @callback execute(program_id :: String.t(), inputs :: map()) ::
    {:ok, outputs :: map()} | {:error, term()}
    
  @callback optimize(program_id :: String.t(), dataset :: list(), config :: map()) ::
    {:ok, optimized_program :: map()} | {:error, term()}
end

# Python implementation for MVP
defmodule AshDSPy.Adapters.PythonPort do
  @behaviour AshDSPy.Adapter
  
  # Uses Erlang ports to communicate with Python DSPy
  @impl true
  def execute(program_id, inputs) do
    AshDSPy.PythonBridge.call(:execute, %{
      program_id: program_id,
      inputs: inputs
    })
  end
  
  @impl true
  def optimize(program_id, dataset, config) do
    AshDSPy.PythonBridge.call(:optimize, %{
      program_id: program_id,
      dataset: dataset,
      optimizer: config[:optimizer] || "BootstrapFewShot",
      config: config
    })
  end
end

# Future native implementation
defmodule AshDSPy.Adapters.Native do
  @behaviour AshDSPy.Adapter
  
  # Pure Elixir implementation (future)
  @impl true
  def execute(program_id, inputs) do
    {:error, :not_implemented}
  end
end
```

### 6. Python Bridge (Port-Based Communication)

```elixir
defmodule AshDSPy.PythonBridge do
  use GenServer
  
  # Port-based communication with Python DSPy
  # Similar to the design from DSPY_ADAPTER_LAYER_ARCHITECTURE.md
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def call(command, args, timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:call, command, args}, timeout)
  end
  
  @impl true
  def init(_opts) do
    python_script = Path.join(:code.priv_dir(:ash_dspy), "python/dspy_bridge.py")
    
    port = Port.open({:spawn_executable, python_executable()}, [
      {:args, [python_script]},
      {:packet, 4},
      :binary,
      :exit_status
    ])
    
    {:ok, %{port: port, requests: %{}, request_id: 0}}
  end
  
  # Handle requests/responses with Python DSPy
  # Implementation similar to DSPY_ADAPTER_LAYER_ARCHITECTURE.md
end
```

## Integration with Our Signature Innovation

### 1. Signature Compilation Process

```elixir
# Step 1: Define signature with our native syntax
defmodule QASignature do
  use AshDSPy.Signature
  
  # Beautiful native syntax from our innovation
  signature question: :string, context: :string -> answer: :string, confidence: :float
end

# Step 2: Compile-time processing
defmodule AshDSPy.Signature.Compiler do
  def __before_compile__(env) do
    signature_ast = Module.get_attribute(env.module, :signature_ast)
    
    # Generate ExDantic schemas
    input_schema = compile_exdantic_schema(signature_ast.inputs)
    output_schema = compile_exdantic_schema(signature_ast.outputs)
    
    # Generate JSON schema for LLMs
    json_schema = compile_json_schema(signature_ast)
    
    # Store compiled artifacts
    quote do
      def input_schema, do: unquote(Macro.escape(input_schema))
      def output_schema, do: unquote(Macro.escape(output_schema))
      def json_schema, do: unquote(Macro.escape(json_schema))
      
      # Integration with Ash
      def create_ash_signature! do
        MyApp.ML.Signature.create!(%{
          name: to_string(__MODULE__),
          signature_ast: unquote(Macro.escape(signature_ast)),
          input_schema: input_schema(),
          output_schema: output_schema(),
          json_schema: json_schema()
        })
      end
    end
  end
end
```

### 2. ExDantic Integration for Validation

```elixir
# ExDantic schemas generated from our signature syntax
defmodule AshDSPy.Signature.ExDanticCompiler do
  def compile_schema(fields) do
    Enum.map(fields, fn {name, type, constraints} ->
      {name, convert_type(type), convert_constraints(constraints)}
    end)
  end
  
  defp convert_type(:string), do: :string
  defp convert_type(:float), do: :float
  defp convert_type({:list, inner}), do: {:array, convert_type(inner)}
  defp convert_type({:dict, k, v}), do: {:map, {convert_type(k), convert_type(v)}}
  
  # Runtime validation using ExDantic
  def validate_with_schema(data, schema) do
    # Create runtime ExDantic schema
    exdantic_schema = Exdantic.Runtime.create_schema(schema)
    
    # Validate with Pydantic-like behavior
    Exdantic.EnhancedValidator.validate(exdantic_schema, data, 
      config: Exdantic.Config.create(coercion: :safe, strict: true)
    )
  end
end
```

### 3. Automatic API Generation

```elixir
# GraphQL API automatically generated from our signature
"""
type QAProgram {
  id: ID!
  name: String!
  status: ProgramStatus!
  signature: Signature!
  executions: [Execution!]!
}

type Mutation {
  executeProgram(input: ExecuteProgramInput!): ExecuteProgramResult!
  optimizeProgram(input: OptimizeProgramInput!): OptimizeProgramResult!
}

input ExecuteProgramInput {
  programId: ID!
  question: String!      # From our signature definition
  context: String!       # From our signature definition
}

type ExecuteProgramResult {
  answer: String!        # From our signature definition
  confidence: Float!     # From our signature definition
  executionId: ID!
  metrics: ExecutionMetrics
}
"""
```

## MVP Implementation Plan

### Phase 1: Foundation (Weeks 1-2)
1. **AshDSPy.Signature resource** with native syntax compilation
2. **ExDantic integration** for validation schemas
3. **Basic Python bridge** with port communication
4. **Program resource** with simple execute action

### Phase 2: Core Operations (Weeks 3-4)
1. **AshDSPy.DataLayer** custom data layer implementation
2. **Adapter pattern** with Python port adapter
3. **Execution tracking** and metrics collection
4. **Basic optimization** via Python bridge

### Phase 3: Production Features (Weeks 5-6)
1. **GraphQL API** generation for ML operations
2. **AshOban integration** for background jobs
3. **State machine** for program lifecycle
4. **Performance monitoring** and observability

### Phase 4: Advanced Features (Weeks 7-8)
1. **Dataset management** resource
2. **Advanced optimization** algorithms
3. **Real-time subscriptions** for long-running jobs
4. **Deployment automation** and versioning

## Example Usage Scenarios

### 1. Simple Q&A Program

```elixir
# Define signature
defmodule QASignature do
  use AshDSPy.Signature
  signature question: :string -> answer: :string, confidence: :float
end

# Create program
{:ok, program} = MyApp.ML.Program.create!(%{
  name: "Simple QA",
  signature_id: QASignature.create_ash_signature!().id
})

# Execute
{:ok, result} = MyApp.ML.Program.execute(program, %{
  question: "What is Elixir?"
})

# Result: %{answer: "Elixir is a functional...", confidence: 0.87}
```

### 2. Complex RAG Pipeline

```elixir
# Multi-step signature
defmodule RAGSignature do
  use AshDSPy.Signature
  
  signature query: :string, 
           documents: list[:string] ->
    answer: :string,
    sources: list[:string],
    confidence: :float
end

# Optimize with dataset
{:ok, dataset} = MyApp.ML.Dataset.create!(%{
  name: "QA Dataset",
  data: load_training_data()
})

{:ok, optimized} = MyApp.ML.Program.optimize(program, %{
  dataset_id: dataset.id,
  optimizer: "BootstrapFewShot",
  metric: "exact_match"
})
```

### 3. GraphQL API Usage

```graphql
mutation ExecuteProgram($input: ExecuteProgramInput!) {
  executeProgram(input: $input) {
    answer
    confidence
    executionId
    metrics {
      latencyMs
      tokenUsage
    }
  }
}
```

## Benefits of This Approach

### 1. Native Developer Experience
- **Beautiful syntax** from our signature innovation
- **Full IDE support** with autocompletion and error checking
- **Type safety** throughout the ML pipeline

### 2. Production Ready
- **Ash ecosystem integration** (GraphQL, REST, Admin UI)
- **Observability** built-in (metrics, tracing, audit logs)
- **Scalability** via BEAM concurrency model

### 3. ML-First Design
- **Automatic validation** using ExDantic
- **Experiment tracking** via resource relationships
- **Version management** with AshPaperTrail

### 4. Flexible Architecture
- **Adapter pattern** allows switching between Python and native
- **Extensible** via Ash extensions and custom actions
- **API-first** with automatic GraphQL/REST generation

## Conclusion

This MVP combines the best of our signature innovation with Ash's production infrastructure to create a truly unique ML framework. We get:

- **Beautiful native syntax** that eliminates ceremony
- **Production-ready infrastructure** via Ash ecosystem
- **Automatic API generation** for ML operations
- **Type-safe validation** using ExDantic
- **Flexible architecture** supporting both Python and native implementations

The result is a DSPy implementation that's more elegant than Python while being more powerful and production-ready than any existing ML framework in Elixir.

*Ready to revolutionize ML infrastructure in the BEAM ecosystem.*
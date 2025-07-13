# Ash-DSPy Integration Architecture

## Executive Summary

This document proposes a novel approach to integrating DSPy with Elixir by leveraging the Ash framework ecosystem. Rather than building a traditional ports-based bridge, we model DSPy concepts as Ash resources, creating a production-ready, observable, and highly composable ML infrastructure.

## Core Concept: DSPy as an Ash Domain

Instead of treating DSPy as an external service, we model it as a domain within Ash, with resources representing:
- Programs
- Modules (Predictors, Retrievers, etc.)
- Signatures
- Executions
- Optimizations
- Datasets
- Metrics

This transforms ML pipelines from opaque Python processes into traceable, queryable, and manageable business entities.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Ash Application Layer                      │
├─────────────────────────────────────────────────────────────┤
│  AshGraphQL  │  AshJsonApi  │  AshPhoenix  │  AshAdmin     │
├─────────────────────────────────────────────────────────────┤
│                      DSPy Domain                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Program   │  │   Module    │  │  Signature  │         │
│  │  Resource   │  │  Resource   │  │  Resource   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Execution  │  │Optimization │  │   Dataset   │         │
│  │  Resource   │  │  Resource   │  │  Resource   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
├─────────────────────────────────────────────────────────────┤
│              DSPy Data Layer (Custom)                         │
│  ┌─────────────────────────────────────────────┐            │
│  │          Python Process Manager              │            │
│  │    (Port + State Management + Caching)      │            │
│  └─────────────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────┤
│              Supporting Infrastructure                        │
│  AshPostgres │ AshOban │ AshPaperTrail │ AshStateMachine   │
└─────────────────────────────────────────────────────────────┘
```

## Key Resources

### 1. Program Resource

```elixir
defmodule MyApp.ML.Program do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :version, :integer, default: 1
    attribute :status, :atom, constraints: [one_of: [:draft, :testing, :production]]
    attribute :config, :map
    attribute :metrics, :map
    timestamps()
  end

  relationships do
    has_many :modules, MyApp.ML.Module
    has_many :executions, MyApp.ML.Execution
    has_many :optimizations, MyApp.ML.Optimization
    belongs_to :compiled_from, MyApp.ML.Optimization
  end

  actions do
    defaults [:read, :destroy]
    
    create :create do
      primary? true
      accept [:name, :description, :config]
    end
    
    update :deploy do
      accept []
      change set_attribute(:status, :production)
      change MyApp.ML.Changes.DeployToProduction
    end
    
    action :execute, :map do
      argument :input, :map, allow_nil?: false
      run MyApp.ML.Actions.ExecuteProgram
    end
    
    action :compile, :struct do
      constraints instance_of: MyApp.ML.Optimization
      argument :dataset_id, :uuid, allow_nil?: false
      argument :metric, :string, allow_nil?: false
      argument :optimizer, :map, allow_nil?: false
      run MyApp.ML.Actions.CompileProgram
    end
  end

  code_interface do
    define :execute
    define :compile
  end
end
```

### 2. Module Resource

```elixir
defmodule MyApp.ML.Module do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :type, :atom, constraints: [
      one_of: [:predict, :chain_of_thought, :retrieve, :react, :custom]
    ]
    attribute :signature, :string
    attribute :config, :map
    attribute :position, :integer
  end

  relationships do
    belongs_to :program, MyApp.ML.Program
    has_many :connections, MyApp.ML.ModuleConnection, 
      destination_attribute: :from_module_id
  end
end
```

### 3. Execution Resource

```elixir
defmodule MyApp.ML.Execution do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  attributes do
    uuid_primary_key :id
    attribute :input, :map, allow_nil?: false
    attribute :output, :map
    attribute :trace, :map
    attribute :duration_ms, :integer
    attribute :token_usage, :map
    attribute :error, :string
    timestamps()
  end

  relationships do
    belongs_to :program, MyApp.ML.Program
    belongs_to :user, MyApp.Accounts.User
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: :pending, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: :running, to: :failed
    end
  end

  actions do
    defaults [:read]
    
    create :create do
      accept [:input]
      argument :program_id, :uuid, allow_nil?: false
      
      change relate_actor(:user)
      change set_attribute(:state, :pending)
      change MyApp.ML.Changes.EnqueueExecution
    end
    
    update :start do
      accept []
      require_atomic? false
      change transition_state(:running)
    end
    
    update :complete do
      accept [:output, :trace, :duration_ms, :token_usage]
      require_atomic? false
      change transition_state(:completed)
    end
    
    update :fail do
      accept [:error]
      require_atomic? false  
      change transition_state(:failed)
    end
  end
end
```

### 4. Dataset Resource

```elixir
defmodule MyApp.ML.Dataset do
  use Ash.Resource,
    domain: MyApp.ML,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :type, :atom, constraints: [one_of: [:training, :validation, :test]]
    attribute :data, {:array, :map}
    attribute :size, :integer
    attribute :schema, :map
    timestamps()
  end

  relationships do
    has_many :optimizations, MyApp.ML.Optimization
  end

  calculations do
    calculate :statistics, :map, MyApp.ML.Calculations.DatasetStatistics
  end
end
```

## Custom Data Layer

The custom data layer handles the Python bridge:

```elixir
defmodule MyApp.ML.DataLayer do
  @behaviour Ash.DataLayer

  defmodule PythonBridge do
    use GenServer
    
    # Manages a pool of Python processes
    # Handles state persistence between calls
    # Implements smart caching for embeddings
    # Manages lifecycle of compiled programs
  end

  # Translates Ash queries to Python operations
  def run_query(query, resource, parent) do
    case query.action.type do
      :read -> handle_read(query, resource)
      :create -> handle_create(query, resource)
      :update -> handle_update(query, resource)
      :destroy -> handle_destroy(query, resource)
      {:action, _} -> handle_action(query, resource)
    end
  end
end
```

## Integration with Ash Ecosystem

### 1. AshOban for Background Jobs

```elixir
defmodule MyApp.ML.Workers.ExecuteProgramWorker do
  use Oban.Worker, queue: :ml_inference, max_attempts: 3

  @impl true
  def perform(%Job{args: %{"execution_id" => execution_id}}) do
    execution = MyApp.ML.get!(Execution, execution_id)
    
    # Start execution
    {:ok, execution} = MyApp.ML.start(execution)
    
    # Run through Python bridge
    result = MyApp.ML.DataLayer.PythonBridge.execute(
      execution.program_id,
      execution.input
    )
    
    # Complete or fail
    case result do
      {:ok, output} ->
        MyApp.ML.complete(execution, %{
          output: output.result,
          trace: output.trace,
          duration_ms: output.duration,
          token_usage: output.token_usage
        })
      
      {:error, reason} ->
        MyApp.ML.fail(execution, %{error: reason})
    end
  end
end
```

### 2. AshGraphQL for API

```elixir
defmodule MyApp.ML do
  use Ash.Domain, extensions: [AshGraphQL.Domain]

  graphql do
    queries do
      get :get_program, :read
      list :list_programs, :read
      
      get :get_execution, :read
      list :list_executions, :read
    end

    mutations do
      create :create_program, :create
      update :deploy_program, :deploy
      
      create :execute_program, :execute
      create :compile_program, :compile
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

### 3. AshAuthentication for Security

```elixir
policies do
  policy action_type(:read) do
    authorize_if actor_attribute_equals(:role, :admin)
    authorize_if expr(user_id == ^actor(:id))
  end
  
  policy action(:execute) do
    authorize_if actor_attribute_equals(:role, [:admin, :ml_user])
    authorize_if expr(
      program.status == :production and 
      actor.ml_credits > 0
    )
  end
  
  policy action(:compile) do
    authorize_if actor_attribute_equals(:role, :ml_engineer)
  end
end
```

### 4. AshPaperTrail for Audit

```elixir
defmodule MyApp.ML.Program do
  use Ash.Resource,
    extensions: [AshPaperTrail.Resource]
    
  paper_trail do
    attributes_as_attributes [:name, :config, :status]
    change_tracking_mode :changes_only
  end
end
```

## Advanced Features

### 1. Prompt Versioning & A/B Testing

```elixir
defmodule MyApp.ML.PromptVersion do
  use Ash.Resource,
    domain: MyApp.ML
    
  attributes do
    uuid_primary_key :id
    attribute :version, :string
    attribute :prompt_template, :string
    attribute :performance_metrics, :map
    attribute :traffic_percentage, :decimal
  end
  
  relationships do
    belongs_to :module, MyApp.ML.Module
  end
end
```

### 2. Cost Tracking

```elixir
defmodule MyApp.ML.Calculations.MonthlyCost do
  use Ash.Resource.Calculation
  
  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      executions = MyApp.ML.list!(Execution, 
        filter: [
          program_id: record.id,
          inserted_at: [greater_than: thirty_days_ago()]
        ]
      )
      
      total_tokens = Enum.sum_by(executions, & &1.token_usage["total"])
      total_tokens * token_price()
    end)
  end
end
```

### 3. Smart Caching with AshCachex

```elixir
defmodule MyApp.ML.Cache do
  use AshCachex,
    otp_app: :my_app,
    adapter: AshCachex.Adapter.Cachex
    
  cache :embedding_cache do
    ttl :timer.hours(24)
    limit 10_000
  end
  
  cache :prediction_cache do
    ttl :timer.minutes(10)
    key_generator &generate_prediction_key/1
  end
end
```

## Implementation Phases

### Phase 1: Core Infrastructure
- Basic Python bridge with port management
- Program, Module, and Execution resources
- Simple execute action

### Phase 2: Optimization & Training
- Dataset resource and management
- Optimization workflows with AshOban
- Metrics and evaluation

### Phase 3: Production Features
- AshStateMachine for execution states
- Cost tracking and limits
- Caching layer
- A/B testing infrastructure

### Phase 4: Advanced Integrations
- AshAI integration for embeddings
- Multi-model orchestration
- Real-time monitoring with AshAppsignal
- Advanced authorization policies

## Benefits of This Approach

1. **Production-Ready**: Built-in monitoring, error handling, and scaling
2. **Observable**: Every execution is tracked, queryable, and auditable
3. **Secure**: Fine-grained authorization at every level
4. **Composable**: Mix ML with business logic seamlessly
5. **API-First**: Instant GraphQL/REST APIs for all ML operations
6. **Maintainable**: Clear separation of concerns, testable components
7. **Extensible**: Easy to add new module types, metrics, or optimizers

## Conclusion

By modeling DSPy as an Ash domain, we transform ML operations from black-box processes into first-class business entities. This approach provides unprecedented visibility, control, and integration capabilities while maintaining the power and flexibility of DSPy's core abstractions.

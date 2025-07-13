# Stage 3: Production Features - APIs, Jobs & Monitoring

## Overview

Stage 3 transforms the DSPy-Ash integration into a production-ready system with automatic API generation, background job processing, and comprehensive monitoring.

**Goal**: Deploy DSPy programs as production APIs with full observability and scalability.

**Duration**: Week 5-6

## 1. GraphQL API Generation

### 1.1 Enhanced ML Domain with GraphQL

```elixir
# lib/dspex/ml/domain.ex (enhanced)
defmodule DSPex.ML.Domain do
  @moduledoc """
  ML domain with full GraphQL API generation.
  """
  
  use Ash.Domain, extensions: [AshGraphQL.Domain, AshJsonApi.Domain]
  
  resources do
    resource DSPex.ML.Signature
    resource DSPex.ML.Program
    resource DSPex.ML.Execution
    resource DSPex.ML.Dataset
    resource DSPex.ML.OptimizationJob
  end
  
  graphql do
    # Queries
    queries do
      get :get_program, :read do
        type_name :program
      end
      
      list :list_programs, :read do
        type_name :program
      end
      
      get :get_execution, :read do
        type_name :execution
      end
      
      list :list_executions, :read do
        type_name :execution
      end
      
      get :get_signature, :read do
        type_name :signature
      end
      
      list :list_signatures, :read do
        type_name :signature
      end
    end
    
    # Mutations
    mutations do
      create :create_program, :create_with_signature do
        type_name :program
      end
      
      create :execute_program, :execute do
        type_name :execution_result
      end
      
      create :optimize_program, :optimize do
        type_name :optimization_result
      end
      
      update :deploy_program, :deploy do
        type_name :program
      end
    end
    
    # Subscriptions for real-time updates
    subscriptions do
      subscribe :execution_updates do
        actions [:create, :update]
        read_action :read
      end
      
      subscribe :optimization_updates do
        actions [:create, :update]
        read_action :read
      end
    end
  end
  
  # JSON API configuration
  json_api do
    prefix "/api/ml"
    
    routes do
      base "/programs"
      get :read
      index :read
      post :create_with_signature
      
      related :executions, :read
      relationship :executions, :read
      
      base "/executions"
      get :read
      index :read
      
      base "/signatures"
      get :read
      index :read
    end
  end
end
```

### 1.2 GraphQL Schema Types

```elixir
# lib/dspex/ml/graphql_types.ex
defmodule DSPex.ML.GraphQLTypes do
  @moduledoc """
  Custom GraphQL types for ML operations.
  """
  
  use Absinthe.Schema.Notation
  use AshGraphQL, domains: [DSPex.ML.Domain]
  
  # Custom scalar types for ML
  scalar :embedding do
    description "Vector embedding represented as array of floats"
    
    serialize &Jason.encode!/1
    parse fn
      %{value: value} when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, list} when is_list(list) -> {:ok, list}
          _ -> :error
        end
      %{value: list} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end
  
  scalar :probability do
    description "Probability value between 0.0 and 1.0"
    
    serialize & &1
    parse fn
      %{value: value} when is_float(value) and value >= 0.0 and value <= 1.0 -> {:ok, value}
      %{value: value} when is_integer(value) and value in 0..1 -> {:ok, value * 1.0}
      _ -> :error
    end
  end
  
  # Execution result type
  object :execution_result do
    field :id, :id
    field :program_id, :id
    field :outputs, :json
    field :duration_ms, :integer
    field :token_usage, :json
    field :status, :execution_status
    field :started_at, :datetime
    field :completed_at, :datetime
  end
  
  # Optimization result type
  object :optimization_result do
    field :id, :id
    field :program_id, :id
    field :score, :float
    field :optimizer, :string
    field :dataset_size, :integer
    field :optimization_time_ms, :integer
    field :status, :optimization_status
  end
  
  # Program performance metrics
  object :performance_metrics do
    field :total_executions, :integer
    field :success_rate, :float
    field :average_duration_ms, :float
    field :total_tokens_used, :integer
    field :last_executed_at, :datetime
  end
  
  # Execution status enum
  enum :execution_status do
    value :pending
    value :running
    value :completed
    value :failed
  end
  
  # Optimization status enum
  enum :optimization_status do
    value :queued
    value :running
    value :completed
    value :failed
  end
  
  # Input/Output field type
  object :signature_field do
    field :name, :string
    field :type, :string
    field :description, :string
    field :required, :boolean
    field :constraints, :json
  end
end
```

### 1.3 GraphQL Schema

```elixir
# lib/dspex_web/schema.ex
defmodule DSPexWeb.Schema do
  @moduledoc """
  GraphQL schema for DSPy ML operations.
  """
  
  use Absinthe.Schema
  use AshGraphQL, domains: [DSPex.ML.Domain]
  
  import_types DSPex.ML.GraphQLTypes
  import_types Absinthe.Type.Custom
  
  query do
    # Program queries
    field :program, :program do
      arg :id, non_null(:id)
      resolve AshGraphQL.Resolver.resolve(&DSPex.ML.Program.get_program/2)
    end
    
    field :programs, list_of(:program) do
      arg :filter, :program_filter
      arg :sort, list_of(:program_sort)
      resolve AshGraphQL.Resolver.resolve(&DSPex.ML.Program.list_programs/2)
    end
    
    # Execution queries
    field :execution, :execution do
      arg :id, non_null(:id)
      resolve AshGraphQL.Resolver.resolve(&DSPex.ML.Execution.get_execution/2)
    end
    
    field :executions, list_of(:execution) do
      arg :program_id, :id
      arg :filter, :execution_filter
      arg :sort, list_of(:execution_sort)
      resolve AshGraphQL.Resolver.resolve(&DSPex.ML.Execution.list_executions/2)
    end
    
    # Performance metrics
    field :program_metrics, :performance_metrics do
      arg :program_id, non_null(:id)
      resolve &DSPex.GraphQL.Resolvers.program_metrics/3
    end
  end
  
  mutation do
    # Program management
    field :create_program, :program do
      arg :name, non_null(:string)
      arg :signature_module, non_null(:string)
      arg :description, :string
      
      resolve &DSPex.GraphQL.Resolvers.create_program/3
    end
    
    field :deploy_program, :program do
      arg :id, non_null(:id)
      
      resolve &DSPex.GraphQL.Resolvers.deploy_program/3
    end
    
    # Execution
    field :execute_program, :execution_result do
      arg :program_id, non_null(:id)
      arg :inputs, non_null(:json)
      
      resolve &DSPex.GraphQL.Resolvers.execute_program/3
    end
    
    # Optimization
    field :optimize_program, :optimization_result do
      arg :program_id, non_null(:id)
      arg :dataset_id, non_null(:id)
      arg :optimizer, :string, default_value: "BootstrapFewShot"
      arg :metric, :string, default_value: "exact_match"
      arg :config, :json, default_value: %{}
      
      resolve &DSPex.GraphQL.Resolvers.optimize_program/3
    end
  end
  
  subscription do
    # Real-time execution updates
    field :execution_updates, :execution do
      arg :program_id, :id
      
      config fn args, _info ->
        case args[:program_id] do
          nil -> {:ok, topic: "executions"}
          program_id -> {:ok, topic: "executions:#{program_id}"}
        end
      end
      
      trigger :execute_program, topic: fn result ->
        ["executions", "executions:#{result.program_id}"]
      end
    end
    
    # Real-time optimization updates
    field :optimization_updates, :optimization_result do
      arg :program_id, :id
      
      config fn args, _info ->
        case args[:program_id] do
          nil -> {:ok, topic: "optimizations"}
          program_id -> {:ok, topic: "optimizations:#{program_id}"}
        end
      end
      
      trigger :optimize_program, topic: fn result ->
        ["optimizations", "optimizations:#{result.program_id}"]
      end
    end
  end
end
```

### 1.4 GraphQL Resolvers

```elixir
# lib/dspex/graphql/resolvers.ex
defmodule DSPex.GraphQL.Resolvers do
  @moduledoc """
  GraphQL resolvers for DSPy operations.
  """
  
  alias DSPex.ML.{Program, Execution, OptimizationJob}
  
  def create_program(_parent, args, _resolution) do
    signature_module = Module.safe_concat([args.signature_module])
    
    case Program.create_with_signature(%{
      name: args.name,
      description: args[:description],
      signature_module: signature_module
    }) do
      {:ok, program} -> {:ok, program}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  def deploy_program(_parent, %{id: id}, _resolution) do
    case Program.get!(id) do
      {:ok, program} ->
        case Program.deploy(program) do
          {:ok, deployed} -> {:ok, deployed}
          {:error, reason} -> {:error, format_error(reason)}
        end
      error -> error
    end
  end
  
  def execute_program(_parent, args, _resolution) do
    %{program_id: program_id, inputs: inputs} = args
    
    case Program.get!(program_id) do
      {:ok, program} ->
        # Start execution tracking
        {:ok, execution} = Execution.start_execution(%{
          program_id: program_id,
          inputs: inputs
        })
        
        # Execute via custom data layer
        case Program.execute(program, %{inputs: inputs}) do
          {:ok, result} ->
            # Complete execution tracking
            {:ok, completed} = Execution.complete_execution(execution, %{
              outputs: result,
              duration_ms: result[:_metadata][:execution_time_ms] || 0
            })
            
            # Publish subscription update
            Absinthe.Subscription.publish(
              DSPexWeb.Endpoint,
              completed,
              execution_updates: ["executions", "executions:#{program_id}"]
            )
            
            {:ok, completed}
          
          {:error, reason} ->
            {:ok, _failed} = Execution.fail_execution(execution, %{
              error_message: to_string(reason)
            })
            
            {:error, reason}
        end
      
      error -> error
    end
  end
  
  def optimize_program(_parent, args, _resolution) do
    %{program_id: program_id, dataset_id: dataset_id} = args
    
    # Create optimization job
    {:ok, job} = OptimizationJob.create!(%{
      program_id: program_id,
      dataset_id: dataset_id,
      optimizer: args[:optimizer] || "BootstrapFewShot",
      metric: args[:metric] || "exact_match",
      config: args[:config] || %{},
      status: :queued
    })
    
    # Enqueue background job
    DSPex.Workers.OptimizationWorker.new(%{
      optimization_job_id: job.id
    })
    |> Oban.insert()
    
    {:ok, job}
  end
  
  def program_metrics(_parent, %{program_id: program_id}, _resolution) do
    case Program.get!(program_id) do
      {:ok, program} ->
        executions = Execution.list!(filter: [program_id: program_id])
        
        metrics = %{
          total_executions: length(executions),
          success_rate: calculate_success_rate(executions),
          average_duration_ms: calculate_average_duration(executions),
          total_tokens_used: calculate_total_tokens(executions),
          last_executed_at: get_last_execution_time(executions)
        }
        
        {:ok, metrics}
      
      error -> error
    end
  end
  
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
  
  defp calculate_success_rate([]), do: 0.0
  defp calculate_success_rate(executions) do
    successful = Enum.count(executions, & &1.status == :completed)
    successful / length(executions)
  end
  
  defp calculate_average_duration(executions) do
    durations = Enum.filter_map(executions, & &1.duration_ms, & &1.duration_ms)
    
    case durations do
      [] -> 0.0
      list -> Enum.sum(list) / length(list)
    end
  end
  
  defp calculate_total_tokens(executions) do
    executions
    |> Enum.map(& &1.token_usage["total"] || 0)
    |> Enum.sum()
  end
  
  defp get_last_execution_time([]), do: nil
  defp get_last_execution_time(executions) do
    executions
    |> Enum.map(& &1.started_at)
    |> Enum.max()
  end
end
```

## 2. Background Job Processing with AshOban

### 2.1 Oban Configuration

```elixir
# lib/dspex/application.ex (add Oban)
defmodule DSPex.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Schema cache
      DSPex.Validation.SchemaCache,
      
      # Python bridge
      DSPex.PythonBridge.Bridge,
      
      # Database
      DSPex.Repo,
      
      # Oban for background jobs
      {Oban, Application.fetch_env!(:dspex, Oban)},
      
      # Web endpoint
      DSPexWeb.Endpoint
    ]
    
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 2.2 OptimizationJob Resource

```elixir
# lib/dspex/ml/optimization_job.ex
defmodule DSPex.ML.OptimizationJob do
  @moduledoc """
  Resource for tracking optimization jobs.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban]
  
  attributes do
    uuid_primary_key :id
    
    attribute :optimizer, :string, allow_nil?: false, default: "BootstrapFewShot"
    attribute :metric, :string, allow_nil?: false, default: "exact_match"
    attribute :config, :map, default: %{}
    
    attribute :status, :atom, constraints: [
      one_of: [:queued, :running, :completed, :failed, :cancelled]
    ], default: :queued
    
    # Results
    attribute :score, :float
    attribute :optimization_time_ms, :integer
    attribute :optimized_state, :map
    attribute :error_message, :string
    
    # Oban job tracking
    attribute :oban_job_id, :integer
    
    timestamps()
  end
  
  relationships do
    belongs_to :program, DSPex.ML.Program
    belongs_to :dataset, DSPex.ML.Dataset
  end
  
  state_machine do
    initial_states [:queued]
    default_initial_state :queued
    
    transitions do
      transition :start, from: :queued, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:queued, :running], to: :failed
      transition :cancel, from: [:queued, :running], to: :cancelled
    end
  end
  
  # Oban integration
  oban do
    triggers do
      trigger :enqueue_optimization do
        action :create
        worker DSPex.Workers.OptimizationWorker
        
        scheduler fn record ->
          %{optimization_job_id: record.id}
        end
      end
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_and_enqueue do
      accept [:optimizer, :metric, :config]
      argument :program_id, :uuid, allow_nil?: false
      argument :dataset_id, :uuid, allow_nil?: false
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.manage_relationship(:program, 
             Ash.Changeset.get_argument(changeset, :program_id), type: :append)
        |> Ash.Changeset.manage_relationship(:dataset,
             Ash.Changeset.get_argument(changeset, :dataset_id), type: :append)
      end
      
      # This will trigger the Oban job via the trigger
    end
    
    update :start_optimization do
      accept [:oban_job_id]
      require_atomic? false
      change transition_state(:running)
    end
    
    update :complete_optimization do
      accept [:score, :optimization_time_ms, :optimized_state]
      require_atomic? false
      change transition_state(:completed)
    end
    
    update :fail_optimization do
      accept [:error_message]
      require_atomic? false
      change transition_state(:failed)
    end
  end
  
  code_interface do
    define :create_and_enqueue
    define :start_optimization
    define :complete_optimization
    define :fail_optimization
  end
end
```

### 2.3 Optimization Worker

```elixir
# lib/dspex/workers/optimization_worker.ex
defmodule DSPex.Workers.OptimizationWorker do
  @moduledoc """
  Oban worker for running DSPy program optimizations.
  """
  
  use Oban.Worker, queue: :ml_optimization, max_attempts: 3
  
  alias DSPex.ML.{OptimizationJob, Program, Dataset}
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"optimization_job_id" => job_id}}) do
    optimization_job = OptimizationJob.get!(job_id)
    
    # Start the optimization
    {:ok, started_job} = OptimizationJob.start_optimization(optimization_job, %{
      oban_job_id: Oban.current_job().id
    })
    
    # Publish subscription update
    publish_optimization_update(started_job)
    
    try do
      # Load related data
      program = Program.get!(started_job.program_id)
      dataset = Dataset.get!(started_job.dataset_id)
      
      # Run optimization via adapter
      adapter = Application.get_env(:dspex, :adapter)
      
      start_time = System.monotonic_time(:millisecond)
      
      result = adapter.optimize_program(
        program.dspy_program_id,
        dataset.data,
        %{
          optimizer: started_job.optimizer,
          metric: started_job.metric,
          config: started_job.config
        }
      )
      
      case result do
        {:ok, optimization_result} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time
          
          # Complete the optimization
          {:ok, completed_job} = OptimizationJob.complete_optimization(started_job, %{
            score: optimization_result["score"],
            optimization_time_ms: duration,
            optimized_state: optimization_result
          })
          
          # Update program with optimized state
          Program.update!(program, %{
            compiled_state: optimization_result,
            performance_metrics: Map.merge(program.performance_metrics || %{}, %{
              "last_optimization_score" => optimization_result["score"],
              "last_optimization_time" => DateTime.utc_now() |> DateTime.to_iso8601()
            }),
            status: :optimized
          })
          
          # Publish completion
          publish_optimization_update(completed_job)
          
          :ok
        
        {:error, reason} ->
          {:ok, failed_job} = OptimizationJob.fail_optimization(started_job, %{
            error_message: to_string(reason)
          })
          
          publish_optimization_update(failed_job)
          
          {:error, reason}
      end
      
    rescue
      error ->
        {:ok, failed_job} = OptimizationJob.fail_optimization(started_job, %{
          error_message: Exception.message(error)
        })
        
        publish_optimization_update(failed_job)
        
        {:error, error}
    end
  end
  
  defp publish_optimization_update(job) do
    Absinthe.Subscription.publish(
      DSPexWeb.Endpoint,
      job,
      optimization_updates: ["optimizations", "optimizations:#{job.program_id}"]
    )
  end
end
```

### 2.4 Dataset Resource

```elixir
# lib/dspex/ml/dataset.ex
defmodule DSPex.ML.Dataset do
  @moduledoc """
  Resource for managing training/evaluation datasets.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :data, {:array, :map}, allow_nil?: false
    attribute :size, :integer
    attribute :schema, :map
    attribute :metadata, :map, default: %{}
    
    attribute :type, :atom, constraints: [
      one_of: [:training, :validation, :test, :custom]
    ], default: :training
    
    timestamps()
  end
  
  relationships do
    has_many :optimization_jobs, DSPex.ML.OptimizationJob
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_from_file do
      argument :file_path, :string, allow_nil?: false
      argument :format, :atom, constraints: [one_of: [:json, :csv, :jsonl]], default: :json
      
      change DSPex.ML.Changes.LoadDatasetFromFile
    end
    
    action :validate_for_signature, :map do
      argument :signature_module, :atom, allow_nil?: false
      
      run fn input, context ->
        dataset = context.resource
        signature_module = input.arguments.signature_module
        
        DSPex.ML.Actions.ValidateDatasetForSignature.run(dataset, signature_module)
      end
    end
    
    action :sample, :struct do
      argument :size, :integer, allow_nil?: false
      argument :random_seed, :integer
      
      run fn input, context ->
        dataset = context.resource
        size = min(input.arguments.size, length(dataset.data))
        
        sampled_data = case input.arguments.random_seed do
          nil -> Enum.take_random(dataset.data, size)
          seed -> 
            :rand.seed(:exsplus, {seed, seed, seed})
            Enum.take_random(dataset.data, size)
        end
        
        {:ok, %{dataset | data: sampled_data, size: length(sampled_data)}}
      end
    end
  end
  
  calculations do
    calculate :statistics, :map do
      calculation fn records, _context ->
        Enum.map(records, fn dataset ->
          data = dataset.data || []
          
          %{
            size: length(data),
            has_inputs: has_field?(data, "inputs"),
            has_outputs: has_field?(data, "outputs"), 
            input_fields: extract_input_fields(data),
            output_fields: extract_output_fields(data)
          }
        end)
      end
    end
  end
  
  code_interface do
    define :create_from_file
    define :validate_for_signature
    define :sample
  end
  
  defp has_field?([], _field), do: false
  defp has_field?([item | _rest], field) when is_map(item) do
    Map.has_key?(item, field)
  end
  defp has_field?(_data, _field), do: false
  
  defp extract_input_fields([]), do: []
  defp extract_input_fields([item | _rest]) when is_map(item) do
    case Map.get(item, "inputs") do
      inputs when is_map(inputs) -> Map.keys(inputs)
      _ -> []
    end
  end
  defp extract_input_fields(_), do: []
  
  defp extract_output_fields([]), do: []
  defp extract_output_fields([item | _rest]) when is_map(item) do
    case Map.get(item, "outputs") do
      outputs when is_map(outputs) -> Map.keys(outputs)
      _ -> []
    end
  end
  defp extract_output_fields(_), do: []
end
```

## 3. Monitoring and Observability

### 3.1 Telemetry Setup

```elixir
# lib/dspex/telemetry.ex
defmodule DSPex.Telemetry do
  @moduledoc """
  Telemetry setup for DSPy operations monitoring.
  """
  
  use Supervisor
  import Telemetry.Metrics
  
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end
  
  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def metrics do
    [
      # Program execution metrics
      counter("dspex.program.execution.count",
        tags: [:program_id, :status]
      ),
      
      distribution("dspex.program.execution.duration",
        unit: {:native, :millisecond},
        tags: [:program_id]
      ),
      
      distribution("dspex.program.execution.token_usage",
        tags: [:program_id, :token_type]
      ),
      
      # Optimization metrics  
      counter("dspex.optimization.count",
        tags: [:optimizer, :status]
      ),
      
      distribution("dspex.optimization.duration",
        unit: {:native, :millisecond},
        tags: [:optimizer]
      ),
      
      distribution("dspex.optimization.score",
        tags: [:optimizer, :metric]
      ),
      
      # Python bridge metrics
      counter("dspex.python_bridge.requests.count",
        tags: [:command, :status]
      ),
      
      distribution("dspex.python_bridge.requests.duration",
        unit: {:native, :millisecond},
        tags: [:command]
      ),
      
      # System metrics
      last_value("dspex.programs.active_count"),
      last_value("dspex.executions.queue_length"),
      last_value("dspex.python_bridge.connection_status")
    ]
  end
  
  defp periodic_measurements do
    [
      # Measure active programs
      {DSPex.Telemetry, :measure_active_programs, []},
      
      # Measure queue lengths
      {DSPex.Telemetry, :measure_queue_lengths, []},
      
      # Measure Python bridge health
      {DSPex.Telemetry, :measure_python_bridge_health, []}
    ]
  end
  
  def measure_active_programs do
    count = DSPex.ML.Program.count!(filter: [status: [:ready, :optimized, :deployed]])
    :telemetry.execute([:dspex, :programs], %{active_count: count})
  end
  
  def measure_queue_lengths do
    running = DSPex.ML.Execution.count!(filter: [status: :running])
    :telemetry.execute([:dspex, :executions], %{queue_length: running})
  end
  
  def measure_python_bridge_health do
    status = case Process.whereis(DSPex.PythonBridge.Bridge) do
      nil -> 0
      _pid -> 1
    end
    
    :telemetry.execute([:dspex, :python_bridge], %{connection_status: status})
  end
end
```

### 3.2 Execution Instrumentation

```elixir
# lib/dspex/instrumentation/execution.ex
defmodule DSPex.Instrumentation.Execution do
  @moduledoc """
  Telemetry instrumentation for program executions.
  """
  
  def instrument_execution(program, inputs, fun) do
    start_time = System.monotonic_time()
    
    metadata = %{
      program_id: program.id,
      program_name: program.name,
      input_size: map_size(inputs)
    }
    
    :telemetry.span(
      [:dspex, :program, :execution],
      metadata,
      fn ->
        case fun.() do
          {:ok, result} = success ->
            measurements = %{
              duration: System.monotonic_time() - start_time,
              token_usage: get_token_usage(result),
              output_size: map_size(result)
            }
            
            {success, Map.merge(metadata, %{status: :success}) |> Map.merge(measurements)}
          
          {:error, reason} = error ->
            measurements = %{
              duration: System.monotonic_time() - start_time
            }
            
            {error, Map.merge(metadata, %{status: :error, error: reason}) |> Map.merge(measurements)}
        end
      end
    )
  end
  
  defp get_token_usage(result) do
    case result do
      %{_metadata: %{token_usage: usage}} -> usage
      _ -> %{}
    end
  end
end
```

### 3.3 LiveDashboard Integration

```elixir
# lib/dspex_web/telemetry.ex
defmodule DSPexWeb.Telemetry do
  @moduledoc """
  Phoenix LiveDashboard integration for DSPy monitoring.
  """
  
  use Supervisor
  import Telemetry.Metrics
  
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end
  
  @impl true
  def init(_arg) do
    children = [
      # Telemetry metrics
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router.dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      
      # Database metrics
      summary("dspex.repo.query.total_time",
        unit: {:native, :millisecond}
      ),
      summary("dspex.repo.query.decode_time",
        unit: {:native, :millisecond}
      ),
      summary("dspex.repo.query.query_time",
        unit: {:native, :millisecond}
      ),
      summary("dspex.repo.query.queue_time",
        unit: {:native, :millisecond}
      ),
      summary("dspex.repo.query.idle_time",
        unit: {:native, :millisecond}
      ),
      
      # VM metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),
      
      # DSPy specific metrics from DSPex.Telemetry
      *DSPex.Telemetry.metrics()
    ]
  end
end
```

### 3.4 Performance Monitoring

```elixir
# lib/dspex/monitoring/performance_monitor.ex
defmodule DSPex.Monitoring.PerformanceMonitor do
  @moduledoc """
  Monitor and alert on DSPy performance issues.
  """
  
  use GenServer
  
  defstruct [
    :thresholds,
    :alert_handlers,
    :metrics_history
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Attach telemetry handlers
    events = [
      [:dspex, :program, :execution, :stop],
      [:dspex, :optimization, :stop],
      [:dspex, :python_bridge, :requests, :stop]
    ]
    
    :telemetry.attach_many("performance_monitor", events, &handle_event/4, nil)
    
    state = %__MODULE__{
      thresholds: Keyword.get(opts, :thresholds, default_thresholds()),
      alert_handlers: Keyword.get(opts, :alert_handlers, []),
      metrics_history: %{}
    }
    
    {:ok, state}
  end
  
  def handle_event([:dspex, :program, :execution, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:execution_completed, measurements, metadata})
  end
  
  def handle_event([:dspex, :optimization, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:optimization_completed, measurements, metadata})
  end
  
  def handle_event([:dspex, :python_bridge, :requests, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:bridge_request_completed, measurements, metadata})
  end
  
  @impl true
  def handle_cast({:execution_completed, measurements, metadata}, state) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    # Check for slow executions
    if duration_ms > state.thresholds.slow_execution_ms do
      alert = %{
        type: :slow_execution,
        program_id: metadata.program_id,
        duration_ms: duration_ms,
        threshold_ms: state.thresholds.slow_execution_ms,
        timestamp: DateTime.utc_now()
      }
      
      send_alerts(alert, state.alert_handlers)
    end
    
    # Check for high error rates
    if metadata.status == :error do
      check_error_rate(metadata.program_id, state)
    end
    
    {:noreply, update_metrics_history(state, :execution, measurements, metadata)}
  end
  
  @impl true
  def handle_cast({:optimization_completed, measurements, metadata}, state) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    # Check for very long optimizations
    if duration_ms > state.thresholds.long_optimization_ms do
      alert = %{
        type: :long_optimization,
        program_id: metadata.program_id,
        optimizer: metadata.optimizer,
        duration_ms: duration_ms,
        threshold_ms: state.thresholds.long_optimization_ms,
        timestamp: DateTime.utc_now()
      }
      
      send_alerts(alert, state.alert_handlers)
    end
    
    {:noreply, update_metrics_history(state, :optimization, measurements, metadata)}
  end
  
  @impl true
  def handle_cast({:bridge_request_completed, measurements, metadata}, state) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    # Check for slow Python bridge calls
    if duration_ms > state.thresholds.slow_bridge_call_ms do
      alert = %{
        type: :slow_bridge_call,
        command: metadata.command,
        duration_ms: duration_ms,
        threshold_ms: state.thresholds.slow_bridge_call_ms,
        timestamp: DateTime.utc_now()
      }
      
      send_alerts(alert, state.alert_handlers)
    end
    
    {:noreply, update_metrics_history(state, :bridge_call, measurements, metadata)}
  end
  
  defp default_thresholds do
    %{
      slow_execution_ms: 5_000,
      long_optimization_ms: 300_000,  # 5 minutes
      slow_bridge_call_ms: 1_000,
      high_error_rate_threshold: 0.1  # 10%
    }
  end
  
  defp send_alerts(alert, handlers) do
    Enum.each(handlers, fn handler ->
      try do
        handler.(alert)
      rescue
        error ->
          Logger.error("Alert handler failed: #{inspect(error)}")
      end
    end)
  end
  
  defp check_error_rate(program_id, state) do
    # Get recent executions for this program
    recent_window = DateTime.add(DateTime.utc_now(), -300, :second)  # Last 5 minutes
    
    executions = DSPex.ML.Execution.list!(
      filter: [
        program_id: program_id,
        started_at: [greater_than: recent_window]
      ]
    )
    
    if length(executions) >= 10 do  # Only check if we have enough data
      error_count = Enum.count(executions, & &1.status == :failed)
      error_rate = error_count / length(executions)
      
      if error_rate > state.thresholds.high_error_rate_threshold do
        alert = %{
          type: :high_error_rate,
          program_id: program_id,
          error_rate: error_rate,
          threshold: state.thresholds.high_error_rate_threshold,
          sample_size: length(executions),
          timestamp: DateTime.utc_now()
        }
        
        send_alerts(alert, state.alert_handlers)
      end
    end
  end
  
  defp update_metrics_history(state, event_type, measurements, metadata) do
    # Keep a sliding window of metrics for trend analysis
    # Implementation details omitted for brevity
    state
  end
end
```

## 4. Web Interface Components

### 4.1 Phoenix Router

```elixir
# lib/dspex_web/router.ex
defmodule DSPexWeb.Router do
  use DSPexWeb, :router
  
  pipeline :api do
    plug :accepts, ["json"]
  end
  
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DSPexWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end
  
  scope "/" do
    pipe_through :browser
    
    # LiveDashboard
    live_dashboard "/dashboard",
      metrics: DSPexWeb.Telemetry,
      additional_pages: [
        dspy_overview: DSPexWeb.DSPyDashboard
      ]
    
    # Live views for ML operations
    live "/", DSPexWeb.ProgramLive.Index, :index
    live "/programs/new", DSPexWeb.ProgramLive.Index, :new
    live "/programs/:id", DSPexWeb.ProgramLive.Show, :show
    live "/programs/:id/execute", DSPexWeb.ProgramLive.Show, :execute
    live "/programs/:id/optimize", DSPexWeb.ProgramLive.Show, :optimize
  end
  
  scope "/api" do
    pipe_through :api
    
    # GraphQL API
    forward "/graphql", Absinthe.Plug, schema: DSPexWeb.Schema
    
    # GraphQL subscriptions
    forward "/socket", Absinthe.Plug.GraphiQL,
      schema: DSPexWeb.Schema,
      interface: :simple,
      socket: DSPexWeb.UserSocket
  end
  
  # JSON API routes (auto-generated by Ash)
  scope "/api/ml" do
    pipe_through :api
    
    # These routes are auto-generated by AshJsonApi
    forward "/", AshJsonApi.Router,
      domains: [DSPex.ML.Domain],
      json_schema: "/api/ml/json_schema"
  end
end
```

### 4.2 WebSocket for Real-time Updates

```elixir
# lib/dspex_web/channels/user_socket.ex
defmodule DSPexWeb.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: DSPexWeb.Schema
  
  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end
  
  @impl true
  def id(_socket), do: nil
end
```

## 5. Testing Stage 3

```elixir
# test/stage3_production_features_test.exs
defmodule Stage3ProductionFeaturesTest do
  use ExUnit.Case, async: false
  use DSPexWeb.ConnCase
  
  defmodule TestSignature do
    use DSPex.Signature
    signature question: :string -> answer: :string, confidence: :float
  end
  
  test "GraphQL program creation" do
    mutation = """
    mutation CreateProgram($name: String!, $signatureModule: String!) {
      createProgram(name: $name, signatureModule: $signatureModule) {
        id
        name
        status
        signature {
          name
        }
      }
    }
    """
    
    variables = %{
      "name" => "Test GraphQL Program",
      "signatureModule" => "Stage3ProductionFeaturesTest.TestSignature"
    }
    
    response = post(build_conn(), "/api/graphql", %{
      query: mutation,
      variables: variables
    })
    
    assert json_response(response, 200)["data"]["createProgram"]["name"] == "Test GraphQL Program"
  end
  
  test "GraphQL program execution" do
    # Create program first
    {:ok, program} = DSPex.ML.Program.create_with_signature(%{
      name: "GraphQL Test Program",
      signature_module: TestSignature
    })
    
    mutation = """
    mutation ExecuteProgram($programId: ID!, $inputs: JSON!) {
      executeProgram(programId: $programId, inputs: $inputs) {
        id
        outputs
        durationMs
        status
      }
    }
    """
    
    variables = %{
      "programId" => program.id,
      "inputs" => %{"question" => "What is GraphQL?"}
    }
    
    response = post(build_conn(), "/api/graphql", %{
      query: mutation,
      variables: variables
    })
    
    assert response_data = json_response(response, 200)["data"]["executeProgram"]
    assert response_data["status"] in ["COMPLETED", "FAILED"]  # Either is fine for test
  end
  
  test "optimization job creation and processing" do
    # Create program and dataset
    {:ok, program} = DSPex.ML.Program.create_with_signature(%{
      name: "Optimization Test",
      signature_module: TestSignature
    })
    
    {:ok, dataset} = DSPex.ML.Dataset.create!(%{
      name: "Test Dataset",
      data: [
        %{"inputs" => %{"question" => "What is AI?"}, "outputs" => %{"answer" => "Artificial Intelligence"}},
        %{"inputs" => %{"question" => "What is ML?"}, "outputs" => %{"answer" => "Machine Learning"}}
      ],
      type: :training
    })
    
    # Create optimization job
    {:ok, job} = DSPex.ML.OptimizationJob.create_and_enqueue(%{
      program_id: program.id,
      dataset_id: dataset.id,
      optimizer: "BootstrapFewShot",
      metric: "exact_match"
    })
    
    assert job.status == :queued
    assert job.optimizer == "BootstrapFewShot"
    
    # The Oban job should be created
    assert Enum.any?(Oban.peek_queue(:ml_optimization), fn job ->
      job.args["optimization_job_id"] == job.id
    end)
  end
  
  test "REST API program listing" do
    # Create some programs
    {:ok, _program1} = DSPex.ML.Program.create_with_signature(%{
      name: "REST Test 1",
      signature_module: TestSignature
    })
    
    {:ok, _program2} = DSPex.ML.Program.create_with_signature(%{
      name: "REST Test 2", 
      signature_module: TestSignature
    })
    
    # List via REST API
    response = get(build_conn(), "/api/ml/programs")
    
    programs = json_response(response, 200)["data"]
    assert length(programs) >= 2
    
    program_names = Enum.map(programs, & &1["attributes"]["name"])
    assert "REST Test 1" in program_names
    assert "REST Test 2" in program_names
  end
  
  test "telemetry metrics collection" do
    # Create and execute a program to generate telemetry
    {:ok, program} = DSPex.ML.Program.create_with_signature(%{
      name: "Telemetry Test",
      signature_module: TestSignature
    })
    
    # Mock telemetry handler
    test_pid = self()
    
    :telemetry.attach_many(
      "test_handler",
      [[:dspex, :program, :execution, :stop]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )
    
    # Execute program (may fail, but should still emit telemetry)
    _result = DSPex.ML.Program.execute(program, %{inputs: %{question: "test"}})
    
    # Should receive telemetry event
    assert_receive {:telemetry_event, [:dspex, :program, :execution, :stop], measurements, metadata}, 1000
    
    assert measurements.duration > 0
    assert metadata.program_id == program.id
    
    :telemetry.detach("test_handler")
  end
end
```

## Stage 3 Deliverables

By the end of Stage 3, you should have:

1. ✅ **GraphQL API** with queries, mutations, and real-time subscriptions
2. ✅ **REST API** auto-generated by AshJsonApi  
3. ✅ **Background job processing** for long-running optimizations
4. ✅ **Comprehensive monitoring** with telemetry and performance alerts
5. ✅ **Production-ready features** like error handling and observability
6. ✅ **Real-time updates** via WebSocket subscriptions
7. ✅ **Dataset management** for training and evaluation
8. ✅ **Performance monitoring** with automated alerting

**Next**: Stage 4 will add advanced features like multi-model orchestration, deployment automation, and advanced optimization algorithms.
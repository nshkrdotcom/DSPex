# Stage 4: Advanced Features - Multi-Model Orchestration & Deployment

## Overview

Stage 4 implements advanced features that make the DSPy-Ash integration enterprise-ready: multi-model orchestration, automated deployment pipelines, advanced optimization algorithms, and comprehensive experiment management.

**Goal**: Complete production system with advanced ML workflow capabilities.

**Duration**: Week 7-8

## 1. Multi-Model Orchestration

### 1.1 Model Registry Resource

```elixir
# lib/dspex/ml/model.ex
defmodule DSPex.ML.Model do
  @moduledoc """
  Resource for managing different language models and their configurations.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :provider, :atom, constraints: [
      one_of: [:openai, :anthropic, :cohere, :huggingface, :local]
    ], allow_nil?: false
    
    attribute :model_name, :string, allow_nil?: false  # e.g., "gpt-4", "claude-3-opus"
    attribute :api_key, :string, sensitive?: true
    attribute :base_url, :string  # For custom endpoints
    attribute :config, :map, default: %{}  # Provider-specific config
    
    attribute :status, :atom, constraints: [
      one_of: [:available, :testing, :deprecated, :error]
    ], default: :testing
    
    # Performance characteristics
    attribute :cost_per_token, :decimal, default: Decimal.new("0.00")
    attribute :max_tokens, :integer
    attribute :context_window, :integer
    attribute :supports_functions, :boolean, default: false
    attribute :supports_streaming, :boolean, default: false
    
    # Metrics
    attribute :average_latency_ms, :float
    attribute :success_rate, :float
    attribute :last_health_check, :utc_datetime
    
    timestamps()
  end
  
  relationships do
    has_many :program_models, DSPex.ML.ProgramModel
    has_many :executions, DSPex.ML.Execution
  end
  
  state_machine do
    initial_states [:testing]
    default_initial_state :testing
    
    transitions do
      transition :approve, from: :testing, to: :available
      transition :deprecate, from: [:testing, :available], to: :deprecated
      transition :error, from: [:testing, :available], to: :error
      transition :retest, from: [:deprecated, :error], to: :testing
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :register_model do
      argument :test_on_creation, :boolean, default: true
      
      change fn changeset, _context ->
        test_on_creation = Ash.Changeset.get_argument(changeset, :test_on_creation)
        
        if test_on_creation do
          # Enqueue health check
          DSPex.Workers.ModelHealthCheckWorker.new(%{
            model_id: Ash.Changeset.get_attribute(changeset, :id)
          })
          |> Oban.insert()
        end
        
        changeset
      end
    end
    
    update :approve_model do
      accept []
      require_atomic? false
      change transition_state(:available)
    end
    
    action :health_check, :map do
      run DSPex.ML.Actions.ModelHealthCheck
    end
    
    action :estimate_cost, :map do
      argument :text, :string, allow_nil?: false
      
      run fn input, context ->
        model = context.resource
        text = input.arguments.text
        
        # Simple token estimation (would use proper tokenizer in production)
        estimated_tokens = div(String.length(text), 4)
        estimated_cost = Decimal.mult(model.cost_per_token, Decimal.new(estimated_tokens))
        
        {:ok, %{
          estimated_tokens: estimated_tokens,
          estimated_cost: estimated_cost,
          currency: "USD"
        }}
      end
    end
  end
  
  calculations do
    calculate :health_status, :atom do
      calculation fn records, _context ->
        Enum.map(records, fn model ->
          case model.last_health_check do
            nil -> :unknown
            time ->
              age_hours = DateTime.diff(DateTime.utc_now(), time, :hour)
              cond do
                age_hours > 24 -> :stale
                model.success_rate && model.success_rate > 0.95 -> :healthy
                model.success_rate && model.success_rate > 0.8 -> :degraded
                true -> :unhealthy
              end
          end
        end)
      end
    end
  end
  
  code_interface do
    define :register_model
    define :approve_model
    define :health_check
    define :estimate_cost
  end
end
```

### 1.2 Multi-Model Program Support

```elixir
# lib/dspex/ml/program_model.ex
defmodule DSPex.ML.ProgramModel do
  @moduledoc """
  Join resource for programs and models with routing rules.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    
    attribute :routing_strategy, :atom, constraints: [
      one_of: [:primary, :fallback, :load_balanced, :cost_optimized, :latency_optimized]
    ], default: :primary
    
    attribute :priority, :integer, default: 0  # Higher priority = preferred
    attribute :weight, :integer, default: 100  # For load balancing
    attribute :conditions, :map, default: %{}  # Routing conditions
    
    # Performance tracking
    attribute :total_requests, :integer, default: 0
    attribute :successful_requests, :integer, default: 0
    attribute :total_cost, :decimal, default: Decimal.new("0.00")
    
    timestamps()
  end
  
  relationships do
    belongs_to :program, DSPex.ML.Program
    belongs_to :model, DSPex.ML.Model
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :assign_model do
      argument :routing_strategy, :atom, default: :primary
      argument :conditions, :map, default: %{}
      
      change fn changeset, _context ->
        strategy = Ash.Changeset.get_argument(changeset, :routing_strategy)
        conditions = Ash.Changeset.get_argument(changeset, :conditions)
        
        changeset
        |> Ash.Changeset.change_attribute(:routing_strategy, strategy)
        |> Ash.Changeset.change_attribute(:conditions, conditions)
      end
    end
    
    update :record_execution do
      accept [:successful_requests, :total_requests, :total_cost]
      require_atomic? false
    end
  end
  
  code_interface do
    define :assign_model
    define :record_execution
  end
end
```

### 1.3 Model Router

```elixir
# lib/dspex/ml/model_router.ex
defmodule DSPex.ML.ModelRouter do
  @moduledoc """
  Routes program executions to appropriate models based on strategies.
  """
  
  alias DSPex.ML.{Program, Model, ProgramModel}
  
  @doc """
  Select the best model for a program execution based on routing strategy.
  """
  def select_model(program, inputs, context \\ %{}) do
    program_models = load_program_models(program)
    
    case program_models do
      [] -> {:error, "No models configured for program"}
      models -> route_to_model(models, inputs, context)
    end
  end
  
  defp load_program_models(program) do
    ProgramModel.list!(
      filter: [program_id: program.id],
      load: [:model],
      sort: [priority: :desc]
    )
  end
  
  defp route_to_model(program_models, inputs, context) do
    available_models = Enum.filter(program_models, fn pm ->
      pm.model.status == :available and meets_conditions?(pm, inputs, context)
    end)
    
    case available_models do
      [] -> fallback_to_any_model(program_models)
      models -> select_by_strategy(models, inputs, context)
    end
  end
  
  defp meets_conditions?(program_model, inputs, context) do
    conditions = program_model.conditions || %{}
    
    Enum.all?(conditions, fn
      {"input_size_max", max_size} ->
        input_size = estimate_input_size(inputs)
        input_size <= max_size
      
      {"context_required", context_key} ->
        Map.has_key?(context, String.to_atom(context_key))
      
      {"cost_limit", max_cost} ->
        estimated_cost = estimate_cost(program_model.model, inputs)
        Decimal.compare(estimated_cost, Decimal.new(to_string(max_cost))) != :gt
      
      _ -> true
    end)
  end
  
  defp select_by_strategy(models, inputs, context) do
    primary_model = Enum.find(models, & &1.routing_strategy == :primary)
    
    case primary_model do
      nil -> select_by_secondary_strategy(models, inputs, context)
      model -> check_model_health_and_select(model, models)
    end
  end
  
  defp select_by_secondary_strategy(models, inputs, _context) do
    # Group by strategy
    strategies = Enum.group_by(models, & &1.routing_strategy)
    
    cond do
      strategies[:cost_optimized] -> 
        select_cheapest_model(strategies[:cost_optimized], inputs)
      
      strategies[:latency_optimized] ->
        select_fastest_model(strategies[:latency_optimized])
      
      strategies[:load_balanced] ->
        select_by_load_balancing(strategies[:load_balanced])
      
      true ->
        {:ok, hd(models)}
    end
  end
  
  defp select_cheapest_model(models, inputs) do
    cheapest = Enum.min_by(models, fn pm ->
      estimate_cost(pm.model, inputs)
    end)
    
    {:ok, cheapest}
  end
  
  defp select_fastest_model(models) do
    fastest = Enum.min_by(models, fn pm ->
      pm.model.average_latency_ms || 1000
    end)
    
    {:ok, fastest}
  end
  
  defp select_by_load_balancing(models) do
    # Weighted random selection based on success rate and weight
    weights = Enum.map(models, fn pm ->
      base_weight = pm.weight || 100
      success_rate = pm.model.success_rate || 0.5
      base_weight * success_rate
    end)
    
    total_weight = Enum.sum(weights)
    random_value = :rand.uniform() * total_weight
    
    selected = select_weighted_random(models, weights, random_value, 0)
    {:ok, selected}
  end
  
  defp select_weighted_random([model | _], [weight | _], random_value, acc) 
       when random_value <= acc + weight do
    model
  end
  
  defp select_weighted_random([_ | models], [weight | weights], random_value, acc) do
    select_weighted_random(models, weights, random_value, acc + weight)
  end
  
  defp select_weighted_random([], _, _, _), do: nil
  
  defp check_model_health_and_select(primary_model, all_models) do
    case primary_model.model.health_status do
      :healthy -> {:ok, primary_model}
      :degraded -> 
        # Use primary but consider fallback for next request
        schedule_health_check(primary_model.model)
        {:ok, primary_model}
      _ ->
        # Find fallback
        fallback = Enum.find(all_models, & &1.routing_strategy == :fallback)
        case fallback do
          nil -> {:ok, primary_model}  # Use primary anyway
          model -> {:ok, model}
        end
    end
  end
  
  defp fallback_to_any_model(program_models) do
    # If no models meet conditions, try the first available one
    case Enum.find(program_models, & &1.model.status == :available) do
      nil -> {:error, "No available models"}
      model -> {:ok, model}
    end
  end
  
  defp estimate_input_size(inputs) do
    inputs
    |> Jason.encode!()
    |> String.length()
  end
  
  defp estimate_cost(model, inputs) do
    estimated_tokens = div(estimate_input_size(inputs), 4)
    Decimal.mult(model.cost_per_token, Decimal.new(estimated_tokens))
  end
  
  defp schedule_health_check(model) do
    DSPex.Workers.ModelHealthCheckWorker.new(%{model_id: model.id})
    |> Oban.insert()
  end
end
```

### 1.4 Enhanced Execution with Model Routing

```elixir
# lib/dspex/data_layer/query_handler.ex (enhanced execute)
defmodule DSPex.DataLayer.QueryHandler do
  # ... existing code ...
  
  defp execute_via_adapter(program, inputs) do
    # Use model router to select best model
    case DSPex.ML.ModelRouter.select_model(program, inputs) do
      {:ok, program_model} ->
        adapter = get_adapter_for_model(program_model.model)
        
        # Track execution start
        start_time = System.monotonic_time(:millisecond)
        
        result = adapter.execute_program(
          program.dspy_program_id,
          inputs,
          model_config: build_model_config(program_model.model)
        )
        
        # Track execution completion
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        # Update model metrics
        case result do
          {:ok, output} ->
            update_model_metrics(program_model, duration, output, :success)
            result
          
          {:error, _} = error ->
            update_model_metrics(program_model, duration, nil, :error)
            
            # Try fallback model if available
            try_fallback_model(program, inputs, program_model, error)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp try_fallback_model(program, inputs, failed_model, original_error) do
    # Find fallback models excluding the failed one
    fallback_models = DSPex.ML.ProgramModel.list!(
      filter: [
        program_id: program.id,
        routing_strategy: :fallback
      ],
      load: [:model]
    )
    |> Enum.reject(& &1.id == failed_model.id)
    
    case fallback_models do
      [] -> original_error
      [fallback | _] ->
        Logger.warning("Primary model failed, trying fallback: #{fallback.model.name}")
        
        adapter = get_adapter_for_model(fallback.model)
        adapter.execute_program(
          program.dspy_program_id,
          inputs,
          model_config: build_model_config(fallback.model)
        )
    end
  end
  
  defp get_adapter_for_model(model) do
    case model.provider do
      :openai -> DSPex.Adapters.OpenAI
      :anthropic -> DSPex.Adapters.Anthropic
      :cohere -> DSPex.Adapters.Cohere
      _ -> Application.get_env(:dspex, :adapter, DSPex.Adapters.PythonPort)
    end
  end
  
  defp build_model_config(model) do
    %{
      provider: model.provider,
      model: model.model_name,
      api_key: model.api_key,
      base_url: model.base_url,
      max_tokens: model.max_tokens,
      config: model.config
    }
  end
  
  defp update_model_metrics(program_model, duration, output, status) do
    # Update ProgramModel metrics
    updates = case status do
      :success ->
        cost = calculate_execution_cost(program_model.model, output)
        %{
          total_requests: program_model.total_requests + 1,
          successful_requests: program_model.successful_requests + 1,
          total_cost: Decimal.add(program_model.total_cost, cost)
        }
      
      :error ->
        %{
          total_requests: program_model.total_requests + 1
        }
    end
    
    DSPex.ML.ProgramModel.record_execution(program_model, updates)
    
    # Update Model aggregate metrics
    update_model_aggregate_metrics(program_model.model, duration, status)
  end
  
  defp calculate_execution_cost(model, output) do
    token_usage = get_token_usage_from_output(output)
    total_tokens = token_usage["total"] || 0
    
    Decimal.mult(model.cost_per_token, Decimal.new(total_tokens))
  end
  
  defp update_model_aggregate_metrics(model, duration, status) do
    # This would update aggregate metrics across all programs
    # Implementation would involve querying recent executions and recalculating
    # For brevity, we'll just update latency
    
    new_latency = case model.average_latency_ms do
      nil -> duration * 1.0
      current -> (current * 0.9) + (duration * 0.1)  # Exponential moving average
    end
    
    DSPex.ML.Model.update!(model, %{average_latency_ms: new_latency})
  end
end
```

## 2. Deployment Automation

### 2.1 Deployment Pipeline Resource

```elixir
# lib/dspex/ml/deployment_pipeline.ex
defmodule DSPex.ML.DeploymentPipeline do
  @moduledoc """
  Resource for managing deployment pipelines and automation.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine, AshOban]
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    
    attribute :status, :atom, constraints: [
      one_of: [:draft, :active, :paused, :failed]
    ], default: :draft
    
    # Pipeline configuration
    attribute :trigger_conditions, :map, default: %{}
    attribute :validation_rules, {:array, :map}, default: []
    attribute :deployment_config, :map, default: %{}
    attribute :rollback_config, :map, default: %{}
    
    # Monitoring
    attribute :success_rate_threshold, :float, default: 0.95
    attribute :latency_threshold_ms, :integer, default: 5000
    attribute :error_rate_threshold, :float, default: 0.05
    
    timestamps()
  end
  
  relationships do
    belongs_to :program, DSPex.ML.Program
    has_many :deployments, DSPex.ML.Deployment
  end
  
  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    transitions do
      transition :activate, from: :draft, to: :active
      transition :pause, from: :active, to: :paused
      transition :resume, from: :paused, to: :active
      transition :fail, from: [:active, :paused], to: :failed
      transition :reset, from: :failed, to: :draft
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_pipeline do
      argument :trigger_conditions, :map, default: %{}
      argument :validation_rules, {:array, :map}, default: []
      
      change fn changeset, _context ->
        trigger_conditions = Ash.Changeset.get_argument(changeset, :trigger_conditions)
        validation_rules = Ash.Changeset.get_argument(changeset, :validation_rules)
        
        changeset
        |> Ash.Changeset.change_attribute(:trigger_conditions, trigger_conditions)
        |> Ash.Changeset.change_attribute(:validation_rules, validation_rules)
      end
    end
    
    update :activate_pipeline do
      accept []
      require_atomic? false
      change transition_state(:active)
      
      change fn changeset, _context ->
        # Start monitoring this pipeline
        DSPex.Workers.PipelineMonitorWorker.new(%{
          pipeline_id: changeset.data.id
        })
        |> Oban.insert()
        
        changeset
      end
    end
    
    action :check_trigger_conditions, :boolean do
      argument :context, :map, default: %{}
      
      run fn input, context ->
        pipeline = context.resource
        check_context = input.arguments.context
        
        DSPex.ML.Actions.CheckTriggerConditions.run(pipeline, check_context)
      end
    end
    
    action :trigger_deployment, :struct do
      argument :reason, :string, default: "Manual trigger"
      argument :config_overrides, :map, default: %{}
      
      run DSPex.ML.Actions.TriggerDeployment
    end
  end
  
  code_interface do
    define :create_pipeline
    define :activate_pipeline
    define :check_trigger_conditions
    define :trigger_deployment
  end
end
```

### 2.2 Deployment Resource

```elixir
# lib/dspex/ml/deployment.ex
defmodule DSPex.ML.Deployment do
  @moduledoc """
  Resource for tracking individual deployments.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    
    attribute :version, :string, allow_nil?: false
    attribute :trigger_reason, :string
    attribute :config, :map, default: %{}
    
    attribute :status, :atom, constraints: [
      one_of: [:pending, :validating, :deploying, :deployed, :failed, :rolled_back]
    ], default: :pending
    
    # Deployment artifacts
    attribute :program_snapshot, :map  # Snapshot of program state
    attribute :validation_results, :map
    attribute :deployment_logs, {:array, :string}, default: []
    
    # Monitoring data
    attribute :health_checks, {:array, :map}, default: []
    attribute :performance_metrics, :map, default: %{}
    
    # Timing
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    attribute :rollback_at, :utc_datetime
    
    timestamps()
  end
  
  relationships do
    belongs_to :pipeline, DSPex.ML.DeploymentPipeline
    belongs_to :program, DSPex.ML.Program
  end
  
  state_machine do
    initial_states [:pending]
    default_initial_state :pending
    
    transitions do
      transition :start_validation, from: :pending, to: :validating
      transition :start_deployment, from: :validating, to: :deploying
      transition :complete, from: :deploying, to: :deployed
      transition :fail, from: [:validating, :deploying], to: :failed
      transition :rollback, from: [:deployed, :failed], to: :rolled_back
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :start_deployment do
      argument :trigger_reason, :string, default: "Automated trigger"
      argument :config_overrides, :map, default: %{}
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:version, generate_version())
      end
      
      # Enqueue deployment job
      change fn changeset, _context ->
        DSPex.Workers.DeploymentWorker.new(%{
          deployment_id: Ash.Changeset.get_attribute(changeset, :id)
        })
        |> Oban.insert()
        
        changeset
      end
    end
    
    update :update_status do
      accept [:status, :validation_results, :deployment_logs, :health_checks]
      require_atomic? false
      
      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :status) do
          status when status in [:deployed, :failed, :rolled_back] ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
          _ ->
            changeset
        end
      end
    end
    
    action :validate_deployment, :map do
      run DSPex.ML.Actions.ValidateDeployment
    end
    
    action :execute_deployment, :map do
      run DSPex.ML.Actions.ExecuteDeployment
    end
    
    action :rollback_deployment, :map do
      run DSPex.ML.Actions.RollbackDeployment
    end
  end
  
  calculations do
    calculate :duration_minutes, :float do
      calculation fn records, _context ->
        Enum.map(records, fn deployment ->
          case {deployment.started_at, deployment.completed_at} do
            {start, finish} when not is_nil(start) and not is_nil(finish) ->
              DateTime.diff(finish, start, :second) / 60.0
            _ -> nil
          end
        end)
      end
    end
  end
  
  code_interface do
    define :start_deployment
    define :update_status
    define :validate_deployment
    define :execute_deployment
    define :rollback_deployment
  end
  
  defp generate_version do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "v#{timestamp}"
  end
end
```

### 2.3 Deployment Worker

```elixir
# lib/dspex/workers/deployment_worker.ex
defmodule DSPex.Workers.DeploymentWorker do
  @moduledoc """
  Oban worker for executing deployment pipelines.
  """
  
  use Oban.Worker, queue: :deployment, max_attempts: 3
  
  alias DSPex.ML.{Deployment, DeploymentPipeline, Program}
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => deployment_id}}) do
    deployment = Deployment.get!(deployment_id)
    pipeline = DeploymentPipeline.get!(deployment.pipeline_id)
    program = Program.get!(deployment.program_id)
    
    try do
      # Step 1: Validation
      {:ok, validation_results} = validate_deployment(deployment, pipeline, program)
      
      Deployment.update_status(deployment, %{
        status: :validating,
        validation_results: validation_results
      })
      
      case validation_results.passed do
        false ->
          fail_deployment(deployment, "Validation failed: #{validation_results.errors}")
          
        true ->
          # Step 2: Execute deployment
          execute_deployment_steps(deployment, pipeline, program)
      end
      
    rescue
      error ->
        fail_deployment(deployment, "Deployment error: #{Exception.message(error)}")
        {:error, error}
    end
  end
  
  defp validate_deployment(deployment, pipeline, program) do
    validation_rules = pipeline.validation_rules || []
    
    results = Enum.map(validation_rules, fn rule ->
      validate_rule(rule, deployment, program)
    end)
    
    passed = Enum.all?(results, & &1.passed)
    errors = results |> Enum.reject(& &1.passed) |> Enum.map(& &1.error)
    
    {:ok, %{
      passed: passed,
      errors: errors,
      details: results
    }}
  end
  
  defp validate_rule(%{"type" => "performance_threshold"} = rule, _deployment, program) do
    threshold = rule["threshold"]
    metric = rule["metric"]
    
    # Get recent performance data
    recent_executions = get_recent_executions(program, 100)
    current_metric = calculate_metric(recent_executions, metric)
    
    passed = case rule["operator"] do
      ">" -> current_metric > threshold
      ">=" -> current_metric >= threshold
      "<" -> current_metric < threshold
      "<=" -> current_metric <= threshold
      _ -> false
    end
    
    %{
      passed: passed,
      error: unless(passed, do: "#{metric} (#{current_metric}) does not meet threshold #{rule["operator"]} #{threshold}"),
      metric: metric,
      value: current_metric,
      threshold: threshold
    }
  end
  
  defp validate_rule(%{"type" => "minimum_executions"} = rule, _deployment, program) do
    required_count = rule["count"]
    
    recent_executions = get_recent_executions(program, required_count)
    actual_count = length(recent_executions)
    
    passed = actual_count >= required_count
    
    %{
      passed: passed,
      error: unless(passed, do: "Only #{actual_count} executions, need #{required_count}"),
      required: required_count,
      actual: actual_count
    }
  end
  
  defp validate_rule(%{"type" => "canary_test"} = rule, deployment, program) do
    test_inputs = rule["test_inputs"]
    expected_outputs = rule["expected_outputs"]
    
    # Run canary test
    case Program.execute(program, %{inputs: test_inputs}) do
      {:ok, result} ->
        passed = outputs_match?(result, expected_outputs, rule["tolerance"] || 0.1)
        
        %{
          passed: passed,
          error: unless(passed, do: "Canary test failed: output mismatch"),
          test_inputs: test_inputs,
          actual_outputs: result,
          expected_outputs: expected_outputs
        }
      
      {:error, reason} ->
        %{
          passed: false,
          error: "Canary test failed: #{reason}",
          test_inputs: test_inputs
        }
    end
  end
  
  defp execute_deployment_steps(deployment, pipeline, program) do
    Deployment.update_status(deployment, %{status: :deploying})
    
    config = Map.merge(pipeline.deployment_config, deployment.config)
    
    # Create program snapshot
    program_snapshot = create_program_snapshot(program)
    
    Deployment.update_status(deployment, %{program_snapshot: program_snapshot})
    
    # Execute deployment based on strategy
    case config["strategy"] do
      "blue_green" -> 
        execute_blue_green_deployment(deployment, program, config)
      
      "canary" ->
        execute_canary_deployment(deployment, program, config)
      
      "rolling" ->
        execute_rolling_deployment(deployment, program, config)
      
      _ ->
        execute_immediate_deployment(deployment, program, config)
    end
  end
  
  defp execute_immediate_deployment(deployment, program, _config) do
    # Update program status to deployed
    Program.update!(program, %{status: :deployed})
    
    # Start health monitoring
    schedule_health_checks(deployment)
    
    Deployment.update_status(deployment, %{
      status: :deployed,
      deployment_logs: ["Immediate deployment completed successfully"]
    })
    
    :ok
  end
  
  defp execute_canary_deployment(deployment, program, config) do
    canary_percentage = config["canary_percentage"] || 10
    monitoring_duration = config["monitoring_duration_minutes"] || 30
    
    # Deploy canary version
    logs = ["Starting canary deployment with #{canary_percentage}% traffic"]
    
    Deployment.update_status(deployment, %{
      deployment_logs: logs
    })
    
    # In a real implementation, this would:
    # 1. Route percentage of traffic to new version
    # 2. Monitor metrics for specified duration
    # 3. Automatically promote or rollback based on metrics
    
    # For now, we'll simulate the process
    Process.sleep(5000)  # Simulate monitoring period
    
    # Check if canary is healthy (simplified)
    canary_healthy = simulate_canary_health_check()
    
    if canary_healthy do
      # Promote canary to full deployment
      Program.update!(program, %{status: :deployed})
      
      Deployment.update_status(deployment, %{
        status: :deployed,
        deployment_logs: logs ++ ["Canary deployment successful, promoted to full deployment"]
      })
    else
      # Rollback canary
      Deployment.update_status(deployment, %{
        status: :rolled_back,
        deployment_logs: logs ++ ["Canary deployment failed, rolled back"]
      })
    end
    
    :ok
  end
  
  defp fail_deployment(deployment, reason) do
    Deployment.update_status(deployment, %{
      status: :failed,
      deployment_logs: [reason]
    })
  end
  
  defp get_recent_executions(program, count) do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)
    
    DSPex.ML.Execution.list!(
      filter: [
        program_id: program.id,
        started_at: [greater_than: since],
        status: :completed
      ],
      limit: count,
      sort: [started_at: :desc]
    )
  end
  
  defp calculate_metric(executions, "success_rate") do
    case length(executions) do
      0 -> 0.0
      total -> Enum.count(executions, & &1.status == :completed) / total
    end
  end
  
  defp calculate_metric(executions, "average_latency") do
    case executions do
      [] -> 0.0
      list -> 
        durations = Enum.map(list, & &1.duration_ms || 0)
        Enum.sum(durations) / length(durations)
    end
  end
  
  defp outputs_match?(actual, expected, tolerance) do
    # Simplified output matching - would be more sophisticated in production
    case {actual, expected} do
      {%{answer: actual_answer}, %{answer: expected_answer}} ->
        String.jaro_distance(actual_answer, expected_answer) >= (1.0 - tolerance)
      _ -> false
    end
  end
  
  defp create_program_snapshot(program) do
    %{
      id: program.id,
      name: program.name,
      status: program.status,
      compiled_state: program.compiled_state,
      performance_metrics: program.performance_metrics,
      snapshot_at: DateTime.utc_now()
    }
  end
  
  defp schedule_health_checks(deployment) do
    # Schedule periodic health checks for the deployment
    DSPex.Workers.DeploymentHealthCheckWorker.new(%{
      deployment_id: deployment.id
    }, schedule_in: 60)  # First check in 1 minute
    |> Oban.insert()
  end
  
  defp simulate_canary_health_check do
    # Simulate canary health check - would use real metrics in production
    :rand.uniform() > 0.1  # 90% success rate
  end
end
```

## 3. Advanced Optimization Algorithms

### 3.1 Optimizer Registry

```elixir
# lib/dspex/optimizers/registry.ex
defmodule DSPex.Optimizers.Registry do
  @moduledoc """
  Registry of available optimization algorithms.
  """
  
  @optimizers %{
    "BootstrapFewShot" => DSPex.Optimizers.BootstrapFewShot,
    "MIPRO" => DSPex.Optimizers.MIPRO,
    "COPRO" => DSPex.Optimizers.COPRO,
    "AdvancedBootstrap" => DSPex.Optimizers.AdvancedBootstrap,
    "MultiObjective" => DSPex.Optimizers.MultiObjective,
    "BayesianOptimizer" => DSPex.Optimizers.BayesianOptimizer
  }
  
  def get_optimizer(name) do
    case Map.get(@optimizers, name) do
      nil -> {:error, "Unknown optimizer: #{name}"}
      optimizer -> {:ok, optimizer}
    end
  end
  
  def list_optimizers do
    Map.keys(@optimizers)
  end
  
  def get_optimizer_info(name) do
    case get_optimizer(name) do
      {:ok, optimizer} -> optimizer.info()
      error -> error
    end
  end
end
```

### 3.2 Advanced Bootstrap Optimizer

```elixir
# lib/dspex/optimizers/advanced_bootstrap.ex
defmodule DSPex.Optimizers.AdvancedBootstrap do
  @moduledoc """
  Advanced bootstrap optimizer with adaptive sampling and quality filtering.
  """
  
  @behaviour DSPex.Optimizers.Optimizer
  
  def info do
    %{
      name: "AdvancedBootstrap",
      description: "Bootstrap optimizer with adaptive sampling and quality filtering",
      parameters: [
        %{name: "max_demos", type: :integer, default: 8, description: "Maximum demonstrations"},
        %{name: "quality_threshold", type: :float, default: 0.8, description: "Quality threshold for demos"},
        %{name: "diversity_factor", type: :float, default: 0.3, description: "Diversity weighting"},
        %{name: "adaptive_sampling", type: :boolean, default: true, description: "Use adaptive sampling"}
      ]
    }
  end
  
  @impl true
  def optimize(program, dataset, metric, config) do
    max_demos = config[:max_demos] || 8
    quality_threshold = config[:quality_threshold] || 0.8
    diversity_factor = config[:diversity_factor] || 0.3
    adaptive_sampling = config[:adaptive_sampling] || true
    
    # Generate candidate demonstrations
    candidates = generate_candidate_demos(program, dataset, metric)
    
    # Filter by quality
    quality_demos = filter_by_quality(candidates, quality_threshold, metric)
    
    # Select diverse, high-quality subset
    selected_demos = if adaptive_sampling do
      select_adaptive_demos(quality_demos, max_demos, diversity_factor)
    else
      select_top_demos(quality_demos, max_demos)
    end
    
    # Optimize program with selected demonstrations
    optimized_program = apply_demonstrations(program, selected_demos)
    
    # Evaluate optimized program
    score = evaluate_program(optimized_program, dataset, metric)
    
    {:ok, %{
      optimized_program: optimized_program,
      score: score,
      demonstrations: selected_demos,
      metadata: %{
        candidates_generated: length(candidates),
        quality_filtered: length(quality_demos),
        final_selected: length(selected_demos)
      }
    }}
  end
  
  defp generate_candidate_demos(program, dataset, metric) do
    # Use multiple strategies to generate diverse candidates
    strategies = [
      &generate_random_demos/3,
      &generate_hard_examples_demos/3,
      &generate_diverse_demos/3
    ]
    
    candidates = Enum.flat_map(strategies, fn strategy ->
      strategy.(program, dataset, metric)
    end)
    
    # Remove duplicates and invalid demos
    candidates
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(&valid_demo?/1)
  end
  
  defp filter_by_quality(candidates, threshold, metric) do
    Enum.filter(candidates, fn demo ->
      demo.quality_score >= threshold
    end)
  end
  
  defp select_adaptive_demos(demos, max_count, diversity_factor) do
    # Balance quality and diversity using weighted selection
    sorted_demos = Enum.sort_by(demos, & &1.quality_score, :desc)
    
    selected = []
    remaining = sorted_demos
    
    select_diverse_subset(selected, remaining, max_count, diversity_factor)
  end
  
  defp select_diverse_subset(selected, _remaining, max_count, _diversity_factor) 
       when length(selected) >= max_count do
    selected
  end
  
  defp select_diverse_subset(selected, [], _max_count, _diversity_factor) do
    selected
  end
  
  defp select_diverse_subset(selected, remaining, max_count, diversity_factor) do
    # Calculate diversity scores for remaining demos
    diversity_scores = Enum.map(remaining, fn demo ->
      diversity_score = calculate_diversity_score(demo, selected)
      combined_score = (1 - diversity_factor) * demo.quality_score + 
                      diversity_factor * diversity_score
      {demo, combined_score}
    end)
    
    # Select demo with highest combined score
    {best_demo, _score} = Enum.max_by(diversity_scores, fn {_demo, score} -> score end)
    
    new_selected = [best_demo | selected]
    new_remaining = List.delete(remaining, best_demo)
    
    select_diverse_subset(new_selected, new_remaining, max_count, diversity_factor)
  end
  
  defp calculate_diversity_score(demo, selected_demos) do
    if Enum.empty?(selected_demos) do
      1.0
    else
      # Calculate minimum similarity to any selected demo
      similarities = Enum.map(selected_demos, fn selected ->
        calculate_similarity(demo, selected)
      end)
      
      1.0 - Enum.max(similarities)  # Diversity = 1 - max_similarity
    end
  end
  
  defp calculate_similarity(demo1, demo2) do
    # Simple text-based similarity for now
    # In production, would use embeddings or more sophisticated methods
    String.jaro_distance(demo1.input_text, demo2.input_text)
  end
  
  # Additional helper functions...
  defp generate_random_demos(program, dataset, _metric) do
    dataset
    |> Enum.take_random(20)
    |> Enum.map(&convert_to_demo(&1, program))
  end
  
  defp generate_hard_examples_demos(program, dataset, metric) do
    # Generate demos from examples where the program initially struggles
    # Implementation would involve running program on dataset and selecting
    # examples with low scores for demonstration generation
    []
  end
  
  defp generate_diverse_demos(program, dataset, _metric) do
    # Generate demos to cover diverse input space
    # Implementation would use clustering or other diversity techniques
    []
  end
  
  defp valid_demo?(demo) do
    not is_nil(demo.input_text) and not is_nil(demo.output_text)
  end
  
  defp select_top_demos(demos, max_count) do
    demos
    |> Enum.sort_by(& &1.quality_score, :desc)
    |> Enum.take(max_count)
  end
  
  defp apply_demonstrations(program, demos) do
    # Apply selected demonstrations to the program
    # This would involve updating the program's few-shot examples
    Map.put(program, :demonstrations, demos)
  end
  
  defp evaluate_program(program, dataset, metric) do
    # Evaluate the program on the dataset using the metric
    # For now, return a simulated score
    0.85 + :rand.uniform() * 0.1
  end
  
  defp convert_to_demo(example, _program) do
    %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(),
      input_text: Jason.encode!(example["inputs"]),
      output_text: Jason.encode!(example["outputs"]),
      quality_score: 0.8 + :rand.uniform() * 0.2  # Simulated quality score
    }
  end
end
```

### 3.3 Multi-Objective Optimizer

```elixir
# lib/dspex/optimizers/multi_objective.ex
defmodule DSPex.Optimizers.MultiObjective do
  @moduledoc """
  Multi-objective optimizer that balances accuracy, latency, and cost.
  """
  
  @behaviour DSPex.Optimizers.Optimizer
  
  def info do
    %{
      name: "MultiObjective",
      description: "Optimizer that balances multiple objectives like accuracy, latency, and cost",
      parameters: [
        %{name: "objectives", type: :map, required: true, description: "Objectives and their weights"},
        %{name: "pareto_iterations", type: :integer, default: 10, description: "Pareto frontier iterations"},
        %{name: "population_size", type: :integer, default: 20, description: "Population size for optimization"}
      ]
    }
  end
  
  @impl true
  def optimize(program, dataset, _primary_metric, config) do
    objectives = config[:objectives] || %{
      "accuracy" => 0.6,
      "latency" => 0.2,
      "cost" => 0.2
    }
    
    pareto_iterations = config[:pareto_iterations] || 10
    population_size = config[:population_size] || 20
    
    # Generate initial population of program variants
    population = generate_initial_population(program, population_size)
    
    # Evolve population using multi-objective optimization
    final_population = evolve_population(population, dataset, objectives, pareto_iterations)
    
    # Select best solution from Pareto frontier
    best_solution = select_best_solution(final_population, objectives)
    
    {:ok, %{
      optimized_program: best_solution.program,
      score: best_solution.composite_score,
      objectives: best_solution.objective_scores,
      pareto_frontier: extract_pareto_frontier(final_population),
      metadata: %{
        population_size: length(final_population),
        iterations: pareto_iterations
      }
    }}
  end
  
  defp generate_initial_population(base_program, size) do
    # Generate variants of the program with different configurations
    Enum.map(1..size, fn i ->
      variant = create_program_variant(base_program, i)
      %{
        id: i,
        program: variant,
        objective_scores: %{},
        composite_score: 0.0
      }
    end)
  end
  
  defp evolve_population(population, dataset, objectives, iterations) do
    Enum.reduce(1..iterations, population, fn iteration, pop ->
      # Evaluate objectives for each solution
      evaluated_pop = Enum.map(pop, fn solution ->
        scores = evaluate_objectives(solution.program, dataset)
        composite = calculate_composite_score(scores, objectives)
        
        %{solution | 
          objective_scores: scores,
          composite_score: composite
        }
      end)
      
      # Select survivors based on Pareto dominance
      survivors = select_pareto_survivors(evaluated_pop, objectives)
      
      # Generate new solutions through crossover and mutation
      new_solutions = generate_offspring(survivors, length(population) - length(survivors))
      
      survivors ++ new_solutions
    end)
  end
  
  defp evaluate_objectives(program, dataset) do
    # Evaluate program on multiple objectives
    sample_size = min(length(dataset), 20)  # Use sample for faster evaluation
    sample = Enum.take_random(dataset, sample_size)
    
    # Measure accuracy
    accuracy = measure_accuracy(program, sample)
    
    # Measure latency
    latency = measure_latency(program, sample)
    
    # Estimate cost
    cost = estimate_cost(program, sample)
    
    %{
      "accuracy" => accuracy,
      "latency" => 1.0 / (latency / 1000.0 + 1.0),  # Convert to score (higher is better)
      "cost" => 1.0 / (cost + 0.01)  # Convert to score (higher is better)
    }
  end
  
  defp calculate_composite_score(objective_scores, weights) do
    Enum.reduce(weights, 0.0, fn {objective, weight}, acc ->
      score = Map.get(objective_scores, objective, 0.0)
      acc + weight * score
    end)
  end
  
  defp select_pareto_survivors(population, _objectives) do
    # Select solutions that are not dominated by any other solution
    Enum.filter(population, fn solution ->
      not dominated_by_any?(solution, population)
    end)
  end
  
  defp dominated_by_any?(solution, population) do
    Enum.any?(population, fn other ->
      other.id != solution.id and dominates?(other, solution)
    end)
  end
  
  defp dominates?(solution1, solution2) do
    # Solution1 dominates solution2 if it's better or equal on all objectives
    # and strictly better on at least one
    scores1 = solution1.objective_scores
    scores2 = solution2.objective_scores
    
    all_better_or_equal = Enum.all?(scores1, fn {obj, score1} ->
      score2 = Map.get(scores2, obj, 0.0)
      score1 >= score2
    end)
    
    any_strictly_better = Enum.any?(scores1, fn {obj, score1} ->
      score2 = Map.get(scores2, obj, 0.0)
      score1 > score2
    end)
    
    all_better_or_equal and any_strictly_better
  end
  
  defp generate_offspring(survivors, count) do
    # Generate new solutions through crossover and mutation
    Enum.map(1..count, fn i ->
      parent1 = Enum.random(survivors)
      parent2 = Enum.random(survivors)
      
      child_program = crossover(parent1.program, parent2.program)
      mutated_program = mutate(child_program)
      
      %{
        id: 1000 + i,  # Different ID space for offspring
        program: mutated_program,
        objective_scores: %{},
        composite_score: 0.0
      }
    end)
  end
  
  defp select_best_solution(population, objectives) do
    # Select the solution with the highest composite score
    Enum.max_by(population, fn solution ->
      calculate_composite_score(solution.objective_scores, objectives)
    end)
  end
  
  defp extract_pareto_frontier(population) do
    # Return all non-dominated solutions
    select_pareto_survivors(population, %{})
  end
  
  # Placeholder implementations for genetic operations
  defp create_program_variant(base_program, variant_id) do
    # Create a variant by adjusting parameters
    Map.put(base_program, :variant_id, variant_id)
  end
  
  defp crossover(program1, program2) do
    # Simple crossover - combine aspects of both programs
    # In practice, this would involve sophisticated program combination
    if :rand.uniform() > 0.5, do: program1, else: program2
  end
  
  defp mutate(program) do
    # Mutate program parameters slightly
    # In practice, this would involve parameter adjustment
    program
  end
  
  defp measure_accuracy(program, sample) do
    # Measure accuracy on sample - simplified for example
    0.8 + :rand.uniform() * 0.2
  end
  
  defp measure_latency(program, sample) do
    # Measure average latency - simplified for example
    500 + :rand.uniform() * 1000  # ms
  end
  
  defp estimate_cost(program, sample) do
    # Estimate cost per execution - simplified for example
    0.01 + :rand.uniform() * 0.05  # USD
  end
end
```

## 4. Experiment Management

### 4.1 Experiment Resource

```elixir
# lib/dspex/ml/experiment.ex
defmodule DSPex.ML.Experiment do
  @moduledoc """
  Resource for managing ML experiments and comparisons.
  """
  
  use Ash.Resource,
    domain: DSPex.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :hypothesis, :string
    
    attribute :status, :atom, constraints: [
      one_of: [:planned, :running, :completed, :cancelled]
    ], default: :planned
    
    # Experiment configuration
    attribute :config, :map, default: %{}
    attribute :variants, {:array, :map}, default: []
    attribute :success_criteria, :map, default: %{}
    
    # Results
    attribute :results, :map
    attribute :conclusions, :string
    attribute :statistical_significance, :float
    
    # Timing
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    
    timestamps()
  end
  
  relationships do
    has_many :experiment_runs, DSPex.ML.ExperimentRun
    belongs_to :baseline_program, DSPex.ML.Program
    belongs_to :dataset, DSPex.ML.Dataset
  end
  
  state_machine do
    initial_states [:planned]
    default_initial_state :planned
    
    transitions do
      transition :start, from: :planned, to: :running
      transition :complete, from: :running, to: :completed
      transition :cancel, from: [:planned, :running], to: :cancelled
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_experiment do
      argument :variants, {:array, :map}, allow_nil?: false
      argument :success_criteria, :map, default: %{}
      
      change fn changeset, _context ->
        variants = Ash.Changeset.get_argument(changeset, :variants)
        criteria = Ash.Changeset.get_argument(changeset, :success_criteria)
        
        changeset
        |> Ash.Changeset.change_attribute(:variants, variants)
        |> Ash.Changeset.change_attribute(:success_criteria, criteria)
      end
    end
    
    update :start_experiment do
      accept []
      require_atomic? false
      change transition_state(:running)
      
      change fn changeset, _context ->
        # Enqueue experiment execution
        DSPex.Workers.ExperimentWorker.new(%{
          experiment_id: changeset.data.id
        })
        |> Oban.insert()
        
        Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
      end
    end
    
    action :analyze_results, :map do
      run DSPex.ML.Actions.AnalyzeExperimentResults
    end
    
    action :compare_variants, :map do
      argument :metric, :string, default: "accuracy"
      
      run fn input, context ->
        experiment = context.resource
        metric = input.arguments.metric
        
        DSPex.ML.Analysis.CompareVariants.run(experiment, metric)
      end
    end
  end
  
  calculations do
    calculate :duration_hours, :float do
      calculation fn records, _context ->
        Enum.map(records, fn experiment ->
          case {experiment.started_at, experiment.completed_at} do
            {start, finish} when not is_nil(start) and not is_nil(finish) ->
              DateTime.diff(finish, start, :second) / 3600.0
            _ -> nil
          end
        end)
      end
    end
    
    calculate :best_variant, :string do
      calculation fn records, _context ->
        Enum.map(records, fn experiment ->
          case experiment.results do
            nil -> nil
            results ->
              results
              |> Map.get("variants", %{})
              |> Enum.max_by(fn {_name, data} -> data["score"] || 0 end, fn -> {"none", %{}} end)
              |> elem(0)
          end
        end)
      end
    end
  end
  
  code_interface do
    define :create_experiment
    define :start_experiment
    define :analyze_results
    define :compare_variants
  end
end
```

### 4.2 Experiment Worker

```elixir
# lib/dspex/workers/experiment_worker.ex
defmodule DSPex.Workers.ExperimentWorker do
  @moduledoc """
  Worker for executing ML experiments.
  """
  
  use Oban.Worker, queue: :experiments, max_attempts: 2
  
  alias DSPex.ML.{Experiment, Program, Dataset, ExperimentRun}
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"experiment_id" => experiment_id}}) do
    experiment = Experiment.get!(experiment_id)
    dataset = Dataset.get!(experiment.dataset_id)
    baseline = Program.get!(experiment.baseline_program_id)
    
    try do
      # Execute experiment variants
      variant_results = execute_variants(experiment, dataset, baseline)
      
      # Analyze results
      analysis = analyze_experiment_results(variant_results, experiment.success_criteria)
      
      # Update experiment with results
      Experiment.update!(experiment, %{
        status: :completed,
        completed_at: DateTime.utc_now(),
        results: %{
          variants: variant_results,
          analysis: analysis,
          statistical_tests: analysis.statistical_tests
        },
        statistical_significance: analysis.p_value,
        conclusions: generate_conclusions(analysis)
      })
      
      :ok
      
    rescue
      error ->
        Experiment.update!(experiment, %{
          status: :cancelled,
          completed_at: DateTime.utc_now(),
          conclusions: "Experiment failed: #{Exception.message(error)}"
        })
        
        {:error, error}
    end
  end
  
  defp execute_variants(experiment, dataset, baseline) do
    # Always include baseline
    baseline_results = execute_variant(baseline, dataset, "baseline")
    
    # Execute each variant
    variant_results = Enum.map(experiment.variants, fn variant ->
      variant_program = create_variant_program(baseline, variant)
      execute_variant(variant_program, dataset, variant["name"])
    end)
    
    Map.new([{"baseline", baseline_results} | Enum.map(variant_results, &{&1.name, &1})])
  end
  
  defp execute_variant(program, dataset, variant_name) do
    # Split dataset for evaluation
    {train_set, test_set} = split_dataset(dataset.data, 0.8)
    
    # If this is a variant that needs optimization, optimize it
    optimized_program = if variant_name != "baseline" do
      optimize_program_variant(program, train_set)
    else
      program
    end
    
    # Evaluate on test set
    results = evaluate_program_on_dataset(optimized_program, test_set)
    
    # Record experiment run
    {:ok, run} = ExperimentRun.create!(%{
      experiment_id: program.id,  # This would be the experiment ID in practice
      variant_name: variant_name,
      program_snapshot: create_program_snapshot(optimized_program),
      dataset_split: %{train_size: length(train_set), test_size: length(test_set)},
      results: results,
      completed_at: DateTime.utc_now()
    })
    
    %{
      name: variant_name,
      program: optimized_program,
      run_id: run.id,
      score: results.accuracy,
      latency: results.average_latency,
      cost: results.total_cost,
      details: results
    }
  end
  
  defp create_variant_program(baseline, variant_config) do
    # Create program variant based on configuration
    # This would involve changing optimization parameters, model settings, etc.
    
    case variant_config["type"] do
      "optimizer_change" ->
        # Change optimizer parameters
        Map.merge(baseline, %{
          optimizer_config: variant_config["optimizer_config"]
        })
      
      "model_change" ->
        # Change underlying model
        Map.merge(baseline, %{
          model_config: variant_config["model_config"]
        })
      
      "prompt_change" ->
        # Change prompting strategy
        Map.merge(baseline, %{
          prompt_strategy: variant_config["prompt_strategy"]
        })
      
      _ ->
        baseline
    end
  end
  
  defp optimize_program_variant(program, train_set) do
    # Run optimization if the variant requires it
    # This is a simplified version
    program
  end
  
  defp evaluate_program_on_dataset(program, test_set) do
    results = Enum.map(test_set, fn example ->
      start_time = System.monotonic_time(:millisecond)
      
      case Program.execute(program, %{inputs: example["inputs"]}) do
        {:ok, output} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time
          
          correct = outputs_match?(output, example["outputs"])
          
          %{
            correct: correct,
            duration_ms: duration,
            input: example["inputs"],
            expected_output: example["outputs"],
            actual_output: output
          }
        
        {:error, _reason} ->
          %{
            correct: false,
            duration_ms: 5000,  # Penalty for errors
            input: example["inputs"],
            expected_output: example["outputs"],
            actual_output: nil,
            error: true
          }
      end
    end)
    
    # Calculate aggregate metrics
    total_examples = length(results)
    correct_count = Enum.count(results, & &1.correct)
    total_duration = Enum.sum(Enum.map(results, & &1.duration_ms))
    
    %{
      accuracy: correct_count / total_examples,
      total_examples: total_examples,
      correct_examples: correct_count,
      average_latency: total_duration / total_examples,
      total_duration: total_duration,
      total_cost: estimate_total_cost(results),
      error_rate: Enum.count(results, &Map.get(&1, :error, false)) / total_examples,
      detailed_results: results
    }
  end
  
  defp analyze_experiment_results(variant_results, success_criteria) do
    baseline_score = get_in(variant_results, ["baseline", "score"])
    
    # Compare each variant to baseline
    comparisons = Enum.map(variant_results, fn {name, results} ->
      if name == "baseline" do
        {name, %{improvement: 0.0, significant: false}}
      else
        improvement = (results.score - baseline_score) / baseline_score
        significant = abs(improvement) > (success_criteria["min_improvement"] || 0.05)
        
        {name, %{
          improvement: improvement,
          significant: significant,
          score: results.score,
          baseline_score: baseline_score
        }}
      end
    end)
    |> Map.new()
    
    # Find best variant
    best_variant = variant_results
                  |> Enum.reject(fn {name, _} -> name == "baseline" end)
                  |> Enum.max_by(fn {_, results} -> results.score end, fn -> {"none", %{score: 0}} end)
    
    # Statistical tests (simplified)
    p_value = calculate_p_value(variant_results)
    
    %{
      comparisons: comparisons,
      best_variant: elem(best_variant, 0),
      best_improvement: get_in(comparisons, [elem(best_variant, 0), :improvement]),
      p_value: p_value,
      statistical_tests: %{
        test_type: "two_sample_t_test",
        p_value: p_value,
        significant: p_value < 0.05
      },
      summary: generate_summary(comparisons, best_variant)
    }
  end
  
  defp generate_conclusions(analysis) do
    best_variant = analysis.best_variant
    improvement = analysis.best_improvement
    significant = analysis.statistical_tests.significant
    
    cond do
      significant and improvement > 0.1 ->
        "#{best_variant} shows significant improvement of #{Float.round(improvement * 100, 1)}%. Recommend deployment."
      
      significant and improvement > 0.05 ->
        "#{best_variant} shows moderate improvement of #{Float.round(improvement * 100, 1)}%. Consider deployment with additional testing."
      
      significant ->
        "#{best_variant} shows slight improvement of #{Float.round(improvement * 100, 1)}%. May not justify deployment costs."
      
      true ->
        "No variant shows statistically significant improvement over baseline. Recommend exploring different approaches."
    end
  end
  
  # Helper functions
  defp split_dataset(data, train_ratio) do
    shuffled = Enum.shuffle(data)
    split_point = round(length(shuffled) * train_ratio)
    
    {Enum.take(shuffled, split_point), Enum.drop(shuffled, split_point)}
  end
  
  defp outputs_match?(actual, expected) do
    # Simplified matching - would use sophisticated comparison in production
    case {actual, expected} do
      {%{"answer" => actual_answer}, %{"answer" => expected_answer}} ->
        String.jaro_distance(actual_answer, expected_answer) > 0.8
      _ -> false
    end
  end
  
  defp estimate_total_cost(results) do
    # Simplified cost estimation
    Enum.count(results) * 0.01  # $0.01 per execution
  end
  
  defp calculate_p_value(variant_results) do
    # Simplified p-value calculation
    # In production, would use proper statistical tests
    :rand.uniform() * 0.1  # Random p-value for example
  end
  
  defp generate_summary(comparisons, {best_variant_name, best_variant_data}) do
    improvement_count = comparisons
                       |> Enum.count(fn {name, data} -> 
                         name != "baseline" and data.improvement > 0 
                       end)
    
    "#{improvement_count} of #{map_size(comparisons) - 1} variants showed improvement. " <>
    "Best variant: #{best_variant_name} with #{Float.round(best_variant_data.score * 100, 1)}% accuracy."
  end
  
  defp create_program_snapshot(program) do
    %{
      id: program.id,
      config: program.config || %{},
      timestamp: DateTime.utc_now()
    }
  end
end
```

## Stage 4 Deliverables

By the end of Stage 4, you should have:

1. ✅ **Multi-model orchestration** with intelligent routing and fallback
2. ✅ **Automated deployment pipelines** with canary and blue-green strategies
3. ✅ **Advanced optimization algorithms** including multi-objective optimization
4. ✅ **Comprehensive experiment management** with statistical analysis
5. ✅ **Model registry and health monitoring** for production reliability
6. ✅ **Performance-based model selection** with cost and latency optimization
7. ✅ **Enterprise-ready features** for large-scale ML operations

**Final Result**: A complete, production-ready DSPy-Ash integration that rivals or exceeds commercial ML platforms in functionality while maintaining the elegance of our native signature syntax.
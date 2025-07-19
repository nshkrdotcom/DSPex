# Task: PIPELINE.1 - Basic Pipeline Engine

## Context
You are implementing the basic pipeline engine that orchestrates sequences of DSPex operations. This engine enables users to chain multiple operations together with automatic data flow and error handling.

## Required Reading

### 1. Pipeline Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/pipeline.ex`
  - Current pipeline structure
  - Execution patterns

### 2. Pipeline Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/02_CORE_COMPONENTS_DETAILED.md`
  - Section: "Component 5: Pipeline Orchestration Engine"
  - Stage execution patterns

### 3. libStaging Pipeline Patterns
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 191-206: Pipeline orchestration patterns
  - Stage definition and execution

### 4. Success Criteria
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Stage 7: Pipeline tests and examples

### 5. Router Integration
- **File**: Previous prompt ROUTER.1
  - How router decisions affect pipeline execution

## Implementation Requirements

### Pipeline Structure
```elixir
defmodule DSPex.Pipeline do
  use GenServer
  
  @moduledoc """
  Orchestrates sequential execution of DSPex operations.
  Supports:
  - Sequential stages
  - Data transformation between stages
  - Error handling and recovery
  - Execution tracking
  """
  
  defstruct [
    :id,
    :stages,
    :context,
    :current_stage,
    :results,
    :status,
    :started_at,
    :completed_at,
    :options
  ]
  
  defmodule Stage do
    defstruct [
      :id,
      :type,              # :operation | :transform | :validate
      :operation,         # DSPex operation name
      :config,           # Stage configuration
      :input_mapping,    # How to extract input from context
      :output_key,       # Where to store output in context
      :error_handler,    # Optional error handling
      :timeout          # Stage-specific timeout
    ]
  end
end
```

### Pipeline Builder API
```elixir
defmodule DSPex.Pipeline.Builder do
  @moduledoc """
  Fluent API for building pipelines
  """
  
  def new(opts \\ []) do
    %DSPex.Pipeline{
      id: generate_id(),
      stages: [],
      context: %{},
      status: :pending,
      options: opts
    }
  end
  
  def add_stage(pipeline, operation, config \\ %{}) do
    stage = %Stage{
      id: "stage_#{length(pipeline.stages) + 1}",
      type: :operation,
      operation: operation,
      config: config,
      input_mapping: config[:input_mapping] || :auto,
      output_key: config[:output_key] || operation,
      timeout: config[:timeout]
    }
    
    %{pipeline | stages: pipeline.stages ++ [stage]}
  end
  
  def add_transform(pipeline, transform_fn, opts \\ []) do
    stage = %Stage{
      id: "transform_#{length(pipeline.stages) + 1}",
      type: :transform,
      operation: transform_fn,
      config: opts,
      output_key: opts[:output_key]
    }
    
    %{pipeline | stages: pipeline.stages ++ [stage]}
  end
  
  def add_validator(pipeline, validator_fn, opts \\ []) do
    stage = %Stage{
      id: "validate_#{length(pipeline.stages) + 1}",
      type: :validate,
      operation: validator_fn,
      config: opts,
      error_handler: opts[:on_error]
    }
    
    %{pipeline | stages: pipeline.stages ++ [stage]}
  end
  
  def with_context(pipeline, context) do
    %{pipeline | context: Map.merge(pipeline.context, context)}
  end
end
```

### Pipeline Execution Engine
```elixir
defmodule DSPex.Pipeline.Executor do
  def execute(pipeline, input \\ %{}) do
    # Initialize execution context
    context = Map.merge(pipeline.context, %{input: input})
    
    # Start execution
    pipeline = %{pipeline | 
      status: :running,
      started_at: DateTime.utc_now(),
      results: %{}
    }
    
    # Execute stages sequentially
    result = pipeline.stages
    |> Enum.reduce_while({:ok, context, pipeline}, &execute_stage/2)
    
    case result do
      {:ok, final_context, final_pipeline} ->
        completed_pipeline = %{final_pipeline |
          status: :completed,
          completed_at: DateTime.utc_now()
        }
        {:ok, final_context, completed_pipeline}
        
      {:error, reason, failed_pipeline} ->
        error_pipeline = %{failed_pipeline |
          status: :failed,
          completed_at: DateTime.utc_now()
        }
        {:error, reason, error_pipeline}
    end
  end
  
  defp execute_stage(stage, {:ok, context, pipeline}) do
    start_time = System.monotonic_time(:millisecond)
    
    # Extract input for stage
    stage_input = extract_stage_input(stage, context)
    
    # Execute based on stage type
    result = case stage.type do
      :operation ->
        execute_operation(stage, stage_input)
        
      :transform ->
        execute_transform(stage, stage_input)
        
      :validate ->
        execute_validation(stage, stage_input)
    end
    
    # Record execution time
    duration = System.monotonic_time(:millisecond) - start_time
    
    case result do
      {:ok, output} ->
        # Update context with output
        new_context = store_stage_output(stage, output, context)
        
        # Update pipeline results
        updated_pipeline = update_pipeline_results(pipeline, stage, %{
          status: :success,
          output: output,
          duration: duration
        })
        
        # Emit telemetry
        emit_stage_completed(stage, duration, :success)
        
        {:cont, {:ok, new_context, updated_pipeline}}
        
      {:error, reason} ->
        # Try error handler if available
        case handle_stage_error(stage, reason, context) do
          {:recover, recovery_value} ->
            new_context = store_stage_output(stage, recovery_value, context)
            updated_pipeline = update_pipeline_results(pipeline, stage, %{
              status: :recovered,
              error: reason,
              recovery: recovery_value,
              duration: duration
            })
            {:cont, {:ok, new_context, updated_pipeline}}
            
          :halt ->
            updated_pipeline = update_pipeline_results(pipeline, stage, %{
              status: :failed,
              error: reason,
              duration: duration
            })
            emit_stage_completed(stage, duration, :failed)
            {:halt, {:error, reason, updated_pipeline}}
        end
    end
  end
end
```

### Operation Execution
```elixir
defp execute_operation(stage, input) do
  # Route through DSPex
  case DSPex.Router.route(stage.operation, input, stage.config) do
    {:ok, route} ->
      # Execute with timeout
      timeout = stage.timeout || route.timeout || 30_000
      
      Task.async(fn ->
        case route.implementation do
          :native ->
            apply(route.module, :execute, [input, stage.config])
            
          :python ->
            DSPex.Python.Snakepit.execute(
              route.pool_type,
              "execute_module",
              %{
                module: stage.operation,
                inputs: input,
                config: stage.config
              },
              timeout: timeout
            )
        end
      end)
      |> Task.await(timeout)
      
    {:error, reason} ->
      {:error, {:routing_failed, reason}}
  end
rescue
  e in Task.TimeoutError ->
    {:error, {:timeout, stage.id}}
end
```

### Input/Output Mapping
```elixir
defp extract_stage_input(stage, context) do
  case stage.input_mapping do
    :auto ->
      # Use the output from the previous stage or initial input
      Map.get(context, :last_output, context.input)
      
    key when is_atom(key) ->
      # Use specific key from context
      Map.get(context, key)
      
    keys when is_list(keys) ->
      # Extract multiple keys
      Map.take(context, keys)
      
    mapper when is_function(mapper, 1) ->
      # Custom mapping function
      mapper.(context)
  end
end

defp store_stage_output(stage, output, context) do
  context
  |> Map.put(:last_output, output)
  |> Map.put(stage.output_key || stage.id, output)
end
```

### Error Handling
```elixir
defp handle_stage_error(stage, error, context) do
  case stage.error_handler do
    nil ->
      :halt
      
    :skip ->
      {:recover, nil}
      
    :use_default ->
      {:recover, get_default_value(stage)}
      
    handler when is_function(handler, 2) ->
      case handler.(error, context) do
        {:recover, value} -> {:recover, value}
        :retry -> retry_stage(stage, context)
        :halt -> :halt
      end
  end
end
```

## Acceptance Criteria
- [ ] Sequential pipeline execution works
- [ ] Data flows correctly between stages
- [ ] Input/output mapping is flexible
- [ ] Error handling with recovery options
- [ ] Timeout handling per stage
- [ ] Pipeline status tracking
- [ ] Telemetry events for monitoring
- [ ] Builder API is intuitive
- [ ] Results are accessible after execution

## Testing Requirements
Create tests in:
- `test/dspex/pipeline_test.exs`
- `test/dspex/pipeline/executor_test.exs`

Test scenarios:
- Simple multi-stage pipeline
- Data transformation between stages
- Error handling and recovery
- Timeout handling
- Custom input/output mapping
- Pipeline status transitions
- Empty pipeline handling

## Example Usage
```elixir
# Build a pipeline
pipeline = DSPex.Pipeline.Builder.new()
|> add_stage("extract_entities", %{
  model: "gpt-3.5-turbo",
  output_key: :entities
})
|> add_transform(fn ctx ->
  # Filter only person entities
  Enum.filter(ctx.entities, & &1.type == "person")
end, output_key: :people)
|> add_stage("summarize", %{
  input_mapping: fn ctx -> 
    %{text: "People found: #{Enum.join(ctx.people, ", ")}"}
  end
})
|> add_validator(fn ctx ->
  if ctx.summary != "", do: :ok, else: {:error, "Empty summary"}
end)
|> with_context(%{user_id: "123"})

# Execute pipeline
{:ok, result, completed_pipeline} = DSPex.Pipeline.execute(pipeline, %{
  text: "John met Sarah at the conference in Paris."
})

# Access results
result.entities  # All entities
result.people    # ["John", "Sarah"]
result.summary   # "People found: John, Sarah"

# Check execution details
completed_pipeline.results["stage_1"].duration  # 234ms
completed_pipeline.status  # :completed
```

## Dependencies
- Requires Router (ROUTER.1) for operation routing
- Uses telemetry for monitoring
- Integrates with all DSPex operations

## Time Estimate
8 hours total:
- 2 hours: Core pipeline structure
- 2 hours: Execution engine
- 1 hour: Builder API
- 1 hour: Input/output mapping
- 1 hour: Error handling
- 1 hour: Testing

## Notes
- Keep stages simple in this version
- Focus on sequential execution first
- Make data flow explicit and debuggable
- Consider stage result caching
- Plan for parallel execution later
- Add pipeline visualization helpers
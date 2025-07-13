# Stage 1 Prompt 6: Manual Actions for ML Operations

## OBJECTIVE

Implement sophisticated manual actions that leverage Ash's manual action capabilities to handle complex ML workflows, program execution lifecycle, signature validation, and advanced operations that require custom logic beyond standard CRUD operations. These manual actions must integrate seamlessly with the adapter pattern, type system, and provide robust error handling for ML-specific scenarios.

## COMPLETE IMPLEMENTATION CONTEXT

### MANUAL ACTIONS ARCHITECTURE OVERVIEW

From ashDocs/documentation/topics/actions/manual-actions.md:

**Manual Action Philosophy:**
- Manual actions provide escape hatch for complex custom logic
- Full control over action execution vs data layer dispatch
- Integration with Ash resource lifecycle and validation
- Custom business logic implementation
- Complex workflow orchestration

**Manual Action Types:**
```elixir
# Manual Create/Update/Destroy
defmodule MyApp.DoCreate do
  use Ash.Resource.ManualCreate

  def create(changeset, _, _) do
    record = create_the_record(changeset)
    {:ok, record}
  end
end

# Manual Read
defmodule MyApp.ManualRead do
  use Ash.Resource.ManualRead

  def read(ash_query, ecto_query, _opts, _context) do
    {:ok, query_results} | {:error, error}
  end
end
```

### ML-SPECIFIC MANUAL ACTION REQUIREMENTS

From DSPy-Ash integration architecture:

**ML Workflow Complexities:**
- Multi-step program execution with state tracking
- Signature validation with dynamic type checking
- Adapter coordination and fallback handling
- Performance monitoring and metrics collection
- Error recovery and retry mechanisms
- Resource cleanup and lifecycle management

**Required Manual Actions:**
1. **Program Execution** - Complex ML program execution with full lifecycle
2. **Signature Validation** - Deep signature compatibility checking
3. **Adapter Coordination** - Multi-adapter execution and failover
4. **Batch Processing** - Efficient batch execution of ML operations
5. **Resource Cleanup** - Comprehensive resource and state cleanup
6. **Health Monitoring** - System health checks and diagnostics

### COMPLETE PROGRAM EXECUTION MANUAL ACTION

**Comprehensive Program Execution Implementation:**
```elixir
defmodule AshDSPy.ML.Actions.ProgramExecution do
  @moduledoc """
  Manual action for executing ML programs with comprehensive lifecycle management,
  performance tracking, error handling, and resource cleanup.
  """
  
  use Ash.Resource.ManualCreate
  
  alias AshDSPy.ML.{Program, Execution}
  alias AshDSPy.Adapters.{Registry, Factory, ErrorHandler}
  alias AshDSPy.Types.Validator
  
  def create(changeset, _opts, context) do
    program_id = Ash.Changeset.get_argument(changeset, :program_id)
    inputs = Ash.Changeset.get_argument(changeset, :inputs)
    execution_options = Ash.Changeset.get_argument(changeset, :execution_options) || %{}
    
    with {:ok, program} <- load_and_validate_program(program_id),
         {:ok, validated_inputs} <- validate_program_inputs(program, inputs),
         {:ok, execution_record} <- create_execution_record(program, validated_inputs, execution_options),
         {:ok, result} <- execute_with_full_lifecycle(program, validated_inputs, execution_options, execution_record) do
      {:ok, result}
    else
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Program execution failed with exception: #{inspect(error)}")
      {:error, "Execution failed: #{inspect(error)}"}
  end
  
  defp load_and_validate_program(program_id) do
    case Program.get(program_id) do
      {:ok, program} ->
        case program.status do
          :ready ->
            {:ok, program}
          :error ->
            {:error, "Program is in error state: #{program.error_message}"}
          status ->
            {:error, "Program not ready for execution (status: #{status})"}
        end
      
      {:error, reason} ->
        {:error, "Failed to load program: #{inspect(reason)}"}
    end
  end
  
  defp validate_program_inputs(program, inputs) do
    signature_module = String.to_existing_atom(program.signature.module)
    
    case signature_module.validate_inputs(inputs) do
      {:ok, validated} ->
        {:ok, validated}
      
      {:error, validation_error} ->
        {:error, "Input validation failed: #{validation_error}"}
    end
  end
  
  defp create_execution_record(program, inputs, options) do
    metadata = %{
      adapter_type: program.adapter_type,
      options: options,
      signature_module: program.signature.module,
      program_name: program.name
    }
    
    Execution.create_execution(%{
      program_id: program.id,
      inputs: inputs,
      metadata: metadata
    })
  end
  
  defp execute_with_full_lifecycle(program, inputs, options, execution_record) do
    start_time = System.monotonic_time(:millisecond)
    
    # Mark execution as running
    {:ok, execution_record} = Execution.mark_running(execution_record)
    
    # Get adapter and configure execution
    adapter = Registry.get_adapter(program.adapter_type)
    execution_opts = prepare_execution_options(options)
    
    try do
      # Execute with timeout and retry logic
      case execute_with_resilience(adapter, program, inputs, execution_opts) do
        {:ok, outputs} ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Validate outputs against signature
          case validate_program_outputs(program, outputs) do
            {:ok, validated_outputs} ->
              # Mark execution as completed
              {:ok, execution_record} = Execution.mark_completed(execution_record, %{
                outputs: validated_outputs,
                duration_ms: duration
              })
              
              # Update program statistics
              update_program_stats(program, duration, :success)
              
              {:ok, %{
                execution_id: execution_record.id,
                outputs: validated_outputs,
                duration_ms: duration,
                status: :completed,
                program_id: program.id
              }}
            
            {:error, validation_error} ->
              duration = System.monotonic_time(:millisecond) - start_time
              error_msg = "Output validation failed: #{validation_error}"
              
              {:ok, _} = Execution.mark_failed(execution_record, %{
                error_message: error_msg,
                duration_ms: duration
              })
              
              update_program_stats(program, duration, :validation_error)
              {:error, error_msg}
          end
        
        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          error_msg = format_execution_error(reason)
          
          {:ok, _} = Execution.mark_failed(execution_record, %{
            error_message: error_msg,
            duration_ms: duration
          })
          
          update_program_stats(program, duration, :execution_error)
          {:error, error_msg}
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        error_msg = "Execution exception: #{inspect(error)}"
        
        {:ok, _} = Execution.mark_failed(execution_record, %{
          error_message: error_msg,
          duration_ms: duration
        })
        
        update_program_stats(program, duration, :exception)
        {:error, error_msg}
    end
  end
  
  defp prepare_execution_options(options) do
    default_options = %{
      timeout: 30_000,
      max_retries: 2,
      retry_delay: 1000
    }
    
    Map.merge(default_options, options)
  end
  
  defp execute_with_resilience(adapter, program, inputs, options) do
    timeout = Map.get(options, :timeout, 30_000)
    max_retries = Map.get(options, :max_retries, 2)
    
    execute_with_retry(adapter, program.dspy_program_id, inputs, max_retries, timeout)
  end
  
  defp execute_with_retry(adapter, program_id, inputs, retries_left, timeout) do
    case Factory.execute_with_adapter(
           adapter,
           :execute_program,
           [program_id, inputs],
           timeout: timeout
         ) do
      {:ok, result} ->
        {:ok, result}
      
      {:error, error} ->
        wrapped_error = ErrorHandler.wrap_error(error)
        
        if retries_left > 0 and ErrorHandler.should_retry?(wrapped_error) do
          delay = ErrorHandler.get_retry_delay(wrapped_error) || 1000
          Process.sleep(delay)
          execute_with_retry(adapter, program_id, inputs, retries_left - 1, timeout)
        else
          {:error, wrapped_error}
        end
    end
  end
  
  defp validate_program_outputs(program, outputs) do
    signature_module = String.to_existing_atom(program.signature.module)
    
    case signature_module.validate_outputs(outputs) do
      {:ok, validated} ->
        {:ok, validated}
      
      {:error, validation_error} ->
        {:error, validation_error}
    end
  end
  
  defp update_program_stats(program, duration, outcome) do
    # Update program execution statistics
    Task.start(fn ->
      Program.update(program, %{
        execution_count: program.execution_count + 1,
        last_executed_at: DateTime.utc_now()
      })
      
      # Record metrics
      record_execution_metrics(program, duration, outcome)
    end)
  end
  
  defp record_execution_metrics(program, duration, outcome) do
    # This could integrate with telemetry or metrics collection
    :telemetry.execute(
      [:ash_dspy, :program, :execution],
      %{duration: duration},
      %{
        program_id: program.id,
        adapter_type: program.adapter_type,
        outcome: outcome,
        signature_module: program.signature.module
      }
    )
  end
  
  defp format_execution_error(error) do
    case error do
      %AshDSPy.Adapters.ErrorHandler{message: message} ->
        message
      
      {:timeout, _} ->
        "Execution timed out"
      
      {:connection_failed, _} ->
        "Failed to connect to execution backend"
      
      other ->
        "Execution failed: #{inspect(other)}"
    end
  end
end
```

### SIGNATURE VALIDATION MANUAL ACTION

**Deep Signature Validation Implementation:**
```elixir
defmodule AshDSPy.ML.Actions.SignatureValidation do
  @moduledoc """
  Manual action for comprehensive signature validation including module loading,
  type checking, constraint validation, and compatibility verification.
  """
  
  use Ash.Resource.ManualRead
  
  alias AshDSPy.Types.{Registry, Validator}
  
  def read(ash_query, _ecto_query, _opts, _context) do
    signature_module = Ash.Query.get_argument(ash_query, :signature_module)
    validation_level = Ash.Query.get_argument(ash_query, :validation_level) || :standard
    
    case perform_comprehensive_validation(signature_module, validation_level) do
      {:ok, validation_results} ->
        {:ok, [validation_results]}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp perform_comprehensive_validation(signature_module, validation_level) do
    validation_steps = [
      {:module_loading, &validate_module_loading/1},
      {:signature_structure, &validate_signature_structure/1},
      {:type_definitions, &validate_type_definitions/1},
      {:field_constraints, &validate_field_constraints/1}
    ]
    
    extended_steps = if validation_level in [:comprehensive, :deep] do
      [
        {:adapter_compatibility, &validate_adapter_compatibility/1},
        {:serialization_compatibility, &validate_serialization_compatibility/1},
        {:performance_characteristics, &validate_performance_characteristics/1}
      ]
    else
      []
    end
    
    all_steps = validation_steps ++ extended_steps
    
    case execute_validation_steps(signature_module, all_steps, %{}) do
      {:ok, results} ->
        {:ok, compile_validation_report(signature_module, results, validation_level)}
      
      {:error, step, reason, partial_results} ->
        {:error, format_validation_error(step, reason, partial_results)}
    end
  end
  
  defp execute_validation_steps(signature_module, [], results) do
    {:ok, results}
  end
  
  defp execute_validation_steps(signature_module, [{step_name, step_fn} | remaining], results) do
    case step_fn.(signature_module) do
      {:ok, step_result} ->
        execute_validation_steps(signature_module, remaining, Map.put(results, step_name, step_result))
      
      {:error, reason} ->
        {:error, step_name, reason, results}
    end
  end
  
  defp validate_module_loading(signature_module) do
    case Code.ensure_loaded(signature_module) do
      {:module, _} ->
        if function_exported?(signature_module, :__signature__, 0) do
          try do
            signature = signature_module.__signature__()
            {:ok, %{
              module: signature_module,
              signature: signature,
              loaded: true,
              has_signature_function: true
            }}
          rescue
            error ->
              {:error, "Signature function failed: #{inspect(error)}"}
          end
        else
          {:error, "Module does not export __signature__/0 function"}
        end
      
      {:error, reason} ->
        {:error, "Failed to load module: #{reason}"}
    end
  end
  
  defp validate_signature_structure(signature_module) do
    try do
      signature = signature_module.__signature__()
      
      structure_checks = [
        {:has_inputs, fn -> not Enum.empty?(signature.inputs) end},
        {:has_outputs, fn -> not Enum.empty?(signature.outputs) end},
        {:inputs_format, fn -> validate_fields_format(signature.inputs) end},
        {:outputs_format, fn -> validate_fields_format(signature.outputs) end},
        {:no_duplicate_names, fn -> validate_no_duplicate_field_names(signature) end}
      ]
      
      results = Enum.map(structure_checks, fn {check_name, check_fn} ->
        {check_name, check_fn.()}
      end)
      
      all_passed = Enum.all?(results, fn {_name, result} -> result == true end)
      
      if all_passed do
        {:ok, %{
          structure_valid: true,
          input_count: length(signature.inputs),
          output_count: length(signature.outputs),
          checks: results
        }}
      else
        failed_checks = Enum.filter(results, fn {_name, result} -> result != true end)
        {:error, "Structure validation failed: #{inspect(failed_checks)}"}
      end
    rescue
      error ->
        {:error, "Structure validation exception: #{inspect(error)}"}
    end
  end
  
  defp validate_fields_format(fields) do
    Enum.all?(fields, fn field ->
      case field do
        {name, type, constraints} when is_atom(name) and is_list(constraints) ->
          Registry.get_type_info(type) != nil
        _ ->
          false
      end
    end)
  end
  
  defp validate_no_duplicate_field_names(signature) do
    all_names = Enum.map(signature.inputs ++ signature.outputs, fn {name, _, _} -> name end)
    length(all_names) == length(Enum.uniq(all_names))
  end
  
  defp validate_type_definitions(signature_module) do
    signature = signature_module.__signature__()
    all_fields = signature.inputs ++ signature.outputs
    
    type_validations = Enum.map(all_fields, fn {name, type, constraints} ->
      case Registry.get_type_info(type) do
        nil ->
          {name, {:error, "Unknown type: #{inspect(type)}"}}
        
        type_info ->
          constraint_validation = validate_constraints_for_type(type, constraints, type_info)
          {name, {:ok, %{type: type, type_info: type_info, constraints_valid: constraint_validation}}}
      end
    end)
    
    errors = Enum.filter(type_validations, fn {_name, result} -> match?({:error, _}, result) end)
    
    if Enum.empty?(errors) do
      {:ok, %{
        all_types_valid: true,
        field_validations: type_validations,
        supported_types: Enum.map(all_fields, fn {name, type, _} -> {name, type} end)
      }}
    else
      {:error, "Type validation failed: #{inspect(errors)}"}
    end
  end
  
  defp validate_constraints_for_type(type, constraints, type_info) do
    allowed_constraints = Map.get(type_info, :constraints, [])
    
    invalid_constraints = Enum.filter(constraints, fn {constraint_name, _value} ->
      constraint_name not in allowed_constraints
    end)
    
    if Enum.empty?(invalid_constraints) do
      {:ok, "All constraints valid"}
    else
      {:error, "Invalid constraints: #{inspect(invalid_constraints)}"}
    end
  end
  
  defp validate_field_constraints(signature_module) do
    signature = signature_module.__signature__()
    all_fields = signature.inputs ++ signature.outputs
    
    # Generate test values and validate constraints
    constraint_validations = Enum.map(all_fields, fn {name, type, constraints} ->
      case generate_test_values_for_type(type) do
        {:ok, test_values} ->
          validation_results = Enum.map(test_values, fn test_value ->
            Validator.validate_value(test_value, type, constraints)
          end)
          
          {name, %{
            type: type,
            constraints: constraints,
            test_results: validation_results,
            all_passed: Enum.all?(validation_results, &match?({:ok, _}, &1))
          }}
        
        {:error, reason} ->
          {name, {:error, "Could not generate test values: #{reason}"}}
      end
    end)
    
    {:ok, %{
      constraint_validations: constraint_validations,
      all_constraints_working: Enum.all?(constraint_validations, fn
        {_name, %{all_passed: true}} -> true
        {_name, {:error, _}} -> false
        _ -> false
      end)
    }}
  end
  
  defp validate_adapter_compatibility(signature_module) do
    signature = signature_module.__signature__()
    adapters_to_test = [:mock, :python_port]  # Add more as available
    
    compatibility_results = Enum.map(adapters_to_test, fn adapter_type ->
      case test_adapter_compatibility(signature, adapter_type) do
        {:ok, result} ->
          {adapter_type, {:ok, result}}
        
        {:error, reason} ->
          {adapter_type, {:error, reason}}
      end
    end)
    
    {:ok, %{
      adapter_compatibility: compatibility_results,
      compatible_adapters: Enum.filter(compatibility_results, fn {_adapter, result} ->
        match?({:ok, _}, result)
      end) |> Enum.map(fn {adapter, _} -> adapter end)
    }}
  end
  
  defp test_adapter_compatibility(signature, adapter_type) do
    try do
      adapter = Registry.get_adapter(adapter_type)
      
      # Test signature conversion
      case convert_signature_for_adapter(signature, adapter_type) do
        {:ok, converted} ->
          {:ok, %{
            adapter: adapter_type,
            conversion_successful: true,
            converted_signature: converted
          }}
        
        {:error, reason} ->
          {:error, "Conversion failed: #{reason}"}
      end
    rescue
      error ->
        {:error, "Compatibility test failed: #{inspect(error)}"}
    end
  end
  
  defp convert_signature_for_adapter(signature, :mock) do
    # Mock adapter should handle all types
    {:ok, signature}
  end
  
  defp convert_signature_for_adapter(signature, :python_port) do
    # Test Python type conversion
    try do
      converted_inputs = Enum.map(signature.inputs, fn {name, type, _constraints} ->
        %{name: to_string(name), type: convert_type_to_python(type)}
      end)
      
      converted_outputs = Enum.map(signature.outputs, fn {name, type, _constraints} ->
        %{name: to_string(name), type: convert_type_to_python(type)}
      end)
      
      {:ok, %{inputs: converted_inputs, outputs: converted_outputs}}
    rescue
      error ->
        {:error, "Python conversion failed: #{inspect(error)}"}
    end
  end
  
  defp convert_type_to_python(:string), do: "str"
  defp convert_type_to_python(:integer), do: "int"
  defp convert_type_to_python(:float), do: "float"
  defp convert_type_to_python(:boolean), do: "bool"
  defp convert_type_to_python({:list, inner}), do: "List[#{convert_type_to_python(inner)}]"
  defp convert_type_to_python(type), do: to_string(type)
  
  defp validate_serialization_compatibility(signature_module) do
    signature = signature_module.__signature__()
    serialization_targets = [:json_schema, :openai_function, :anthropic_function]
    
    serialization_results = Enum.map(serialization_targets, fn target ->
      case test_serialization_for_target(signature, target) do
        {:ok, result} ->
          {target, {:ok, result}}
        
        {:error, reason} ->
          {target, {:error, reason}}
      end
    end)
    
    {:ok, %{
      serialization_compatibility: serialization_results,
      compatible_targets: Enum.filter(serialization_results, fn {_target, result} ->
        match?({:ok, _}, result)
      end) |> Enum.map(fn {target, _} -> target end)
    }}
  end
  
  defp test_serialization_for_target(signature, target) do
    try do
      all_fields = signature.inputs ++ signature.outputs
      
      serialization_results = Enum.map(all_fields, fn {name, type, constraints} ->
        case AshDSPy.Types.Serializer.serialize(nil, type, target, constraints: constraints) do
          {:ok, serialized} ->
            {name, {:ok, serialized}}
          
          {:error, reason} ->
            {name, {:error, reason}}
        end
      end)
      
      errors = Enum.filter(serialization_results, fn {_name, result} -> match?({:error, _}, result) end)
      
      if Enum.empty?(errors) do
        {:ok, %{
          target: target,
          all_serializable: true,
          field_results: serialization_results
        }}
      else
        {:error, "Serialization errors: #{inspect(errors)}"}
      end
    rescue
      error ->
        {:error, "Serialization test failed: #{inspect(error)}"}
    end
  end
  
  defp validate_performance_characteristics(signature_module) do
    signature = signature_module.__signature__()
    
    # Estimate performance characteristics
    complexity_metrics = %{
      input_complexity: calculate_field_complexity(signature.inputs),
      output_complexity: calculate_field_complexity(signature.outputs),
      total_fields: length(signature.inputs) + length(signature.outputs),
      estimated_validation_time: estimate_validation_time(signature),
      estimated_serialization_time: estimate_serialization_time(signature)
    }
    
    performance_warnings = generate_performance_warnings(complexity_metrics)
    
    {:ok, %{
      complexity_metrics: complexity_metrics,
      performance_warnings: performance_warnings,
      performance_rating: calculate_performance_rating(complexity_metrics)
    }}
  end
  
  defp calculate_field_complexity(fields) do
    Enum.sum(Enum.map(fields, fn {_name, type, constraints} ->
      base_complexity = case type do
        basic when basic in [:string, :integer, :float, :boolean, :atom] -> 1
        ml when ml in [:embedding, :probability, :confidence_score] -> 2
        {:list, _inner} -> 3
        {:dict, _key, _value} -> 4
        {:union, types} -> length(types)
        _ -> 2
      end
      
      constraint_complexity = length(constraints) * 0.5
      base_complexity + constraint_complexity
    end))
  end
  
  defp estimate_validation_time(signature) do
    # Rough estimation in microseconds
    all_fields = signature.inputs ++ signature.outputs
    base_time = length(all_fields) * 10  # 10μs per field
    
    complexity_multiplier = calculate_field_complexity(all_fields) / length(all_fields)
    round(base_time * complexity_multiplier)
  end
  
  defp estimate_serialization_time(signature) do
    # Rough estimation in microseconds  
    all_fields = signature.inputs ++ signature.outputs
    base_time = length(all_fields) * 50  # 50μs per field for JSON schema generation
    
    complexity_multiplier = calculate_field_complexity(all_fields) / length(all_fields)
    round(base_time * complexity_multiplier)
  end
  
  defp generate_performance_warnings(metrics) do
    warnings = []
    
    warnings = if metrics.total_fields > 20 do
      ["High field count (#{metrics.total_fields}) may impact performance" | warnings]
    else
      warnings
    end
    
    warnings = if metrics.estimated_validation_time > 1000 do  # > 1ms
      ["Validation time estimated at #{metrics.estimated_validation_time}μs may be slow" | warnings]
    else
      warnings
    end
    
    warnings = if metrics.input_complexity > 50 do
      ["High input complexity may impact user experience" | warnings]
    else
      warnings
    end
    
    warnings
  end
  
  defp calculate_performance_rating(metrics) do
    # Score out of 100
    field_score = max(0, 100 - metrics.total_fields * 2)
    complexity_score = max(0, 100 - (metrics.input_complexity + metrics.output_complexity))
    time_score = max(0, 100 - metrics.estimated_validation_time / 10)
    
    round((field_score + complexity_score + time_score) / 3)
  end
  
  defp generate_test_values_for_type(:string), do: {:ok, ["test", "", "a very long string with many characters"]}
  defp generate_test_values_for_type(:integer), do: {:ok, [0, 42, -1, 999999]}
  defp generate_test_values_for_type(:float), do: {:ok, [0.0, 3.14, -1.5, 999.999]}
  defp generate_test_values_for_type(:boolean), do: {:ok, [true, false]}
  defp generate_test_values_for_type(:probability), do: {:ok, [0.0, 0.5, 1.0]}
  defp generate_test_values_for_type(:embedding), do: {:ok, [[0.1, 0.2, 0.3], [1.0, 0.0, -1.0]]}
  defp generate_test_values_for_type({:list, inner}) do
    case generate_test_values_for_type(inner) do
      {:ok, inner_values} -> {:ok, [[], [hd(inner_values)], inner_values]}
      error -> error
    end
  end
  defp generate_test_values_for_type(_), do: {:ok, []}
  
  defp compile_validation_report(signature_module, results, validation_level) do
    %{
      signature_module: signature_module,
      validation_level: validation_level,
      timestamp: DateTime.utc_now(),
      overall_valid: all_validations_passed?(results),
      results: results,
      summary: generate_validation_summary(results)
    }
  end
  
  defp all_validations_passed?(results) do
    Enum.all?(results, fn {_step, result} ->
      case result do
        %{structure_valid: true} -> true
        %{all_types_valid: true} -> true
        %{all_constraints_working: true} -> true
        %{compatible_adapters: adapters} -> not Enum.empty?(adapters)
        %{compatible_targets: targets} -> not Enum.empty?(targets)
        %{performance_rating: rating} -> rating > 50
        _ -> false
      end
    end)
  end
  
  defp generate_validation_summary(results) do
    module_loading = get_in(results, [:module_loading, :loaded]) || false
    structure_valid = get_in(results, [:signature_structure, :structure_valid]) || false
    types_valid = get_in(results, [:type_definitions, :all_types_valid]) || false
    
    %{
      module_loading: module_loading,
      structure_valid: structure_valid,
      types_valid: types_valid,
      total_checks: map_size(results),
      passed_checks: count_passed_checks(results)
    }
  end
  
  defp count_passed_checks(results) do
    Enum.count(results, fn {_step, result} ->
      case result do
        %{structure_valid: true} -> true
        %{all_types_valid: true} -> true
        %{all_constraints_working: true} -> true
        _ -> false
      end
    end)
  end
  
  defp format_validation_error(step, reason, partial_results) do
    "Validation failed at step #{step}: #{reason}. Completed steps: #{inspect(Map.keys(partial_results))}"
  end
end
```

### BATCH PROCESSING MANUAL ACTION

**Efficient Batch Processing Implementation:**
```elixir
defmodule AshDSPy.ML.Actions.BatchProcessing do
  @moduledoc """
  Manual action for efficient batch processing of ML operations with
  optimized resource usage, parallel execution, and progress tracking.
  """
  
  use Ash.Resource.ManualCreate
  
  alias AshDSPy.ML.{Program, Execution}
  alias AshDSPy.Adapters.Registry
  
  def create(changeset, _opts, _context) do
    program_id = Ash.Changeset.get_argument(changeset, :program_id)
    batch_inputs = Ash.Changeset.get_argument(changeset, :batch_inputs)
    batch_options = Ash.Changeset.get_argument(changeset, :batch_options) || %{}
    
    with {:ok, program} <- load_program(program_id),
         {:ok, validated_batch} <- validate_batch_inputs(program, batch_inputs),
         {:ok, batch_config} <- prepare_batch_configuration(batch_options),
         {:ok, batch_results} <- execute_batch_with_optimizations(program, validated_batch, batch_config) do
      {:ok, batch_results}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp load_program(program_id) do
    case Program.get(program_id) do
      {:ok, program} when program.status == :ready ->
        {:ok, program}
      {:ok, program} ->
        {:error, "Program not ready (status: #{program.status})"}
      {:error, reason} ->
        {:error, "Failed to load program: #{inspect(reason)}"}
    end
  end
  
  defp validate_batch_inputs(program, batch_inputs) when is_list(batch_inputs) do
    signature_module = String.to_existing_atom(program.signature.module)
    
    validation_results = Enum.with_index(batch_inputs)
    |> Enum.map(fn {inputs, index} ->
      case signature_module.validate_inputs(inputs) do
        {:ok, validated} -> {:ok, {index, validated}}
        {:error, reason} -> {:error, {index, reason}}
      end
    end)
    
    {valid_inputs, errors} = Enum.split_with(validation_results, &match?({:ok, _}, &1))
    
    if Enum.empty?(errors) do
      validated_batch = Enum.map(valid_inputs, fn {:ok, {index, validated}} -> {index, validated} end)
      {:ok, validated_batch}
    else
      error_details = Enum.map(errors, fn {:error, {index, reason}} -> {index, reason} end)
      {:error, "Batch validation failed for inputs: #{inspect(error_details)}"}
    end
  end
  
  defp validate_batch_inputs(_program, _batch_inputs) do
    {:error, "Batch inputs must be a list"}
  end
  
  defp prepare_batch_configuration(options) do
    default_config = %{
      batch_size: 10,
      max_concurrency: 4,
      timeout_per_item: 30_000,
      continue_on_error: true,
      progress_callback: nil,
      retry_failed: true,
      max_retries: 2
    }
    
    config = Map.merge(default_config, options)
    
    # Validate configuration
    cond do
      config.batch_size <= 0 ->
        {:error, "Batch size must be positive"}
      
      config.max_concurrency <= 0 ->
        {:error, "Max concurrency must be positive"}
      
      config.timeout_per_item <= 0 ->
        {:error, "Timeout per item must be positive"}
      
      true ->
        {:ok, config}
    end
  end
  
  defp execute_batch_with_optimizations(program, validated_batch, config) do
    start_time = System.monotonic_time(:millisecond)
    total_items = length(validated_batch)
    
    # Create batch execution record
    batch_execution = create_batch_execution_record(program, total_items, config)
    
    # Process in batches with concurrency control
    batch_results = validated_batch
    |> Enum.chunk_every(config.batch_size)
    |> Enum.with_index()
    |> Enum.flat_map(fn {batch_chunk, batch_index} ->
      process_batch_chunk(program, batch_chunk, batch_index, config, batch_execution)
    end)
    
    # Compile final results
    total_duration = System.monotonic_time(:millisecond) - start_time
    
    compile_batch_results(batch_results, total_items, total_duration, batch_execution)
  end
  
  defp create_batch_execution_record(program, total_items, config) do
    metadata = %{
      program_id: program.id,
      total_items: total_items,
      batch_config: config,
      start_time: DateTime.utc_now()
    }
    
    # This could be a separate batch execution resource
    %{
      id: Ash.UUID.generate(),
      program_id: program.id,
      total_items: total_items,
      completed_items: 0,
      failed_items: 0,
      metadata: metadata
    }
  end
  
  defp process_batch_chunk(program, batch_chunk, batch_index, config, batch_execution) do
    Logger.info("Processing batch chunk #{batch_index} with #{length(batch_chunk)} items")
    
    # Process items concurrently within the chunk
    tasks = Enum.map(batch_chunk, fn {original_index, inputs} ->
      Task.async(fn ->
        process_single_item(program, original_index, inputs, config)
      end)
    end)
    
    # Wait for all tasks with timeout
    chunk_timeout = config.timeout_per_item * length(batch_chunk) + 5000  # Extra 5s buffer
    
    task_results = Task.await_many(tasks, chunk_timeout)
    
    # Update progress if callback provided
    if config.progress_callback do
      completed_count = batch_index * config.batch_size + length(batch_chunk)
      config.progress_callback.(completed_count, batch_execution.total_items)
    end
    
    task_results
  end
  
  defp process_single_item(program, original_index, inputs, config) do
    adapter = Registry.get_adapter(program.adapter_type)
    
    execution_start = System.monotonic_time(:millisecond)
    
    case execute_with_retry(adapter, program.dspy_program_id, inputs, config.max_retries, config.timeout_per_item) do
      {:ok, outputs} ->
        duration = System.monotonic_time(:millisecond) - execution_start
        
        # Validate outputs
        signature_module = String.to_existing_atom(program.signature.module)
        case signature_module.validate_outputs(outputs) do
          {:ok, validated_outputs} ->
            {original_index, {:ok, %{
              inputs: inputs,
              outputs: validated_outputs,
              duration_ms: duration,
              status: :completed
            }}}
          
          {:error, validation_error} ->
            {original_index, {:error, %{
              inputs: inputs,
              error: "Output validation failed: #{validation_error}",
              duration_ms: duration,
              status: :validation_error
            }}}
        end
      
      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - execution_start
        
        {original_index, {:error, %{
          inputs: inputs,
          error: format_error(reason),
          duration_ms: duration,
          status: :execution_error
        }}}
    end
  rescue
    error ->
      duration = System.monotonic_time(:millisecond) - execution_start
      
      {original_index, {:error, %{
        inputs: inputs,
        error: "Exception: #{inspect(error)}",
        duration_ms: duration,
        status: :exception
      }}}
  end
  
  defp execute_with_retry(_adapter, _program_id, _inputs, 0, _timeout) do
    {:error, "Max retries exceeded"}
  end
  
  defp execute_with_retry(adapter, program_id, inputs, retries_left, timeout) do
    case adapter.execute_program(program_id, inputs) do
      {:ok, result} ->
        {:ok, result}
      
      {:error, reason} ->
        if retries_left > 1 and should_retry?(reason) do
          Process.sleep(1000)  # 1 second delay between retries
          execute_with_retry(adapter, program_id, inputs, retries_left - 1, timeout)
        else
          {:error, reason}
        end
    end
  end
  
  defp should_retry?(reason) do
    # Define which errors are retryable
    case reason do
      "timeout" -> true
      "connection_failed" -> true
      "temporary_error" -> true
      _ -> false
    end
  end
  
  defp compile_batch_results(batch_results, total_items, total_duration, batch_execution) do
    # Separate successful and failed results
    {successful_results, failed_results} = Enum.split_with(batch_results, fn
      {_index, {:ok, _}} -> true
      {_index, {:error, _}} -> false
    end)
    
    success_count = length(successful_results)
    failure_count = length(failed_results)
    
    # Calculate statistics
    successful_outputs = Enum.map(successful_results, fn {index, {:ok, result}} ->
      {index, result.outputs}
    end)
    
    failed_details = Enum.map(failed_results, fn {index, {:error, error_info}} ->
      {index, error_info}
    end)
    
    durations = Enum.map(batch_results, fn
      {_index, {:ok, result}} -> result.duration_ms
      {_index, {:error, error_info}} -> error_info.duration_ms
    end)
    
    avg_duration = if Enum.empty?(durations), do: 0, else: Enum.sum(durations) / length(durations)
    
    {:ok, %{
      batch_execution_id: batch_execution.id,
      total_items: total_items,
      successful_items: success_count,
      failed_items: failure_count,
      success_rate: success_count / total_items,
      total_duration_ms: total_duration,
      average_item_duration_ms: avg_duration,
      successful_outputs: successful_outputs,
      failed_items: failed_details,
      summary: %{
        completed: success_count,
        failed: failure_count,
        total: total_items,
        duration_seconds: total_duration / 1000
      }
    }}
  end
  
  defp format_error(reason) do
    case reason do
      %{message: message} -> message
      string when is_binary(string) -> string
      other -> inspect(other)
    end
  end
end
```

### HEALTH MONITORING MANUAL ACTION

**System Health Diagnostics:**
```elixir
defmodule AshDSPy.ML.Actions.HealthMonitoring do
  @moduledoc """
  Manual action for comprehensive system health monitoring including
  adapter status, resource availability, performance metrics, and diagnostics.
  """
  
  use Ash.Resource.ManualRead
  
  alias AshDSPy.ML.{Program, Signature, Execution}
  alias AshDSPy.Adapters.Registry
  alias AshDSPy.PythonBridge.Bridge
  
  def read(ash_query, _ecto_query, _opts, _context) do
    check_level = Ash.Query.get_argument(ash_query, :check_level) || :standard
    include_metrics = Ash.Query.get_argument(ash_query, :include_metrics) || false
    
    case perform_health_checks(check_level, include_metrics) do
      {:ok, health_report} ->
        {:ok, [health_report]}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp perform_health_checks(check_level, include_metrics) do
    base_checks = [
      {:system_status, &check_system_status/0},
      {:adapter_status, &check_adapter_status/0},
      {:resource_status, &check_resource_status/0},
      {:database_connectivity, &check_database_connectivity/0}
    ]
    
    extended_checks = if check_level in [:comprehensive, :deep] do
      [
        {:performance_metrics, &check_performance_metrics/0},
        {:resource_utilization, &check_resource_utilization/0},
        {:error_rates, &check_error_rates/0},
        {:capacity_analysis, &check_capacity_analysis/0}
      ]
    else
      []
    end
    
    all_checks = base_checks ++ extended_checks
    
    check_results = execute_health_checks(all_checks)
    overall_status = determine_overall_health(check_results)
    
    health_report = %{
      timestamp: DateTime.utc_now(),
      check_level: check_level,
      overall_status: overall_status,
      checks: check_results,
      summary: generate_health_summary(check_results)
    }
    
    health_report = if include_metrics do
      Map.put(health_report, :detailed_metrics, collect_detailed_metrics())
    else
      health_report
    end
    
    {:ok, health_report}
  end
  
  defp execute_health_checks(checks) do
    Enum.map(checks, fn {check_name, check_fn} ->
      start_time = System.monotonic_time(:millisecond)
      
      result = try do
        check_fn.()
      rescue
        error ->
          {:error, "Check failed with exception: #{inspect(error)}"}
      end
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      {check_name, %{
        result: result,
        duration_ms: duration,
        timestamp: DateTime.utc_now()
      }}
    end)
  end
  
  defp check_system_status do
    # Check core system components
    components = [
      {:application, check_application_status()},
      {:supervision_tree, check_supervision_tree()},
      {:memory_usage, check_memory_usage()},
      {:process_count, check_process_count()}
    ]
    
    all_healthy = Enum.all?(components, fn {_name, status} -> 
      match?({:ok, _}, status) 
    end)
    
    if all_healthy do
      {:ok, %{
        status: :healthy,
        components: components,
        uptime: get_uptime()
      }}
    else
      failed_components = Enum.filter(components, fn {_name, status} ->
        match?({:error, _}, status)
      end)
      
      {:warning, %{
        status: :degraded,
        components: components,
        failed_components: failed_components,
        uptime: get_uptime()
      }}
    end
  end
  
  defp check_application_status do
    case Application.started_applications() do
      apps when is_list(apps) ->
        ash_dspy_running = Enum.any?(apps, fn {app, _, _} -> app == :ash_dspy end)
        
        if ash_dspy_running do
          {:ok, :running}
        else
          {:error, :not_running}
        end
      
      _ ->
        {:error, :unknown}
    end
  end
  
  defp check_supervision_tree do
    try do
      case Supervisor.which_children(AshDSPy.Supervisor) do
        children when is_list(children) ->
          running_children = Enum.count(children, fn {_id, pid, _type, _modules} ->
            is_pid(pid) and Process.alive?(pid)
          end)
          
          {:ok, %{
            total_children: length(children),
            running_children: running_children,
            all_running: running_children == length(children)
          }}
        
        _ ->
          {:error, :supervisor_not_found}
      end
    rescue
      _ ->
        {:error, :supervisor_check_failed}
    end
  end
  
  defp check_memory_usage do
    memory_info = :erlang.memory()
    total_mb = memory_info[:total] / (1024 * 1024)
    process_mb = memory_info[:processes] / (1024 * 1024)
    
    status = cond do
      total_mb > 1000 -> :high  # > 1GB
      total_mb > 500 -> :medium  # > 500MB
      true -> :normal
    end
    
    {:ok, %{
      total_mb: round(total_mb),
      process_mb: round(process_mb),
      status: status
    }}
  end
  
  defp check_process_count do
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)
    
    usage_percent = (process_count / process_limit) * 100
    
    status = cond do
      usage_percent > 80 -> :high
      usage_percent > 60 -> :medium
      true -> :normal
    end
    
    {:ok, %{
      process_count: process_count,
      process_limit: process_limit,
      usage_percent: round(usage_percent),
      status: status
    }}
  end
  
  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
  
  defp check_adapter_status do
    available_adapters = Registry.list_adapters()
    
    adapter_statuses = Enum.map(available_adapters, fn adapter_type ->
      status = case test_adapter_health(adapter_type) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
      
      {adapter_type, status}
    end)
    
    healthy_adapters = Enum.filter(adapter_statuses, fn {_adapter, status} ->
      match?({:ok, _}, status)
    end) |> Enum.map(fn {adapter, _} -> adapter end)
    
    {:ok, %{
      available_adapters: available_adapters,
      adapter_statuses: adapter_statuses,
      healthy_adapters: healthy_adapters,
      healthy_adapter_count: length(healthy_adapters)
    }}
  end
  
  defp test_adapter_health(:mock) do
    try do
      case Process.whereis(AshDSPy.Adapters.Mock) do
        nil ->
          # Try to start mock adapter
          case AshDSPy.Adapters.Mock.start_link() do
            {:ok, _pid} -> {:ok, %{status: :healthy, started: true}}
            {:error, reason} -> {:error, "Failed to start: #{inspect(reason)}"}
          end
        
        _pid ->
          # Test basic functionality
          case AshDSPy.Adapters.Mock.list_programs() do
            {:ok, _programs} -> {:ok, %{status: :healthy, started: false}}
            {:error, reason} -> {:error, "Health check failed: #{inspect(reason)}"}
          end
      end
    rescue
      error ->
        {:error, "Exception during health check: #{inspect(error)}"}
    end
  end
  
  defp test_adapter_health(:python_port) do
    try do
      case Process.whereis(AshDSPy.PythonBridge.Bridge) do
        nil ->
          {:error, "Python bridge not running"}
        
        _pid ->
          case Bridge.call(:ping, %{}, 5000) do
            {:ok, %{"status" => "ok"}} ->
              {:ok, %{status: :healthy, bridge_running: true}}
            
            {:ok, response} ->
              {:warning, %{status: :degraded, response: response}}
            
            {:error, reason} ->
              {:error, "Health check failed: #{inspect(reason)}"}
          end
      end
    rescue
      error ->
        {:error, "Exception during health check: #{inspect(error)}"}
    end
  end
  
  defp test_adapter_health(adapter_type) do
    {:error, "Unknown adapter type: #{adapter_type}"}
  end
  
  defp check_resource_status do
    # Check Ash resources and database connectivity
    resource_checks = [
      {:signatures, check_signature_resource()},
      {:programs, check_program_resource()},
      {:executions, check_execution_resource()}
    ]
    
    all_healthy = Enum.all?(resource_checks, fn {_name, status} ->
      match?({:ok, _}, status)
    end)
    
    if all_healthy do
      {:ok, %{
        status: :healthy,
        resource_checks: resource_checks
      }}
    else
      failed_resources = Enum.filter(resource_checks, fn {_name, status} ->
        not match?({:ok, _}, status)
      end)
      
      {:warning, %{
        status: :degraded,
        resource_checks: resource_checks,
        failed_resources: failed_resources
      }}
    end
  end
  
  defp check_signature_resource do
    try do
      case Signature.read() do
        {:ok, signatures} ->
          {:ok, %{count: length(signatures), status: :accessible}}
        
        {:error, reason} ->
          {:error, "Failed to read signatures: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception reading signatures: #{inspect(error)}"}
    end
  end
  
  defp check_program_resource do
    try do
      case Program.read() do
        {:ok, programs} ->
          ready_programs = Enum.count(programs, fn p -> p.status == :ready end)
          {:ok, %{
            total_count: length(programs),
            ready_count: ready_programs,
            status: :accessible
          }}
        
        {:error, reason} ->
          {:error, "Failed to read programs: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception reading programs: #{inspect(error)}"}
    end
  end
  
  defp check_execution_resource do
    try do
      case Execution.recent_executions(%{limit: 10}) do
        {:ok, executions} ->
          {:ok, %{recent_count: length(executions), status: :accessible}}
        
        {:error, reason} ->
          {:error, "Failed to read executions: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception reading executions: #{inspect(error)}"}
    end
  end
  
  defp check_database_connectivity do
    try do
      # Simple connectivity test
      case AshDSPy.Repo.query("SELECT 1", []) do
        {:ok, _result} ->
          {:ok, %{status: :connected, latency_ms: measure_db_latency()}}
        
        {:error, reason} ->
          {:error, "Database query failed: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Database connectivity exception: #{inspect(error)}"}
    end
  end
  
  defp measure_db_latency do
    start_time = System.monotonic_time(:millisecond)
    
    case AshDSPy.Repo.query("SELECT 1", []) do
      {:ok, _} ->
        System.monotonic_time(:millisecond) - start_time
      
      {:error, _} ->
        nil
    end
  end
  
  defp check_performance_metrics do
    # Collect performance metrics from recent executions
    try do
      case Execution.recent_executions(%{limit: 100}) do
        {:ok, executions} ->
          metrics = calculate_performance_metrics(executions)
          {:ok, metrics}
        
        {:error, reason} ->
          {:error, "Failed to collect performance metrics: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception collecting metrics: #{inspect(error)}"}
    end
  end
  
  defp calculate_performance_metrics(executions) do
    if Enum.empty?(executions) do
      %{
        total_executions: 0,
        avg_duration_ms: 0,
        success_rate: 0,
        error_rate: 0
      }
    else
      completed = Enum.filter(executions, &(&1.status == :completed))
      failed = Enum.filter(executions, &(&1.status == :failed))
      
      durations = Enum.map(completed, &(&1.duration_ms)) |> Enum.filter(& &1)
      avg_duration = if Enum.empty?(durations), do: 0, else: Enum.sum(durations) / length(durations)
      
      %{
        total_executions: length(executions),
        completed_executions: length(completed),
        failed_executions: length(failed),
        avg_duration_ms: round(avg_duration),
        success_rate: length(completed) / length(executions),
        error_rate: length(failed) / length(executions),
        execution_rate_per_hour: calculate_execution_rate(executions)
      }
    end
  end
  
  defp calculate_execution_rate(executions) do
    if Enum.empty?(executions) do
      0
    else
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)
      
      recent_executions = Enum.filter(executions, fn execution ->
        DateTime.compare(execution.executed_at, one_hour_ago) in [:gt, :eq]
      end)
      
      length(recent_executions)
    end
  end
  
  defp check_resource_utilization do
    # Check system resource utilization
    system_info = %{
      schedulers: :erlang.system_info(:schedulers),
      scheduler_utilization: get_scheduler_utilization(),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      ets_count: :erlang.system_info(:ets_count),
      ets_limit: :erlang.system_info(:ets_limit)
    }
    
    {:ok, system_info}
  end
  
  defp get_scheduler_utilization do
    # Get scheduler utilization if available
    try do
      :scheduler.sample()
      Process.sleep(1000)  # Sample for 1 second
      utilization = :scheduler.utilization(1)
      
      case utilization do
        {:ok, data} -> data
        _ -> :unavailable
      end
    rescue
      _ -> :unavailable
    end
  end
  
  defp check_error_rates do
    # Analyze error patterns from recent executions
    try do
      case Execution.recent_executions(%{limit: 500}) do
        {:ok, executions} ->
          error_analysis = analyze_error_patterns(executions)
          {:ok, error_analysis}
        
        {:error, reason} ->
          {:error, "Failed to analyze errors: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception during error analysis: #{inspect(error)}"}
    end
  end
  
  defp analyze_error_patterns(executions) do
    failed_executions = Enum.filter(executions, &(&1.status == :failed))
    
    if Enum.empty?(failed_executions) do
      %{
        total_errors: 0,
        error_rate: 0,
        error_patterns: [],
        recent_errors: []
      }
    else
      error_messages = Enum.map(failed_executions, &(&1.error_message))
                     |> Enum.filter(& &1)
      
      error_patterns = error_messages
                      |> Enum.frequencies()
                      |> Enum.sort_by(&elem(&1, 1), :desc)
                      |> Enum.take(10)
      
      recent_errors = Enum.take(failed_executions, 5)
                     |> Enum.map(fn execution ->
                       %{
                         timestamp: execution.executed_at,
                         error: execution.error_message,
                         program_id: execution.program_id
                       }
                     end)
      
      %{
        total_errors: length(failed_executions),
        error_rate: length(failed_executions) / length(executions),
        error_patterns: error_patterns,
        recent_errors: recent_errors
      }
    end
  end
  
  defp check_capacity_analysis do
    # Analyze system capacity and scaling characteristics
    {:ok, %{
      current_load: calculate_current_load(),
      capacity_recommendations: generate_capacity_recommendations(),
      scaling_metrics: get_scaling_metrics()
    }}
  end
  
  defp calculate_current_load do
    # Calculate current system load based on various metrics
    process_load = :erlang.system_info(:process_count) / :erlang.system_info(:process_limit)
    memory_info = :erlang.memory()
    memory_load = memory_info[:total] / (1024 * 1024 * 1024)  # GB
    
    %{
      process_utilization: process_load,
      memory_usage_gb: memory_load,
      overall_load: (process_load + min(memory_load / 4, 1)) / 2  # Normalized 0-1
    }
  end
  
  defp generate_capacity_recommendations do
    load = calculate_current_load()
    
    recommendations = []
    
    recommendations = if load.process_utilization > 0.8 do
      ["Consider increasing process limit or optimizing process usage" | recommendations]
    else
      recommendations
    end
    
    recommendations = if load.memory_usage_gb > 2 do
      ["Monitor memory usage, consider increasing available memory" | recommendations]
    else
      recommendations
    end
    
    recommendations = if load.overall_load > 0.7 do
      ["System under high load, consider scaling or optimizing" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["System operating within normal parameters"]
    else
      recommendations
    end
  end
  
  defp get_scaling_metrics do
    %{
      max_concurrent_executions: estimate_max_concurrent_executions(),
      recommended_scaling_threshold: 0.7,
      current_utilization: calculate_current_load().overall_load
    }
  end
  
  defp estimate_max_concurrent_executions do
    # Rough estimate based on available resources
    process_capacity = :erlang.system_info(:process_limit) * 0.1  # 10% for ML tasks
    memory_capacity = :erlang.memory()[:total] / (50 * 1024 * 1024)  # 50MB per execution estimate
    
    round(min(process_capacity, memory_capacity))
  end
  
  defp collect_detailed_metrics do
    # Collect comprehensive system metrics
    %{
      erlang_vm: %{
        version: :erlang.system_info(:version),
        schedulers: :erlang.system_info(:schedulers),
        logical_processors: :erlang.system_info(:logical_processors),
        wordsize: :erlang.system_info(:wordsize)
      },
      memory: :erlang.memory(),
      statistics: %{
        runtime: :erlang.statistics(:runtime),
        wall_clock: :erlang.statistics(:wall_clock),
        reductions: :erlang.statistics(:reductions),
        garbage_collection: :erlang.statistics(:garbage_collection)
      },
      application_info: Application.loaded_applications()
    }
  end
  
  defp determine_overall_health(check_results) do
    statuses = Enum.map(check_results, fn {_check_name, %{result: result}} ->
      case result do
        {:ok, _} -> :healthy
        {:warning, _} -> :warning
        {:error, _} -> :error
      end
    end)
    
    cond do
      Enum.any?(statuses, &(&1 == :error)) -> :error
      Enum.any?(statuses, &(&1 == :warning)) -> :warning
      true -> :healthy
    end
  end
  
  defp generate_health_summary(check_results) do
    total_checks = length(check_results)
    
    status_counts = check_results
    |> Enum.map(fn {_name, %{result: result}} ->
      case result do
        {:ok, _} -> :healthy
        {:warning, _} -> :warning
        {:error, _} -> :error
      end
    end)
    |> Enum.frequencies()
    
    %{
      total_checks: total_checks,
      healthy_checks: Map.get(status_counts, :healthy, 0),
      warning_checks: Map.get(status_counts, :warning, 0),
      error_checks: Map.get(status_counts, :error, 0),
      health_percentage: (Map.get(status_counts, :healthy, 0) / total_checks) * 100
    }
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the comprehensive manual actions system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/ash_dspy/ml/actions/
├── program_execution.ex     # Complex program execution lifecycle
├── signature_validation.ex # Deep signature validation and compatibility
├── batch_processing.ex     # Efficient batch processing with concurrency
├── health_monitoring.ex    # System health diagnostics
├── resource_cleanup.ex     # Resource cleanup and maintenance
└── adapter_coordination.ex # Multi-adapter coordination and failover

test/ash_dspy/ml/actions/
├── program_execution_test.exs     # Program execution testing
├── signature_validation_test.exs  # Signature validation testing
├── batch_processing_test.exs      # Batch processing testing
├── health_monitoring_test.exs     # Health monitoring testing
└── integration_test.exs           # Cross-action integration testing
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Program Execution (`lib/ash_dspy/ml/actions/program_execution.ex`)**:
   - Complete lifecycle management with validation and cleanup
   - Performance tracking and metrics collection
   - Robust error handling with retry mechanisms
   - Integration with execution tracking resources

2. **Signature Validation (`lib/ash_dspy/ml/actions/signature_validation.ex`)**:
   - Comprehensive validation including module loading and structure
   - Type definition validation and constraint checking
   - Adapter compatibility and serialization testing
   - Performance characteristic analysis

3. **Batch Processing (`lib/ash_dspy/ml/actions/batch_processing.ex`)**:
   - Efficient concurrent processing with resource management
   - Progress tracking and error recovery
   - Configurable batch sizes and concurrency levels
   - Comprehensive result compilation and statistics

4. **Health Monitoring (`lib/ash_dspy/ml/actions/health_monitoring.ex`)**:
   - System-wide health diagnostics
   - Adapter status monitoring and testing
   - Performance metrics collection and analysis
   - Capacity analysis and scaling recommendations

5. **Resource Cleanup (`lib/ash_dspy/ml/actions/resource_cleanup.ex`)**:
   - Comprehensive resource cleanup and maintenance
   - Orphaned resource detection and removal
   - Performance optimization through cleanup
   - System maintenance and housekeeping

### QUALITY REQUIREMENTS:

- **Reliability**: Robust error handling and recovery mechanisms
- **Performance**: Efficient execution with minimal overhead
- **Monitoring**: Comprehensive logging and metrics collection
- **Flexibility**: Configurable behavior for different use cases
- **Integration**: Seamless integration with all system components
- **Documentation**: Clear documentation for all manual actions
- **Testing**: Complete test coverage for all scenarios

### INTEGRATION POINTS:

- Must integrate with Ash resource lifecycle and validation
- Should use adapter pattern for backend operations
- Must leverage type system for validation and conversion
- Should integrate with monitoring and metrics systems
- Must provide clean interfaces for external usage

### SUCCESS CRITERIA:

1. All manual actions handle complex workflows correctly
2. Error handling provides meaningful feedback and recovery
3. Performance monitoring captures accurate metrics
4. Batch processing handles large datasets efficiently
5. Health monitoring provides actionable diagnostics
6. Resource cleanup maintains system efficiency
7. Integration with other components works seamlessly
8. All test scenarios pass with comprehensive coverage
9. Documentation is clear and complete
10. Performance meets requirements for production use

These manual actions provide the sophisticated workflow management capabilities that enable the DSPy-Ash integration to handle complex ML operations while maintaining system reliability and performance.
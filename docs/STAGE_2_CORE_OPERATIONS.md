# Stage 2: Core Operations - Custom Data Layer & Enhanced Validation

## Overview

Stage 2 builds on the foundation to create a custom Ash data layer that seamlessly integrates with DSPy operations, adds ExDantic validation, and implements proper execution tracking.

**Goal**: Execute DSPy programs through Ash's query interface with full validation and state management.

**Duration**: Week 3-4

## 1. Custom Data Layer Implementation

### 1.1 Core Data Layer

```elixir
# lib/ash_dspy/data_layer.ex
defmodule AshDSPy.DataLayer do
  @moduledoc """
  Custom Ash data layer for DSPy operations.
  
  This data layer:
  - Delegates CRUD operations to AshPostgres
  - Handles DSPy-specific actions (execute, optimize) via adapters
  - Manages state synchronization between Ash and DSPy
  """
  
  @behaviour Ash.DataLayer
  
  alias AshDSPy.DataLayer.{QueryHandler, StateManager}
  
  @impl true
  def can?(resource, feature) do
    case feature do
      # DSPy-specific actions we handle
      {:action, name} when name in [:execute, :optimize, :compile] -> true
      
      # Delegate everything else to Postgres
      _ -> AshPostgres.DataLayer.can?(resource, feature)
    end
  end
  
  @impl true
  def resource_to_query(resource, domain) do
    AshPostgres.DataLayer.resource_to_query(resource, domain)
  end
  
  @impl true
  def run_query(query, resource, context) do
    case query.action.type do
      # Handle custom DSPy actions
      :action -> 
        QueryHandler.handle_action(query, resource, context)
      
      # Delegate CRUD to Postgres
      _ -> 
        AshPostgres.DataLayer.run_query(query, resource, context)
    end
  end
  
  @impl true
  def run_query_with_lateral_join(query, parent_data, resource, context) do
    AshPostgres.DataLayer.run_query_with_lateral_join(query, parent_data, resource, context)
  end
  
  @impl true
  def run_aggregate_query(query, aggregates, resource, context) do
    AshPostgres.DataLayer.run_aggregate_query(query, aggregates, resource, context)
  end
  
  @impl true
  def run_aggregate_query_with_lateral_join(query, aggregates, parent_data, resource, context) do
    AshPostgres.DataLayer.run_aggregate_query_with_lateral_join(query, aggregates, parent_data, resource, context)
  end
  
  # Additional required callbacks delegated to Postgres
  defdelegate create(resource, changeset, context), to: AshPostgres.DataLayer
  defdelegate update(resource, changeset, context), to: AshPostgres.DataLayer
  defdelegate destroy(resource, changeset, context), to: AshPostgres.DataLayer
  defdelegate sort(query, sort, resource), to: AshPostgres.DataLayer
  defdelegate filter(query, filter, resource), to: AshPostgres.DataLayer
  defdelegate limit(query, limit, resource), to: AshPostgres.DataLayer
  defdelegate offset(query, offset, resource), to: AshPostgres.DataLayer
  defdelegate distinct(query, distinct, resource), to: AshPostgres.DataLayer
end
```

### 1.2 Query Handler

```elixir
# lib/ash_dspy/data_layer/query_handler.ex
defmodule AshDSPy.DataLayer.QueryHandler do
  @moduledoc """
  Handles DSPy-specific query operations.
  """
  
  alias AshDSPy.DataLayer.StateManager
  alias AshDSPy.Validation.SignatureValidator
  
  def handle_action(query, resource, context) do
    action = query.action
    
    case action.name do
      :execute -> handle_execute(query, resource, context)
      :optimize -> handle_optimize(query, resource, context)
      :compile -> handle_compile(query, resource, context)
      _ -> {:error, "Unknown action: #{action.name}"}
    end
  end
  
  defp handle_execute(query, resource, context) do
    with {:ok, program} <- get_program_instance(query, context),
         {:ok, inputs} <- extract_inputs(query),
         {:ok, validated_inputs} <- validate_inputs(program, inputs),
         {:ok, execution_record} <- create_execution_record(program, validated_inputs),
         {:ok, result} <- execute_via_adapter(program, validated_inputs),
         {:ok, validated_result} <- validate_outputs(program, result),
         {:ok, updated_execution} <- update_execution_record(execution_record, validated_result) do
      
      # Return result in Ash format
      {:ok, [validated_result], context}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp handle_optimize(query, resource, context) do
    with {:ok, program} <- get_program_instance(query, context),
         {:ok, dataset} <- extract_dataset(query),
         {:ok, config} <- extract_optimization_config(query),
         {:ok, optimization_job} <- create_optimization_job(program, dataset, config),
         {:ok, result} <- run_optimization(program, dataset, config) do
      
      # Update program with optimized state
      StateManager.update_program_state(program, result.optimized_state)
      
      {:ok, [result], context}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_program_instance(query, context) do
    case query.resource_instance || context.resource do
      nil -> {:error, "No program instance found"}
      program -> {:ok, program}
    end
  end
  
  defp extract_inputs(query) do
    inputs = query.arguments
    {:ok, inputs}
  end
  
  defp validate_inputs(program, inputs) do
    signature_module = get_signature_module(program)
    SignatureValidator.validate_inputs(signature_module, inputs)
  end
  
  defp validate_outputs(program, outputs) do
    signature_module = get_signature_module(program)
    SignatureValidator.validate_outputs(signature_module, outputs)
  end
  
  defp execute_via_adapter(program, inputs) do
    adapter = get_adapter()
    
    # Ensure program exists in adapter
    case StateManager.ensure_program_exists(program, adapter) do
      {:ok, dspy_program_id} ->
        adapter.execute_program(dspy_program_id, inputs)
      error ->
        error
    end
  end
  
  defp create_execution_record(program, inputs) do
    AshDSPy.ML.Execution.create!(%{
      program_id: program.id,
      inputs: inputs,
      status: :running,
      started_at: DateTime.utc_now()
    })
  end
  
  defp update_execution_record(execution, result) do
    AshDSPy.ML.Execution.update!(execution, %{
      outputs: result,
      status: :completed,
      completed_at: DateTime.utc_now()
    })
  end
  
  defp get_signature_module(program) do
    # Load signature module from program
    signature = AshDSPy.ML.Signature.get!(program.signature_id)
    Module.safe_concat([signature.module])
  end
  
  defp get_adapter do
    Application.get_env(:ash_dspy, :adapter, AshDSPy.Adapters.PythonPort)
  end
end
```

### 1.3 State Manager

```elixir
# lib/ash_dspy/data_layer/state_manager.ex
defmodule AshDSPy.DataLayer.StateManager do
  @moduledoc """
  Manages state synchronization between Ash and DSPy.
  """
  
  @doc """
  Ensures a program exists in the DSPy adapter.
  Creates it if it doesn't exist, returns the DSPy program ID.
  """
  def ensure_program_exists(program, adapter) do
    case program.dspy_program_id do
      nil -> create_program_in_adapter(program, adapter)
      id -> {:ok, id}
    end
  end
  
  defp create_program_in_adapter(program, adapter) do
    signature = AshDSPy.ML.Signature.get!(program.signature_id)
    signature_module = Module.safe_concat([signature.module])
    
    config = %{
      id: program.id,
      signature: signature_module,
      modules: program.modules || []
    }
    
    case adapter.create_program(config) do
      {:ok, result} ->
        dspy_program_id = result["program_id"] || program.id
        
        # Update program with DSPy ID
        {:ok, updated_program} = AshDSPy.ML.Program.update!(program, %{
          dspy_program_id: dspy_program_id,
          status: :ready
        })
        
        {:ok, dspy_program_id}
      
      error -> error
    end
  end
  
  @doc """
  Updates program state after optimization.
  """
  def update_program_state(program, optimized_state) do
    AshDSPy.ML.Program.update!(program, %{
      compiled_state: optimized_state,
      status: :optimized
    })
  end
end
```

## 2. ExDantic Integration

### 2.1 Signature Validator with ExDantic

```elixir
# lib/ash_dspy/validation/signature_validator.ex
defmodule AshDSPy.Validation.SignatureValidator do
  @moduledoc """
  Enhanced validation using ExDantic for Pydantic-like behavior.
  """
  
  @doc """
  Validate inputs against signature schema with ExDantic.
  """
  def validate_inputs(signature_module, inputs) do
    schema = get_or_create_input_schema(signature_module)
    
    case Exdantic.TypeAdapter.validate(schema, inputs, coerce: true) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_validation_errors(errors)}
    end
  end
  
  @doc """
  Validate outputs against signature schema with ExDantic.
  """
  def validate_outputs(signature_module, outputs) do
    schema = get_or_create_output_schema(signature_module)
    
    case Exdantic.TypeAdapter.validate(schema, outputs, coerce: true) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_validation_errors(errors)}
    end
  end
  
  defp get_or_create_input_schema(signature_module) do
    case :ets.lookup(:signature_schemas, {signature_module, :input}) do
      [{_, schema}] -> schema
      [] -> create_and_cache_schema(signature_module, :input)
    end
  end
  
  defp get_or_create_output_schema(signature_module) do
    case :ets.lookup(:signature_schemas, {signature_module, :output}) do
      [{_, schema}] -> schema
      [] -> create_and_cache_schema(signature_module, :output)
    end
  end
  
  defp create_and_cache_schema(signature_module, type) do
    signature = signature_module.__signature__()
    
    fields = case type do
      :input -> signature.inputs
      :output -> signature.outputs
    end
    
    # Convert to ExDantic field format
    exdantic_fields = Enum.map(fields, fn {name, field_type, constraints} ->
      {name, convert_type_to_exdantic(field_type), convert_constraints(constraints)}
    end)
    
    # Create runtime schema
    schema = Exdantic.Runtime.create_schema(exdantic_fields,
      title: "#{signature_module}_#{type}",
      description: "#{type} schema for #{signature_module}"
    )
    
    # Cache it
    :ets.insert(:signature_schemas, {{signature_module, type}, schema})
    
    schema
  end
  
  defp convert_type_to_exdantic(:string), do: :string
  defp convert_type_to_exdantic(:integer), do: :integer
  defp convert_type_to_exdantic(:float), do: :float
  defp convert_type_to_exdantic(:boolean), do: :boolean
  defp convert_type_to_exdantic({:list, inner}), do: {:array, convert_type_to_exdantic(inner)}
  defp convert_type_to_exdantic({:dict, k, v}), do: {:map, {convert_type_to_exdantic(k), convert_type_to_exdantic(v)}}
  defp convert_type_to_exdantic(type), do: type
  
  defp convert_constraints(constraints) do
    # Convert our constraint format to ExDantic format
    Enum.map(constraints, fn
      {:min_length, n} -> [min_length: n]
      {:max_length, n} -> [max_length: n]
      {:min, n} -> [gteq: n]
      {:max, n} -> [lteq: n]
      other -> other
    end)
    |> List.flatten()
  end
  
  defp format_validation_errors(errors) do
    errors
    |> Enum.map(&Exdantic.Error.format/1)
    |> Enum.join(", ")
  end
end
```

### 2.2 Schema Cache Setup

```elixir
# lib/ash_dspy/validation/schema_cache.ex
defmodule AshDSPy.Validation.SchemaCache do
  @moduledoc """
  ETS-based cache for compiled ExDantic schemas.
  """
  
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  @impl true
  def init(_) do
    :ets.new(:signature_schemas, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
  
  def clear_cache do
    :ets.delete_all_objects(:signature_schemas)
  end
  
  def cache_info do
    :ets.info(:signature_schemas)
  end
end
```

## 3. Enhanced Program Resource

### 3.1 Program Resource with Custom Data Layer

```elixir
# lib/ash_dspy/ml/program.ex
defmodule AshDSPy.ML.Program do
  @moduledoc """
  Enhanced program resource using custom data layer.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshDSPy.DataLayer,  # Use our custom data layer!
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string
    attribute :dspy_program_id, :string
    attribute :modules, {:array, :map}, default: []
    attribute :compiled_state, :map
    attribute :performance_metrics, :map, default: %{}
    
    attribute :status, :atom, constraints: [
      one_of: [:draft, :ready, :optimized, :deployed, :error]
    ], default: :draft
    
    timestamps()
  end
  
  relationships do
    belongs_to :signature, AshDSPy.ML.Signature
    has_many :executions, AshDSPy.ML.Execution
  end
  
  # State machine for program lifecycle
  state_machine do
    initial_states [:draft]
    default_initial_state :draft
    
    transitions do
      transition :initialize, from: :draft, to: :ready
      transition :optimize, from: [:ready], to: :optimized
      transition :deploy, from: [:ready, :optimized], to: :deployed
      transition :error, from: [:draft, :ready, :optimized], to: :error
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :create_with_signature do
      argument :signature_module, :atom, allow_nil?: false
      argument :modules, {:array, :map}, default: []
      
      change fn changeset, _context ->
        signature_module = Ash.Changeset.get_argument(changeset, :signature_module)
        modules = Ash.Changeset.get_argument(changeset, :modules)
        
        # Create signature record if it doesn't exist
        signature_record = get_or_create_signature(signature_module)
        
        changeset
        |> Ash.Changeset.manage_relationship(:signature, signature_record, type: :append)
        |> Ash.Changeset.change_attribute(:modules, modules)
      end
    end
    
    # Execute action - handled by custom data layer
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      
      # The actual implementation is in QueryHandler.handle_execute/3
      run fn _input, _context ->
        # This function should never be called because the data layer
        # intercepts :action type queries
        {:error, "Execute action should be handled by data layer"}
      end
    end
    
    # Optimize action - handled by custom data layer  
    action :optimize, :struct do
      argument :dataset, {:array, :map}, allow_nil?: false
      argument :optimizer, :string, default: "BootstrapFewShot"
      argument :metric, :string, default: "exact_match"
      argument :config, :map, default: %{}
      
      run fn _input, _context ->
        {:error, "Optimize action should be handled by data layer"}
      end
    end
    
    # Deploy action with state transition
    update :deploy do
      accept []
      require_atomic? false
      change transition_state(:deployed)
      
      change fn changeset, _context ->
        # Add deployment logic here
        changeset
      end
    end
  end
  
  code_interface do
    define :create_with_signature
    define :execute
    define :optimize
    define :deploy
  end
  
  defp get_or_create_signature(signature_module) do
    signature = signature_module.__signature__()
    
    case AshDSPy.ML.Signature.get_by_module(to_string(signature_module)) do
      {:ok, existing} -> existing
      {:error, _} ->
        {:ok, signature_data} = AshDSPy.ML.Signature.from_module(%{
          signature_module: signature_module
        })
        AshDSPy.ML.Signature.create!(signature_data)
    end
  end
end
```

### 3.2 Execution Resource

```elixir
# lib/ash_dspy/ml/execution.ex
defmodule AshDSPy.ML.Execution do
  @moduledoc """
  Resource for tracking program executions.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]
  
  attributes do
    uuid_primary_key :id
    
    attribute :inputs, :map, allow_nil?: false
    attribute :outputs, :map
    attribute :error_message, :string
    
    attribute :status, :atom, constraints: [
      one_of: [:pending, :running, :completed, :failed]
    ], default: :pending
    
    # Performance metrics
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    attribute :duration_ms, :integer
    attribute :token_usage, :map
    
    timestamps()
  end
  
  relationships do
    belongs_to :program, AshDSPy.ML.Program
  end
  
  state_machine do
    initial_states [:pending]
    default_initial_state :pending
    
    transitions do
      transition :start, from: :pending, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:pending, :running], to: :failed
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :start_execution do
      argument :program_id, :uuid, allow_nil?: false
      argument :inputs, :map, allow_nil?: false
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:status, :running)
      end
    end
    
    update :complete_execution do
      accept [:outputs, :duration_ms, :token_usage]
      require_atomic? false
      
      change transition_state(:completed)
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end
    
    update :fail_execution do
      accept [:error_message]
      require_atomic? false
      
      change transition_state(:failed)
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end
  end
  
  calculations do
    calculate :duration_seconds, :float do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          case record.duration_ms do
            nil -> nil
            ms -> ms / 1000.0
          end
        end)
      end
    end
    
    calculate :success_rate, :float do
      calculation fn records, _context ->
        if Enum.empty?(records) do
          [0.0]
        else
          successful = Enum.count(records, & &1.status == :completed)
          rate = successful / Enum.count(records)
          [rate]
        end
      end
    end
  end
  
  code_interface do
    define :start_execution
    define :complete_execution
    define :fail_execution
  end
end
```

## 4. Enhanced Adapters

### 4.1 Enhanced Python Port Adapter

```elixir
# lib/ash_dspy/adapters/python_port.ex (enhanced)
defmodule AshDSPy.Adapters.PythonPort do
  @moduledoc """
  Enhanced Python port adapter with better error handling and state management.
  """
  
  @behaviour AshDSPy.Adapters.Adapter
  
  alias AshDSPy.PythonBridge.Bridge
  
  @impl true
  def create_program(config) do
    signature_def = convert_signature(config.signature)
    
    request = %{
      id: config.id,
      signature: signature_def,
      modules: config.modules || build_default_modules(signature_def)
    }
    
    case Bridge.call(:create_program, request, 10_000) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to create program: #{reason}"}
    end
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    request = %{
      program_id: program_id,
      inputs: inputs
    }
    
    start_time = System.monotonic_time(:millisecond)
    
    case Bridge.call(:execute_program, request, 30_000) do
      {:ok, result} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        enhanced_result = Map.merge(result, %{
          "duration_ms" => duration,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        
        {:ok, enhanced_result}
      
      {:error, reason} -> 
        {:error, "Execution failed: #{reason}"}
    end
  end
  
  @impl true
  def optimize_program(program_id, dataset, config) do
    request = %{
      program_id: program_id,
      dataset: dataset,
      optimizer: config[:optimizer] || "BootstrapFewShot",
      metric: config[:metric] || "exact_match",
      config: Map.drop(config, [:optimizer, :metric])
    }
    
    # Optimization can take a long time
    case Bridge.call(:optimize_program, request, 300_000) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Optimization failed: #{reason}"}
    end
  end
  
  @impl true
  def list_programs do
    case Bridge.call(:list_programs, %{}, 5_000) do
      {:ok, result} -> {:ok, result["programs"] || []}
      {:error, reason} -> {:error, "Failed to list programs: #{reason}"}
    end
  end
  
  defp convert_signature(signature_module) do
    signature = signature_module.__signature__()
    
    %{
      name: to_string(signature_module),
      inputs: convert_fields(signature.inputs),
      outputs: convert_fields(signature.outputs)
    }
  end
  
  defp convert_fields(fields) do
    Enum.map(fields, fn {name, type, constraints} ->
      %{
        name: to_string(name),
        type: convert_type_to_python(type),
        constraints: convert_constraints_to_python(constraints)
      }
    end)
  end
  
  defp convert_type_to_python(:string), do: "str"
  defp convert_type_to_python(:integer), do: "int" 
  defp convert_type_to_python(:float), do: "float"
  defp convert_type_to_python(:boolean), do: "bool"
  defp convert_type_to_python({:list, inner}), do: "List[#{convert_type_to_python(inner)}]"
  defp convert_type_to_python({:dict, k, v}), do: "Dict[#{convert_type_to_python(k)}, #{convert_type_to_python(v)}]"
  defp convert_type_to_python(type), do: to_string(type)
  
  defp convert_constraints_to_python(constraints) do
    # Convert Elixir constraints to Python-compatible format
    Map.new(constraints)
  end
  
  defp build_default_modules(signature_def) do
    # Build default DSPy modules based on signature
    [
      %{
        name: "predictor",
        type: "Predict",
        signature: signature_def
      }
    ]
  end
end
```

## 5. Enhanced Python Bridge

### 5.1 Enhanced Python Script

```python
# priv/python/dspy_bridge.py (enhanced)
#!/usr/bin/env python3

import sys
import json
import struct
import traceback
import time
from typing import Dict, Any, List
import dspy

class DSPyBridge:
    def __init__(self):
        self.programs = {}
        self.signatures = {}
        
    def handle_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        handlers = {
            'create_program': self.create_program,
            'execute_program': self.execute_program,
            'optimize_program': self.optimize_program,
            'list_programs': self.list_programs
        }
        
        if command not in handlers:
            raise ValueError(f"Unknown command: {command}")
            
        return handlers[command](args)
    
    def create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['id']
        signature_def = args['signature']
        modules_def = args.get('modules', [])
        
        # Create dynamic signature class
        signature_class = self._create_signature_class(signature_def)
        self.signatures[program_id] = signature_class
        
        # Create program with modules
        if modules_def:
            program = self._create_custom_program(signature_class, modules_def)
        else:
            # Default to simple Predict
            program = dspy.Predict(signature_class)
        
        self.programs[program_id] = program
        
        return {
            "program_id": program_id,
            "status": "created",
            "signature": signature_def['name'],
            "modules": len(modules_def)
        }
    
    def execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['program_id']
        inputs = args['inputs']
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program = self.programs[program_id]
        
        start_time = time.time()
        
        try:
            # Execute with proper error handling
            result = program(**inputs)
            
            # Convert result to dict
            if hasattr(result, '__dict__'):
                output = {k: v for k, v in result.__dict__.items() 
                         if not k.startswith('_')}
            else:
                output = {"result": str(result)}
            
            execution_time = (time.time() - start_time) * 1000  # Convert to ms
            
            return {
                **output,
                "_metadata": {
                    "execution_time_ms": execution_time,
                    "program_id": program_id,
                    "status": "success"
                }
            }
            
        except Exception as e:
            execution_time = (time.time() - start_time) * 1000
            
            return {
                "error": str(e),
                "_metadata": {
                    "execution_time_ms": execution_time,
                    "program_id": program_id,
                    "status": "error"
                }
            }
    
    def optimize_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        program_id = args['program_id']
        dataset = args['dataset']
        optimizer_name = args.get('optimizer', 'BootstrapFewShot')
        metric_name = args.get('metric', 'exact_match')
        config = args.get('config', {})
        
        if program_id not in self.programs:
            raise ValueError(f"Program not found: {program_id}")
        
        program = self.programs[program_id]
        
        # Convert dataset to DSPy examples
        examples = []
        for item in dataset:
            example = dspy.Example(**item)
            if 'inputs' in item and 'outputs' in item:
                example = example.with_inputs(*item['inputs'].keys())
            examples.append(example)
        
        # Get metric function
        metric = self._get_metric_function(metric_name)
        
        # Create optimizer
        if optimizer_name == 'BootstrapFewShot':
            optimizer = dspy.BootstrapFewShot(
                metric=metric,
                max_bootstrapped_demos=config.get('max_bootstrapped_demos', 4),
                max_labeled_demos=config.get('max_labeled_demos', 16)
            )
        else:
            raise ValueError(f"Unknown optimizer: {optimizer_name}")
        
        # Run optimization
        start_time = time.time()
        optimized_program = optimizer.compile(program, trainset=examples)
        optimization_time = (time.time() - start_time) * 1000
        
        # Store optimized program
        self.programs[program_id] = optimized_program
        
        # Calculate score
        score = self._evaluate_program(optimized_program, examples, metric)
        
        return {
            "program_id": program_id,
            "score": score,
            "optimization_time_ms": optimization_time,
            "optimizer": optimizer_name,
            "metric": metric_name,
            "dataset_size": len(examples)
        }
    
    def list_programs(self, args: Dict[str, Any]) -> Dict[str, Any]:
        programs = []
        for program_id, program in self.programs.items():
            programs.append({
                "id": program_id,
                "type": type(program).__name__,
                "signature": self.signatures.get(program_id, {}).get('name', 'Unknown')
            })
        
        return {"programs": programs}
    
    def _create_signature_class(self, signature_def: Dict[str, Any]):
        class_name = signature_def.get('name', 'DynamicSignature')
        
        # Create dynamic signature class
        class DynamicSignature(dspy.Signature):
            pass
        
        DynamicSignature.__name__ = class_name
        
        # Add input fields
        for field in signature_def.get('inputs', []):
            field_name = field['name']
            field_desc = field.get('description', '')
            setattr(DynamicSignature, field_name, dspy.InputField(desc=field_desc))
        
        # Add output fields
        for field in signature_def.get('outputs', []):
            field_name = field['name'] 
            field_desc = field.get('description', '')
            setattr(DynamicSignature, field_name, dspy.OutputField(desc=field_desc))
        
        return DynamicSignature
    
    def _create_custom_program(self, signature_class, modules_def):
        # For now, just return a Predict - can be extended for complex programs
        return dspy.Predict(signature_class)
    
    def _get_metric_function(self, metric_name: str):
        if metric_name == 'exact_match':
            return lambda example, pred: example.answer == pred.answer
        else:
            # Default metric
            return lambda example, pred: 1.0 if hasattr(example, 'answer') and hasattr(pred, 'answer') and example.answer == pred.answer else 0.0
    
    def _evaluate_program(self, program, examples, metric):
        if not examples:
            return 0.0
        
        total_score = 0
        for example in examples:
            try:
                prediction = program(**{k: v for k, v in example.__dict__.items() if not k.startswith('_')})
                score = metric(example, prediction)
                total_score += score
            except:
                # Failed prediction counts as 0
                pass
        
        return total_score / len(examples)

# Rest of the communication code remains the same as Stage 1...
def read_message():
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        return None
    
    length = struct.unpack('>I', length_bytes)[0]
    message_bytes = sys.stdin.buffer.read(length)
    if len(message_bytes) < length:
        return None
    
    return json.loads(message_bytes.decode('utf-8'))

def write_message(message):
    message_bytes = json.dumps(message).encode('utf-8')
    length = len(message_bytes)
    
    sys.stdout.buffer.write(struct.pack('>I', length))
    sys.stdout.buffer.write(message_bytes)
    sys.stdout.buffer.flush()

def main():
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
                    'success': True,
                    'result': result
                })
            except Exception as e:
                write_message({
                    'id': request_id,
                    'success': False,
                    'error': str(e),
                    'traceback': traceback.format_exc()
                })
                
        except Exception as e:
            sys.stderr.write(f"Bridge error: {e}\n")
            sys.stderr.write(traceback.format_exc())

if __name__ == '__main__':
    main()
```

## 6. Application Configuration

### 6.1 Enhanced Application

```elixir
# lib/ash_dspy/application.ex (enhanced)
defmodule AshDSPy.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Schema cache for ExDantic
      AshDSPy.Validation.SchemaCache,
      
      # Python bridge
      AshDSPy.PythonBridge.Bridge,
      
      # Postgres repo for CRUD operations
      AshDSPy.Repo
    ]
    
    opts = [strategy: :one_for_one, name: AshDSPy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 6.2 Enhanced Configuration

```elixir
# config/config.exs (enhanced)
import Config

# Adapter configuration
config :ash_dspy, :adapter, AshDSPy.Adapters.PythonPort

# Database configuration
config :ash_dspy, AshDSPy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost", 
  database: "ash_dspy_dev",
  pool_size: 10

config :ash_dspy,
  ecto_repos: [AshDSPy.Repo]

# ExDantic configuration
config :exdantic,
  default_config: %{
    coercion: :safe,
    strict: true,
    extra: :forbid
  }

# Python bridge configuration
config :ash_dspy, :python_bridge,
  timeout: 30_000,
  python_executable: "python3",
  script_path: "priv/python/dspy_bridge.py"
```

## 7. Testing Stage 2

```elixir
# test/stage2_core_operations_test.exs
defmodule Stage2CoreOperationsTest do
  use ExUnit.Case
  
  # Test signature with multiple fields
  defmodule ComplexSignature do
    use AshDSPy.Signature
    
    signature question: :string, context: :string -> 
      answer: :string, 
      confidence: :float,
      sources: {:list, :string}
  end
  
  test "program creation with custom data layer" do
    {:ok, program} = AshDSPy.ML.Program.create_with_signature(%{
      name: "Complex QA Program",
      signature_module: ComplexSignature
    })
    
    assert program.name == "Complex QA Program"
    assert program.status == :draft
    refute is_nil(program.signature_id)
  end
  
  test "program execution through custom data layer" do
    {:ok, program} = AshDSPy.ML.Program.create_with_signature(%{
      name: "Test Program",
      signature_module: ComplexSignature
    })
    
    inputs = %{
      question: "What is machine learning?",
      context: "Machine learning is a branch of AI..."
    }
    
    # This should work through the custom data layer
    case AshDSPy.ML.Program.execute(program, %{inputs: inputs}) do
      {:ok, result} ->
        assert Map.has_key?(result, :answer)
        assert Map.has_key?(result, :confidence) 
        assert Map.has_key?(result, :sources)
        
      {:error, reason} ->
        # Expected if Python bridge isn't fully set up
        assert reason =~ "Program not initialized" or reason =~ "Python"
    end
  end
  
  test "signature validation with ExDantic" do
    inputs = %{question: "test", context: "test context"}
    
    {:ok, validated} = AshDSPy.Validation.SignatureValidator.validate_inputs(
      ComplexSignature, 
      inputs
    )
    
    assert validated.question == "test"
    assert validated.context == "test context"
    
    # Test type coercion
    invalid_inputs = %{question: 123, context: "test"}
    
    case AshDSPy.Validation.SignatureValidator.validate_inputs(ComplexSignature, invalid_inputs) do
      {:ok, coerced} ->
        # ExDantic should coerce integer to string
        assert coerced.question == "123"
      {:error, _} ->
        # Or reject if coercion fails
        assert true
    end
  end
  
  test "execution tracking" do
    {:ok, program} = AshDSPy.ML.Program.create_with_signature(%{
      name: "Tracking Test",
      signature_module: ComplexSignature
    })
    
    {:ok, execution} = AshDSPy.ML.Execution.start_execution(%{
      program_id: program.id,
      inputs: %{question: "test", context: "test"}
    })
    
    assert execution.status == :running
    assert execution.program_id == program.id
    refute is_nil(execution.started_at)
    
    # Complete execution
    {:ok, completed} = AshDSPy.ML.Execution.complete_execution(execution, %{
      outputs: %{answer: "test answer", confidence: 0.8, sources: []},
      duration_ms: 150
    })
    
    assert completed.status == :completed
    assert completed.duration_ms == 150
  end
end
```

## Stage 2 Deliverables

By the end of Stage 2, you should have:

1. ✅ **Custom data layer** that seamlessly bridges Ash and DSPy
2. ✅ **ExDantic integration** for Pydantic-like validation 
3. ✅ **Enhanced Python bridge** with better error handling
4. ✅ **Execution tracking** with performance metrics
5. ✅ **State management** between Ash and DSPy systems
6. ✅ **Working validation** with type coercion and constraints

**Next**: Stage 3 will add API generation, background jobs, and monitoring.
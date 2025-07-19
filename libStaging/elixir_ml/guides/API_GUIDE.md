# ElixirML API Guide

**Complete reference for the ElixirML unified machine learning schema system**

## 📚 Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Schema Creation](#schema-creation)
4. [Data Validation](#data-validation)
5. [ML-Specific Types](#ml-specific-types)
6. [Variable System](#variable-system)
7. [Performance Monitoring](#performance-monitoring)
8. [Error Handling](#error-handling)
9. [Advanced Features](#advanced-features)
10. [Production Usage](#production-usage)

## 🚀 Quick Start

### Installation

```elixir
# mix.exs
def deps do
  [
    {:elixir_ml, "~> 1.0"}
  ]
end
```

### Basic Usage

```elixir
# Create a schema
schema = ElixirML.Runtime.create_schema([
  {:temperature, :float, gteq: 0.0, lteq: 2.0},
  {:max_tokens, :integer, gteq: 1, lteq: 4096}
])

# Validate data
{:ok, validated} = ElixirML.Runtime.validate(schema, %{
  temperature: 0.7,
  max_tokens: 1000
})
```

## 🏗️ Core Concepts

### Schema
A schema defines the structure and constraints for data validation.

```elixir
schema = ElixirML.Runtime.create_schema([
  {:field_name, :field_type, constraint1: value1, constraint2: value2}
])
```

### Data Types
ElixirML supports standard and ML-specific data types:

- `:string` - Text data with length constraints
- `:integer` - Whole numbers with range constraints  
- `:float` - Decimal numbers with range constraints
- `:boolean` - True/false values
- `:atom` - Elixir atoms with choice constraints

### Constraints
Constraints define validation rules for each field:

- `gteq: value` - Greater than or equal to
- `lteq: value` - Less than or equal to
- `min_length: value` - Minimum string length
- `max_length: value` - Maximum string length
- `choices: [...]` - List of allowed values
- `optional: true` - Field is not required

## 📝 Schema Creation

### Basic Schema

```elixir
user_schema = ElixirML.Runtime.create_schema([
  {:name, :string, min_length: 1, max_length: 100},
  {:age, :integer, gteq: 0, lteq: 150},
  {:email, :string, min_length: 5},
  {:active, :boolean}
])
```

### ML Parameter Schema

```elixir
llm_schema = ElixirML.Runtime.create_schema([
  {:model, :string, choices: ["gpt-4", "gpt-3.5-turbo", "claude-3"]},
  {:temperature, :float, gteq: 0.0, lteq: 2.0},
  {:max_tokens, :integer, gteq: 1, lteq: 8192},
  {:top_p, :float, gteq: 0.0, lteq: 1.0},
  {:stream, :boolean, optional: true}
])
```

### Provider-Specific Schema

```elixir
openai_schema = ElixirML.Runtime.create_schema([
  {:model, :string, choices: ["gpt-4", "gpt-3.5-turbo"]},
  {:temperature, :float, gteq: 0.0, lteq: 2.0},
  {:max_tokens, :integer, gteq: 1, lteq: 4096}
], provider: :openai)

anthropic_schema = ElixirML.Runtime.create_schema([
  {:model, :string, choices: ["claude-3-opus", "claude-3-sonnet"]},
  {:max_tokens, :integer, gteq: 1, lteq: 100_000}
], provider: :anthropic)
```

### Schema Composition

```elixir
base_schema = ElixirML.Runtime.create_schema([
  {:temperature, :float, gteq: 0.0, lteq: 2.0}
])

extended_schema = ElixirML.Runtime.extend_schema(base_schema, [
  {:max_tokens, :integer, gteq: 1, lteq: 4096},
  {:top_p, :float, gteq: 0.0, lteq: 1.0}
])
```

## ✅ Data Validation

### Basic Validation

```elixir
# Valid data
data = %{temperature: 0.7, max_tokens: 1000}
{:ok, validated} = ElixirML.Runtime.validate(schema, data)

# Invalid data
invalid_data = %{temperature: 3.0, max_tokens: -1}
{:error, errors} = ElixirML.Runtime.validate(schema, invalid_data)
```

### Batch Validation

```elixir
dataset = [
  %{temperature: 0.7, max_tokens: 1000},
  %{temperature: 1.2, max_tokens: 2000},
  %{temperature: 0.3, max_tokens: 500}
]

results = ElixirML.Runtime.batch_validate(schema, dataset)
# Returns list of {:ok, validated} or {:error, errors}
```

### Validation with Metadata

```elixir
{:ok, validated, metadata} = ElixirML.Runtime.validate_with_metadata(
  schema, 
  data,
  include_performance: true
)

# metadata contains validation performance info
```

## 🧠 ML-Specific Types

### Basic ML Types

```elixir
alias ElixirML.Variable.MLTypes

# Probability variables (0.0 to 1.0)
prob_var = MLTypes.probability(:confidence, precision: 0.001)

# Temperature for LLM sampling
temp_var = MLTypes.temperature(:sampling_temp)

# Token counting
token_var = MLTypes.token_count(:max_tokens, max: 4096)

# Cost estimation
cost_var = MLTypes.cost_estimate(:operation_cost, currency: :usd)
```

### Advanced ML Types

```elixir
# High-dimensional embeddings
embedding_var = MLTypes.embedding(:text_embedding, dimensions: 1536)

# Quality assessment
quality_var = MLTypes.quality_score(:output_quality, scale: :likert_10)

# Reasoning complexity
complexity_var = MLTypes.reasoning_complexity(:task_complexity)

# Context window management
context_var = MLTypes.context_window(:context_size, model: "gpt-4")

# Latency estimation
latency_var = MLTypes.latency_estimate(:response_time, units: :milliseconds)

# Confidence scoring
confidence_var = MLTypes.confidence_score(:prediction_confidence)
```

### Provider-Optimized Types

```elixir
# OpenAI optimized variables
openai_vars = [
  MLTypes.temperature(:temperature),
  MLTypes.probability(:top_p),
  MLTypes.token_count(:max_tokens, max: 4096),
  MLTypes.cost_estimate(:cost, currency: :usd, scaling: :token_based)
]

# Anthropic optimized variables
anthropic_vars = [
  MLTypes.token_count(:max_tokens, max: 100_000),
  MLTypes.reasoning_complexity(:reasoning_depth),
  MLTypes.cost_estimate(:cost, scaling: :character_based)
]

# Groq optimized variables
groq_vars = [
  MLTypes.latency_estimate(:response_time, target: :sub_second),
  MLTypes.batch_size(:batch_size, max: 1000)
]
```

## 🎛️ Variable System

### Creating Variable Spaces

```elixir
# LLM optimization space
llm_space = MLTypes.llm_optimization_space()

# Teleprompter optimization space
teleprompter_space = MLTypes.teleprompter_optimization_space()

# Multi-objective optimization
multi_obj_space = MLTypes.multi_objective_space()

# Custom variable space
custom_space = ElixirML.Variable.Space.new(name: "Custom ML Space")
               |> ElixirML.Variable.Space.add_variables([
                 MLTypes.temperature(:temp),
                 MLTypes.probability(:confidence),
                 MLTypes.token_count(:tokens, max: 2000)
               ])
```

### Variable Space Operations

```elixir
# Validate configurations
config = %{temp: 0.7, confidence: 0.9, tokens: 1500}
{:ok, validated_config} = ElixirML.Variable.Space.validate_configuration(space, config)

# Generate random configurations
{:ok, random_config} = ElixirML.Variable.Space.random_configuration(space)

# Get variable bounds
bounds = ElixirML.Variable.Space.get_bounds(space)

# Check if configuration is valid
is_valid = ElixirML.Variable.Space.valid_configuration?(space, config)
```

### Custom Constraints

```elixir
# Add custom constraint function
constraint_fn = fn config ->
  if config.temperature > 1.0 and config.provider == :groq do
    {:error, "Groq doesn't support high temperature"}
  else
    {:ok, config}
  end
end

space = ElixirML.Variable.Space.new()
        |> ElixirML.Variable.Space.add_constraint(constraint_fn)
```

## 📊 Performance Monitoring

### Validation Benchmarking

```elixir
# Benchmark schema validation
dataset = [%{temperature: 0.7, max_tokens: 1000} | _rest]

stats = ElixirML.Performance.benchmark_validation(
  schema, 
  dataset,
  iterations: 1000,
  warmup: 100
)

# Results
stats.validations_per_second  # e.g., 65_789
stats.avg_time_microseconds   # e.g., 15.2
stats.total_validations       # e.g., 1000
```

### Memory Analysis

```elixir
memory_stats = ElixirML.Performance.analyze_memory_usage(schema, dataset)

# Results
memory_stats.initial_memory_bytes      # Memory before validation
memory_stats.final_memory_bytes        # Memory after validation
memory_stats.memory_used_bytes         # Memory consumed
memory_stats.memory_per_validation_bytes  # Average per validation
```

### Schema Complexity Profiling

```elixir
profile = ElixirML.Performance.profile_schema_complexity(schema)

# Results
profile.field_count                    # Number of fields
profile.total_complexity_score         # Overall complexity
profile.average_field_complexity       # Average per field
profile.optimization_recommendations   # Suggestions for improvement
```

### Variable Space Performance

```elixir
# Benchmark variable space validation
space_stats = ElixirML.Performance.benchmark_variable_space_validation(
  space, 
  configurations, 
  iterations: 100
)

# Analyze optimization space
analysis = ElixirML.Performance.analyze_optimization_space(space)
analysis.total_variables
analysis.total_complexity_score
analysis.estimated_search_time_seconds

# Identify performance bottlenecks
bottlenecks = ElixirML.Performance.identify_performance_bottlenecks(space)
```

## ❌ Error Handling

### Validation Errors

```elixir
case ElixirML.Runtime.validate(schema, data) do
  {:ok, validated} ->
    # Handle successful validation
    process_data(validated)
  
  {:error, %ElixirML.Schema.ValidationError{} = error} ->
    # Handle single validation error
    IO.puts("Field #{error.field}: #{error.message}")
  
  {:error, errors} when is_list(errors) ->
    # Handle multiple validation errors
    Enum.each(errors, fn error ->
      IO.puts("Field #{error.field}: #{error.message}")
    end)
end
```

### Error Information

```elixir
%ElixirML.Schema.ValidationError{
  field: :temperature,
  message: "Value 3.0 is greater than maximum allowed value 2.0",
  value: 3.0,
  constraints: %{lteq: 2.0}
}
```

### Custom Error Handling

```elixir
defmodule MyApp.ValidationHelpers do
  def format_errors(errors) when is_list(errors) do
    Enum.map(errors, &format_single_error/1)
  end
  
  def format_errors(error), do: [format_single_error(error)]
  
  defp format_single_error(%ElixirML.Schema.ValidationError{} = error) do
    %{
      field: error.field,
      message: error.message,
      received_value: error.value,
      constraints: error.constraints || %{}
    }
  end
end
```

## 🔬 Advanced Features

### JSON Schema Export

```elixir
# Export to JSON Schema format
json_schema = ElixirML.Runtime.to_json_schema(schema)

# Provider-optimized JSON Schema
openai_json = ElixirML.Runtime.to_json_schema(schema, provider: :openai)
anthropic_json = ElixirML.Runtime.to_json_schema(schema, provider: :anthropic)

# Custom JSON Schema options
custom_json = ElixirML.Runtime.to_json_schema(schema, 
  title: "My API Schema",
  description: "Schema for ML API parameters",
  version: "1.0.0"
)
```

### Schema Introspection

```elixir
# Get schema information
info = ElixirML.Runtime.schema_info(schema)
info.field_count
info.required_fields
info.optional_fields
info.constraint_summary

# Get field details
field_info = ElixirML.Runtime.field_info(schema, :temperature)
field_info.type
field_info.constraints
field_info.required?
```

### Runtime Schema Modification

```elixir
# Add fields to existing schema
updated_schema = ElixirML.Runtime.add_fields(schema, [
  {:new_field, :string, min_length: 1}
])

# Remove fields from schema
reduced_schema = ElixirML.Runtime.remove_fields(schema, [:optional_field])

# Update field constraints
modified_schema = ElixirML.Runtime.update_field(schema, :temperature, 
  gteq: 0.1, lteq: 1.5
)
```

### Conditional Validation

```elixir
# Schema with conditional constraints
conditional_schema = ElixirML.Runtime.create_schema([
  {:provider, :string, choices: ["openai", "anthropic"]},
  {:model, :string, min_length: 1},
  {:max_tokens, :integer, gteq: 1}
], conditional_constraints: [
  # If provider is "openai", max_tokens <= 4096
  {%{provider: "openai"}, %{max_tokens: [lteq: 4096]}},
  # If provider is "anthropic", max_tokens <= 100_000
  {%{provider: "anthropic"}, %{max_tokens: [lteq: 100_000]}}
])
```

## 🏭 Production Usage

### Phoenix Integration

```elixir
defmodule MyAppWeb.MLController do
  use MyAppWeb, :controller
  
  @schema ElixirML.Runtime.create_schema([
    {:prompt, :string, min_length: 1},
    {:temperature, :float, gteq: 0.0, lteq: 2.0}
  ])
  
  def generate(conn, params) do
    case ElixirML.Runtime.validate(@schema, params) do
      {:ok, validated} ->
        result = MLService.generate(validated)
        json(conn, result)
      
      {:error, errors} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: format_errors(errors)})
    end
  end
end
```

### GenServer State Validation

```elixir
defmodule MLWorker do
  use GenServer
  
  @config_schema ElixirML.Runtime.create_schema([
    {:worker_id, :string, min_length: 1},
    {:batch_size, :integer, gteq: 1, lteq: 100}
  ])
  
  def init(config) do
    case ElixirML.Runtime.validate(@config_schema, config) do
      {:ok, validated_config} ->
        {:ok, validated_config}
      
      {:error, errors} ->
        {:stop, {:invalid_config, errors}}
    end
  end
end
```

### Ecto Integration

```elixir
defmodule MyApp.MLModel do
  use Ecto.Schema
  import Ecto.Changeset
  
  @ml_params_schema ElixirML.Runtime.create_schema([
    {:temperature, :float, gteq: 0.0, lteq: 2.0},
    {:max_tokens, :integer, gteq: 1, lteq: 4096}
  ])
  
  def changeset(model, attrs) do
    model
    |> cast(attrs, [:name, :ml_params])
    |> validate_ml_params()
  end
  
  defp validate_ml_params(changeset) do
    case get_field(changeset, :ml_params) do
      nil -> changeset
      params ->
        case ElixirML.Runtime.validate(@ml_params_schema, params) do
          {:ok, _} -> changeset
          {:error, errors} ->
            add_error(changeset, :ml_params, "Invalid: #{format_errors(errors)}")
        end
    end
  end
end
```

### Performance Monitoring

```elixir
# Set up telemetry for production monitoring
:telemetry.attach_many(
  "elixir-ml-metrics",
  [
    [:elixir_ml, :validation, :success],
    [:elixir_ml, :validation, :error]
  ],
  &handle_telemetry/4,
  %{}
)

defp handle_telemetry([:elixir_ml, :validation, :success], measurements, metadata, _) do
  # Log to your monitoring system
  Logger.info("Validation success", 
    duration: measurements.duration_microseconds,
    operation: metadata.operation
  )
  
  # Send to Prometheus/StatsD/etc.
  :telemetry_metrics.counter([:elixir_ml, :validations, :total])
end
```

### Caching and Optimization

```elixir
# Pre-compile schemas for better performance
defmodule MyApp.Schemas do
  @llm_schema ElixirML.Runtime.create_schema([
    {:temperature, :float, gteq: 0.0, lteq: 2.0},
    {:max_tokens, :integer, gteq: 1, lteq: 4096}
  ])
  
  def llm_schema, do: @llm_schema
  
  # Cache validation results for repeated data
  def validate_with_cache(data) do
    cache_key = :crypto.hash(:md5, :erlang.term_to_binary(data))
    
    case :ets.lookup(:validation_cache, cache_key) do
      [{^cache_key, result}] -> result
      [] ->
        result = ElixirML.Runtime.validate(@llm_schema, data)
        :ets.insert(:validation_cache, {cache_key, result})
        result
    end
  end
end
```

## 📋 Best Practices

### Schema Design

1. **Keep schemas focused** - One schema per logical data structure
2. **Use appropriate constraints** - Set realistic min/max values
3. **Leverage provider optimizations** - Use provider-specific schemas
4. **Document your schemas** - Include clear field descriptions

### Performance

1. **Pre-compile schemas** - Define schemas at compile time when possible
2. **Use batch validation** - Validate multiple records together
3. **Monitor performance** - Use telemetry for production monitoring
4. **Cache when appropriate** - Cache validation results for repeated data

### Error Handling

1. **Provide clear error messages** - Help users understand what went wrong
2. **Include constraint information** - Show what values are allowed
3. **Handle errors gracefully** - Don't crash on validation failures
4. **Log validation failures** - Track common validation issues

### Testing

1. **Test with valid data** - Ensure schemas accept correct input
2. **Test with invalid data** - Verify proper error handling
3. **Test edge cases** - Boundary values, empty strings, etc.
4. **Performance test** - Ensure schemas meet performance requirements

## 🔗 API Reference

### ElixirML.Runtime

- `create_schema/1,2` - Create a new schema
- `validate/2` - Validate data against schema
- `batch_validate/2` - Validate multiple records
- `to_json_schema/1,2` - Export to JSON Schema format
- `schema_info/1` - Get schema information

### ElixirML.Variable.MLTypes

- `probability/2` - Create probability variable
- `temperature/2` - Create temperature variable
- `token_count/2` - Create token count variable
- `embedding/2` - Create embedding variable
- `llm_optimization_space/0` - Create LLM optimization space

### ElixirML.Performance

- `benchmark_validation/3` - Benchmark validation performance
- `analyze_memory_usage/2` - Analyze memory consumption
- `profile_schema_complexity/1` - Profile schema complexity
- `identify_performance_bottlenecks/1` - Find performance issues

---

**ElixirML**: The unified foundation for machine learning in Elixir. 🚀 
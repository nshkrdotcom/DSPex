defmodule DSPEx.Teleprompter.SIMBA.ElixirMLSchemas do
  @moduledoc """
  ElixirML validation schemas for SIMBA teleprompter data structures.

  This module provides comprehensive validation schemas using ElixirML for:
  - Trajectory data and metadata
  - Bucket statistics and grouping
  - Performance metrics and scoring
  - Training examples and predictions
  - Strategy configuration and results

  These schemas ensure data integrity throughout the SIMBA optimization process
  while leveraging ElixirML's ML-native types and provider optimizations.
  """

  alias ElixirML.Runtime
  alias ElixirML.JsonSchema

  @doc """
  Schema for SIMBA trajectory validation.

  Validates complete execution trajectory including inputs, outputs, scoring,
  and execution metadata used for pattern analysis.
  """
  def trajectory_schema do
    fields = [
      # Core trajectory data
      {:inputs, :map, required: true},
      {:outputs, :map, required: true},
      {:score, :float, required: true, gteq: 0.0, lteq: 1.0},

      # Execution metadata
      {:success, :boolean, required: true},
      {:duration, :integer, required: false, gteq: 0, range: {0, 1_000_000}},
      {:model_config, :map, required: false},
      {:error, :string, required: false},
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Trajectory",
      description: "SIMBA execution trajectory with ML-native validation"
    )
  end

  @doc """
  Schema for SIMBA bucket validation.

  Validates bucket structure containing grouped trajectories with
  performance statistics for strategy selection.
  """
  @spec bucket_schema() :: map()
  def bucket_schema do
    fields = [
      # Trajectory collection
      {:trajectories, {:array, :map}, required: true, min_items: 1},

      # Performance statistics
      {:max_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:min_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:avg_score, :float, required: true, gteq: 0.0, lteq: 1.0},

      # Gap analysis for strategy selection
      {:max_to_min_gap, :float, required: true, gteq: 0.0},
      {:max_to_avg_gap, :float, required: true, gteq: 0.0},

      # Additional bucket metadata
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Bucket",
      description: "SIMBA performance bucket with trajectory grouping"
    )
  end

  @doc """
  Schema for SIMBA performance metrics validation.

  Validates performance tracking data used for optimization convergence
  and strategy effectiveness measurement.
  """
  def performance_metrics_schema do
    fields = [
      # Core performance metrics
      {:accuracy, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:f1_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:precision, :float, required: false, gteq: 0.0, lteq: 1.0},
      {:recall, :float, required: false, gteq: 0.0, lteq: 1.0},

      # Execution performance
      {:latency_ms, :integer, required: true, gt: 0, range: {1, 1_000_000}},
      {:throughput, :float, required: false, gt: 0.0, range: {0.0, 1000.0}},

      # Dataset statistics
      {:example_count, :integer, required: true, gteq: 0, range: {0, 1_000_000}},
      {:success_count, :integer, required: true, gteq: 0, range: {0, 1_000_000}},
      {:failure_count, :integer, required: true, gteq: 0, range: {0, 1_000_000}},

      # Optimization metrics
      {:improvement_score, :float, required: false, gteq: 0.0},
      {:convergence_indicator, :float, required: false, gteq: 0.0, lteq: 1.0}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Performance Metrics",
      description: "SIMBA optimization performance tracking"
    )
  end

  @doc """
  Schema for SIMBA training example validation.

  Validates training examples used in mini-batch optimization with
  proper input/output field structure and quality scoring.
  """
  def training_example_schema do
    fields = [
      # Core example data
      {:inputs, :map, required: true},
      {:outputs, :map, required: true},

      # Quality and validation
      {:quality_score, :float, required: false, gteq: 0.0, lteq: 1.0},
      {:validated, :boolean, required: false, default: false},

      # Example metadata
      {:example_id, :string, required: false},
      {:source, :string, required: false},
      {:created_at, :string, required: false},
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Training Example",
      description: "SIMBA training example with quality scoring"
    )
  end

  @doc """
  Schema for SIMBA strategy configuration validation.

  Validates strategy application configuration including constraints,
  thresholds, and optimization parameters.
  """
  def strategy_config_schema do
    fields = [
      # Strategy identification
      {:strategy_name, :string, required: true, min_length: 1},
      {:strategy_version, :string, required: false},

      # Application thresholds
      {:min_improvement_threshold, :float, required: false, gteq: 0.0, lteq: 1.0, default: 0.1},
      {:max_score_threshold, :float, required: false, gteq: 0.0, lteq: 1.0, default: 0.1},

      # Strategy-specific parameters
      {:max_demos, :integer, required: false, gteq: 0, lteq: 100, default: 4},
      {:demo_input_field_maxlen, :integer,
       required: false, gt: 0, range: {1, 10_000_000}, default: 100_000},
      {:temperature, :float, required: false, gt: 0.0, lteq: 2.0, default: 0.2},

      # Application control
      {:enabled, :boolean, required: false, default: true},
      {:priority, :integer, required: false, gteq: 0, lteq: 10, default: 5},

      # Configuration metadata
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Strategy Configuration",
      description: "SIMBA strategy configuration with ML-aware parameters"
    )
  end

  @doc """
  Schema for SIMBA optimization result validation.

  Validates the complete optimization result including the optimized program,
  performance improvements, and optimization statistics.
  """
  @spec optimization_result_schema() :: map()
  def optimization_result_schema do
    fields = [
      # Optimization success
      {:success, :boolean, required: true},
      {:improved, :boolean, required: true},

      # Performance comparison
      {:initial_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:final_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:improvement_delta, :float, required: true, gteq: -1.0, lteq: 1.0},

      # Optimization statistics
      {:steps_taken, :integer, required: true, gteq: 0, range: {0, 1000}},
      {:strategies_applied, {:array, :string}, required: true},
      {:total_trajectories, :integer, required: true, gteq: 0, range: {0, 1_000_000}},
      {:successful_trajectories, :integer, required: true, gteq: 0, range: {0, 1_000_000}},

      # Timing information
      {:duration_ms, :integer, required: true, gt: 0, range: {1, 10_000_000}},
      {:convergence_step, :integer, required: false, gteq: 0, range: {0, 1000}},

      # Result metadata
      {:correlation_id, :string, required: false},
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Optimization Result",
      description: "SIMBA optimization result with performance analysis"
    )
  end

  @doc """
  Schema for SIMBA bucket statistics validation.

  Validates detailed bucket analysis statistics used for strategy
  selection and trajectory pattern analysis.
  """
  @spec bucket_statistics_schema() :: map()
  def bucket_statistics_schema do
    fields = [
      # Basic statistics
      {:count, :integer, required: true, gteq: 0, range: {0, 1_000_000}},
      {:mean_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:median_score, :float, required: true, gteq: 0.0, lteq: 1.0},
      {:std_dev, :float, required: true, gteq: 0.0},

      # Performance distribution
      {:score_distribution, {:array, :float}, required: true},
      {:percentiles, :map, required: false},

      # Quality metrics
      {:consistency_score, :float, required: false, gteq: 0.0, lteq: 1.0},
      {:reliability_score, :float, required: false, gteq: 0.0, lteq: 1.0},

      # Pattern analysis
      {:common_patterns, {:array, :string}, required: false},
      {:outlier_count, :integer, required: false, gteq: 0, range: {0, 1_000_000}},

      # Metadata
      {:analysis_timestamp, :string, required: false},
      {:metadata, :map, required: false, default: %{}}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Bucket Statistics",
      description: "SIMBA bucket analysis statistics"
    )
  end

  # Validation functions

  @doc """
  Validates trajectory data using ElixirML schema.
  """
  def validate_trajectory(data) do
    schema = trajectory_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates bucket data using ElixirML schema.
  """
  @spec validate_bucket(map()) :: {:ok, map()} | {:error, term()}
  def validate_bucket(data) do
    schema = bucket_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates performance metrics using ElixirML schema.
  """
  def validate_performance_metrics(data) do
    schema = performance_metrics_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates training example using ElixirML schema.
  """
  def validate_training_example(data) do
    schema = training_example_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates strategy configuration using ElixirML schema.
  """
  def validate_strategy_config(data) do
    schema = strategy_config_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates optimization result using ElixirML schema.
  """
  @spec validate_optimization_result(map()) :: {:ok, map()} | {:error, term()}
  def validate_optimization_result(data) do
    schema = optimization_result_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates bucket statistics using ElixirML schema.
  """
  @spec validate_bucket_statistics(map()) :: {:ok, map()} | {:error, term()}
  def validate_bucket_statistics(data) do
    schema = bucket_statistics_schema()
    Runtime.validate(schema, data)
  end

  @doc """
  Validates a list of training examples.
  """
  def validate_training_examples(examples) when is_list(examples) do
    schema = training_example_schema()

    results =
      Enum.map(examples, fn example ->
        Runtime.validate(schema, example)
      end)

    # Check if all validations succeeded
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        validated_examples = Enum.map(results, fn {:ok, validated} -> validated end)
        {:ok, validated_examples}

      {:error, _} = error ->
        error
    end
  end

  # JSON Schema generation with provider optimization

  @doc """
  Generates JSON Schema for trajectory data with provider optimization.
  """
  def to_json_schema(schema, opts \\ []) do
    provider = Keyword.get(opts, :provider, :generic)
    JsonSchema.generate(schema, provider: provider)
  end

  @doc """
  Extracts variables from schema for optimization systems.
  """
  def extract_variables(schema) do
    Runtime.extract_variables(schema)
  end

  @doc """
  Creates provider-optimized JSON schema for LLM instruction generation.
  """
  @spec create_instruction_schema(module(), atom()) :: map()
  def create_instruction_schema(_signature_module, provider \\ :openai) do
    # Create schema based on signature for instruction generation
    fields = [
      {:signature_name, :string, required: true},
      {:input_fields, {:array, :string}, required: true},
      {:output_fields, {:array, :string}, required: true},
      {:current_instruction, :string, required: false},
      {:performance_score, :probability, required: true},
      {:improvement_areas, {:array, :string}, required: false},
      {:suggested_instruction, :string, required: true}
    ]

    schema =
      Runtime.create_schema(fields,
        title: "LLM Instruction Generation",
        description: "Schema for generating optimized instructions via LLM"
      )

    to_json_schema(schema, provider: provider)
  end

  @doc """
  Creates schema for trajectory analysis patterns.
  """
  @spec create_pattern_analysis_schema() :: map()
  def create_pattern_analysis_schema do
    fields = [
      {:pattern_type, :string, required: true},
      {:confidence, :probability, required: true},
      {:frequency, :integer, required: true, gteq: 0},
      {:impact_score, :probability, required: true},
      {:examples, {:array, :map}, required: false},
      {:recommendations, {:array, :string}, required: false}
    ]

    Runtime.create_schema(fields,
      title: "SIMBA Pattern Analysis",
      description: "Schema for trajectory pattern analysis"
    )
  end
end

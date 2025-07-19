defmodule DSPEx.Teleprompter.SIMBA.SinterSchemas do
  @moduledoc """
  Sinter validation schemas for SIMBA teleprompter data structures.

  This module provides comprehensive validation schemas for:
  - Trajectory data and metadata
  - Bucket statistics and grouping
  - Performance metrics and scoring
  - Training examples and predictions
  - Strategy configuration and results

  These schemas ensure data integrity throughout the SIMBA optimization process.
  """

  @doc """
  Schema for SIMBA trajectory validation.

  Validates complete execution trajectory including inputs, outputs, scoring,
  and execution metadata used for pattern analysis.
  """
  def trajectory_schema do
    Sinter.Schema.define(
      [
        # Core trajectory data
        {:inputs, :map, [required: true]},
        {:outputs, :map, [required: true]},
        {:score, :float, [required: true, gteq: 0.0, lteq: 1.0]},

        # Execution metadata
        {:success, :boolean, [required: true]},
        {:duration, :integer, [optional: true, gteq: 0]},
        {:model_config, :map, [optional: true]},
        {:error, :string, [optional: true]},
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Trajectory"
    )
  end

  @doc """
  Schema for SIMBA bucket validation.

  Validates bucket structure containing grouped trajectories with
  performance statistics for strategy selection.
  """
  def bucket_schema do
    Sinter.Schema.define(
      [
        # Trajectory collection
        {:trajectories, {:array, :map}, [required: true, min_items: 1]},

        # Performance statistics
        {:max_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:min_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:avg_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},

        # Gap analysis for strategy selection
        {:max_to_min_gap, :float, [required: true, gteq: 0.0]},
        {:max_to_avg_gap, :float, [required: true, gteq: 0.0]},

        # Additional bucket metadata
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Bucket"
    )
  end

  @doc """
  Schema for SIMBA performance metrics validation.

  Validates performance tracking data used for optimization convergence
  and strategy effectiveness measurement.
  """
  def performance_metrics_schema do
    Sinter.Schema.define(
      [
        # Core performance metrics
        {:accuracy, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:f1_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:precision, :float, [optional: true, gteq: 0.0, lteq: 1.0]},
        {:recall, :float, [optional: true, gteq: 0.0, lteq: 1.0]},

        # Execution performance
        {:latency_ms, :integer, [required: true, gt: 0]},
        {:throughput, :float, [optional: true, gt: 0.0]},

        # Dataset statistics
        {:example_count, :integer, [required: true, gteq: 0]},
        {:success_count, :integer, [required: true, gteq: 0]},
        {:failure_count, :integer, [required: true, gteq: 0]},

        # Optimization metrics
        {:improvement_score, :float, [optional: true, gteq: 0.0]},
        {:convergence_indicator, :float, [optional: true, gteq: 0.0, lteq: 1.0]}
      ],
      title: "SIMBA Performance Metrics"
    )
  end

  @doc """
  Schema for SIMBA training example validation.

  Validates training examples used in mini-batch optimization with
  proper input/output field structure and quality scoring.
  """
  def training_example_schema do
    Sinter.Schema.define(
      [
        # Core example data
        {:inputs, :map, [required: true]},
        {:outputs, :map, [required: true]},

        # Quality and validation
        {:quality_score, :float, [optional: true, gteq: 0.0, lteq: 1.0]},
        {:validated, :boolean, [optional: true, default: false]},

        # Example metadata
        {:example_id, :string, [optional: true]},
        {:source, :string, [optional: true]},
        {:created_at, :string, [optional: true]},
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Training Example"
    )
  end

  @doc """
  Schema for SIMBA strategy configuration validation.

  Validates strategy application configuration including constraints,
  thresholds, and optimization parameters.
  """
  def strategy_config_schema do
    Sinter.Schema.define(
      [
        # Strategy identification
        {:strategy_name, :string, [required: true, min_length: 1]},
        {:strategy_version, :string, [optional: true]},

        # Application thresholds
        {:min_improvement_threshold, :float,
         [optional: true, gteq: 0.0, lteq: 1.0, default: 0.1]},
        {:max_score_threshold, :float, [optional: true, gteq: 0.0, lteq: 1.0, default: 0.1]},

        # Strategy-specific parameters
        {:max_demos, :integer, [optional: true, gteq: 0, lteq: 100, default: 4]},
        {:demo_input_field_maxlen, :integer, [optional: true, gt: 0, default: 100_000]},
        {:temperature, :float, [optional: true, gt: 0.0, lteq: 2.0, default: 0.2]},

        # Application control
        {:enabled, :boolean, [optional: true, default: true]},
        {:priority, :integer, [optional: true, gteq: 0, lteq: 10, default: 5]},

        # Configuration metadata
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Strategy Configuration"
    )
  end

  @doc """
  Schema for SIMBA optimization result validation.

  Validates the complete optimization result including the optimized program,
  performance improvements, and optimization statistics.
  """
  def optimization_result_schema do
    Sinter.Schema.define(
      [
        # Optimization success
        {:success, :boolean, [required: true]},
        {:improved, :boolean, [required: true]},

        # Performance comparison
        {:initial_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:final_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:improvement_delta, :float, [required: true, gteq: -1.0, lteq: 1.0]},

        # Optimization statistics
        {:steps_taken, :integer, [required: true, gteq: 0]},
        {:strategies_applied, {:array, :string}, [required: true]},
        {:total_trajectories, :integer, [required: true, gteq: 0]},
        {:successful_trajectories, :integer, [required: true, gteq: 0]},

        # Timing information
        {:duration_ms, :integer, [required: true, gt: 0]},
        {:convergence_step, :integer, [optional: true, gteq: 0]},

        # Result metadata
        {:correlation_id, :string, [optional: true]},
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Optimization Result"
    )
  end

  @doc """
  Schema for SIMBA bucket statistics validation.

  Validates detailed bucket analysis statistics used for strategy
  selection and performance tracking.
  """
  def bucket_statistics_schema do
    Sinter.Schema.define(
      [
        # Basic counts
        {:trajectory_count, :integer, [required: true, gteq: 0]},
        {:successful_count, :integer, [required: true, gteq: 0]},
        {:failed_count, :integer, [required: true, gteq: 0]},

        # Score statistics
        {:max_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:min_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:avg_score, :float, [required: true, gteq: 0.0, lteq: 1.0]},
        {:median_score, :float, [optional: true, gteq: 0.0, lteq: 1.0]},

        # Distribution analysis
        {:score_variance, :float, [required: true, gteq: 0.0]},
        {:score_std_dev, :float, [optional: true, gteq: 0.0]},

        # Improvement indicators
        {:improvement_potential, :boolean, [required: true]},
        {:strategy_applicable, :boolean, [optional: true]},

        # Additional statistics
        {:metadata, :map, [optional: true, default: %{}]}
      ],
      title: "SIMBA Bucket Statistics"
    )
  end

  @doc """
  Helper function to validate trajectory data using Sinter.
  """
  def validate_trajectory(trajectory_data) do
    Sinter.Validator.validate(trajectory_schema(), trajectory_data)
  end

  @doc """
  Helper function to validate bucket data using Sinter.
  """
  def validate_bucket(bucket_data) do
    Sinter.Validator.validate(bucket_schema(), bucket_data)
  end

  @doc """
  Helper function to validate performance metrics using Sinter.
  """
  def validate_performance_metrics(metrics_data) do
    Sinter.Validator.validate(performance_metrics_schema(), metrics_data)
  end

  @doc """
  Helper function to validate training example using Sinter.
  """
  def validate_training_example(example_data) do
    Sinter.Validator.validate(training_example_schema(), example_data)
  end

  @doc """
  Helper function to validate strategy configuration using Sinter.
  """
  def validate_strategy_config(config_data) do
    Sinter.Validator.validate(strategy_config_schema(), config_data)
  end

  @doc """
  Helper function to validate optimization result using Sinter.
  """
  def validate_optimization_result(result_data) do
    Sinter.Validator.validate(optimization_result_schema(), result_data)
  end

  @doc """
  Helper function to validate bucket statistics using Sinter.
  """
  def validate_bucket_statistics(stats_data) do
    Sinter.Validator.validate(bucket_statistics_schema(), stats_data)
  end

  @doc """
  Batch validation helper for multiple trajectories.
  """
  def validate_trajectories(trajectories) when is_list(trajectories) do
    schema = trajectory_schema()
    results = Enum.map(trajectories, &Sinter.Validator.validate(schema, &1))

    # Check if all validations succeeded
    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, data} -> data end)}
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Batch validation helper for multiple training examples.
  """
  def validate_training_examples(examples) when is_list(examples) do
    schema = training_example_schema()
    results = Enum.map(examples, &Sinter.Validator.validate(schema, &1))

    # Check if all validations succeeded
    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, data} -> data end)}
      {:error, errors} -> {:error, errors}
    end
  end
end

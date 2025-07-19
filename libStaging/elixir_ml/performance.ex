defmodule ElixirML.Performance do
  @moduledoc """
  Performance monitoring and optimization utilities for ElixirML.

  This module provides tools for monitoring validation performance and
  optimizing schemas for high-throughput scenarios common in DSPEx.

  Enhanced from Sinter performance patterns with ML-specific optimizations.
  """

  alias ElixirML.{Runtime, Variable}

  @doc """
  Benchmarks validation performance for a schema and dataset.

  Returns timing information useful for optimizing DSPEx programs.

  ## Parameters

    * `schema` - The ElixirML Runtime schema to benchmark
    * `dataset` - Sample data for benchmarking
    * `opts` - Benchmark options

  ## Options

    * `:iterations` - Number of iterations to run (default: 1000)
    * `:warmup` - Number of warmup iterations (default: 100)

  ## Returns

    * Map with timing statistics

  ## Examples

      iex> schema = Runtime.create_schema([{:id, :integer, gteq: 1}])
      iex> dataset = [%{id: 1}, %{id: 2}, %{id: 3}]
      iex> stats = ElixirML.Performance.benchmark_validation(schema, dataset)
      iex> is_number(stats.avg_time_microseconds)
      true
  """
  @spec benchmark_validation(Runtime.t(), [map()], keyword()) :: map()
  def benchmark_validation(schema, dataset, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    warmup = Keyword.get(opts, :warmup, 100)

    # Handle empty datasets
    if Enum.empty?(dataset) do
      %{
        total_time_microseconds: 0,
        total_validations: 0,
        avg_time_microseconds: 0,
        validations_per_second: 0
      }
    else
      # Warmup
      Enum.each(1..warmup, fn _ ->
        Enum.each(dataset, &Runtime.validate(schema, &1))
      end)

      # Benchmark
      {total_time, _} =
        :timer.tc(fn ->
          Enum.each(1..iterations, fn _ ->
            Enum.each(dataset, &Runtime.validate(schema, &1))
          end)
        end)

      total_validations = iterations * length(dataset)
      avg_time_per_validation = total_time / total_validations

      %{
        total_time_microseconds: total_time,
        total_validations: total_validations,
        avg_time_microseconds: avg_time_per_validation,
        validations_per_second: trunc(1_000_000 / avg_time_per_validation)
      }
    end
  end

  @doc """
  Benchmarks variable space validation performance.

  Specialized for ElixirML Variable.Space validation patterns.
  """
  @spec benchmark_variable_space_validation(Variable.Space.t(), [map()], keyword()) :: map()
  def benchmark_variable_space_validation(space, configurations, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)
    warmup = Keyword.get(opts, :warmup, 10)

    # Handle empty configurations
    if Enum.empty?(configurations) do
      %{
        total_time_microseconds: 0,
        total_validations: 0,
        avg_time_microseconds: 0,
        validations_per_second: 0
      }
    else
      # Warmup
      Enum.each(1..warmup, fn _ ->
        Enum.each(configurations, &Variable.Space.validate_configuration(space, &1))
      end)

      # Benchmark
      {total_time, _} =
        :timer.tc(fn ->
          Enum.each(1..iterations, fn _ ->
            Enum.each(configurations, &Variable.Space.validate_configuration(space, &1))
          end)
        end)

      total_validations = iterations * length(configurations)
      avg_time_per_validation = total_time / total_validations

      %{
        total_time_microseconds: total_time,
        total_validations: total_validations,
        avg_time_microseconds: avg_time_per_validation,
        validations_per_second: trunc(1_000_000 / avg_time_per_validation)
      }
    end
  end

  @doc """
  Analyzes memory usage during validation.

  Useful for optimizing memory consumption in long-running DSPEx programs.

  ## Parameters

    * `schema` - The schema to analyze
    * `dataset` - Sample data for analysis

  ## Returns

    * Map with memory usage statistics
  """
  @spec analyze_memory_usage(Runtime.t(), [map()]) :: map()
  def analyze_memory_usage(schema, dataset) do
    # Force garbage collection before measurement
    :erlang.garbage_collect()
    {_, initial_memory} = :erlang.process_info(self(), :memory)

    # Perform validations
    results = Enum.map(dataset, &Runtime.validate(schema, &1))

    # Measure memory after validation
    :erlang.garbage_collect()
    {_, final_memory} = :erlang.process_info(self(), :memory)

    memory_used = final_memory - initial_memory
    successful_validations = Enum.count(results, &match?({:ok, _}, &1))

    %{
      initial_memory_bytes: initial_memory,
      final_memory_bytes: final_memory,
      memory_used_bytes: memory_used,
      memory_per_validation_bytes:
        if(successful_validations > 0, do: memory_used / successful_validations, else: 0),
      successful_validations: successful_validations,
      total_validations: length(dataset)
    }
  end

  @doc """
  Profiles schema complexity for optimization recommendations.

  Analyzes a schema to identify potential performance bottlenecks and
  suggests optimizations for DSPEx usage.

  ## Parameters

    * `schema` - The ElixirML Runtime schema to profile

  ## Returns

    * Map with complexity analysis and optimization suggestions
  """
  @spec profile_schema_complexity(Runtime.t()) :: map()
  def profile_schema_complexity(schema) do
    fields = schema.fields
    field_count = map_size(fields)

    # Analyze field complexity
    complexity_scores =
      Enum.map(fields, fn {name, field_def} ->
        {name, calculate_field_complexity(field_def)}
      end)

    total_complexity = Enum.sum(Enum.map(complexity_scores, fn {_, score} -> score end))
    avg_complexity = if field_count > 0, do: total_complexity / field_count, else: 0

    # Generate recommendations
    recommendations = generate_optimization_recommendations(fields, complexity_scores)

    %{
      field_count: field_count,
      total_complexity_score: total_complexity,
      average_field_complexity: avg_complexity,
      complexity_by_field: Map.new(complexity_scores),
      optimization_recommendations: recommendations
    }
  end

  @doc """
  Calculates complexity score for individual variables.

  Enhanced for ML-specific variable types.
  """
  @spec calculate_variable_complexity(Variable.t()) :: number()
  def calculate_variable_complexity(%Variable{} = variable) do
    base_score = 1.0

    # Type complexity scoring
    type_score =
      case variable.type do
        atom when atom in [:float, :integer, :boolean] -> 1.0
        :choice -> 1.5
        :module -> 2.0
        # Composite variables are most complex
        :composite -> 3.0
        _ -> 1.5
      end

    # Constraint complexity scoring
    constraint_score =
      if is_map(variable.constraints), do: map_size(variable.constraints) * 0.3, else: 0

    # Dependencies add complexity
    dependency_score = length(variable.dependencies) * 0.5

    # ML-specific metadata complexity
    ml_score = calculate_ml_metadata_complexity(variable.metadata)

    base_score + type_score + constraint_score + dependency_score + ml_score
  end

  @doc """
  Analyzes optimization space for performance characteristics.
  """
  @spec analyze_optimization_space(Variable.Space.t()) :: map()
  def analyze_optimization_space(space) do
    variables = Map.values(space.variables)
    variable_count = length(variables)

    # Calculate dimensionality score
    dimensionality_score = calculate_dimensionality_score(variables)

    # Analyze complexity breakdown
    complexity_breakdown =
      variables
      |> Enum.map(fn var -> {var.name, calculate_variable_complexity(var)} end)
      |> Map.new()

    # Generate performance tips
    performance_tips = generate_space_performance_tips(space, variables)

    %{
      dimensionality_score: dimensionality_score,
      variable_count: variable_count,
      complexity_breakdown: complexity_breakdown,
      performance_tips: performance_tips,
      estimated_search_time: estimate_search_time(dimensionality_score, variable_count)
    }
  end

  @doc """
  Identifies performance bottlenecks in variable spaces.
  """
  @spec identify_performance_bottlenecks(Variable.Space.t()) :: map()
  def identify_performance_bottlenecks(space) do
    variables = Map.values(space.variables)

    # Identify potential bottlenecks
    bottlenecks = []

    # Check for high-dimensional variables
    high_dim_vars =
      Enum.filter(variables, fn var ->
        (var.type == :composite and
           get_in(var.metadata, [:dimensions])) &&
          get_in(var.metadata, [:dimensions]) > 512
      end)

    bottlenecks =
      if length(high_dim_vars) > 0 do
        [
          "High-dimensional embedding variables: #{inspect(Enum.map(high_dim_vars, & &1.name))}"
          | bottlenecks
        ]
      else
        bottlenecks
      end

    # Check for too many variables
    bottlenecks =
      if length(variables) > 20 do
        ["High variable count (#{length(variables)}) may slow optimization" | bottlenecks]
      else
        bottlenecks
      end

    # Check for complex constraints
    complex_vars =
      Enum.filter(variables, fn var ->
        calculate_variable_complexity(var) > 5.0
      end)

    bottlenecks =
      if length(complex_vars) > 0 do
        [
          "Complex variables detected: #{inspect(Enum.map(complex_vars, & &1.name))}"
          | bottlenecks
        ]
      else
        bottlenecks
      end

    # Performance metrics
    performance_metrics = %{
      total_variables: length(variables),
      complex_variables: length(complex_vars),
      high_dimensional_variables: length(high_dim_vars),
      average_complexity:
        Enum.sum(Enum.map(variables, &calculate_variable_complexity/1)) / length(variables)
    }

    # Optimization suggestions
    suggestions = generate_bottleneck_suggestions(bottlenecks, performance_metrics)

    %{
      potential_bottlenecks: bottlenecks,
      performance_metrics: performance_metrics,
      optimization_suggestions: suggestions
    }
  end

  # Private helper functions

  @spec calculate_field_complexity(map()) :: number()
  defp calculate_field_complexity(field_def) do
    base_score = 1.0

    # Type complexity scoring
    type_score =
      case field_def.type do
        atom when atom in [:string, :integer, :float, :boolean, :atom] -> 1.0
        _ -> 1.5
      end

    # Constraint complexity scoring
    constraint_score =
      if is_map(field_def.constraints), do: map_size(field_def.constraints) * 0.5, else: 0

    # Required fields are slightly more complex due to validation
    required_score = if field_def.required, do: 0.2, else: 0.0

    base_score + type_score + constraint_score + required_score
  end

  @spec generate_optimization_recommendations(map(), [{atom(), number()}]) :: [String.t()]
  defp generate_optimization_recommendations(fields, complexity_scores) do
    recommendations = []

    # Check for overly complex fields
    complex_fields =
      complexity_scores
      |> Enum.filter(fn {_, score} -> score > 5.0 end)
      |> Enum.map(fn {name, _} -> name end)

    recommendations =
      if length(complex_fields) > 0 do
        ["Consider simplifying complex fields: #{inspect(complex_fields)}" | recommendations]
      else
        recommendations
      end

    # Check for too many fields
    recommendations =
      if map_size(fields) > 20 do
        [
          "Consider reducing field count (#{map_size(fields)}) for better performance"
          | recommendations
        ]
      else
        recommendations
      end

    # Default recommendation if schema looks good
    if Enum.empty?(recommendations) do
      ["Schema is well-optimized for performance"]
    else
      Enum.reverse(recommendations)
    end
  end

  defp calculate_ml_metadata_complexity(metadata) when is_map(metadata) do
    # ML-specific complexity factors
    ml_factors = [
      :dimensions,
      :ml_type,
      :calibration_method,
      :tokenizer,
      :currency,
      :assessment_scale
    ]

    ml_complexity = Enum.count(ml_factors, &Map.has_key?(metadata, &1)) * 0.2

    # High-dimensional embeddings add significant complexity
    dimension_complexity =
      case Map.get(metadata, :dimensions) do
        dim when is_integer(dim) and dim > 1000 -> 2.0
        dim when is_integer(dim) and dim > 100 -> 1.0
        dim when is_integer(dim) -> 0.5
        _ -> 0.0
      end

    ml_complexity + dimension_complexity
  end

  defp calculate_ml_metadata_complexity(_), do: 0.0

  defp calculate_dimensionality_score(variables) do
    # Base dimensionality from variable count
    base_dim = length(variables)

    # Additional complexity from composite variables
    composite_complexity =
      variables
      |> Enum.filter(&(&1.type == :composite))
      |> Enum.map(fn var ->
        case get_in(var.metadata, [:dimensions]) do
          # Scale down for scoring
          dim when is_integer(dim) -> dim / 100
          _ -> 1
        end
      end)
      |> Enum.sum()

    base_dim + composite_complexity
  end

  defp generate_space_performance_tips(space, variables) do
    tips = []

    # Check for high dimensionality
    tips =
      if length(variables) > 15 do
        [
          "Consider dimensionality reduction techniques for spaces with #{length(variables)} variables"
          | tips
        ]
      else
        tips
      end

    # Check for embedding variables
    embedding_count =
      Enum.count(variables, fn var ->
        get_in(var.metadata, [:ml_type]) == :embedding
      end)

    tips =
      if embedding_count > 0 do
        [
          "Use efficient embedding representations for #{embedding_count} embedding variables"
          | tips
        ]
      else
        tips
      end

    # Check metadata for optimization hints
    tips =
      if space.metadata[:space_type] == :provider_optimized do
        [
          "Provider-optimized space detected - use provider-specific optimization strategies"
          | tips
        ]
      else
        tips
      end

    if Enum.empty?(tips) do
      ["Variable space is well-structured for optimization"]
    else
      Enum.reverse(tips)
    end
  end

  defp estimate_search_time(dimensionality_score, variable_count) do
    # Simple heuristic for search time estimation
    # 0.1 seconds per variable
    base_time = variable_count * 0.1
    complexity_multiplier = :math.log(dimensionality_score + 1)
    base_time * complexity_multiplier
  end

  defp generate_bottleneck_suggestions(_bottlenecks, metrics) do
    suggestions = []

    suggestions =
      if metrics.total_variables > 20 do
        ["Consider variable selection or dimensionality reduction" | suggestions]
      else
        suggestions
      end

    suggestions =
      if metrics.average_complexity > 3.0 do
        ["Simplify variable constraints to reduce complexity" | suggestions]
      else
        suggestions
      end

    suggestions =
      if metrics.high_dimensional_variables > 0 do
        ["Use embedding compression techniques for high-dimensional variables" | suggestions]
      else
        suggestions
      end

    if Enum.empty?(suggestions) do
      ["Space is well-optimized - no major bottlenecks detected"]
    else
      Enum.reverse(suggestions)
    end
  end
end

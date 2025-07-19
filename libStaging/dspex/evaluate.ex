defmodule DSPEx.Evaluate do
  @moduledoc """
  Concurrent evaluation engine for DSPEx programs with Foundation integration.

  This module provides comprehensive evaluation capabilities for DSPEx programs,
  including local concurrent evaluation and distributed evaluation across
  Foundation clusters. It automatically selects the optimal evaluation strategy
  based on the available infrastructure.

  ## Features

  - Concurrent local evaluation using Task.async_stream
  - Distributed evaluation across Foundation clusters
  - Fault-tolerant execution with error isolation
  - Comprehensive metrics and telemetry
  - Progress tracking and reporting
  - Automatic fallback strategies

  ## Examples

      # Simple evaluation
      iex> program = DSPEx.Predict.new(MySignature, :openai)
      iex> examples = [%{inputs: %{question: "2+2?"}, outputs: %{answer: "4"}}]
      iex> metric_fn = fn example, prediction ->
      ...>   if example.outputs.answer == prediction.answer, do: 1.0, else: 0.0
      ...> end
      iex> {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn)
      iex> result.score
      1.0

      # With custom options
      iex> {:ok, result} = DSPEx.Evaluate.run(program, examples, metric_fn,
      ...>   max_concurrency: 50,
      ...>   distributed: true,
      ...>   progress_callback: &IO.inspect/1
      ...> )

  """

  alias Foundation.Utils

  @type evaluation_result :: %{
          score: float(),
          stats: %{
            total_examples: non_neg_integer(),
            successful: non_neg_integer(),
            failed: non_neg_integer(),
            duration_ms: non_neg_integer(),
            success_rate: float(),
            throughput: float(),
            errors: [term()]
          }
        }

  @type evaluation_options :: [
          max_concurrency: pos_integer(),
          timeout: timeout(),
          distributed: boolean(),
          progress_callback: (map() -> any()) | nil,
          fault_tolerance: :none | :skip_failed | :retry_failed
        ]

  @doc """
  Run evaluation with automatic strategy selection.

  Automatically chooses between local and distributed evaluation based on
  the available infrastructure and options. This is the recommended entry
  point for most evaluation tasks.

  ## Parameters

  - `program` - DSPEx program to evaluate (must implement DSPEx.Program behavior)
  - `examples` - List of examples with inputs and expected outputs
  - `metric_fn` - Function that takes (example, prediction) and returns a score
  - `opts` - Optional evaluation configuration

  ## Options

  - `:max_concurrency` - Maximum concurrent evaluations (default: 100)
  - `:timeout` - Timeout per evaluation (default: :infinity)
  - `:distributed` - Force distributed evaluation (default: auto-detect)
  - `:progress_callback` - Function called with progress updates
  - `:fault_tolerance` - How to handle failed evaluations (default: :skip_failed)

  ## Returns

  - `{:ok, evaluation_result()}` - Successful evaluation with score and stats
  - `{:error, reason}` - Error during evaluation

  """
  @spec run(DSPEx.Program.t(), [DSPEx.Example.t()], function(), evaluation_options()) ::
          {:ok, evaluation_result()} | {:error, term()}
  def run(program, examples, metric_fn, opts \\ []) do
    # Validate inputs
    with :ok <- validate_program(program),
         :ok <- validate_examples(examples),
         :ok <- validate_metric_function(metric_fn) do
      correlation_id = Keyword.get(opts, :correlation_id) || Utils.generate_correlation_id()

      start_time = System.monotonic_time()

      :telemetry.execute(
        [:dspex, :evaluate, :run, :start],
        %{system_time: System.system_time()},
        %{
          program: DSPEx.Program.program_name(program),
          example_count: length(examples),
          correlation_id: correlation_id
        }
      )

      result = do_run(program, examples, metric_fn, opts)

      duration = System.monotonic_time() - start_time
      success = match?({:ok, _}, result)

      :telemetry.execute(
        [:dspex, :evaluate, :run, :stop],
        %{duration: duration, success: success},
        %{
          program: DSPEx.Program.program_name(program),
          correlation_id: correlation_id
        }
      )

      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run local evaluation with Task.async_stream.

  Forces local evaluation regardless of cluster availability. Useful for
  development, testing, or when you want to ensure evaluation runs on
  the current node.

  """
  @spec run_local(DSPEx.Program.t(), [DSPEx.Example.t()], function(), evaluation_options()) ::
          {:ok, evaluation_result()} | {:error, term()}
  def run_local(program, examples, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Utils.generate_correlation_id()

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :evaluate, :local, :start],
      %{system_time: System.system_time()},
      %{
        program: DSPEx.Program.program_name(program),
        example_count: length(examples),
        correlation_id: correlation_id
      }
    )

    result = do_run_local(program, examples, metric_fn, opts)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :evaluate, :local, :stop],
      %{duration: duration, success: success},
      %{
        program: DSPEx.Program.program_name(program),
        correlation_id: correlation_id
      }
    )

    result
  end

  @doc """
  Run distributed evaluation across Foundation cluster.

  Forces distributed evaluation if cluster is available, otherwise falls back
  to local evaluation. Useful for benchmarking distributed performance.

  """
  @spec run_distributed(DSPEx.Program.t(), [DSPEx.Example.t()], function(), evaluation_options()) ::
          {:ok, evaluation_result()} | {:error, term()}
  def run_distributed(program, examples, metric_fn, opts \\ []) do
    correlation_id = Keyword.get(opts, :correlation_id) || Utils.generate_correlation_id()

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :evaluate, :distributed, :start],
      %{system_time: System.system_time()},
      %{
        program: DSPEx.Program.program_name(program),
        example_count: length(examples),
        correlation_id: correlation_id
      }
    )

    result =
      if cluster_available?() do
        do_run_distributed(program, examples, metric_fn, opts)
      else
        # Fallback to local
        do_run_local(program, examples, metric_fn, opts)
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :evaluate, :distributed, :stop],
      %{duration: duration, success: success},
      %{
        program: DSPEx.Program.program_name(program),
        correlation_id: correlation_id
      }
    )

    result
  end

  # Private Implementation

  defp do_run(program, examples, metric_fn, opts) do
    should_distribute = Keyword.get(opts, :distributed, cluster_available?())

    if should_distribute and cluster_available?() do
      do_run_distributed(program, examples, metric_fn, opts)
    else
      do_run_local(program, examples, metric_fn, opts)
    end
  end

  defp do_run_local(program, examples, metric_fn, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 100)
    timeout = Keyword.get(opts, :timeout, :infinity)
    progress_callback = Keyword.get(opts, :progress_callback)

    start_time = System.monotonic_time()
    examples_list = examples
    total_examples = length(examples_list)

    # Execute evaluations concurrently
    results =
      examples_list
      |> Stream.with_index()
      |> Task.async_stream(
        fn {example, index} ->
          result = evaluate_single_example(program, example, metric_fn)

          # Report progress
          if progress_callback && rem(index, 10) == 0 do
            progress_callback.(%{
              completed: index + 1,
              total: total_examples,
              percentage: (index + 1) / total_examples * 100
            })
          end

          result
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    process_evaluation_results(results, duration)
  end

  defp do_run_distributed(program, examples, metric_fn, opts) do
    # For now, implement as multi-node Task.async_stream
    # Future: Use Foundation's WorkDistribution when available

    # Get available nodes (if Foundation clustering is available)
    nodes = get_available_nodes()

    if length(nodes) <= 1 do
      # Not enough nodes for distribution, fallback to local
      do_run_local(program, examples, metric_fn, opts)
    else
      distribute_evaluation_work(program, examples, metric_fn, nodes, opts)
    end
  end

  defp distribute_evaluation_work(program, examples, metric_fn, nodes, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 50)
    chunk_size = calculate_optimal_chunk_size(examples, nodes)

    start_time = System.monotonic_time()

    # Distribute chunks across nodes
    results =
      examples
      |> Enum.chunk_every(chunk_size)
      |> Enum.with_index()
      |> Task.async_stream(
        fn {chunk, index} ->
          target_node = Enum.at(nodes, rem(index, length(nodes)))

          # Execute chunk on target node
          :rpc.call(target_node, __MODULE__, :evaluate_chunk_on_node, [
            program,
            chunk,
            metric_fn,
            max_concurrency
          ])
        end,
        timeout: :infinity
      )
      |> Enum.reduce({[], %{}}, fn
        {:ok, {:ok, chunk_result}}, {results, stats} ->
          {[chunk_result | results], merge_chunk_stats(stats, chunk_result.stats)}

        {:ok, {:error, error}}, {results, stats} ->
          updated_stats = Map.update(stats, :chunk_failures, [error], &[error | &1])
          {results, updated_stats}

        {:exit, reason}, {results, stats} ->
          updated_stats = Map.update(stats, :node_failures, [reason], &[reason | &1])
          {results, updated_stats}
      end)

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    aggregate_distributed_results(results, duration)
  end

  @doc """
  Evaluate a chunk of examples on a specific node.

  This function is called via RPC for distributed evaluation.
  """
  def evaluate_chunk_on_node(program, chunk, metric_fn, max_concurrency) do
    results =
      chunk
      |> Task.async_stream(
        fn example ->
          evaluate_single_example(program, example, metric_fn)
        end,
        max_concurrency: max_concurrency,
        timeout: 30_000
      )
      |> Enum.to_list()

    {scores, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, {:ok, score}}, {scores, errors} -> {[score | scores], errors}
        {:ok, {:error, error}}, {scores, errors} -> {scores, [error | errors]}
        {:exit, reason}, {scores, errors} -> {scores, [{:timeout, reason} | errors]}
      end)

    {:ok,
     %{
       scores: scores,
       stats: %{
         node: node(),
         chunk_size: length(chunk),
         successful: length(scores),
         failed: length(errors),
         errors: errors
       }
     }}
  end

  defp evaluate_single_example(program, example, metric_fn) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :evaluate, :example, :start],
      %{system_time: System.system_time()},
      %{program: DSPEx.Program.program_name(program)}
    )

    result =
      try do
        # Extract inputs based on example format
        inputs =
          case example do
            %DSPEx.Example{} -> DSPEx.Example.inputs(example)
            %{inputs: inputs} -> inputs
          end

        case DSPEx.Program.forward(program, inputs) do
          {:ok, prediction} ->
            try do
              score = metric_fn.(example, prediction)

              if is_number(score) do
                {:ok, score}
              else
                {:error, {:invalid_metric_result, score}}
              end
            rescue
              exception -> {:error, {:metric_function_error, exception}}
            catch
              :throw, value -> {:error, {:metric_function_throw, value}}
              :exit, reason -> {:error, {:metric_function_exit, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        exception -> {:error, {:program_exception, exception}}
      catch
        :throw, value -> {:error, {:program_throw, value}}
        :exit, reason -> {:error, {:program_exit, reason}}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :evaluate, :example, :stop],
      %{duration: duration, success: success},
      %{program: DSPEx.Program.program_name(program)}
    )

    result
  end

  # Validation functions

  defp validate_program(program) when is_struct(program) do
    if DSPEx.Program.implements_program?(program.__struct__) do
      :ok
    else
      {:error, {:invalid_program, "Program must implement DSPEx.Program behavior"}}
    end
  end

  defp validate_program(_),
    do:
      {:error, {:invalid_program, "Program must be a struct implementing DSPEx.Program behavior"}}

  defp validate_examples(examples) when is_list(examples) and length(examples) > 0 do
    if Enum.all?(examples, &valid_example?/1) do
      # Additional Sinter validation for examples if available
      validate_examples_with_sinter(examples)
    else
      {:error, {:invalid_examples, "All examples must have inputs and outputs fields"}}
    end
  end

  defp validate_examples(_),
    do: {:error, {:invalid_examples, "Examples must be a non-empty list"}}

  defp validate_metric_function(metric_fn) when is_function(metric_fn, 2), do: :ok

  defp validate_metric_function(_),
    do: {:error, {:invalid_metric_function, "Metric function must accept 2 arguments"}}

  @dialyzer {:nowarn_function, valid_example?: 1}
  # Accept both old format and new DSPEx.Example format
  defp valid_example?(%{inputs: inputs, outputs: outputs})
       when is_map(inputs) and is_map(outputs),
       do: true

  defp valid_example?(%DSPEx.Example{} = _example), do: true

  defp valid_example?(_), do: false

  # Utility functions

  defp cluster_available? do
    # Check if we're running in a cluster
    nodes = Node.list()
    length(nodes) > 0
  end

  defp get_available_nodes do
    # Include self and connected nodes
    [node() | Node.list()]
  end

  defp calculate_optimal_chunk_size(examples, nodes) do
    total_examples = length(examples)
    total_nodes = length(nodes)

    # Aim for 2-3 chunks per node for load balancing
    chunk_size = div(total_examples, total_nodes * 3)
    max(chunk_size, 1)
  end

  defp process_evaluation_results(results, duration) do
    {scores, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, {:ok, score}}, {scores, errors} -> {[score | scores], errors}
        {:ok, {:error, error}}, {scores, errors} -> {scores, [error | errors]}
        {:exit, reason}, {scores, errors} -> {scores, [{:timeout, reason} | errors]}
      end)

    if Enum.empty?(scores) do
      # No successful evaluations - analyze error types to determine response
      total_examples = length(errors)

      # Return error if all failures are critical (timeouts, system errors)
      # Return zero score if failures are data-related (validation, parsing)
      critical_errors = Enum.count(errors, &critical_error?/1)

      if critical_errors > total_examples * 0.8 do
        {:error, {:evaluation_failed, "Too many critical errors", errors}}
      else
        # Calculate throughput even for failed operations
        throughput = calculate_throughput(total_examples, duration)

        {:ok,
         %{
           score: 0.0,
           stats: %{
             total_examples: total_examples,
             successful: 0,
             failed: length(errors),
             duration_ms: duration,
             success_rate: 0.0,
             throughput: throughput,
             errors: errors
           }
         }}
      end
    else
      total_examples = length(scores) + length(errors)
      average_score = Enum.sum(scores) / length(scores)
      success_rate = length(scores) / total_examples

      # Calculate throughput (examples per second), handle very fast operations
      throughput = calculate_throughput(total_examples, duration)

      {:ok,
       %{
         score: average_score,
         stats: %{
           total_examples: total_examples,
           successful: length(scores),
           failed: length(errors),
           duration_ms: duration,
           success_rate: success_rate,
           throughput: throughput,
           errors: errors
         }
       }}
    end
  end

  defp aggregate_distributed_results({chunk_results, _global_stats}, duration) do
    all_scores = Enum.flat_map(chunk_results, & &1.scores)

    if Enum.empty?(all_scores) do
      {:error, :no_successful_evaluations}
    else
      total_stats =
        Enum.reduce(chunk_results, %{}, fn chunk_result, acc ->
          %{
            total_examples: (acc[:total_examples] || 0) + chunk_result.stats.chunk_size,
            successful: (acc[:successful] || 0) + chunk_result.stats.successful,
            failed: (acc[:failed] || 0) + chunk_result.stats.failed,
            nodes_used: MapSet.put(acc[:nodes_used] || MapSet.new(), chunk_result.stats.node)
          }
        end)

      average_score = Enum.sum(all_scores) / length(all_scores)
      success_rate = total_stats.successful / total_stats.total_examples
      throughput = total_stats.total_examples / (duration / 1000)

      {:ok,
       %{
         score: average_score,
         stats:
           Map.merge(total_stats, %{
             duration_ms: duration,
             success_rate: success_rate,
             throughput: throughput,
             nodes_used: MapSet.size(total_stats.nodes_used),
             distribution_overhead: calculate_distribution_overhead(duration, chunk_results),
             errors: []
           })
       }}
    end
  end

  defp merge_chunk_stats(global_stats, chunk_stats) do
    Map.merge(global_stats, chunk_stats, fn
      _key, v1, v2 when is_number(v1) and is_number(v2) -> v1 + v2
      _key, v1, v2 when is_list(v1) and is_list(v2) -> v1 ++ v2
      _key, _v1, v2 -> v2
    end)
  end

  defp calculate_distribution_overhead(total_duration, chunk_results) do
    # Calculate overhead of distribution vs estimated local time
    estimated_local_duration =
      Enum.max_by(chunk_results, fn result ->
        Map.get(result.stats, :duration_ms, 0)
      end)
      |> get_in([Access.key(:stats), Access.key(:duration_ms)]) || 0

    if estimated_local_duration > 0 do
      overhead_percentage = (total_duration - estimated_local_duration) / total_duration * 100
      max(overhead_percentage, 0)
    else
      0
    end
  end

  defp calculate_throughput(total_examples, duration) do
    if is_number(duration) and duration > 0 do
      # examples per second
      total_examples / (duration / 1000)
    else
      # For very fast operations (< 1ms), estimate based on total examples
      # assume 1ms duration for throughput calculation
      total_examples * 1000.0
    end
  end

  defp critical_error?({:timeout, _}), do: true
  defp critical_error?({:exit, _}), do: true
  defp critical_error?({:system_error, _}), do: true
  defp critical_error?({:network_error, _}), do: true
  defp critical_error?({:client_error, _}), do: true
  defp critical_error?(_), do: false

  # Sinter integration functions for evaluation

  defp validate_examples_with_sinter(examples) do
    try do
      # Validate examples structure using Sinter if available
      # For now, gracefully continue without failing evaluation
      validated_count = validate_example_batch_with_sinter(examples)

      :telemetry.execute(
        [:dspex, :evaluate, :validation, :sinter],
        %{validated_examples: validated_count},
        %{total_examples: length(examples)}
      )

      :ok
    rescue
      # Graceful degradation if Sinter validation fails
      _ -> :ok
    end
  end

  defp validate_example_batch_with_sinter(examples) do
    examples
    # Sample first 5 examples for validation
    |> Enum.take(5)
    |> Enum.count(fn example ->
      case example do
        %{inputs: inputs, outputs: outputs} ->
          validate_example_fields_with_sinter(inputs, outputs)

        %DSPEx.Example{} = ex ->
          validate_example_fields_with_sinter(DSPEx.Example.inputs(ex), DSPEx.Example.outputs(ex))

        _ ->
          false
      end
    end)
  end

  defp validate_example_fields_with_sinter(inputs, outputs) do
    try do
      # Basic validation that inputs and outputs are proper maps
      is_map(inputs) and is_map(outputs) and
        map_size(inputs) > 0 and map_size(outputs) > 0
    rescue
      _ -> false
    end
  end
end

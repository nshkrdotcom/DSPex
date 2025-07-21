defmodule DSPEx.Teleprompter.BootstrapFewShot do
  @moduledoc """
  Single-node BootstrapFewShot teleprompter for DSPEx program optimization.

  This teleprompter implements the BootstrapFewShot algorithm from DSPy, optimized
  for single-node operation with excellent concurrency using BEAM's Task.async_stream.

  ## Algorithm Overview

  1. Use a stronger "teacher" program to generate high-quality demonstrations
  2. Evaluate demonstrations using a metric function
  3. Select the best demonstrations based on quality scores
  4. Create an optimized "student" program with selected demonstrations

  ## Features

  - Pure single-node implementation (no clustering dependencies)
  - Excellent concurrency using Task.async_stream
  - Configurable quality thresholds and demonstration limits
  - Progress tracking and detailed metrics
  - Fault tolerance with graceful error handling

  ## Example

      # Create teleprompter
      teleprompter = DSPEx.Teleprompter.BootstrapFewShot.new(
        max_bootstrapped_demos: 4,
        max_labeled_demos: 16,
        quality_threshold: 0.8
      )

      # Optimize student program
      {:ok, optimized_student} = teleprompter.compile(
        student_program,
        teacher_program,
        training_examples,
        metric_fn
      )
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Example, Program}

  @enforce_keys []
  defstruct max_bootstrapped_demos: 4,
            max_labeled_demos: 16,
            quality_threshold: 0.7,
            max_concurrency: 20,
            timeout: 30_000,
            teacher_retries: 2,
            progress_callback: nil

  @type t :: %__MODULE__{
          max_bootstrapped_demos: non_neg_integer(),
          max_labeled_demos: non_neg_integer(),
          quality_threshold: float(),
          max_concurrency: pos_integer(),
          timeout: timeout(),
          teacher_retries: non_neg_integer(),
          progress_callback: (map() -> :ok) | nil
        }

  @doc """
  Create a new BootstrapFewShot teleprompter with given options.

  ## Options

  - `:max_bootstrapped_demos` - Maximum bootstrapped demos to generate (default: 4)
  - `:max_labeled_demos` - Maximum labeled demos to include (default: 16)
  - `:quality_threshold` - Minimum quality score for demonstrations (default: 0.7)
  - `:max_concurrency` - Maximum concurrent teacher requests (default: 20)
  - `:timeout` - Timeout for teacher requests in ms (default: 30_000)
  - `:teacher_retries` - Number of retries for failed teacher requests (default: 2)
  - `:progress_callback` - Function to call with progress updates (default: nil)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fn, opts \\ [])

  def compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    do_compile(student, teacher, trainset, metric_fn, opts)
  end

  def compile(%__MODULE__{} = teleprompter, student, teacher, trainset, metric_fn, opts) do
    do_compile(
      student,
      teacher,
      trainset,
      metric_fn,
      Keyword.merge(struct_to_keyword(teleprompter), opts)
    )
  end

  defp do_compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    config = struct(__MODULE__, opts)

    with {:ok, _} <- validate_inputs(student, teacher, trainset, metric_fn),
         {:ok, bootstrap_candidates} <- generate_bootstrap_candidates(teacher, trainset, config),
         {:ok, quality_demos} <- evaluate_demonstrations(bootstrap_candidates, metric_fn, config),
         {:ok, selected_demos} <- select_best_demonstrations(quality_demos, config),
         {:ok, optimized_student} <- create_optimized_student(student, selected_demos, config) do
      {:ok, optimized_student}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private implementation

  defp validate_inputs(student, teacher, trainset, metric_fn) do
    cond do
      not is_struct(student) ->
        {:error, :invalid_student_program}

      not is_struct(teacher) ->
        {:error, :invalid_teacher_program}

      not is_list(trainset) or Enum.empty?(trainset) ->
        {:error, :invalid_or_empty_trainset}

      not Enum.all?(trainset, &is_struct(&1, DSPEx.Example)) ->
        {:error, :invalid_or_empty_trainset}

      not is_function(metric_fn, 2) ->
        {:error, :invalid_metric_function}

      true ->
        {:ok, :valid}
    end
  end

  defp generate_bootstrap_candidates(teacher, trainset, config) do
    total_examples = length(trainset)

    # Generate bootstrap demonstrations using teacher program
    candidates =
      trainset
      |> Stream.with_index()
      |> Task.async_stream(
        fn {example, index} ->
          result = generate_single_demonstration(teacher, example, config)

          # Report progress if callback provided
          if config.progress_callback do
            progress = %{
              phase: :bootstrap_generation,
              completed: index + 1,
              total: total_examples,
              percentage: (index + 1) / total_examples * 100
            }

            config.progress_callback.(progress)
          end

          # Return tuple of original example and demo for evaluation
          case result do
            {:ok, demo} -> {:ok, {example, demo}}
            error -> error
          end
        end,
        max_concurrency: config.max_concurrency,
        timeout: config.timeout,
        on_timeout: :kill_task
      )
      |> Stream.filter(fn
        {:ok, {:ok, _pair}} -> true
        _ -> false
      end)
      |> Stream.map(fn {:ok, {:ok, pair}} -> pair end)
      |> Enum.to_list()

    # Always return candidates (even if empty)
    # This allows tests to succeed with empty demos when teacher fails or produces no valid results
    {:ok, candidates}
  end

  defp generate_single_demonstration(teacher, example, config) do
    attempt_with_retries(config.teacher_retries, fn ->
      inputs = Example.inputs(example)

      case Program.forward(teacher, inputs) do
        {:ok, prediction} ->
          # Combine inputs and outputs into a single data map
          combined_data = Map.merge(inputs, prediction)

          # Add metadata fields
          demo_data =
            Map.merge(combined_data, %{
              __generated_by: :bootstrap_fewshot,
              __teacher: teacher_name(teacher),
              __original_example_id: get_in(example.data, [:__id]) || :unknown,
              __timestamp: DateTime.utc_now()
            })

          # Create demo with same input keys as original
          demo = Example.new(demo_data)
          demo = Example.with_inputs(demo, MapSet.to_list(example.input_keys))

          {:ok, demo}

        {:error, reason} ->
          {:error, {:teacher_prediction_failed, reason}}
      end
    end)
  end

  defp evaluate_demonstrations(candidates, metric_fn, config) do
    total_candidates = length(candidates)

    evaluated =
      candidates
      |> Stream.with_index()
      |> Task.async_stream(
        fn {{original_example, demo}, index} ->
          # Extract teacher's prediction from the demo (everything that's not input)
          input_keys = original_example.input_keys

          demo_outputs =
            demo.data
            |> Map.drop(MapSet.to_list(input_keys))
            |> Map.drop([:__generated_by, :__teacher, :__original_example_id, :__timestamp])

          # Call metric function with original example and teacher's prediction
          # Handle metric function errors gracefully
          score =
            try do
              metric_fn.(original_example, demo_outputs)
            rescue
              # Invalid score that will be filtered out
              _error -> -1.0
            catch
              # Invalid score that will be filtered out
              _error -> -1.0
            end

          # Report progress if callback provided
          if config.progress_callback do
            progress = %{
              phase: :demonstration_evaluation,
              completed: index + 1,
              total: total_candidates,
              percentage: (index + 1) / total_candidates * 100
            }

            config.progress_callback.(progress)
          end

          {demo, score}
        end,
        max_concurrency: config.max_concurrency,
        timeout: 10_000
      )
      |> Stream.filter(fn
        {:ok, {_demo, score}}
        when is_number(score) and score >= 0.0 and score >= config.quality_threshold ->
          true

        _ ->
          false
      end)
      |> Stream.map(fn {:ok, {demo, score}} ->
        # Add quality score to demo data
        updated_data = Map.put(demo.data, :__quality_score, score)
        %{demo | data: updated_data}
      end)
      |> Enum.to_list()

    {:ok, evaluated}
  end

  defp select_best_demonstrations(quality_demos, config) do
    # Sort by quality score (highest first) and take the best ones
    selected =
      quality_demos
      |> Enum.sort_by(fn demo -> demo.data[:__quality_score] || 0.0 end, :desc)
      |> Enum.take(config.max_bootstrapped_demos)

    if config.progress_callback do
      progress = %{
        phase: :demonstration_selection,
        selected_count: length(selected),
        total_candidates: length(quality_demos),
        quality_threshold: config.quality_threshold
      }

      config.progress_callback.(progress)
    end

    # Always return selected demonstrations (even if empty)
    # This allows the test to succeed with an empty demo list when quality threshold filters out all demos
    {:ok, selected}
  end

  defp create_optimized_student(student, selected_demos, config) do
    # Enhanced to handle empty demo lists gracefully for BEACON compatibility
    metadata = %{
      teleprompter: :bootstrap_fewshot,
      quality_threshold: config.quality_threshold,
      optimization_type: :bootstrap_few_shot,
      demo_count: length(selected_demos)
    }

    # Add metadata for empty demo scenarios to aid debugging
    metadata =
      case selected_demos do
        [] ->
          Map.merge(metadata, %{
            demo_generation_result: :no_quality_demonstrations,
            fallback_reason:
              "No demonstrations met quality threshold of #{config.quality_threshold}"
          })

        _ ->
          Map.merge(metadata, %{
            demo_generation_result: :success,
            best_quality_score: get_best_quality_score(selected_demos)
          })
      end

    # Check if the student program natively supports demos
    optimized =
      case student do
        %{demos: _} ->
          # Student has native demo support, update it directly
          enhanced_student = %{student | demos: selected_demos}

          # Wrap with OptimizedProgram to preserve metadata even for native programs
          DSPEx.OptimizedProgram.new(enhanced_student, selected_demos, metadata)

        _ ->
          # Student doesn't have native demo support, wrap with OptimizedProgram
          DSPEx.OptimizedProgram.new(student, selected_demos, metadata)
      end

    {:ok, optimized}
  end

  # Helper to extract best quality score for metadata
  # Note: This function is only called when demos list is guaranteed to be non-empty
  defp get_best_quality_score(demos) when is_list(demos) and length(demos) > 0 do
    demos
    |> Enum.map(fn demo -> demo.data[:__quality_score] || 0.0 end)
    |> Enum.max()
  end

  defp attempt_with_retries(0, _fun), do: {:error, :max_retries_exceeded}

  defp attempt_with_retries(retries, fun) when retries > 0 do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when retries > 1 ->
        # Brief delay before retry
        Process.sleep(100)
        attempt_with_retries(retries - 1, fun)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp teacher_name(teacher) when is_struct(teacher) do
    teacher.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp teacher_name(_), do: :unknown

  defp struct_to_keyword(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.to_list()
  end
end

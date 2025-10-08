defmodule DSPex.Pipeline do
  @moduledoc """
  Pipeline orchestration for complex ML workflows.

  Pipelines allow you to compose multiple operations, mixing native Elixir
  and Python implementations seamlessly. Supports sequential, parallel,
  and conditional execution.

  ## Example

      pipeline = DSPex.pipeline([
        {:native, Signature, spec: "query -> keywords"},
        {:python, "dspy.ChainOfThought", signature: "keywords -> analysis"},
        {:parallel, [
          {:native, Search, index: "docs"},
          {:python, "dspy.ColBERTv2", k: 10}
        ]},
        {:native, Template, template: "Results: <%= @results %>"}
      ])
      
      {:ok, result} = DSPex.run_pipeline(pipeline, %{query: "quantum computing"})
  """

  require Logger

  defstruct [:id, :steps, :context, :metrics, :options]

  @type step_type :: :native | :python | :parallel | :conditional | :map | :reduce

  @type step ::
          {step_type(), module() | String.t(), keyword()}
          | {:parallel, [step()]}
          | {:conditional, (map() -> boolean()), step(), step()}
          | {:map, atom(), step()}
          | {:reduce, atom(), step(), term()}

  @type t :: %__MODULE__{
          id: String.t(),
          steps: [step()],
          context: map(),
          metrics: map(),
          options: keyword()
        }

  @doc """
  Create a new pipeline with the given steps.
  """
  @spec new([step()], keyword()) :: t()
  def new(steps, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      steps: compile_steps(steps),
      context: %{},
      metrics: init_metrics(),
      options: opts
    }
  end

  @doc """
  Execute a pipeline with the given input.
  """
  @spec run(t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(pipeline, input, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Merge pipeline options with runtime options
    opts = Keyword.merge(pipeline.options, opts)

    # Initialize execution state
    initial_state = %{
      input: input,
      current: input,
      context: pipeline.context,
      results: [],
      step_index: 0,
      metrics: pipeline.metrics
    }

    # Execute steps
    result = execute_steps(pipeline.steps, initial_state, opts)

    # Record overall metrics
    duration = System.monotonic_time(:millisecond) - start_time
    record_pipeline_metrics(pipeline.id, duration, result)

    # Return final result
    case result do
      {:ok, state} -> {:ok, state.current}
      error -> error
    end
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp init_metrics do
    %{
      start_time: nil,
      end_time: nil,
      step_durations: [],
      total_duration: nil
    }
  end

  defp compile_steps(steps) do
    Enum.map(steps, &compile_step/1)
  end

  defp compile_step({:parallel, sub_steps}) do
    {:parallel, compile_steps(sub_steps)}
  end

  defp compile_step({:conditional, condition, true_step, false_step}) do
    {:conditional, condition, compile_step(true_step), compile_step(false_step)}
  end

  defp compile_step({:map, field, step}) do
    {:map, field, compile_step(step)}
  end

  defp compile_step(step), do: step

  defp execute_steps([], state, _opts), do: {:ok, state}

  defp execute_steps([step | rest], state, opts) do
    step_start = System.monotonic_time(:millisecond)

    case execute_step(step, state, opts) do
      {:ok, new_state} ->
        # Record step metrics
        duration = System.monotonic_time(:millisecond) - step_start
        new_state = record_step_metrics(new_state, step, duration)

        # Continue with next step
        execute_steps(rest, new_state, opts)

      {:error, reason} ->
        if opts[:continue_on_error] do
          Logger.warning("Pipeline step failed, continuing: #{inspect(reason)}")
          state = Map.update(state, :errors, [reason], &[reason | &1])
          execute_steps(rest, state, opts)
        else
          {:error, reason}
        end

      error ->
        error
    end
  end

  defp execute_step({:native, module, step_opts}, state, _opts) do
    Logger.debug("Executing native step: #{inspect(module)}")

    try do
      result = apply(module, :execute, [state.current, step_opts])

      case result do
        {:ok, output} ->
          new_state = %{state | current: output, results: [output | state.results]}
          {:ok, new_state}

        error ->
          error
      end
    rescue
      e ->
        {:error, {:native_step_error, module, e}}
    end
  end

  defp execute_step({:python, module_name, step_opts}, state, _opts) do
    Logger.debug("Executing Python step: #{module_name}")

    # Determine pool based on module
    _pool = select_pool_for_module(module_name)

    # Prepare arguments
    args = prepare_python_step_args(module_name, state.current, step_opts)

    # Use DSPex.Bridge for Python calls
    session_id = step_opts[:session_id] || DSPex.Utils.ID.generate("pipeline")

    case DSPex.Bridge.call_dspy(
           module_name,
           "__call__",
           args,
           Keyword.put(step_opts, :session_id, session_id)
         ) do
      {:ok, output} ->
        new_state = %{state | current: output, results: [output | state.results]}
        {:ok, new_state}

      error ->
        error
    end
  end

  defp execute_step({:parallel, sub_steps}, state, opts) do
    Logger.debug("Executing parallel steps: #{length(sub_steps)} tasks")

    # Start all tasks in parallel
    tasks =
      Enum.map(sub_steps, fn step ->
        Task.async(fn ->
          execute_step(step, state, opts)
        end)
      end)

    # Wait for all tasks with timeout
    timeout = opts[:step_timeout] || 30_000

    results = Task.await_many(tasks, timeout)

    # Collect successful results
    case collect_parallel_results(results) do
      {:ok, outputs} ->
        new_state = %{
          state
          | current: outputs,
            results: [outputs | state.results]
        }

        {:ok, new_state}

      error ->
        error
    end
  end

  defp execute_step({:conditional, condition, true_step, false_step}, state, opts) do
    if condition.(state.current) do
      execute_step(true_step, state, opts)
    else
      execute_step(false_step, state, opts)
    end
  end

  defp execute_step({:map, field, step}, state, opts) do
    items = get_in(state.current, [field]) || []

    results =
      Enum.map(items, fn item ->
        item_state = %{state | current: item}

        case execute_step(step, item_state, opts) do
          {:ok, new_state} -> {:ok, new_state.current}
          error -> error
        end
      end)

    case collect_map_results(results) do
      {:ok, mapped_items} ->
        new_current = put_in(state.current, [field], mapped_items)
        {:ok, %{state | current: new_current}}

      error ->
        error
    end
  end

  defp prepare_python_step_args("dspy." <> _module, current, opts) do
    # Standard DSPy module arguments
    %{
      inputs: current,
      options: Map.new(opts)
    }
  end

  defp prepare_python_step_args(_module, current, opts) do
    # Generic Python module
    %{
      data: current,
      options: Map.new(opts)
    }
  end

  defp select_pool_for_module(module_name) do
    cond do
      String.contains?(module_name, ["MIPRO", "Optimizer", "Bootstrap"]) -> :optimizer
      String.contains?(module_name, ["ColBERT", "Neural", "Embed"]) -> :neural
      true -> :general
    end
  end

  defp collect_parallel_results(results) do
    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      outputs = Enum.map(results, fn {:ok, state} -> state.current end)
      {:ok, outputs}
    else
      {:error, {:parallel_execution_failed, errors}}
    end
  end

  defp collect_map_results(results) do
    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      outputs = Enum.map(results, fn {:ok, output} -> output end)
      {:ok, outputs}
    else
      {:error, {:map_execution_failed, errors}}
    end
  end

  defp record_step_metrics(state, step, duration) do
    step_info = %{
      type: elem(step, 0),
      duration: duration,
      timestamp: DateTime.utc_now()
    }

    put_in(state, [:metrics, :step_durations], [step_info | state.metrics.step_durations])
  end

  defp record_pipeline_metrics(pipeline_id, duration, result) do
    success =
      case result do
        {:ok, _} -> true
        _ -> false
      end

    :telemetry.execute(
      [:dspex, :pipeline, :run],
      %{duration: duration, success: success},
      %{pipeline_id: pipeline_id}
    )
  end
end

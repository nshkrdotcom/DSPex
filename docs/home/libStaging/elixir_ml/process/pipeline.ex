defmodule ElixirML.Process.Pipeline do
  @moduledoc """
  Pipeline execution system for complex ML workflows.
  Supports sequential and parallel execution patterns with error handling.
  """

  defstruct [
    :id,
    :name,
    :stages,
    :execution_strategy,
    :error_handling,
    :timeout,
    :metadata
  ]

  @type execution_strategy :: :sequential | :parallel | :dag
  @type error_handling :: :fail_fast | :continue_on_error | :retry

  @doc """
  Create a new pipeline with specified stages.
  """
  def new(stages, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_pipeline_id()),
      name: Keyword.get(opts, :name, "Pipeline"),
      stages: stages,
      execution_strategy: Keyword.get(opts, :execution_strategy, :sequential),
      error_handling: Keyword.get(opts, :error_handling, :fail_fast),
      timeout: Keyword.get(opts, :timeout, 30_000),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Execute a pipeline with given inputs.
  """
  def execute(pipeline, inputs, opts \\ []) do
    execution_context = %{
      pipeline: pipeline,
      inputs: inputs,
      opts: opts,
      started_at: System.monotonic_time(:millisecond),
      stage_results: %{},
      errors: []
    }

    case pipeline.execution_strategy do
      :sequential -> execute_sequential(execution_context)
      :parallel -> execute_parallel(execution_context)
      :dag -> execute_dag(execution_context)
    end
  end

  @doc """
  Execute a program using the pipeline system.
  """
  def execute_program(program, inputs, opts \\ []) do
    # Create a simple single-stage pipeline for program execution
    pipeline =
      new(
        [
          %{
            id: :program_execution,
            type: :program,
            program: program,
            timeout: Keyword.get(opts, :timeout, 30_000)
          }
        ],
        opts
      )

    execute(pipeline, inputs, opts)
  end

  # Private execution functions

  defp execute_sequential(context) do
    context.pipeline.stages
    |> Enum.reduce_while({:ok, context.inputs, context}, fn stage, {:ok, inputs, ctx} ->
      case execute_stage(stage, inputs, ctx) do
        {:ok, outputs} ->
          new_ctx = %{ctx | stage_results: Map.put(ctx.stage_results, stage.id, outputs)}
          {:cont, {:ok, outputs, new_ctx}}

        {:error, error} ->
          case handle_stage_error(stage, error, ctx) do
            {:retry, retry_ctx} ->
              case execute_stage(stage, inputs, retry_ctx) do
                {:ok, outputs} ->
                  new_ctx = %{
                    retry_ctx
                    | stage_results: Map.put(retry_ctx.stage_results, stage.id, outputs)
                  }

                  {:cont, {:ok, outputs, new_ctx}}

                {:error, retry_error} ->
                  {:halt, {:error, retry_error}}
              end

            {:continue, continue_ctx} ->
              {:cont, {:ok, inputs, continue_ctx}}

            {:halt, halt_error} ->
              {:halt, {:error, halt_error}}
          end
      end
    end)
    |> case do
      {:ok, final_outputs, final_context} ->
        {:ok,
         %{
           outputs: final_outputs,
           stage_results: final_context.stage_results,
           execution_time: System.monotonic_time(:millisecond) - final_context.started_at,
           pipeline_id: context.pipeline.id
         }}

      {:error, error} ->
        {:error,
         %{
           error: error,
           stage_results: context.stage_results,
           execution_time: System.monotonic_time(:millisecond) - context.started_at,
           pipeline_id: context.pipeline.id
         }}
    end
  end

  defp execute_parallel(context) do
    # Execute all stages in parallel
    tasks =
      context.pipeline.stages
      |> Enum.map(fn stage ->
        Task.async(fn ->
          {stage.id, execute_stage(stage, context.inputs, context)}
        end)
      end)

    # Wait for all tasks to complete
    results = Task.await_many(tasks, context.pipeline.timeout)

    # Process results
    {successes, errors} =
      Enum.split_with(results, fn {_id, result} ->
        match?({:ok, _}, result)
      end)

    if Enum.empty?(errors) or context.pipeline.error_handling == :continue_on_error do
      stage_results =
        successes
        |> Enum.into(%{}, fn {id, {:ok, result}} -> {id, result} end)

      # Combine outputs (this is simplified - might need more sophisticated merging)
      combined_outputs =
        stage_results
        |> Map.values()
        # Take first result as primary output
        |> List.first()

      {:ok,
       %{
         outputs: combined_outputs,
         stage_results: stage_results,
         execution_time: System.monotonic_time(:millisecond) - context.started_at,
         pipeline_id: context.pipeline.id,
         errors: errors
       }}
    else
      {:error,
       %{
         error: errors |> List.first() |> elem(1),
         stage_results: %{},
         execution_time: System.monotonic_time(:millisecond) - context.started_at,
         pipeline_id: context.pipeline.id
       }}
    end
  end

  defp execute_dag(context) do
    # TODO: Implement DAG execution with dependency resolution
    # For now, fall back to sequential
    execute_sequential(context)
  end

  defp execute_stage(stage, inputs, context) do
    case stage.type do
      :program ->
        execute_program_stage(stage, inputs, context)

      :function ->
        execute_function_stage(stage, inputs, context)

      :validation ->
        execute_validation_stage(stage, inputs, context)

      _ ->
        {:error, {:unknown_stage_type, stage.type}}
    end
  end

  defp execute_program_stage(stage, inputs, context) do
    program = stage.program

    # Start or get existing program worker
    case ElixirML.Process.ProgramSupervisor.start_program(program,
           timeout: Map.get(stage, :timeout, context.pipeline.timeout)
         ) do
      {:ok, pid} ->
        try do
          ElixirML.Process.ProgramWorker.execute(pid, inputs, context.opts)
        after
          ElixirML.Process.ProgramSupervisor.stop_program(pid)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp execute_function_stage(stage, inputs, _context) do
    try do
      result = stage.function.(inputs)
      {:ok, result}
    rescue
      error -> {:error, error}
    end
  end

  defp execute_validation_stage(stage, inputs, _context) do
    case stage.validator.(inputs) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} = error -> error
      true -> {:ok, inputs}
      false -> {:error, :validation_failed}
    end
  end

  defp handle_stage_error(stage, error, context) do
    case context.pipeline.error_handling do
      :fail_fast ->
        {:halt, error}

      :continue_on_error ->
        new_context = %{context | errors: [error | context.errors]}
        {:continue, new_context}

      :retry ->
        retry_count = Map.get(stage, :retry_count, 0)
        max_retries = Map.get(stage, :max_retries, 3)

        if retry_count < max_retries do
          _updated_stage = Map.put(stage, :retry_count, retry_count + 1)
          {:retry, context}
        else
          {:halt, error}
        end
    end
  end

  defp generate_pipeline_id do
    "pipeline_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end

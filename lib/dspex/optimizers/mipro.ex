defmodule DSPex.Optimizers.MIPRO do
  @moduledoc """
  MIPROv2 (Multi-Instruction Proposal Optimizer v2).

  Optimizes prompts by proposing and evaluating multiple instruction variants.
  More powerful than BootstrapFewShot but requires more computation.

  Note: This wraps dspy.MIPROv2 as the original MIPRO is deprecated.
  """

  alias DSPex.Utils.ID

  @doc """
  Optimize a program using MIPROv2.

  ## Examples

      {:ok, program_id} = DSPex.Modules.Predict.create("context, question -> answer")
      
      trainset = [
        %{context: "The sky is blue.", question: "What color is the sky?", answer: "blue"},
        # ... more examples
      ]
      
      {:ok, optimized} = DSPex.Optimizers.MIPRO.optimize(
        program_id,
        trainset,
        num_candidates: 10,
        init_temperature: 1.0
      )
  """
  def optimize(program_id, trainset, opts \\ []) do
    optimizer_id = ID.generate("mipro")

    config = %{
      prompt_model: opts[:prompt_model],
      task_model: opts[:task_model],
      metric: opts[:metric],
      num_candidates: opts[:num_candidates] || 10,
      init_temperature: opts[:init_temperature] || 1.0,
      verbose: opts[:verbose] || false,
      track_stats: opts[:track_stats] || true,
      view_data_batch_size: opts[:view_data_batch_size],
      minibatch_size: opts[:minibatch_size] || 25,
      minibatch_full_eval_steps: opts[:minibatch_full_eval_steps] || 10,
      minibatch: opts[:minibatch] || true,
      num_trials: opts[:num_trials] || 100,
      max_bootstrapped_demos: opts[:max_bootstrapped_demos] || 3,
      max_labeled_demos: opts[:max_labeled_demos] || 5,
      eval_kwargs: opts[:eval_kwargs] || %{},
      seed: opts[:seed] || 123
    }

    # Create the optimizer
    with {:ok, _} <-
           Snakepit.Python.call(
             "dspy.MIPROv2",
             config,
             Keyword.merge([store_as: optimizer_id], opts)
           ),
         # Compile the program
         {:ok, result} <-
           Snakepit.Python.call(
             "stored.#{optimizer_id}.compile",
             %{
               student: "stored.#{program_id}",
               trainset: trainset,
               valset: opts[:valset],
               num_trials: config.num_trials,
               max_bootstrapped_demos: config.max_bootstrapped_demos,
               max_labeled_demos: config.max_labeled_demos,
               eval_kwargs: config.eval_kwargs
             },
             opts
           ) do
      {:ok,
       %{
         optimized_program_id: "#{program_id}_mipro",
         optimizer_id: optimizer_id,
         result: result
       }}
    end
  end

  @doc """
  Get optimization statistics from MIPRO.
  """
  def get_stats(optimizer_id, opts \\ []) do
    Snakepit.Python.call(
      "stored.#{optimizer_id}.get_stats",
      %{},
      opts
    )
  end
end

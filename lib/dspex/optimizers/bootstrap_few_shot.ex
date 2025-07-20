defmodule DSPex.Optimizers.BootstrapFewShot do
  @moduledoc """
  Bootstrap Few-Shot optimizer.

  Automatically generates few-shot examples from a training set to improve
  prompt performance. This is one of the most popular DSPy optimizers.
  """

  alias DSPex.Utils.ID

  @doc """
  Optimize a program using bootstrap few-shot learning.

  ## Examples

      {:ok, program_id} = DSPex.Modules.ChainOfThought.create("question -> answer")
      
      trainset = [
        %{question: "What is 2+2?", answer: "4"},
        %{question: "What is the capital of France?", answer: "Paris"}
      ]
      
      {:ok, optimized} = DSPex.Optimizers.BootstrapFewShot.optimize(
        program_id,
        trainset,
        max_bootstrapped_demos: 3
      )
  """
  def optimize(program_id, trainset, opts \\ []) do
    optimizer_id = ID.generate("bootstrap_fs")

    config = %{
      max_bootstrapped_demos: opts[:max_bootstrapped_demos] || 4,
      max_labeled_demos: opts[:max_labeled_demos] || 16,
      max_rounds: opts[:max_rounds] || 1,
      max_errors: opts[:max_errors] || 5
    }

    # Create the optimizer
    with {:ok, _} <-
           Snakepit.Python.call(
             "dspy.BootstrapFewShot",
             config,
             Keyword.merge([store_as: optimizer_id], opts)
           ),
         # Compile the program with training data
         {:ok, result} <-
           Snakepit.Python.call(
             "stored.#{optimizer_id}.compile",
             %{
               student: "stored.#{program_id}",
               trainset: trainset
             },
             opts
           ) do
      {:ok,
       %{
         optimized_program_id: "#{program_id}_optimized",
         optimizer_id: optimizer_id,
         result: result
       }}
    end
  end

  @doc """
  Get the bootstrapped demos from an optimized program.
  """
  def get_demos(optimized_program_id, opts \\ []) do
    Snakepit.Python.call(
      "stored.#{optimized_program_id}.demos",
      %{},
      opts
    )
  end
end

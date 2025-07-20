defmodule DSPex.Optimizers.BootstrapFewShotWithRandomSearch do
  @moduledoc """
  Bootstrap Few-Shot with Random Search optimizer.

  Combines bootstrap few-shot learning with random search over hyperparameters
  to find optimal configurations.
  """

  alias DSPex.Utils.ID

  @doc """
  Optimize a program using bootstrap few-shot with random search.

  ## Examples

      {:ok, program_id} = DSPex.Modules.Predict.create("question -> answer")
      
      trainset = [
        %{question: "What is AI?", answer: "Artificial Intelligence..."},
        # ... more examples
      ]
      
      {:ok, optimized} = DSPex.Optimizers.BootstrapFewShotWithRandomSearch.optimize(
        program_id,
        trainset,
        num_candidate_sets: 10,
        max_bootstrapped_demos: 3
      )
  """
  def optimize(program_id, trainset, opts \\ []) do
    optimizer_id = ID.generate("bootstrap_rs")

    config = %{
      metric: opts[:metric],
      teacher_settings: opts[:teacher_settings] || %{},
      max_bootstrapped_demos: opts[:max_bootstrapped_demos] || 4,
      max_labeled_demos: opts[:max_labeled_demos] || 16,
      max_rounds: opts[:max_rounds] || 1,
      num_candidate_programs: opts[:num_candidate_programs] || 16,
      num_threads: opts[:num_threads] || 6,
      max_errors: opts[:max_errors] || 5,
      stop_at_score: opts[:stop_at_score],
      metric_threshold: opts[:metric_threshold]
    }

    # Configure random search parameters
    search_config = %{
      num_candidate_sets: opts[:num_candidate_sets] || 10,
      seed: opts[:seed] || 2024
    }

    # Create the optimizer
    with {:ok, _} <-
           Snakepit.Python.call(
             "dspy.BootstrapFewShotWithRandomSearch",
             Map.merge(config, search_config),
             Keyword.merge([store_as: optimizer_id], opts)
           ),
         # Compile the program
         {:ok, result} <-
           Snakepit.Python.call(
             "stored.#{optimizer_id}.compile",
             %{
               student: "stored.#{program_id}",
               trainset: trainset,
               valset: opts[:valset]
             },
             opts
           ) do
      {:ok,
       %{
         optimized_program_id: "#{program_id}_rs_optimized",
         optimizer_id: optimizer_id,
         result: result
       }}
    end
  end
end

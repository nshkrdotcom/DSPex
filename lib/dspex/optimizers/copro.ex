defmodule DSPex.Optimizers.COPRO do
  @moduledoc """
  COPRO (Coordinate Prompt Optimization).

  Optimizes prompts by coordinating multiple optimization strategies.
  Particularly effective for multi-stage reasoning tasks.
  """

  alias DSPex.Utils.ID

  @doc """
  Optimize a program using COPRO.

  ## Examples

      {:ok, program_id} = DSPex.Modules.ChainOfThought.create("question -> answer")
      
      trainset = [
        %{question: "Explain photosynthesis", answer: "..."},
        # ... more examples
      ]
      
      {:ok, optimized} = DSPex.Optimizers.COPRO.optimize(
        program_id,
        trainset,
        depth: 3,
        breadth: 10
      )
  """
  def optimize(program_id, trainset, opts \\ []) do
    optimizer_id = ID.generate("copro")

    config = %{
      metric: opts[:metric],
      depth: opts[:depth] || 3,
      breadth: opts[:breadth] || 10,
      init_temperature: opts[:init_temperature] || 1.4,
      track_stats: opts[:track_stats] || true,
      verbose: opts[:verbose] || false
    }

    # Create the optimizer
    with {:ok, _} <-
           Snakepit.Python.call(
             "dspy.COPRO",
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
               eval_kwargs: opts[:eval_kwargs] || %{}
             },
             opts
           ) do
      {:ok,
       %{
         optimized_program_id: "#{program_id}_copro",
         optimizer_id: optimizer_id,
         result: result
       }}
    end
  end
end

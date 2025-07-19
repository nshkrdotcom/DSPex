defmodule DSPEx.Teleprompter.SIMBA.Strategy.AppendRule do
  @moduledoc """
  AppendRule strategy for SIMBA instruction-based optimization.

  This strategy analyzes trajectory patterns to identify what differentiates
  successful from unsuccessful executions, then generates improved instructions
  to help the program perform better on similar tasks.

  Based on DSPy's append_a_rule strategy from the SIMBA implementation.
  """

  @behaviour DSPEx.Teleprompter.SIMBA.Strategy

  alias DSPEx.Teleprompter.SIMBA.{Bucket, Trajectory}
  alias DSPEx.Teleprompter.SIMBA.Signatures.OfferFeedback

  require Logger

  @doc """
  Returns the strategy name identifier.
  """
  @spec strategy_name() :: atom()
  def strategy_name, do: :append_rule

  @doc """
  Check if this strategy is applicable to the given bucket and context.

  AppendRule requires:
  1. At least some trajectories in the bucket
  2. Variance in success patterns (both successful and failed trajectories)
  3. Sufficient trajectory data for meaningful analysis
  """
  @spec applicable?(Bucket.t(), map()) :: boolean()
  def applicable?(%Bucket{trajectories: []}, _context), do: false

  def applicable?(%Bucket{trajectories: trajectories}, _context) when length(trajectories) < 2,
    do: false

  def applicable?(%Bucket{trajectories: trajectories}, _context) do
    successful_count = Enum.count(trajectories, &Trajectory.successful?/1)
    failed_count = length(trajectories) - successful_count

    # Need both successful and failed trajectories for comparison
    successful_count > 0 && failed_count > 0
  end

  @doc """
  Apply the AppendRule strategy to improve the program instruction.

  Analyzes trajectory patterns and uses LLM to generate instruction improvements.
  """
  @spec apply(Bucket.t(), struct(), map()) :: {:ok, struct()} | {:skip, String.t()}
  def apply(%Bucket{trajectories: trajectories}, source_program, opts) do
    # Build context for the old apply/2 interface
    context = Map.merge(opts, %{current_program: source_program})

    with {:ok, trajectory_analysis} <- analyze_trajectories(trajectories),
         {:ok, instruction_advice} <- generate_instruction_advice(trajectory_analysis, context),
         {:ok, enhanced_program} <-
           apply_instruction_improvements(context.current_program, instruction_advice) do
      Logger.debug("AppendRule strategy successfully enhanced program instruction")
      {:ok, enhanced_program}
    else
      {:error, reason} ->
        Logger.warning("AppendRule strategy failed: #{reason}")
        {:skip, reason}
    end
  end

  # Private helper functions

  defp analyze_trajectories(trajectories) do
    successful_trajectories = Enum.filter(trajectories, &Trajectory.successful?/1)
    failed_trajectories = Enum.reject(trajectories, &Trajectory.successful?/1)

    if Enum.empty?(successful_trajectories) || Enum.empty?(failed_trajectories) do
      {:error, "insufficient trajectory variance for rule generation"}
    else
      # Select representative trajectories for analysis
      best_trajectory = Enum.max_by(successful_trajectories, &Trajectory.quality_score/1)
      worst_trajectory = Enum.min_by(failed_trajectories, &Trajectory.quality_score/1)

      {:ok,
       %{
         better_trajectory: best_trajectory,
         worse_trajectory: worst_trajectory,
         successful_count: length(successful_trajectories),
         failed_count: length(failed_trajectories)
       }}
    end
  end

  defp generate_instruction_advice(analysis, context) do
    # Format trajectory information for LLM analysis
    better_trajectory_text = format_trajectory_for_analysis(analysis.better_trajectory)
    worse_trajectory_text = format_trajectory_for_analysis(analysis.worse_trajectory)

    # Prepare inputs for OfferFeedback signature
    inputs = %{
      program_code: inspect(context.current_program),
      modules_defn: "DSPEx program with signature #{inspect(context.current_program.signature)}",
      better_program_trajectory: better_trajectory_text,
      worse_program_trajectory: worse_trajectory_text
    }

    # Use LLM to generate instruction improvements
    case call_offer_feedback_llm(inputs, context) do
      {:ok, response} ->
        extract_instruction_advice({:ok, response})

      response when is_binary(response) ->
        # Handle direct string responses (like mock failing client)
        extract_instruction_advice({:ok, response})

      {:error, reason} ->
        {:error, "failed to generate instruction advice: #{reason}"}
    end
  end

  defp call_offer_feedback_llm(inputs, context) do
    # Use the client from context or fall back to default
    client_fn = Map.get(context, :client, &default_client_call/3)

    # Call the LLM with OfferFeedback signature
    client_fn.(OfferFeedback, inputs, temperature: 0.3)
  rescue
    error ->
      {:error, "LLM call failed: #{inspect(error)}"}
  end

  defp default_client_call(signature, inputs, options) do
    # Default implementation using DSPEx.Program
    client = Keyword.get(options, :client, :default)
    temperature = Keyword.get(options, :temperature, 0.3)

    # Create a prediction program
    program = DSPEx.Predict.new(signature, client)

    # Execute the prediction - options should be a keyword list
    case DSPEx.Program.forward(program, inputs, temperature: temperature) do
      {:ok, outputs} -> {:ok, outputs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_instruction_advice({:ok, %{module_advice: advice}}) when is_map(advice) do
    # Extract the main instruction improvement
    main_advice = Map.get(advice, "main", Map.values(advice) |> List.first())

    if is_binary(main_advice) && String.length(main_advice) > 10 do
      {:ok, String.trim(main_advice)}
    else
      {:error, "no meaningful instruction advice generated"}
    end
  end

  defp extract_instruction_advice({:ok, response}) do
    {:error, "malformed LLM response: #{inspect(response)}"}
  end

  defp apply_instruction_improvements(program, advice) do
    current_instruction = program.instruction || ""

    # Combine existing instruction with new advice
    enhanced_instruction =
      if String.length(current_instruction) > 0 do
        "#{current_instruction}\n\nAdditional guidance: #{advice}"
      else
        "#{advice}"
      end

    # Create enhanced program with new instruction
    enhanced_program = %{program | instruction: enhanced_instruction}

    {:ok, enhanced_program}
  end

  defp format_trajectory_for_analysis(trajectory) do
    """
    Input: #{inspect(trajectory.inputs)}
    Output: #{inspect(trajectory.outputs)}
    Score: #{trajectory.score}
    Success: #{trajectory.success}
    #{if trajectory.error, do: "Error: #{inspect(trajectory.error)}", else: ""}
    """
    |> String.trim()
  end
end

defmodule DSPEx.Teleprompter.SIMBA.Bucket do
  @moduledoc """
  Represents a bucket of trajectories grouped by performance characteristics.

  Buckets are used to identify patterns in program execution and determine
  which trajectories are suitable for strategy application. Each bucket
  contains trajectories from the same example but with different program
  configurations or model settings.
  """

  alias DSPEx.Teleprompter.SIMBA.Trajectory

  @enforce_keys [:trajectories]
  defstruct [
    # List of trajectories in this bucket
    :trajectories,
    # Highest score in bucket
    :max_score,
    # Lowest score in bucket
    :min_score,
    # Average score in bucket
    :avg_score,
    # Difference between max and min scores
    :max_to_min_gap,
    # Difference between max and average scores
    :max_to_avg_gap,
    # Additional bucket metadata
    :metadata
  ]

  @type t :: %__MODULE__{
          trajectories: [Trajectory.t()],
          max_score: float() | nil,
          min_score: float() | nil,
          avg_score: float() | nil,
          max_to_min_gap: float() | nil,
          max_to_avg_gap: float() | nil,
          metadata: map() | nil
        }

  @doc """
  Create a new bucket from trajectories.
  """
  @spec new([Trajectory.t()], keyword()) :: t()
  def new(trajectories, opts \\ []) do
    scores = Enum.map(trajectories, &Trajectory.quality_score/1)

    max_score = if Enum.empty?(scores), do: 0.0, else: Enum.max(scores)
    min_score = if Enum.empty?(scores), do: 0.0, else: Enum.min(scores)
    avg_score = if Enum.empty?(scores), do: 0.0, else: Enum.sum(scores) / length(scores)

    %__MODULE__{
      trajectories: Enum.sort_by(trajectories, &(-Trajectory.quality_score(&1))),
      max_score: max_score,
      min_score: min_score,
      avg_score: avg_score,
      max_to_min_gap: max_score - min_score,
      max_to_avg_gap: max_score - avg_score,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Check if bucket shows improvement potential for strategy application.
  """
  @spec has_improvement_potential?(t(), float()) :: boolean()
  def has_improvement_potential?(
        %__MODULE__{max_to_min_gap: gap, max_score: max_score},
        threshold \\ 0.1
      ) do
    gap > threshold and max_score > 0.1
  end

  @doc """
  Get the best trajectory from the bucket.
  """
  @spec best_trajectory(t()) :: Trajectory.t() | nil
  def best_trajectory(%__MODULE__{trajectories: []}), do: nil
  def best_trajectory(%__MODULE__{trajectories: [best | _]}), do: best

  @doc """
  Get successful trajectories from the bucket.
  """
  @spec successful_trajectories(t()) :: [Trajectory.t()]
  def successful_trajectories(%__MODULE__{trajectories: trajectories}) do
    Enum.filter(trajectories, &Trajectory.successful?/1)
  end

  @doc """
  Calculate bucket statistics.
  """
  @spec statistics(t()) :: map()
  def statistics(%__MODULE__{} = bucket) do
    %{
      trajectory_count: length(bucket.trajectories),
      successful_count: length(successful_trajectories(bucket)),
      max_score: bucket.max_score,
      min_score: bucket.min_score,
      avg_score: bucket.avg_score,
      score_variance: calculate_score_variance(bucket),
      improvement_potential: has_improvement_potential?(bucket)
    }
  end

  defp calculate_score_variance(%__MODULE__{trajectories: trajectories, avg_score: avg_score}) do
    if length(trajectories) <= 1 do
      0.0
    else
      scores = Enum.map(trajectories, &Trajectory.quality_score/1)

      variance_sum =
        Enum.reduce(scores, 0.0, fn score, acc ->
          diff = score - avg_score
          acc + diff * diff
        end)

      variance_sum / length(scores)
    end
  end
end

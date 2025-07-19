defmodule ElixirML.Resources.OptimizationRun do
  @moduledoc """
  OptimizationRun resource for ElixirML.

  Represents an optimization run that tracks the optimization process
  and results for a program.
  """

  use ElixirML.Resource
  alias ElixirML.Resources.Schemas

  attributes do
    attribute(:name, :string, allow_nil?: false)

    attribute(:status, :atom,
      constraints: [one_of: [:pending, :running, :completed, :failed, :cancelled]],
      default: :pending
    )

    attribute(:strategy, :atom,
      constraints: [one_of: [:simba, :bayesian, :grid_search, :random]],
      default: :simba
    )

    schema_attribute(:config, Schemas.OptimizationConfig, default: %{})
    schema_attribute(:results, Schemas.OptimizationResults, default: %{})
    schema_attribute(:metrics, Schemas.PerformanceMetrics, default: %{})

    attribute(:started_at, :string, default: nil)
    attribute(:completed_at, :string, default: nil)
    attribute(:created_at, :string, default: nil)
    attribute(:updated_at, :string, default: nil)
  end

  relationships do
    belongs_to(:program, ElixirML.Resources.Program)
    belongs_to(:variable_space, ElixirML.Resources.VariableSpace)
    has_many(:configurations, ElixirML.Resources.VariableConfiguration)
  end

  actions do
    action :start do
      argument(:training_data, {:array, :map}, allow_nil?: false)
    end

    action :stop do
    end

    action :update_progress do
      argument(:progress, :float, allow_nil?: false)
      argument(:current_metrics, :map, default: %{})
    end
  end

  calculations do
    calculate(:duration, :integer, __MODULE__.Calculations.Duration)
    calculate(:best_score, :float, __MODULE__.Calculations.BestScore)
    calculate(:iterations_completed, :integer, __MODULE__.Calculations.IterationsCompleted)
  end

  # Calculation modules
  defmodule Calculations do
    @moduledoc """
    Calculation modules for OptimizationRun resource.
    """

    defmodule Duration do
      @moduledoc """
      Calculates the duration of the optimization run.
      """

      def calculate(run, _args) do
        case {run.started_at, run.completed_at} do
          {nil, _} -> {:ok, 0}
          {_, nil} -> {:ok, 0}
          {start_time, end_time} -> {:ok, end_time - start_time}
        end
      end
    end

    defmodule BestScore do
      @moduledoc """
      Returns the best score achieved during the optimization run.
      """

      def calculate(run, _args) do
        best_score = Map.get(run.results || %{}, :best_score, 0.0)
        {:ok, best_score}
      end
    end

    defmodule IterationsCompleted do
      @moduledoc """
      Returns the number of iterations completed in the optimization run.
      """

      def calculate(run, _args) do
        iterations = Map.get(run.results || %{}, :iterations_completed, 0)
        {:ok, iterations}
      end
    end
  end
end

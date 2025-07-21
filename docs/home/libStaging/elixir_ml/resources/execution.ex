defmodule ElixirML.Resources.Execution do
  @moduledoc """
  Execution resource for ElixirML.

  Represents a single execution of a program with specific inputs
  and configuration.
  """

  use ElixirML.Resource
  alias ElixirML.Resources.Schemas

  attributes do
    attribute(:status, :atom,
      constraints: [one_of: [:pending, :running, :completed, :failed]],
      default: :pending
    )

    schema_attribute(:inputs, Schemas.ExecutionInputs, allow_nil?: false)
    schema_attribute(:outputs, Schemas.ExecutionOutputs, default: %{})
    schema_attribute(:configuration, Schemas.VariableValues, default: %{})
    schema_attribute(:metrics, Schemas.ExecutionMetrics, default: %{})

    attribute(:started_at, :string, default: nil)
    attribute(:completed_at, :string, default: nil)
    attribute(:error_message, :string, default: nil)

    attribute(:created_at, :string, default: nil)
    attribute(:updated_at, :string, default: nil)
  end

  relationships do
    belongs_to(:program, ElixirML.Resources.Program)
    belongs_to(:variable_configuration, ElixirML.Resources.VariableConfiguration)
  end

  actions do
    action :start do
    end

    action :complete do
      argument(:outputs, :map, allow_nil?: false)
      argument(:metrics, :map, default: %{})
    end

    action :fail do
      argument(:error_message, :string, allow_nil?: false)
    end
  end

  calculations do
    calculate(:duration, :integer, __MODULE__.Calculations.Duration)
    calculate(:success, :boolean, __MODULE__.Calculations.Success)
  end

  # Calculation modules
  defmodule Calculations do
    @moduledoc """
    Calculation modules for Execution resource.
    """

    defmodule Duration do
      @moduledoc """
      Calculates the duration of the execution.
      """

      def calculate(execution, _args) do
        case {execution.started_at, execution.completed_at} do
          {nil, _} -> {:ok, 0}
          {_, nil} -> {:ok, 0}
          {start_time, end_time} -> {:ok, end_time - start_time}
        end
      end
    end

    defmodule Success do
      @moduledoc """
      Determines if the execution was successful.
      """

      def calculate(execution, _args) do
        success = execution.status == :completed
        {:ok, success}
      end
    end
  end
end

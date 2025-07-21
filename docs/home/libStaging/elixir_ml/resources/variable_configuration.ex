defmodule ElixirML.Resources.VariableConfiguration do
  @moduledoc """
  VariableConfiguration resource for ElixirML.

  Represents a specific configuration of variables within a variable space.
  Used for optimization runs and program execution.
  """

  use ElixirML.Resource
  alias ElixirML.Resources.Schemas

  attributes do
    attribute(:name, :string, default: "")

    schema_attribute(:configuration, Schemas.VariableValues, allow_nil?: false)
    schema_attribute(:metadata, Schemas.ConfigurationMetadata, default: %{})

    attribute(:performance_score, :float, default: nil)

    attribute(:validation_status, :atom,
      constraints: [one_of: [:valid, :invalid, :unknown]],
      default: :unknown
    )

    attribute(:created_at, :string, default: nil)
    attribute(:updated_at, :string, default: nil)
  end

  relationships do
    belongs_to(:variable_space, ElixirML.Resources.VariableSpace)
    belongs_to(:optimization_run, ElixirML.Resources.OptimizationRun)
  end

  actions do
    action :validate do
    end

    action :update_performance do
      argument(:score, :float, allow_nil?: false)
      argument(:metrics, :map, default: %{})
    end
  end

  calculations do
    calculate(:variable_count, :integer, __MODULE__.Calculations.VariableCount)
    calculate(:is_valid, :boolean, __MODULE__.Calculations.IsValid)
  end

  @doc """
  Creates a configuration from a map of variable values.
  """
  @spec from_values(term(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def from_values(variable_space_id, values, opts \\ []) do
    create(%{
      name: Keyword.get(opts, :name, "Configuration"),
      variable_space_id: variable_space_id,
      configuration: values,
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  # Calculation modules
  defmodule Calculations do
    @moduledoc """
    Calculation modules for VariableConfiguration resource.
    """

    defmodule VariableCount do
      @moduledoc """
      Counts the number of variables in the configuration.
      """

      def calculate(config, _args) do
        count = map_size(config.configuration || %{})
        {:ok, count}
      end
    end

    defmodule IsValid do
      @moduledoc """
      Determines if the variable configuration is valid.
      """

      def calculate(config, _args) do
        valid = config.validation_status == :valid
        {:ok, valid}
      end
    end
  end
end

defmodule ElixirML.Resources.Program do
  @moduledoc """
  Program resource for ElixirML.

  Represents a machine learning program with signature, configuration,
  and optimization capabilities. Integrates with the Variable System
  for automatic parameter optimization.

  ## Usage

      {:ok, program} = ElixirML.Resources.Program.create(%{
        name: "Question Answering",
        type: :chain_of_thought,
        signature_config: %{
          input_fields: [%{"name" => "question", "type" => "string"}],
          output_fields: [%{"name" => "answer", "type" => "string"}]
        }
      })

      {:ok, result} = ElixirML.Resources.Program.execute_action(
        program,
        :execute,
        %{inputs: %{question: "What is the capital of France?"}}
      )
  """

  use ElixirML.Resource
  alias ElixirML.Resources.Schemas
  alias ElixirML.Variable.Space

  attributes do
    attribute(:name, :string, allow_nil?: false)

    attribute(:type, :atom,
      constraints: [one_of: [:predict, :chain_of_thought, :react, :program_of_thought, :custom]],
      allow_nil?: false
    )

    schema_attribute(:signature_config, Schemas.ProgramSignatureConfig, allow_nil?: false)
    schema_attribute(:program_config, Schemas.ProgramConfig, default: %{})

    attribute(:status, :atom,
      constraints: [one_of: [:draft, :active, :optimizing, :archived]],
      default: :draft
    )

    schema_attribute(:performance_metrics, Schemas.PerformanceMetrics, default: %{})

    # Metadata
    attribute(:created_at, :string, default: nil)
    attribute(:updated_at, :string, default: nil)
    attribute(:version, :integer, default: 1)
  end

  relationships do
    belongs_to(:variable_space, ElixirML.Resources.VariableSpace)
    has_many(:optimization_runs, ElixirML.Resources.OptimizationRun)
    has_many(:executions, ElixirML.Resources.Execution)
  end

  actions do
    action :execute do
      argument(:inputs, :map, allow_nil?: false)
      argument(:variable_configuration, :map, default: %{})
      argument(:options, :map, default: %{})
    end

    action :optimize do
      argument(:training_data, {:array, :map}, allow_nil?: false)
      argument(:optimization_strategy, :atom, default: :simba)
      argument(:optimization_config, :map, default: %{})
    end

    action :validate_inputs do
      argument(:inputs, :map, allow_nil?: false)
    end

    action :update_performance do
      argument(:metrics, :map, allow_nil?: false)
    end
  end

  calculations do
    calculate(:current_performance_score, :float, __MODULE__.Calculations.CurrentPerformanceScore)
    calculate(:optimization_count, :integer, __MODULE__.Calculations.OptimizationCount)

    calculate(
      :variable_importance_scores,
      {:array, :map},
      __MODULE__.Calculations.VariableImportanceScores
    )

    calculate(:execution_history, {:array, :map}, __MODULE__.Calculations.ExecutionHistory)
  end

  # Note: Custom validations removed to fix compilation issues
  # Resource-level validations would be implemented differently

  # Helper functions for program creation and management

  @doc """
  Creates a program from a DSPEx signature and configuration.
  """
  @spec from_signature(module(), keyword()) :: {:ok, struct()} | {:error, term()}
  def from_signature(signature_module, opts \\ []) do
    # Extract signature information
    signature_config = extract_signature_config(signature_module)

    # Extract variables if variable space is requested
    variable_space_id =
      if Keyword.get(opts, :create_variable_space, true) do
        {:ok, var_space} = create_variable_space_from_signature(signature_module, opts)
        var_space.id
      else
        nil
      end

    create(%{
      name: Keyword.get(opts, :name, "Program"),
      type: Keyword.get(opts, :type, :predict),
      signature_config: signature_config,
      program_config: Keyword.get(opts, :config, %{}),
      variable_space_id: variable_space_id
    })
  end

  @doc """
  Extracts variables from the program for optimization.
  """
  @spec get_variable_space(struct()) :: Space.t()
  def get_variable_space(_program) do
    # Extract variables from program configuration and signature
    # This would integrate with the Variable system when VariableSpace resource is implemented
    Space.new()
  end

  # Private helper functions

  @spec extract_signature_config(module()) :: map()
  defp extract_signature_config(_signature_module) do
    # This would extract the actual signature configuration
    # For now, return a basic structure
    %{
      input_fields: [%{"name" => "input", "type" => "string"}],
      output_fields: [%{"name" => "output", "type" => "string"}],
      instructions: "Basic program instructions",
      examples: []
    }
  end

  @spec create_variable_space_from_signature(module(), keyword()) :: {:ok, map()}
  defp create_variable_space_from_signature(_signature_module, _opts) do
    # Create a variable space based on the signature
    # This would integrate with the existing Variable system when VariableSpace resource is implemented
    {:ok, %{id: :placeholder_variable_space_id}}
  end

  # Calculation modules (these would be implemented separately)
  defmodule Calculations do
    @moduledoc """
    Calculation modules for Program resource.
    """

    defmodule CurrentPerformanceScore do
      @moduledoc """
      Calculates the current performance score based on metrics.
      """

      def calculate(program, _args) do
        # Calculate current performance based on recent metrics
        metrics = program.performance_metrics || %{}

        # Simple composite score: average of accuracy, precision, recall
        accuracy = Map.get(metrics, :accuracy, 0.0)
        precision = Map.get(metrics, :precision, 0.0)
        recall = Map.get(metrics, :recall, 0.0)

        score = (accuracy + precision + recall) / 3.0
        {:ok, score}
      end
    end

    defmodule OptimizationCount do
      @moduledoc """
      Counts the number of optimization runs for this program.
      """

      def calculate(program, _args) do
        # Count optimization runs for this program
        # In a real implementation, this would query the relationship
        {:ok, length(program.optimization_runs || [])}
      end
    end

    defmodule VariableImportanceScores do
      @moduledoc """
      Calculates variable importance scores based on optimization history.
      """

      def calculate(_program, _args) do
        # Calculate variable importance based on optimization history
        # This would analyze optimization runs to determine variable impact
        {:ok, []}
      end
    end

    defmodule ExecutionHistory do
      @moduledoc """
      Returns the execution history for this program.
      """

      def calculate(program, _args) do
        # Return execution history for this program
        {:ok, program.executions || []}
      end
    end
  end
end

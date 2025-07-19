defmodule ElixirML do
  @moduledoc """
  ElixirML - Revolutionary ML Foundation for Elixir

  ElixirML provides a comprehensive foundation for machine learning workflows in Elixir,
  featuring universal parameter optimization, ML-native type systems, and advanced
  process orchestration.

  ## Key Components

  - **Schema Engine**: ML-specific validation with compile-time optimization
  - **Variable System**: Universal parameter optimization enabling automatic module selection  
  - **Resource Framework**: Ash-inspired declarative resource management
  - **Process Orchestrator**: Advanced supervision and process management

  ## Quick Start

      # Define an ML schema
      defmodule MyApp.QASchema do
        use ElixirML.Schema

        defschema QuestionAnswering do
          field :question, :string, required: true
          field :context, :string, required: true
          field :answer, :string, required: true
          field :confidence, :probability, default: 0.8
        end
      end

      # Create a variable space for optimization
      space = ElixirML.Variable.Space.new()
      |> ElixirML.Variable.Space.add_variable(
        ElixirML.Variable.MLTypes.provider(:provider)
      )
      |> ElixirML.Variable.Space.add_variable(
        ElixirML.Variable.MLTypes.temperature(:temperature, range: {0.0, 1.0})
      )

      # Generate optimized configurations
      {:ok, config} = ElixirML.Variable.Space.random_configuration(space)

  ## Architecture

  ElixirML is built on four foundation components:

  1. **Schema Engine** (`ElixirML.Schema`) - Provides ML-specific type validation
  2. **Variable System** (`ElixirML.Variable`) - Universal parameter optimization
  3. **Resource Framework** (`ElixirML.Resource`) - Declarative resource management  
  4. **Process Orchestrator** (`ElixirML.Process`) - Advanced supervision and execution
  """

  @doc """
  Start the ElixirML application and all supervised processes.
  """
  def start do
    ElixirML.Application.start(nil, nil)
  end

  @doc """
  Get the current status of all ElixirML components.
  """
  def status do
    %{
      orchestrator: orchestrator_status(),
      registries: registry_status(),
      resources: resource_status(),
      version: version()
    }
  end

  @doc """
  Get ElixirML version information.
  """
  def version do
    try do
      Application.spec(:elixir_ml, :vsn) |> to_string()
    rescue
      _ -> "dev"
    end
  end

  @doc """
  Execute a pipeline with the Process Orchestrator.
  """
  def execute_pipeline(pipeline, inputs, opts \\ []) do
    ElixirML.Process.Pipeline.execute(pipeline, inputs, opts)
  end

  @doc """
  Create and execute a program using the foundation.
  """
  def execute_program(program, inputs, opts \\ []) do
    ElixirML.Process.Pipeline.execute_program(program, inputs, opts)
  end

  @doc """
  Get comprehensive system statistics.
  """
  def system_stats do
    %{
      process_orchestrator: ElixirML.Process.Orchestrator.process_stats(),
      resource_manager: ElixirML.Process.ResourceManager.get_resource_stats(),
      schema_registry: ElixirML.Process.SchemaRegistry.cache_stats(),
      variable_registry: ElixirML.Process.VariableRegistry.registry_stats()
    }
  end

  # Private helper functions

  defp orchestrator_status do
    case Process.whereis(ElixirML.Process.Orchestrator) do
      nil ->
        :not_started

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :running
        else
          :stopped
        end
    end
  end

  defp registry_status do
    %{
      schema_registry: process_status(ElixirML.Process.SchemaRegistry),
      variable_registry: process_status(ElixirML.Process.VariableRegistry)
    }
  end

  defp resource_status do
    %{
      resource_manager: process_status(ElixirML.Process.ResourceManager),
      program_supervisor: process_status(ElixirML.Process.ProgramSupervisor)
    }
  end

  defp process_status(module) do
    case Process.whereis(module) do
      nil ->
        :not_started

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :running
        else
          :stopped
        end
    end
  end
end

defmodule ElixirML.Resources.VariableSpace do
  @moduledoc """
  VariableSpace resource for ElixirML.

  Represents a variable space that defines the parameter space for optimization.
  Integrates with the Variable System to provide structured variable management.
  """

  use ElixirML.Resource
  alias ElixirML.Resources.Schemas

  attributes do
    attribute(:name, :string, allow_nil?: false)
    attribute(:description, :string, default: "")

    schema_attribute(:variable_definitions, Schemas.VariableDefinitions, default: [])
    schema_attribute(:constraints, Schemas.VariableConstraints, default: %{})
    schema_attribute(:optimization_hints, Schemas.OptimizationHints, default: %{})

    attribute(:discrete_space_size, :integer, default: 1)
    attribute(:continuous_dimensions, :integer, default: 0)

    # Metadata
    attribute(:created_at, :string, default: nil)
    attribute(:updated_at, :string, default: nil)
  end

  relationships do
    has_many(:programs, ElixirML.Resources.Program)
    has_many(:optimization_runs, ElixirML.Resources.OptimizationRun)
    has_many(:configurations, ElixirML.Resources.VariableConfiguration)
  end

  actions do
    action :generate_configuration do
      argument(:strategy, :atom, default: :random)
      argument(:seed, :integer, default: nil)
    end

    action :validate_configuration do
      argument(:configuration, :map, allow_nil?: false)
    end
  end

  calculations do
    calculate(:variable_count, :integer, __MODULE__.Calculations.VariableCount)
    calculate(:complexity_score, :float, __MODULE__.Calculations.ComplexityScore)
    calculate(:optimization_difficulty, :atom, __MODULE__.Calculations.OptimizationDifficulty)
  end

  @doc """
  Creates a variable space from Variable.Space.
  """
  @spec from_variable_space(ElixirML.Variable.Space.t()) :: {:ok, struct()} | {:error, term()}
  def from_variable_space(%ElixirML.Variable.Space{} = space) do
    create(%{
      name: space.name,
      description: Map.get(space.metadata, :description, ""),
      variable_definitions: convert_variables_to_definitions(space.variables),
      constraints: convert_constraints(space.constraints),
      discrete_space_size: calculate_discrete_size(space.variables),
      continuous_dimensions: calculate_continuous_dimensions(space.variables)
    })
  end

  @doc """
  Converts resource to Variable.Space.
  """
  @spec to_variable_space(struct()) :: ElixirML.Variable.Space.t()
  def to_variable_space(variable_space) do
    %ElixirML.Variable.Space{
      id: ensure_valid_id(variable_space),
      name: variable_space.name,
      variables: convert_definitions_to_variables(variable_space.variable_definitions || []),
      dependencies: extract_dependencies(variable_space.variable_definitions || []),
      constraints: convert_constraints_to_functions(variable_space.constraints || %{}),
      metadata: build_metadata(variable_space),
      optimization_config: Map.get(variable_space, :optimization_hints, %{})
    }
  end

  # Helper functions
  @spec ensure_valid_id(struct()) :: String.t()
  defp ensure_valid_id(variable_space) do
    case Map.get(variable_space, :id) do
      nil -> generate_space_id()
      id when is_binary(id) -> id
      id -> to_string(id)
    end
  end

  @spec build_metadata(struct()) :: map()
  defp build_metadata(variable_space) do
    %{
      description: variable_space.description || "",
      discrete_space_size: variable_space.discrete_space_size || 1,
      continuous_dimensions: variable_space.continuous_dimensions || 0
    }
  end

  @spec convert_variables_to_definitions(map()) :: [map()]
  defp convert_variables_to_definitions(variables) do
    Enum.map(variables, fn {_name, variable} ->
      %{
        name: Atom.to_string(variable.name),
        type: Atom.to_string(variable.type),
        default: variable.default,
        constraints: variable.constraints,
        description: variable.description,
        metadata: variable.metadata,
        dependencies: variable.dependencies || []
      }
    end)
  end

  @spec convert_definitions_to_variables([map()]) :: map()
  defp convert_definitions_to_variables(definitions) do
    definitions
    |> Enum.map(&build_variable_from_definition/1)
    |> Map.new(fn var -> {var.name, var} end)
  end

  @spec build_variable_from_definition(map()) :: ElixirML.Variable.t()
  defp build_variable_from_definition(def) do
    %ElixirML.Variable{
      name: extract_atom_field(def, "name"),
      type: extract_atom_field(def, "type"),
      default: extract_field(def, "default"),
      constraints: extract_field(def, "constraints") || %{},
      description: extract_field(def, "description"),
      dependencies: extract_dependencies_list(def),
      metadata: extract_field(def, "metadata") || %{},
      optimization_hints: []
    }
  end

  @spec extract_atom_field(map(), String.t()) :: atom()
  defp extract_atom_field(def, field_name) do
    String.to_atom(def[field_name] || Map.get(def, String.to_atom(field_name)))
  end

  @spec extract_field(map(), String.t()) :: term()
  defp extract_field(def, field_name) do
    def[field_name] || Map.get(def, String.to_atom(field_name))
  end

  @spec extract_dependencies_list(map()) :: [atom()]
  defp extract_dependencies_list(def) do
    deps = extract_field(def, "dependencies") || []
    Enum.map(deps, &String.to_atom/1)
  end

  @spec extract_dependencies([map()]) :: %{atom() => [atom()]}
  defp extract_dependencies(definitions) do
    definitions
    |> Enum.reduce(%{}, fn def, acc ->
      name = String.to_atom(def["name"] || def.name)

      deps =
        (def["dependencies"] || def.dependencies || [])
        |> Enum.map(&String.to_atom/1)

      Map.put(acc, name, deps)
    end)
  end

  @spec convert_constraints_to_functions(map()) :: [function()]
  defp convert_constraints_to_functions(constraints) when is_map(constraints) do
    # Convert constraint map to list of constraint functions
    # This is a simplified conversion - in practice, you might want more sophisticated constraint handling
    Map.get(constraints, :validations, [])
  end

  @spec convert_constraints([function()]) :: map()
  defp convert_constraints(constraints) do
    %{
      validations: constraints,
      dependencies: %{}
    }
  end

  @spec generate_space_id() :: String.t()
  defp generate_space_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @spec calculate_discrete_size(map()) :: non_neg_integer()
  defp calculate_discrete_size(variables) do
    variables
    |> Map.values()
    |> Enum.map(&discrete_variable_size/1)
    |> Enum.reduce(1, &*/2)
  end

  @spec calculate_continuous_dimensions(map()) :: non_neg_integer()
  defp calculate_continuous_dimensions(variables) do
    variables
    |> Map.values()
    |> Enum.count(fn var -> var.type == :float end)
  end

  @spec discrete_variable_size(ElixirML.Variable.t()) :: pos_integer()
  defp discrete_variable_size(%ElixirML.Variable{type: :choice, constraints: %{choices: choices}}) do
    length(choices)
  end

  defp discrete_variable_size(%ElixirML.Variable{
         type: :integer,
         constraints: %{range: {min, max}}
       }) do
    max - min + 1
  end

  defp discrete_variable_size(%ElixirML.Variable{type: :module, constraints: %{modules: modules}}) do
    length(modules)
  end

  defp discrete_variable_size(_), do: 1

  # Calculation modules
  defmodule Calculations do
    @moduledoc """
    Calculation modules for VariableSpace resource.
    """

    defmodule VariableCount do
      @moduledoc """
      Calculates the number of variables in a variable space.
      """

      def calculate(variable_space, _args) do
        count = length(variable_space.variable_definitions || [])
        {:ok, count}
      end
    end

    defmodule ComplexityScore do
      @moduledoc """
      Calculates a complexity score based on variables and constraints.
      """

      def calculate(variable_space, _args) do
        # Simple complexity score based on number of variables and constraints
        var_count = length(variable_space.variable_definitions || [])
        constraint_count = map_size(variable_space.constraints || %{})

        score = var_count * 1.0 + constraint_count * 2.0
        {:ok, score}
      end
    end

    defmodule OptimizationDifficulty do
      @moduledoc """
      Determines the optimization difficulty level based on variable count.
      """

      def calculate(variable_space, _args) do
        var_count = length(variable_space.variable_definitions || [])

        difficulty =
          cond do
            var_count <= 3 -> :easy
            var_count <= 8 -> :medium
            var_count <= 15 -> :hard
            true -> :extreme
          end

        {:ok, difficulty}
      end
    end
  end
end

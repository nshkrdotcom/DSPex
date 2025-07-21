defmodule ElixirML.Variable.Space do
  @moduledoc """
  Manages collections of variables with relationships and constraints.
  Provides the search space for optimization algorithms.

  Variable Spaces are the foundation for automatic optimization - they define
  the complete parameter space that optimizers can explore.
  """

  @enforce_keys [:id, :name]
  defstruct [
    # Unique identifier
    :id,
    # Human-readable name
    :name,
    # Map of variable_name => Variable
    :variables,
    # Variable dependency graph
    :dependencies,
    # Cross-variable constraints
    :constraints,
    # Space-level metadata
    :metadata,
    # Optimization-specific configuration
    :optimization_config
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          variables: %{atom() => ElixirML.Variable.t()},
          dependencies: %{atom() => [atom()]},
          constraints: [function()],
          metadata: map(),
          optimization_config: map()
        }

  @doc """
  Create a new variable space.

  ## Examples

      iex> space = ElixirML.Variable.Space.new(name: "ML Model Config")
      iex> space.name
      "ML Model Config"
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      name: Keyword.get(opts, :name, "VariableSpace"),
      variables: %{},
      dependencies: %{},
      constraints: [],
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_config: Keyword.get(opts, :optimization_config, %{})
    }
  end

  @doc """
  Add a variable to the space.

  ## Examples

      iex> space = ElixirML.Variable.Space.new()
      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> space = ElixirML.Variable.Space.add_variable(space, var)
      iex> Map.has_key?(space.variables, :temperature)
      true
  """
  @spec add_variable(t(), ElixirML.Variable.t()) :: t()
  def add_variable(%__MODULE__{} = space, %ElixirML.Variable{} = variable) do
    updated_variables = Map.put(space.variables, variable.name, variable)
    updated_dependencies = Map.put(space.dependencies, variable.name, variable.dependencies)

    %{space | variables: updated_variables, dependencies: updated_dependencies}
  end

  @doc """
  Add multiple variables to the space.
  """
  @spec add_variables(t(), [ElixirML.Variable.t()]) :: t()
  def add_variables(%__MODULE__{} = space, variables) when is_list(variables) do
    Enum.reduce(variables, space, &add_variable(&2, &1))
  end

  @doc """
  Get a variable from the space by name.
  """
  @spec get_variable(t(), atom()) :: ElixirML.Variable.t() | nil
  def get_variable(%__MODULE__{} = space, name) do
    Map.get(space.variables, name)
  end

  @doc """
  Remove a variable from the space.
  """
  @spec remove_variable(t(), atom()) :: t()
  def remove_variable(%__MODULE__{} = space, name) do
    updated_variables = Map.delete(space.variables, name)
    updated_dependencies = Map.delete(space.dependencies, name)

    # Also remove any dependencies on this variable
    cleaned_dependencies =
      Enum.reduce(updated_dependencies, %{}, fn {var_name, deps}, acc ->
        cleaned_deps = Enum.reject(deps, &(&1 == name))
        Map.put(acc, var_name, cleaned_deps)
      end)

    %{space | variables: updated_variables, dependencies: cleaned_dependencies}
  end

  @doc """
  Add a cross-variable constraint to the space.

  ## Examples

      iex> space = ElixirML.Variable.Space.new()
      iex> constraint = fn config ->
      ...>   if config.temperature > 1.0 and config.provider == :groq do
      ...>     {:error, "Groq doesn't support high temperature"}
      ...>   else
      ...>     {:ok, config}
      ...>   end
      ...> end
      iex> space = ElixirML.Variable.Space.add_constraint(space, constraint)
      iex> length(space.constraints)
      1
  """
  @spec add_constraint(t(), function()) :: t()
  def add_constraint(%__MODULE__{} = space, constraint_fn) when is_function(constraint_fn, 1) do
    %{space | constraints: [constraint_fn | space.constraints]}
  end

  @doc """
  Validate a configuration against the variable space.

  This checks:
  1. All variables are present (or have defaults)
  2. All values are valid for their variable constraints
  3. All cross-variable constraints are satisfied
  4. All dependencies are resolved

  ## Examples

      iex> space = ElixirML.Variable.Space.new()
      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> space = ElixirML.Variable.Space.add_variable(space, var)
      iex> config = %{temperature: 0.8}
      iex> ElixirML.Variable.Space.validate_configuration(space, config)
      {:ok, %{temperature: 0.8}}
  """
  @spec validate_configuration(t(), map()) :: {:ok, map()} | {:error, String.t()}
  def validate_configuration(%__MODULE__{} = space, configuration) do
    with {:ok, complete_config} <- ensure_all_variables_present(space, configuration),
         {:ok, validated_config} <- validate_variable_values(space, complete_config),
         {:ok, resolved_config} <- resolve_dependencies(space, validated_config),
         {:ok, final_config} <- validate_constraints(space, resolved_config) do
      {:ok, final_config}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Generate a random configuration within the variable space constraints.

  ## Examples

      iex> space = ElixirML.Variable.Space.new()
      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> space = ElixirML.Variable.Space.add_variable(space, var)
      iex> {:ok, config} = ElixirML.Variable.Space.random_configuration(space)
      iex> Map.has_key?(config, :temperature)
      true
  """
  @spec random_configuration(t()) :: {:ok, map()} | {:error, String.t()}
  def random_configuration(%__MODULE__{} = space) do
    config =
      Enum.reduce(space.variables, %{}, fn {name, variable}, acc ->
        if variable.type != :composite do
          value = ElixirML.Variable.random_value(variable)
          Map.put(acc, name, value)
        else
          acc
        end
      end)

    # Resolve composite variables
    case resolve_dependencies(space, config) do
      {:ok, resolved_config} ->
        # Validate the random configuration
        case validate_constraints(space, resolved_config) do
          {:ok, validated_config} ->
            {:ok, validated_config}

          {:error, _} ->
            # If constraints fail, try again (up to a limit)
            random_configuration(space)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate multiple random configurations.

  ## Examples

      iex> space = ElixirML.Variable.Space.new()
      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> space = ElixirML.Variable.Space.add_variable(space, var)
      iex> configs = ElixirML.Variable.Space.sample_configurations(space, count: 5)
      iex> length(configs)
      5
  """
  @spec sample_configurations(t(), keyword()) :: [map()]
  def sample_configurations(%__MODULE__{} = space, opts \\ []) do
    count = Keyword.get(opts, :count, 10)
    max_attempts = Keyword.get(opts, :max_attempts, count * 3)

    generate_configurations(space, [], count, max_attempts)
  end

  @doc """
  Get the dimensionality of the variable space.
  Returns {discrete_dimensions, continuous_dimensions}
  """
  @spec dimensionality(t()) :: {non_neg_integer(), non_neg_integer()}
  def dimensionality(%__MODULE__{} = space) do
    {discrete, continuous} =
      Enum.reduce(space.variables, {0, 0}, fn {_name, variable}, {disc, cont} ->
        case variable.type do
          :float -> {disc, cont + 1}
          :integer -> {disc + 1, cont}
          :choice -> {disc + 1, cont}
          :module -> {disc + 1, cont}
          # Computed from other variables
          :composite -> {disc, cont}
        end
      end)

    {discrete, continuous}
  end

  @doc """
  Validate that a variable space is well-formed.

  Checks for:
  - Valid variable definitions
  - Resolvable dependencies
  - No circular dependencies
  - Valid constraints
  """
  @spec validate_space(t()) :: {:ok, t()} | {:error, term()}
  def validate_space(%__MODULE__{} = space) do
    with {:ok, _} <- validate_variables(space),
         {:ok, _} <- validate_dependencies(space),
         {:ok, _} <- validate_constraints(space) do
      {:ok, space}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Extract variables from a signature or schema module.
  """
  @spec from_signature(module(), keyword()) :: t()
  def from_signature(signature_module, opts \\ []) do
    space = new(opts)

    # Extract variables from the signature if it supports __variables__
    variables =
      if function_exported?(signature_module, :__variables__, 0) do
        signature_module.__variables__()
        |> Enum.map(fn {name, type, opts} ->
          create_variable_from_field(name, type, opts)
        end)
      else
        []
      end

    add_variables(space, variables)
  end

  @doc """
  Check if the variable space is valid (no circular dependencies, etc.).
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = space) do
    case check_circular_dependencies(space) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the dependency order for variables (topological sort).
  """
  @spec dependency_order(t()) :: [atom()]
  def dependency_order(%__MODULE__{} = space) do
    case topological_sort(space.dependencies) do
      {:ok, order} -> order
      {:error, _} -> []
    end
  end

  # Private helper functions

  @spec generate_id() :: String.t()
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @spec ensure_all_variables_present(t(), map()) :: {:ok, map()} | {:error, String.t()}
  defp ensure_all_variables_present(%__MODULE__{} = space, configuration) do
    missing_required = find_missing_required_variables(space, configuration)

    if Enum.empty?(missing_required) do
      complete_config = add_default_values(space, configuration)
      {:ok, complete_config}
    else
      missing_names = Enum.map(missing_required, fn {name, _} -> name end)
      {:error, "Missing required variables: #{inspect(missing_names)}"}
    end
  end

  defp find_missing_required_variables(space, configuration) do
    Enum.filter(space.variables, fn {name, variable} ->
      not Map.has_key?(configuration, name) and is_nil(variable.default)
    end)
  end

  defp add_default_values(space, configuration) do
    Enum.reduce(space.variables, configuration, fn {name, variable}, acc ->
      if Map.has_key?(acc, name) do
        acc
      else
        Map.put(acc, name, variable.default)
      end
    end)
  end

  defp validate_variable_values(%__MODULE__{} = space, configuration) do
    Enum.reduce_while(configuration, {:ok, %{}}, fn {name, value}, {:ok, acc} ->
      case validate_single_variable(space, name, value) do
        {:ok, validated_value} ->
          {:cont, {:ok, Map.put(acc, name, validated_value)}}

        {:error, reason} ->
          {:halt, {:error, "Variable #{name}: #{reason}"}}
      end
    end)
  end

  defp validate_single_variable(space, name, value) do
    case Map.get(space.variables, name) do
      nil ->
        # Unknown variable - just pass through
        {:ok, value}

      %ElixirML.Variable{type: :composite} ->
        # Skip validation for composite variables - they're computed
        {:ok, value}

      variable ->
        ElixirML.Variable.validate(variable, value)
    end
  end

  defp resolve_dependencies(%__MODULE__{} = space, configuration) do
    dependency_order = dependency_order(space)

    Enum.reduce_while(dependency_order, {:ok, configuration}, fn var_name, {:ok, acc_config} ->
      case resolve_single_dependency(space, var_name, acc_config) do
        {:ok, updated_config} ->
          {:cont, {:ok, updated_config}}

        {:error, reason} ->
          {:halt, {:error, "Failed to compute #{var_name}: #{reason}"}}
      end
    end)
  end

  defp resolve_single_dependency(space, var_name, configuration) do
    case Map.get(space.variables, var_name) do
      %ElixirML.Variable{type: :composite} = variable ->
        case compute_composite_variable(variable, configuration) do
          {:ok, computed_value} ->
            {:ok, Map.put(configuration, var_name, computed_value)}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:ok, configuration}
    end
  end

  defp compute_composite_variable(%ElixirML.Variable{type: :composite} = variable, configuration) do
    compute_fn = variable.constraints[:compute_fn]

    if compute_fn do
      try do
        result = compute_fn.(configuration)
        {:ok, result}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "No compute function defined"}
    end
  end

  defp validate_constraints(%__MODULE__{} = space, configuration) do
    Enum.reduce_while(space.constraints, {:ok, configuration}, fn constraint_fn,
                                                                  {:ok, acc_config} ->
      case constraint_fn.(acc_config) do
        {:ok, updated_config} ->
          {:cont, {:ok, updated_config}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        true ->
          {:cont, {:ok, acc_config}}

        false ->
          {:halt, {:error, "Constraint validation failed"}}
      end
    end)
  end

  defp generate_configurations(_space, configs, 0, _max_attempts) do
    configs
  end

  defp generate_configurations(_space, configs, _remaining, 0) do
    configs
  end

  defp generate_configurations(space, configs, remaining, max_attempts) do
    case random_configuration(space) do
      {:ok, config} ->
        generate_configurations(space, [config | configs], remaining - 1, max_attempts - 1)

      {:error, _} ->
        generate_configurations(space, configs, remaining, max_attempts - 1)
    end
  end

  defp create_variable_from_field(name, type, opts) do
    case type do
      :float -> ElixirML.Variable.float(name, opts)
      :integer -> ElixirML.Variable.integer(name, opts)
      :string -> ElixirML.Variable.choice(name, [], opts)
      _ -> ElixirML.Variable.choice(name, [], opts)
    end
  end

  defp check_circular_dependencies(%__MODULE__{} = space) do
    case topological_sort(space.dependencies) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp topological_sort(dependencies) do
    # Simple topological sort using Kahn's algorithm
    in_degree =
      Enum.reduce(dependencies, %{}, fn {node, deps}, acc ->
        acc = Map.put_new(acc, node, 0)

        Enum.reduce(deps, acc, fn dep, acc2 ->
          Map.update(acc2, dep, 1, &(&1 + 1))
        end)
      end)

    queue =
      Enum.filter(in_degree, fn {_node, degree} -> degree == 0 end)
      |> Enum.map(fn {node, _} -> node end)

    kahn_sort(dependencies, in_degree, queue, [])
  end

  defp kahn_sort(_dependencies, in_degree, [], result) do
    if Enum.all?(in_degree, fn {_node, degree} -> degree == 0 end) do
      {:ok, Enum.reverse(result)}
    else
      {:error, "Circular dependency detected"}
    end
  end

  defp kahn_sort(dependencies, in_degree, [node | queue], result) do
    # Remove edges from this node
    deps = Map.get(dependencies, node, [])

    updated_in_degree =
      Enum.reduce(deps, in_degree, fn dep, acc ->
        Map.update(acc, dep, 0, &(&1 - 1))
      end)

    # Add any nodes with no incoming edges to the queue
    new_queue_nodes =
      Enum.filter(updated_in_degree, fn {n, degree} ->
        degree == 0 and n not in result and n != node
      end)
      |> Enum.map(fn {n, _} -> n end)

    updated_queue = queue ++ new_queue_nodes

    kahn_sort(dependencies, updated_in_degree, updated_queue, [node | result])
  end

  # Additional validation helper functions for validate_space/1

  defp validate_variables(%__MODULE__{} = space) do
    # Check that all variables are valid
    Enum.reduce_while(space.variables, {:ok, []}, fn {name, variable}, {:ok, acc} ->
      case ElixirML.Variable.validate(variable) do
        {:ok, _} -> {:cont, {:ok, [name | acc]}}
        {:error, reason} -> {:halt, {:error, "Invalid variable #{name}: #{reason}"}}
      end
    end)
  end

  defp validate_dependencies(%__MODULE__{} = space) do
    # Check that all dependencies reference existing variables
    case check_dependency_references(space) do
      :ok -> check_circular_dependencies(space)
      {:error, _} = error -> error
    end
  end

  defp validate_constraints(%__MODULE__{} = space) do
    # Check that all constraints are valid functions
    try do
      Enum.each(space.constraints, fn constraint ->
        unless is_function(constraint, 1) do
          throw({:error, "Invalid constraint: must be a function of arity 1"})
        end
      end)

      {:ok, space}
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_dependency_references(%__MODULE__{} = space) do
    variable_names = Map.keys(space.variables) |> MapSet.new()

    Enum.reduce_while(space.dependencies, :ok, fn {var_name, deps}, _acc ->
      case MapSet.member?(variable_names, var_name) do
        false ->
          {:halt, {:error, "Unknown variable in dependencies: #{var_name}"}}

        true ->
          case Enum.find(deps, fn dep -> not MapSet.member?(variable_names, dep) end) do
            nil ->
              {:cont, :ok}

            unknown_dep ->
              {:halt, {:error, "Unknown dependency: #{unknown_dep} for variable #{var_name}"}}
          end
      end
    end)
  end
end

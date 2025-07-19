defmodule ElixirML.Variable do
  @moduledoc """
  Universal variable abstraction enabling any optimizer to tune any parameter.
  Revolutionary system for automatic module selection and parameter optimization.

  This is the key innovation that makes everything configurable - any parameter
  in the system can be declared as a Variable and optimized by any optimizer.
  """

  @type variable_type :: :float | :integer | :choice | :module | :composite

  @enforce_keys [:name, :type]
  defstruct [
    # Variable identifier (atom)
    :name,
    # Variable type
    :type,
    # Default value
    :default,
    # Type-specific constraints
    :constraints,
    # Human-readable description
    :description,
    # Variable dependencies
    :dependencies,
    # Additional metadata
    :metadata,
    # Hints for optimizers
    :optimization_hints
  ]

  @type t :: %__MODULE__{
          name: atom(),
          type: variable_type(),
          default: term(),
          constraints: map(),
          description: String.t() | nil,
          dependencies: [atom()],
          metadata: map(),
          optimization_hints: keyword()
        }

  @doc """
  Create a continuous floating-point variable.

  ## Examples

      iex> ElixirML.Variable.float(:temperature, range: {0.0, 2.0}, default: 0.7)
      %ElixirML.Variable{
        name: :temperature,
        type: :float,
        default: 0.7,
        constraints: %{range: {0.0, 2.0}, precision: 0.01, distribution: :uniform}
      }
  """
  @spec float(atom(), keyword()) :: t()
  def float(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :float,
      default: Keyword.get(opts, :default, 0.5),
      constraints: %{
        range: Keyword.get(opts, :range, {0.0, 1.0}),
        precision: Keyword.get(opts, :precision, 0.01),
        distribution: Keyword.get(opts, :distribution, :uniform)
      },
      description: Keyword.get(opts, :description),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc """
  Create an integer variable.

  ## Examples

      iex> ElixirML.Variable.integer(:max_tokens, range: {1, 4096}, default: 1000)
      %ElixirML.Variable{name: :max_tokens, type: :integer, default: 1000}
  """
  @spec integer(atom(), keyword()) :: t()
  def integer(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :integer,
      default: Keyword.get(opts, :default, 1),
      constraints: %{
        range: Keyword.get(opts, :range, {1, 100}),
        step: Keyword.get(opts, :step, 1)
      },
      description: Keyword.get(opts, :description),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc """
  Create a discrete choice variable.

  ## Examples

      iex> ElixirML.Variable.choice(:provider, [:openai, :anthropic, :groq], default: :openai)
      %ElixirML.Variable{name: :provider, type: :choice, default: :openai}
  """
  @spec choice(atom(), [term()], keyword()) :: t()
  def choice(name, choices, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :choice,
      default: Keyword.get(opts, :default, List.first(choices)),
      constraints: %{
        choices: choices,
        allow_custom: Keyword.get(opts, :allow_custom, false),
        weights: Keyword.get(opts, :weights, nil)
      },
      description: Keyword.get(opts, :description),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc """
  Create a module selection variable for automatic module selection.

  This is a revolutionary feature that enables automatic selection of
  different implementations based on optimization results.

  ## Examples

      iex> ElixirML.Variable.module(:adapter,
      ...>   modules: [ElixirML.Adapter.JSON, ElixirML.Adapter.Chat],
      ...>   behavior: ElixirML.Adapter
      ...> )
      %ElixirML.Variable{name: :adapter, type: :module}
  """
  @spec module(atom(), keyword()) :: t()
  def module(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :module,
      default: Keyword.get(opts, :default),
      constraints: %{
        modules: Keyword.get(opts, :modules, []),
        behavior: Keyword.get(opts, :behavior),
        capabilities: Keyword.get(opts, :capabilities, []),
        compatibility_matrix: Keyword.get(opts, :compatibility, %{})
      },
      description: Keyword.get(opts, :description),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc """
  Create a composite variable that depends on other variables.

  ## Examples

      iex> compute_fn = fn config ->
      ...>   %{model: "default", temperature: config.temperature}
      ...> end
      iex> ElixirML.Variable.composite(:model_config,
      ...>   dependencies: [:provider, :temperature],
      ...>   compute: compute_fn
      ...> )
      %ElixirML.Variable{name: :model_config, type: :composite}
  """
  @spec composite(atom(), keyword()) :: t()
  def composite(name, opts \\ []) do
    %__MODULE__{
      name: name,
      type: :composite,
      default: Keyword.get(opts, :default),
      constraints: %{
        compute_fn: Keyword.get(opts, :compute),
        validation_fn: Keyword.get(opts, :validate)
      },
      description: Keyword.get(opts, :description),
      dependencies: Keyword.get(opts, :dependencies, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      optimization_hints: Keyword.get(opts, :hints, [])
    }
  end

  @doc """
  Validate a variable's definition is well-formed.

  Returns `{:ok, variable}` for valid variables, `{:error, reason}` for invalid ones.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = variable) do
    # Basic validation - just check the variable is well-formed
    case variable.type do
      type when type in [:float, :integer, :choice, :module, :composite] ->
        {:ok, variable}

      _ ->
        {:error, "Invalid variable type: #{variable.type}"}
    end
  end

  @doc """
  Validate a variable configuration against its constraints.

  ## Examples

      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> ElixirML.Variable.validate(var, 0.8)
      {:ok, 0.8}

      iex> ElixirML.Variable.validate(var, 3.0)
      {:error, "Value 3.0 outside range {0.0, 2.0}"}
  """
  @spec validate(t(), term()) :: {:ok, term()} | {:error, String.t()}
  def validate(%__MODULE__{type: :float} = variable, value) do
    {min, max} = variable.constraints.range

    cond do
      not is_number(value) ->
        {:error, "Expected number, got #{inspect(value)}"}

      value < min or value > max ->
        {:error, "Value #{value} outside range #{inspect(variable.constraints.range)}"}

      true ->
        {:ok, value}
    end
  end

  def validate(%__MODULE__{type: :integer} = variable, value) do
    {min, max} = variable.constraints.range

    cond do
      not is_integer(value) ->
        {:error, "Expected integer, got #{inspect(value)}"}

      value < min or value > max ->
        {:error, "Value #{value} outside range #{inspect(variable.constraints.range)}"}

      true ->
        {:ok, value}
    end
  end

  def validate(%__MODULE__{type: :choice} = variable, value) do
    choices = variable.constraints.choices

    if value in choices do
      {:ok, value}
    else
      if variable.constraints.allow_custom do
        {:ok, value}
      else
        {:error, "Value #{inspect(value)} not in choices #{inspect(choices)}"}
      end
    end
  end

  def validate(%__MODULE__{type: :module} = variable, value) do
    modules = variable.constraints.modules

    cond do
      not is_atom(value) ->
        {:error, "Expected module atom, got #{inspect(value)}"}

      Enum.empty?(modules) ->
        # If no modules specified, just check if it's a valid module
        {:ok, value}

      value in modules ->
        {:ok, value}

      true ->
        {:error, "Module #{value} not in allowed modules #{inspect(modules)}"}
    end
  end

  def validate(%__MODULE__{type: :composite} = _variable, _value) do
    # Composite variables are computed, not directly set
    {:error, "Composite variables cannot be directly validated"}
  end

  @doc """
  Generate a random value for a variable within its constraints.
  Useful for optimization algorithms that need to sample the space.

  ## Examples

      iex> var = ElixirML.Variable.float(:temperature, range: {0.0, 2.0})
      iex> value = ElixirML.Variable.random_value(var)
      iex> value >= 0.0 and value <= 2.0
      true
  """
  @spec random_value(t()) :: term()
  def random_value(%__MODULE__{type: :float} = variable) do
    {min, max} = variable.constraints.range
    min + :rand.uniform() * (max - min)
  end

  def random_value(%__MODULE__{type: :integer} = variable) do
    {min, max} = variable.constraints.range
    min + :rand.uniform(max - min + 1) - 1
  end

  def random_value(%__MODULE__{type: :choice} = variable) do
    choices = variable.constraints.choices
    Enum.random(choices)
  end

  def random_value(%__MODULE__{type: :module} = variable) do
    modules = variable.constraints.modules

    if Enum.empty?(modules) do
      variable.default
    else
      Enum.random(modules)
    end
  end

  def random_value(%__MODULE__{type: :composite}) do
    # Composite variables depend on other variables
    nil
  end

  @doc """
  Check if two variables are compatible (can coexist in the same configuration).

  ## Examples

      iex> var1 = ElixirML.Variable.choice(:provider, [:openai])
      iex> var2 = ElixirML.Variable.choice(:model, [:gpt4])
      iex> ElixirML.Variable.compatible?(var1, var2)
      true
  """
  @spec compatible?(t(), t()) :: boolean()
  def compatible?(%__MODULE__{} = var1, %__MODULE__{} = var2) do
    # Check compatibility matrix if present
    compatibility_matrix = var1.constraints[:compatibility_matrix] || %{}

    case Map.get(compatibility_matrix, var2.name) do
      # No constraints means compatible
      nil -> true
      constraints -> check_compatibility_constraints(var2, constraints)
    end
  end

  @doc """
  Get optimization hints for a variable.
  These hints help optimizers understand how to best optimize this variable.
  """
  @spec optimization_hints(t()) :: keyword()
  def optimization_hints(%__MODULE__{} = variable) do
    base_hints =
      case variable.type do
        :float -> [continuous: true, differentiable: true]
        :integer -> [discrete: true, ordered: true]
        :choice -> [discrete: true, categorical: true]
        :module -> [discrete: true, categorical: true, high_impact: true]
        :composite -> [computed: true, dependent: true]
      end

    Keyword.merge(base_hints, variable.optimization_hints)
  end

  # Private helper functions

  @spec check_compatibility_constraints(t(), term()) :: boolean()
  defp check_compatibility_constraints(_variable, _constraints) do
    # Check basic compatibility constraints
    # In a full implementation, this would check various constraint types:
    # - Value ranges that must align
    # - Exclusive choices that cannot coexist
    # - Dependencies that must be satisfied
    true
  end
end

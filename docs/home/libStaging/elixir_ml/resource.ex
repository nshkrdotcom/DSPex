defmodule ElixirML.Resource do
  @moduledoc """
  Ash-inspired resource framework for ElixirML.

  Treats programs, optimizations, and configurations as first-class resources
  with relationships, validations, and lifecycle hooks.

  ## Usage

      defmodule MyApp.Program do
        use ElixirML.Resource

        attributes do
          attribute :name, :string, allow_nil?: false
          attribute :type, :atom, constraints: [one_of: [:predict, :chain_of_thought]]
          schema_attribute :config, MyApp.ProgramConfig
        end

        relationships do
          belongs_to :variable_space, ElixirML.Resources.VariableSpace
          has_many :optimization_runs, ElixirML.Resources.OptimizationRun
        end

        actions do
          action :execute do
            argument :inputs, :map, allow_nil?: false
            run MyApp.Actions.ExecuteProgram
          end
        end
      end
  """

  @doc """
  Defines a resource with attributes, relationships, actions, and calculations.
  """
  defmacro __using__(_opts \\ []) do
    quote do
      # Import DSL macros
      import ElixirML.Resource.DSL

      # Track resource metadata
      Module.register_attribute(__MODULE__, :attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :relationships, accumulate: true)
      Module.register_attribute(__MODULE__, :actions, accumulate: true)
      Module.register_attribute(__MODULE__, :calculations, accumulate: true)
      Module.register_attribute(__MODULE__, :validations, accumulate: true)
      Module.register_attribute(__MODULE__, :schema_attributes, accumulate: true)

      # Import ElixirML Schema integration
      alias ElixirML.Schema

      @before_compile ElixirML.Resource.Compiler

      # Resource behaviour
      @behaviour ElixirML.Resource.Behaviour
    end
  end

  @doc """
  Creates a new instance of a resource.
  """
  @callback create(attributes :: map()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Retrieves a resource by ID.
  """
  @callback get(id :: term()) :: {:ok, struct()} | {:error, :not_found}

  @doc """
  Updates a resource with new attributes.
  """
  @callback update(resource :: struct(), attributes :: map()) ::
              {:ok, struct()} | {:error, term()}

  @doc """
  Deletes a resource.
  """
  @callback delete(resource :: struct()) :: :ok | {:error, term()}

  @doc """
  Validates a resource's attributes.
  """
  @callback validate(resource :: struct()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Executes a named action on the resource.
  """
  @callback execute_action(resource :: struct(), action_name :: atom(), arguments :: map()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Calculates a named calculation for the resource.
  """
  @callback calculate(resource :: struct(), calculation_name :: atom(), arguments :: map()) ::
              {:ok, term()} | {:error, term()}
end

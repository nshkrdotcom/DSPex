defmodule DSPex.Variables do
  @moduledoc """
  High-level API for working with variables in a DSPex context.

  This module provides the primary interface for variable operations,
  abstracting away the underlying backend complexity.

  ## Quick Start

      {:ok, ctx} = DSPex.Context.start_link()
      
      # Define variables with types and constraints
      defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Get and set values
      temp = get(ctx, :temperature)
      set(ctx, :temperature, 0.9)
      
      # Functional updates
      update(ctx, :temperature, &min(&1 * 1.1, 2.0))
      
      # Batch operations
      values = get_many(ctx, [:temperature, :max_tokens])
      update_many(ctx, %{temperature: 0.8, max_tokens: 512})

  ## Variable Types

  Supported types (from Stage 1):
  - `:float` - Floating point numbers
  - `:integer` - Whole numbers
  - `:string` - Text values
  - `:boolean` - True/false values

  Future types (Stage 3+):
  - `:choice` - Enumerated values
  - `:module` - DSPy module references
  - `:embedding` - Vector embeddings
  - `:tensor` - Multi-dimensional arrays

  ## Error Handling

  Most functions return values directly for convenience.
  Use the bang (!) variants if you need explicit error handling:

      # Returns nil on error
      value = get(ctx, :missing)  # nil
      
      # Raises on error  
      value = get!(ctx, :missing)  # raises VariableNotFoundError
  """

  alias DSPex.Context
  require Logger

  @type context :: Context.t()
  @type var_identifier :: atom() | String.t()
  @type variable_type :: :float | :integer | :string | :boolean | :choice | :module
  @type constraints :: map()

  defmodule VariableNotFoundError do
    @moduledoc "Raised when a variable doesn't exist."
    defexception [:message, :identifier]

    def exception(identifier) do
      %__MODULE__{
        message: "Variable not found: #{inspect(identifier)}",
        identifier: identifier
      }
    end
  end

  defmodule ValidationError do
    @moduledoc "Raised when a value fails validation."
    defexception [:message, :identifier, :value, :reason]

    def exception(opts) do
      %__MODULE__{
        message: "Validation failed for #{inspect(opts[:identifier])}: #{opts[:reason]}",
        identifier: opts[:identifier],
        value: opts[:value],
        reason: opts[:reason]
      }
    end
  end

  ## Core API

  @doc """
  Defines a new variable in the context.

  This is the primary way to create variables with full type information
  and constraints.

  ## Parameters

    * `context` - The DSPex context
    * `name` - Variable name (atom or string)
    * `type` - Variable type
    * `initial_value` - Initial value
    * `opts` - Options:
      * `:constraints` - Type-specific constraints
      * `:description` - Human-readable description
      * `:metadata` - Additional metadata

  ## Examples

      # Simple variable
      defvariable(ctx, :temperature, :float, 0.7)
      
      # With constraints
      defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "LLM generation temperature"
      )
      
      # String with pattern
      defvariable(ctx, :model_name, :string, "gpt-4",
        constraints: %{
          pattern: "^(gpt-4|gpt-3.5-turbo|claude-3)$"
        }
      )
      
      # Integer with range
      defvariable(ctx, :max_tokens, :integer, 256,
        constraints: %{min: 1, max: 4096}
      )

  ## Returns

    * `{:ok, var_id}` - Successfully created with ID
    * `{:error, reason}` - Creation failed
  """
  @spec defvariable(context, atom(), variable_type(), any(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def defvariable(context, name, type, initial_value, opts \\ []) do
    Context.register_variable(context, name, type, initial_value, opts)
  end

  @doc """
  Defines a variable, raising on error.

  Same as `defvariable/5` but raises on failure.
  """
  @spec defvariable!(context, atom(), variable_type(), any(), keyword()) :: String.t()
  def defvariable!(context, name, type, initial_value, opts \\ []) do
    case defvariable(context, name, type, initial_value, opts) do
      {:ok, var_id} ->
        var_id

      {:error, reason} ->
        raise ArgumentError, "Failed to define variable #{name}: #{inspect(reason)}"
    end
  end

  @doc """
  Gets a variable value.

  ## Parameters

    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `default` - Value to return if not found (default: nil)

  ## Examples

      temperature = get(ctx, :temperature)
      
      # With default
      tokens = get(ctx, :max_tokens, 256)
      
      # Using ID
      value = get(ctx, "var_temperature_12345")

  ## Returns

  The variable value or the default if not found.
  """
  @spec get(context, var_identifier, any()) :: any()
  def get(context, identifier, default \\ nil) do
    case Context.get_variable(context, identifier) do
      {:ok, value} ->
        value

      {:error, :not_found} ->
        default

      {:error, reason} ->
        Logger.warning("Failed to get variable #{identifier}: #{inspect(reason)}")
        default
    end
  end

  @doc """
  Gets a variable value, raising if not found.

  Same as `get/3` but raises `VariableNotFoundError` if the variable doesn't exist.
  """
  @spec get!(context, var_identifier) :: any()
  def get!(context, identifier) do
    case Context.get_variable(context, identifier) do
      {:ok, value} -> value
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to get variable: #{inspect(reason)}"
    end
  end

  @doc """
  Sets a variable value.

  ## Parameters

    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `value` - New value (will be validated)
    * `opts` - Options:
      * `:metadata` - Metadata for this update

  ## Examples

      set(ctx, :temperature, 0.9)
      
      # With metadata
      set(ctx, :temperature, 0.9,
        metadata: %{"reason" => "user_adjustment"}
      )

  ## Returns

    * `:ok` - Successfully updated
    * `{:error, reason}` - Update failed
  """
  @spec set(context, var_identifier, any(), keyword()) :: :ok | {:error, term()}
  def set(context, identifier, value, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.set_variable(context, identifier, value, metadata)
  end

  @doc """
  Sets a variable value, raising on error.

  Same as `set/4` but raises on failure.
  """
  @spec set!(context, var_identifier, any(), keyword()) :: :ok
  def set!(context, identifier, value, opts \\ []) do
    case set(context, identifier, value, opts) do
      :ok ->
        :ok

      {:error, :not_found} ->
        raise VariableNotFoundError, identifier

      {:error, reason} ->
        raise ValidationError, identifier: identifier, value: value, reason: reason
    end
  end

  @doc """
  Updates a variable using a function.

  The function receives the current value and should return the new value.

  ## Parameters

    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `update_fn` - Function that takes current value and returns new value
    * `opts` - Options passed to `set/4`

  ## Examples

      # Increment
      update(ctx, :counter, &(&1 + 1))
      
      # Complex update
      update(ctx, :temperature, fn temp ->
        min(temp * 1.1, 2.0)
      end)
      
      # With metadata
      update(ctx, :counter, &(&1 + 1),
        metadata: %{"operation" => "increment"}
      )

  ## Returns

    * `:ok` - Successfully updated
    * `{:error, reason}` - Update failed
  """
  @spec update(context, var_identifier, (any() -> any()), keyword()) :: :ok | {:error, term()}
  def update(context, identifier, update_fn, opts \\ []) when is_function(update_fn, 1) do
    case Context.get_variable(context, identifier) do
      {:ok, current_value} ->
        new_value = update_fn.(current_value)
        set(context, identifier, new_value, opts)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a variable using a function, raising on error.
  """
  @spec update!(context, var_identifier, (any() -> any()), keyword()) :: :ok
  def update!(context, identifier, update_fn, opts \\ []) do
    case update(context, identifier, update_fn, opts) do
      :ok -> :ok
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to update variable: #{inspect(reason)}"
    end
  end

  @doc """
  Gets multiple variables at once.

  Efficient batch retrieval of multiple variables.

  ## Parameters

    * `context` - The DSPex context
    * `identifiers` - List of variable names or IDs

  ## Examples

      values = get_many(ctx, [:temperature, :max_tokens, :model])
      # %{temperature: 0.7, max_tokens: 256, model: "gpt-4"}
      
      # Missing variables are omitted
      values = get_many(ctx, [:exists, :missing])
      # %{exists: "value"}

  ## Returns

  Map of identifier => value for found variables.
  """
  @spec get_many(context, [var_identifier]) :: map()
  def get_many(context, identifiers) do
    case Context.get_variables(context, identifiers) do
      {:ok, %{found: found, missing: _missing}} ->
        # Extract values from SessionStore Variable structs and convert keys
        Map.new(found, fn {k, var} ->
          key =
            if is_binary(k) and identifier_in_list?(k, identifiers),
              do: safe_to_atom(k, identifiers),
              else: k

          {key, var.value}
        end)

      {:error, reason} ->
        Logger.warning("Failed to get variables: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Updates multiple variables at once.

  Efficient batch update of multiple variables.

  ## Parameters

    * `context` - The DSPex context  
    * `updates` - Map of identifier => new value
    * `opts` - Options:
      * `:metadata` - Metadata for all updates
      * `:atomic` - If true, all updates must succeed (default: false)

  ## Examples

      update_many(ctx, %{
        temperature: 0.8,
        max_tokens: 512,
        model: "gpt-4"
      })
      
      # Atomic update
      update_many(ctx, updates, atomic: true)

  ## Returns

    * `:ok` - All updates succeeded
    * `{:error, {:partial_failure, errors}}` - Some updates failed (non-atomic)
    * `{:error, reason}` - Update failed (atomic)
  """
  @spec update_many(context, map(), keyword()) :: :ok | {:error, term()}
  def update_many(context, updates, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.update_variables(context, updates, metadata)
  end

  @doc """
  Updates multiple variables, raising on error.
  """
  @spec update_many!(context, map(), keyword()) :: :ok
  def update_many!(context, updates, opts \\ []) do
    case update_many(context, updates, opts) do
      :ok ->
        :ok

      {:error, {:partial_failure, errors}} ->
        raise "Failed to update variables: #{inspect(errors)}"

      {:error, reason} ->
        raise "Failed to update variables: #{inspect(reason)}"
    end
  end

  @doc """
  Lists all variables in the context.

  ## Parameters

    * `context` - The DSPex context

  ## Returns

  List of variable information maps containing:
    * `:id` - Variable ID
    * `:name` - Variable name
    * `:type` - Variable type
    * `:value` - Current value
    * `:constraints` - Type constraints
    * `:metadata` - Variable metadata
    * `:version` - Version number

  ## Examples

      variables = list(ctx)
      # [
      #   %{name: :temperature, type: :float, value: 0.7, ...},
      #   %{name: :max_tokens, type: :integer, value: 256, ...}
      # ]
  """
  @spec list(context) :: [map()]
  def list(context) do
    case Context.list_variables(context) do
      {:ok, variables} ->
        variables

      {:error, reason} ->
        Logger.error("Failed to list variables: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Checks if a variable exists.

  ## Parameters

    * `context` - The DSPex context
    * `identifier` - Variable name or ID

  ## Examples

      if exists?(ctx, :temperature) do
        # Variable exists
      end
  """
  @spec exists?(context, var_identifier) :: boolean()
  def exists?(context, identifier) do
    case Context.get_variable(context, identifier) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Deletes a variable.

  ## Parameters

    * `context` - The DSPex context
    * `identifier` - Variable name or ID

  ## Returns

    * `:ok` - Successfully deleted
    * `{:error, reason}` - Deletion failed
  """
  @spec delete(context, var_identifier) :: :ok | {:error, term()}
  def delete(context, identifier) do
    Context.delete_variable(context, identifier)
  end

  @doc """
  Deletes a variable, raising on error.
  """
  @spec delete!(context, var_identifier) :: :ok
  def delete!(context, identifier) do
    case delete(context, identifier) do
      :ok -> :ok
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to delete variable: #{inspect(reason)}"
    end
  end

  ## Convenience Functions

  @doc """
  Gets a variable's metadata.

  ## Examples

      meta = get_metadata(ctx, :temperature)
      # %{"description" => "LLM generation temperature", ...}
  """
  @spec get_metadata(context, var_identifier) :: map() | nil
  def get_metadata(context, identifier) do
    case list(context) do
      [] ->
        nil

      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.metadata
        end
    end
  end

  @doc """
  Gets a variable's type.

  ## Examples

      type = get_type(ctx, :temperature)
      # :float
  """
  @spec get_type(context, var_identifier) :: atom() | nil
  def get_type(context, identifier) do
    case list(context) do
      [] ->
        nil

      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.type
        end
    end
  end

  @doc """
  Gets a variable's constraints.

  ## Examples

      constraints = get_constraints(ctx, :temperature)
      # %{min: 0.0, max: 2.0}
  """
  @spec get_constraints(context, var_identifier) :: map() | nil
  def get_constraints(context, identifier) do
    case list(context) do
      [] ->
        nil

      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.constraints
        end
    end
  end

  ## Private Helpers

  defp identifier_in_list?(string_id, identifiers) do
    Enum.any?(identifiers, fn id ->
      to_string(id) == string_id
    end)
  end

  defp safe_to_atom(string, identifiers) do
    # Find the original atom from the identifier list
    Enum.find(identifiers, fn id ->
      to_string(id) == string
    end) || string
  end

  defp match_identifier?(variable, identifier) do
    variable.id == to_string(identifier) or
      to_string(variable.name) == to_string(identifier)
  end
end

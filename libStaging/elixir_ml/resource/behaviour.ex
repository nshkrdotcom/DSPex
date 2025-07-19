defmodule ElixirML.Resource.Behaviour do
  @moduledoc """
  Behaviour defining the interface for ElixirML resources.

  All resources must implement these callbacks to provide
  consistent CRUD operations and validation.
  """

  @doc """
  Creates a new resource instance with the given attributes.

  ## Parameters
  - `attributes`: Map of attribute names to values

  ## Returns
  - `{:ok, resource}` on success
  - `{:error, reason}` on failure
  """
  @callback create(attributes :: map()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Retrieves a resource by its unique identifier.

  ## Parameters
  - `id`: The unique identifier for the resource

  ## Returns
  - `{:ok, resource}` if found
  - `{:error, :not_found}` if not found
  """
  @callback get(id :: term()) :: {:ok, struct()} | {:error, :not_found}

  @doc """
  Updates an existing resource with new attributes.

  ## Parameters
  - `resource`: The existing resource struct
  - `attributes`: Map of attributes to update

  ## Returns
  - `{:ok, updated_resource}` on success
  - `{:error, reason}` on validation or other errors
  """
  @callback update(resource :: struct(), attributes :: map()) ::
              {:ok, struct()} | {:error, term()}

  @doc """
  Deletes a resource from the system.

  ## Parameters
  - `resource`: The resource to delete

  ## Returns
  - `:ok` on successful deletion
  - `{:error, reason}` on failure
  """
  @callback delete(resource :: struct()) :: :ok | {:error, term()}

  @doc """
  Validates a resource's current state and attributes.

  ## Parameters
  - `resource`: The resource to validate

  ## Returns
  - `{:ok, resource}` if valid
  - `{:error, validation_errors}` if invalid
  """
  @callback validate(resource :: struct()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Executes a named action on the resource.

  ## Parameters
  - `resource`: The resource to execute the action on
  - `action_name`: The name of the action to execute
  - `arguments`: Arguments for the action

  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @callback execute_action(resource :: struct(), action_name :: atom(), arguments :: map()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Calculates a named calculation for the resource.

  ## Parameters
  - `resource`: The resource to calculate for
  - `calculation_name`: The name of the calculation
  - `arguments`: Arguments for the calculation

  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @callback calculate(resource :: struct(), calculation_name :: atom(), arguments :: map()) ::
              {:ok, term()} | {:error, term()}
end

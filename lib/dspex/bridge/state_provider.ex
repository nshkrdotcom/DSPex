defmodule DSPex.Bridge.StateProvider do
  @moduledoc """
  Behaviour for session state backends.

  This abstraction allows DSPex to use different storage strategies:
  - LocalState: In-process Agent for pure Elixir workflows (microsecond latency)
  - BridgedState: SessionStore + gRPC for Python integration (millisecond latency)

  Future backends could include distributed state, persistent state, etc.

  ## Implementation Requirements

  All callbacks must return tagged tuples: `{:ok, result}` or `{:error, reason}`.
  State is opaque to callers - each backend defines its own structure.

  ## Example Implementation

      defmodule MyBackend do
        @behaviour DSPex.Bridge.StateProvider
        
        defstruct [:storage, :session_id]
        
        @impl true
        def init(opts) do
          session_id = Keyword.fetch!(opts, :session_id)
          {:ok, %__MODULE__{storage: %{}, session_id: session_id}}
        end
        
        # ... implement other callbacks
      end
  """

  @type state :: any()
  @type var_id :: String.t()
  @type var_identifier :: atom() | String.t()
  @type variable_type :: atom()
  @type error :: {:error, term()}
  @type metadata :: map()

  # Core lifecycle callbacks

  @doc """
  Initialize the state backend.

  Options are backend-specific but should include at least:
  - `:session_id` - Unique session identifier

  Returns `{:ok, state}` or `{:error, reason}`.
  """
  @callback init(opts :: keyword()) :: {:ok, state} | error

  @doc """
  Clean up any resources held by the backend.

  This is called when the context is shutting down.
  Should release any external resources (connections, processes, etc).
  """
  @callback cleanup(state) :: :ok

  # Variable operations

  @doc """
  Register a new variable.

  Options may include:
  - `:constraints` - Type-specific constraints
  - `:metadata` - Additional metadata
  - `:description` - Human-readable description

  Returns `{:ok, {var_id, new_state}}` where var_id is the unique identifier.
  """
  @callback register_variable(
              state,
              name :: var_identifier,
              type :: variable_type,
              initial_value :: any(),
              opts :: keyword()
            ) :: {:ok, {var_id, state}} | error

  @doc """
  Get a variable value by name or ID.

  Should support both variable names (atoms/strings) and variable IDs.
  Returns `{:ok, value}` or `{:error, :not_found}`.
  """
  @callback get_variable(state, var_identifier) :: {:ok, value :: any()} | error

  @doc """
  Update a variable value.

  The metadata map is merged with existing metadata.
  Should validate the new value against type and constraints.

  Returns `{:ok, new_state}` or an error.
  """
  @callback set_variable(
              state,
              var_identifier,
              new_value :: any(),
              metadata
            ) :: {:ok, state} | error

  @doc """
  Delete a variable.

  Returns `{:ok, new_state}` or `{:error, :not_found}`.
  """
  @callback delete_variable(state, var_identifier) :: {:ok, state} | error

  @doc """
  List all variables.

  Returns a list of variable information maps containing at least:
  - `:id` - Variable ID
  - `:name` - Variable name
  - `:type` - Variable type
  - `:value` - Current value

  Additional fields like constraints and metadata are optional.
  """
  @callback list_variables(state) :: {:ok, list(map())} | error

  # Batch operations

  @doc """
  Get multiple variables at once.

  Returns a map of identifier => value for found variables.
  Missing variables are simply omitted from the result.

  More efficient than multiple get_variable calls for remote backends.
  """
  @callback get_variables(state, identifiers :: list(var_identifier)) ::
              {:ok, %{var_identifier => any()}} | error

  @doc """
  Update multiple variables atomically (if supported).

  The updates map has identifier => new_value pairs.
  Metadata applies to all updates.

  If the backend doesn't support atomic updates, it should update
  as many as possible and return `{:error, {:partial_failure, errors}}`
  where errors is a map of identifier => error_reason.

  Returns `{:ok, new_state}` if all updates succeed.
  """
  @callback update_variables(state, updates :: map(), metadata) ::
              {:ok, state} | error

  # State migration

  @doc """
  Export all state for migration.

  Returns a map containing at least:
  - `:session_id` - Session identifier
  - `:variables` - Map of var_id => variable data
  - `:variable_index` - Map of name => var_id

  The exported format should be backend-agnostic to enable migration
  between different backend types.
  """
  @callback export_state(state) :: {:ok, map()} | error

  @doc """
  Import state from an export.

  Used when migrating from another backend. Should merge with existing
  state rather than replacing it entirely.

  Returns `{:ok, new_state}` with the imported variables.
  """
  @callback import_state(state, exported :: map()) :: {:ok, state} | error

  # Capabilities

  @doc """
  Returns backend capabilities.

  Used by the Context to make decisions about operations.
  Should return a map with at least:
  - `:atomic_updates` - Whether update_variables is truly atomic
  - `:streaming` - Whether the backend supports watch operations
  - `:persistent` - Whether state survives process restarts
  - `:distributed` - Whether state is accessible from other nodes

  Additional backend-specific capabilities can be included.
  """
  @callback capabilities() :: map()

  @doc """
  Check if this backend requires the Python bridge.

  Used to determine when to initialize gRPC connections.
  LocalState returns false, BridgedState returns true.
  """
  @callback requires_bridge?() :: boolean()

  # Optional callbacks for streaming (Stage 3)

  @doc """
  Watch variables for changes (optional).

  If the backend supports streaming, this enables reactive updates.
  The watcher_fn will be called with (identifier, old_value, new_value, metadata).

  Options may include:
  - `:include_initial` - Send current values immediately
  - `:filter` - Function (old, new) -> boolean to filter updates
  - `:watcher_pid` - Process to monitor for cleanup

  Returns `{:ok, {ref, new_state}}` where ref can be used to stop watching.
  """
  @callback watch_variables(
              state,
              identifiers :: list(var_identifier),
              watcher_fn :: function(),
              opts :: keyword()
            ) :: {:ok, {reference(), state}} | error

  @doc """
  Stop watching variables (optional).

  Returns `{:ok, new_state}` after removing the watcher.
  """
  @callback unwatch_variables(state, reference()) :: {:ok, state} | error

  @optional_callbacks [watch_variables: 4, unwatch_variables: 2]

  # Validation helper

  @doc """
  Validates that a module implements all required callbacks.

  Useful for testing and compile-time checks.
  """
  def validate_provider!(module) when is_atom(module) do
    # Ensure module is loaded
    case Code.ensure_loaded(module) do
      {:module, _} -> :ok
      {:error, reason} -> raise "Failed to load module #{module}: #{inspect(reason)}"
    end

    required_callbacks = [
      init: 1,
      cleanup: 1,
      register_variable: 5,
      get_variable: 2,
      set_variable: 4,
      delete_variable: 2,
      list_variables: 1,
      get_variables: 2,
      update_variables: 3,
      export_state: 1,
      import_state: 2,
      capabilities: 0,
      requires_bridge?: 0
    ]

    Enum.each(required_callbacks, fn {fun, arity} ->
      unless function_exported?(module, fun, arity) do
        raise "#{module} does not implement required callback #{fun}/#{arity}"
      end
    end)

    :ok
  end
end

defmodule DSPex.PythonBridge.Session do
  @moduledoc """
  Session data structure for centralized session management.

  This struct represents a session in the centralized session store,
  containing all session-related data including programs, metadata,
  and lifecycle information.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          programs: map(),
          metadata: map(),
          created_at: integer(),
          last_accessed: integer(),
          ttl: integer()
        }

  @enforce_keys [:id, :created_at, :ttl]
  defstruct [
    :id,
    :created_at,
    :last_accessed,
    :ttl,
    programs: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new session with the given ID and options.

  ## Parameters

  - `id` - Unique session identifier
  - `opts` - Keyword list of options:
    - `:ttl` - Time-to-live in seconds (default: 3600)
    - `:metadata` - Initial metadata map (default: %{})
    - `:programs` - Initial programs map (default: %{})

  ## Examples

      iex> Session.new("session_123")
      %Session{id: "session_123", programs: %{}, metadata: %{}, ...}
      
      iex> Session.new("session_456", ttl: 7200, metadata: %{user_id: "user_1"})
      %Session{id: "session_456", ttl: 7200, metadata: %{user_id: "user_1"}, ...}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id) do
    now = System.monotonic_time(:second)

    %__MODULE__{
      id: id,
      programs: Keyword.get(opts, :programs, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: now,
      last_accessed: now,
      ttl: Keyword.get(opts, :ttl, 3600)
    }
  end

  @doc """
  Updates the last_accessed timestamp to the current time.

  ## Parameters

  - `session` - The session to touch

  ## Returns

  Updated session with current last_accessed timestamp.
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = session) do
    %{session | last_accessed: System.monotonic_time(:second)}
  end

  @doc """
  Checks if a session has expired based on its TTL.

  ## Parameters

  - `session` - The session to check
  - `current_time` - Optional current time (defaults to current monotonic time)

  ## Returns

  `true` if the session has expired, `false` otherwise.
  """
  @spec expired?(t(), integer() | nil) :: boolean()
  def expired?(%__MODULE__{} = session, current_time \\ nil) do
    current_time = current_time || System.monotonic_time(:second)
    session.last_accessed + session.ttl < current_time
  end

  @doc """
  Validates that a session struct has all required fields and valid data.

  ## Parameters

  - `session` - The session to validate

  ## Returns

  `:ok` if valid, `{:error, reason}` if invalid.
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = session) do
    cond do
      not is_binary(session.id) or session.id == "" ->
        {:error, :invalid_id}

      not is_map(session.programs) ->
        {:error, :invalid_programs}

      not is_map(session.metadata) ->
        {:error, :invalid_metadata}

      not is_integer(session.created_at) ->
        {:error, :invalid_created_at}

      not is_integer(session.last_accessed) ->
        {:error, :invalid_last_accessed}

      not is_integer(session.ttl) or session.ttl <= 0 ->
        {:error, :invalid_ttl}

      session.last_accessed < session.created_at ->
        {:error, :invalid_timestamps}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :not_a_session}

  @doc """
  Adds or updates a program in the session.

  ## Parameters

  - `session` - The session to update
  - `program_id` - The program identifier
  - `program_data` - The program data to store

  ## Returns

  Updated session with the program added/updated.
  """
  @spec put_program(t(), String.t(), term()) :: t()
  def put_program(%__MODULE__{} = session, program_id, program_data)
      when is_binary(program_id) do
    programs = Map.put(session.programs, program_id, program_data)
    %{session | programs: programs}
  end

  @doc """
  Gets a program from the session.

  ## Parameters

  - `session` - The session to query
  - `program_id` - The program identifier

  ## Returns

  `{:ok, program_data}` if found, `{:error, :not_found}` if not found.
  """
  @spec get_program(t(), String.t()) :: {:ok, term()} | {:error, :not_found}
  def get_program(%__MODULE__{} = session, program_id) when is_binary(program_id) do
    case Map.get(session.programs, program_id) do
      nil -> {:error, :not_found}
      program_data -> {:ok, program_data}
    end
  end

  @doc """
  Removes a program from the session.

  ## Parameters

  - `session` - The session to update
  - `program_id` - The program identifier to remove

  ## Returns

  Updated session with the program removed.
  """
  @spec delete_program(t(), String.t()) :: t()
  def delete_program(%__MODULE__{} = session, program_id) when is_binary(program_id) do
    programs = Map.delete(session.programs, program_id)
    %{session | programs: programs}
  end

  @doc """
  Updates session metadata.

  ## Parameters

  - `session` - The session to update
  - `key` - The metadata key
  - `value` - The metadata value

  ## Returns

  Updated session with the metadata updated.
  """
  @spec put_metadata(t(), term(), term()) :: t()
  def put_metadata(%__MODULE__{} = session, key, value) do
    metadata = Map.put(session.metadata, key, value)
    %{session | metadata: metadata}
  end

  @doc """
  Gets metadata from the session.

  ## Parameters

  - `session` - The session to query
  - `key` - The metadata key
  - `default` - Default value if key not found

  ## Returns

  The metadata value or the default.
  """
  @spec get_metadata(t(), term(), term()) :: term()
  def get_metadata(%__MODULE__{} = session, key, default \\ nil) do
    Map.get(session.metadata, key, default)
  end
end

defmodule DSPex.PythonBridge.SessionState do
  @moduledoc """
  Session state management for the Python bridge pool.

  This module provides a structured way to manage session state across
  pool workers, including:

  - Session metadata (ID, user, creation time)
  - Program registry per session
  - Configuration and preferences
  - Usage statistics and metrics

  ## Session Lifecycle

  1. **Creation**: Session created when first operation requested
  2. **Active**: Session actively used for operations
  3. **Idle**: No operations for some time
  4. **Cleanup**: Session resources freed

  ## Data Structure

  Sessions are stored as a map with the following structure:

  ```elixir
  %{
    session_id: "unique_session_id",
    user_id: "optional_user_id",
    created_at: DateTime.t(),
    last_activity: DateTime.t(),
    programs: %{program_id => program_info},
    config: %{key => value},
    stats: %{
      operations_count: integer(),
      errors_count: integer(),
      last_error: any()
    },
    metadata: %{key => value}
  }
  ```
  """

  require Logger

  @type session_id :: String.t()
  @type program_id :: String.t()
  @type user_id :: String.t() | nil

  @type session :: %{
          session_id: session_id(),
          user_id: user_id(),
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          programs: %{program_id() => program_info()},
          config: map(),
          stats: session_stats(),
          metadata: map()
        }

  @type program_info :: %{
          program_id: program_id(),
          signature: map(),
          created_at: DateTime.t(),
          last_executed: DateTime.t() | nil,
          execution_count: non_neg_integer()
        }

  @type session_stats :: %{
          operations_count: non_neg_integer(),
          errors_count: non_neg_integer(),
          last_error: any(),
          total_execution_time_ms: non_neg_integer()
        }

  @doc """
  Creates a new session with default values.

  ## Options

  - `:user_id` - Optional user identifier
  - `:config` - Initial configuration map
  - `:metadata` - Additional metadata

  ## Examples

      iex> SessionState.new("session_123", user_id: "user_456")
      %{
        session_id: "session_123",
        user_id: "user_456",
        created_at: ~U[...],
        ...
      }
  """
  @spec new(session_id(), keyword()) :: session()
  def new(session_id, opts \\ []) do
    %{
      session_id: session_id,
      user_id: Keyword.get(opts, :user_id),
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      programs: %{},
      config: Keyword.get(opts, :config, %{}),
      stats: init_stats(),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Updates the last activity timestamp for a session.
  """
  @spec touch(session()) :: session()
  def touch(session) do
    %{session | last_activity: DateTime.utc_now()}
  end

  @doc """
  Adds a program to the session.
  """
  @spec add_program(session(), program_id(), map()) :: session()
  def add_program(session, program_id, signature) do
    program_info = %{
      program_id: program_id,
      signature: signature,
      created_at: DateTime.utc_now(),
      last_executed: nil,
      execution_count: 0
    }

    programs = Map.put(session.programs, program_id, program_info)

    session
    |> Map.put(:programs, programs)
    |> touch()
  end

  @doc """
  Records a program execution in the session.
  """
  @spec record_execution(session(), program_id(), integer()) :: session()
  def record_execution(session, program_id, execution_time_ms) do
    case Map.get(session.programs, program_id) do
      nil ->
        Logger.warning("Recording execution for unknown program: #{program_id}")
        session

      program_info ->
        updated_program = %{
          program_info
          | last_executed: DateTime.utc_now(),
            execution_count: program_info.execution_count + 1
        }

        programs = Map.put(session.programs, program_id, updated_program)

        stats =
          session.stats
          |> Map.update(:operations_count, 1, &(&1 + 1))
          |> Map.update(:total_execution_time_ms, execution_time_ms, &(&1 + execution_time_ms))

        session
        |> Map.put(:programs, programs)
        |> Map.put(:stats, stats)
        |> touch()
    end
  end

  @doc """
  Records an error in the session.
  """
  @spec record_error(session(), any()) :: session()
  def record_error(session, error) do
    stats =
      session.stats
      |> Map.update(:errors_count, 1, &(&1 + 1))
      |> Map.put(:last_error, error)

    session
    |> Map.put(:stats, stats)
    |> touch()
  end

  @doc """
  Removes a program from the session.
  """
  @spec remove_program(session(), program_id()) :: session()
  def remove_program(session, program_id) do
    programs = Map.delete(session.programs, program_id)

    session
    |> Map.put(:programs, programs)
    |> touch()
  end

  @doc """
  Updates session configuration.
  """
  @spec update_config(session(), map()) :: session()
  def update_config(session, config_updates) do
    config = Map.merge(session.config, config_updates)

    session
    |> Map.put(:config, config)
    |> touch()
  end

  @doc """
  Checks if a session is considered stale.

  A session is stale if it hasn't been active for the specified timeout.
  """
  @spec stale?(session(), integer()) :: boolean()
  def stale?(session, timeout_ms) do
    last_activity_ms = DateTime.to_unix(session.last_activity, :millisecond)
    now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    now_ms - last_activity_ms > timeout_ms
  end

  @doc """
  Gets session age in milliseconds.
  """
  @spec age_ms(session()) :: integer()
  def age_ms(session) do
    created_ms = DateTime.to_unix(session.created_at, :millisecond)
    now_ms = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    now_ms - created_ms
  end

  @doc """
  Converts session to a summary map for external consumption.
  """
  @spec to_summary(session()) :: map()
  def to_summary(session) do
    %{
      session_id: session.session_id,
      user_id: session.user_id,
      created_at: session.created_at,
      last_activity: session.last_activity,
      age_ms: age_ms(session),
      programs_count: map_size(session.programs),
      stats: session.stats
    }
  end

  @doc """
  Serializes session state for transmission to Python workers.
  """
  @spec serialize_for_worker(session()) :: map()
  def serialize_for_worker(session) do
    %{
      "session_id" => session.session_id,
      "programs" => serialize_programs(session.programs),
      "config" => session.config,
      "stats" => Map.from_struct(session.stats)
    }
  end

  ## Private Functions

  defp init_stats do
    %{
      operations_count: 0,
      errors_count: 0,
      last_error: nil,
      total_execution_time_ms: 0
    }
  end

  defp serialize_programs(programs) do
    Map.new(programs, fn {id, info} ->
      {id,
       %{
         "signature" => info.signature,
         "created_at" => DateTime.to_iso8601(info.created_at),
         "execution_count" => info.execution_count
       }}
    end)
  end
end

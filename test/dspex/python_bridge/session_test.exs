defmodule DSPex.PythonBridge.SessionTest do
  @moduledoc """
  Tests for the Session data structure.

  Uses basic isolation since these are pure data structure tests
  with no process interactions.
  """

  use DSPex.UnifiedTestFoundation, :basic

  alias DSPex.PythonBridge.Session

  describe "new/2" do
    test "creates a session with required fields" do
      session = Session.new("test_session")

      assert session.id == "test_session"
      assert session.programs == %{}
      assert session.metadata == %{}
      assert is_integer(session.created_at)
      assert is_integer(session.last_accessed)
      # default TTL
      assert session.ttl == 3600
      assert session.created_at == session.last_accessed
    end

    test "creates a session with custom options" do
      metadata = %{user_id: "user_123"}
      programs = %{prog_1: %{data: "test"}}

      session =
        Session.new("test_session",
          ttl: 7200,
          metadata: metadata,
          programs: programs
        )

      assert session.id == "test_session"
      assert session.programs == programs
      assert session.metadata == metadata
      assert session.ttl == 7200
    end

    test "requires string ID" do
      assert_raise FunctionClauseError, fn ->
        Session.new(123)
      end
    end
  end

  describe "touch/1" do
    test "updates last_accessed timestamp" do
      session = Session.new("test_session")
      original_time = session.last_accessed

      # Touch the session - this should update last_accessed to current time
      touched_session = Session.touch(session)

      # The timestamp should be >= original (monotonic time can be equal if very fast)
      assert touched_session.last_accessed >= original_time
      assert touched_session.id == session.id
      assert touched_session.programs == session.programs
      assert touched_session.metadata == session.metadata
      assert touched_session.created_at == session.created_at
      assert touched_session.ttl == session.ttl
    end
  end

  describe "expired?/2" do
    test "returns false for non-expired session" do
      session = Session.new("test_session", ttl: 3600)

      refute Session.expired?(session)
    end

    test "returns true for expired session" do
      # Create session with very short TTL
      session = Session.new("test_session", ttl: 1)

      # Test expiration by providing a future time (2 seconds later)
      future_time = session.last_accessed + 2

      assert Session.expired?(session, future_time)
    end

    test "uses provided current_time" do
      session = Session.new("test_session", ttl: 3600)
      # 2 hours later
      future_time = session.last_accessed + 7200

      assert Session.expired?(session, future_time)
    end

    test "handles edge case of exact expiration time" do
      session = Session.new("test_session", ttl: 3600)
      expiration_time = session.last_accessed + session.ttl

      refute Session.expired?(session, expiration_time)
      assert Session.expired?(session, expiration_time + 1)
    end
  end

  describe "validate/1" do
    test "validates correct session" do
      session = Session.new("test_session")

      assert Session.validate(session) == :ok
    end

    test "rejects invalid ID" do
      session = %Session{
        id: "",
        programs: %{},
        metadata: %{},
        created_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: 3600
      }

      assert Session.validate(session) == {:error, :invalid_id}
    end

    test "rejects non-string ID" do
      session = %Session{
        id: 123,
        programs: %{},
        metadata: %{},
        created_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: 3600
      }

      assert Session.validate(session) == {:error, :invalid_id}
    end

    test "rejects invalid programs" do
      session = %Session{
        id: "test",
        programs: "not_a_map",
        metadata: %{},
        created_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: 3600
      }

      assert Session.validate(session) == {:error, :invalid_programs}
    end

    test "rejects invalid metadata" do
      session = %Session{
        id: "test",
        programs: %{},
        metadata: "not_a_map",
        created_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: 3600
      }

      assert Session.validate(session) == {:error, :invalid_metadata}
    end

    test "rejects invalid timestamps" do
      now = System.monotonic_time(:second)

      # Invalid created_at (not integer)
      session1 = %Session{
        id: "test",
        programs: %{},
        metadata: %{},
        created_at: "not_integer",
        last_accessed: now,
        ttl: 3600
      }

      assert Session.validate(session1) == {:error, :invalid_created_at}

      # Invalid last_accessed (not integer)
      session2 = %Session{
        id: "test",
        programs: %{},
        metadata: %{},
        created_at: now,
        last_accessed: "not_integer",
        ttl: 3600
      }

      assert Session.validate(session2) == {:error, :invalid_last_accessed}

      # last_accessed before created_at
      session3 = %Session{
        id: "test",
        programs: %{},
        metadata: %{},
        created_at: now,
        last_accessed: now - 100,
        ttl: 3600
      }

      assert Session.validate(session3) == {:error, :invalid_timestamps}
    end

    test "rejects invalid TTL" do
      session = %Session{
        id: "test",
        programs: %{},
        metadata: %{},
        created_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: -1
      }

      assert Session.validate(session) == {:error, :invalid_ttl}
    end

    test "rejects non-session struct" do
      assert Session.validate(%{}) == {:error, :not_a_session}
      assert Session.validate("not_a_session") == {:error, :not_a_session}
    end
  end

  describe "put_program/3" do
    test "adds program to session" do
      session = Session.new("test_session")
      program_data = %{signature: "test", created_at: System.monotonic_time(:second)}

      updated_session = Session.put_program(session, "prog_1", program_data)

      assert updated_session.programs["prog_1"] == program_data
      assert updated_session.id == session.id
    end

    test "updates existing program" do
      session = Session.new("test_session", programs: %{"prog_1" => %{old: "data"}})
      new_data = %{new: "data"}

      updated_session = Session.put_program(session, "prog_1", new_data)

      assert updated_session.programs["prog_1"] == new_data
    end

    test "requires string program_id" do
      session = Session.new("test_session")

      assert_raise FunctionClauseError, fn ->
        Session.put_program(session, 123, %{})
      end
    end
  end

  describe "get_program/2" do
    test "returns program if exists" do
      program_data = %{signature: "test"}
      session = Session.new("test_session", programs: %{"prog_1" => program_data})

      assert Session.get_program(session, "prog_1") == {:ok, program_data}
    end

    test "returns error if program not found" do
      session = Session.new("test_session")

      assert Session.get_program(session, "nonexistent") == {:error, :not_found}
    end

    test "requires string program_id" do
      session = Session.new("test_session")

      assert_raise FunctionClauseError, fn ->
        Session.get_program(session, 123)
      end
    end
  end

  describe "delete_program/2" do
    test "removes program from session" do
      session = Session.new("test_session", programs: %{"prog_1" => %{}, "prog_2" => %{}})

      updated_session = Session.delete_program(session, "prog_1")

      refute Map.has_key?(updated_session.programs, "prog_1")
      assert Map.has_key?(updated_session.programs, "prog_2")
    end

    test "is idempotent for non-existent programs" do
      session = Session.new("test_session")

      updated_session = Session.delete_program(session, "nonexistent")

      assert updated_session.programs == %{}
    end

    test "requires string program_id" do
      session = Session.new("test_session")

      assert_raise FunctionClauseError, fn ->
        Session.delete_program(session, 123)
      end
    end
  end

  describe "put_metadata/3" do
    test "adds metadata to session" do
      session = Session.new("test_session")

      updated_session = Session.put_metadata(session, :user_id, "user_123")

      assert updated_session.metadata[:user_id] == "user_123"
    end

    test "updates existing metadata" do
      session = Session.new("test_session", metadata: %{user_id: "old_user"})

      updated_session = Session.put_metadata(session, :user_id, "new_user")

      assert updated_session.metadata[:user_id] == "new_user"
    end

    test "supports any key/value types" do
      session = Session.new("test_session")

      updated_session =
        session
        |> Session.put_metadata("string_key", "string_value")
        |> Session.put_metadata(:atom_key, 123)
        |> Session.put_metadata({:tuple, :key}, %{map: "value"})

      assert updated_session.metadata["string_key"] == "string_value"
      assert updated_session.metadata[:atom_key] == 123
      assert updated_session.metadata[{:tuple, :key}] == %{map: "value"}
    end
  end

  describe "get_metadata/3" do
    test "returns metadata value if exists" do
      session = Session.new("test_session", metadata: %{user_id: "user_123"})

      assert Session.get_metadata(session, :user_id) == "user_123"
    end

    test "returns default if key not found" do
      session = Session.new("test_session")

      assert Session.get_metadata(session, :nonexistent, "default") == "default"
    end

    test "returns nil as default if not specified" do
      session = Session.new("test_session")

      assert Session.get_metadata(session, :nonexistent) == nil
    end
  end
end

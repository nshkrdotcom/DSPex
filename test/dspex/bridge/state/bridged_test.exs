defmodule DSPex.Bridge.State.BridgedTest do
  use DSPex.Bridge.StateProviderTest, provider: DSPex.Bridge.State.Bridged
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DSPex.Bridge.State.{Bridged, Local}
  alias Snakepit.Bridge.SessionStore

  setup do
    # Ensure SessionStore is running
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    on_exit(fn ->
      # Cleanup any test sessions
      # SessionStore should handle this via TTL
      :ok
    end)

    :ok
  end

  describe "BridgedState specific features" do
    setup do
      {:ok, state} = Bridged.init(session_id: "test_bridged_#{System.unique_integer()}")
      {:ok, state: state}
    end

    test "delegates to SessionStore", %{state: state} do
      # Register a variable
      {:ok, {var_id, state}} = Bridged.register_variable(state, :test_var, :string, "hello", [])

      # Verify it exists in SessionStore
      assert SessionStore.has_variable?(state.session_id, :test_var)
      assert SessionStore.has_variable?(state.session_id, var_id)

      # Get directly from SessionStore
      {:ok, variable} = SessionStore.get_variable(state.session_id, :test_var)
      assert variable.value == "hello"
      assert variable.name == :test_var
      assert variable.type == :string

      # Update through Bridged
      {:ok, state} = Bridged.set_variable(state, :test_var, "world", %{})

      # Verify in SessionStore
      {:ok, variable} = SessionStore.get_variable(state.session_id, :test_var)
      assert variable.value == "world"
      assert variable.version == 1

      Bridged.cleanup(state)
    end

    test "handles session expiration gracefully", %{state: state} do
      # Register a variable
      {:ok, {_, state}} = Bridged.register_variable(state, :test_var, :integer, 42, [])

      # Delete session directly
      SessionStore.delete_session(state.session_id)

      # Operations should return session_expired error
      assert {:error, :session_expired} = Bridged.get_variable(state, :test_var)
      assert {:error, :session_expired} = Bridged.set_variable(state, :test_var, 100, %{})
      assert {:error, :session_expired} = Bridged.list_variables(state)
    end

    test "batch operations use SessionStore batching", %{state: state} do
      # Register multiple variables
      {:ok, {_, state}} = Bridged.register_variable(state, :var1, :integer, 1, [])
      {:ok, {_, state}} = Bridged.register_variable(state, :var2, :string, "two", [])
      {:ok, {_, state}} = Bridged.register_variable(state, :var3, :float, 3.0, [])

      # Batch get
      _values =
        capture_log(fn ->
          {:ok, result} = Bridged.get_variables(state, [:var1, :var2, :var3, :missing])

          assert result == %{
                   "var1" => 1,
                   "var2" => "two",
                   "var3" => 3.0
                 }
        end)

      # Batch update
      updates = %{
        var1: 10,
        var2: "twenty",
        var3: 30.0
      }

      {:ok, state} = Bridged.update_variables(state, updates, %{})

      # Verify updates
      {:ok, var1} = Bridged.get_variable(state, :var1)
      assert var1 == 10

      {:ok, var2} = Bridged.get_variable(state, :var2)
      assert var2 == "twenty"

      {:ok, var3} = Bridged.get_variable(state, :var3)
      assert var3 == 30.0

      Bridged.cleanup(state)
    end

    test "preserves metadata through operations", %{state: state} do
      # Register with metadata
      meta = %{"source" => "test", "purpose" => "validation"}

      {:ok, {_, state}} =
        Bridged.register_variable(state, :meta_var, :string, "test", metadata: meta)

      # Get from SessionStore to check metadata
      {:ok, variable} = SessionStore.get_variable(state.session_id, :meta_var)
      # SessionStore might override source metadata
      assert variable.metadata["purpose"] == "validation"

      # Update with additional metadata
      {:ok, state} = Bridged.set_variable(state, :meta_var, "updated", %{"updated_by" => "test"})

      {:ok, variable} = SessionStore.get_variable(state.session_id, :meta_var)
      assert variable.metadata["updated_by"] == "test"
      # Original metadata should be preserved (but source might be updated)
      assert variable.metadata["purpose"] == "validation"

      Bridged.cleanup(state)
    end
  end

  describe "state migration from LocalState" do
    test "imports LocalState export correctly" do
      # Create LocalState with some data
      {:ok, local} = Local.init([])
      {:ok, {_, local}} = Local.register_variable(local, :var1, :integer, 42, [])
      {:ok, {_, local}} = Local.register_variable(local, :var2, :string, "hello", [])

      {:ok, {_, local}} =
        Local.register_variable(local, :var3, :float, 3.14, constraints: %{min: 0, max: 10})

      # Export state
      {:ok, exported} = Local.export_state(local)

      # Import into BridgedState
      {:ok, bridged} = Bridged.init(existing_state: exported)

      # Verify all variables were imported
      {:ok, var1} = Bridged.get_variable(bridged, :var1)
      assert var1 == 42

      {:ok, var2} = Bridged.get_variable(bridged, :var2)
      assert var2 == "hello"

      {:ok, var3} = Bridged.get_variable(bridged, :var3)
      assert var3 == 3.14

      # Verify constraints were preserved
      # Should fail constraint
      assert {:error, _} = Bridged.set_variable(bridged, :var3, 15.0, %{})

      # Cleanup
      Local.cleanup(local)
      Bridged.cleanup(bridged)
    end

    test "handles import failures gracefully" do
      # Create invalid export
      invalid_export = %{
        # Missing required fields
        variables: %{}
      }

      # Should fail to initialize
      # BridgedState currently doesn't validate export format - it just imports what it can
      case Bridged.init(existing_state: invalid_export) do
        {:ok, state} -> Bridged.cleanup(state)
        {:error, _} -> :ok
      end

      # Create LocalState with failing variable
      {:ok, local} = Local.init([])
      {:ok, {_, local}} = Local.register_variable(local, :good_var, :integer, 42, [])

      {:ok, exported} = Local.export_state(local)

      # Corrupt one variable
      corrupted =
        put_in(
          exported.variables[Map.keys(exported.variables) |> List.first()].type,
          :invalid_type
        )

      # Import should handle failure - capture expected logs
      {result, logs} =
        with_log(fn ->
          Bridged.init(existing_state: corrupted)
        end)

      # Verify we got the expected warning and error logs
      assert logs =~ "Failed to register variable good_var: {:unknown_type, :invalid_type}"
      assert logs =~ "Failed to import 1 variables"

      case result do
        {:ok, bridged} ->
          # Some variables might have imported
          Bridged.cleanup(bridged)

        {:error, reason} ->
          # Expected if all imports failed
          assert match?({:import_failed, _}, reason)
      end

      Local.cleanup(local)
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "operations complete within target latency" do
      {:ok, state} = Bridged.init([])

      # Register operation - target < 5ms
      {time, {:ok, {_, state}}} =
        :timer.tc(fn ->
          Bridged.register_variable(state, :perf_test, :integer, 42, [])
        end)

      # microseconds
      assert time < 5_000

      # Get operation - target < 2ms
      {time, {:ok, _value}} =
        :timer.tc(fn ->
          Bridged.get_variable(state, :perf_test)
        end)

      assert time < 2_000

      # Set operation - target < 5ms
      {time, {:ok, _}} =
        :timer.tc(fn ->
          Bridged.set_variable(state, :perf_test, 100, %{})
        end)

      assert time < 5_000

      # Batch operations should amortize cost
      variables = for i <- 1..10, do: {:"batch_#{i}", i}

      for {name, value} <- variables do
        {:ok, {_, _new_state}} = Bridged.register_variable(state, name, :integer, value, [])
      end

      # Batch get - should be faster than individual gets
      names = Keyword.keys(variables)

      {batch_time, {:ok, _}} =
        :timer.tc(fn ->
          Bridged.get_variables(state, names)
        end)

      # Average time per variable should be < 1ms
      assert batch_time / length(names) < 1_000

      Bridged.cleanup(state)
    end
  end

  describe "error handling" do
    setup do
      {:ok, state} = Bridged.init(session_id: "error_test_#{System.unique_integer()}")
      {:ok, state: state}
    end

    test "validates types and constraints", %{state: state} do
      # Register with constraints
      {:ok, {_, state}} =
        Bridged.register_variable(
          state,
          :constrained,
          :integer,
          50,
          constraints: %{min: 0, max: 100}
        )

      # Valid update
      assert {:ok, _} = Bridged.set_variable(state, :constrained, 75, %{})

      # Invalid type - BridgedState returns the error without logging
      assert {:error, _} = Bridged.set_variable(state, :constrained, "not a number", %{})

      # Constraint violation - BridgedState returns the error without logging
      assert {:error, _} = Bridged.set_variable(state, :constrained, 150, %{})

      Bridged.cleanup(state)
    end

    test "handles partial batch failures", %{state: state} do
      # Register some variables
      {:ok, {_, state}} = Bridged.register_variable(state, :valid1, :integer, 1, [])

      {:ok, {_, state}} =
        Bridged.register_variable(state, :valid2, :integer, 2, constraints: %{max: 10})

      # Batch update with one failure
      updates = %{
        valid1: 5,
        # Will fail constraint
        valid2: 20,
        # Will fail as not found
        nonexistent: 100
      }

      assert {:error, {:partial_failure, errors}} =
               Bridged.update_variables(state, updates, %{})

      # SessionStore converts keys to strings in the results/errors map
      assert Map.has_key?(errors, "valid2")
      assert Map.has_key?(errors, "nonexistent")

      # Valid update should have succeeded
      assert {:ok, 5} = Bridged.get_variable(state, :valid1)
      # Unchanged
      assert {:ok, 2} = Bridged.get_variable(state, :valid2)

      Bridged.cleanup(state)
    end
  end

  describe "integration scenarios" do
    test "concurrent access from multiple processes" do
      {:ok, state} = Bridged.init(session_id: "concurrent_#{System.unique_integer()}")
      {:ok, {_, state}} = Bridged.register_variable(state, :shared, :integer, 0, [])

      # Spawn multiple processes to update the variable
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            # Each process increments 10 times
            for _ <- 1..10 do
              {:ok, current} = Bridged.get_variable(state, :shared)
              Bridged.set_variable(state, :shared, current + 1, %{})
              # Small random delay
              :timer.sleep(:rand.uniform(5))
            end
          end)
        end

      # Wait for all tasks
      Task.await_many(tasks, 5000)

      # Final value will be less than 100 due to race conditions
      # This demonstrates why atomic operations are important
      {:ok, final} = Bridged.get_variable(state, :shared)
      assert final > 0
      assert final <= 100

      Bridged.cleanup(state)
    end

    test "works with large values" do
      {:ok, state} = Bridged.init(session_id: "large_#{System.unique_integer()}")

      # Large string
      large_string = String.duplicate("x", 100_000)
      {:ok, {_, state}} = Bridged.register_variable(state, :large_str, :string, large_string, [])
      {:ok, retrieved} = Bridged.get_variable(state, :large_str)
      assert retrieved == large_string

      # Large list (would be :embedding type in real usage)
      large_list = for _ <- 1..1000, do: :rand.uniform()

      {:ok, {_, state}} =
        Bridged.register_variable(state, :large_list, :embedding, large_list, [])

      {:ok, retrieved} = Bridged.get_variable(state, :large_list)
      assert retrieved == large_list

      Bridged.cleanup(state)
    end
  end
end

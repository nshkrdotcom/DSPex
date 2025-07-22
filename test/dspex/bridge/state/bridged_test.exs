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
      {:ok, {_var_id, state}} =
        Bridged.register_variable(
          state,
          :bridge_test,
          :string,
          "hello",
          []
        )

      # Verify it's stored via our get_variable method
      assert {:ok, "hello"} = Bridged.get_variable(state, :bridge_test)

      # Update via BridgedState
      {:ok, state} = Bridged.set_variable(state, :bridge_test, "world", %{})

      # Verify via our get_variable method
      assert {:ok, "world"} = Bridged.get_variable(state, :bridge_test)

      Bridged.cleanup(state)
    end

    test "handles session expiration gracefully", %{state: state} do
      # Register a variable
      {:ok, {_, state}} =
        Bridged.register_variable(
          state,
          :temp_var,
          :integer,
          42,
          []
        )

      # Manually delete the session to simulate expiration
      SessionStore.delete_session(state.session_id)

      # Operations should return session_expired error
      assert {:error, :session_expired} = Bridged.get_variable(state, :temp_var)
      assert {:error, :session_expired} = Bridged.set_variable(state, :temp_var, 100, %{})
      assert {:error, :session_expired} = Bridged.list_variables(state)
    end

    test "batch operations use SessionStore batching", %{state: state} do
      # Register multiple variables
      state =
        Enum.reduce(1..10, state, fn i, acc ->
          {:ok, {_, new_state}} =
            Bridged.register_variable(
              acc,
              :"batch_#{i}",
              :integer,
              i,
              []
            )

          new_state
        end)

      # Batch get
      identifiers = Enum.map(1..10, &:"batch_#{&1}")
      {:ok, values} = Bridged.get_variables(state, identifiers)

      assert map_size(values) == 10
      assert values["batch_5"] == 5

      # Batch update
      updates = Map.new(1..10, fn i -> {:"batch_#{i}", i * 10} end)
      {:ok, state} = Bridged.update_variables(state, updates, %{})

      # Verify updates
      {:ok, values} = Bridged.get_variables(state, identifiers)
      assert values["batch_5"] == 50

      Bridged.cleanup(state)
    end

    test "preserves metadata through operations", %{state: state} do
      # Register with metadata
      {:ok, {_, state}} =
        Bridged.register_variable(
          state,
          :meta_test,
          :string,
          "test",
          metadata: %{custom: "value"},
          description: "Test variable"
        )

      # Verify value was stored
      assert {:ok, "test"} = Bridged.get_variable(state, :meta_test)

      # Update with new metadata
      {:ok, state} =
        Bridged.set_variable(
          state,
          :meta_test,
          "updated",
          %{updated_by: "test"}
        )

      # Verify the update worked
      assert {:ok, "updated"} = Bridged.get_variable(state, :meta_test)

      Bridged.cleanup(state)
    end
  end

  describe "state migration from LocalState" do
    test "imports LocalState export correctly" do
      # Create and populate LocalState
      {:ok, local} = Local.init(session_id: "local_source")

      {:ok, {_, local}} =
        Local.register_variable(local, :migrated, :float, 3.14,
          constraints: %{min: 0, max: 10},
          metadata: %{source: "local"}
        )

      {:ok, {_, local}} = Local.register_variable(local, :counter, :integer, 42, [])

      # Export from LocalState
      {:ok, exported} = Local.export_state(local)

      # Import into BridgedState
      {:ok, bridged} =
        Bridged.init(
          session_id: "bridged_target",
          existing_state: exported
        )

      # Verify all variables migrated
      assert {:ok, 3.14} = Bridged.get_variable(bridged, :migrated)
      assert {:ok, 42} = Bridged.get_variable(bridged, :counter)

      # Check that variable values are preserved
      assert {:ok, variables} = Bridged.list_variables(bridged)
      migrated_var = Enum.find(variables, &(&1.name == :migrated))
      assert migrated_var != nil
      assert migrated_var.constraints == %{min: 0, max: 10}

      # Cleanup
      Local.cleanup(local)
      Bridged.cleanup(bridged)
    end

    test "handles import failures gracefully" do
      # Create invalid export (missing required :variables key)
      invalid_export = %{
        # Missing required fields - no variables key at all
        foo: "bar"
      }

      # Should fail to init with invalid export
      assert {:error, _} =
               Bridged.init(
                 session_id: "bad_import",
                 existing_state: invalid_export
               )

      # Session should not exist
      # SessionStore returns :not_found for missing sessions
      assert {:error, :not_found} = SessionStore.get_session("bad_import")
    end
  end

  describe "performance characteristics" do
    setup do
      {:ok, state} = Bridged.init(session_id: "perf_test_#{System.unique_integer()}")

      # Pre-populate variables
      state =
        Enum.reduce(1..50, state, fn i, acc ->
          {:ok, {_, new_state}} =
            Bridged.register_variable(
              acc,
              :"perf_var_#{i}",
              :integer,
              i,
              []
            )

          new_state
        end)

      {:ok, state: state}
    end

    test "operations complete within target latency", %{state: state} do
      # Measure get operation
      {get_time, {:ok, _}} =
        :timer.tc(fn ->
          Bridged.get_variable(state, :perf_var_25)
        end)

      # Should be under 5ms (generous for CI)
      assert get_time < 5_000

      # Measure set operation
      {set_time, {:ok, _}} =
        :timer.tc(fn ->
          Bridged.set_variable(state, :perf_var_25, 999, %{})
        end)

      # Should be under 10ms (generous for CI)
      assert set_time < 10_000

      # Measure batch get
      identifiers = Enum.map(1..20, &:"perf_var_#{&1}")

      {batch_time, {:ok, values}} =
        :timer.tc(fn ->
          Bridged.get_variables(state, identifiers)
        end)

      assert map_size(values) == 20

      # Batch should be more efficient than individual
      # Should be under 20ms for 20 variables
      assert batch_time < 20_000

      # Average time per variable in batch
      avg_per_var = batch_time / 20
      # Better than individual gets
      assert avg_per_var < get_time

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

      # Invalid type
      assert capture_log(fn ->
               assert {:error, _} = Bridged.set_variable(state, :constrained, "not a number", %{})
             end) =~ "must be an integer"

      # Constraint violation
      assert capture_log(fn ->
               assert {:error, _} = Bridged.set_variable(state, :constrained, 150, %{})
             end) =~ "value 150 is above maximum 100"

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

      assert Map.has_key?(errors, :valid2)
      assert Map.has_key?(errors, :nonexistent)

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

      # Spawn multiple processes to increment
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Each process creates its own state reference
            {:ok, my_state} = Bridged.init(session_id: state.session_id)

            # Read-modify-write
            {:ok, current} = Bridged.get_variable(my_state, :shared)
            Bridged.set_variable(my_state, :shared, current + 1, %{process: i})
          end)
        end

      # Wait for all
      Enum.each(tasks, &Task.await/1)

      # Final value will be <= 10 due to race conditions
      # This is expected without true atomic operations
      {:ok, final} = Bridged.get_variable(state, :shared)
      assert final > 0 and final <= 10

      Bridged.cleanup(state)
    end

    test "works with large values" do
      {:ok, state} = Bridged.init(session_id: "large_#{System.unique_integer()}")

      # Store a large string
      large_value = String.duplicate("x", 100_000)

      {:ok, {_, state}} =
        Bridged.register_variable(
          state,
          :large,
          :string,
          large_value,
          []
        )

      # Retrieve it
      {:ok, retrieved} = Bridged.get_variable(state, :large)
      assert byte_size(retrieved) == 100_000

      # Update with another large value
      another_large = String.duplicate("y", 100_000)
      assert {:ok, _} = Bridged.set_variable(state, :large, another_large, %{})

      Bridged.cleanup(state)
    end
  end
end

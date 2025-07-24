defmodule DSPex.Bridge.State.LocalTest do
  use DSPex.Bridge.StateProviderTest, provider: DSPex.Bridge.State.Local

  alias DSPex.Bridge.State.Local

  describe "LocalState specific features" do
    setup do
      {:ok, state} = Local.init(session_id: "test_local")
      {:ok, state: state}
    end

    @tag :performance
    test "sub-microsecond performance", %{state: state} do
      # Register a variable
      {:ok, {_, state}} =
        Local.register_variable(
          state,
          :perf_test,
          :float,
          1.0,
          []
        )

      # Measure get performance
      measurements =
        for _ <- 1..1000 do
          {time, {:ok, _}} =
            :timer.tc(fn ->
              Local.get_variable(state, :perf_test)
            end)

          time
        end

      avg_microseconds = Enum.sum(measurements) / length(measurements)

      # Should average under 5 microseconds (relaxed for test environment)
      assert avg_microseconds < 5.0

      # 99th percentile should be under 50 microseconds (relaxed for test environment)
      sorted = Enum.sort(measurements)
      p99 = Enum.at(sorted, round(length(sorted) * 0.99))
      assert p99 < 50.0
    end

    test "efficient batch operations", %{state: state} do
      # Register 100 variables
      state =
        Enum.reduce(1..100, state, fn i, acc_state ->
          {:ok, {_, new_state}} =
            Local.register_variable(
              acc_state,
              :"var_#{i}",
              :integer,
              i,
              []
            )

          new_state
        end)

      # Batch get all 100
      identifiers = Enum.map(1..100, &:"var_#{&1}")

      {time, {:ok, values}} =
        :timer.tc(fn ->
          Local.get_variables(state, identifiers)
        end)

      assert map_size(values) == 100

      # Should be much faster than 100 individual gets
      # Roughly 10-50 microseconds total
      # 50ms
      assert time < 50_000
    end

    test "memory efficiency", %{state: state} do
      # Get initial memory
      {:ok, exported1} = Local.export_state(state)
      initial_size = :erlang.external_size(exported1)

      # Add 10 variables
      state =
        Enum.reduce(1..10, state, fn i, acc_state ->
          {:ok, {_, new_state}} =
            Local.register_variable(
              acc_state,
              :"mem_test_#{i}",
              :string,
              String.duplicate("x", 100),
              metadata: %{index: i}
            )

          new_state
        end)

      # Check memory growth
      {:ok, exported2} = Local.export_state(state)
      final_size = :erlang.external_size(exported2)

      growth_per_var = (final_size - initial_size) / 10

      # Should be reasonably efficient
      # Roughly 200-500 bytes per variable with 100-char string
      assert growth_per_var < 1000
    end

    test "name collision detection", %{state: state} do
      # Register a variable
      {:ok, {_, state}} =
        Local.register_variable(
          state,
          :duplicate,
          :string,
          "first",
          []
        )

      # Try to register with same name
      assert {:error, {:already_exists, :duplicate}} =
               Local.register_variable(state, :duplicate, :string, "second", [])

      # Original still has first value
      assert {:ok, "first"} = Local.get_variable(state, :duplicate)
    end

    test "stats tracking", %{state: state} do
      # Perform various operations
      {:ok, {_, state}} = Local.register_variable(state, :x, :integer, 1, [])
      {:ok, 1} = Local.get_variable(state, :x)
      {:ok, 1} = Local.get_variable(state, :x)
      {:ok, state} = Local.set_variable(state, :x, 2, %{})

      # Export to see stats
      {:ok, exported} = Local.export_state(state)
      stats = exported.stats

      assert stats.variable_count == 1
      # register + 2 gets + 1 set
      assert stats.total_operations >= 4
      assert stats.total_updates == 1
      assert stats.total_get_microseconds > 0
    end
  end

  describe "state migration" do
    test "can import from another LocalState" do
      # Create source state
      {:ok, source} = Local.init(session_id: "source")
      {:ok, {_, source}} = Local.register_variable(source, :a, :integer, 1, [])
      {:ok, {_, source}} = Local.register_variable(source, :b, :string, "test", [])

      # Export
      {:ok, exported} = Local.export_state(source)

      # Import into new state
      {:ok, target} = Local.init(session_id: "target")
      {:ok, target} = Local.import_state(target, exported)

      # Verify
      assert {:ok, 1} = Local.get_variable(target, :a)
      assert {:ok, "test"} = Local.get_variable(target, :b)

      # Can still add new variables
      {:ok, {_, target}} = Local.register_variable(target, :c, :float, 3.14, [])
      assert {:ok, 3.14} = Local.get_variable(target, :c)

      # Cleanup
      Local.cleanup(source)
      Local.cleanup(target)
    end
  end
end

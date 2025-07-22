defmodule DSPex.Bridge.StateProviderTest do
  @moduledoc """
  Shared tests for StateProvider implementations.

  Use this module in your backend tests:

      defmodule MyBackendTest do
        use DSPex.Bridge.StateProviderTest, provider: MyBackend
      end
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)

    quote do
      use ExUnit.Case, async: true

      @provider unquote(provider)

      describe "StateProvider compliance for #{@provider}" do
        test "implements all required callbacks" do
          assert DSPex.Bridge.StateProvider.validate_provider!(@provider) == :ok
        end

        test "basic variable lifecycle" do
          {:ok, state} = @provider.init(session_id: "test")

          # Register
          assert {:ok, {var_id, state}} =
                   @provider.register_variable(
                     state,
                     :test_var,
                     :string,
                     "hello",
                     []
                   )

          assert is_binary(var_id)

          # Get
          assert {:ok, "hello"} = @provider.get_variable(state, :test_var)
          assert {:ok, "hello"} = @provider.get_variable(state, var_id)

          # Update
          assert {:ok, state} = @provider.set_variable(state, :test_var, "world", %{})
          assert {:ok, "world"} = @provider.get_variable(state, :test_var)

          # Delete
          assert {:ok, state} = @provider.delete_variable(state, :test_var)
          assert {:error, :not_found} = @provider.get_variable(state, :test_var)

          # Cleanup
          assert :ok = @provider.cleanup(state)
        end

        test "batch operations" do
          {:ok, state} = @provider.init(session_id: "test")

          # Register multiple
          {:ok, {_, state}} = @provider.register_variable(state, :a, :integer, 1, [])
          {:ok, {_, state}} = @provider.register_variable(state, :b, :integer, 2, [])
          {:ok, {_, state}} = @provider.register_variable(state, :c, :integer, 3, [])

          # Batch get
          assert {:ok, values} = @provider.get_variables(state, [:a, :b, :c])
          assert values[:a] == 1 or values["a"] == 1
          assert values[:b] == 2 or values["b"] == 2
          assert values[:c] == 3 or values["c"] == 3

          # Batch update
          assert {:ok, state} =
                   @provider.update_variables(
                     state,
                     %{a: 10, b: 20, c: 30},
                     %{}
                   )

          assert {:ok, 10} = @provider.get_variable(state, :a)
          assert {:ok, 20} = @provider.get_variable(state, :b)
          assert {:ok, 30} = @provider.get_variable(state, :c)

          :ok = @provider.cleanup(state)
        end

        test "export and import state" do
          {:ok, state1} = @provider.init(session_id: "test")

          # Create some state
          {:ok, {_, state1}} = @provider.register_variable(state1, :x, :float, 3.14, [])
          {:ok, {_, state1}} = @provider.register_variable(state1, :y, :string, "test", [])

          # Export
          assert {:ok, exported} = @provider.export_state(state1)
          assert exported.session_id == "test"
          assert map_size(exported.variables) == 2

          # Import into new backend
          {:ok, state2} = @provider.init(session_id: "test2")
          assert {:ok, state2} = @provider.import_state(state2, exported)

          # Verify imported state
          assert {:ok, 3.14} = @provider.get_variable(state2, :x)
          assert {:ok, "test"} = @provider.get_variable(state2, :y)

          :ok = @provider.cleanup(state1)
          :ok = @provider.cleanup(state2)
        end

        test "capabilities and metadata" do
          caps = @provider.capabilities()
          assert is_map(caps)
          assert is_boolean(caps[:atomic_updates])
          assert is_boolean(caps[:streaming])
          assert is_boolean(caps[:persistent])
          assert is_boolean(caps[:distributed])

          assert is_boolean(@provider.requires_bridge?())
        end

        test "missing variables return not_found" do
          {:ok, state} = @provider.init(session_id: "test")

          assert {:error, :not_found} = @provider.get_variable(state, :nonexistent)
          assert {:error, :not_found} = @provider.delete_variable(state, :nonexistent)

          # Batch get with missing should just omit them
          assert {:ok, values} = @provider.get_variables(state, [:missing1, :missing2])
          assert values == %{}

          :ok = @provider.cleanup(state)
        end

        test "variable name and ID resolution" do
          {:ok, state} = @provider.init(session_id: "test")

          # Register with atom name
          {:ok, {var_id, state}} = @provider.register_variable(state, :myvar, :string, "test", [])

          # Should work with atom, string name, and ID
          assert {:ok, "test"} = @provider.get_variable(state, :myvar)
          assert {:ok, "test"} = @provider.get_variable(state, "myvar")
          assert {:ok, "test"} = @provider.get_variable(state, var_id)

          :ok = @provider.cleanup(state)
        end

        test "metadata preservation" do
          {:ok, state} = @provider.init(session_id: "test")

          # Register with metadata
          {:ok, {_, state}} =
            @provider.register_variable(
              state,
              :meta_var,
              :integer,
              42,
              metadata: %{created_by: "test", purpose: "testing"}
            )

          # Update with new metadata
          assert {:ok, state} =
                   @provider.set_variable(
                     state,
                     :meta_var,
                     100,
                     %{updated_by: "test", reason: "test update"}
                   )

          # List should include the variable with value
          assert {:ok, vars} = @provider.list_variables(state)
          assert length(vars) == 1
          var = hd(vars)
          assert var.name == :meta_var or var.name == "meta_var"
          assert var.value == 100

          :ok = @provider.cleanup(state)
        end
      end
    end
  end
end

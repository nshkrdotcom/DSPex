defmodule DSPex.VariablesTest do
  use ExUnit.Case, async: true

  alias DSPex.{Context, Variables}
  alias DSPex.Variables.VariableNotFoundError

  setup do
    {:ok, ctx} = Context.start_link()
    {:ok, ctx: ctx}
  end

  describe "defvariable/5" do
    test "creates typed variables", %{ctx: ctx} do
      assert {:ok, var_id} = Variables.defvariable(ctx, :test, :string, "hello")
      assert String.starts_with?(var_id, "var_")

      assert Variables.get(ctx, :test) == "hello"
    end

    test "enforces constraints", %{ctx: ctx} do
      assert {:ok, _} =
               Variables.defvariable(ctx, :score, :float, 0.5, constraints: %{min: 0.0, max: 1.0})

      # Valid update
      assert :ok = Variables.set(ctx, :score, 0.8)

      # Invalid update
      assert {:error, _} = Variables.set(ctx, :score, 1.5)
    end

    test "bang variant raises", %{ctx: ctx} do
      var_id = Variables.defvariable!(ctx, :bang, :integer, 42)
      assert is_binary(var_id)

      # Try to create duplicate
      assert_raise ArgumentError, ~r/Failed to define variable/, fn ->
        Variables.defvariable!(ctx, :bang, :integer, 100)
      end
    end
  end

  describe "get/3 and get!/2" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :exists, :string, "value")
      :ok
    end

    test "get returns value or default", %{ctx: ctx} do
      assert Variables.get(ctx, :exists) == "value"
      assert Variables.get(ctx, :missing) == nil
      assert Variables.get(ctx, :missing, "default") == "default"
    end

    test "get! raises on missing", %{ctx: ctx} do
      assert Variables.get!(ctx, :exists) == "value"

      assert_raise VariableNotFoundError, ~r/Variable not found: :missing/, fn ->
        Variables.get!(ctx, :missing)
      end
    end
  end

  describe "update/4" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :counter, :integer, 0)
      :ok
    end

    test "applies function to current value", %{ctx: ctx} do
      assert :ok = Variables.update(ctx, :counter, &(&1 + 1))
      assert Variables.get(ctx, :counter) == 1

      assert :ok = Variables.update(ctx, :counter, &(&1 * 2))
      assert Variables.get(ctx, :counter) == 2
    end

    test "returns error for missing variable", %{ctx: ctx} do
      assert {:error, :not_found} = Variables.update(ctx, :missing, &(&1 + 1))
    end

    test "validates new value", %{ctx: ctx} do
      Variables.defvariable!(ctx, :limited, :integer, 5, constraints: %{max: 10})

      # This would exceed constraint
      assert {:error, _} = Variables.update(ctx, :limited, &(&1 * 3))
    end
  end

  describe "batch operations" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :a, :integer, 1)
      Variables.defvariable!(ctx, :b, :integer, 2)
      Variables.defvariable!(ctx, :c, :integer, 3)
      :ok
    end

    test "get_many returns found variables", %{ctx: ctx} do
      values = Variables.get_many(ctx, [:a, :b, :missing])

      assert values == %{a: 1, b: 2}
      assert not Map.has_key?(values, :missing)
    end

    test "update_many updates multiple variables", %{ctx: ctx} do
      assert :ok = Variables.update_many(ctx, %{a: 10, b: 20})

      assert Variables.get(ctx, :a) == 10
      assert Variables.get(ctx, :b) == 20
      # Unchanged
      assert Variables.get(ctx, :c) == 3
    end

    test "update_many handles partial failures", %{ctx: ctx} do
      Variables.defvariable!(ctx, :constrained, :integer, 5, constraints: %{max: 10})

      # One update will fail
      result =
        Variables.update_many(ctx, %{
          a: 100,
          # Exceeds max
          constrained: 50
        })

      assert {:error, {:partial_failure, _}} = result
      # Updated
      assert Variables.get(ctx, :a) == 100
      # Not updated
      assert Variables.get(ctx, :constrained) == 5
    end
  end

  describe "introspection" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :typed, :float, 3.14,
        constraints: %{min: 0},
        metadata: %{"unit" => "radians"}
      )

      :ok
    end

    test "list returns all variables", %{ctx: ctx} do
      vars = Variables.list(ctx)
      assert length(vars) == 1

      var = hd(vars)
      assert var.name == :typed
      assert var.type == :float
      assert var.value == 3.14
    end

    test "get_type returns variable type", %{ctx: ctx} do
      assert Variables.get_type(ctx, :typed) == :float
      assert Variables.get_type(ctx, :missing) == nil
    end

    test "get_constraints returns constraints", %{ctx: ctx} do
      assert Variables.get_constraints(ctx, :typed) == %{min: 0}
      assert Variables.get_constraints(ctx, :missing) == nil
    end

    test "get_metadata returns metadata", %{ctx: ctx} do
      meta = Variables.get_metadata(ctx, :typed)
      assert meta["unit"] == "radians"
    end

    test "exists? checks existence", %{ctx: ctx} do
      assert Variables.exists?(ctx, :typed) == true
      assert Variables.exists?(ctx, :missing) == false
    end
  end

  describe "delete operations" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :deleteme, :string, "temp")
      :ok
    end

    test "delete removes variable", %{ctx: ctx} do
      assert Variables.exists?(ctx, :deleteme)
      assert :ok = Variables.delete(ctx, :deleteme)
      assert not Variables.exists?(ctx, :deleteme)
    end

    test "delete returns error for missing", %{ctx: ctx} do
      assert {:error, :not_found} = Variables.delete(ctx, :missing)
    end

    test "delete! raises on missing", %{ctx: ctx} do
      assert_raise VariableNotFoundError, fn ->
        Variables.delete!(ctx, :missing)
      end
    end
  end
end

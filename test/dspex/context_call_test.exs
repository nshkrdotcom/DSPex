defmodule DSPex.ContextCallTest do
  use ExUnit.Case, async: true

  alias DSPex.Context

  describe "Context.call/3" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end

    test "returns error when program not found", %{ctx: ctx} do
      assert {:error, {:program_not_found, "nonexistent"}} = Context.call(ctx, "nonexistent", %{})
    end

    test "stores program ID in spec when registering", %{ctx: ctx} do
      Context.register_program(ctx, "my_program", %{
        type: :dspy,
        module_type: "predict"
      })

      # Get the state to verify program was stored with ID
      state = :sys.get_state(ctx)
      program_spec = Map.get(state.programs, "my_program")

      assert program_spec.id == "my_program"
      assert program_spec.type == :dspy
      assert program_spec.module_type == "predict"
    end
  end
end

defmodule DSPex.GeneratedSurface018Test do
  use ExUnit.Case, async: true

  test "SnakeBridge 0.18 generated DSPy default arities are available" do
    expected = [
      {Dspy.LM, :new, 1},
      {Dspy.LM, :new, 2},
      {Dspy.LM, :forward, 1},
      {Dspy.LM, :forward, 2},
      {Dspy.PredictClass, :new, 1},
      {Dspy.ChainOfThought, :new, 1},
      {Dspy.Example, :new, 0},
      {Dspy.Example, :new, 1},
      {Dspy.BootstrapFewShot, :new, 0},
      {Dspy.Experimental.TypeSafe, :new, 1},
      {Dspy.Predict.RLM, :new, 1},
      {Dspy.Predict.RLM, :new, 9}
    ]

    Enum.each(expected, fn {module, function, arity} ->
      assert {:module, ^module} = Code.ensure_loaded(module)

      assert function_exported?(module, function, arity),
             "expected #{inspect(module)}.#{function}/#{arity}"
    end)
  end
end

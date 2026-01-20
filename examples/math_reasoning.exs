# Math Reasoning Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/math_reasoning.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Math Reasoning Example")
  IO.puts("==============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  # Chain of thought for math problems
  {:ok, solver} = Dspy.ChainOfThought.new("problem -> answer", [])

  problems = [
    "A train travels 120 miles in 2 hours. What is its average speed?",
    "If 3x + 7 = 22, what is x?",
    "A rectangle has length 8 and width 5. What is its area and perimeter?"
  ]

  for problem <- problems do
    IO.puts("Problem: #{problem}")
    {:ok, result} = Dspy.ChainOfThought.forward(solver, problem: problem)
    {:ok, reasoning} = SnakeBridge.attr(result, "reasoning")
    {:ok, answer} = SnakeBridge.attr(result, "answer")
    IO.puts("Reasoning: #{reasoning}")
    IO.puts("Answer: #{answer}\n")
  end

  IO.puts("Done!")
end)

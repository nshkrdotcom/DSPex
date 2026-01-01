# Math Reasoning Example
#
# Run with: mix run examples/math_reasoning.exs

DSPex.run(fn ->
  IO.puts("DSPex Math Reasoning Example")
  IO.puts("==============================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  # Chain of thought for math problems
  solver = DSPex.chain_of_thought!("problem -> answer")

  problems = [
    "A train travels 120 miles in 2 hours. What is its average speed?",
    "If 3x + 7 = 22, what is x?",
    "A rectangle has length 8 and width 5. What is its area and perimeter?"
  ]

  for problem <- problems do
    IO.puts("Problem: #{problem}")
    result = DSPex.method!(solver, "forward", [], problem: problem)
    reasoning = DSPex.attr!(result, "reasoning")
    answer = DSPex.attr!(result, "answer")
    IO.puts("Reasoning: #{reasoning}")
    IO.puts("Answer: #{answer}\n")
  end

  IO.puts("Done!")
end)

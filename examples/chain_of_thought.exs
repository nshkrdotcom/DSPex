# Chain of Thought Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/chain_of_thought.exs
#
# Requires: GEMINI_API_KEY environment variable

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Chain of Thought Example")
  IO.puts("===============================\n")

  # Setup using native bindings
  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [], temperature: 0.7)
  {:ok, _} = Dspy.configure(lm: lm)

  # Create ChainOfThought predictor using native bindings
  {:ok, cot} = Dspy.ChainOfThought.new("question -> answer", [])

  questions = [
    "If I have 5 apples and give 2 to my friend, then buy 3 more, how many do I have?",
    "What is 15% of 80?"
  ]

  for question <- questions do
    IO.puts("Q: #{question}")
    {:ok, result} = Dspy.ChainOfThought.forward(cot, question: question)
    {:ok, reasoning} = SnakeBridge.attr(result, "reasoning")
    {:ok, answer} = SnakeBridge.attr(result, "answer")
    IO.puts("Reasoning: #{reasoning}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end)

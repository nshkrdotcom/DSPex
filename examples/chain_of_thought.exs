# Chain of Thought Example
#
# Run with: mix run --no-start examples/chain_of_thought.exs
#
# Requires: GEMINI_API_KEY environment variable

DSPex.run(fn ->
  IO.puts("DSPex Chain of Thought Example")
  IO.puts("===============================\n")

  # Setup
  lm = DSPex.lm!("gemini/gemini-flash-lite-latest", temperature: 0.7)
  DSPex.configure!(lm: lm)

  # Create ChainOfThought predictor
  cot = DSPex.chain_of_thought!("question -> answer")

  questions = [
    "If I have 5 apples and give 2 to my friend, then buy 3 more, how many do I have?",
    "What is 15% of 80?"
  ]

  for question <- questions do
    IO.puts("Q: #{question}")
    result = DSPex.method!(cot, "forward", [], question: question)
    reasoning = DSPex.attr!(result, "reasoning")
    answer = DSPex.attr!(result, "answer")
    IO.puts("Reasoning: #{reasoning}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end)

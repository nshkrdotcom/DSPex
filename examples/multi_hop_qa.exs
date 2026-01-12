# Multi-hop QA Example
#
# Run with: mix run --no-start examples/multi_hop_qa.exs
#
# Requires: GEMINI_API_KEY environment variable

DSPex.run(fn ->
  IO.puts("DSPex Multi-hop QA Example")
  IO.puts("=============================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  hop1 = DSPex.predict!("question -> answer")
  hop2 = DSPex.predict!("context, question -> answer")

  question = "What is the capital of the state where the University of Michigan is located?"
  IO.puts("Question: #{question}\n")

  hop1_question = "Which state is the University of Michigan located in?"
  hop1_result = DSPex.method!(hop1, "forward", [], question: hop1_question)
  state = DSPex.attr!(hop1_result, "answer")
  IO.puts("Hop 1 answer: #{state}")

  context = "The University of Michigan is located in #{state}."
  hop2_question = "What is the capital of #{state}?"
  hop2_result = DSPex.method!(hop2, "forward", [], context: context, question: hop2_question)
  capital = DSPex.attr!(hop2_result, "answer")
  IO.puts("Hop 2 answer: #{capital}\n")

  IO.puts("Done!")
end)

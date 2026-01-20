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

  capitals = %{"Michigan" => "Lansing"}
  capital = Map.get(capitals, state, "Unknown")
  context = "The capital of #{state} is #{capital}."
  IO.puts("Retrieved context: #{context}")
  hop2_question = "What is the capital of #{state}?"
  hop2_result = DSPex.method!(hop2, "forward", [], context: context, question: hop2_question)
  hop2_answer = DSPex.attr!(hop2_result, "answer")
  IO.puts("Hop 2 answer: #{hop2_answer}\n")

  IO.puts("Done!")
end)

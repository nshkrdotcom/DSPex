# Multi-hop QA Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/multi_hop_qa.exs
#
# Requires: GEMINI_API_KEY environment variable

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Multi-hop QA Example")
  IO.puts("=============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, hop1} = Dspy.PredictClass.new("question -> answer", [])
  {:ok, hop2} = Dspy.PredictClass.new("context, question -> answer", [])

  question = "What is the capital of the state where the University of Michigan is located?"
  IO.puts("Question: #{question}\n")

  hop1_question = "Which state is the University of Michigan located in?"
  {:ok, hop1_result} = Dspy.PredictClass.forward(hop1, question: hop1_question)
  {:ok, state} = SnakeBridge.attr(hop1_result, "answer")
  IO.puts("Hop 1 answer: #{state}")

  capitals = %{"Michigan" => "Lansing"}
  capital = Map.get(capitals, state, "Unknown")
  context = "The capital of #{state} is #{capital}."
  IO.puts("Retrieved context: #{context}")
  hop2_question = "What is the capital of #{state}?"
  {:ok, hop2_result} = Dspy.PredictClass.forward(hop2, context: context, question: hop2_question)
  {:ok, hop2_answer} = SnakeBridge.attr(hop2_result, "answer")
  IO.puts("Hop 2 answer: #{hop2_answer}\n")

  IO.puts("Done!")
end

# Custom Signature with Instructions Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/custom_signature.exs

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Custom Signature Example")
  IO.puts("================================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  # Create a signature with custom instructions via generated wrappers
  {:ok, sig} =
    Dspy.make_signature(
      "question -> answer",
      "You are a helpful assistant that answers questions concisely in one sentence."
    )

  # Create predictor with custom signature
  {:ok, predict} = Dspy.PredictClass.new(sig, [])

  questions = [
    "What is photosynthesis?",
    "Why is the sky blue?"
  ]

  for question <- questions do
    {:ok, result} = Dspy.PredictClass.forward(predict, question: question)
    {:ok, answer} = SnakeBridge.attr(result, "answer")
    IO.puts("Q: #{question}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end

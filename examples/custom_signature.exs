# Custom Signature with Instructions Example
#
# Run with: mix run --no-start examples/custom_signature.exs

DSPex.run(fn ->
  IO.puts("DSPex Custom Signature Example")
  IO.puts("================================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  # Create a signature with custom instructions via generated wrappers
  {:ok, sig} =
    Dspy.make_signature(
      "question -> answer",
      "You are a helpful assistant that answers questions concisely in one sentence."
    )

  # Create predictor with custom signature
  predict = DSPex.predict!(sig)

  questions = [
    "What is photosynthesis?",
    "Why is the sky blue?"
  ]

  for question <- questions do
    result = DSPex.method!(predict, "forward", [], question: question)
    answer = DSPex.attr!(result, "answer")
    IO.puts("Q: #{question}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end)

# Custom Signature with Instructions Example
#
# Run with: mix run examples/custom_signature.exs

DSPex.run(fn ->
  IO.puts("DSPex Custom Signature Example")
  IO.puts("================================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  # Create a signature with custom instructions
  sig = DSPex.call!("dspy", "Signature", ["question -> answer"])

  # Update instructions
  sig =
    DSPex.method!(sig, "with_instructions", [
      "You are a helpful assistant that answers questions concisely in one sentence."
    ])

  # Create predictor with custom signature
  predict = DSPex.call!("dspy", "Predict", [sig])

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

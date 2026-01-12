# Classification Example
#
# Run with: mix run --no-start examples/classification.exs

DSPex.run(fn ->
  IO.puts("DSPex Classification Example")
  IO.puts("=============================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  # Sentiment classification
  classifier = DSPex.predict!("text -> sentiment")

  texts = [
    "I love this product! It's amazing!",
    "This is terrible, worst purchase ever.",
    "It's okay, nothing special."
  ]

  IO.puts("Sentiment Classification:")

  for text <- texts do
    result = DSPex.method!(classifier, "forward", [], text: text)
    sentiment = DSPex.attr!(result, "sentiment")
    IO.puts("  \"#{String.slice(text, 0..40)}...\" -> #{sentiment}")
  end

  IO.puts("\nDone!")
end)

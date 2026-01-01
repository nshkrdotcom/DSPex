# Classification Example
#
# Run with: mix run examples/classification.exs

DSPex.run(fn ->
  IO.puts("DSPex Classification Example")
  IO.puts("=============================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
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

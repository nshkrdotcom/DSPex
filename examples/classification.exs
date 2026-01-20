# Classification Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/classification.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Classification Example")
  IO.puts("=============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  # Sentiment classification
  {:ok, classifier} = Dspy.PredictClass.new("text -> sentiment", [])

  texts = [
    "I love this product! It's amazing!",
    "This is terrible, worst purchase ever.",
    "It's okay, nothing special."
  ]

  IO.puts("Sentiment Classification:")

  for text <- texts do
    {:ok, result} = Dspy.PredictClass.forward(classifier, text: text)
    {:ok, sentiment} = SnakeBridge.attr(result, "sentiment")
    IO.puts("  \"#{String.slice(text, 0..40)}...\" -> #{sentiment}")
  end

  IO.puts("\nDone!")
end)

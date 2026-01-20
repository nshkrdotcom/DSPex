# Multi-Field Signature Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/multi_field.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Multi-Field Signature Example")
  IO.puts("=====================================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  # Multiple inputs and outputs
  {:ok, analyzer} = Dspy.PredictClass.new("title, content -> category, keywords, tone", [])

  title = "Breaking: Major Tech Company Announces Layoffs"
  content = "The company cited economic headwinds and a need to focus on AI initiatives."

  IO.puts("Input:")
  IO.puts("  Title: #{title}")
  IO.puts("  Content: #{content}\n")

  {:ok, result} = Dspy.PredictClass.forward(analyzer, title: title, content: content)

  {:ok, category} = SnakeBridge.attr(result, "category")
  {:ok, keywords} = SnakeBridge.attr(result, "keywords")
  {:ok, tone} = SnakeBridge.attr(result, "tone")

  IO.puts("Output:")
  IO.puts("  Category: #{category}")
  IO.puts("  Keywords: #{keywords}")
  IO.puts("  Tone: #{tone}")

  IO.puts("\nDone!")
end)

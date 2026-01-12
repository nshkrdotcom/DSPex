# Multi-Field Signature Example
#
# Run with: mix run --no-start examples/multi_field.exs

DSPex.run(fn ->
  IO.puts("DSPex Multi-Field Signature Example")
  IO.puts("=====================================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  # Multiple inputs and outputs
  analyzer = DSPex.predict!("title, content -> category, keywords, tone")

  title = "Breaking: Major Tech Company Announces Layoffs"
  content = "The company cited economic headwinds and a need to focus on AI initiatives."

  IO.puts("Input:")
  IO.puts("  Title: #{title}")
  IO.puts("  Content: #{content}\n")

  result = DSPex.method!(analyzer, "forward", [], title: title, content: content)

  category = DSPex.attr!(result, "category")
  keywords = DSPex.attr!(result, "keywords")
  tone = DSPex.attr!(result, "tone")

  IO.puts("Output:")
  IO.puts("  Category: #{category}")
  IO.puts("  Keywords: #{keywords}")
  IO.puts("  Tone: #{tone}")

  IO.puts("\nDone!")
end)

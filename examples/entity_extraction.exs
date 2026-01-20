# Entity Extraction Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/entity_extraction.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Entity Extraction Example")
  IO.puts("=================================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, extractor} = Dspy.PredictClass.new("text -> people, organizations, locations", [])

  text = """
  Apple CEO Tim Cook announced a new partnership with Microsoft at their
  headquarters in Cupertino, California. The event was also attended by
  Satya Nadella, who flew in from Seattle.
  """

  IO.puts("Text: #{String.trim(text)}\n")

  {:ok, result} = Dspy.PredictClass.forward(extractor, text: text)

  {:ok, people} = SnakeBridge.attr(result, "people")
  {:ok, orgs} = SnakeBridge.attr(result, "organizations")
  {:ok, locations} = SnakeBridge.attr(result, "locations")

  IO.puts("Extracted Entities:")
  IO.puts("  People: #{people}")
  IO.puts("  Organizations: #{orgs}")
  IO.puts("  Locations: #{locations}")

  IO.puts("\nDone!")
end)

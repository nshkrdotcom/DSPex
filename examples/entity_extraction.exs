# Entity Extraction Example
#
# Run with: mix run --no-start examples/entity_extraction.exs

DSPex.run(fn ->
  IO.puts("DSPex Entity Extraction Example")
  IO.puts("=================================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  extractor = DSPex.predict!("text -> people, organizations, locations")

  text = """
  Apple CEO Tim Cook announced a new partnership with Microsoft at their
  headquarters in Cupertino, California. The event was also attended by
  Satya Nadella, who flew in from Seattle.
  """

  IO.puts("Text: #{String.trim(text)}\n")

  result = DSPex.method!(extractor, "forward", [], text: text)

  people = DSPex.attr!(result, "people")
  orgs = DSPex.attr!(result, "organizations")
  locations = DSPex.attr!(result, "locations")

  IO.puts("Extracted Entities:")
  IO.puts("  People: #{people}")
  IO.puts("  Organizations: #{orgs}")
  IO.puts("  Locations: #{locations}")

  IO.puts("\nDone!")
end)

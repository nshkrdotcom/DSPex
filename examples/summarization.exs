# Summarization Example
#
# Run with: mix run --no-start examples/summarization.exs

DSPex.run(fn ->
  IO.puts("DSPex Summarization Example")
  IO.puts("============================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  summarizer = DSPex.predict!("text -> summary")

  text = """
  Elixir is a dynamic, functional language for building scalable and maintainable
  applications. Elixir runs on the Erlang VM, known for creating low-latency,
  distributed, and fault-tolerant systems. These capabilities and Elixir tooling
  allow developers to be productive in several domains, such as web development,
  embedded software, machine learning, data pipelines, and multimedia processing.
  """

  IO.puts("Original text:")
  IO.puts(String.trim(text))
  IO.puts("")

  result = DSPex.method!(summarizer, "forward", [], text: text)
  summary = DSPex.attr!(result, "summary")

  IO.puts("Summary: #{summary}")
  IO.puts("\nDone!")
end)

# Summarization Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/summarization.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Summarization Example")
  IO.puts("============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, summarizer} = Dspy.PredictClass.new("text -> summary", [])

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

  {:ok, result} = Dspy.PredictClass.forward(summarizer, text: text)
  {:ok, summary} = SnakeBridge.attr(result, "summary")

  IO.puts("Summary: #{summary}")
  IO.puts("\nDone!")
end)

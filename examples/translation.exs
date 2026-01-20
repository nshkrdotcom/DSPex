# Translation Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/translation.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Translation Example")
  IO.puts("==========================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, translator} = Dspy.PredictClass.new("text, target_language -> translation", [])

  phrases = [
    {"Hello, how are you?", "Spanish"},
    {"The weather is beautiful today.", "French"},
    {"I love programming in Elixir.", "Japanese"}
  ]

  for {text, lang} <- phrases do
    {:ok, result} = Dspy.PredictClass.forward(translator, text: text, target_language: lang)
    {:ok, translation} = SnakeBridge.attr(result, "translation")
    IO.puts("#{text}")
    IO.puts("  -> [#{lang}] #{translation}\n")
  end

  IO.puts("Done!")
end)

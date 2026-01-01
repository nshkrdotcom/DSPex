# Translation Example
#
# Run with: mix run examples/translation.exs

DSPex.run(fn ->
  IO.puts("DSPex Translation Example")
  IO.puts("==========================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  translator = DSPex.predict!("text, target_language -> translation")

  phrases = [
    {"Hello, how are you?", "Spanish"},
    {"The weather is beautiful today.", "French"},
    {"I love programming in Elixir.", "Japanese"}
  ]

  for {text, lang} <- phrases do
    result = DSPex.method!(translator, "forward", [], text: text, target_language: lang)
    translation = DSPex.attr!(result, "translation")
    IO.puts("#{text}")
    IO.puts("  -> [#{lang}] #{translation}\n")
  end

  IO.puts("Done!")
end)

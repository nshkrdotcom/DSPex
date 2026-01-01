# Direct LM Call Example
#
# Run with: mix run examples/direct_lm_call.exs

DSPex.run(fn ->
  IO.puts("DSPex Direct LM Call Example")
  IO.puts("==============================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini", temperature: 0.9)

  # Call LM directly (not through a module)
  messages = [
    %{"role" => "user", "content" => "Tell me a one-line joke about programming."}
  ]

  IO.puts("Calling LM directly with messages...\n")

  # Direct call returns list of completions
  completions = DSPex.method!(lm, "__call__", [], messages: messages)

  # Get first completion
  first = Enum.at(completions, 0)
  IO.puts("Response: #{first}\n")

  # Another direct call
  messages2 = [
    %{"role" => "user", "content" => "What's 2+2? Reply with just the number."}
  ]

  completions2 = DSPex.method!(lm, "__call__", [], messages: messages2)
  IO.puts("2+2 = #{Enum.at(completions2, 0)}")

  IO.puts("\nDone!")
end)

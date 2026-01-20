# Direct LM Call Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/direct_lm_call.exs

Snakepit.run_as_script(fn ->
  Application.ensure_all_started(:snakebridge)

  IO.puts("DSPex Direct LM Call Example")
  IO.puts("==============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [], temperature: 0.9)

  # Call LM directly (not through a module)
  messages = [
    %{"role" => "user", "content" => "Tell me a one-line joke about programming."}
  ]

  IO.puts("Calling LM directly with messages...\n")

  # Direct call returns list of completions
  {:ok, completions} = Dspy.LM.call(lm, [], messages: messages)

  # Get first completion
  first = Enum.at(completions, 0)
  IO.puts("Response: #{first}\n")

  # Another direct call
  messages2 = [
    %{"role" => "user", "content" => "What's 2+2? Reply with just the number."}
  ]

  {:ok, completions2} = Dspy.LM.call(lm, [], messages: messages2)
  IO.puts("2+2 = #{Enum.at(completions2, 0)}")

  IO.puts("\nDone!")
end)

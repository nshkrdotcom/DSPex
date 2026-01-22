# Code Generation Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/code_gen.exs

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Code Generation Example")
  IO.puts("===============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, coder} = Dspy.ChainOfThought.new("task, language -> code", [])

  tasks = [
    {"Write a function to check if a number is prime", "Python"},
    {"Write a function to reverse a string", "Elixir"}
  ]

  for {task, lang} <- tasks do
    IO.puts("Task: #{task} (#{lang})")
    {:ok, result} = Dspy.ChainOfThought.forward(coder, task: task, language: lang)
    {:ok, reasoning} = SnakeBridge.attr(result, "reasoning")
    {:ok, code} = SnakeBridge.attr(result, "code")
    IO.puts("Reasoning: #{String.slice(reasoning, 0..100)}...")
    IO.puts("Code:\n#{code}\n")
  end

  IO.puts("Done!")
end

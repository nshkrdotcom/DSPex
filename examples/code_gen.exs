# Code Generation Example
#
# Run with: mix run examples/code_gen.exs

DSPex.run(fn ->
  IO.puts("DSPex Code Generation Example")
  IO.puts("===============================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  coder = DSPex.chain_of_thought!("task, language -> code")

  tasks = [
    {"Write a function to check if a number is prime", "Python"},
    {"Write a function to reverse a string", "Elixir"}
  ]

  for {task, lang} <- tasks do
    IO.puts("Task: #{task} (#{lang})")
    result = DSPex.method!(coder, "forward", [], task: task, language: lang)
    reasoning = DSPex.attr!(result, "reasoning")
    code = DSPex.attr!(result, "code")
    IO.puts("Reasoning: #{String.slice(reasoning, 0..100)}...")
    IO.puts("Code:\n#{code}\n")
  end

  IO.puts("Done!")
end)

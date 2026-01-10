# Optimization Example (BootstrapFewShot)
#
# Run with: mix run examples/optimization.exs
#
# Requires: OPENAI_API_KEY environment variable

DSPex.run(fn ->
  IO.puts("DSPex Optimization Example")
  IO.puts("==========================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  student = DSPex.predict!("question -> answer")

  build_example = fn question, answer ->
    example = DSPex.call!("dspy", "Example", [], question: question, answer: answer)
    DSPex.method!(example, "with_inputs", ["question"])
  end

  trainset = [
    build_example.("What is 2 + 2?", "4"),
    build_example.("What is the capital of France?", "Paris"),
    build_example.("What color do you get by mixing blue and yellow?", "Green")
  ]

  optimizer = DSPex.call!("dspy", "BootstrapFewShot", [])

  # Some DSPy optimizers accept a metric argument. If needed, pass `metric:` here.
  optimized = DSPex.method!(optimizer, "compile", [student], trainset: trainset)

  question = "What is the capital of Italy?"
  result = DSPex.method!(optimized, "forward", [], question: question)
  answer = DSPex.attr!(result, "answer")

  IO.puts("Question: #{question}")
  IO.puts("Answer: #{answer}\n")
  IO.puts("Done!")
end)

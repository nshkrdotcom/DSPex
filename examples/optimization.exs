# Optimization Example (BootstrapFewShot)
#
# Run with: mix run --no-start examples/optimization.exs
#
# Requires: GEMINI_API_KEY environment variable

DSPex.run(fn ->
  IO.puts("DSPex Optimization Example")
  IO.puts("==========================\n")

  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)

  student = DSPex.predict!("question -> answer")

  build_example = fn question, answer ->
    {:ok, example} = Dspy.Example.new([], question: question, answer: answer)
    {:ok, example} = Dspy.Example.with_inputs(example, ["question"])
    example
  end

  trainset = [
    build_example.("What is 2 + 2?", "4"),
    build_example.("What is the capital of France?", "Paris"),
    build_example.("What color do you get by mixing blue and yellow?", "Green")
  ]

  {:ok, optimizer} = Dspy.BootstrapFewShot.new([])

  # Some DSPy optimizers accept a metric argument. If needed, pass `metric:` here.
  {:ok, optimized} = Dspy.BootstrapFewShot.compile(optimizer, student, trainset: trainset)

  question = "What is the capital of Italy?"
  result = DSPex.method!(optimized, "forward", [], question: question)
  answer = DSPex.attr!(result, "answer")

  IO.puts("Question: #{question}")
  IO.puts("Answer: #{answer}\n")
  IO.puts("Done!")
end)

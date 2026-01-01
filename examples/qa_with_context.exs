# Q&A with Context Example
#
# Run with: mix run examples/qa_with_context.exs

DSPex.run(fn ->
  IO.puts("DSPex Q&A with Context Example")
  IO.puts("================================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  qa = DSPex.predict!("context, question -> answer")

  context = """
  The Erlang programming language was created by Joe Armstrong, Robert Virding,
  and Mike Williams at Ericsson in 1986. It was designed for building concurrent,
  distributed, and fault-tolerant systems. The name comes from Danish mathematician
  Agner Krarup Erlang. Elixir, created by José Valim in 2011, runs on the Erlang VM
  and brings modern syntax and tooling while maintaining Erlang's strengths.
  """

  questions = [
    "Who created Erlang?",
    "When was Elixir created?",
    "What is Erlang designed for?"
  ]

  IO.puts("Context: #{String.slice(context, 0..100)}...\n")

  for question <- questions do
    result = DSPex.method!(qa, "forward", [], context: context, question: question)
    answer = DSPex.attr!(result, "answer")
    IO.puts("Q: #{question}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end)

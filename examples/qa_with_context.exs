# Q&A with Context Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/qa_with_context.exs

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Q&A with Context Example")
  IO.puts("================================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  {:ok, qa} = Dspy.PredictClass.new("context, question -> answer", [])

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
    {:ok, result} = Dspy.PredictClass.forward(qa, context: context, question: question)
    {:ok, answer} = SnakeBridge.attr(result, "answer")
    IO.puts("Q: #{question}")
    IO.puts("A: #{answer}\n")
  end

  IO.puts("Done!")
end

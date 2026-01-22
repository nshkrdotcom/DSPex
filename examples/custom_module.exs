# Custom Module Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/custom_module.exs
#
# Requires: GEMINI_API_KEY environment variable

require SnakeBridge

defmodule CustomQA do
  def new do
    {:ok, extract} = Dspy.PredictClass.new("question -> keywords", [])
    {:ok, answer} = Dspy.PredictClass.new("question, keywords -> answer", [])
    %{extract: extract, answer: answer}
  end

  def forward(%{extract: extract, answer: answer}, question) do
    {:ok, keywords_result} = Dspy.PredictClass.forward(extract, question: question)
    {:ok, keywords} = SnakeBridge.attr(keywords_result, "keywords")

    {:ok, answer_result} =
      Dspy.PredictClass.forward(answer, question: question, keywords: keywords)

    {:ok, final_answer} = SnakeBridge.attr(answer_result, "answer")

    {keywords, final_answer}
  end
end

SnakeBridge.script do
  IO.puts("DSPex Custom Module Example")
  IO.puts("===========================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  qa = CustomQA.new()
  question = "How does Elixir build on Erlang's concurrency model?"

  {keywords, answer} = CustomQA.forward(qa, question)

  IO.puts("Question: #{question}")
  IO.puts("Keywords: #{inspect(keywords)}")
  IO.puts("Answer: #{answer}\n")
  IO.puts("Done!")
end

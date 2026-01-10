# Custom Module Example
#
# Run with: mix run examples/custom_module.exs
#
# Requires: OPENAI_API_KEY environment variable

defmodule CustomQA do
  def new do
    %{
      extract: DSPex.predict!("question -> keywords"),
      answer: DSPex.predict!("question, keywords -> answer")
    }
  end

  def forward(%{extract: extract, answer: answer}, question) do
    keywords_result = DSPex.method!(extract, "forward", [], question: question)
    keywords = DSPex.attr!(keywords_result, "keywords")

    answer_result =
      DSPex.method!(answer, "forward", [], question: question, keywords: keywords)

    {keywords, DSPex.attr!(answer_result, "answer")}
  end
end

DSPex.run(fn ->
  IO.puts("DSPex Custom Module Example")
  IO.puts("===========================\n")

  lm = DSPex.lm!("openai/gpt-4o-mini")
  DSPex.configure!(lm: lm)

  qa = CustomQA.new()
  question = "How does Elixir build on Erlang's concurrency model?"

  {keywords, answer} = CustomQA.forward(qa, question)

  IO.puts("Question: #{question}")
  IO.puts("Keywords: #{inspect(keywords)}")
  IO.puts("Answer: #{answer}\n")
  IO.puts("Done!")
end)

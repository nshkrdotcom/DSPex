# Retrieval-Augmented Generation (RAG) Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/rag.exs
#
# Requires: GEMINI_API_KEY environment variable

require SnakeBridge

defmodule SimpleRetriever do
  def retrieve(docs, query, k) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)

    docs
    |> Enum.map(&score_doc(&1, terms))
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(k)
  end

  defp score_doc(%{text: text} = doc, terms) do
    text = String.downcase(text)
    score = Enum.count(terms, &String.contains?(text, &1))
    Map.put(doc, :score, score)
  end
end

SnakeBridge.script do
  IO.puts("DSPex RAG Example")
  IO.puts("=================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)

  docs = [
    %{
      title: "Erlang Origins",
      text:
        "Erlang was created at Ericsson in 1986 by Joe Armstrong, Robert Virding, and Mike Williams."
    },
    %{
      title: "Elixir Timeline",
      text:
        "Elixir was created by Jose Valim and released publicly in 2011, running on the Erlang VM."
    },
    %{
      title: "BEAM Overview",
      text:
        "The BEAM virtual machine powers Erlang and Elixir, offering concurrency, fault tolerance, and distribution."
    }
  ]

  question = "Who created Elixir and what does it run on?"
  top_docs = SimpleRetriever.retrieve(docs, question, 2)

  context =
    Enum.map_join(top_docs, "\n\n", &"[#{&1.title}] #{&1.text}")

  {:ok, rag} = Dspy.PredictClass.new("context, question -> answer", [])
  {:ok, result} = Dspy.PredictClass.forward(rag, context: context, question: question)
  {:ok, answer} = SnakeBridge.attr(result, "answer")

  IO.puts("Question: #{question}\n")
  IO.puts("Retrieved context:\n#{context}\n")
  IO.puts("Answer: #{answer}\n")
  IO.puts("Done!")
end

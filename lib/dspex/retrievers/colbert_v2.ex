defmodule DSPex.Retrievers.ColBERTv2 do
  @moduledoc """
  ColBERTv2 retrieval module for dense passage retrieval.

  Provides efficient multi-vector retrieval using the ColBERTv2 architecture.
  Requires a pre-built ColBERTv2 index.
  """

  alias DSPex.Utils.ID

  @doc """
  Initialize a ColBERTv2 retriever with an index.

  ## Examples

      {:ok, retriever} = DSPex.Retrievers.ColBERTv2.init(
        index_path: "/path/to/colbert/index",
        index_name: "my_index"
      )
      
      {:ok, results} = DSPex.Retrievers.ColBERTv2.search(
        retriever,
        "What is machine learning?",
        k: 10
      )
  """
  def init(opts \\ []) do
    id = opts[:store_as] || ID.generate("colbert")

    config = %{
      url: opts[:url] || "http://0.0.0.0:8893/api/search",
      port: opts[:port],
      index_root: opts[:index_root],
      index_name: opts[:index_name],
      index_path: opts[:index_path]
    }

    case Snakepit.Python.call(
           "dspy.ColBERTv2",
           config,
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Search for passages using ColBERTv2.

  Returns a list of retrieved passages with scores.
  """
  def search(retriever_id, query, opts \\ []) do
    k = opts[:k] || 10

    Snakepit.Python.call(
      "stored.#{retriever_id}.__call__",
      %{query: query, k: k},
      opts
    )
  end

  @doc """
  Search with additional filtering or metadata.
  """
  def search_with_filter(retriever_id, query, filter_fn, opts \\ []) do
    # Note: Filter function needs to be registered on Python side
    k = opts[:k] || 10

    Snakepit.Python.call(
      "stored.#{retriever_id}.search_with_filter",
      %{query: query, k: k, filter: filter_fn},
      opts
    )
  end
end

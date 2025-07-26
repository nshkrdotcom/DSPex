defmodule DSPex.Retrieve do
  @moduledoc """
  High-level wrapper for document retrieval functionality.
  
  This module provides a simplified API for retrieval operations,
  supporting various backends for document search and
  retrieval-augmented generation (RAG).
  
  ## Examples
  
      # Simple usage
      {:ok, docs} = DSPex.Retrieve.search(
        "What is machine learning?",
        backend: "colbertv2",
        k: 5
      )
      
      # With session
      {:ok, session} = DSPex.Session.new()
      {:ok, retriever} = DSPex.Retrieve.new(
        k: 10,
        backend: "elasticsearch",
        session: session
      )
      {:ok, docs} = DSPex.Retrieve.retrieve(retriever, "climate change effects")
      
      # Access results
      Enum.each(docs, fn doc ->
        IO.puts("Score: #{doc.score}")
        IO.puts("Text: #{doc.text}")
        IO.puts("Metadata: #{inspect(doc.metadata)}")
      end)
  """
  
  alias DSPex.Modules.ContractBased.Retrieve, as: ContractImpl
  
  @doc """
  Create a new Retrieve instance.
  
  ## Options
  
  - `:k` - Number of documents to retrieve (default: 5)
  - `:backend` - Retrieval backend to use
  - `:session` - DSPex.Session to use for this instance
  - `:index_name` - Name of the index to search
  - `:api_key` - API key for the backend service
  - `:endpoint` - Backend service endpoint
  """
  defdelegate new(k \\ 5, opts \\ []), to: ContractImpl
  
  @doc """
  Retrieve documents for a query.
  
  Takes an instance created with `new/2` and a query string.
  """
  def retrieve(retriever_ref, query, opts \\ []) when is_binary(query) do
    ContractImpl.retrieve(retriever_ref, %{query: query}, opts)
  end
  
  @doc """
  Create a Retrieve instance (contract-based API).
  
  ## Parameters
  
  - `params` - Map with optional `:k`, `:backend`, and configuration
  - `opts` - Additional options
  """
  defdelegate create(params, opts \\ []), to: ContractImpl
  
  @doc """
  Retrieve documents (contract-based API).
  
  Takes an instance and query parameters.
  """
  defdelegate retrieve(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  One-shot document retrieval.
  
  Combines creation and retrieval in a single call.
  
  ## Examples
  
      {:ok, docs} = DSPex.Retrieve.search(
        "quantum computing applications",
        backend: "pinecone",
        k: 10
      )
      
      {:ok, docs} = DSPex.Retrieve.search(
        "Elixir programming",
        backend: "elasticsearch",
        k: 5,
        filters: %{category: "tutorial"}
      )
  """
  def search(query, opts \\ []) when is_binary(query) do
    create_params = %{
      k: opts[:k] || 5,
      backend: opts[:backend],
      retriever: opts[:retriever],
      index_name: opts[:index_name],
      api_key: opts[:api_key],
      endpoint: opts[:endpoint]
    }
    
    retrieve_params = %{
      query: query,
      k: opts[:override_k]
    }
    
    ContractImpl.call(create_params, retrieve_params, opts)
  end
  
  @doc """
  Create and retrieve in one call.
  """
  defdelegate call(create_params, retrieve_params, opts \\ []), to: ContractImpl
  
  @doc """
  Search with custom parameters.
  """
  defdelegate search(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Legacy call method for compatibility.
  """
  defdelegate __call__(retriever_ref, query, opts \\ []), to: ContractImpl
  
  @doc """
  Batch retrieval for multiple queries.
  """
  defdelegate batch_retrieve(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Add documents to the index.
  """
  defdelegate add_documents(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Add documents (convenience wrapper).
  """
  defdelegate add_docs(retriever_ref, documents, opts \\ []), to: ContractImpl
  
  @doc """
  Remove documents from the index.
  """
  defdelegate remove_documents(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Remove documents (convenience wrapper).
  """
  defdelegate remove_docs(retriever_ref, ids, opts \\ []), to: ContractImpl
  
  @doc """
  Update a document in the index.
  """
  defdelegate update_document(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Update document (convenience wrapper).
  """
  defdelegate update_doc(retriever_ref, id, document, opts \\ []), to: ContractImpl
  
  @doc """
  Clear all documents from the index.
  """
  defdelegate clear_index(retriever_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Get index statistics.
  """
  defdelegate get_index_stats(retriever_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Get retrieval metrics.
  """
  defdelegate get_metrics(retriever_ref, opts \\ []), to: ContractImpl
  
  @doc """
  Configure reranking.
  """
  defdelegate configure_reranking(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Set similarity threshold.
  """
  defdelegate set_similarity_threshold(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Forward pass with raw parameters.
  """
  defdelegate forward(retriever_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Create a filter function.
  
  ## Examples
  
      filter = DSPex.Retrieve.make_filter(
        min_score: 0.8,
        required_metadata: [:source, :date],
        exclude_sources: ["unreliable.com"]
      )
  """
  defdelegate make_filter(criteria), to: ContractImpl
  
  @doc """
  Set a custom scoring function.
  """
  defdelegate set_custom_scorer(retriever_ref, scorer_fn, opts \\ []), to: ContractImpl
  
  @doc """
  Enable query expansion.
  """
  defdelegate enable_query_expansion(retriever_ref, opts \\ []), to: ContractImpl
  
  @doc """
  Apply custom document transformation.
  """
  defdelegate with_doc_transform(retriever_ref, transform_fn, opts \\ []), to: ContractImpl
  
  @doc """
  Enable caching for repeated queries.
  """
  defdelegate enable_cache(retriever_ref, cache_opts \\ [], opts \\ []), to: ContractImpl
end
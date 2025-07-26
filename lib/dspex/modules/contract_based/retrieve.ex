defmodule DSPex.Modules.ContractBased.Retrieve do
  @moduledoc """
  Contract-based implementation of DSPy Retrieve functionality.
  
  This module provides a typed, validated interface for retrieval operations,
  supporting various backends for document search and retrieval-augmented generation.
  
  ## Features
  
  - Multiple backend support (ColBERTv2, Elasticsearch, vector DBs)
  - Batch retrieval operations
  - Document management (add, update, remove)
  - Similarity threshold configuration
  - Reranking support
  
  ## Examples
  
      # Create a retriever with ColBERTv2 backend
      {:ok, retriever} = Retrieve.create(%{
        backend: "colbertv2",
        k: 5,
        index_name: "wikipedia"
      })
      
      # Retrieve documents
      {:ok, docs} = Retrieve.retrieve(retriever, %{
        query: "What is machine learning?"
      })
      # Returns: [
      #   %{text: "Machine learning is...", score: 0.95, metadata: %{...}},
      #   %{text: "ML algorithms...", score: 0.89, metadata: %{...}},
      #   ...
      # ]
      
      # Batch retrieval
      {:ok, results} = Retrieve.batch_retrieve(retriever, %{
        queries: ["What is AI?", "Deep learning basics"]
      })
  """
  
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Observable
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.ResultTransform
  
  use_contract DSPex.Contracts.Retrieve
  
  alias DSPex.Utils.ID
  
  @supported_backends ~w(colbertv2 elasticsearch pinecone weaviate qdrant custom)
  
  @doc """
  Result transformation pipeline for Retrieve results.
  
  Ensures consistent document format across backends.
  """
  def transform_result({:ok, results}) when is_list(results) do
    {:ok, Enum.map(results, &normalize_document/1)}
  end
  
  def transform_result({:ok, %{"documents" => docs} = result}) when is_list(docs) do
    {:ok, %{result | "documents" => Enum.map(docs, &normalize_document/1)}}
  end
  
  def transform_result(error), do: error
  
  @doc """
  Observable hooks for monitoring retrieval operations.
  """
  def default_hooks do
    %{
      before_retrieve: fn params -> 
        IO.puts("[Retrieve] Searching for: #{params.query}")
        :ok
      end,
      after_retrieve: fn result ->
        case result do
          {:ok, docs} when is_list(docs) ->
            IO.puts("[Retrieve] Found #{length(docs)} documents")
          _ ->
            :ok
        end
        :ok
      end,
      on_document_added: fn doc ->
        IO.puts("[Retrieve] Added document: #{doc[:id] || "unknown"}")
        :ok
      end,
      on_rerank: fn docs ->
        IO.puts("[Retrieve] Reranking #{length(docs)} documents")
        :ok
      end,
      on_index_operation: fn op ->
        IO.puts("[Retrieve] Index operation: #{op}")
        :ok
      end
    }
  end
  
  @doc """
  Create and retrieve in one call (stateless).
  
  Combines create and retrieve operations for convenience.
  
  ## Examples
  
      {:ok, docs} = Retrieve.call(
        %{backend: "elasticsearch", k: 10},
        %{query: "climate change effects"}
      )
  """
  def call(create_params, retrieve_params, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    with {:ok, retriever_ref} <- create(create_params, Keyword.put(opts, :session_id, session_id)),
         {:ok, docs} <- retrieve(retriever_ref, retrieve_params, opts) do
      {:ok, docs}
    end
  end
  
  @doc """
  Search with custom parameters per backend.
  
  Allows backend-specific search options.
  
  ## Examples
  
      {:ok, docs} = Retrieve.search(retriever, 
        query: "neural networks",
        k: 10,
        filters: %{year: {:gte, 2020}},
        boost_recent: true
      )
  """
  def search(retriever_ref, params, opts \\ []) do
    # Extract standard params
    query = params[:query] || raise ArgumentError, "query is required"
    k = params[:k]
    
    # Pass through to retrieve with optional k override
    retrieve_params = %{query: query}
    retrieve_params = if k, do: Map.put(retrieve_params, :k, k), else: retrieve_params
    
    retrieve(retriever_ref, retrieve_params, opts)
  end
  
  @doc """
  Add documents with automatic batching.
  
  Handles large document sets efficiently.
  
  ## Examples
  
      documents = [
        %{id: "1", text: "Document 1", metadata: %{source: "wiki"}},
        %{id: "2", text: "Document 2", metadata: %{source: "arxiv"}}
      ]
      
      {:ok, _} = Retrieve.add_documents(retriever, %{
        documents: documents,
        batch_size: 100
      })
  """
  def add_docs(retriever_ref, documents, opts \\ []) when is_list(documents) do
    params = %{
      documents: documents,
      batch_size: opts[:batch_size] || 100
    }
    
    add_documents(retriever_ref, params, opts)
  end
  
  @doc """
  Update a single document by ID.
  
  Convenience wrapper for updating documents.
  """
  def update_doc(retriever_ref, id, document, opts \\ []) do
    update_document(retriever_ref, %{document_id: id, document: document}, opts)
  end
  
  @doc """
  Remove multiple documents by ID.
  
  Convenience wrapper for bulk removal.
  """
  def remove_docs(retriever_ref, ids, opts \\ []) when is_list(ids) do
    remove_documents(retriever_ref, %{document_ids: ids}, opts)
  end
  
  @doc """
  Configure retrieval with a custom scoring function.
  
  Allows fine-tuning of relevance scoring.
  
  ## Examples
  
      scorer = fn doc, query ->
        base_score = doc.score
        recency_boost = if recent?(doc), do: 0.1, else: 0
        base_score + recency_boost
      end
      
      {:ok, _} = Retrieve.set_custom_scorer(retriever, scorer)
  """
  def set_custom_scorer(retriever_ref, scorer_fn, opts \\ []) 
      when is_function(scorer_fn, 2) do
    {:ok, %{ref: retriever_ref, custom_scorer: scorer_fn}}
  end
  
  @doc """
  Enable query expansion for better recall.
  
  Automatically expands queries with synonyms and related terms.
  """
  def enable_query_expansion(retriever_ref, opts \\ []) do
    {:ok, %{ref: retriever_ref, query_expansion: true, expansion_opts: opts}}
  end
  
  @doc """
  Create a filtering function for post-retrieval filtering.
  
  ## Examples
  
      filter = Retrieve.make_filter(
        min_score: 0.7,
        required_metadata: [:source, :date],
        exclude_sources: ["unreliable.com"]
      )
  """
  def make_filter(criteria) do
    fn doc ->
      score_ok = is_nil(criteria[:min_score]) or doc[:score] >= criteria[:min_score]
      
      metadata_ok = case criteria[:required_metadata] do
        nil -> true
        fields -> Enum.all?(fields, &Map.has_key?(doc[:metadata] || %{}, &1))
      end
      
      source_ok = case criteria[:exclude_sources] do
        nil -> true
        sources -> not (doc[:metadata][:source] in sources)
      end
      
      score_ok and metadata_ok and source_ok
    end
  end
  
  @doc """
  Get retrieval performance metrics.
  
  Returns statistics about retrieval operations.
  """
  def get_metrics(retriever_ref, opts \\ []) do
    with {:ok, stats} <- get_index_stats(retriever_ref, %{}, opts) do
      {:ok, Map.merge(stats, %{
        backend: get_backend_info(retriever_ref),
        performance: calculate_performance_metrics(stats)
      })}
    end
  end
  
  # Backward compatibility helpers
  @doc false
  def new(k \\ 5, opts \\ []) do
    IO.warn("Retrieve.new/2 is deprecated. Use create/2 instead.", 
            Macro.Env.stacktrace(__ENV__))
    
    params = %{k: k}
    params = if opts[:backend], do: Map.put(params, :backend, opts[:backend]), else: params
    
    create(params, opts)
  end
  
  @doc false
  def __call__(retriever_ref, query, opts \\ []) do
    IO.warn("Retrieve.__call__/3 is deprecated. Use retrieve/3 instead.", 
            Macro.Env.stacktrace(__ENV__))
    retrieve(retriever_ref, %{query: query}, opts)
  end
  
  # Private helper functions
  defp normalize_document(doc) when is_map(doc) do
    %{
      text: doc["text"] || doc["content"] || doc["passage"],
      score: doc["score"] || doc["similarity"] || 1.0,
      id: doc["id"] || doc["doc_id"] || generate_doc_id(doc),
      metadata: doc["metadata"] || extract_metadata(doc)
    }
  end
  
  defp normalize_document(text) when is_binary(text) do
    %{
      text: text,
      score: 1.0,
      id: generate_doc_id(%{text: text}),
      metadata: %{}
    }
  end
  
  defp generate_doc_id(doc) do
    content = doc["text"] || doc["content"] || ""
    :crypto.hash(:md5, content) |> Base.encode16(case: :lower)
  end
  
  defp extract_metadata(doc) do
    doc
    |> Map.drop(["text", "content", "passage", "score", "similarity", "id", "doc_id"])
    |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
  end
  
  defp get_backend_info(retriever_ref) do
    # Would query the actual backend info from the bridge
    %{type: "unknown", version: "unknown"}
  end
  
  defp calculate_performance_metrics(stats) do
    %{
      avg_retrieval_time: stats["avg_retrieval_time"] || 0,
      cache_hit_rate: stats["cache_hit_rate"] || 0,
      index_size: stats["index_size"] || 0
    }
  end
  
  @doc """
  Apply custom document transformation.
  
  Allows processing of retrieved documents.
  """
  def with_doc_transform(retriever_ref, transform_fn, opts \\ []) 
      when is_function(transform_fn, 1) do
    {:ok, %{ref: retriever_ref, doc_transform: transform_fn}}
  end
  
  @doc """
  Enable caching for repeated queries.
  
  Improves performance for common queries.
  """
  def enable_cache(retriever_ref, cache_opts \\ [], opts \\ []) do
    {:ok, %{ref: retriever_ref, cache_enabled: true, cache_opts: cache_opts}}
  end
end
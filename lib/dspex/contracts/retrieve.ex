defmodule DSPex.Contracts.Retrieve do
  @moduledoc """
  Contract for DSPy Retrieve functionality.
  
  Defines the interface for retrieval operations that search through
  document collections, vector databases, or other data sources.
  This is a key component for Retrieval-Augmented Generation (RAG).
  
  ## Usage
  
  Retrieve modules connect to various retrieval backends:
  - ColBERTv2 for dense retrieval
  - Elasticsearch for keyword search
  - Pinecone, Weaviate, or Qdrant for vector search
  - Custom retrieval systems
  """
  
  @python_class "dspy.Retrieve"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      k: {:optional, :integer, 5},
      retriever: {:optional, :reference, nil},
      backend: {:optional, :string, "colbertv2"},
      index_name: {:optional, :string, nil},
      api_key: {:optional, :string, nil},
      endpoint: {:optional, :string, nil}
    ],
    returns: :reference,
    description: "Create a new Retrieve instance with the specified configuration"
    
  defmethod :retrieve, :__call__,
    params: [
      query: {:required, :string},
      k: {:optional, :integer, nil}
    ],
    returns: {:list, :map},
    description: "Retrieve k most relevant documents for the query"
    
  defmethod :forward, :forward,
    params: [
      query: {:required, :string},
      k: {:optional, :integer, nil}
    ],
    returns: :map,
    description: "Forward pass returning structured retrieval results"
    
  defmethod :batch_retrieve, :batch_retrieve,
    params: [
      queries: {:required, {:list, :string}},
      k: {:optional, :integer, nil}
    ],
    returns: {:list, {:list, :map}},
    description: "Retrieve documents for multiple queries in batch"
    
  defmethod :add_documents, :add_documents,
    params: [
      documents: {:required, {:list, :map}},
      batch_size: {:optional, :integer, 100}
    ],
    returns: :map,
    description: "Add documents to the retrieval index"
    
  defmethod :remove_documents, :remove_documents,
    params: [
      document_ids: {:required, {:list, :string}}
    ],
    returns: :map,
    description: "Remove documents from the retrieval index by ID"
    
  defmethod :update_document, :update_document,
    params: [
      document_id: {:required, :string},
      document: {:required, :map}
    ],
    returns: :map,
    description: "Update a document in the retrieval index"
    
  defmethod :clear_index, :clear_index,
    params: [],
    returns: :map,
    description: "Clear all documents from the retrieval index"
    
  defmethod :get_index_stats, :get_index_stats,
    params: [],
    returns: :map,
    description: "Get statistics about the retrieval index"
    
  defmethod :configure_reranking, :configure_reranking,
    params: [
      reranker: {:optional, :string, nil},
      rerank_k: {:optional, :integer, nil}
    ],
    returns: :map,
    description: "Configure reranking for retrieved results"
    
  defmethod :set_similarity_threshold, :set_similarity_threshold,
    params: [
      threshold: {:required, :float}
    ],
    returns: :map,
    description: "Set minimum similarity threshold for retrieved documents"
end
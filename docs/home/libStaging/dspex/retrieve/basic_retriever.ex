defmodule DSPEx.Retrieve.BasicRetriever do
  @moduledoc """
  Basic retrieval system for DSPEx.

  This module provides a simple document retrieval system based on semantic
  similarity using embeddings. It allows you to create a retriever with a
  collection of documents and then query for the most relevant documents.

  ## Usage

      # Create a retriever with documents
      documents = [
        "The cat sat on the mat",
        "Dogs are loyal companions",
        "Birds can fly in the sky"
      ]
      retriever = BasicRetriever.new(documents, model: :text_embedding_ada_002)
      
      # Retrieve relevant documents
      {:ok, results} = BasicRetriever.retrieve(retriever, "feline pets", top_k: 2)
      
      # Add more documents
      updated_retriever = BasicRetriever.add_documents(retriever, ["More documents"])

  ## Features

  - Semantic similarity search using embeddings
  - Configurable similarity thresholds
  - Support for different embedding models
  - Document addition and management
  """

  alias DSPEx.Retrieve.Embeddings

  defstruct [:documents, :model, :embeddings]

  @type t :: %__MODULE__{
          documents: [String.t()],
          model: atom(),
          embeddings: [[float()]] | nil
        }

  @doc """
  Create a new BasicRetriever with a collection of documents.

  ## Parameters

  - `documents` - List of documents (strings) to index
  - `opts` - Options including the embedding model

  ## Returns

  A BasicRetriever struct ready for querying.

  ## Raises

  ArgumentError if documents is empty or contains non-string elements.
  """
  @spec new([String.t()], keyword()) :: t()
  def new(documents, opts \\ [])

  def new([], _opts) do
    raise ArgumentError, "Documents list cannot be empty"
  end

  def new(documents, opts) when is_list(documents) do
    unless Enum.all?(documents, &is_binary/1) do
      raise ArgumentError, "All documents must be strings"
    end

    model = Keyword.get(opts, :model, :text_embedding_ada_002)

    %__MODULE__{
      documents: documents,
      model: model,
      # Lazy computation - embeddings generated on first use
      embeddings: nil
    }
  end

  def new(_documents, _opts) do
    raise ArgumentError, "Documents must be a list"
  end

  @doc """
  Retrieve the most relevant documents for a query.

  ## Parameters

  - `retriever` - The BasicRetriever struct
  - `query` - Query string to search for
  - `opts` - Options including top_k and similarity_threshold

  ## Returns

  `{:ok, results}` where results is a list of `{document, score}` tuples sorted by relevance.
  """
  @spec retrieve(t(), String.t(), keyword()) ::
          {:ok, [{String.t(), float()}]} | {:error, String.t()}
  def retrieve(retriever, query, opts \\ [])

  def retrieve(%__MODULE__{} = retriever, query, opts) when is_binary(query) do
    # Ensure embeddings are computed
    retriever_with_embeddings = ensure_embeddings(retriever)

    top_k = Keyword.get(opts, :top_k, 10)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, 0.0)

    # Use the semantic search functionality from Embeddings module
    Embeddings.semantic_search(
      query,
      retriever_with_embeddings.documents,
      model: retriever_with_embeddings.model,
      top_k: top_k,
      similarity_threshold: similarity_threshold
    )
  end

  def retrieve(_retriever, _query, _opts) do
    {:error, "Query must be a string"}
  end

  @doc """
  Add new documents to the retriever.

  ## Parameters

  - `retriever` - The BasicRetriever struct
  - `new_documents` - List of new documents to add

  ## Returns

  Updated BasicRetriever struct with new documents added.

  ## Raises

  ArgumentError if new_documents contains non-string elements.
  """
  @spec add_documents(t(), [String.t()]) :: t()
  def add_documents(%__MODULE__{} = retriever, new_documents) when is_list(new_documents) do
    unless Enum.all?(new_documents, &is_binary/1) do
      raise ArgumentError, "All new documents must be strings"
    end

    updated_documents = retriever.documents ++ new_documents

    %{
      retriever
      | documents: updated_documents,
        # Reset embeddings so they're recomputed with new documents
        embeddings: nil
    }
  end

  def add_documents(_retriever, _new_documents) do
    raise ArgumentError, "New documents must be a list"
  end

  @doc """
  Get the number of documents in the retriever.

  ## Parameters

  - `retriever` - The BasicRetriever struct

  ## Returns

  Number of documents in the retriever.
  """
  @spec document_count(t()) :: non_neg_integer()
  def document_count(%__MODULE__{documents: documents}) do
    length(documents)
  end

  @doc """
  Get information about the retriever.

  ## Parameters

  - `retriever` - The BasicRetriever struct

  ## Returns

  Map with retriever information.
  """
  @spec info(t()) :: map()
  def info(%__MODULE__{} = retriever) do
    %{
      document_count: document_count(retriever),
      model: retriever.model,
      embeddings_computed: retriever.embeddings != nil
    }
  end

  # Private helper functions

  # Ensure embeddings are computed for all documents
  defp ensure_embeddings(%__MODULE__{embeddings: nil} = retriever) do
    {:ok, embeddings} = Embeddings.batch_embed(retriever.documents, model: retriever.model)
    %{retriever | embeddings: embeddings}
  end

  defp ensure_embeddings(%__MODULE__{} = retriever) do
    retriever
  end
end

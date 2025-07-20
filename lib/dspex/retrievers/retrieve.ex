defmodule DSPex.Retrievers.Retrieve do
  @moduledoc """
  Generic retrieval module supporting multiple vector databases.

  Provides a unified interface for various retrieval backends including
  ChromaDB, Pinecone, Weaviate, and many others.
  """

  alias DSPex.Utils.ID

  @doc """
  Initialize a retriever with a specific backend.

  ## Examples

      # ChromaDB
      {:ok, retriever} = DSPex.Retrievers.Retrieve.init(:chromadb,
        collection_name: "my_docs",
        persist_directory: "./chroma_db"
      )
      
      # Pinecone
      {:ok, retriever} = DSPex.Retrievers.Retrieve.init(:pinecone,
        api_key: "your-api-key",
        environment: "us-west1-gcp",
        index_name: "my-index"
      )
  """
  def init(backend, opts \\ []) do
    id = opts[:store_as] || ID.generate("retrieve_#{backend}")

    backend_class = get_backend_class(backend)

    case Snakepit.Python.call(
           backend_class,
           prepare_backend_config(backend, opts),
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Search for documents/passages.
  """
  def search(retriever_id, query, opts \\ []) do
    k = opts[:k] || 5

    Snakepit.Python.call(
      "stored.#{retriever_id}.forward",
      %{query: query, k: k},
      opts
    )
  end

  @doc """
  Add documents to the retrieval index.
  """
  def add_documents(retriever_id, documents, opts \\ []) do
    Snakepit.Python.call(
      "stored.#{retriever_id}.add_texts",
      %{texts: documents, metadatas: opts[:metadata]},
      opts
    )
  end

  @doc """
  Update the retrieval index.
  """
  def update_index(retriever_id, opts \\ []) do
    Snakepit.Python.call(
      "stored.#{retriever_id}.update_index",
      %{},
      opts
    )
  end

  # Supported backends
  defp get_backend_class(:chromadb), do: "dspy.ChromadbRM"
  defp get_backend_class(:pinecone), do: "dspy.PineconeRM"
  defp get_backend_class(:weaviate), do: "dspy.WeaviateRM"
  defp get_backend_class(:qdrant), do: "dspy.QdrantRM"
  defp get_backend_class(:faiss), do: "dspy.FaissRM"
  defp get_backend_class(:milvus), do: "dspy.MilvusRM"
  defp get_backend_class(:mongodb_atlas), do: "dspy.MongoDBAtlasRM"
  defp get_backend_class(:marqo), do: "dspy.MarqoRM"
  defp get_backend_class(:vectara), do: "dspy.VectaraRM"
  defp get_backend_class(:myscale), do: "dspy.MyScaleRM"
  defp get_backend_class(:pgvector), do: "dspy.PgVectorRM"
  defp get_backend_class(:you), do: "dspy.YouRM"
  defp get_backend_class(:ragatouille), do: "dspy.RAGatouilleRM"
  defp get_backend_class(:snowflake), do: "dspy.SnowflakeRM"
  defp get_backend_class(:watsonx), do: "dspy.WatsonDiscoveryRM"
  defp get_backend_class(:clarifai), do: "dspy.ClarifaiRM"
  defp get_backend_class(:databricks), do: "dspy.DatabricksRM"
  defp get_backend_class(:deeplake), do: "dspy.DeeplakeRM"
  defp get_backend_class(:exa), do: "dspy.ExaSearchRM"
  defp get_backend_class(:neo4j), do: "dspy.Neo4jRM"
  defp get_backend_class(:lancedb), do: "dspy.LancedbRM"
  defp get_backend_class(:astradb), do: "dspy.AstraDbRM"
  defp get_backend_class(:custom), do: raise("Custom class required - pass class in opts")

  defp prepare_backend_config(:chromadb, opts) do
    %{
      collection_name: opts[:collection_name] || "default",
      persist_directory: opts[:persist_directory] || "./chroma_db",
      embedding_function: opts[:embedding_function],
      k: opts[:k] || 5
    }
  end

  defp prepare_backend_config(:pinecone, opts) do
    %{
      api_key: opts[:api_key] || raise("Pinecone API key required"),
      environment: opts[:environment] || raise("Pinecone environment required"),
      index_name: opts[:index_name] || raise("Pinecone index name required"),
      namespace: opts[:namespace],
      k: opts[:k] || 5
    }
  end

  defp prepare_backend_config(:weaviate, opts) do
    %{
      weaviate_url: opts[:url] || "http://localhost:8080",
      weaviate_api_key: opts[:api_key],
      collection_name: opts[:collection_name] || "DSPyCollection",
      k: opts[:k] || 5
    }
  end

  # Add more backend configurations as needed
  defp prepare_backend_config(_, opts), do: opts
end

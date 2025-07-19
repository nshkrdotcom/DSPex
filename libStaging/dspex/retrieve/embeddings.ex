defmodule DSPEx.Retrieve.Embeddings do
  @moduledoc """
  Embeddings module for DSPEx retrieval system.

  This module provides functionality for generating text embeddings using various
  embedding models and computing similarity between embeddings for semantic search
  and retrieval applications.

  ## Usage

      # Generate embeddings for a single text
      {:ok, embedding} = Embeddings.embed("Hello world", model: :text_embedding_ada_002)
      
      # Generate embeddings for multiple texts
      {:ok, embeddings} = Embeddings.batch_embed(["Text 1", "Text 2"], model: :text_embedding_ada_002)
      
      # Compute similarity between embeddings
      similarity = Embeddings.cosine_similarity(embedding1, embedding2)
      
      # Perform semantic search
      {:ok, results} = Embeddings.semantic_search("query", documents, top_k: 5)

  ## Supported Models

  - `:text_embedding_ada_002` - OpenAI's Ada-002 embedding model (1536 dimensions)
  - `:text_embedding_small` - Smaller embedding model (768 dimensions)
  """

  require Logger

  @doc """
  Generate embeddings for a single text.

  ## Parameters

  - `text` - The text to embed (must be a string)
  - `opts` - Options including the embedding model

  ## Returns

  `{:ok, embedding}` where embedding is a list of floats, or `{:error, reason}`.
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, String.t()}
  def embed(text, opts \\ [])

  def embed(text, opts) when is_binary(text) do
    model = Keyword.get(opts, :model, :text_embedding_ada_002)

    case model do
      :text_embedding_ada_002 ->
        # Generate mock embedding with 1536 dimensions for Ada-002
        embedding = generate_mock_embedding(text, 1536)
        {:ok, embedding}

      :text_embedding_small ->
        # Generate mock embedding with 768 dimensions for small model
        embedding = generate_mock_embedding(text, 768)
        {:ok, embedding}

      _ ->
        # Default to Ada-002 dimensions for unknown models
        embedding = generate_mock_embedding(text, 1536)
        {:ok, embedding}
    end
  end

  def embed(_text, _opts) do
    {:error, "Text must be a string"}
  end

  @doc """
  Generate embeddings for multiple texts in batch.

  ## Parameters

  - `texts` - List of texts to embed (all must be strings)
  - `opts` - Options including the embedding model

  ## Returns

  `{:ok, embeddings}` where embeddings is a list of embedding vectors, or `{:error, reason}`.
  """
  @spec batch_embed([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, String.t()}
  def batch_embed(texts, opts \\ [])

  def batch_embed([], _opts), do: {:ok, []}

  def batch_embed(texts, opts) when is_list(texts) do
    # Validate all texts are strings
    if Enum.all?(texts, &is_binary/1) do
      embeddings =
        Enum.map(texts, fn text ->
          {:ok, embedding} = embed(text, opts)
          embedding
        end)

      {:ok, embeddings}
    else
      {:error, "All texts must be strings"}
    end
  end

  def batch_embed(_texts, _opts) do
    {:error, "Texts must be a list"}
  end

  @doc """
  Compute cosine similarity between two embeddings.

  ## Parameters

  - `embedding1` - First embedding vector
  - `embedding2` - Second embedding vector

  ## Returns

  Similarity score between -1.0 and 1.0, or `{:error, reason}`.
  """
  @spec cosine_similarity([float()], [float()]) :: float() | {:error, String.t()}
  def cosine_similarity(embedding1, embedding2)
      when is_list(embedding1) and is_list(embedding2) do
    cond do
      length(embedding1) != length(embedding2) ->
        {:error, "Embeddings must have the same dimensions"}

      Enum.all?(embedding1, &(&1 == 0.0)) or Enum.all?(embedding2, &(&1 == 0.0)) ->
        {:error, "Cannot compute similarity with zero vectors"}

      true ->
        dot_product = dot_product(embedding1, embedding2)
        norm1 = vector_norm(embedding1)
        norm2 = vector_norm(embedding2)

        dot_product / (norm1 * norm2)
    end
  end

  def cosine_similarity(_embedding1, _embedding2) do
    {:error, "Embeddings must be lists of numbers"}
  end

  @doc """
  Perform semantic search on a collection of texts.

  ## Parameters

  - `query` - Query text to search for
  - `texts` - List of texts to search in
  - `opts` - Options including model and top_k

  ## Returns

  `{:ok, results}` where results is a list of `{text, score}` tuples sorted by relevance.
  """
  @spec semantic_search(String.t(), [String.t()], keyword()) ::
          {:ok, [{String.t(), float()}]} | {:error, String.t()}
  def semantic_search(query, texts, opts \\ [])

  def semantic_search(_query, [], _opts), do: {:ok, []}

  def semantic_search(query, texts, opts) when is_binary(query) and is_list(texts) do
    top_k = Keyword.get(opts, :top_k, 10)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, 0.0)
    model = Keyword.get(opts, :model, :text_embedding_ada_002)

    with {:ok, query_embedding} <- embed(query, model: model),
         {:ok, text_embeddings} <- batch_embed(texts, model: model) do
      # Compute similarities and create results
      results =
        texts
        |> Enum.zip(text_embeddings)
        |> Enum.map(fn {text, embedding} ->
          similarity = cosine_similarity(query_embedding, embedding)

          case similarity do
            {:error, _} -> {text, 0.0}
            score -> {text, score}
          end
        end)
        |> Enum.filter(fn {_text, score} -> score >= similarity_threshold end)
        |> Enum.sort_by(fn {_text, score} -> score end, &>=/2)
        |> Enum.take(top_k)

      {:ok, results}
    end
  end

  def semantic_search(_query, _texts, _opts) do
    {:error, "Query must be a string and texts must be a list"}
  end

  # Private helper functions

  # Generate a mock embedding based on text content (for testing)
  defp generate_mock_embedding(text, dimensions) do
    # Create a simple hash-based mock embedding
    # In production, this would call an actual embedding API
    seed = :erlang.phash2(text, 1_000_000)
    :rand.seed(:exsplus, {seed, seed + 1, seed + 2})

    # Generate normalized random vector
    vector = for _ <- 1..dimensions, do: (:rand.uniform() - 0.5) * 2.0
    normalize_vector(vector)
  end

  # Normalize a vector to unit length
  defp normalize_vector(vector) do
    norm = vector_norm(vector)
    if norm > 0, do: Enum.map(vector, &(&1 / norm)), else: vector
  end

  # Compute dot product of two vectors
  defp dot_product(vec1, vec2) do
    vec1
    |> Enum.zip(vec2)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()
  end

  # Compute the L2 norm of a vector
  defp vector_norm(vector) do
    vector
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    |> :math.sqrt()
  end
end

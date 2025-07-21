defmodule ElixirML.Schema.DSL do
  @moduledoc """
  DSL macros for defining ElixirML schemas with ML-specific types.
  """

  @doc """
  Define a field in the schema.

  ## Examples

      field :embedding, :embedding, required: true
      field :confidence, :probability, default: 0.5
      field :tokens, :token_list, max_length: 1000
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @fields {unquote(name), unquote(type), unquote(opts)}

      # If field is marked as variable, track it
      if unquote(opts[:variable]) do
        @variables {unquote(name), unquote(type), unquote(opts)}
      end
    end
  end

  @doc """
  Define a validation function for the schema.

  ## Examples

      validation :check_embedding_dimension do
        fn data ->
          if length(data.embedding) == 384 do
            {:ok, data}
          else
            {:error, "Embedding must be 384 dimensions"}
          end
        end
      end
  """
  defmacro validation(name, do: block) do
    quote do
      @validations {unquote(name), unquote(block)}
    end
  end

  @doc """
  Define a transformation function for the schema.

  ## Examples

      transform :normalize_confidence do
        fn data ->
          Map.update(data, :confidence, 0.5, &max(0.0, min(1.0, &1)))
        end
      end
  """
  defmacro transform(name, do: block) do
    quote do
      @transforms {unquote(name), unquote(block)}
    end
  end

  @doc """
  Set schema metadata.

  ## Examples

      metadata %{
        version: "1.0",
        description: "Question answering schema",
        ml_type: :text_generation
      }
  """
  defmacro metadata(meta) do
    quote do
      @metadata Map.merge(@metadata || %{}, unquote(meta))
    end
  end

  @doc """
  Define schema-level constraints.

  ## Examples

      constraint :embedding_confidence_consistency do
        fn data ->
          if data.confidence > 0.9 and length(data.embedding) < 100 do
            {:error, "High confidence requires richer embedding"}
          else
            {:ok, data}
          end
        end
      end
  """
  defmacro constraint(name, do: block) do
    quote do
      @validations {unquote(name), unquote(block)}
    end
  end
end

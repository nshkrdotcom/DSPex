defmodule AshDSPex.Signature.TypeParser do
  @moduledoc """
  Parser for signature type system supporting basic, ML-specific, and composite types.

  This module handles parsing and validation of type definitions used in signature DSL.
  It supports a comprehensive type system designed for machine learning applications
  while maintaining compatibility with standard Elixir types.

  ## Supported Type Categories

  ### Basic Types
  - `:string` - Text data, questions, responses
  - `:integer` - Numeric values, counts, indices  
  - `:float` - Decimal numbers, probabilities, scores
  - `:boolean` - Binary flags, yes/no responses
  - `:atom` - Enumerated values, status indicators
  - `:any` - Unconstrained values, debugging
  - `:map` - Structured data, complex inputs

  ### ML-Specific Types
  - `:embedding` - Vector embeddings for semantic search
  - `:probability` - Values constrained 0.0-1.0
  - `:confidence_score` - Model confidence metrics
  - `:reasoning_chain` - Step-by-step reasoning traces

  ### Composite Types
  - `{:list, inner_type}` - Arrays of values
  - `{:dict, key_type, value_type}` - Key-value mappings
  - `{:union, [type1, type2, ...]}` - One of multiple types

  ## Usage

      # Parse basic type
      {:ok, :string} = TypeParser.parse_type(:string)

      # Parse composite type
      {:ok, {:list, :string}} = TypeParser.parse_type({:list, :string})

      # Parse with validation
      true = TypeParser.is_valid_type?(:probability)
      false = TypeParser.is_valid_type?(:invalid_type)
  """

  @basic_types [:string, :integer, :float, :boolean, :atom, :any, :map]
  @ml_types [:embedding, :probability, :confidence_score, :reasoning_chain]
  @valid_types @basic_types ++ @ml_types

  @doc """
  Parses a type definition and validates it against the supported type system.

  Returns `{:ok, parsed_type}` for valid types or `{:error, reason}` for invalid ones.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.parse_type(:string)
      {:ok, :string}

      iex> AshDSPex.Signature.TypeParser.parse_type({:list, :string})
      {:ok, {:list, :string}}

      iex> AshDSPex.Signature.TypeParser.parse_type({:dict, :string, :integer})
      {:ok, {:dict, :string, :integer}}

      iex> AshDSPex.Signature.TypeParser.parse_type(:invalid)
      {:error, "Unsupported type: :invalid"}
  """
  @spec parse_type(any()) :: {:ok, term()} | {:error, String.t()}
  def parse_type(type) when type in @valid_types do
    {:ok, type}
  end

  def parse_type({:list, inner_type}) do
    case parse_type(inner_type) do
      {:ok, parsed_inner} -> {:ok, {:list, parsed_inner}}
      {:error, reason} -> {:error, "Invalid inner type in list: #{reason}"}
    end
  end

  def parse_type({:dict, key_type, value_type}) do
    with {:ok, parsed_key} <- parse_type(key_type),
         {:ok, parsed_value} <- parse_type(value_type) do
      {:ok, {:dict, parsed_key, parsed_value}}
    end
  end

  def parse_type({:union, types}) when is_list(types) do
    if Enum.empty?(types) do
      {:error, "Union type cannot be empty"}
    else
      case parse_union_types(types, []) do
        {:ok, parsed_types} -> {:ok, {:union, parsed_types}}
        error -> error
      end
    end
  end

  def parse_type(invalid_type) do
    {:error, "Unsupported type: #{inspect(invalid_type)}"}
  end

  @doc """
  Checks if a type is valid without full parsing.

  Returns `true` for valid types, `false` for invalid ones.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.is_valid_type?(:string)
      true

      iex> AshDSPex.Signature.TypeParser.is_valid_type?({:list, :string})
      true

      iex> AshDSPex.Signature.TypeParser.is_valid_type?(:invalid)
      false
  """
  @spec is_valid_type?(any()) :: boolean()
  def is_valid_type?(type) do
    case parse_type(type) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns all supported basic types.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.basic_types()
      [:string, :integer, :float, :boolean, :atom, :any, :map]
  """
  @spec basic_types() :: [atom()]
  def basic_types, do: @basic_types

  @doc """
  Returns all supported ML-specific types.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.ml_types()
      [:embedding, :probability, :confidence_score, :reasoning_chain]
  """
  @spec ml_types() :: [atom()]
  def ml_types, do: @ml_types

  @doc """
  Returns all supported types (basic + ML-specific).

  ## Examples

      iex> length(AshDSPex.Signature.TypeParser.all_types())
      11
  """
  @spec all_types() :: [atom()]
  def all_types, do: @valid_types

  @doc """
  Generates a human-readable description of a type.

  Useful for error messages and documentation.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.describe_type(:string)
      "string"

      iex> AshDSPex.Signature.TypeParser.describe_type({:list, :string})
      "list of string"

      iex> AshDSPex.Signature.TypeParser.describe_type({:dict, :string, :integer})
      "dict with string keys and integer values"
  """
  @spec describe_type(any()) :: String.t()
  def describe_type(type) when type in @valid_types do
    Atom.to_string(type)
  end

  def describe_type({:list, inner_type}) do
    "list of #{describe_type(inner_type)}"
  end

  def describe_type({:dict, key_type, value_type}) do
    "dict with #{describe_type(key_type)} keys and #{describe_type(value_type)} values"
  end

  def describe_type({:union, types}) do
    type_descriptions = Enum.map(types, &describe_type/1)
    "union of #{Enum.join(type_descriptions, " | ")}"
  end

  def describe_type(invalid_type) do
    "unknown type #{inspect(invalid_type)}"
  end

  # Private helper functions

  defp parse_union_types([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_union_types([type | rest], acc) do
    case parse_type(type) do
      {:ok, parsed_type} -> parse_union_types(rest, [parsed_type | acc])
      error -> error
    end
  end

  @doc """
  Validates that a type definition is well-formed and supported.

  More comprehensive than `is_valid_type?/1`, this function also checks
  for common mistakes and provides detailed error messages.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.validate_type_definition(:string)
      :ok

      iex> AshDSPex.Signature.TypeParser.validate_type_definition({:list, :invalid})
      {:error, "Invalid inner type in list: Unsupported type: :invalid"}
  """
  @spec validate_type_definition(any()) :: :ok | {:error, String.t()}
  def validate_type_definition(type) do
    case parse_type(type) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts all referenced types from a composite type definition.

  Useful for dependency analysis and validation.

  ## Examples

      iex> AshDSPex.Signature.TypeParser.extract_referenced_types(:string)
      [:string]

      iex> AshDSPex.Signature.TypeParser.extract_referenced_types({:list, :string})
      [:string]

      iex> AshDSPex.Signature.TypeParser.extract_referenced_types({:union, [:string, :integer]})
      [:string, :integer]
  """
  @spec extract_referenced_types(any()) :: [atom()]
  def extract_referenced_types(type) when type in @valid_types do
    [type]
  end

  def extract_referenced_types({:list, inner_type}) do
    extract_referenced_types(inner_type)
  end

  def extract_referenced_types({:dict, key_type, value_type}) do
    (extract_referenced_types(key_type) ++ extract_referenced_types(value_type))
    |> Enum.uniq()
  end

  def extract_referenced_types({:union, types}) do
    types
    |> Enum.flat_map(&extract_referenced_types/1)
    |> Enum.uniq()
  end

  def extract_referenced_types(_), do: []
end

defmodule ElixirML.Schema.Types do
  @moduledoc """
  ML-specific type definitions and validation functions.
  Extends standard Elixir types with specialized ML types.
  """

  @type ml_type ::
          :embedding
          | :tensor
          | :token_list
          | :probability
          | :confidence_score
          | :model_response
          | :variable_config
          | :reasoning_chain
          | :attention_weights
          | :api_key

  @doc """
  Validate an embedding vector.

  ## Examples

      iex> ElixirML.Schema.Types.validate_type([1.0, 2.0, 3.0], :embedding)
      {:ok, [1.0, 2.0, 3.0]}

      iex> ElixirML.Schema.Types.validate_type("invalid", :embedding)
      {:error, "Embedding must be list of numbers"}
  """
  def validate_type(value, :embedding) do
    case value do
      list when is_list(list) and length(list) > 0 ->
        if Enum.all?(list, &is_number/1) do
          {:ok, value}
        else
          {:error, "Embedding must be list of numbers"}
        end

      _ ->
        {:error, "Invalid embedding format"}
    end
  end

  def validate_type(value, :probability) do
    case value do
      num when is_number(num) and num >= 0.0 and num <= 1.0 ->
        {:ok, value}

      _ ->
        {:error, "Probability must be between 0.0 and 1.0"}
    end
  end

  def validate_type(value, :confidence_score) do
    case value do
      num when is_number(num) and num >= 0.0 ->
        {:ok, value}

      _ ->
        {:error, "Confidence score must be non-negative number"}
    end
  end

  def validate_type(value, :token_list) do
    case value do
      list when is_list(list) ->
        if Enum.all?(list, &(is_binary(&1) or is_integer(&1))) do
          {:ok, value}
        else
          {:error, "Token list must contain strings or integers"}
        end

      _ ->
        {:error, "Token list must be a list"}
    end
  end

  def validate_type(value, :tensor) do
    case value do
      list when is_list(list) ->
        if valid_tensor_structure?(list) do
          {:ok, value}
        else
          {:error, "Invalid tensor structure"}
        end

      _ ->
        {:error, "Tensor must be a nested list structure"}
    end
  end

  def validate_type(value, :model_response) do
    case value do
      %{text: text} when is_binary(text) ->
        {:ok, value}

      %{"text" => text} when is_binary(text) ->
        {:ok, value}

      _ ->
        {:error, "Model response must have 'text' field"}
    end
  end

  def validate_type(value, :variable_config) do
    case value do
      %{name: name, type: type} when is_atom(name) and is_atom(type) ->
        {:ok, value}

      %{"name" => name, "type" => type} when is_binary(name) and is_binary(type) ->
        {:ok, value}

      _ ->
        {:error, "Variable config must have 'name' and 'type' fields"}
    end
  end

  def validate_type(value, :reasoning_chain) do
    case value do
      list when is_list(list) ->
        if Enum.all?(list, &valid_reasoning_step?/1) do
          {:ok, value}
        else
          {:error, "Invalid reasoning chain structure"}
        end

      _ ->
        {:error, "Reasoning chain must be a list"}
    end
  end

  def validate_type(value, :attention_weights) do
    case value do
      matrix when is_list(matrix) ->
        if valid_attention_matrix?(matrix) do
          {:ok, value}
        else
          {:error, "Invalid attention weights matrix"}
        end

      _ ->
        {:error, "Attention weights must be a matrix (list of lists)"}
    end
  end

  def validate_type(value, :api_key) do
    case value do
      str when is_binary(str) and byte_size(str) > 0 ->
        {:ok, value}

      {:system, env_var} when is_binary(env_var) ->
        {:ok, value}

      _ ->
        {:error, "API key must be a non-empty string or {:system, env_var} tuple"}
    end
  end

  # Fallback for standard types
  def validate_type(value, type) do
    validate_basic_type(value, type)
  end

  # Complex type validation for tuples like {:array, :map}
  defp validate_basic_type(value, {:array, element_type}) when is_list(value) do
    # Validate each element in the array
    case validate_array_elements(value, element_type) do
      {:ok, _} -> {:ok, value}
      error -> error
    end
  end

  defp validate_basic_type(value, {:array, _element_type}) do
    {:error, "Expected array but got #{inspect(value)}"}
  end

  # Basic type validation fallback
  defp validate_basic_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_basic_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_basic_type(value, :float) when is_float(value), do: {:ok, value}
  defp validate_basic_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_basic_type(value, :map) when is_map(value), do: {:ok, value}
  defp validate_basic_type(value, :list) when is_list(value), do: {:ok, value}
  defp validate_basic_type(value, :atom) when is_atom(value), do: {:ok, value}
  defp validate_basic_type(_value, type) when is_atom(type), do: {:error, "Invalid type: #{type}"}
  defp validate_basic_type(_value, type), do: {:error, "Invalid type: #{inspect(type)}"}

  # Helper function to validate array elements
  defp validate_array_elements([], _element_type), do: {:ok, []}

  defp validate_array_elements([head | tail], element_type) do
    case validate_basic_type(head, element_type) do
      {:ok, _} -> validate_array_elements(tail, element_type)
      error -> error
    end
  end

  # Private helper functions

  defp valid_tensor_structure?(list) do
    Enum.all?(list, fn item ->
      cond do
        is_number(item) -> true
        is_list(item) -> valid_tensor_structure?(item)
        true -> false
      end
    end)
  end

  defp valid_reasoning_step?(step) do
    case step do
      %{step: _, reasoning: reasoning} when is_binary(reasoning) -> true
      %{"step" => _, "reasoning" => reasoning} when is_binary(reasoning) -> true
      _ -> false
    end
  end

  defp valid_attention_matrix?(matrix) do
    case matrix do
      [] ->
        true

      [first_row | _rest] when is_list(first_row) ->
        row_length = length(first_row)

        Enum.all?(matrix, fn row ->
          is_list(row) and
            length(row) == row_length and
            Enum.all?(row, &is_number/1)
        end)

      _ ->
        false
    end
  end
end

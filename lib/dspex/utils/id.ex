defmodule DSPex.Utils.ID do
  @moduledoc """
  ID generation utilities for DSPex.

  Provides consistent ID generation for various DSPex components.
  """

  @doc """
  Generate a unique ID with an optional prefix.

  ## Examples

      DSPex.Utils.ID.generate()           # "a1b2c3d4"
      DSPex.Utils.ID.generate("predict")  # "predict_a1b2c3d4"
  """
  def generate(prefix \\ nil) do
    id =
      :crypto.strong_rand_bytes(8)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    if prefix do
      "#{prefix}_#{id}"
    else
      id
    end
  end

  @doc """
  Generate a timestamped ID.
  """
  def generate_timestamped(prefix \\ nil) do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_unix(:millisecond)
      |> to_string()

    random =
      :crypto.strong_rand_bytes(4)
      |> Base.encode16(case: :lower)

    base_id = "#{timestamp}_#{random}"

    if prefix do
      "#{prefix}_#{base_id}"
    else
      base_id
    end
  end

  @doc """
  Check if a string is a valid ID format.
  """
  def valid?(id) when is_binary(id) do
    case String.split(id, "_") do
      [_prefix, hex] -> valid_hex?(hex)
      [hex] -> valid_hex?(hex)
      _ -> false
    end
  end

  def valid?(_), do: false

  defp valid_hex?(str) do
    String.match?(str, ~r/^[a-f0-9]+$/i)
  end
end

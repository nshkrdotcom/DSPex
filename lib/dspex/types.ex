defmodule DSPex.Types do
  @moduledoc """
  Common type definitions for DSPex.
  
  This module serves as the entry point for all type definitions
  used in the DSPex system, providing consistent data structures
  for Python-Elixir interop.
  """

  @doc """
  Re-exports all domain types for convenience.
  """
  defdelegate prediction, to: DSPex.Types.Prediction, as: :__struct__
  defdelegate chain_of_thought_result, to: DSPex.Types.ChainOfThoughtResult, as: :__struct__
  defdelegate react_result, to: DSPex.Types.ReactResult, as: :__struct__
  defdelegate program_of_thought_result, to: DSPex.Types.ProgramOfThoughtResult, as: :__struct__

  @doc """
  Validates a value against a type specification.
  """
  def validate_type(value, {:struct, module}) when is_atom(module) do
    case value do
      %^module{} -> :ok
      _ -> {:error, {:invalid_type, expected: module, got: value.__struct__}}
    end
  end

  def validate_type(value, :string) when is_binary(value), do: :ok
  def validate_type(value, :integer) when is_integer(value), do: :ok
  def validate_type(value, :float) when is_float(value), do: :ok
  def validate_type(value, :boolean) when is_boolean(value), do: :ok
  def validate_type(value, :map) when is_map(value), do: :ok
  def validate_type(value, :list) when is_list(value), do: :ok
  def validate_type(value, {:list, type}) when is_list(value) do
    Enum.reduce_while(value, :ok, fn item, _acc ->
      case validate_type(item, type) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  def validate_type(_value, :reference), do: :ok
  def validate_type(_value, type), do: {:error, {:invalid_type, type}}
end
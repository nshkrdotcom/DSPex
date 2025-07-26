defmodule DSPex.Bridge.Behaviours.ResultTransform do
  @moduledoc """
  Behavior for transforming data between Python and Elixir representations.
  
  This allows you to work with idiomatic Elixir data structures while
  maintaining compatibility with Python's data formats.
  """
  
  @doc """
  Transform raw Python result into domain-specific Elixir types.
  
  This is called automatically after successful Python method calls,
  allowing you to convert generic maps/lists into proper structs.
  
  ## Parameters
  
  - `python_result` - The raw result from Python (typically a map)
  
  ## Return Value
  
  The transformed result in your preferred Elixir format.
  
  ## Example
  
      def transform_result(%{"answer" => answer, "confidence" => conf}) do
        %MyApp.Prediction{
          answer: answer,
          confidence: conf,
          timestamp: DateTime.utc_now()
        }
      end
  """
  @callback transform_result(python_result :: map()) :: term()
  
  @doc """
  Transform Elixir input for Python consumption.
  
  This is called before sending data to Python, allowing you to convert
  Elixir-specific types into Python-compatible formats.
  
  ## Parameters
  
  - `elixir_input` - The input from Elixir code
  
  ## Return Value
  
  A map that can be serialized and sent to Python.
  
  ## Example
  
      def transform_input(%MyApp.Query{text: text, context: context}) do
        %{
          "question" => text,
          "context" => Enum.join(context, "\\n")
        }
      end
  """
  @callback transform_input(elixir_input :: map()) :: map()
  
  @optional_callbacks [transform_input: 1]
end
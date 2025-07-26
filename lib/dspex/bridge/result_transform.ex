defmodule DSPex.Bridge.ResultTransform do
  @moduledoc """
  Enables automatic transformation of data between Python and Elixir formats.
  
  This behavior allows you to work with idiomatic Elixir data structures
  (structs, atoms, tuples) while maintaining compatibility with Python's
  data formats (dicts, strings, lists).
  
  ## Usage
  
      defmodule MyPredictor do
        use DSPex.Bridge.SimpleWrapper
        use DSPex.Bridge.ResultTransform
        
        wrap_dspy "dspy.Predict"
        
        @impl DSPex.Bridge.ResultTransform
        def transform_result(%{"answer" => answer, "confidence" => conf}) do
          %MyApp.Prediction{
            answer: answer,
            confidence: conf,
            generated_at: DateTime.utc_now()
          }
        end
        
        @impl DSPex.Bridge.ResultTransform
        def transform_input(%MyApp.Query{text: text, context: ctx}) do
          %{
            "question" => text,
            "context" => format_context(ctx)
          }
        end
      end
  """
  
  alias DSPex.Bridge.Behaviours
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Behaviours.ResultTransform
      
      # Default implementation (no transformation)
      @impl Behaviours.ResultTransform
      def transform_result(result), do: result
      
      # Optional callback with default
      def transform_input(input), do: input
      
      defoverridable [transform_result: 1, transform_input: 1]
      
      # Register this behavior
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :result_transform
    end
  end
end
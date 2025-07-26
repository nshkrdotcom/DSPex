defmodule DSPex.Bridge.ResultTransformTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.Behaviours
  
  defmodule TestStruct do
    defstruct [:name, :value, :timestamp]
  end
  
  describe "ResultTransform behavior" do
    defmodule TestTransform do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.ResultTransform
      
      wrap_dspy "test.Transform"
      
      @impl Behaviours.ResultTransform
      def transform_result(%{"name" => name, "value" => value}) do
        %TestStruct{
          name: name,
          value: value,
          timestamp: DateTime.utc_now()
        }
      end
      
      @impl Behaviours.ResultTransform
      def transform_input(%TestStruct{} = input) do
        %{
          "name" => input.name,
          "value" => input.value,
          "timestamp" => DateTime.to_iso8601(input.timestamp)
        }
      end
      
      # Override default for other types
      def transform_input(input) when is_map(input), do: input
    end
    
    test "implements ResultTransform behaviour" do
      assert TestTransform.__info__(:attributes)[:behaviour] 
             |> Enum.member?(Behaviours.ResultTransform)
    end
    
    test "tracks result_transform behavior" do
      behaviors = TestTransform.__dspex_behaviors__()
      assert :result_transform in behaviors
    end
    
    test "transforms Python result to Elixir struct" do
      python_result = %{"name" => "test", "value" => 42}
      result = TestTransform.transform_result(python_result)
      
      assert %TestStruct{} = result
      assert result.name == "test"
      assert result.value == 42
      assert result.timestamp != nil
    end
    
    test "transforms Elixir struct to Python format" do
      input = %TestStruct{
        name: "test",
        value: 42,
        timestamp: ~U[2024-01-15 10:00:00Z]
      }
      
      result = TestTransform.transform_input(input)
      
      assert result == %{
        "name" => "test",
        "value" => 42,
        "timestamp" => "2024-01-15T10:00:00Z"
      }
    end
    
    test "passes through maps unchanged when appropriate" do
      input = %{"already" => "formatted"}
      assert TestTransform.transform_input(input) == input
    end
  end
  
  describe "default implementations" do
    defmodule NoTransform do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.ResultTransform
      
      wrap_dspy "test.NoTransform"
    end
    
    test "default transform_result returns value unchanged" do
      input = %{"test" => "value"}
      assert NoTransform.transform_result(input) == input
    end
    
    test "default transform_input returns value unchanged" do
      input = %{"test" => "value"}
      assert NoTransform.transform_input(input) == input
    end
  end
end
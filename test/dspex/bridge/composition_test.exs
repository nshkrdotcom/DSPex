defmodule DSPex.Bridge.CompositionTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.Behaviours
  
  defmodule TestResult do
    defstruct [:value, :processed_at]
    
    def from_python_result(%{"value" => value}) do
      {:ok, %__MODULE__{
        value: String.upcase(value),
        processed_at: DateTime.utc_now()
      }}
    end
  end
  
  describe "composing multiple behaviors" do
    defmodule FullFeaturedWrapper do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.Bidirectional
      use DSPex.Bridge.Observable
      use DSPex.Bridge.ResultTransform
      
      wrap_dspy "test.FullFeatured"
      
      @impl Behaviours.Bidirectional
      def elixir_tools do
        [
          {"validate", &validate_input/1},
          {"enhance", &enhance_data/1}
        ]
      end
      
      @impl Behaviours.Bidirectional
      def on_python_callback(tool, args, context) do
        send(self(), {:tool_called, tool, args, context})
        :ok
      end
      
      @impl Behaviours.Observable
      def telemetry_metadata(operation, args) do
        %{
          operation: operation,
          timestamp: System.system_time(:millisecond),
          has_args: map_size(args) > 0
        }
      end
      
      @impl Behaviours.Observable
      def before_execute(operation, args) do
        send(self(), {:before, operation, args})
        :ok
      end
      
      @impl Behaviours.Observable
      def after_execute(operation, args, result) do
        send(self(), {:after, operation, args, result})
        :ok
      end
      
      @impl Behaviours.ResultTransform
      def transform_result(%{"value" => _} = result) do
        TestResult.from_python_result(result)
        |> case do
          {:ok, struct} -> struct
          _ -> result
        end
      end
      
      @impl Behaviours.ResultTransform
      def transform_input(%{query: query} = input) when is_binary(query) do
        %{
          "question" => query,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      end
      
      # Test helpers
      defp validate_input(%{"text" => text}) do
        String.length(text) > 3
      end
      
      defp enhance_data(%{"value" => value}) do
        %{"value" => value, "enhanced" => true}
      end
    end
    
    test "all behaviors are tracked" do
      behaviors = FullFeaturedWrapper.__dspex_behaviors__()
      
      assert :simple_wrapper in behaviors
      assert :bidirectional in behaviors
      assert :observable in behaviors
      assert :result_transform in behaviors
    end
    
    test "implements all behavior callbacks" do
      module_behaviors = FullFeaturedWrapper.__info__(:attributes)[:behaviour]
      
      assert Behaviours.Bidirectional in module_behaviors
      assert Behaviours.Observable in module_behaviors
      assert Behaviours.ResultTransform in module_behaviors
    end
    
    test "bidirectional tools are accessible" do
      tools = FullFeaturedWrapper.elixir_tools()
      assert length(tools) == 2
      
      # Test validate tool
      {"validate", validator} = Enum.find(tools, fn {name, _} -> name == "validate" end)
      assert validator.(%{"text" => "short"}) == true
      assert validator.(%{"text" => "no"}) == false
      
      # Test enhance tool
      {"enhance", enhancer} = Enum.find(tools, fn {name, _} -> name == "enhance" end)
      assert enhancer.(%{"value" => "test"}) == %{"value" => "test", "enhanced" => true}
    end
    
    test "observable callbacks are called" do
      FullFeaturedWrapper.before_execute(:create, %{test: true})
      assert_received {:before, :create, %{test: true}}
      
      FullFeaturedWrapper.after_execute(:call, %{method: "test"}, {:ok, "result"})
      assert_received {:after, :call, %{method: "test"}, {:ok, "result"}}
    end
    
    test "telemetry metadata includes custom fields" do
      metadata = FullFeaturedWrapper.telemetry_metadata(:call, %{arg: "value"})
      
      assert metadata.operation == :call
      assert metadata.has_args == true
      assert is_integer(metadata.timestamp)
    end
    
    test "result transformation works" do
      python_result = %{"value" => "hello"}
      transformed = FullFeaturedWrapper.transform_result(python_result)
      
      assert %TestResult{} = transformed
      assert transformed.value == "HELLO"
      assert transformed.processed_at != nil
    end
    
    test "input transformation works" do
      elixir_input = %{query: "What is AI?"}
      transformed = FullFeaturedWrapper.transform_input(elixir_input)
      
      assert transformed["question"] == "What is AI?"
      assert transformed["timestamp"] != nil
    end
    
    test "python callback notification works" do
      FullFeaturedWrapper.on_python_callback("validate", %{"arg" => "value"}, %{session_id: "123"})
      assert_received {:tool_called, "validate", %{"arg" => "value"}, %{session_id: "123"}}
    end
  end
  
  describe "behavior independence" do
    defmodule IndependentBehaviorTest do
      # Testing that behaviors can be added in any order
      use DSPex.Bridge.Observable      # Observable first
      use DSPex.Bridge.SimpleWrapper   # SimpleWrapper second
      use DSPex.Bridge.Bidirectional   # Bidirectional third
      
      wrap_dspy "test.Independent"
      
      @impl Behaviours.Bidirectional
      def elixir_tools, do: []
    end
    
    test "behaviors work regardless of order" do
      behaviors = IndependentBehaviorTest.__dspex_behaviors__()
      
      # All behaviors should be present
      assert :simple_wrapper in behaviors
      assert :bidirectional in behaviors
      assert :observable in behaviors
      
      # Functions should still be generated
      assert function_exported?(IndependentBehaviorTest, :create, 1)
      assert function_exported?(IndependentBehaviorTest, :call, 3)
      assert function_exported?(IndependentBehaviorTest, :elixir_tools, 0)
    end
  end
end
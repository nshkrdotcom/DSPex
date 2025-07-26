defmodule DSPex.Bridge.BidirectionalTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Bridge.Behaviours
  
  describe "Bidirectional behavior" do
    defmodule TestBidirectional do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.Bidirectional
      
      wrap_dspy "test.Bidirectional"
      
      @impl Behaviours.Bidirectional
      def elixir_tools do
        [
          {"validate", &validate/1},
          {"transform", &transform/1},
          {"fetch_data", &fetch_data/1}
        ]
      end
      
      @impl Behaviours.Bidirectional
      def on_python_callback(tool_name, args, _context) do
        send(self(), {:callback, tool_name, args})
        :ok
      end
      
      def validate(%{"value" => value}) when is_binary(value) do
        String.length(value) > 5
      end
      
      def transform(%{"text" => text}) do
        String.upcase(text)
      end
      
      def fetch_data(%{"id" => id}) do
        %{"id" => id, "data" => "test_data_#{id}"}
      end
    end
    
    test "implements Bidirectional behaviour" do
      assert TestBidirectional.__info__(:attributes)[:behaviour] 
             |> Enum.member?(Behaviours.Bidirectional)
    end
    
    test "tracks bidirectional behavior" do
      behaviors = TestBidirectional.__dspex_behaviors__()
      assert :bidirectional in behaviors
    end
    
    test "provides elixir tools list" do
      tools = TestBidirectional.elixir_tools()
      assert length(tools) == 3
      
      assert {"validate", validator} = Enum.find(tools, fn {name, _} -> name == "validate" end)
      assert is_function(validator, 1)
      
      assert {"transform", transformer} = Enum.find(tools, fn {name, _} -> name == "transform" end)
      assert is_function(transformer, 1)
    end
    
    test "validate tool works correctly" do
      tools = TestBidirectional.elixir_tools()
      {"validate", validator} = Enum.find(tools, fn {name, _} -> name == "validate" end)
      
      assert validator.(%{"value" => "short"}) == false
      assert validator.(%{"value" => "long enough"}) == true
    end
    
    test "transform tool works correctly" do
      tools = TestBidirectional.elixir_tools()
      {"transform", transformer} = Enum.find(tools, fn {name, _} -> name == "transform" end)
      
      assert transformer.(%{"text" => "hello"}) == "HELLO"
    end
    
    test "on_python_callback sends message" do
      TestBidirectional.on_python_callback("test_tool", %{"arg" => "value"}, %{})
      assert_received {:callback, "test_tool", %{"arg" => "value"}}
    end
  end
  
  describe "default implementations" do
    defmodule MinimalBidirectional do
      use DSPex.Bridge.SimpleWrapper
      use DSPex.Bridge.Bidirectional
      
      wrap_dspy "test.Minimal"
      
      @impl Behaviours.Bidirectional
      def elixir_tools, do: []
    end
    
    test "on_python_callback has default implementation" do
      assert :ok = MinimalBidirectional.on_python_callback("any", %{}, %{})
    end
  end
end
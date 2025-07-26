defmodule DSPex.Bridge.SimpleWrapperTest do
  use ExUnit.Case, async: true
  
  describe "SimpleWrapper macro" do
    defmodule TestWrapper do
      use DSPex.Bridge.SimpleWrapper
      wrap_dspy "test.Component"
    end
    
    test "generates create functions" do
      assert function_exported?(TestWrapper, :create, 0)
      assert function_exported?(TestWrapper, :create, 1)
    end
    
    test "generates call functions" do
      assert function_exported?(TestWrapper, :call, 2)
      assert function_exported?(TestWrapper, :call, 3)
    end
    
    test "generates helper functions" do
      assert function_exported?(TestWrapper, :__call__, 2)
      assert function_exported?(TestWrapper, :forward, 2)
    end
    
    test "stores Python class name" do
      assert TestWrapper.__python_class__() == "test.Component"
    end
    
    test "tracks behaviors" do
      behaviors = TestWrapper.__dspex_behaviors__()
      assert :simple_wrapper in behaviors
    end
  end
  
  describe "with mock bridge" do
    defmodule MockBridge do
      def create_instance(_class, args), do: {:ok, make_ref()}
      def call_method(_ref, _method, _args), do: {:ok, %{"result" => "test"}}
    end
    
    defmodule TestWrapperWithMock do
      use DSPex.Bridge.SimpleWrapper
      wrap_dspy "test.MockComponent"
    end
    
    test "create delegates to orchestrator" do
      # This would test the actual delegation when integrated
      # For now, we verify the function exists and accepts args
      assert function_exported?(TestWrapperWithMock, :create, 1)
    end
  end
end
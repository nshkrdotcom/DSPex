defmodule DSPex.Contracts.WrapperTest do
  use ExUnit.Case, async: true
  
  # Define a test contract
  defmodule TestContract do
    @python_class "test.TestClass"
    @contract_version "1.0.0"
    
    use DSPex.Contract
    
    defmethod :simple_method, :simple,
      params: [
        name: {:required, :string}
      ],
      returns: :string
      
    defmethod :complex_method, :complex,
      params: [
        count: {:required, :integer},
        items: {:optional, {:list, :string}, []}
      ],
      returns: :map
  end
  
  # Define a wrapper module using the contract
  defmodule TestWrapper do
    use DSPex.Contracts.Wrapper
    
    defwrapper :simple_method,
      contract: DSPex.Contracts.WrapperTest.TestContract,
      method: :simple_method
      
    defwrapper :complex_method,
      contract: DSPex.Contracts.WrapperTest.TestContract,
      method: :complex_method
      
    defwrapper :no_validation,
      contract: DSPex.Contracts.WrapperTest.TestContract,
      method: :simple_method,
      validate_input: false,
      cast_output: false
  end
  
  describe "defwrapper macro" do
    test "generates wrapper functions" do
      # Verify the functions exist
      assert function_exported?(TestWrapper, :simple_method, 2)
      assert function_exported?(TestWrapper, :complex_method, 2)
      assert function_exported?(TestWrapper, :no_validation, 2)
    end
  end
  
  describe "wrapper function behavior" do
    setup do
      # Mock the Bridge.call_method to return predictable results
      :meck.new(DSPex.Bridge, [:passthrough])
      
      :meck.expect(DSPex.Bridge, :call_method, fn
        _ref, "simple", %{name: "test"} ->
          {:ok, "Hello test"}
        
        _ref, "complex", %{count: count, items: items} ->
          {:ok, %{count: count, items: items, processed: true}}
        
        _ref, _, _ ->
          {:error, :unknown_method}
      end)
      
      on_exit(fn -> :meck.unload() end)
      
      {:ok, ref: make_ref()}
    end
    
    test "validates input parameters", %{ref: ref} do
      # Valid input
      assert {:ok, "Hello test"} = TestWrapper.simple_method(ref, %{name: "test"})
      
      # Missing required parameter
      assert {:error, {:missing_required_param, :name}} = 
        TestWrapper.simple_method(ref, %{})
      
      # Wrong type
      assert {:error, {:invalid_type, :name, :string, :integer}} = 
        TestWrapper.simple_method(ref, %{name: 123})
    end
    
    test "handles optional parameters with defaults", %{ref: ref} do
      # Without optional parameter
      assert {:ok, %{count: 5, items: [], processed: true}} = 
        TestWrapper.complex_method(ref, %{count: 5})
      
      # With optional parameter
      assert {:ok, %{count: 3, items: ["a", "b"], processed: true}} = 
        TestWrapper.complex_method(ref, %{count: 3, items: ["a", "b"]})
    end
    
    test "skips validation when validate_input is false", %{ref: ref} do
      # This would normally fail validation but passes with no_validation
      assert {:ok, "Hello test"} = TestWrapper.no_validation(ref, %{name: "test"})
    end
  end
end
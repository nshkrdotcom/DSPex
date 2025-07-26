defmodule DSPex.Bridge.ContractBasedTest do
  use ExUnit.Case, async: true
  
  # Define a test contract
  defmodule TestContract do
    use DSPex.Contract
    
    @python_class "test.ContractComponent"
    @contract_version "1.0.0"
    
    defmethod :create, :__init__,
      params: [
        name: {:required, :string},
        count: {:optional, :integer, 1}
      ],
      returns: :reference
      
    defmethod :process, "process",
      params: [
        input: {:required, :string}
      ],
      returns: {:struct, DSPex.Types.Prediction}
      
    defmethod :flexible, "flexible",
      params: :variable_keyword,
      returns: :map
  end
  
  describe "ContractBased macro" do
    defmodule TestContractWrapper do
      use DSPex.Bridge.ContractBased
      use_contract TestContract
    end
    
    test "uses the contract module" do
      assert TestContractWrapper.__contract_module__() == TestContract
    end
    
    test "gets Python class from contract" do
      assert TestContractWrapper.__python_class__() == "test.ContractComponent"
    end
    
    test "tracks contract_based behavior" do
      behaviors = TestContractWrapper.__dspex_behaviors__()
      assert :contract_based in behaviors
    end
    
    test "generates create function" do
      assert function_exported?(TestContractWrapper, :create, 0)
      assert function_exported?(TestContractWrapper, :create, 1)
    end
  end
  
  describe "contract validation" do
    test "contract defines methods" do
      methods = TestContract.__methods__()
      
      assert {:create, create_spec} = Enum.find(methods, fn {name, _} -> name == :create end)
      assert create_spec.python_name == :__init__
      assert create_spec.params == [name: {:required, :string}, count: {:optional, :integer, 1}]
      assert create_spec.returns == :reference
    end
    
    test "contract validates create args" do
      assert :ok = TestContract.validate_create_args(%{name: "test"})
      assert :ok = TestContract.validate_create_args(%{name: "test", count: 5})
      
      assert {:error, {:missing_required_param, :string}} = 
        TestContract.validate_create_args(%{})
      
      assert {:error, _} = 
        TestContract.validate_create_args(%{name: 123})  # wrong type
    end
    
    test "contract validates method args" do
      assert :ok = TestContract.validate_method_args(:process, %{input: "test"})
      
      assert {:error, {:missing_required_param, :string}} = 
        TestContract.validate_method_args(:process, %{})
      
      assert {:error, {:unknown_method, :unknown}} = 
        TestContract.validate_method_args(:unknown, %{})
    end
    
    test "variable keyword params accept anything" do
      assert :ok = TestContract.validate_method_args(:flexible, %{anything: "goes"})
      assert :ok = TestContract.validate_method_args(:flexible, %{})
    end
  end
end
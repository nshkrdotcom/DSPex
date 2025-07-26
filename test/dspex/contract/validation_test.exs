defmodule DSPex.Contract.ValidationTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Contract.Validation
  
  describe "validate_params/2" do
    test "validates required string parameters" do
      spec = [name: {:required, :string}]
      
      assert :ok = Validation.validate_params(%{name: "test"}, spec)
      assert {:error, {:missing_required_param, :name}} = 
        Validation.validate_params(%{}, spec)
      assert {:error, {:invalid_type, _, _, _}} = 
        Validation.validate_params(%{name: 123}, spec)
    end
    
    test "validates optional parameters with defaults" do
      spec = [
        name: {:required, :string},
        count: {:optional, :integer, 10}
      ]
      
      assert :ok = Validation.validate_params(%{name: "test"}, spec)
      assert :ok = Validation.validate_params(%{name: "test", count: 5}, spec)
      assert {:error, _} = Validation.validate_params(%{name: "test", count: "five"}, spec)
    end
    
    test "validates multiple types" do
      spec = [
        string: {:required, :string},
        integer: {:required, :integer},
        float: {:required, :float},
        boolean: {:required, :boolean},
        map: {:required, :map},
        list: {:required, :list}
      ]
      
      valid_params = %{
        string: "test",
        integer: 42,
        float: 3.14,
        boolean: true,
        map: %{},
        list: []
      }
      
      assert :ok = Validation.validate_params(valid_params, spec)
    end
    
    test "accepts integers as floats" do
      spec = [value: {:required, :float}]
      assert :ok = Validation.validate_params(%{value: 42}, spec)
      assert :ok = Validation.validate_params(%{value: 3.14}, spec)
    end
    
    test "validates typed lists" do
      spec = [items: {:required, {:list, :string}}]
      
      assert :ok = Validation.validate_params(%{items: ["a", "b", "c"]}, spec)
      assert {:error, _} = Validation.validate_params(%{items: ["a", 2, "c"]}, spec)
    end
    
    test "validates struct types" do
      spec = [result: {:required, {:struct, DSPex.Types.Prediction}}]
      
      valid_struct = %DSPex.Types.Prediction{answer: "test"}
      assert :ok = Validation.validate_params(%{result: valid_struct}, spec)
      
      assert {:error, _} = Validation.validate_params(%{result: %{}}, spec)
    end
    
    test "accepts variable keyword parameters" do
      assert :ok = Validation.validate_params(%{any: "thing"}, :variable_keyword)
      assert :ok = Validation.validate_params(%{}, :variable_keyword)
    end
  end
  
  describe "validate_params/2 with :variable_keyword" do
    test "accepts any keyword parameters when spec is :variable_keyword" do
      assert :ok = Validation.validate_params(%{any: "thing", other: 123}, :variable_keyword)
      assert :ok = Validation.validate_params(%{}, :variable_keyword)
      assert :ok = Validation.validate_params(%{complex: %{nested: "value"}}, :variable_keyword)
    end
  end
end
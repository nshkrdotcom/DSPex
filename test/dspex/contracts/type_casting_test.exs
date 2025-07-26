defmodule DSPex.Contracts.TypeCastingTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Contracts.TypeCasting
  
  describe "cast_result/2 - primitive types" do
    test "casts strings" do
      assert {:ok, "hello"} = TypeCasting.cast_result("hello", :string)
      assert {:error, {:cannot_cast, 123, :string}} = TypeCasting.cast_result(123, :string)
    end
    
    test "casts integers" do
      assert {:ok, 42} = TypeCasting.cast_result(42, :integer)
      assert {:error, {:cannot_cast, "42", :integer}} = TypeCasting.cast_result("42", :integer)
    end
    
    test "casts floats" do
      assert {:ok, 3.14} = TypeCasting.cast_result(3.14, :float)
      assert {:ok, 42.0} = TypeCasting.cast_result(42, :float)
      assert {:error, {:cannot_cast, "3.14", :float}} = TypeCasting.cast_result("3.14", :float)
    end
    
    test "casts booleans" do
      assert {:ok, true} = TypeCasting.cast_result(true, :boolean)
      assert {:ok, false} = TypeCasting.cast_result(false, :boolean)
      assert {:error, {:cannot_cast, 1, :boolean}} = TypeCasting.cast_result(1, :boolean)
    end
    
    test "casts atoms" do
      assert {:ok, :test} = TypeCasting.cast_result(:test, :atom)
      assert {:ok, :hello} = TypeCasting.cast_result("hello", :atom)
      assert {:error, {:cannot_cast, 123, :atom}} = TypeCasting.cast_result(123, :atom)
    end
  end
  
  describe "cast_result/2 - complex types" do
    test "casts lists" do
      assert {:ok, [1, 2, 3]} = TypeCasting.cast_result([1, 2, 3], :list)
      assert {:error, {:cannot_cast, "not a list", :list}} = 
        TypeCasting.cast_result("not a list", :list)
    end
    
    test "casts typed lists" do
      assert {:ok, [1.0, 2.0, 3.0]} = TypeCasting.cast_result([1, 2, 3], {:list, :float})
      assert {:ok, ["a", "b", "c"]} = TypeCasting.cast_result(["a", "b", "c"], {:list, :string})
      
      assert {:error, {:cannot_cast, 1, :string}} = 
        TypeCasting.cast_result([1, 2, 3], {:list, :string})
    end
    
    test "casts maps" do
      assert {:ok, %{a: 1}} = TypeCasting.cast_result(%{a: 1}, :map)
      assert {:error, {:cannot_cast, [1, 2], :map}} = TypeCasting.cast_result([1, 2], :map)
    end
    
    test "casts tuples" do
      assert {:ok, {1, 2, 3}} = TypeCasting.cast_result({1, 2, 3}, :tuple)
      assert {:ok, {1, 2, 3}} = TypeCasting.cast_result([1, 2, 3], :tuple)
      assert {:error, {:cannot_cast, "not a tuple", :tuple}} = 
        TypeCasting.cast_result("not a tuple", :tuple)
    end
    
    test "casts references" do
      ref = make_ref()
      assert {:ok, ^ref} = TypeCasting.cast_result(ref, :reference)
      
      python_ref = %{__python_ref__: "some_ref"}
      assert {:ok, ^python_ref} = TypeCasting.cast_result(python_ref, :reference)
      
      assert {:error, {:cannot_cast, "not a ref", :reference}} = 
        TypeCasting.cast_result("not a ref", :reference)
    end
    
    test "casts any type" do
      assert {:ok, "anything"} = TypeCasting.cast_result("anything", :any)
      assert {:ok, 123} = TypeCasting.cast_result(123, :any)
      assert {:ok, %{}} = TypeCasting.cast_result(%{}, :any)
    end
  end
  
  describe "cast_result/2 - struct types" do
    defmodule TestStruct do
      defstruct [:name, :value]
    end
    
    defmodule TestStructWithConverter do
      defstruct [:name, :value]
      
      def from_python_result(%{name: name, value: value}) do
        {:ok, %__MODULE__{name: String.upcase(name), value: value * 2}}
      end
    end
    
    test "casts to struct using struct/2" do
      input = %{name: "test", value: 42}
      assert {:ok, %TestStruct{name: "test", value: 42}} = 
        TypeCasting.cast_result(input, {:struct, TestStruct})
    end
    
    test "casts to struct with string keys" do
      input = %{"name" => "test", "value" => 42}
      assert {:ok, %TestStruct{name: "test", value: 42}} = 
        TypeCasting.cast_result(input, {:struct, TestStruct})
    end
    
    test "casts to struct using from_python_result/1" do
      input = %{name: "test", value: 21}
      assert {:ok, %TestStructWithConverter{name: "TEST", value: 42}} = 
        TypeCasting.cast_result(input, {:struct, TestStructWithConverter})
    end
    
    test "handles struct creation errors" do
      assert {:error, {:cannot_cast, "not a map", {:struct, TestStruct}}} = 
        TypeCasting.cast_result("not a map", {:struct, TestStruct})
    end
  end
  
  describe "cast_result/2 - error handling" do
    test "returns error for unknown types" do
      assert {:error, {:unknown_type, :unknown_type, "value"}} = 
        TypeCasting.cast_result("value", :unknown_type)
    end
  end
end
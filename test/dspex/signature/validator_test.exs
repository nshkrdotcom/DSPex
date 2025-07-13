defmodule DSPex.Signature.ValidatorTest do
  use ExUnit.Case
  doctest DSPex.Signature.Validator

  alias DSPex.Signature.Validator

  describe "basic type validation" do
    test "validates string types" do
      assert {:ok, "hello"} = Validator.validate_type("hello", :string)
      assert {:error, _} = Validator.validate_type(123, :string)
      assert {:error, _} = Validator.validate_type(:atom, :string)
    end

    test "validates integer types" do
      assert {:ok, 42} = Validator.validate_type(42, :integer)
      assert {:error, _} = Validator.validate_type("42", :integer)
      # Coercion allowed for whole numbers
      assert {:ok, 42} = Validator.validate_type(42.0, :integer)
      # Non-whole number rejected
      assert {:error, _} = Validator.validate_type(42.5, :integer)
    end

    test "validates float types" do
      assert {:ok, 3.14} = Validator.validate_type(3.14, :float)
      # integer coercion
      assert {:ok, 42.0} = Validator.validate_type(42, :float)
      assert {:error, _} = Validator.validate_type("3.14", :float)
    end

    test "validates boolean types" do
      assert {:ok, true} = Validator.validate_type(true, :boolean)
      assert {:ok, false} = Validator.validate_type(false, :boolean)
      assert {:error, _} = Validator.validate_type("true", :boolean)
      assert {:error, _} = Validator.validate_type(1, :boolean)
    end

    test "validates atom types" do
      assert {:ok, :test} = Validator.validate_type(:test, :atom)
      assert {:error, _} = Validator.validate_type("test", :atom)
    end

    test "validates any type" do
      assert {:ok, "anything"} = Validator.validate_type("anything", :any)
      assert {:ok, 123} = Validator.validate_type(123, :any)
      assert {:ok, %{}} = Validator.validate_type(%{}, :any)
      assert {:ok, nil} = Validator.validate_type(nil, :any)
    end

    test "validates map types" do
      assert {:ok, %{}} = Validator.validate_type(%{}, :map)
      assert {:ok, %{a: 1}} = Validator.validate_type(%{a: 1}, :map)
      assert {:error, _} = Validator.validate_type([], :map)
      assert {:error, _} = Validator.validate_type("map", :map)
    end
  end

  describe "ML-specific type validation" do
    test "validates embedding types" do
      assert {:ok, [1.0, 2.0, 3.0]} = Validator.validate_type([1.0, 2.0, 3.0], :embedding)
      assert {:ok, [1, 2, 3]} = Validator.validate_type([1, 2, 3], :embedding)
      assert {:error, _} = Validator.validate_type([1, "2", 3], :embedding)
      assert {:error, _} = Validator.validate_type("not_a_list", :embedding)
    end

    test "validates probability types" do
      assert {:ok, 0.5} = Validator.validate_type(0.5, :probability)
      assert {:ok, +0.0} = Validator.validate_type(+0.0, :probability)
      assert {:ok, 1.0} = Validator.validate_type(1.0, :probability)
      assert {:error, _} = Validator.validate_type(-0.1, :probability)
      assert {:error, _} = Validator.validate_type(1.1, :probability)
      assert {:error, _} = Validator.validate_type("0.5", :probability)
    end

    test "validates confidence_score types" do
      assert {:ok, 0.85} = Validator.validate_type(0.85, :confidence_score)
      assert {:ok, +0.0} = Validator.validate_type(+0.0, :confidence_score)
      assert {:ok, 1.0} = Validator.validate_type(1.0, :confidence_score)
      assert {:error, _} = Validator.validate_type(-0.1, :confidence_score)
      assert {:error, _} = Validator.validate_type(1.1, :confidence_score)
    end

    test "validates reasoning_chain types" do
      chain = ["step 1", "step 2", "step 3"]
      assert {:ok, ^chain} = Validator.validate_type(chain, :reasoning_chain)
      assert {:error, _} = Validator.validate_type(["step", 123, "step"], :reasoning_chain)
      assert {:error, _} = Validator.validate_type("not_a_list", :reasoning_chain)
    end
  end

  describe "composite type validation" do
    test "validates list types" do
      assert {:ok, ["a", "b", "c"]} = Validator.validate_type(["a", "b", "c"], {:list, :string})
      assert {:ok, [1, 2, 3]} = Validator.validate_type([1, 2, 3], {:list, :integer})
      assert {:ok, []} = Validator.validate_type([], {:list, :string})

      assert {:error, _} = Validator.validate_type([1, "2", 3], {:list, :integer})
      assert {:error, _} = Validator.validate_type("not_a_list", {:list, :string})
    end

    test "validates nested list types" do
      nested_list = [["a", "b"], ["c", "d"]]
      assert {:ok, ^nested_list} = Validator.validate_type(nested_list, {:list, {:list, :string}})

      invalid_nested = [["a", "b"], ["c", 123]]
      assert {:error, _} = Validator.validate_type(invalid_nested, {:list, {:list, :string}})
    end

    test "validates dict types" do
      dict = %{"key1" => 1, "key2" => 2}
      assert {:ok, ^dict} = Validator.validate_type(dict, {:dict, :string, :integer})

      atom_key_dict = %{key1: "value1", key2: "value2"}
      assert {:ok, _} = Validator.validate_type(atom_key_dict, {:dict, :atom, :string})

      assert {:error, _} =
               Validator.validate_type(%{"key" => "wrong_type"}, {:dict, :string, :integer})

      assert {:error, _} = Validator.validate_type([], {:dict, :string, :integer})
    end

    test "validates union types" do
      union_type = {:union, [:string, :integer]}

      assert {:ok, "hello"} = Validator.validate_type("hello", union_type)
      assert {:ok, 42} = Validator.validate_type(42, union_type)
      assert {:error, _} = Validator.validate_type(3.14, union_type)
      assert {:error, _} = Validator.validate_type([], union_type)
    end
  end

  describe "field validation" do
    test "validates fields with all present data" do
      fields = [
        {:name, :string, []},
        {:age, :integer, []},
        {:active, :boolean, []}
      ]

      data = %{name: "Alice", age: 30, active: true}

      {:ok, validated} = Validator.validate_fields(data, fields)
      assert validated.name == "Alice"
      assert validated.age == 30
      assert validated.active == true
    end

    test "rejects missing required fields" do
      fields = [{:name, :string, []}, {:age, :integer, []}]
      data = %{name: "Alice"}

      assert {:error, "Missing required field: age"} = Validator.validate_fields(data, fields)
    end

    test "provides field-specific error messages" do
      fields = [{:name, :string, []}, {:age, :integer, []}]
      data = %{name: "Alice", age: "thirty"}

      {:error, message} = Validator.validate_fields(data, fields)
      assert message =~ "Field age:"
      assert message =~ "Expected :integer"
    end

    test "validates complex field structures" do
      fields = [
        {:query, :string, []},
        {:context, {:list, :string}, []},
        {:metadata, {:dict, :string, :any}, []}
      ]

      data = %{
        query: "search term",
        context: ["web", "docs"],
        metadata: %{"source" => "user", "priority" => 1}
      }

      {:ok, validated} = Validator.validate_fields(data, fields)
      assert validated.query == "search term"
      assert validated.context == ["web", "docs"]
      assert validated.metadata == %{"source" => "user", "priority" => 1}
    end

    test "rejects non-map data" do
      fields = [{:name, :string, []}]

      assert {:error, "Data must be a map, got: \"not_a_map\""} =
               Validator.validate_fields("not_a_map", fields)

      assert {:error, "Data must be a map, got: []"} = Validator.validate_fields([], fields)
    end
  end

  describe "utility functions" do
    test "check_required_fields identifies missing fields" do
      fields = [{:name, :string, []}, {:age, :integer, []}, {:email, :string, []}]

      complete_data = %{name: "Alice", age: 30, email: "alice@example.com"}
      assert :ok = Validator.check_required_fields(complete_data, fields)

      incomplete_data = %{name: "Alice"}
      {:error, missing} = Validator.check_required_fields(incomplete_data, fields)
      assert "Missing required field: age" in missing
      assert "Missing required field: email" in missing
    end

    test "validate_partial allows missing fields" do
      fields = [{:name, :string, []}, {:age, :integer, []}, {:email, :string, []}]

      partial_data = %{name: "Alice", age: 30}
      {:ok, validated} = Validator.validate_partial(partial_data, fields)
      assert validated.name == "Alice"
      assert validated.age == 30
      refute Map.has_key?(validated, :email)

      # Still validates present fields
      invalid_partial = %{name: "Alice", age: "thirty"}
      assert {:error, _} = Validator.validate_partial(invalid_partial, fields)
    end
  end

  describe "type coercion" do
    test "coerces integer to float" do
      assert {:ok, 42.0} = Validator.validate_type(42, :float)
    end

    test "coerces float to integer when appropriate" do
      assert {:ok, 42} = Validator.validate_type(42.0, :integer)
      # Non-whole number
      assert {:error, _} = Validator.validate_type(42.5, :integer)
    end
  end

  describe "error messages" do
    test "provides descriptive error messages" do
      {:error, message} = Validator.validate_type(123, :string)
      assert message =~ "Expected :string"
      assert message =~ "got: 123"
      assert message =~ "integer"
    end

    test "provides context for composite type errors" do
      {:error, message} = Validator.validate_type([1, "2", 3], {:list, :integer})
      assert message =~ "List item validation failed"
    end

    test "provides context for dict validation errors" do
      {:error, message} = Validator.validate_type(%{"key" => "value"}, {:dict, :string, :integer})
      assert message =~ "Dict entry validation failed"
    end
  end
end

defmodule DSPex.Adapters.TypeConverterTest do
  use ExUnit.Case, async: true

  alias DSPex.Adapters.TypeConverter

  doctest TypeConverter

  @moduletag :layer_1

  describe "dspy_to_elixir/1" do
    test "converts basic DSPy types to Elixir types" do
      assert TypeConverter.dspy_to_elixir("str") == :string
      assert TypeConverter.dspy_to_elixir("int") == :integer
      assert TypeConverter.dspy_to_elixir("float") == :float
      assert TypeConverter.dspy_to_elixir("bool") == :boolean
      assert TypeConverter.dspy_to_elixir("None") == nil
      assert TypeConverter.dspy_to_elixir("NoneType") == nil
    end

    test "converts list types" do
      assert TypeConverter.dspy_to_elixir("List[str]") == {:list, :string}
      assert TypeConverter.dspy_to_elixir("List[int]") == {:list, :integer}
      assert TypeConverter.dspy_to_elixir("List[float]") == {:list, :float}
    end

    test "converts dict types" do
      assert TypeConverter.dspy_to_elixir("Dict[str, int]") == {:map, :string, :integer}
      assert TypeConverter.dspy_to_elixir("Dict[str, float]") == {:map, :string, :float}
      assert TypeConverter.dspy_to_elixir("Dict[int, str]") == {:map, :integer, :string}
    end

    test "converts optional types" do
      assert TypeConverter.dspy_to_elixir("Optional[str]") == {:optional, :string}
      assert TypeConverter.dspy_to_elixir("Optional[int]") == {:optional, :integer}
    end

    test "handles unknown types" do
      assert TypeConverter.dspy_to_elixir("CustomType") == :any
      assert TypeConverter.dspy_to_elixir("Unknown") == :any
    end
  end

  describe "elixir_to_dspy/1" do
    test "converts basic Elixir types to DSPy types" do
      assert TypeConverter.elixir_to_dspy(:string) == "str"
      assert TypeConverter.elixir_to_dspy(:integer) == "int"
      assert TypeConverter.elixir_to_dspy(:float) == "float"
      assert TypeConverter.elixir_to_dspy(:boolean) == "bool"
      assert TypeConverter.elixir_to_dspy(:atom) == "str"
      assert TypeConverter.elixir_to_dspy(nil) == "None"
    end

    test "converts complex types" do
      assert TypeConverter.elixir_to_dspy({:list, :string}) == "List[str]"
      assert TypeConverter.elixir_to_dspy({:list, :integer}) == "List[int]"
      assert TypeConverter.elixir_to_dspy({:map, :string, :integer}) == "Dict[str, int]"
    end

    test "handles unknown types" do
      assert TypeConverter.elixir_to_dspy(:unknown) == "Any"
      assert TypeConverter.elixir_to_dspy({:custom, :type}) == "Any"
    end
  end

  describe "from_dspy/2" do
    test "converts basic data types" do
      assert TypeConverter.from_dspy(nil) == nil
      assert TypeConverter.from_dspy("hello") == "hello"
      assert TypeConverter.from_dspy(42) == 42
      assert TypeConverter.from_dspy(3.14) == 3.14
      assert TypeConverter.from_dspy(true) == true
      assert TypeConverter.from_dspy(false) == false
    end

    test "converts lists" do
      assert TypeConverter.from_dspy([1, 2, 3]) == [1, 2, 3]
      assert TypeConverter.from_dspy(["a", "b", "c"]) == ["a", "b", "c"]
      assert TypeConverter.from_dspy([]) == []
    end

    test "converts maps with string keys" do
      input = %{"name" => "test", "value" => 42}
      assert TypeConverter.from_dspy(input) == %{"name" => "test", "value" => 42}
    end

    test "converts maps with atom_keys option" do
      input = %{"name" => "test", "value" => 42}
      expected = %{name: "test", value: 42}
      assert TypeConverter.from_dspy(input, atom_keys: true) == expected
    end

    test "converts nested structures" do
      input = %{
        "user" => %{
          "name" => "John",
          "scores" => [100, 95, 98],
          "active" => true
        }
      }

      result = TypeConverter.from_dspy(input)
      assert result["user"]["name"] == "John"
      assert result["user"]["scores"] == [100, 95, 98]
      assert result["user"]["active"] == true
    end

    test "handles strict mode" do
      # In strict mode, unknown types should raise
      assert_raise ArgumentError, fn ->
        TypeConverter.from_dspy(self(), strict: true)
      end
    end
  end

  describe "to_dspy/2" do
    test "converts basic data types" do
      assert TypeConverter.to_dspy(nil) == nil
      assert TypeConverter.to_dspy("hello") == "hello"
      assert TypeConverter.to_dspy(42) == 42
      assert TypeConverter.to_dspy(3.14) == 3.14
      assert TypeConverter.to_dspy(true) == true
      assert TypeConverter.to_dspy(false) == false
    end

    test "converts atoms to strings" do
      assert TypeConverter.to_dspy(:atom) == "atom"
      assert TypeConverter.to_dspy(:test_atom) == "test_atom"
    end

    test "converts tuples to lists" do
      assert TypeConverter.to_dspy({:ok, "result"}) == ["ok", "result"]
      assert TypeConverter.to_dspy({1, 2, 3}) == [1, 2, 3]
    end

    test "converts maps with atom keys to string keys" do
      input = %{name: "test", value: 42}
      expected = %{"name" => "test", "value" => 42}
      assert TypeConverter.to_dspy(input) == expected
    end

    test "converts structs to maps" do
      # Using a built-in struct instead of defining one in the test
      input = %Range{first: 1, last: 10, step: 1}
      result = TypeConverter.to_dspy(input)

      assert result == %{"first" => 1, "last" => 10, "step" => 1}
    end

    test "converts complex nested structures" do
      input = %{
        user: %{
          name: "John",
          tags: [:admin, :active],
          metadata: %{created: ~D[2024-01-01]}
        }
      }

      result = TypeConverter.to_dspy(input)
      assert result["user"]["name"] == "John"
      assert result["user"]["tags"] == ["admin", "active"]
      assert is_binary(result["user"]["metadata"]["created"])
    end
  end

  describe "convert_signature/1" do
    test "converts Elixir signature format to DSPy wire format" do
      signature = %{
        inputs: [
          %{name: :question, type: :string, description: "User question"},
          %{name: :context, type: {:list, :string}}
        ],
        outputs: [
          %{name: :answer, type: :string},
          %{name: :confidence, type: :float}
        ]
      }

      result = TypeConverter.convert_signature(signature)

      assert result["inputs"] == [
               %{"name" => "question", "type" => "str", "description" => "User question"},
               %{"name" => "context", "type" => "List[str]", "description" => ""}
             ]

      assert result["outputs"] == [
               %{"name" => "answer", "type" => "str", "description" => ""},
               %{"name" => "confidence", "type" => "float", "description" => ""}
             ]
    end
  end

  describe "validate_type/2" do
    test "validates basic types" do
      assert TypeConverter.validate_type("hello", :string) == :ok
      assert TypeConverter.validate_type(42, :integer) == :ok
      assert TypeConverter.validate_type(3.14, :float) == :ok
      assert TypeConverter.validate_type(true, :boolean) == :ok
      assert TypeConverter.validate_type(nil, nil) == :ok
    end

    test "validates list types" do
      assert TypeConverter.validate_type([1, 2, 3], {:list, :integer}) == :ok
      assert TypeConverter.validate_type(["a", "b"], {:list, :string}) == :ok
      assert TypeConverter.validate_type([], {:list, :any}) == :ok
    end

    test "rejects invalid types" do
      assert {:error, _} = TypeConverter.validate_type(42, :string)
      assert {:error, _} = TypeConverter.validate_type("hello", :integer)
      assert {:error, _} = TypeConverter.validate_type([1, "two"], {:list, :integer})
    end

    test "any type accepts anything" do
      assert TypeConverter.validate_type("anything", :any) == :ok
      assert TypeConverter.validate_type(42, :any) == :ok
      assert TypeConverter.validate_type(%{}, :any) == :ok
    end
  end

  describe "coerce/2" do
    test "coerces to string" do
      assert TypeConverter.coerce(42, :string) == {:ok, "42"}
      assert TypeConverter.coerce(:atom, :string) == {:ok, "atom"}
      assert TypeConverter.coerce(true, :string) == {:ok, "true"}
    end

    test "coerces to integer" do
      assert TypeConverter.coerce("42", :integer) == {:ok, 42}
      assert TypeConverter.coerce("-10", :integer) == {:ok, -10}
      assert {:error, _} = TypeConverter.coerce("not_a_number", :integer)
      assert {:error, _} = TypeConverter.coerce("42.5", :integer)
    end

    test "coerces to float" do
      assert TypeConverter.coerce("3.14", :float) == {:ok, 3.14}
      assert TypeConverter.coerce("42", :float) == {:ok, 42.0}
      assert TypeConverter.coerce(42, :float) == {:ok, 42.0}
      assert {:error, _} = TypeConverter.coerce("not_a_number", :float)
    end

    test "coerces to boolean" do
      assert TypeConverter.coerce("true", :boolean) == {:ok, true}
      assert TypeConverter.coerce("false", :boolean) == {:ok, false}
      assert TypeConverter.coerce("1", :boolean) == {:ok, true}
      assert TypeConverter.coerce("0", :boolean) == {:ok, false}
      assert TypeConverter.coerce(1, :boolean) == {:ok, true}
      assert TypeConverter.coerce(0, :boolean) == {:ok, false}
    end

    test "coerces to atom" do
      assert TypeConverter.coerce("test", :atom) == {:ok, :test}
      assert TypeConverter.coerce("hello_world", :atom) == {:ok, :hello_world}
    end

    test "returns data unchanged if already correct type" do
      assert TypeConverter.coerce("hello", :string) == {:ok, "hello"}
      assert TypeConverter.coerce(42, :integer) == {:ok, 42}
      assert TypeConverter.coerce(3.14, :float) == {:ok, 3.14}
      assert TypeConverter.coerce(true, :boolean) == {:ok, true}
    end
  end

  describe "convert_type/3 (enhanced)" do
    test "converts basic types to python format" do
      assert TypeConverter.convert_type(:string, :python) == "str"
      assert TypeConverter.convert_type(:integer, :python) == "int"
      assert TypeConverter.convert_type(:float, :python) == "float"
      assert TypeConverter.convert_type(:boolean, :python) == "bool"
      assert TypeConverter.convert_type(:any, :python) == "Any"
    end

    test "converts ML-specific types" do
      assert TypeConverter.convert_type(:embedding, :python) == "List[float]"
      assert TypeConverter.convert_type(:probability, :python) == "float"
      assert TypeConverter.convert_type(:confidence_score, :python) == "float"
      assert TypeConverter.convert_type(:reasoning_chain, :python) == "List[str]"
    end

    test "converts composite types" do
      assert TypeConverter.convert_type({:list, :string}, :python) == "List[str]"
      assert TypeConverter.convert_type({:dict, :string, :integer}, :python) == "Dict[str, int]"

      union_result = TypeConverter.convert_type({:union, [:string, :integer]}, :python)
      assert union_result == "Union[str, int]"
    end

    test "converts to json_schema format" do
      assert TypeConverter.convert_type(:string, :json_schema) == "string"
      assert TypeConverter.convert_type(:integer, :json_schema) == "integer"
      assert TypeConverter.convert_type(:float, :json_schema) == "number"
      assert TypeConverter.convert_type(:boolean, :json_schema) == "boolean"

      list_result = TypeConverter.convert_type({:list, :string}, :json_schema)
      assert list_result == %{type: "array", items: "string"}

      dict_result = TypeConverter.convert_type({:dict, :string, :integer}, :json_schema)
      assert dict_result == %{type: "object", additionalProperties: "integer"}
    end

    test "converts to mock format" do
      assert TypeConverter.convert_type(:string, :mock) == "string"
      assert TypeConverter.convert_type(:integer, :mock) == "integer"
      assert TypeConverter.convert_type(:embedding, :mock) == "embedding"
      assert TypeConverter.convert_type(:probability, :mock) == "probability"
    end

    test "respects test layer preferences" do
      assert TypeConverter.convert_type(:embedding, :mock, test_layer: :layer_1) == "embedding"

      assert TypeConverter.convert_type(:probability, :mock, test_layer: :layer_1) ==
               "probability"
    end
  end

  describe "validate_input/3 (enhanced)" do
    test "validates ML-specific types" do
      assert {:ok, 0.5} = TypeConverter.validate_input(0.5, :probability)
      assert {:ok, +0.0} = TypeConverter.validate_input(+0.0, :probability)
      assert {:ok, 1.0} = TypeConverter.validate_input(1.0, :probability)

      assert {:error, _} = TypeConverter.validate_input(-0.1, :probability)
      assert {:error, _} = TypeConverter.validate_input(1.1, :probability)

      assert {:ok, 0.8} = TypeConverter.validate_input(0.8, :confidence_score)

      embedding = [0.1, 0.2, 0.3, 0.4]
      assert {:ok, ^embedding} = TypeConverter.validate_input(embedding, :embedding)

      assert {:error, _} = TypeConverter.validate_input([0.1, "invalid"], :embedding)
    end

    test "test layer specific validation" do
      # Mock layer should accept flexible inputs
      assert {:ok, 42} = TypeConverter.validate_input(42, :string, test_layer: :layer_1)

      assert {:ok, "hello"} =
               TypeConverter.validate_input("hello", :integer, test_layer: :layer_1)

      # Integration layer should be strict
      assert {:error, _} = TypeConverter.validate_input(42, :string, test_layer: :layer_3)
      assert {:error, _} = TypeConverter.validate_input("hello", :integer, test_layer: :layer_3)
    end

    test "validates composite types" do
      assert {:ok, ["a", "b", "c"]} =
               TypeConverter.validate_input(["a", "b", "c"], {:list, :string})

      assert {:error, _} = TypeConverter.validate_input(["a", 1, "c"], {:list, :string})
    end
  end

  describe "convert_signature_to_format/3 (enhanced)" do
    defmodule TestSignature do
      use DSPex.Signature

      @signature_ast {:->, [],
                      [
                        [{:question, :string}, {:context, {:list, :string}}],
                        [
                          {:answer, :string},
                          {:confidence, :probability},
                          {:reasoning, :reasoning_chain}
                        ]
                      ]}
    end

    test "converts signature to python format" do
      result = TypeConverter.convert_signature_to_format(TestSignature, :python)

      assert Map.has_key?(result, :inputs)
      assert Map.has_key?(result, :outputs)

      inputs = result.inputs
      assert length(inputs) == 2

      question_input = Enum.find(inputs, &(&1.name == "question"))
      assert question_input.type == "str"

      context_input = Enum.find(inputs, &(&1.name == "context"))
      assert context_input.type == "List[str]"

      outputs = result.outputs
      assert length(outputs) == 3

      confidence_output = Enum.find(outputs, &(&1.name == "confidence"))
      assert confidence_output.type == "float"

      reasoning_output = Enum.find(outputs, &(&1.name == "reasoning"))
      assert reasoning_output.type == "List[str]"
    end

    test "converts signature to mock format" do
      result = TypeConverter.convert_signature_to_format(TestSignature, :mock)

      inputs = result.inputs
      question_input = Enum.find(inputs, &(&1.name == :question))
      assert question_input.type == "string"

      context_input = Enum.find(inputs, &(&1.name == :context))
      assert context_input.type == {:list, "string"}
    end

    test "applies test layer specific conversions" do
      mock_result =
        TypeConverter.convert_signature_to_format(TestSignature, :mock, test_layer: :layer_1)

      python_result =
        TypeConverter.convert_signature_to_format(TestSignature, :python, test_layer: :layer_3)

      # Results should differ based on test layer
      assert mock_result != python_result
    end
  end

  describe "complex type parsing" do
    test "handles nested list types" do
      assert TypeConverter.dspy_to_elixir("List[List[int]]") == {:list, {:list, :integer}}
    end

    test "handles whitespace in type definitions" do
      assert TypeConverter.dspy_to_elixir("Dict[str,  int]") == {:map, :string, :integer}
      assert TypeConverter.dspy_to_elixir("Dict[ str , int ]") == {:map, :string, :integer}
    end

    test "handles optional nested types" do
      assert TypeConverter.dspy_to_elixir("Optional[List[str]]") == {:optional, {:list, :string}}
    end
  end
end

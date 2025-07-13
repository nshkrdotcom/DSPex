defmodule DSPex.Signature.TypeParserTest do
  use ExUnit.Case
  doctest DSPex.Signature.TypeParser

  alias DSPex.Signature.TypeParser

  describe "basic type parsing" do
    test "parses basic types successfully" do
      assert {:ok, :string} = TypeParser.parse_type(:string)
      assert {:ok, :integer} = TypeParser.parse_type(:integer)
      assert {:ok, :float} = TypeParser.parse_type(:float)
      assert {:ok, :boolean} = TypeParser.parse_type(:boolean)
      assert {:ok, :atom} = TypeParser.parse_type(:atom)
      assert {:ok, :any} = TypeParser.parse_type(:any)
      assert {:ok, :map} = TypeParser.parse_type(:map)
    end

    test "parses ML-specific types successfully" do
      assert {:ok, :embedding} = TypeParser.parse_type(:embedding)
      assert {:ok, :probability} = TypeParser.parse_type(:probability)
      assert {:ok, :confidence_score} = TypeParser.parse_type(:confidence_score)
      assert {:ok, :reasoning_chain} = TypeParser.parse_type(:reasoning_chain)
    end

    test "rejects unsupported types" do
      assert {:error, "Unsupported type: :invalid"} = TypeParser.parse_type(:invalid)
      assert {:error, _} = TypeParser.parse_type("string")
      assert {:error, _} = TypeParser.parse_type(123)
    end
  end

  describe "composite type parsing" do
    test "parses list types" do
      assert {:ok, {:list, :string}} = TypeParser.parse_type({:list, :string})
      assert {:ok, {:list, :integer}} = TypeParser.parse_type({:list, :integer})
      assert {:ok, {:list, :embedding}} = TypeParser.parse_type({:list, :embedding})
    end

    test "parses nested list types" do
      assert {:ok, {:list, {:list, :string}}} = TypeParser.parse_type({:list, {:list, :string}})
    end

    test "rejects list with invalid inner type" do
      assert {:error, _} = TypeParser.parse_type({:list, :invalid})
    end

    test "parses dict types" do
      assert {:ok, {:dict, :string, :integer}} = TypeParser.parse_type({:dict, :string, :integer})
      assert {:ok, {:dict, :atom, :string}} = TypeParser.parse_type({:dict, :atom, :string})
    end

    test "rejects dict with invalid types" do
      assert {:error, _} = TypeParser.parse_type({:dict, :invalid, :string})
      assert {:error, _} = TypeParser.parse_type({:dict, :string, :invalid})
    end

    test "parses union types" do
      assert {:ok, {:union, [:string, :integer]}} =
               TypeParser.parse_type({:union, [:string, :integer]})

      assert {:ok, {:union, [:string, :integer, :float]}} =
               TypeParser.parse_type({:union, [:string, :integer, :float]})
    end

    test "rejects union with invalid types" do
      assert {:error, _} = TypeParser.parse_type({:union, [:string, :invalid]})
      assert {:error, _} = TypeParser.parse_type({:union, []})
    end
  end

  describe "type validation" do
    test "is_valid_type? returns correct results" do
      assert TypeParser.is_valid_type?(:string)
      assert TypeParser.is_valid_type?(:embedding)
      assert TypeParser.is_valid_type?({:list, :string})
      assert TypeParser.is_valid_type?({:dict, :string, :integer})
      assert TypeParser.is_valid_type?({:union, [:string, :integer]})

      refute TypeParser.is_valid_type?(:invalid)
      refute TypeParser.is_valid_type?({:list, :invalid})
      refute TypeParser.is_valid_type?("string")
    end

    test "validate_type_definition returns appropriate results" do
      assert :ok = TypeParser.validate_type_definition(:string)
      assert :ok = TypeParser.validate_type_definition({:list, :string})

      assert {:error, _} = TypeParser.validate_type_definition(:invalid)
      assert {:error, _} = TypeParser.validate_type_definition({:list, :invalid})
    end
  end

  describe "type introspection" do
    test "basic_types returns correct list" do
      types = TypeParser.basic_types()
      assert :string in types
      assert :integer in types
      assert :float in types
      assert :boolean in types
      assert :atom in types
      assert :any in types
      assert :map in types
      assert length(types) == 7
    end

    test "ml_types returns correct list" do
      types = TypeParser.ml_types()
      assert :embedding in types
      assert :probability in types
      assert :confidence_score in types
      assert :reasoning_chain in types
      assert length(types) == 4
    end

    test "all_types combines basic and ML types" do
      all_types = TypeParser.all_types()
      basic_types = TypeParser.basic_types()
      ml_types = TypeParser.ml_types()

      assert length(all_types) == length(basic_types) + length(ml_types)
      Enum.each(basic_types, &assert(&1 in all_types))
      Enum.each(ml_types, &assert(&1 in all_types))
    end
  end

  describe "type description" do
    test "describes basic types" do
      assert TypeParser.describe_type(:string) == "string"
      assert TypeParser.describe_type(:integer) == "integer"
      assert TypeParser.describe_type(:embedding) == "embedding"
    end

    test "describes composite types" do
      assert TypeParser.describe_type({:list, :string}) == "list of string"

      assert TypeParser.describe_type({:dict, :string, :integer}) ==
               "dict with string keys and integer values"

      assert TypeParser.describe_type({:union, [:string, :integer]}) ==
               "union of string | integer"
    end

    test "describes nested types" do
      nested_type = {:list, {:dict, :string, :integer}}
      description = TypeParser.describe_type(nested_type)
      assert description == "list of dict with string keys and integer values"
    end

    test "describes unknown types" do
      description = TypeParser.describe_type(:unknown)
      assert description =~ "unknown type"
    end
  end

  describe "type extraction" do
    test "extracts referenced types from basic types" do
      assert TypeParser.extract_referenced_types(:string) == [:string]
      assert TypeParser.extract_referenced_types(:embedding) == [:embedding]
    end

    test "extracts referenced types from composite types" do
      assert TypeParser.extract_referenced_types({:list, :string}) == [:string]

      assert TypeParser.extract_referenced_types({:dict, :string, :integer}) == [
               :string,
               :integer
             ]

      union_types = TypeParser.extract_referenced_types({:union, [:string, :integer, :float]})
      assert :string in union_types
      assert :integer in union_types
      assert :float in union_types
      assert length(union_types) == 3
    end

    test "extracts unique types from nested structures" do
      nested_type = {:dict, :string, {:list, :string}}
      types = TypeParser.extract_referenced_types(nested_type)
      assert :string in types
      # Should only appear once despite being referenced twice
      assert length(Enum.filter(types, &(&1 == :string))) == 1
    end

    test "handles invalid types gracefully" do
      assert TypeParser.extract_referenced_types(:invalid) == []
      assert TypeParser.extract_referenced_types("not_an_atom") == []
    end
  end
end

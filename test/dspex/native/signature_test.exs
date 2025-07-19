defmodule DSPex.Native.SignatureTest do
  use ExUnit.Case, async: true

  alias DSPex.Native.Signature

  describe "parse/1" do
    test "parses simple signature" do
      assert {:ok, sig} = Signature.parse("question -> answer")

      assert sig.inputs == [%{name: :question, type: :string, description: nil}]
      assert sig.outputs == [%{name: :answer, type: :string, description: nil}]
    end

    test "parses signature with types" do
      assert {:ok, sig} =
               Signature.parse("question: str, count: int -> answer: str, confidence: float")

      assert sig.inputs == [
               %{name: :question, type: :string, description: nil},
               %{name: :count, type: :integer, description: nil}
             ]

      assert sig.outputs == [
               %{name: :answer, type: :string, description: nil},
               %{name: :confidence, type: :float, description: nil}
             ]
    end

    test "parses signature with descriptions" do
      assert {:ok, sig} = Signature.parse("question: str 'User query' -> answer: str 'Response'")

      assert sig.inputs == [
               %{name: :question, type: :string, description: "User query"}
             ]

      assert sig.outputs == [
               %{name: :answer, type: :string, description: "Response"}
             ]
    end

    test "parses complex types" do
      assert {:ok, sig} =
               Signature.parse("items: list[str], metadata: dict[str] -> results: list[float]")

      assert sig.inputs == [
               %{name: :items, type: {:list, :string}, description: nil},
               %{name: :metadata, type: {:dict, :string}, description: nil}
             ]

      assert sig.outputs == [
               %{name: :results, type: {:list, :float}, description: nil}
             ]
    end

    test "parses optional types" do
      assert {:ok, sig} = Signature.parse("required: str, optional: optional[int] -> result: str")

      assert sig.inputs == [
               %{name: :required, type: :string, description: nil},
               %{name: :optional, type: {:optional, :integer}, description: nil}
             ]
    end

    test "parses from map specification" do
      spec = %{
        inputs: [
          %{name: :question, type: :string, description: "The question"},
          %{name: :context, type: {:list, :string}}
        ],
        outputs: [
          %{name: :answer, type: :string}
        ]
      }

      assert {:ok, sig} = Signature.parse(spec)
      assert length(sig.inputs) == 2
      assert length(sig.outputs) == 1
    end

    test "returns error for invalid syntax" do
      assert {:error, _} = Signature.parse("invalid syntax without arrow")
    end
  end

  describe "compile/1" do
    test "compiles signature with validator and serializer" do
      assert {:ok, compiled} = Signature.compile("question: str -> answer: str")

      assert Map.has_key?(compiled, :signature)
      assert Map.has_key?(compiled, :validator)
      assert Map.has_key?(compiled, :serializer)
      assert Map.has_key?(compiled, :compiled_at)
    end

    test "compiled validator validates data" do
      {:ok, compiled} = Signature.compile("name: str, age: int -> greeting: str")

      # Valid data
      assert {:ok, []} = compiled.validator.(%{name: "Alice", age: 30})

      # Missing field
      {:ok, errors} = compiled.validator.(%{name: "Alice"})
      assert "input field 'age': is required" in errors

      # Wrong type
      {:ok, errors} = compiled.validator.(%{name: "Alice", age: "thirty"})
      assert Enum.any?(errors, &String.contains?(&1, "invalid type"))
    end

    test "compiled serializer prepares data" do
      {:ok, compiled} = Signature.compile("items: list[str] -> count: int")

      {:ok, serialized} = compiled.serializer.(%{items: ["a", "b", "c"]})

      assert Map.has_key?(serialized, :inputs)
      assert Map.has_key?(serialized, :signature_hash)
      assert serialized.inputs.items == ["a", "b", "c"]
    end
  end

  describe "type parsing" do
    test "recognizes all basic types" do
      types = [
        {"str", :string},
        {"string", :string},
        {"int", :integer},
        {"integer", :integer},
        {"float", :float},
        {"bool", :boolean},
        {"boolean", :boolean}
      ]

      for {type_str, expected} <- types do
        {:ok, sig} = Signature.parse("field: #{type_str} -> result")
        assert [%{type: ^expected}] = sig.inputs
      end
    end

    test "handles nested list types" do
      {:ok, sig} = Signature.parse("nested: list[list[int]] -> result")
      assert [%{type: {:list, {:list, :integer}}}] = sig.inputs
    end
  end
end

defmodule DSPex.Signature.MetadataTest do
  use ExUnit.Case, async: true

  alias DSPex.Signature.Metadata

  describe "to_enhanced_metadata/2" do
    defmodule TestSignature do
      use DSPex.Signature

      description("A test signature for sentiment analysis")

      @signature_ast {:->, [],
                      [[{:text, :string}], [{:sentiment, :string}, {:confidence, :probability}]]}
    end

    test "converts signature module to enhanced metadata" do
      metadata = Metadata.to_enhanced_metadata(TestSignature)

      assert metadata.name == "TestSignature"
      assert metadata.description == "A test signature for sentiment analysis"

      # Check inputs
      assert length(metadata.inputs) == 1
      input = List.first(metadata.inputs)
      assert input.name == "text"
      assert input.type == "string"
      assert input.description == "Input field: text"

      # Check outputs
      assert length(metadata.outputs) == 2
      sentiment_output = Enum.find(metadata.outputs, &(&1.name == "sentiment"))
      assert sentiment_output.type == "string"

      confidence_output = Enum.find(metadata.outputs, &(&1.name == "confidence"))
      # probability converts to float
      assert confidence_output.type == "float"
    end

    test "handles signature without description" do
      defmodule NoDescSignature do
        use DSPex.Signature
        @signature_ast {:->, [], [[{:question, :string}], [{:answer, :string}]]}
      end

      metadata = Metadata.to_enhanced_metadata(NoDescSignature)

      assert metadata.name == "NoDescSignature"
      assert metadata.description == "A dynamically generated DSPy signature."
    end

    test "accepts custom description in options" do
      metadata =
        Metadata.to_enhanced_metadata(
          TestSignature,
          description: "Custom description from options"
        )

      assert metadata.description == "Custom description from options"
    end

    test "accepts custom name in options" do
      metadata =
        Metadata.to_enhanced_metadata(
          TestSignature,
          name: "CustomName"
        )

      assert metadata.name == "CustomName"
    end
  end

  describe "normalize_signature_definition/1" do
    test "normalizes basic signature definition" do
      signature_def = %{
        name: "TestSig",
        inputs: [%{name: "input1", type: "string"}],
        outputs: [%{name: "output1", type: "string"}]
      }

      result = Metadata.normalize_signature_definition(signature_def)

      assert result.name == "TestSig"
      assert result.description == "A dynamically generated DSPy signature."
      assert length(result.inputs) == 1
      assert length(result.outputs) == 1
    end

    test "handles string keys" do
      signature_def = %{
        "name" => "StringKeysSig",
        "description" => "Uses string keys",
        "inputs" => [%{"name" => "text", "type" => "string"}],
        "outputs" => [%{"name" => "result", "type" => "string"}]
      }

      result = Metadata.normalize_signature_definition(signature_def)

      assert result.name == "StringKeysSig"
      assert result.description == "Uses string keys"
      assert List.first(result.inputs).name == "text"
    end

    test "handles missing fields with defaults" do
      signature_def = %{
        inputs: [%{name: "input1", type: "string"}],
        outputs: [%{name: "output1", type: "string"}]
      }

      result = Metadata.normalize_signature_definition(signature_def)

      assert result.name == "DynamicSignature"
      assert result.description == "A dynamically generated DSPy signature."
    end

    test "adds default descriptions to fields" do
      signature_def = %{
        name: "TestSig",
        inputs: [%{name: "input1", type: "string"}],
        outputs: [%{name: "output1", type: "string"}]
      }

      result = Metadata.normalize_signature_definition(signature_def)

      input = List.first(result.inputs)
      assert input.description == "Field: input1"

      output = List.first(result.outputs)
      assert output.description == "Field: output1"
    end

    test "preserves existing descriptions" do
      signature_def = %{
        name: "TestSig",
        inputs: [%{name: "input1", type: "string", description: "Custom input desc"}],
        outputs: [%{name: "output1", type: "string", description: "Custom output desc"}]
      }

      result = Metadata.normalize_signature_definition(signature_def)

      assert List.first(result.inputs).description == "Custom input desc"
      assert List.first(result.outputs).description == "Custom output desc"
    end
  end

  describe "validate_metadata/1" do
    test "validates correct metadata" do
      metadata = %{
        name: "ValidSignature",
        description: "A valid signature",
        inputs: [%{name: "text", type: "string", description: "Input text"}],
        outputs: [%{name: "result", type: "string", description: "Output result"}]
      }

      assert Metadata.validate_metadata(metadata) == :ok
    end

    test "rejects metadata with missing required fields" do
      metadata = %{
        name: "InvalidSignature"
        # Missing description, inputs, outputs
      }

      assert {:error, errors} = Metadata.validate_metadata(metadata)
      assert length(errors) > 0
    end

    test "rejects invalid field names" do
      metadata = %{
        name: "InvalidSignature",
        description: "Has invalid field names",
        inputs: [%{name: "123invalid", type: "string", description: "Bad name"}],
        outputs: [%{name: "result", type: "string", description: "Good name"}]
      }

      assert {:error, errors} = Metadata.validate_metadata(metadata)
      assert Enum.any?(errors, fn {type, _msg} -> type == :invalid_field_name end)
    end

    test "rejects duplicate field names" do
      metadata = %{
        name: "DuplicateSignature",
        description: "Has duplicate field names",
        inputs: [%{name: "text", type: "string", description: "Input"}],
        outputs: [%{name: "text", type: "string", description: "Output"}]
      }

      assert {:error, errors} = Metadata.validate_metadata(metadata)
      assert Enum.any?(errors, fn {type, _msg} -> type == :field_name_conflict end)
    end

    test "rejects reserved Python names" do
      metadata = %{
        name: "ReservedSignature",
        description: "Uses reserved Python names",
        inputs: [%{name: "class", type: "string", description: "Reserved name"}],
        outputs: [%{name: "result", type: "string", description: "Good name"}]
      }

      assert {:error, errors} = Metadata.validate_metadata(metadata)
      assert Enum.any?(errors, fn {type, _msg} -> type == :reserved_name_conflict end)
    end
  end

  describe "from_enhanced_metadata/1" do
    test "converts enhanced metadata back to DSPex format" do
      enhanced_metadata = %{
        name: "TestSignature",
        description: "A test signature",
        inputs: [%{name: "text", type: "string", description: "Input text"}],
        outputs: [%{name: "sentiment", type: "string", description: "Output sentiment"}]
      }

      result = Metadata.from_enhanced_metadata(enhanced_metadata)

      assert length(result.inputs) == 1
      assert length(result.outputs) == 1

      {input_name, input_type, input_constraints} = List.first(result.inputs)
      assert input_name == :text
      assert input_type == :string
      assert input_constraints == []

      {output_name, output_type, output_constraints} = List.first(result.outputs)
      assert output_name == :sentiment
      assert output_type == :string
      assert output_constraints == []
    end

    test "handles complex types" do
      enhanced_metadata = %{
        name: "ComplexSignature",
        description: "Uses complex types",
        inputs: [%{name: "items", type: "list<string>", description: "List of items"}],
        outputs: [
          %{name: "mapping", type: "dict<string,float>", description: "String to float mapping"}
        ]
      }

      result = Metadata.from_enhanced_metadata(enhanced_metadata)

      {input_name, input_type, _} = List.first(result.inputs)
      assert input_name == :items
      assert input_type == {:list, :string}

      {output_name, output_type, _} = List.first(result.outputs)
      assert output_name == :mapping
      assert output_type == {:dict, :string, :float}
    end
  end
end

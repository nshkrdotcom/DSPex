defmodule DSPex.Signature.IntegrationTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Signature.Metadata

  describe "Enhanced Signature Integration" do
    defmodule SentimentAnalysis do
      use DSPex.Signature
      
      description "Analyzes text sentiment and extracts confidence scores"
      @signature_ast {:->, [], [
        [{:text, :string}, {:style, :string}], 
        [{:sentiment, :string}, {:confidence, :probability}, {:reasoning, {:list, :string}}]
      ]}
    end

    test "signature module generates enhanced metadata" do
      # Test that the compiled signature module can generate enhanced metadata
      assert function_exported?(SentimentAnalysis, :to_enhanced_metadata, 0)
      assert function_exported?(SentimentAnalysis, :to_python_signature, 0)

      metadata = SentimentAnalysis.to_enhanced_metadata()

      # Validate basic structure
      assert metadata.name == "SentimentAnalysis"
      assert metadata.description == "Analyzes text sentiment and extracts confidence scores"
      
      # Validate inputs
      assert length(metadata.inputs) == 2
      
      text_input = Enum.find(metadata.inputs, &(&1.name == "text"))
      assert text_input.type == "string"
      assert text_input.description == "Input field: text"
      
      style_input = Enum.find(metadata.inputs, &(&1.name == "style"))
      assert style_input.type == "string"

      # Validate outputs
      assert length(metadata.outputs) == 3
      
      sentiment_output = Enum.find(metadata.outputs, &(&1.name == "sentiment"))
      assert sentiment_output.type == "string"
      
      confidence_output = Enum.find(metadata.outputs, &(&1.name == "confidence"))
      assert confidence_output.type == "float"  # probability maps to float
      
      reasoning_output = Enum.find(metadata.outputs, &(&1.name == "reasoning"))
      assert reasoning_output.type == "list<string>"
    end

    test "to_python_signature produces valid metadata" do
      python_signature = SentimentAnalysis.to_python_signature()
      
      # Should be valid enhanced metadata
      assert Metadata.validate_metadata(python_signature) == :ok
      
      # Should have expected structure for Python bridge
      assert Map.has_key?(python_signature, :name)
      assert Map.has_key?(python_signature, :description)
      assert Map.has_key?(python_signature, :inputs)
      assert Map.has_key?(python_signature, :outputs)
    end

    defmodule NoDescriptionSignature do
      use DSPex.Signature
      @signature_ast {:->, [], [[{:question, :string}], [{:answer, :string}]]}
    end

    test "signature without description gets default" do
      metadata = NoDescriptionSignature.to_enhanced_metadata()
      
      assert metadata.description == "A dynamically generated DSPy signature."
    end

    test "signature with custom options" do
      custom_metadata = SentimentAnalysis.to_enhanced_metadata(
        description: "Custom description for testing",
        name: "CustomSentimentAnalysis"
      )
      
      assert custom_metadata.name == "CustomSentimentAnalysis"
      assert custom_metadata.description == "Custom description for testing"
    end

    defmodule ComplexTypesSignature do
      use DSPex.Signature
      
      description "Tests complex type conversion"
      @signature_ast {:->, [], [
        [{:query, :string}, {:context, {:list, :string}}, {:options, {:dict, :atom, :any}}], 
        [{:results, {:list, :string}}, {:metadata, {:dict, :string, :float}}, {:scores, {:union, [:integer, :float]}}]
      ]}
    end

    test "complex types are properly converted" do
      metadata = ComplexTypesSignature.to_enhanced_metadata()
      
      # Check complex input types
      context_input = Enum.find(metadata.inputs, &(&1.name == "context"))
      assert context_input.type == "list<string>"
      
      options_input = Enum.find(metadata.inputs, &(&1.name == "options"))
      assert options_input.type == "dict<string,any>"  # atom becomes string in Python
      
      # Check complex output types
      results_output = Enum.find(metadata.outputs, &(&1.name == "results"))
      assert results_output.type == "list<string>"
      
      metadata_output = Enum.find(metadata.outputs, &(&1.name == "metadata"))
      assert metadata_output.type == "dict<string,float>"
      
      scores_output = Enum.find(metadata.outputs, &(&1.name == "scores"))
      assert scores_output.type == "union<integer|float>"
    end

    test "round-trip conversion preserves structure" do
      # Test conversion from enhanced metadata back to DSPex format
      original_metadata = SentimentAnalysis.to_enhanced_metadata()
      converted_back = Metadata.from_enhanced_metadata(original_metadata)

      # Should have same number of fields
      original_signature = SentimentAnalysis.__signature__()
      assert length(converted_back.inputs) == length(original_signature.inputs)
      assert length(converted_back.outputs) == length(original_signature.outputs)

      # Field names should match
      original_input_names = Enum.map(original_signature.inputs, fn {name, _, _} -> name end)
      converted_input_names = Enum.map(converted_back.inputs, fn {name, _, _} -> name end)
      assert MapSet.new(original_input_names) == MapSet.new(converted_input_names)
    end
  end

  describe "Map-based Signature Integration" do
    test "map signatures are converted to enhanced metadata" do
      # Test that existing map-based signatures work with the new system
      map_signature = %{
        name: "MapBasedSignature",
        description: "A signature defined as a map",
        inputs: [
          %{name: "input_text", type: "string", description: "Text to process"},
          %{name: "temperature", type: "float", description: "Processing temperature"}
        ],
        outputs: [
          %{name: "processed_text", type: "string", description: "Processed output"},
          %{name: "metadata", type: "dict", description: "Processing metadata"}
        ]
      }

      normalized = Metadata.normalize_signature_definition(map_signature)
      assert Metadata.validate_metadata(normalized) == :ok

      # Should preserve all information
      assert normalized.name == "MapBasedSignature"
      assert normalized.description == "A signature defined as a map"
      assert length(normalized.inputs) == 2
      assert length(normalized.outputs) == 2
    end

    test "legacy map signatures get normalized" do
      # Test legacy format without descriptions
      legacy_signature = %{
        inputs: [%{name: "question", type: "string"}],
        outputs: [%{name: "answer", type: "string"}]
      }

      normalized = Metadata.normalize_signature_definition(legacy_signature)

      # Should get defaults
      assert normalized.name == "DynamicSignature"
      assert normalized.description == "A dynamically generated DSPy signature."
      
      # Should get field descriptions
      input = List.first(normalized.inputs)
      assert input.description == "Field: question"
      
      output = List.first(normalized.outputs)
      assert output.description == "Field: answer"
    end

    test "string keys are converted to atom keys" do
      string_key_signature = %{
        "name" => "StringKeysSignature",
        "description" => "Uses string keys",
        "inputs" => [%{"name" => "text", "type" => "string", "description" => "Input text"}],
        "outputs" => [%{"name" => "result", "type" => "string", "description" => "Output result"}]
      }

      normalized = Metadata.normalize_signature_definition(string_key_signature)
      
      assert normalized.name == "StringKeysSignature"
      assert normalized.description == "Uses string keys"
      assert List.first(normalized.inputs).name == "text"
      assert List.first(normalized.outputs).name == "result"
    end
  end

  describe "Error Handling and Edge Cases" do
    test "handles missing or invalid signature definitions gracefully" do
      # Empty map
      empty_sig = %{}
      normalized = Metadata.normalize_signature_definition(empty_sig)
      
      assert normalized.name == "DynamicSignature"
      assert normalized.inputs == []
      assert normalized.outputs == []

      # Should fail validation due to missing fields
      assert {:error, _errors} = Metadata.validate_metadata(normalized)
    end

    test "handles malformed field definitions" do
      malformed_signature = %{
        name: "MalformedSignature",
        description: "Has malformed fields",
        inputs: [
          "not a map",
          %{name: "valid_field", type: "string", description: "This one is valid"}
        ],
        outputs: [%{type: "string"}]  # Missing name
      }

      normalized = Metadata.normalize_signature_definition(malformed_signature)
      
      # Should handle gracefully but fail validation
      assert {:error, errors} = Metadata.validate_metadata(normalized)
      assert length(errors) > 0
    end

    test "validates against Python compatibility" do
      incompatible_signature = %{
        name: "IncompatibleSignature",
        description: "Not compatible with Python",
        inputs: [
          %{name: "class", type: "string", description: "Reserved Python keyword"},
          %{name: "123invalid", type: "string", description: "Invalid Python identifier"}
        ],
        outputs: [
          %{name: "def", type: "string", description: "Another reserved keyword"}
        ]
      }

      normalized = Metadata.normalize_signature_definition(incompatible_signature)
      assert {:error, errors} = Metadata.validate_metadata(normalized)
      
      # Should detect both reserved names and invalid identifiers
      error_types = Enum.map(errors, fn {type, _} -> type end)
      assert :reserved_name_conflict in error_types or :invalid_field_name in error_types
    end
  end
end
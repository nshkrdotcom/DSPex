defmodule DSPex.Signature.EnhancedValidatorTest do
  use ExUnit.Case, async: true

  alias DSPex.Signature.EnhancedValidator

  describe "validate_enhanced_metadata/1" do
    test "validates correct metadata" do
      metadata = %{
        name: "ValidSignature",
        description: "A valid signature for testing",
        inputs: [
          %{name: "text", type: "string", description: "Input text to process"},
          %{name: "temperature", type: "float", description: "Processing temperature"}
        ],
        outputs: [
          %{name: "result", type: "string", description: "Processed result"},
          %{name: "confidence", type: "probability", description: "Confidence score"}
        ]
      }

      assert EnhancedValidator.validate_enhanced_metadata(metadata) == :ok
    end

    test "rejects non-map metadata" do
      assert {:error, [structure: "Metadata must be a map"]} =
               EnhancedValidator.validate_enhanced_metadata("not a map")
    end

    test "rejects metadata missing required fields" do
      metadata = %{
        name: "IncompleteSignature"
        # Missing description, inputs, outputs
      }

      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(metadata)

      error_types = Enum.map(errors, fn {type, _msg} -> type end)
      assert :missing_field in error_types
    end

    test "validates signature name" do
      # Valid names
      valid_metadata = %{
        name: "ValidName123",
        description: "Test",
        inputs: [%{name: "input1", type: "string", description: "Test"}],
        outputs: [%{name: "output1", type: "string", description: "Test"}]
      }

      assert EnhancedValidator.validate_enhanced_metadata(valid_metadata) == :ok

      # Invalid names
      invalid_names = ["123Invalid", "Invalid-Name", "Invalid.Name", "", " "]

      for invalid_name <- invalid_names do
        invalid_metadata = %{valid_metadata | name: invalid_name}
        assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)
        assert Enum.any?(errors, fn {type, _} -> type == :invalid_name end)
      end
    end

    test "validates field names" do
      base_metadata = %{
        name: "TestSignature",
        description: "Test signature",
        inputs: [],
        outputs: []
      }

      # Valid field names
      valid_field = %{name: "valid_field_name", type: "string", description: "Valid field"}
      valid_output = %{name: "valid_output", type: "string", description: "Valid output"}
      valid_metadata = %{base_metadata | inputs: [valid_field], outputs: [valid_output]}
      assert EnhancedValidator.validate_enhanced_metadata(valid_metadata) == :ok

      # Invalid field names
      invalid_names = ["123invalid", "invalid-name", "invalid.name", "", " ", "class", "def"]

      for invalid_name <- invalid_names do
        invalid_field = %{name: invalid_name, type: "string", description: "Invalid field"}
        invalid_metadata = %{base_metadata | inputs: [invalid_field]}
        assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)

        # Should have either invalid_field_name or reserved_name_conflict error
        error_types = Enum.map(errors, fn {type, _} -> type end)
        assert :invalid_field_name in error_types or :reserved_name_conflict in error_types
      end
    end

    test "validates field types" do
      base_metadata = %{
        name: "TestSignature",
        description: "Test signature",
        inputs: [],
        outputs: []
      }

      # Valid field types
      valid_types = [
        "string",
        "integer",
        "float",
        "boolean",
        "list",
        "dict",
        "any",
        "embedding",
        "probability",
        "list<string>",
        "dict<string,float>"
      ]

      for valid_type <- valid_types do
        valid_field = %{name: "test_field", type: valid_type, description: "Test field"}
        valid_output = %{name: "test_output", type: "string", description: "Test output"}
        valid_metadata = %{base_metadata | inputs: [valid_field], outputs: [valid_output]}
        assert EnhancedValidator.validate_enhanced_metadata(valid_metadata) == :ok
      end

      # Invalid field types
      invalid_types = ["unknown_type", "", " "]

      for invalid_type <- invalid_types do
        invalid_field = %{name: "test_field", type: invalid_type, description: "Test field"}
        invalid_metadata = %{base_metadata | inputs: [invalid_field]}
        assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)
        assert Enum.any?(errors, fn {type, _} -> type == :invalid_field_type end)
      end
    end

    test "detects duplicate field names" do
      metadata = %{
        name: "DuplicateSignature",
        description: "Has duplicate field names",
        inputs: [
          %{name: "duplicate", type: "string", description: "First duplicate"},
          %{name: "unique", type: "string", description: "Unique field"}
        ],
        outputs: [
          %{name: "duplicate", type: "string", description: "Second duplicate"}
        ]
      }

      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(metadata)
      assert Enum.any?(errors, fn {type, _} -> type == :field_name_conflict end)
    end

    test "detects reserved Python names" do
      reserved_names = [
        "class",
        "def",
        "if",
        "for",
        "while",
        "try",
        "except",
        "True",
        "False",
        "None",
        "__init__",
        "self"
      ]

      base_metadata = %{
        name: "ReservedSignature",
        description: "Uses reserved names",
        inputs: [],
        outputs: []
      }

      for reserved_name <- reserved_names do
        reserved_field = %{name: reserved_name, type: "string", description: "Reserved field"}
        metadata = %{base_metadata | inputs: [reserved_field]}

        assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(metadata)
        assert Enum.any?(errors, fn {type, _} -> type == :reserved_name_conflict end)
      end
    end

    test "requires at least one input and output field" do
      # No inputs
      no_inputs = %{
        name: "NoInputs",
        description: "Missing inputs",
        inputs: [],
        outputs: [%{name: "output1", type: "string", description: "Output"}]
      }

      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(no_inputs)
      assert Enum.any?(errors, fn {type, _} -> type == :inputs end)

      # No outputs
      no_outputs = %{
        name: "NoOutputs",
        description: "Missing outputs",
        inputs: [%{name: "input1", type: "string", description: "Input"}],
        outputs: []
      }

      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(no_outputs)
      assert Enum.any?(errors, fn {type, _} -> type == :outputs end)
    end

    test "validates field structures" do
      base_metadata = %{
        name: "TestSignature",
        description: "Test signature",
        inputs: [],
        outputs: []
      }

      # Invalid field structure (not a map)
      invalid_metadata = %{base_metadata | inputs: ["not a map"]}
      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)
      assert Enum.any?(errors, fn {type, _} -> type == :inputs end)

      # Missing field name
      missing_name_field = %{type: "string", description: "Missing name"}
      invalid_metadata = %{base_metadata | inputs: [missing_name_field]}
      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)
      assert Enum.any?(errors, fn {type, _} -> type == :invalid_field_name end)

      # Missing field type
      missing_type_field = %{name: "field1", description: "Missing type"}
      invalid_metadata = %{base_metadata | inputs: [missing_type_field]}
      assert {:error, errors} = EnhancedValidator.validate_enhanced_metadata(invalid_metadata)
      assert Enum.any?(errors, fn {type, _} -> type == :invalid_field_type end)
    end
  end

  describe "validate_field_definitions/2" do
    test "validates correct field definitions" do
      fields = [
        %{name: "field1", type: "string", description: "First field"},
        %{name: "field2", type: "integer", description: "Second field"}
      ]

      assert EnhancedValidator.validate_field_definitions(fields, :input) == :ok
    end

    test "rejects non-list field definitions" do
      assert {:error, [{:input, "Field list must be a list"}]} =
               EnhancedValidator.validate_field_definitions("not a list", :input)
    end

    test "validates individual field definitions" do
      # Valid fields
      valid_fields = [
        %{name: "valid_field", type: "string", description: "Valid field"}
      ]

      assert EnhancedValidator.validate_field_definitions(valid_fields, :input) == :ok

      # Invalid field (not a map)
      invalid_fields = ["not a map"]

      assert {:error, errors} =
               EnhancedValidator.validate_field_definitions(invalid_fields, :input)

      assert Enum.any?(errors, fn {type, _} -> type == :input end)

      # Invalid field name
      invalid_name_fields = [
        %{name: "123invalid", type: "string", description: "Invalid name"}
      ]

      assert {:error, errors} =
               EnhancedValidator.validate_field_definitions(invalid_name_fields, :input)

      assert Enum.any?(errors, fn {type, _} -> type == :invalid_field_name end)
    end
  end
end

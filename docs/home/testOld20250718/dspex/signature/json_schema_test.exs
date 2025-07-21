defmodule DSPex.Signature.JsonSchemaTest do
  use ExUnit.Case
  doctest DSPex.Signature.JsonSchema

  alias DSPex.Signature.JsonSchema

  @basic_signature %{
    inputs: [{:question, :string, []}],
    outputs: [{:answer, :string, []}],
    module: TestSignature
  }

  @complex_signature %{
    inputs: [
      {:query, :string, []},
      {:context, {:list, :string}, []}
    ],
    outputs: [
      {:answer, :string, []},
      {:confidence, :float, []},
      {:reasoning, {:list, :string}, []}
    ],
    module: ComplexSignature
  }

  @ml_signature %{
    inputs: [{:text, :string, []}],
    outputs: [
      {:embedding, :embedding, []},
      {:probability, :probability, []},
      {:confidence, :confidence_score, []},
      {:steps, :reasoning_chain, []}
    ],
    module: MLSignature
  }

  describe "OpenAI schema generation" do
    test "generates basic OpenAI schema" do
      schema = JsonSchema.generate(@basic_signature, :openai)

      assert schema.type == "object"
      assert schema.additionalProperties == false
      assert is_map(schema.properties)
      assert is_list(schema.required)
      assert is_binary(schema.description)
    end

    test "includes correct properties" do
      schema = JsonSchema.generate(@basic_signature, :openai)

      assert schema.properties.question.type == "string"
      assert schema.properties.answer.type == "string"
    end

    test "includes required fields" do
      schema = JsonSchema.generate(@basic_signature, :openai)

      assert "question" in schema.required
      assert "answer" in schema.required
    end

    test "handles complex types" do
      schema = JsonSchema.generate(@complex_signature, :openai)

      # List type
      context_prop = schema.properties.context
      assert context_prop.type == "array"
      assert context_prop.items.type == "string"

      # Multiple outputs
      assert schema.properties.answer.type == "string"
      assert schema.properties.confidence.type == "number"

      reasoning_prop = schema.properties.reasoning
      assert reasoning_prop.type == "array"
      assert reasoning_prop.items.type == "string"
    end

    test "handles ML-specific types" do
      schema = JsonSchema.generate(@ml_signature, :openai)

      # Embedding
      embedding_prop = schema.properties.embedding
      assert embedding_prop.type == "array"
      assert embedding_prop.items.type == "number"
      assert embedding_prop.description == "Vector embedding"

      # Probability with constraints
      prob_prop = schema.properties.probability
      assert prob_prop.type == "number"
      assert prob_prop.minimum == 0.0
      assert prob_prop.maximum == 1.0

      # Confidence score
      conf_prop = schema.properties.confidence
      assert conf_prop.type == "number"
      assert conf_prop.minimum == 0.0
      assert conf_prop.maximum == 1.0

      # Reasoning chain
      steps_prop = schema.properties.steps
      assert steps_prop.type == "array"
      assert steps_prop.items.type == "string"
    end
  end

  describe "Anthropic schema generation" do
    test "generates basic Anthropic schema" do
      schema = JsonSchema.generate(@basic_signature, :anthropic)

      assert is_map(schema.input_schema)
      assert schema.input_schema.type == "object"
      assert schema.input_schema.additionalProperties == false
      assert is_binary(schema.description)
    end

    test "includes only input fields in input_schema" do
      schema = JsonSchema.generate(@complex_signature, :anthropic)

      # Should include inputs
      assert Map.has_key?(schema.input_schema.properties, :query)
      assert Map.has_key?(schema.input_schema.properties, :context)

      # Should not include outputs
      refute Map.has_key?(schema.input_schema.properties, :answer)
      refute Map.has_key?(schema.input_schema.properties, :confidence)
    end

    test "includes correct required fields for inputs" do
      schema = JsonSchema.generate(@complex_signature, :anthropic)

      assert "query" in schema.input_schema.required
      assert "context" in schema.input_schema.required
      refute "answer" in schema.input_schema.required
    end
  end

  describe "Generic JSON Schema generation" do
    test "generates valid JSON Schema" do
      schema = JsonSchema.generate(@basic_signature, :generic)

      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert schema.type == "object"
      assert is_binary(schema.title)
      assert is_binary(schema.description)
      assert is_map(schema.properties)
      assert is_list(schema.required)
      assert schema.additionalProperties == false
    end

    test "generates appropriate title and description" do
      schema = JsonSchema.generate(@basic_signature, :generic)

      assert schema.title == "TestSignature"
      assert schema.description =~ "TestSignature signature"
      assert schema.description =~ "question: string -> answer: string"
    end
  end

  describe "type mapping" do
    test "maps basic types correctly" do
      string_schema = JsonSchema.type_to_json_schema(:string, [])
      assert string_schema.type == "string"

      integer_schema = JsonSchema.type_to_json_schema(:integer, [])
      assert integer_schema.type == "integer"

      float_schema = JsonSchema.type_to_json_schema(:float, [])
      assert float_schema.type == "number"

      boolean_schema = JsonSchema.type_to_json_schema(:boolean, [])
      assert boolean_schema.type == "boolean"
    end

    test "maps ML types with constraints" do
      prob_schema = JsonSchema.type_to_json_schema(:probability, [])
      assert prob_schema.type == "number"
      assert prob_schema.minimum == 0.0
      assert prob_schema.maximum == 1.0

      embedding_schema = JsonSchema.type_to_json_schema(:embedding, [])
      assert embedding_schema.type == "array"
      assert embedding_schema.items.type == "number"
    end

    test "maps composite types" do
      list_schema = JsonSchema.type_to_json_schema({:list, :string}, [])
      assert list_schema.type == "array"
      assert list_schema.items.type == "string"

      dict_schema = JsonSchema.type_to_json_schema({:dict, :string, :integer}, [])
      assert dict_schema.type == "object"
      assert dict_schema.additionalProperties.type == "integer"

      union_schema = JsonSchema.type_to_json_schema({:union, [:string, :integer]}, [])
      assert is_list(union_schema.oneOf)
      assert length(union_schema.oneOf) == 2
    end

    test "handles unknown types gracefully" do
      unknown_schema = JsonSchema.type_to_json_schema(:unknown_type, [])
      assert is_binary(unknown_schema.description)
      assert unknown_schema.description =~ "Unknown type"
    end
  end

  describe "constraint application" do
    test "applies string constraints" do
      constraints = [min_length: 5, max_length: 100, pattern: "^[A-Z]"]
      schema = JsonSchema.type_to_json_schema(:string, constraints)

      assert schema.minLength == 5
      assert schema.maxLength == 100
      assert schema.pattern == "^[A-Z]"
    end

    test "applies numeric constraints" do
      constraints = [minimum: 0, maximum: 100, multiple_of: 5]
      schema = JsonSchema.type_to_json_schema(:integer, constraints)

      assert schema.minimum == 0
      assert schema.maximum == 100
      assert schema.multipleOf == 5
    end

    test "applies array constraints" do
      constraints = [min_items: 1, max_items: 10, unique_items: true]
      schema = JsonSchema.type_to_json_schema({:list, :string}, constraints)

      assert schema.minItems == 1
      assert schema.maxItems == 10
      assert schema.uniqueItems == true
    end

    test "ignores irrelevant constraints" do
      # String constraints on integer type should be ignored
      constraints = [min_length: 5, max_length: 100]
      schema = JsonSchema.type_to_json_schema(:integer, constraints)

      refute Map.has_key?(schema, :minLength)
      refute Map.has_key?(schema, :maxLength)
    end
  end

  describe "required fields extraction" do
    test "extracts required fields from field definitions" do
      fields = [
        {:name, :string, []},
        {:age, :integer, []},
        {:email, :string, [optional: true]}
      ]

      required = JsonSchema.get_required_fields(fields)
      assert "name" in required
      assert "age" in required
      refute "email" in required
    end

    test "treats all fields as required by default" do
      fields = [
        {:question, :string, []},
        {:answer, :string, []}
      ]

      required = JsonSchema.get_required_fields(fields)
      assert "question" in required
      assert "answer" in required
      assert length(required) == 2
    end
  end

  describe "schema validation" do
    test "validates correct OpenAI schema" do
      schema = JsonSchema.generate(@basic_signature, :openai)
      assert :ok = JsonSchema.validate_schema(schema)
    end

    test "validates correct Anthropic schema" do
      schema = JsonSchema.generate(@basic_signature, :anthropic)
      assert :ok = JsonSchema.validate_schema(schema)
    end

    test "rejects invalid schema structure" do
      invalid_schema = %{invalid: "structure"}
      assert {:error, _} = JsonSchema.validate_schema(invalid_schema)
    end
  end

  describe "complexity estimation" do
    test "estimates complexity for simple schema" do
      schema = JsonSchema.generate(@basic_signature, :openai)
      complexity = JsonSchema.estimate_complexity(schema)
      assert is_integer(complexity)
      assert complexity > 0
    end

    test "estimates higher complexity for complex schema" do
      simple_schema = JsonSchema.generate(@basic_signature, :openai)
      complex_schema = JsonSchema.generate(@complex_signature, :openai)

      simple_complexity = JsonSchema.estimate_complexity(simple_schema)
      complex_complexity = JsonSchema.estimate_complexity(complex_schema)

      assert complex_complexity > simple_complexity
    end

    test "handles schema without properties" do
      minimal_schema = %{type: "string"}
      complexity = JsonSchema.estimate_complexity(minimal_schema)
      assert complexity == 1
    end
  end

  describe "error handling" do
    test "raises error for unsupported provider" do
      assert_raise RuntimeError, ~r/Unsupported provider/, fn ->
        JsonSchema.generate(@basic_signature, :unsupported)
      end
    end

    test "handles malformed signature gracefully" do
      malformed_signature = %{invalid: "structure"}

      assert_raise RuntimeError, fn ->
        JsonSchema.generate(malformed_signature, :openai)
      end
    end
  end

  describe "property generation" do
    test "generates properties from field definitions" do
      fields = [
        {:name, :string, []},
        {:age, :integer, []},
        {:scores, {:list, :float}, []}
      ]

      properties = JsonSchema.generate_properties(fields)

      assert properties.name.type == "string"
      assert properties.age.type == "integer"
      assert properties.scores.type == "array"
      assert properties.scores.items.type == "number"
    end

    test "preserves field constraints in properties" do
      fields = [
        {:name, :string, [min_length: 2, max_length: 50]},
        {:age, :integer, [minimum: 0, maximum: 150]}
      ]

      properties = JsonSchema.generate_properties(fields)

      assert properties.name.minLength == 2
      assert properties.name.maxLength == 50
      assert properties.age.minimum == 0
      assert properties.age.maximum == 150
    end
  end
end

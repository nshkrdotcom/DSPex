defmodule AshDSPex.SignatureTest do
  use ExUnit.Case
  doctest AshDSPex.Signature

  # Test signature modules - using manual AST until DSL is working
  defmodule TestSignature do
    use AshDSPex.Signature
    @signature_ast {:->, [], [[{:question, :string}], [{:answer, :string}]]}
  end

  defmodule ComplexSignature do
    use AshDSPex.Signature

    @signature_ast {:->, [],
                    [
                      [{:query, :string}, {:context, {:list, :string}}],
                      [{:answer, :string}, {:confidence, :float}, {:reasoning, {:list, :string}}]
                    ]}
  end

  defmodule MLSignature do
    use AshDSPex.Signature

    @signature_ast {:->, [],
                    [
                      [{:text, :string}],
                      [
                        {:embedding, :embedding},
                        {:probability, :probability},
                        {:confidence, :confidence_score},
                        {:steps, :reasoning_chain}
                      ]
                    ]}
  end

  describe "basic signature compilation" do
    test "compiles simple signature" do
      signature = TestSignature.__signature__()

      assert signature.inputs == [{:question, :string, []}]
      assert signature.outputs == [{:answer, :string, []}]
      assert signature.module == TestSignature
    end

    test "generates expected functions" do
      assert function_exported?(TestSignature, :__signature__, 0)
      assert function_exported?(TestSignature, :input_fields, 0)
      assert function_exported?(TestSignature, :output_fields, 0)
      assert function_exported?(TestSignature, :validate_inputs, 1)
      assert function_exported?(TestSignature, :validate_outputs, 1)
      assert function_exported?(TestSignature, :to_json_schema, 1)
      assert function_exported?(TestSignature, :describe, 0)
    end

    test "input_fields returns correct structure" do
      fields = TestSignature.input_fields()
      assert fields == [{:question, :string, []}]
    end

    test "output_fields returns correct structure" do
      fields = TestSignature.output_fields()
      assert fields == [{:answer, :string, []}]
    end

    test "describe returns human-readable format" do
      description = TestSignature.describe()
      assert description == "question: string -> answer: string"
    end
  end

  describe "complex signature compilation" do
    test "compiles multi-field signature" do
      signature = ComplexSignature.__signature__()

      assert signature.inputs == [
               {:query, :string, []},
               {:context, {:list, :string}, []}
             ]

      assert signature.outputs == [
               {:answer, :string, []},
               {:confidence, :float, []},
               {:reasoning, {:list, :string}, []}
             ]
    end

    test "ML signature compiles with special types" do
      signature = MLSignature.__signature__()

      assert signature.inputs == [{:text, :string, []}]

      assert signature.outputs == [
               {:embedding, :embedding, []},
               {:probability, :probability, []},
               {:confidence, :confidence_score, []},
               {:steps, :reasoning_chain, []}
             ]
    end
  end

  describe "validation" do
    test "validates correct inputs" do
      {:ok, validated} = TestSignature.validate_inputs(%{question: "What is 2+2?"})
      assert validated.question == "What is 2+2?"
    end

    test "validates correct outputs" do
      {:ok, validated} = TestSignature.validate_outputs(%{answer: "4"})
      assert validated.answer == "4"
    end

    test "rejects missing fields" do
      {:error, reason} = TestSignature.validate_inputs(%{})
      assert reason =~ "Missing required field: question"
    end

    test "rejects wrong types" do
      {:error, reason} = TestSignature.validate_inputs(%{question: 123})
      assert reason =~ "Expected :string"
    end

    test "validates complex inputs" do
      data = %{
        query: "Find information",
        context: ["database", "search"]
      }

      {:ok, validated} = ComplexSignature.validate_inputs(data)
      assert validated.query == "Find information"
      assert validated.context == ["database", "search"]
    end

    test "validates ML-specific types" do
      data = %{
        embedding: [0.1, 0.2, 0.3],
        probability: 0.85,
        confidence: 0.9,
        steps: ["analyze", "reason", "conclude"]
      }

      {:ok, validated} = MLSignature.validate_outputs(data)
      assert validated.embedding == [0.1, 0.2, 0.3]
      assert validated.probability == 0.85
    end
  end

  describe "JSON schema generation" do
    test "generates OpenAI compatible schema" do
      schema = TestSignature.to_json_schema(:openai)

      assert schema.type == "object"
      assert schema.properties.question.type == "string"
      assert schema.properties.answer.type == "string"
      assert "question" in schema.required
      assert "answer" in schema.required
      assert schema.additionalProperties == false
    end

    test "generates Anthropic compatible schema" do
      schema = TestSignature.to_json_schema(:anthropic)

      assert schema.input_schema.type == "object"
      assert schema.input_schema.properties.question.type == "string"
      assert "question" in schema.input_schema.required
    end

    test "generates generic JSON schema" do
      schema = TestSignature.to_json_schema(:generic)

      assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert schema.type == "object"
      assert is_binary(schema.title)
      assert is_binary(schema.description)
    end

    test "generates schema for complex types" do
      schema = ComplexSignature.to_json_schema(:openai)

      # Check list type
      context_prop = schema.properties.context
      assert context_prop.type == "array"
      assert context_prop.items.type == "string"

      # Check multiple outputs
      assert schema.properties.answer.type == "string"
      assert schema.properties.confidence.type == "number"
      assert schema.properties.reasoning.type == "array"
    end

    test "generates schema for ML types" do
      schema = MLSignature.to_json_schema(:openai)

      # Check embedding
      embedding_prop = schema.properties.embedding
      assert embedding_prop.type == "array"
      assert embedding_prop.items.type == "number"

      # Check probability with constraints
      prob_prop = schema.properties.probability
      assert prob_prop.type == "number"
      assert prob_prop.minimum == 0.0
      assert prob_prop.maximum == 1.0
    end
  end

  describe "error handling" do
    test "raises error for missing signature" do
      assert_raise RuntimeError, ~r/does not define a signature/, fn ->
        defmodule MissingSignature do
          use AshDSPex.Signature
          # No signature definition
        end
      end
    end

    test "raises error for invalid syntax" do
      assert_raise RuntimeError, ~r/Invalid signature syntax/, fn ->
        defmodule InvalidSignature do
          use AshDSPex.Signature
          @signature_ast :invalid_syntax
        end
      end
    end

    test "raises error for unsupported types" do
      assert_raise RuntimeError, ~r/Invalid type/, fn ->
        defmodule UnsupportedType do
          use AshDSPex.Signature
          @signature_ast {:->, [], [[{:input, :unsupported_type}], [{:output, :string}]]}
        end
      end
    end
  end
end

#!/usr/bin/env elixir

# Demo of the AshDSPex signature system

defmodule Demo.QASignature do
  use AshDSPex.Signature
  @signature_ast {:->, [], [[{:question, :string}], [{:answer, :string}]]}
end

defmodule Demo.ComplexSignature do
  use AshDSPex.Signature
  @signature_ast {:->, [], [
    [{:query, :string}, {:context, {:list, :string}}], 
    [{:answer, :string}, {:confidence, :probability}, {:reasoning, {:list, :string}}]
  ]}
end

# Demonstrate basic functionality
IO.puts("=== AshDSPex Signature System Demo ===\n")

# Show signature metadata
IO.puts("Simple QA Signature:")
signature = Demo.QASignature.__signature__()
IO.inspect(signature, pretty: true)

IO.puts("\nComplex Signature:")
complex_signature = Demo.ComplexSignature.__signature__()
IO.inspect(complex_signature, pretty: true)

# Show validation
IO.puts("\n=== Validation Demo ===")

# Valid input
valid_input = %{question: "What is 2+2?"}
case Demo.QASignature.validate_inputs(valid_input) do
  {:ok, validated} -> 
    IO.puts("✓ Valid input validation passed:")
    IO.inspect(validated)
  {:error, reason} -> 
    IO.puts("✗ Validation failed: #{reason}")
end

# Invalid input (missing field)
invalid_input = %{}
case Demo.QASignature.validate_inputs(invalid_input) do
  {:ok, validated} -> 
    IO.puts("✓ Validation passed:")
    IO.inspect(validated)
  {:error, reason} -> 
    IO.puts("✗ Invalid input correctly rejected: #{reason}")
end

# Show JSON schema generation
IO.puts("\n=== JSON Schema Generation ===")

IO.puts("OpenAI Schema:")
openai_schema = Demo.QASignature.to_json_schema(:openai)
IO.inspect(openai_schema, pretty: true)

IO.puts("\nAnthropic Schema:")
anthropic_schema = Demo.QASignature.to_json_schema(:anthropic)
IO.inspect(anthropic_schema, pretty: true)

# Show complex type validation
IO.puts("\n=== Complex Type Validation ===")

complex_input = %{
  query: "Find information about machine learning",
  context: ["AI", "deep learning", "neural networks"]
}

case Demo.ComplexSignature.validate_inputs(complex_input) do
  {:ok, validated} -> 
    IO.puts("✓ Complex input validation passed:")
    IO.inspect(validated)
  {:error, reason} -> 
    IO.puts("✗ Validation failed: #{reason}")
end

complex_output = %{
  answer: "Machine learning is a subset of AI...",
  confidence: 0.85,
  reasoning: ["Analyzed context", "Cross-referenced sources", "Synthesized answer"]
}

case Demo.ComplexSignature.validate_outputs(complex_output) do
  {:ok, validated} -> 
    IO.puts("✓ Complex output validation passed:")
    IO.inspect(validated)
  {:error, reason} -> 
    IO.puts("✗ Validation failed: #{reason}")
end

IO.puts("\n=== Demo Complete ===")
IO.puts("The AshDSPex signature system is working correctly!")
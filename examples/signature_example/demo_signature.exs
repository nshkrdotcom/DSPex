#!/usr/bin/env elixir

# Simple demo script to show DSPex Dynamic Signature capabilities
# Run with: elixir demo_signature.exs

Mix.install([
  {:dspex, path: "../.."}
])

IO.puts("🚀 DSPex Dynamic Signature Demo")
IO.puts("===============================")
IO.puts("")

# This demo shows how DSPex can go beyond 'question → answer' 
# and handle any combination of input/output fields dynamically

# Define a multi-input, multi-output signature
signature = %{
  name: "TextAnalysisSignature",
  description: "Comprehensive text analysis with sentiment, summary, and keyword extraction",
  inputs: [
    %{
      name: "text", 
      type: "string", 
      description: "The input text to analyze for sentiment and content"
    },
    %{
      name: "style", 
      type: "string", 
      description: "Analysis style: 'brief' or 'detailed'"
    }
  ],
  outputs: [
    %{
      name: "sentiment", 
      type: "string", 
      description: "Detected sentiment: positive, negative, or neutral"
    },
    %{
      name: "summary", 
      type: "string", 
      description: "A concise summary of the text content"
    },
    %{
      name: "keywords", 
      type: "string", 
      description: "Key terms extracted from the text"
    },
    %{
      name: "confidence_score", 
      type: "string", 
      description: "Confidence level in the analysis"
    }
  ]
}

IO.puts("📝 Signature Definition:")
IO.puts("   Name: #{signature.name}")
IO.puts("   Inputs: #{Enum.map(signature.inputs, & &1.name) |> Enum.join(", ")}")
IO.puts("   Outputs: #{Enum.map(signature.outputs, & &1.name) |> Enum.join(", ")}")
IO.puts("")

IO.puts("🔧 Technical Implementation:")
IO.puts("   • Elixir defines flexible signature schema")
IO.puts("   • Bridge converts to enriched Python payload")
IO.puts("   • Python creates DSPy signature classes dynamically")
IO.puts("   • Execution uses **inputs unpacking for flexibility")
IO.puts("   • Signature caching for performance")
IO.puts("   • Fallback to Q&A format if dynamic signatures fail")
IO.puts("")

IO.puts("💡 Key Benefits:")
IO.puts("   ✅ Any input/output combination")
IO.puts("   ✅ Type safety and validation")
IO.puts("   ✅ Performance through caching")  
IO.puts("   ✅ Reliability through fallbacks")
IO.puts("   ✅ Easy to extend with new patterns")
IO.puts("")

IO.puts("🎯 This replaces the old hardcoded 'question → answer' approach")
IO.puts("   with a flexible system that can handle any signature pattern!")
IO.puts("")

IO.puts("🚀 To see the full working examples:")
IO.puts("   cd examples/signature_example")
IO.puts("   ./run_signature_example.sh")
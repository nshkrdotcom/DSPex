# Basic DSPex Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/basic.exs
#
# Requires: GEMINI_API_KEY environment variable

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Basic Example")
  IO.puts("===================\n")

  # Create and configure LM using native bindings
  IO.puts("1. Creating language model...")
  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [], temperature: 0.7)
  IO.puts("   Created: gemini/gemini-flash-lite-latest")

  IO.puts("\n2. Configuring DSPy...")
  {:ok, _} = Dspy.configure(lm: lm)
  IO.puts("   Configured!")

  # Create predictor using native bindings
  IO.puts("\n3. Creating Predict module...")
  {:ok, predict} = Dspy.PredictClass.new("question -> answer", [])
  IO.puts("   Created!")

  # Run prediction using native method call
  IO.puts("\n4. Running prediction...")
  question = "What is the capital of Hawaii?"
  IO.puts("   Q: #{question}")

  {:ok, result} = Dspy.PredictClass.forward(predict, question: question)
  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   A: #{answer}")

  IO.puts("\nDone!")
end

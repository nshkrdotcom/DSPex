# Basic DSPex Example
#
# Run with: mix run --no-start examples/basic.exs
#
# Requires: GEMINI_API_KEY environment variable

DSPex.run(fn ->
  IO.puts("DSPex Basic Example")
  IO.puts("===================\n")

  # Create and configure LM
  IO.puts("1. Creating language model...")
  lm = DSPex.lm!("gemini/gemini-flash-lite-latest", temperature: 0.7)
  IO.puts("   Created: gemini/gemini-flash-lite-latest")

  IO.puts("\n2. Configuring DSPy...")
  DSPex.configure!(lm: lm)
  IO.puts("   Configured!")

  # Create predictor
  IO.puts("\n3. Creating Predict module...")
  predict = DSPex.predict!("question -> answer")
  IO.puts("   Created!")

  # Run prediction
  IO.puts("\n4. Running prediction...")
  question = "What is the capital of Hawaii?"
  IO.puts("   Q: #{question}")

  result = DSPex.method!(predict, "forward", [], question: question)
  answer = DSPex.attr!(result, "answer")
  IO.puts("   A: #{answer}")

  IO.puts("\nDone!")
end)

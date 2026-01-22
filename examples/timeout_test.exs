# Timeout Configuration Examples - Using Generated Native Bindings
#
# Demonstrates SnakeBridge 0.13+ timeout architecture
#
# Run with: mix run --no-start examples/timeout_test.exs

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Timeout Configuration Examples")
  IO.puts("=====================================\n")

  # Setup using native bindings
  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [])
  {:ok, _} = Dspy.configure(lm: lm)
  {:ok, predict} = Dspy.PredictClass.new("question -> answer", [])

  # -------------------------------------------------------------------------
  # Example 1: Default timeout (10 min via ml_inference profile)
  # -------------------------------------------------------------------------
  IO.puts("1. Default timeout (ml_inference profile = 10 min)")
  IO.puts("   DSPy calls automatically use :ml_inference profile")

  {:ok, result} = Dspy.PredictClass.forward(predict, question: "What is 2+2?")
  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 2: Per-call timeout override with exact milliseconds
  # -------------------------------------------------------------------------
  IO.puts("2. Per-call timeout override (exact milliseconds)")
  IO.puts("   Using __runtime__: [timeout: 120_000] for 2 minute timeout")

  {:ok, result} =
    Dspy.PredictClass.forward(predict,
      question: "What is the capital of France?",
      __runtime__: [timeout: 120_000]
    )

  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 3: Per-call timeout override with profile
  # -------------------------------------------------------------------------
  IO.puts("3. Per-call timeout with profile")
  IO.puts("   Using __runtime__: [timeout_profile: :batch_job] for 1 hour timeout")

  {:ok, result} =
    Dspy.PredictClass.forward(predict,
      question: "Explain quantum computing briefly",
      __runtime__: [timeout_profile: :batch_job]
    )

  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 4: Direct runtime option passing
  # -------------------------------------------------------------------------
  IO.puts("4. Direct runtime option passing")
  IO.puts("   Passing timeout directly in opts")

  {:ok, result} =
    Dspy.PredictClass.forward(predict,
      question: "What color is the sky?",
      __runtime__: [timeout: 60_000]
    )

  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 5: Using streaming profile
  # -------------------------------------------------------------------------
  IO.puts("5. Using streaming timeout profile")

  {:ok, result} =
    Dspy.PredictClass.forward(predict,
      question: "What is 1+1?",
      __runtime__: [timeout_profile: :streaming]
    )

  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 6: Custom timeout in milliseconds
  # -------------------------------------------------------------------------
  IO.puts("6. Custom timeout (90 seconds)")

  {:ok, result} =
    Dspy.PredictClass.forward(predict,
      question: "Name a planet",
      __runtime__: [timeout: 90_000]
    )

  {:ok, answer} = SnakeBridge.attr(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Timeout Profile Reference
  # -------------------------------------------------------------------------
  IO.puts("Timeout Profile Reference:")
  IO.puts("  :default      - 2 minutes   (standard Python calls)")
  IO.puts("  :streaming    - 30 minutes  (streaming responses)")
  IO.puts("  :ml_inference - 10 minutes  (LLM inference, DSPex default)")
  IO.puts("  :batch_job    - 1 hour      (long-running batch operations)")
  IO.puts("\nDone!")
end

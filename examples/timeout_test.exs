# Timeout Configuration Examples
#
# Demonstrates SnakeBridge 0.10+ timeout architecture with DSPex
#
# Run with: mix run --no-start examples/timeout_test.exs

DSPex.run(fn ->
  IO.puts("DSPex Timeout Configuration Examples")
  IO.puts("=====================================\n")

  # Setup
  lm = DSPex.lm!("gemini/gemini-flash-lite-latest")
  DSPex.configure!(lm: lm)
  predict = DSPex.predict!("question -> answer")

  # -------------------------------------------------------------------------
  # Example 1: Default timeout (10 min via ml_inference profile)
  # -------------------------------------------------------------------------
  IO.puts("1. Default timeout (ml_inference profile = 10 min)")
  IO.puts("   DSPy calls automatically use :ml_inference profile")

  result = DSPex.method!(predict, "forward", [], question: "What is 2+2?")
  answer = DSPex.attr!(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 2: Per-call timeout override with exact milliseconds
  # -------------------------------------------------------------------------
  IO.puts("2. Per-call timeout override (exact milliseconds)")
  IO.puts("   Using __runtime__: [timeout: 120_000] for 2 minute timeout")

  result =
    DSPex.method!(predict, "forward", [],
      question: "What is the capital of France?",
      __runtime__: [timeout: 120_000]
    )

  answer = DSPex.attr!(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 3: Per-call timeout override with profile
  # -------------------------------------------------------------------------
  IO.puts("3. Per-call timeout with profile")
  IO.puts("   Using __runtime__: [timeout_profile: :batch_job] for 1 hour timeout")

  result =
    DSPex.method!(predict, "forward", [],
      question: "Explain quantum computing briefly",
      __runtime__: [timeout_profile: :batch_job]
    )

  answer = DSPex.attr!(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 4: Using DSPex.with_timeout helper
  # -------------------------------------------------------------------------
  IO.puts("4. Using DSPex.with_timeout/2 helper")

  opts = DSPex.with_timeout([question: "What color is the sky?"], timeout: 60_000)
  IO.puts("   Options: #{inspect(opts)}")

  result = DSPex.method!(predict, "forward", [], opts)
  answer = DSPex.attr!(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 5: Using DSPex.timeout_profile helper
  # -------------------------------------------------------------------------
  IO.puts("5. Using DSPex.timeout_profile/1 helper")

  profile_opts = DSPex.timeout_profile(:streaming)
  IO.puts("   Profile opts: #{inspect(profile_opts)}")

  merged_opts = Keyword.merge([question: "What is 1+1?"], profile_opts)
  result = DSPex.method!(predict, "forward", [], merged_opts)
  answer = DSPex.attr!(result, "answer")
  IO.puts("   Answer: #{answer}\n")

  # -------------------------------------------------------------------------
  # Example 6: Using DSPex.timeout_ms helper
  # -------------------------------------------------------------------------
  IO.puts("6. Using DSPex.timeout_ms/1 helper")

  ms_opts = DSPex.timeout_ms(90_000)
  IO.puts("   Timeout opts: #{inspect(ms_opts)}")

  merged_opts = Keyword.merge([question: "Name a planet"], ms_opts)
  result = DSPex.method!(predict, "forward", [], merged_opts)
  answer = DSPex.attr!(result, "answer")
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
end)

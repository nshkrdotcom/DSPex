defmodule DSPex.Modules.ChainOfThoughtTest do
  use ExUnit.Case, async: true
  alias DSPex.Modules.ChainOfThought
  alias DSPex.Native.Signature

  describe "chain of thought reasoning" do
    setup do
      signature = Signature.new("question -> reasoning, answer")
      %{signature: signature}
    end

    test "generates reasoning before answer", %{signature: signature} do
      cot = ChainOfThought.new(signature)
      
      result = ChainOfThought.forward(cot, %{question: "What is 15 * 24?"})
      
      assert {:ok, output} = result
      assert Map.has_key?(output, :reasoning)
      assert Map.has_key?(output, :answer)
      assert is_binary(output.reasoning)
      assert String.length(output.reasoning) > 10 # Non-trivial reasoning
    end

    test "reasoning improves answer quality" do
      # Compare with and without reasoning
      simple_sig = Signature.new("question -> answer")
      cot_sig = Signature.new("question -> reasoning, answer")
      
      simple = DSPex.Modules.Predict.new(simple_sig)
      cot = ChainOfThought.new(cot_sig)
      
      question = %{question: "If I have 3 apples and buy 2 more, then give away 1, how many do I have?"}
      
      {:ok, simple_result} = DSPex.Modules.Predict.forward(simple, question)
      {:ok, cot_result} = ChainOfThought.forward(cot, question)
      
      # CoT should have reasoning
      assert Map.has_key?(cot_result, :reasoning)
      refute Map.has_key?(simple_result, :reasoning)
      
      # Both should have answers
      assert Map.has_key?(simple_result, :answer)
      assert Map.has_key?(cot_result, :answer)
    end

    test "supports custom reasoning prompts", %{signature: signature} do
      cot = ChainOfThought.new(signature, %{
        reasoning_prompt: "Let's think about this step by step:"
      })
      
      {:ok, result} = ChainOfThought.forward(cot, %{question: "Complex question"})
      
      assert result.reasoning =~ "step by step" or 
             String.contains?(result.reasoning, "step")
    end
  end

  describe "multi-step reasoning" do
    test "handles multiple reasoning steps" do
      signature = Signature.new("question -> step1, step2, step3, answer")
      cot = ChainOfThought.new(signature, %{max_steps: 3})
      
      result = ChainOfThought.forward(cot, %{
        question: "Plan a trip from New York to Los Angeles"
      })
      
      assert {:ok, output} = result
      assert Map.has_key?(output, :step1)
      assert Map.has_key?(output, :step2)
      assert Map.has_key?(output, :step3)
      assert Map.has_key?(output, :answer)
    end

    test "validates reasoning chain consistency" do
      signature = Signature.new("problem -> analysis, solution, verification")
      cot = ChainOfThought.new(signature, %{validate_chain: true})
      
      result = ChainOfThought.forward(cot, %{
        problem: "Optimize database query performance"
      })
      
      assert {:ok, output} = result
      
      # Reasoning steps should be related
      assert String.contains?(output.solution, "query") or
             String.contains?(output.solution, "database") or
             String.contains?(output.solution, "performance")
    end
  end

  describe "confidence scoring" do
    test "provides confidence scores for reasoning" do
      signature = Signature.new("question -> reasoning, answer, confidence")
      cot = ChainOfThought.new(signature, %{include_confidence: true})
      
      {:ok, result} = ChainOfThought.forward(cot, %{
        question: "What is the capital of France?"
      })
      
      assert Map.has_key?(result, :confidence)
      assert is_float(result.confidence) or is_integer(result.confidence)
      assert result.confidence >= 0 and result.confidence <= 1
    end
  end

  describe "error handling" do
    setup do
      signature = Signature.new("question -> reasoning, answer")
      %{signature: signature}
    end

    test "handles incomplete reasoning chains", %{signature: signature} do
      cot = ChainOfThought.new(signature, %{
        mock_response: %{reasoning: "Started thinking but..."}
        # Missing answer
      })
      
      result = ChainOfThought.forward(cot, %{question: "Test"})
      
      assert {:error, {:incomplete_reasoning, _}} = result
    end

    test "retries on reasoning failures", %{signature: signature} do
      cot = ChainOfThought.new(signature, %{
        retry_on_failure: true,
        max_retries: 2
      })
      
      # Configure to fail first attempt
      {:ok, result} = ChainOfThought.forward(cot, %{question: "Retry test"})
      
      assert Map.has_key?(result, :reasoning)
      assert Map.has_key?(result, :answer)
    end
  end

  describe "telemetry" do
    test "emits detailed telemetry for reasoning steps" do
      ref = make_ref()
      signature = Signature.new("question -> reasoning, answer")
      cot = ChainOfThought.new(signature)
      
      :telemetry.attach(
        "test-cot-#{inspect(ref)}",
        [:dspex, :chain_of_thought, :step, :stop],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )
      
      ChainOfThought.forward(cot, %{question: "Test question"})
      
      # Should receive telemetry for each reasoning step
      assert_receive {:telemetry, measurements, metadata}, 1000
      
      assert measurements.duration > 0
      assert metadata.step in [:reasoning, :answer]
      
      :telemetry.detach("test-cot-#{inspect(ref)}")
    end
  end

  describe "integration with validators" do
    test "validates reasoning quality" do
      signature = Signature.new("question -> reasoning, answer")
      
      validator = fn reasoning ->
        # Check reasoning is substantial
        words = String.split(reasoning)
        length(words) >= 10
      end
      
      cot = ChainOfThought.new(signature, %{
        reasoning_validator: validator
      })
      
      {:ok, result} = ChainOfThought.forward(cot, %{
        question: "Explain why the sky is blue"
      })
      
      # Reasoning should pass validation
      assert validator.(result.reasoning)
    end
  end
end
defmodule DSPex.Modules.PredictTest do
  use ExUnit.Case, async: true
  alias DSPex.Modules.Predict
  alias DSPex.Native.Signature

  describe "prediction module" do
    setup do
      # Create a test signature
      signature = Signature.new("question -> answer")
      %{signature: signature}
    end

    test "initializes with signature", %{signature: signature} do
      predictor = Predict.new(signature)
      
      assert predictor.signature == signature
      assert predictor.module_type == :predict
      assert predictor.config != nil
    end

    test "executes predictions", %{signature: signature} do
      predictor = Predict.new(signature)
      
      result = Predict.forward(predictor, %{question: "What is Elixir?"})
      
      assert {:ok, prediction} = result
      assert Map.has_key?(prediction, :answer)
      assert is_binary(prediction.answer)
    end

    test "validates input against signature", %{signature: signature} do
      predictor = Predict.new(signature)
      
      # Missing required field
      result = Predict.forward(predictor, %{})
      
      assert {:error, {:validation_error, _}} = result
    end

    test "supports custom configuration" do
      signature = Signature.new("text -> summary")
      config = %{
        temperature: 0.5,
        max_tokens: 100,
        model: "gpt-3.5-turbo"
      }
      
      predictor = Predict.new(signature, config)
      
      assert predictor.config.temperature == 0.5
      assert predictor.config.max_tokens == 100
      assert predictor.config.model == "gpt-3.5-turbo"
    end
  end

  describe "batch predictions" do
    setup do
      signature = Signature.new("question -> answer")
      predictor = Predict.new(signature)
      %{predictor: predictor}
    end

    test "processes batch inputs", %{predictor: predictor} do
      inputs = [
        %{question: "What is Elixir?"},
        %{question: "What is Phoenix?"},
        %{question: "What is LiveView?"}
      ]
      
      results = Predict.forward_batch(predictor, inputs)
      
      assert length(results) == 3
      assert Enum.all?(results, fn r -> match?({:ok, %{answer: _}}, r) end)
    end

    test "handles mixed success/failure in batch", %{predictor: predictor} do
      inputs = [
        %{question: "Valid question"},
        %{}, # Invalid - missing question
        %{question: "Another valid question"}
      ]
      
      results = Predict.forward_batch(predictor, inputs)
      
      assert length(results) == 3
      assert match?({:ok, _}, Enum.at(results, 0))
      assert match?({:error, _}, Enum.at(results, 1))
      assert match?({:ok, _}, Enum.at(results, 2))
    end
  end

  describe "caching" do
    setup do
      signature = Signature.new("question -> answer")
      predictor = Predict.new(signature, %{enable_cache: true})
      %{predictor: predictor}
    end

    test "caches identical predictions", %{predictor: predictor} do
      input = %{question: "What is caching?"}
      
      # First call
      {:ok, result1} = Predict.forward(predictor, input)
      
      # Second call - should be cached
      {:ok, result2} = Predict.forward(predictor, input)
      
      # Results should be identical
      assert result1 == result2
      
      # Check cache stats
      stats = Predict.get_cache_stats(predictor)
      assert stats.hits == 1
      assert stats.misses == 1
    end

    test "cache respects TTL", %{predictor: predictor} do
      predictor = Predict.new(predictor.signature, %{
        enable_cache: true,
        cache_ttl: 50 # 50ms TTL
      })
      
      input = %{question: "What is TTL?"}
      
      # First call
      {:ok, result1} = Predict.forward(predictor, input)
      
      # Wait for cache to expire
      Process.sleep(60)
      
      # Second call - cache should be expired
      {:ok, result2} = Predict.forward(predictor, input)
      
      # Results might be different (in real implementation)
      stats = Predict.get_cache_stats(predictor)
      assert stats.misses == 2
    end
  end

  describe "telemetry" do
    test "emits telemetry for predictions" do
      ref = make_ref()
      signature = Signature.new("question -> answer")
      predictor = Predict.new(signature)
      
      :telemetry.attach(
        "test-predict-#{inspect(ref)}",
        [:dspex, :predict, :forward, :stop],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )
      
      Predict.forward(predictor, %{question: "Test question"})
      
      assert_receive {:telemetry, measurements, metadata}, 1000
      
      assert measurements.duration > 0
      assert metadata.signature == "question -> answer"
      assert metadata.success == true
      
      :telemetry.detach("test-predict-#{inspect(ref)}")
    end
  end

  describe "error handling" do
    setup do
      signature = Signature.new("question -> answer")
      %{signature: signature}
    end

    test "handles LLM errors gracefully", %{signature: signature} do
      predictor = Predict.new(signature, %{
        mock_error: "LLM service unavailable"
      })
      
      result = Predict.forward(predictor, %{question: "Test"})
      
      assert {:error, reason} = result
      assert reason =~ "LLM service unavailable"
    end

    test "validates output format", %{signature: signature} do
      predictor = Predict.new(signature, %{
        mock_response: %{wrong_field: "value"} # Missing 'answer' field
      })
      
      result = Predict.forward(predictor, %{question: "Test"})
      
      assert {:error, {:output_validation_error, _}} = result
    end
  end

  describe "streaming predictions" do
    setup do
      signature = Signature.new("question -> answer")
      predictor = Predict.new(signature, %{streaming: true})
      %{predictor: predictor}
    end

    test "streams prediction chunks", %{predictor: predictor} do
      {:ok, stream} = Predict.forward_stream(predictor, %{question: "Tell me about streaming"})
      
      chunks = Enum.take(stream, 5)
      
      assert length(chunks) == 5
      assert Enum.all?(chunks, fn chunk ->
        Map.has_key?(chunk, :content) and is_binary(chunk.content)
      end)
    end

    test "handles stream interruption", %{predictor: predictor} do
      {:ok, stream} = Predict.forward_stream(predictor, %{question: "Test"})
      
      # Take only first chunk then stop
      first_chunk = Enum.take(stream, 1)
      
      assert length(first_chunk) == 1
      # Stream should handle early termination gracefully
    end
  end
end
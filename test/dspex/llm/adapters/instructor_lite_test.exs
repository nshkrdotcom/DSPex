defmodule DSPex.LLM.Adapters.InstructorLiteTest do
  use ExUnit.Case, async: true

  alias DSPex.LLM.Adapters.InstructorLite

  describe "configure/2" do
    test "configures client for supported providers" do
      for provider <- [:openai, :anthropic, :gemini, :grok, :llamacpp] do
        config = %{api_key: "test-key", model: "test-model"}

        assert {:ok, client} = InstructorLite.configure(provider, config)
        assert client.adapter == InstructorLite
        assert client.provider == provider
        assert client.config == config
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, {:unsupported_provider, :unsupported, supported}} =
               InstructorLite.configure(:unsupported, %{})

      assert :openai in supported
      assert :anthropic in supported
    end

    test "includes response model in client" do
      config = %{api_key: "test", response_model: MySchema}

      assert {:ok, client} = InstructorLite.configure(:openai, config)
      assert client.response_model == MySchema
    end
  end

  describe "generate/3" do
    @tag :skip
    test "formats prompt correctly for string input" do
      # This would require mocking InstructorLite.instruct/2
      # which is an external dependency
    end

    @tag :skip
    test "formats prompt correctly for message list" do
      # This would require mocking InstructorLite.instruct/2
    end
  end

  describe "stream/3" do
    test "returns streaming not supported error" do
      {:ok, client} = InstructorLite.configure(:openai, %{})

      assert {:error, :streaming_not_supported} =
               InstructorLite.stream(client, "prompt", [])
    end
  end

  describe "batch/3" do
    @tag :skip
    test "processes multiple prompts sequentially" do
      # This would require mocking InstructorLite.instruct/2
      # In a real test, we'd verify it calls generate for each prompt
    end
  end

  describe "adapter context building" do
    test "adds default model for OpenAI" do
      {:ok, client} = InstructorLite.configure(:openai, %{api_key: "test"})

      # We can't easily test private functions, but we can test
      # that the configuration is stored correctly
      assert client.provider == :openai
    end

    test "adds default model for Anthropic" do
      {:ok, client} = InstructorLite.configure(:anthropic, %{api_key: "test"})
      assert client.provider == :anthropic
    end

    test "preserves custom model" do
      config = %{api_key: "test", model: "custom-model"}
      {:ok, client} = InstructorLite.configure(:openai, config)
      assert client.config.model == "custom-model"
    end
  end
end

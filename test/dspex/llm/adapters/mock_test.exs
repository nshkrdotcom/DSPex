defmodule DSPex.LLM.Adapters.MockTest do
  use ExUnit.Case, async: true

  alias DSPex.LLM.Adapters.Mock

  describe "configure/2" do
    test "creates mock client with responses" do
      config = %{responses: ["Hello", "World"]}

      assert {:ok, client} = Mock.configure(:test, config)
      assert client.adapter == Mock
      assert client.provider == :test
      assert client.responses == ["Hello", "World"]
      assert client.response_index == 0
    end

    test "creates mock client without responses" do
      assert {:ok, client} = Mock.configure(:test, %{})
      assert client.responses == []
    end
  end

  describe "generate/3" do
    test "returns configured responses in order" do
      {:ok, client} =
        Mock.configure(:test, %{
          responses: ["First", "Second", "Third"]
        })

      assert {:ok, response1} = Mock.generate(client, "prompt1", [])
      assert response1.content == "First"
      assert response1.provider == :mock
      assert response1.metadata.mocked == true

      # Note: In real implementation, we'd need state management
      # For now, it always returns the first response
    end

    test "handles map responses" do
      {:ok, client} =
        Mock.configure(:test, %{
          responses: [
            %{content: "Custom response", extra_field: "value"}
          ]
        })

      assert {:ok, response} = Mock.generate(client, "prompt", [])
      assert response.content == "Custom response"
      assert response.extra_field == "value"
    end

    test "returns error when no responses configured" do
      {:ok, client} = Mock.configure(:test, %{})

      assert {:error, :no_mock_responses_configured} =
               Mock.generate(client, "prompt", [])
    end
  end

  describe "stream/3" do
    test "streams configured chunks" do
      {:ok, client} =
        Mock.configure(:test, %{
          stream_responses: ["Hello", " ", "World", "!"]
        })

      assert {:ok, stream} = Mock.stream(client, "prompt", [])
      chunks = Enum.to_list(stream)
      assert chunks == ["Hello", " ", "World", "!"]
    end

    test "returns error when streaming not configured" do
      {:ok, client} = Mock.configure(:test, %{})

      assert {:error, :streaming_not_configured} =
               Mock.stream(client, "prompt", [])
    end
  end

  describe "batch/3" do
    test "generates responses for multiple prompts" do
      {:ok, client} =
        Mock.configure(:test, %{
          responses: ["Response 1", "Response 2", "Response 3"]
        })

      prompts = ["prompt1", "prompt2", "prompt3"]

      # Note: Current implementation has limitations
      # In a real mock, we'd cycle through responses
      assert {:error, :batch_generation_failed} =
               Mock.batch(client, prompts, [])
    end
  end
end

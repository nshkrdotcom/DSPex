defmodule DSPex.LLM.ClientTest do
  use ExUnit.Case, async: true

  alias DSPex.LLM.Client

  describe "new/1" do
    test "creates client with mock adapter" do
      assert {:ok, client} =
               Client.new(
                 adapter: :mock,
                 provider: :test,
                 responses: ["Hello", "World"]
               )

      assert client.adapter_type == :mock
      assert client.provider == :test
      assert client.id
      assert client.created_at
    end

    test "selects adapter based on requirements" do
      # InstructorLite for structured output
      assert {:ok, client} =
               Client.new(
                 provider: :openai,
                 response_model: String,
                 api_key: "test"
               )

      assert client.adapter_type == :instructor_lite

      # HTTP for streaming
      assert {:ok, client} =
               Client.new(
                 provider: :openai,
                 stream: true,
                 api_key: "test"
               )

      assert client.adapter_type == :http

      # Python for local models
      assert {:ok, client} =
               Client.new(
                 provider: :huggingface,
                 local_model: true
               )

      assert client.adapter_type == :python
    end

    test "returns error for unknown adapter" do
      assert {:error, {:unknown_adapter, :nonexistent}} =
               Client.new(adapter: :nonexistent, provider: :test)
    end
  end

  describe "generate/3 with mock adapter" do
    setup do
      {:ok, client} =
        Client.new(
          adapter: :mock,
          provider: :test,
          responses: [
            "First response",
            %{content: "Second response", custom: true}
          ]
        )

      {:ok, client: client}
    end

    test "generates response from mock", %{client: client} do
      assert {:ok, response} = Client.generate(client, "test prompt")
      assert response.content == "First response"
      assert response.provider == :mock
      assert response.adapter == :mock
      assert response.metadata.mocked == true
    end

    test "returns error when no responses configured" do
      {:ok, client} = Client.new(adapter: :mock, provider: :test)

      assert {:error, :no_mock_responses_configured} =
               Client.generate(client, "test")
    end
  end

  describe "supports_streaming?/1" do
    test "returns true for HTTP adapter" do
      {:ok, client} =
        Client.new(
          adapter: :http,
          provider: :openai,
          api_key: "test"
        )

      assert Client.supports_streaming?(client)
    end

    test "returns true for Python adapter" do
      {:ok, client} =
        Client.new(
          adapter: :python,
          provider: :test
        )

      assert Client.supports_streaming?(client)
    end

    test "returns false for InstructorLite adapter" do
      {:ok, client} =
        Client.new(
          adapter: :instructor_lite,
          provider: :openai,
          api_key: "test"
        )

      refute Client.supports_streaming?(client)
    end
  end

  describe "supports_structured_output?/1" do
    test "returns true for InstructorLite adapter" do
      {:ok, client} =
        Client.new(
          adapter: :instructor_lite,
          provider: :openai,
          api_key: "test"
        )

      assert Client.supports_structured_output?(client)
    end

    test "returns false for HTTP adapter" do
      {:ok, client} =
        Client.new(
          adapter: :http,
          provider: :openai,
          api_key: "test"
        )

      refute Client.supports_structured_output?(client)
    end
  end

  describe "telemetry" do
    test "emits telemetry events on generate" do
      {:ok, client} =
        Client.new(
          adapter: :mock,
          provider: :test,
          responses: ["Success"]
        )

      :telemetry.attach(
        "test-handler",
        [:dspex, :llm, :generate],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Client.generate(client, "test")

      assert_receive {:telemetry, [:dspex, :llm, :generate], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.adapter == :mock
      assert metadata.provider == :test
      assert metadata.success == true

      :telemetry.detach("test-handler")
    end
  end
end

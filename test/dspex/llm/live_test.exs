defmodule DSPex.LLM.LiveTest do
  use ExUnit.Case

  alias DSPex.LLM.Client
  alias DSPex.TestSchemas.{SimpleResponse, MathProblem, CodeExample}

  @moduletag :live_test

  # To run these tests:
  # 1. Set GEMINI_API_KEY environment variable
  # 2. Run: mix test test/dspex/llm/live_test.exs --include live_test --exclude skip

  describe "InstructorLite with Gemini" do
    test "creates default client with Gemini configuration" do
      # This should use default config (Gemini with InstructorLite)
      assert {:ok, client} = Client.new()

      assert client.adapter_type == :instructor_lite
      assert client.provider == :gemini
      assert client.config.model == "gemini-2.0-flash-exp"
    end

    test "generates simple text response with HTTP adapter" do
      # Use HTTP adapter since InstructorLite requires structured output
      {:ok, client} =
        Client.new(
          adapter: :http,
          api_key: System.get_env("GEMINI_API_KEY")
        )

      assert {:ok, response} = Client.generate(client, "Say hello in a friendly way")

      assert response.content
      assert response.provider == :gemini
      assert response.adapter == :http
    end

    @tag :skip
    test "generates structured response with SimpleResponse schema" do
      {:ok, client} = Client.new(response_model: SimpleResponse)

      prompt = "Analyze this message: 'I love using Elixir for building robust systems!'"

      assert {:ok, response} = Client.generate(client, prompt)

      # InstructorLite returns the structured data directly
      assert %SimpleResponse{} = response.content
      assert response.content.message
      assert response.content.sentiment in [:positive, :negative, :neutral]
      assert response.metadata.structured == true
    end

    @tag :skip
    test "solves math problem with structured output" do
      {:ok, client} = Client.new(response_model: MathProblem)

      prompt =
        "Solve this step by step: If a train travels 120 miles in 2 hours, what is its average speed?"

      assert {:ok, response} = Client.generate(client, prompt)

      math_solution = response.content
      assert %MathProblem{} = math_solution
      assert math_solution.solution == 60.0
      assert is_list(math_solution.steps)
      assert length(math_solution.steps) > 0
      assert math_solution.explanation
    end

    @tag :skip
    test "generates code example with explanation" do
      {:ok, client} = Client.new(response_model: CodeExample)

      prompt = "Show me a simple Elixir function that reverses a list"

      assert {:ok, response} = Client.generate(client, prompt)

      code_example = response.content
      assert %CodeExample{} = code_example
      assert code_example.language == "elixir"
      assert code_example.code =~ "def"
      assert code_example.explanation
      assert code_example.complexity in [:beginner, :intermediate, :advanced]
    end

    @tag :skip
    test "handles API errors gracefully" do
      # Use invalid API key
      {:ok, client} = Client.new(api_key: "invalid-key")

      assert {:error, reason} = Client.generate(client, "Hello")
      assert {:instructor_lite_error, _details} = reason
    end

    @tag :skip
    test "works with custom prompts and options" do
      {:ok, client} = Client.new()

      prompt = [
        %{role: "system", content: "You are a helpful Elixir expert."},
        %{role: "user", content: "What are GenServers used for?"}
      ]

      assert {:ok, response} = Client.generate(client, prompt, max_tokens: 200)

      assert response.content
      assert response.content =~ "GenServer" or response.content =~ "process"
    end
  end

  describe "configuration" do
    test "can override default adapter" do
      {:ok, client} =
        Client.new(
          adapter: :http,
          api_key: System.get_env("GEMINI_API_KEY")
        )

      assert client.adapter_type == :http
      assert client.provider == :gemini
    end

    test "can override default provider" do
      {:ok, client} = Client.new(provider: :openai, api_key: "test-key")

      assert client.adapter_type == :instructor_lite
      assert client.provider == :openai
    end
  end
end

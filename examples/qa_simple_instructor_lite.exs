#!/usr/bin/env elixir

# Simple Q&A example using InstructorLite adapter without structured output

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:instructor_lite, "~> 1.0"},
  {:sinter, "~> 0.0.1"}
])

defmodule SimpleQAWithInstructorLite do
  @moduledoc """
  Simple example of using DSPex with InstructorLite adapter for basic question-answering
  using Google's Gemini Flash 2.0 model without structured output.
  """

  def run do
    IO.puts("\n=== Simple Q&A Example with InstructorLite Adapter ===\n")
    
    # Configure the LLM client without response model
    config = [
      adapter: :instructor_lite,
      provider: :gemini,
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini-2.0-flash-exp"
    ]
    
    case DSPex.LLM.Client.new(config) do
      {:ok, client} ->
        # Test various questions
        questions = [
          "What is the capital of Japan?",
          "Explain quantum computing in simple terms.",
          "What are the main benefits of functional programming?",
          "How does photosynthesis work?",
          "What is the difference between machine learning and AI?"
        ]
        
        Enum.each(questions, fn question ->
          IO.puts("\nQ: #{question}")
          
          case DSPex.LLM.Client.generate(client, question) do
            {:ok, response} ->
              IO.puts("A: #{response.content}")
              
            {:error, reason} ->
              IO.puts("Error: #{inspect(reason)}")
          end
        end)
        
      {:error, :missing_api_key} ->
        IO.puts("Error: Please set GEMINI_API_KEY environment variable")
        IO.puts("You can get an API key from: https://makersuite.google.com/app/apikey")
        
      {:error, reason} ->
        IO.puts("Failed to create client: #{inspect(reason)}")
    end
  end
end

# Run the example
SimpleQAWithInstructorLite.run()
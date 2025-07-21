#!/usr/bin/env elixir

# Question-Answer example using Gemini adapter (gemini_ex) with Gemini Flash 2.0

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)}
])

defmodule QAWithGeminiEx do
  @moduledoc """
  Example of using DSPex with native Gemini adapter (gemini_ex) for question-answering
  using Google's Gemini Flash 2.0 model.
  
  This adapter provides direct access to Gemini features including streaming.
  """

  def run do
    IO.puts("\n=== Question-Answer Example with Gemini Adapter ===\n")
    
    # Load config
    config_path = Path.join(__DIR__, "config.exs")
    config_data = Code.eval_file(config_path) |> elem(0)
    
    # Configure the LLM client
    config = [
      adapter: :gemini,
      provider: :gemini,
      api_key: config_data.api_key,
      model: config_data.model
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
        
        # Basic Q&A
        IO.puts("--- Basic Question-Answer ---\n")
        
        Enum.each(questions, fn question ->
          IO.puts("\nQ: #{question}")
          
          case DSPex.LLM.Client.generate(client, question) do
            {:ok, response} ->
              IO.puts("A: #{response.content}")
              
            {:error, reason} ->
              IO.puts("Error: #{inspect(reason)}")
          end
        end)
        
        # Streaming example
        IO.puts("\n\n--- Streaming Example ---\n")
        
        streaming_prompt = "Write a short story about a robot learning to paint (3 paragraphs)"
        IO.puts("Q: #{streaming_prompt}")
        IO.write("A: ")
        
        # Define callbacks for streaming
        on_chunk = fn chunk ->
          # Extract text from chunk
          text = case chunk do
            %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]} ->
              text
            _ ->
              ""
          end
          IO.write(text)
        end
        
        on_complete = fn ->
          IO.puts("\n\n[Streaming completed]")
        end
        
        case DSPex.LLM.Client.stream(client, streaming_prompt, [
          on_chunk: on_chunk,
          on_complete: on_complete
        ]) do
          {:ok, _} ->
            # Streaming completed
            :ok
          {:error, reason} ->
            IO.puts("\nStreaming error: #{inspect(reason)}")
        end
        
        # Example with different parameters
        IO.puts("\n\n--- Creative Writing with Parameters ---\n")
        
        creative_prompt = "Write a haiku about artificial intelligence"
        IO.puts("Q: #{creative_prompt}")
        
        case DSPex.LLM.Client.generate(client, creative_prompt, [
          temperature: 0.9,
          max_tokens: 100
        ]) do
          {:ok, response} ->
            IO.puts("A: #{response.content}")
            IO.puts("\nMetadata: #{inspect(response.metadata)}")
            
          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}")
        end
        
        # Batch processing example
        IO.puts("\n\n--- Batch Processing Example ---\n")
        
        batch_questions = [
          "What is 25 * 4?",
          "Name three primary colors",
          "What is the chemical formula for water?"
        ]
        
        IO.puts("Processing #{length(batch_questions)} questions in batch...\n")
        
        case DSPex.LLM.Client.batch(client, batch_questions) do
          {:ok, responses} ->
            Enum.zip(batch_questions, responses)
            |> Enum.each(fn {question, response} ->
              IO.puts("Q: #{question}")
              IO.puts("A: #{response.content}\n")
            end)
            
          {:error, reason} ->
            IO.puts("Batch error: #{inspect(reason)}")
        end
        
      {:error, :missing_api_key} ->
        IO.puts("Error: Please set GEMINI_API_KEY environment variable")
        IO.puts("You can get an API key from: https://makersuite.google.com/app/apikey")
        
      {:error, reason} ->
        IO.puts("Failed to create client: #{inspect(reason)}")
    end
  end
end

# Run the example
QAWithGeminiEx.run()